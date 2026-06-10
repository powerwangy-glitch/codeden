import Foundation
import SwiftUI
import AppKit
import Combine
import ServiceManagement

/// 全局状态：维护会话字典 + 额度，消费事件驱动状态机。
@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var sessions: [Session] = []
    @Published var quotas: [AgentQuota] = []
    @Published var expanded: Bool = false
    /// 由弹簧驱动的当前刘海尺寸（含过冲），SwiftUI 背景读它来一起回弹。
    @Published var islandSize: CGSize = CGSize(width: 280, height: 34)
    /// 物理刘海几何（由 NotchController 注入），UI 据此把内容放到刘海两侧。
    @Published var notch: NotchMetrics = .none

    // MARK: - 持久化偏好（UserDefaults）
    private static let d = UserDefaults.standard
    @Published var soundEnabled: Bool = (d.object(forKey: "soundEnabled") as? Bool) ?? true {
        didSet { Self.d.set(soundEnabled, forKey: "soundEnabled") }
    }
    @Published var showQuota: Bool = (d.object(forKey: "showQuota") as? Bool) ?? true {
        didSet { Self.d.set(showQuota, forKey: "showQuota") }
    }
    @Published var autoExpandOnWaiting: Bool = (d.object(forKey: "autoExpandOnWaiting") as? Bool) ?? true {
        didSet { Self.d.set(autoExpandOnWaiting, forKey: "autoExpandOnWaiting") }
    }
    /// 夜间静音时段（小时制，跨午夜支持，如 23→8）
    @Published var quietHoursEnabled: Bool = (d.object(forKey: "quietHoursEnabled") as? Bool) ?? false {
        didSet { Self.d.set(quietHoursEnabled, forKey: "quietHoursEnabled") }
    }
    @Published var quietStart: Int = (d.object(forKey: "quietStart") as? Int) ?? 23 {
        didSet { Self.d.set(quietStart, forKey: "quietStart") }
    }
    @Published var quietEnd: Int = (d.object(forKey: "quietEnd") as? Int) ?? 8 {
        didSet { Self.d.set(quietEnd, forKey: "quietEnd") }
    }
    /// 展开面板宽度 / 悬停展开延迟
    @Published var panelWidth: Double = (d.object(forKey: "panelWidth") as? Double) ?? 440 {
        didSet { Self.d.set(panelWidth, forKey: "panelWidth") }
    }
    @Published var hoverDelay: Double = (d.object(forKey: "hoverDelay") as? Double) ?? 0 {
        didSet { Self.d.set(hoverDelay, forKey: "hoverDelay") }
    }
    /// 额度显示：auto=跟随最近活跃 agent；或固定 claude/codex
    @Published var quotaProvider: String = (d.object(forKey: "quotaProvider") as? String) ?? "auto" {
        didSet { Self.d.set(quotaProvider, forKey: "quotaProvider") }
    }
    private(set) var lastActiveAgent: AgentKind = .claude

    /// 顶栏实际展示的额度：跟随/固定 + 危险插队
    var displayQuotas: [AgentQuota] {
        guard !quotas.isEmpty else { return [] }
        var picked: [AgentQuota]
        if quotaProvider != "auto", let fixed = quotas.first(where: { $0.agent.rawValue == quotaProvider }) {
            picked = [fixed]
        } else {
            let active = quotas.first(where: { $0.agent == lastActiveAgent }) ?? quotas[0]
            picked = [active]
        }
        // 危险插队：其他 agent 额度 ≥90% 必须露出
        for q in quotas where q.danger && !picked.contains(where: { $0.agent == q.agent }) {
            picked.append(q)
        }
        return picked
    }

    /// 点击额度区：auto → claude → codex → auto 循环
    func cycleQuotaProvider() {
        let order = ["auto", "claude", "codex"]
        let i = order.firstIndex(of: quotaProvider) ?? 0
        quotaProvider = order[(i + 1) % order.count]
        play(.select)
    }

    /// 会话过滤：被屏蔽的目录片段（持久）+ 本次隐藏的会话（临时）
    @Published var blockedDirs: [String] = (d.object(forKey: "blockedDirs") as? [String]) ?? [] {
        didSet { Self.d.set(blockedDirs, forKey: "blockedDirs"); commit() }
    }
    private var hiddenSessionIDs: Set<String> = []

    /// 当前是否处于静音时段
    var inQuietHours: Bool {
        guard quietHoursEnabled else { return false }
        let h = Calendar.current.component(.hour, from: Date())
        return quietStart <= quietEnd ? (h >= quietStart && h < quietEnd)
                                      : (h >= quietStart || h < quietEnd)   // 跨午夜
    }
    /// 统一出声入口：总开关 + 静音时段
    func play(_ cue: Chiptune.Cue) {
        Chiptune.shared.play(cue, enabled: soundEnabled && !inQuietHours)
    }
    @Published var launchAtLogin: Bool = (SMAppService.mainApp.status == .enabled) {
        didSet { applyLoginItem() }
    }
    /// 由 AppDelegate 注入：打开设置 / 引导窗口。
    var openSettings: () -> Void = {}
    var openOnboarding: () -> Void = {}

    /// 养成系统：怪兽经验/等级/进化。
    let buddies = BuddyStore()

    private func applyLoginItem() {
        do {
            if launchAtLogin {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            NSLog("登录项设置失败：\(error.localizedDescription)")
        }
    }

    /// 收起态聚合状态（穷举）。
    enum PillState { case rest, running, waiting, done }
    var pillState: PillState {
        if sessions.contains(where: { $0.state == .waiting }) { return .waiting }
        if sessions.contains(where: { $0.state.isBusy }) { return .running }
        if sessions.contains(where: { $0.state == .done }) { return .done }
        return .rest
    }
    var runningCount: Int { sessions.filter { $0.state.isBusy }.count }
    var waitingCount: Int { sessions.filter { $0.state == .waiting }.count }
    var doneCount: Int { sessions.filter { $0.state == .done }.count }
    var anyQuotaDanger: Bool { quotas.contains { $0.danger } }
    var liveSessions: [Session] { sessions.filter { $0.state == .waiting || $0.state.isBusy } }
    var recentDoneSessions: [Session] { sessions.filter { $0.state == .done } }
    var recentIdleSessions: [Session] { sessions.filter { $0.state == .idle } }

    private var byID: [String: Session] = [:]
    private var pruneTimers: [String: Timer] = [:]
    private let onChange: () -> Void
    private let home = FileManager.default.homeDirectoryForCurrentUser
    private var suppressBuddyXP = false      // 演示数据不计经验
    private let demoSessionIDs: Set<String> = ["demo-1", "demo-2"]

    /// onChange 在状态变化后调用（用于刘海窗口尺寸/动画刷新与声音）。
    init(onChange: @escaping () -> Void = {}) {
        self.onChange = onChange
        // 心跳：刷新「Xm 前」时间标签；清理 30 分钟无活动的空闲会话
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        let stale = byID.values.filter { $0.state == .idle && Date().timeIntervalSince($0.lastUpdate) > 1800 }
        for s in stale { remove(s.id) }
        commit()          // 重发 sessions → elapsedLabel 重算
        if !stale.isEmpty { onChange() }
    }

    // MARK: - 事件消费（状态机核心）

    func ingest(_ e: IngestEvent) {
        if !demoSessionIDs.contains(e.session) {
            clearDemoSessions()
        }
        let agent = AgentKind.from(e.agent)
        var s = byID[e.session] ?? Session(
            id: e.session, agent: agent,
            project: e.project ?? "—", task: "",
            state: .running, user: "", line: .init(tool: nil, text: ""),
            badges: [], lastUpdate: Date(), subagents: 0
        )
        s.agent = agent
        if agent != .unknown { lastActiveAgent = agent }
        if let p = e.project { s.project = p }
        if let sub = e.subagents { s.subagents = max(0, sub) }
        if let t = e.term, !t.isEmpty { s.terminal = t }
        if let b = e.term_bundle, !b.isEmpty { s.bundleID = b }
        if let tty = e.term_tty, !tty.isEmpty { s.tty = tty }
        if let c = e.cwd, !c.isEmpty { s.cwd = c }
        if let meta = claudeDesktopMeta(for: e.session) {
            if s.cwd.isEmpty { s.cwd = meta.cwd }
            if s.project == "—" || s.project.isEmpty {
                let project = URL(fileURLWithPath: meta.cwd).lastPathComponent
                s.project = project.isEmpty ? "Claude" : project
            }
            if !meta.title.isEmpty, s.task.isEmpty {
                s.task = String(meta.title.prefix(36))
            }
        }
        if let meta = codexDesktopMeta(for: e.session) {
            if s.cwd.isEmpty { s.cwd = meta.cwd }
            if s.project == "—" || s.project == "/" || s.project.isEmpty {
                let project = URL(fileURLWithPath: meta.cwd).lastPathComponent
                s.project = project.isEmpty ? "Codex" : project
            }
            let title = cleanedCodexTitle(meta.title, fallback: meta.preview)
            if !title.isEmpty, s.task.isEmpty || s.task == "Codex" {
                s.task = String(title.prefix(36))
            }
            if (s.user.isEmpty || s.user == "Codex"), !meta.preview.isEmpty {
                s.user = meta.preview
            }
        }
        if s.task.isEmpty, let u = e.user, !u.isEmpty, u.lowercased() != agent.displayName.lowercased() {
            let firstLine = u.split(separator: "\n").first.map(String.init) ?? u
            s.task = String(firstLine.prefix(36))
        }
        s.lastUpdate = Date()

        let prev = s.state
        switch e.event {
        case "UserPromptSubmit":
            s.state = .running
            if let u = e.user, !u.isEmpty {
                s.user = u
                // 会话标题 = 首条 prompt 摘要（避免「项目 · 项目」重复）
                if s.task.isEmpty {
                    let firstLine = u.split(separator: "\n").first.map(String.init) ?? u
                    s.task = String(firstLine.prefix(24))
                }
            }
            s.line = .init(tool: nil, text: "思考中…")

        case "PreToolUse":
            s.requestID = nil
            if e.tool == "AskUserQuestion", let qs = e.questions, !qs.isEmpty {
                // Claude 在终端里等你答题 → 刘海展示答题向导
                s.state = .waiting
                s.questions = qs
                s.questionIndex = 0
                s.line = .init(tool: nil, text: "Claude 的提问（\(qs.count) 个问题）")
            } else {
                s.state = .running
                s.questions = nil
                s.line = .init(tool: e.tool, text: e.tool_summary ?? "")
            }

        case "PostToolUse":
            s.state = .running
            s.requestID = nil
            s.questions = nil
            s.plan = nil
            if !suppressBuddyXP { buddies.record(agent, .tool) }
            if let t = e.tool { s.line = .init(tool: t, text: e.tool_summary ?? "完成") }

        case "PermissionRequest":
            s.state = .waiting
            s.requestID = e.request_id          // 非空 → 可在刘海点 允许/拒绝 回写
            if e.tool == "ExitPlanMode", let p = e.plan, !p.isEmpty {
                s.plan = p                       // 计划模式：刘海里读计划直接批
                s.line = .init(tool: nil, text: "计划待审批")
            } else {
                s.line = .init(tool: e.tool, text: "请求权限 · " + (e.tool_summary ?? ""))
            }

        case "Notification":
            // 权限请求 or 空闲等待，靠文本判断
            let msg = (e.message ?? "").lowercased()
            let waitWords = ["permission", "approve", "waiting for your", "needs your",
                             "权限", "批准", "审批", "等待你", "等待您", "需要你", "需要您"]
            s.state = waitWords.contains(where: { msg.contains($0) }) ? .waiting : .idle
            if let m = e.message { s.line = .init(tool: nil, text: m) }

        case "Stop":
            s.state = .done
            s.requestID = nil
            s.questions = nil
            s.plan = nil
            if !suppressBuddyXP { buddies.record(agent, .completion) }
            if let a = e.assistant, !a.isEmpty { s.line = .init(tool: nil, text: a) }
            schedulePrune(e.session)

        case "SubagentStop":
            s.state = .running
            s.subagents = max(0, s.subagents - 1)

        case "SubagentStart":
            s.state = .running
            s.subagents += 1

        case "PreCompact":
            s.state = .compacting
            s.line = .init(tool: nil, text: "压缩上下文…")

        case "SessionStart":
            s.state = .idle

        case "SessionEnd":
            remove(e.session)
            commit()
            return

        default:
            break
        }

        // 用 user/assistant 字段补全（任何事件都可能带）
        if let u = e.user, !u.isEmpty { s.user = u }

        byID[e.session] = s
        commit()

        // 声音：状态跃迁时触发
        if prev != s.state {
            switch s.state {
            case .waiting:
                play(.alert)
                if autoExpandOnWaiting { expanded = true }
            case .done:
                play(.done)
                popupBriefly()
            default: break
            }
        }
        onChange()
    }

    // MARK: - 答题（AskUserQuestion 快捷回复，实验性）

    /// 选第 idx 个选项：唤起对应终端 → 键入数字 → 回车。需要「辅助功能」权限。
    func answer(_ session: Session, option idx: Int) {
        guard let qs = session.questions, var s = byID[session.id] else { return }
        guard let bid = session.bundleID, !bid.isEmpty else {
            s.line = .init(tool: nil, text: "无法定位终端，请回终端回答")
            byID[session.id] = s
            commit()
            onChange()
            return
        }
        guard AXIsProcessTrusted() else {
            s.line = .init(tool: nil, text: "需要开启辅助功能权限，或回终端回答")
            byID[session.id] = s
            commit()
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
            onChange()
            return
        }
        jump(session)   // 先把终端唤到前台
        let digit = "\(idx + 1)"
        let script = """
        delay 0.4
        tell application "System Events"
            keystroke "\(digit)"
            delay 0.15
            key code 36
        end tell
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        try? p.run()

        // 推进向导：还有下一题就停在 waiting，答完转 running
        if s.questionIndex + 1 < qs.count {
            s.questionIndex += 1
        } else {
            s.questions = nil
            s.questionIndex = 0
            s.state = .running
            s.line = .init(tool: nil, text: "已提交回答")
        }
        byID[session.id] = s
        commit()
        play(.select)
        onChange()
    }

    // MARK: - 会话过滤

    func hideSession(_ s: Session) { hiddenSessionIDs.insert(s.id); commit(); onChange() }
    func blockDir(_ s: Session) {
        guard !s.cwd.isEmpty, !blockedDirs.contains(s.cwd) else { return }
        blockedDirs.append(s.cwd)   // didSet 自动 commit
        onChange()
    }
    func clearBlockedDirs() { blockedDirs = [] }

    // MARK: - 跳转：把会话所在终端唤到前台

    func jump(_ session: Session) {
        if session.agent == .codex, openCodexThread(session) {
            play(.select)
            return
        }
        if session.agent == .claude, openClaudeDesktopSession(session) {
            play(.select)
            return
        }
        if let tty = session.tty, jumpToTerminalTTY(session, tty: tty) {
            play(.select)
            return
        }
        guard let bid = session.bundleID, !bid.isEmpty else { return }
        openBundle(bid)
        play(.select)
    }

    private func openCodexThread(_ session: Session) -> Bool {
        guard session.id.hasPrefix("codex-"),
              let url = URL(string: "codex://threads/\(String(session.id.dropFirst(6)))") else {
            return false
        }
        NSWorkspace.shared.open(url)
        return true
    }

    private func openClaudeDesktopSession(_ session: Session) -> Bool {
        let desktopBundleID = "com.anthropic.claudefordesktop"
        guard session.bundleID == desktopBundleID || NSWorkspace.shared.urlForApplication(withBundleIdentifier: desktopBundleID) != nil else {
            return false
        }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        guard session.id.rangeOfCharacter(from: allowed.inverted) == nil,
              let url = URL(string: "claude://claude.ai/resume?session=\(session.id)") else {
            return false
        }
        NSWorkspace.shared.open(url)
        return true
    }

    private func claudeDesktopMeta(for cliSessionID: String) -> (title: String, cwd: String)? {
        guard cliSessionID.rangeOfCharacter(from: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-").inverted) == nil else {
            return nil
        }
        let base = home.appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")
        guard let enumerator = FileManager.default.enumerator(
            at: base,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for case let url as URL in enumerator {
            guard url.lastPathComponent.hasPrefix("local_"), url.pathExtension == "json" else { continue }
            guard let data = try? Data(contentsOf: url),
                  let meta = try? JSONDecoder().decode(ClaudeDesktopSessionMeta.self, from: data),
                  meta.cliSessionId == cliSessionID else { continue }
            return (meta.title ?? "", meta.cwd)
        }
        return nil
    }

    private struct ClaudeDesktopSessionMeta: Decodable {
        var cliSessionId: String?
        var cwd: String
        var title: String?
    }

    private func codexDesktopMeta(for sessionID: String) -> (title: String, cwd: String, preview: String)? {
        guard sessionID.hasPrefix("codex-") else { return nil }
        let threadID = String(sessionID.dropFirst(6))
        guard threadID.rangeOfCharacter(from: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-").inverted) == nil else {
            return nil
        }
        let db = home.appendingPathComponent(".codex/state_5.sqlite").path
        guard FileManager.default.fileExists(atPath: db) else { return nil }
        let query = """
        select coalesce(title,'') as title, coalesce(cwd,'') as cwd, substr(coalesce(preview,''), 1, 220) as preview
        from threads where id = '\(threadID)' limit 1;
        """
        guard let meta = decodeCodexMeta(runSQLite(db, query, json: true)) else { return nil }
        return (meta.title, meta.cwd, meta.preview)
    }

    private func decodeCodexMeta(_ json: String) -> CodexThreadMeta? {
        guard let data = json.data(using: .utf8),
              let rows = try? JSONDecoder().decode([CodexThreadMeta].self, from: data) else { return nil }
        return rows.first
    }

    private struct CodexThreadMeta: Decodable {
        var title: String
        var cwd: String
        var preview: String
    }

    private func cleanedCodexTitle(_ title: String, fallback: String) -> String {
        for source in [title, fallback] {
            for rawLine in source.split(separator: "\n") {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                if line.isEmpty || line.hasPrefix("http://") || line.hasPrefix("https://") { continue }
                return line
            }
        }
        return ""
    }

    private func jumpToTerminalTTY(_ session: Session, tty: String) -> Bool {
        guard let bid = session.bundleID, !bid.isEmpty else { return false }
        switch bid {
        case "com.googlecode.iterm2", "com.googlecode.iterm2.preview":
            return runAppleScript(iTermJumpScript(tty))
        case "com.apple.Terminal":
            return runAppleScript(terminalJumpScript(tty))
        default:
            openBundle(bid)
            return false
        }
    }

    private func openBundle(_ bid: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-b", bid]
        try? p.run()
    }

    private func runAppleScript(_ script: String) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func runSQLite(_ db: String, _ query: String, json: Bool = false) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = json ? ["-json", db, query] : [db, query]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func terminalJumpScript(_ tty: String) -> String {
        let escaped = tty.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return """
        tell application id "com.apple.Terminal"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(escaped)" then
                        set selected tab of w to t
                        set index of w to 1
                        return
                    end if
                end repeat
            end repeat
        end tell
        """
    }

    private func iTermJumpScript(_ tty: String) -> String {
        let escaped = tty.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return """
        tell application id "com.googlecode.iterm2"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(escaped)" then
                            select w
                            select t
                            select s
                            return
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        """
    }

    // MARK: - 审批回写

    /// 用户在刘海点「允许/拒绝」：写决定文件，bridge 轮询到后回传给 Claude。
    func decide(_ session: Session, allow: Bool) {
        guard let rid = session.requestID else { return }
        let dir = home.appendingPathComponent(".notch-island/decisions")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(rid).json")
        let payload: [String: String] = ["behavior": allow ? "allow" : "deny"]
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            try? data.write(to: url)
        }
        if var s = byID[session.id] {
            s.requestID = nil
            s.plan = nil
            s.state = allow ? .running : .idle
            s.line = .init(tool: nil, text: allow ? "已允许 ✓" : "已拒绝")
            s.lastUpdate = Date()
            if allow { buddies.record(session.agent, .approval) }
            byID[session.id] = s
            commit()
        }
        play(allow ? .select : .deny)
        onChange()
    }

    /// 完成提醒：自动展开 4 秒后收起（期间出现待审批则保持展开）
    private var popupWork: DispatchWorkItem?
    private func popupBriefly() {
        guard !expanded else { return }
        expanded = true
        popupWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.pillState != .waiting { self.expanded = false }
        }
        popupWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: w)
    }

    private func schedulePrune(_ id: String) {
        pruneTimers[id]?.invalidate()
        // 完成 20s 后转为 idle（仍保留在列表，避免闪烁）
        pruneTimers[id] = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, var s = self.byID[id] else { return }
                if s.state == .done { s.state = .idle; self.byID[id] = s; self.commit(); self.onChange() }
            }
        }
    }

    private func remove(_ id: String) {
        byID[id] = nil
        pruneTimers[id]?.invalidate(); pruneTimers[id] = nil
    }

    /// 排序：waiting > running > done > idle，再按最近更新。
    private func commit() {
        let activeCutoff = Date().addingTimeInterval(-20 * 60)
        func rank(_ st: SessionState) -> Int {
            switch st { case .waiting: return 0; case .running: return 1; case .compacting: return 1
                        case .done: return 2; case .idle: return 3 }
        }
        sessions = byID.values
            .filter { s in !hiddenSessionIDs.contains(s.id)
                && !blockedDirs.contains(where: { !$0.isEmpty && s.cwd.contains($0) })
                && (s.state != .idle || s.lastUpdate >= activeCutoff) }
            .sorted {
            rank($0.state) != rank($1.state) ? rank($0.state) < rank($1.state)
                                             : $0.lastUpdate > $1.lastUpdate
        }.prefix(6).map { $0 }
    }

    private func clearDemoSessions() {
        guard demoSessionIDs.contains(where: { byID[$0] != nil }) else { return }
        for id in demoSessionIDs { remove(id) }
    }

    // MARK: - 演示数据（无事件时也能看到界面）

    func loadDemo() {
        let demo: [IngestEvent] = [
            .init(session: "demo-1", agent: "claude", project: "交易", event: "PreToolUse",
                  tool: "Bash", tool_summary: "open \"/Users/mac/交易/…/index.html\"",
                  user: "这个排版就可以复刻", subagents: 2),
            .init(session: "demo-2", agent: "codex", project: "Claude", event: "Stop",
                  user: "可以 去吧", assistant: "我看完了，结论很明确…")
        ]
        suppressBuddyXP = true
        demo.forEach { ingest($0) }
        suppressBuddyXP = false
        if var s = byID["demo-1"] { s.badges = [.init(text: "自动批准", kind: .auto)]; s.task = "Mac notch and Vibecoding tool"; byID["demo-1"] = s }
        if var s = byID["demo-2"] { s.task = "复刻完整软件"; byID["demo-2"] = s }
        commit()
    }
}
