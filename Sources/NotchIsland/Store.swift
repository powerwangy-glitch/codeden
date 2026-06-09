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
        if sessions.contains(where: { $0.state == .running }) { return .running }
        if sessions.contains(where: { $0.state == .done }) { return .done }
        return .rest
    }
    var runningCount: Int { sessions.filter { $0.state == .running }.count }
    var anyQuotaDanger: Bool { quotas.contains { $0.danger } }

    private var byID: [String: Session] = [:]
    private var pruneTimers: [String: Timer] = [:]
    private let onChange: () -> Void
    private let home = FileManager.default.homeDirectoryForCurrentUser
    private var suppressBuddyXP = false      // 演示数据不计经验

    /// onChange 在状态变化后调用（用于刘海窗口尺寸/动画刷新与声音）。
    init(onChange: @escaping () -> Void = {}) {
        self.onChange = onChange
    }

    // MARK: - 事件消费（状态机核心）

    func ingest(_ e: IngestEvent) {
        let agent = AgentKind.from(e.agent)
        var s = byID[e.session] ?? Session(
            id: e.session, agent: agent,
            project: e.project ?? "—", task: e.project ?? "会话",
            state: .running, user: "", line: .init(tool: nil, text: ""),
            badges: [], lastUpdate: Date(), subagents: 0
        )
        s.agent = agent
        if let p = e.project { s.project = p }
        if let sub = e.subagents { s.subagents = max(0, sub) }
        if let t = e.term, !t.isEmpty { s.terminal = t }
        if let b = e.term_bundle, !b.isEmpty { s.bundleID = b }
        s.lastUpdate = Date()

        let prev = s.state
        switch e.event {
        case "UserPromptSubmit":
            s.state = .running
            if let u = e.user, !u.isEmpty { s.user = u }
            s.line = .init(tool: nil, text: "思考中…")

        case "PreToolUse":
            s.state = .running
            s.requestID = nil
            s.line = .init(tool: e.tool, text: e.tool_summary ?? "")

        case "PostToolUse":
            s.state = .running
            s.requestID = nil
            if !suppressBuddyXP { buddies.record(agent, .tool) }
            if let t = e.tool { s.line = .init(tool: t, text: e.tool_summary ?? "完成") }

        case "PermissionRequest":
            s.state = .waiting
            s.requestID = e.request_id          // 非空 → 可在刘海点 允许/拒绝 回写
            s.line = .init(tool: e.tool, text: "请求权限 · " + (e.tool_summary ?? ""))

        case "Notification":
            // 权限请求 or 空闲等待，靠文本判断
            let msg = (e.message ?? "").lowercased()
            if msg.contains("permission") || msg.contains("approve") || msg.contains("waiting for your") {
                s.state = .waiting
            } else {
                s.state = .idle
            }
            if let m = e.message { s.line = .init(tool: nil, text: m) }

        case "Stop":
            s.state = .done
            s.requestID = nil
            if !suppressBuddyXP { buddies.record(agent, .completion) }
            if let a = e.assistant, !a.isEmpty { s.line = .init(tool: nil, text: a) }
            schedulePrune(e.session)

        case "SubagentStop":
            s.state = .running
            s.subagents = max(0, s.subagents - 1)

        case "SubagentStart":
            s.state = .running
            s.subagents += 1

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
        if s.task == "会话" || s.task.isEmpty { s.task = s.project }

        byID[e.session] = s
        commit()

        // 声音：状态跃迁时触发
        if prev != s.state {
            switch s.state {
            case .waiting:
                Chiptune.shared.play(.alert, enabled: soundEnabled)
                if autoExpandOnWaiting { expanded = true }
            case .done:    Chiptune.shared.play(.done, enabled: soundEnabled)
            default: break
            }
        }
        onChange()
    }

    // MARK: - 跳转：把会话所在终端唤到前台

    func jump(_ session: Session) {
        guard let bid = session.bundleID, !bid.isEmpty else { return }
        // open -b 最可靠：无论目标 App 是否在跑都会唤到前台（后台 agent 调 activate 常失效）
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-b", bid]
        try? p.run()
        Chiptune.shared.play(.select, enabled: soundEnabled)
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
            s.state = allow ? .running : .idle
            s.line = .init(tool: nil, text: allow ? "已允许 ✓" : "已拒绝")
            s.lastUpdate = Date()
            if allow { buddies.record(session.agent, .approval) }
            byID[session.id] = s
            commit()
        }
        Chiptune.shared.play(allow ? .select : .deny, enabled: soundEnabled)
        onChange()
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
        func rank(_ st: SessionState) -> Int {
            switch st { case .waiting: return 0; case .running: return 1; case .done: return 2; case .idle: return 3 }
        }
        sessions = byID.values.sorted {
            rank($0.state) != rank($1.state) ? rank($0.state) < rank($1.state)
                                             : $0.lastUpdate > $1.lastUpdate
        }
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
