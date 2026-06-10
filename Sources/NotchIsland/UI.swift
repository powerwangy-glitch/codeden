import SwiftUI

// MARK: - 颜色

extension Color {
    static let niText  = Color(white: 0.95)
    static let niText2 = Color(white: 0.66)
    static let niText3 = Color(white: 0.42)
    static let niHair  = Color.white.opacity(0.07)
    static let niBG    = Color(red: 0x05/255, green: 0x05/255, blue: 0x06/255)
    static let niTool  = Color(red: 0x7A/255, green: 0xA2/255, blue: 1.0)
    static let niDone  = Color(red: 0x5F/255, green: 0xD4/255, blue: 0x7F/255)
    static let niWarn  = Color(red: 1.0, green: 0xB3/255, blue: 0x40/255)
    static let niDel   = Color(red: 1.0, green: 0x7A/255, blue: 0x72/255)
}

struct ToolGlyph {
    let symbol: String
    let color: Color
    let label: String

    static func from(_ raw: String?) -> ToolGlyph? {
        guard let raw, !raw.isEmpty else { return nil }
        let key = raw.lowercased()
        if key.contains("bash") { return .init(symbol: "terminal.fill", color: .niWarn, label: raw) }
        if key.contains("read") { return .init(symbol: "doc.text.magnifyingglass", color: Color(red: 0x7A/255, green: 0xA2/255, blue: 1), label: raw) }
        if key.contains("edit") || key.contains("write") || key.contains("notebookedit") {
            return .init(symbol: "square.and.pencil", color: Color(red: 0x5F/255, green: 0xD4/255, blue: 0x7F/255), label: raw)
        }
        if key.contains("grep") || key.contains("glob") || key.contains("search") {
            return .init(symbol: "magnifyingglass", color: Color(red: 0x8E/255, green: 0xD8/255, blue: 1), label: raw)
        }
        if key.contains("web") || key.contains("fetch") {
            return .init(symbol: "globe", color: Color(red: 0x8B/255, green: 0xC7/255, blue: 1), label: raw)
        }
        if key.contains("task") {
            return .init(symbol: "sparkles", color: Color(red: 0xC0/255, green: 0x8B/255, blue: 1), label: raw)
        }
        if key.contains("todo") {
            return .init(symbol: "checklist", color: Color(red: 0x7E/255, green: 0xE7/255, blue: 0x87/255), label: raw)
        }
        if key.contains("exitplan") || key.contains("plan") {
            return .init(symbol: "map.fill", color: .niWarn, label: raw)
        }
        if key.contains("ask") || key.contains("question") {
            return .init(symbol: "questionmark.bubble.fill", color: .niWarn, label: raw)
        }
        return .init(symbol: "wrench.and.screwdriver.fill", color: .niTool, label: raw)
    }
}

// MARK: - 可见岛体：背景尺寸由弹簧 islandSize 驱动 → 果冻回弹

struct IslandView: View {
    @ObservedObject var store: AppStore
    @State private var hoverWork: DispatchWorkItem?

    var body: some View {
        ZStack(alignment: .top) {
            // 背景黑岛体跟随弹簧尺寸拉伸/回弹（果冻感的主体）
            RoundedCorners(radius: store.expanded ? 22 : 18)
                .fill(store.expanded ? Color.niBG : Color.black)
                .frame(width: store.islandSize.width, height: store.islandSize.height)
            // 内容自然尺寸、顶部对齐；过冲时露出的空隙由背景填充
            ContentOnly(store: store)
                .frame(width: store.islandSize.width, alignment: .center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: store.islandSize.width, height: store.islandSize.height, alignment: .top)
        .clipShape(RoundedCorners(radius: store.expanded ? 22 : 18))
        .contentShape(Rectangle())
        .onHover { inside in
            hoverWork?.cancel()
            if inside {
                if store.hoverDelay <= 0.01 { store.expanded = true }
                else {
                    let w = DispatchWorkItem { store.expanded = true }
                    hoverWork = w
                    DispatchQueue.main.asyncAfter(deadline: .now() + store.hoverDelay, execute: w)
                }
            } else if !store.sessions.contains(where: { $0.state == .waiting }) {
                store.expanded = false
            }
        }
        .onTapGesture {
            // 收起态点击：先展开控制中心；具体跳转交给卡片点击。
            guard !store.expanded else { return }
            store.expanded = true
        }
        .contextMenu {
            Button("设置…") { store.openSettings() }
            Button("重看新人引导") { store.openOnboarding() }
            Divider()
            Button("退出 码岛") { NSApp.terminate(nil) }
        }
    }
}

/// 纯内容（无背景、无固定外框），既用于显示也用于离屏测量目标尺寸。
struct ContentOnly: View {
    @ObservedObject var store: AppStore
    var body: some View {
        if store.expanded { PanelView(store: store) }
        else { PillView(store: store) }
    }
}

/// 只圆下面两个角（贴住屏幕顶边）。
struct RoundedCorners: Shape {
    var radius: CGFloat
    func path(in rect: CGRect) -> Path {
        let r = radius
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.closeSubpath()
        return p
    }
}

// MARK: - 收起态药丸

struct PillView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        let n = store.notch
        if n.hasNotch {
            // 横跨刘海：左翼放精灵、右翼放状态，中间让出刘海宽度（内容全在刘海外）
            HStack(spacing: 0) {
                leftWing.frame(width: NotchLayout.wing, alignment: .trailing)
                    .padding(.trailing, 3)
                Color.clear.frame(width: n.width)
                rightWing.frame(width: NotchLayout.wing, alignment: .leading)
                    .padding(.leading, 3)
            }
            .frame(height: n.height)            // 与刘海等高，齐平不突出
        } else {
            // 无刘海（外接屏）：普通居中条
            HStack(spacing: 8) { leftWing; rightWing }
                .padding(.horizontal, 14)
                .frame(height: NotchLayout.fallbackHeight)
                .fixedSize()
        }
    }

    // 左翼：只放一个图标——首个会话的精灵（休息时灰睡）。多会话不堆叠，让数字说话。
    @ViewBuilder private var leftWing: some View {
        if let first = store.sessions.first {
            // 有会话就保持彩色（等待输入也只是「歇着」，不是死灰）
            SpriteView(agent: first.agent, size: 17, running: first.state.isBusy)
        } else {
            SpriteView(agent: .claude, size: 17, sleeping: true)
        }
    }

    // 右翼：一个字符表达一切——数字（在跑）/ ⚡（需要你）/ ✓（完成）/ z（休息）
    @ViewBuilder private var rightWing: some View {
        HStack(spacing: 4) {
            switch store.pillState {
            case .rest:
                Text("z").font(.system(size: 11, design: .monospaced)).foregroundColor(.niText3)
            case .waiting:
                Text("⚡").font(.system(size: 12)).foregroundColor(.niWarn)
            case .done:
                Text("✓").font(.system(size: 12).weight(.bold)).foregroundColor(.niDone)
            case .running:
                Text("\(store.runningCount)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(red: 0x5E/255, green: 0x9E/255, blue: 1.0))
            }
            if store.anyQuotaDanger {
                Text("▲").font(.system(size: 10)).foregroundColor(.niDel)
            }
        }
    }
}

// MARK: - 展开面板

struct PanelView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            // 顶部让出刘海高度，所有内容落在刘海下方（完整可见）
            if store.notch.hasNotch { Color.clear.frame(height: store.notch.height) }
            QuotaHeader(store: store)
            StatusStrip(store: store)
            if store.liveSessions.isEmpty {
                IdlePanel(store: store)
            } else {
                WorkPanel(store: store)
            }
            Color.clear.frame(height: 8)
        }
        .frame(width: CGFloat(store.panelWidth), alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct WorkPanel: View {
    @ObservedObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PanelSectionTitle(title: "正在工作", detail: "\(store.liveSessions.count) 个任务")
            ForEach(store.liveSessions) { s in
                ItemRow(session: s,
                        onDecide: { allow in store.decide(s, allow: allow) },
                        onJump: { store.jump(s) },
                        onHide: { store.hideSession(s) },
                        onBlockDir: { store.blockDir(s) },
                        onAnswer: { i in store.answer(s, option: i) })
            }
            if !store.recentDoneSessions.isEmpty {
                PanelSectionTitle(title: "刚完成", detail: nil)
                    .padding(.top, 4)
                ForEach(store.recentDoneSessions.prefix(2)) { s in
                    ItemRow(session: s,
                            compact: true,
                            onJump: { store.jump(s) },
                            onHide: { store.hideSession(s) },
                            onBlockDir: { store.blockDir(s) })
                }
            }
        }
        .padding(.horizontal, 8)
    }
}

struct IdlePanel: View {
    @ObservedObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                SpriteView(agent: store.lastActiveAgent, size: 30, sleeping: true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("现在没有 agent 在跑")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.niText)
                    Text(idleHint)
                        .font(.system(size: 11.5))
                        .foregroundColor(.niText3)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Button { store.openSettings() } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.niText2)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .help("设置")
            }
            .padding(14)
            .background(Color.white.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            if !store.recentDoneSessions.isEmpty {
                PanelSectionTitle(title: "最近完成", detail: nil)
                ForEach(store.recentDoneSessions.prefix(2)) { s in
                    ItemRow(session: s,
                            compact: true,
                            onJump: { store.jump(s) },
                            onHide: { store.hideSession(s) },
                            onBlockDir: { store.blockDir(s) })
                }
            } else if !store.recentIdleSessions.isEmpty {
                PanelSectionTitle(title: "最近会话", detail: nil)
                ForEach(store.recentIdleSessions.prefix(2)) { s in
                    ItemRow(session: s,
                            compact: true,
                            onJump: { store.jump(s) },
                            onHide: { store.hideSession(s) },
                            onBlockDir: { store.blockDir(s) })
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 2)
    }

    private var idleHint: String {
        if store.showQuota && !store.quotas.isEmpty { return "额度和最近会话还在这里，开跑后会自动切到任务视图。" }
        return "开一个 Claude Code 或 Codex 任务后，这里会自动切到任务视图。"
    }
}

struct PanelSectionTitle: View {
    let title: String
    let detail: String?

    var body: some View {
        HStack(spacing: 7) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.niText2)
            if let detail {
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundColor(.niText3)
            }
            Spacer()
        }
        .padding(.horizontal, 5)
    }
}

struct StatusStrip: View {
    @ObservedObject var store: AppStore

    var body: some View {
        HStack(spacing: 8) {
            statusPill("需要处理", store.waitingCount, .niWarn)
            statusPill("运行中", store.runningCount, .niTool)
            statusPill("刚完成", store.doneCount, .niDone)
            Spacer(minLength: 6)
            Text(statusText)
                .font(.system(size: 10.5))
                .foregroundColor(.niText3)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var statusText: String {
        if store.waitingCount > 0 { return "有操作等你决定" }
        if store.runningCount > 0 { return "agent 正在执行" }
        if store.doneCount > 0 { return "刚结束一轮任务" }
        return "都在休息"
    }

    private func statusPill(_ label: String, _ count: Int, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(count > 0 ? color : Color.niText3.opacity(0.55)).frame(width: 5, height: 5)
            Text(label)
            Text("\(count)").fontWeight(.semibold)
        }
        .font(.system(size: 10.5))
        .foregroundColor(count > 0 ? color : .niText3)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background((count > 0 ? color : Color.white).opacity(count > 0 ? 0.12 : 0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct QuotaHeader: View {
    @ObservedObject var store: AppStore
    var body: some View {
        HStack(spacing: 0) {
            leftGroupTappable
            Spacer(minLength: 10)
            rightGroup
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    // 点击额度区：自动 → 固定Claude → 固定Codex 循环
    @ViewBuilder private var leftGroupTappable: some View {
        leftGroup.contentShape(Rectangle()).onTapGesture { store.cycleQuotaProvider() }
            .help("点击切换额度显示：自动(跟随会话) / 固定 Claude / 固定 Codex")
    }

    @ViewBuilder private var leftGroup: some View {
        HStack(spacing: 12) {
            if store.showQuota {
                if store.quotas.isEmpty {
                    SpriteView(agent: .claude, size: 20)
                    Text("额度待采集 · 终端会话激活后显示").font(.system(size: 10.5)).foregroundColor(.niText3)
                } else {
                    let shown = store.displayQuotas
                    ForEach(shown.indices, id: \.self) { i in
                        let q = shown[i]
                        HStack(spacing: 6) {
                            SpriteView(agent: q.agent, size: 18)
                            quotaSeg(q.fiveHour)
                            Text("|").foregroundColor(.niText3).opacity(0.45)
                            quotaSeg(q.sevenDay)
                        }
                    }
                    if store.quotaProvider != "auto" {
                        Text("固定").font(.system(size: 9)).foregroundColor(.niText3)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.white.opacity(0.07))
                            .clipShape(Capsule())
                    }
                }
            } else {
                SpriteView(agent: .claude, size: 20)
            }
        }
    }

    @ViewBuilder private var rightGroup: some View {
        HStack(spacing: 14) {
            Text(store.soundEnabled ? "🔊" : "🔇").font(.system(size: 14)).foregroundColor(.niText3)
                .onTapGesture { store.soundEnabled.toggle() }
            Text("⚙").font(.system(size: 14)).foregroundColor(.niText3)
                .onTapGesture { store.openSettings() }
        }
    }

    @ViewBuilder private func quotaSeg(_ w: QuotaWindow) -> some View {
        let c: Color = w.usedPercent >= 90 ? .niDel : w.usedPercent >= 70 ? .niWarn : .niDone
        HStack(spacing: 4) {
            Text(w.label).font(.system(size: 12.5)).foregroundColor(.niText3)
            Text("\(w.usedPercent)%").font(.system(size: 12.5).weight(.semibold)).foregroundColor(c)
            Text(w.resetLabel).font(.system(size: 12.5)).foregroundColor(.niText3)
        }
    }
}

struct ItemRow: View {
    let session: Session
    var compact: Bool = false
    var onDecide: (Bool) -> Void = { _ in }
    var onJump: () -> Void = {}
    var onHide: () -> Void = {}
    var onBlockDir: () -> Void = {}
    var onAnswer: (Int) -> Void = { _ in }
    @State private var hovering = false
    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            // 左侧精灵簇（主 + 子 agent）
            HStack(spacing: 2) {
                ForEach(0...session.subagents, id: \.self) { _ in
                    SpriteView(agent: session.agent, size: 20, running: session.state.isBusy)
                }
            }
            .frame(width: 40, alignment: .leading)

            VStack(alignment: .leading, spacing: compact ? 4 : 7) {
                // 第一行：标题 + 标签 + 时间
                HStack(spacing: 8) {
                    Text(session.displayTitle)
                        .font(.system(size: compact ? 12.5 : 13.5).weight(.semibold)).foregroundColor(.niText)
                        .lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 6)
                    if !session.terminal.isEmpty {
                        Text(hovering ? "↩ \(session.terminal)" : session.terminal)
                            .font(.system(size: 10)).foregroundColor(hovering ? .niTool : .niText3)
                    }
                    ForEach(session.badges, id: \.self) { b in badge(b) }
                    agentBadge(session.agent)
                    Text(session.elapsedLabel).font(.system(size: 11)).foregroundColor(.niText3)
                }
                if !compact {
                    ProgressLine(session: session)
                }
                // 第二行：任务摘要
                if !session.displaySubtitle.isEmpty {
                    Text(session.displaySubtitle).font(.system(size: compact ? 11.2 : 12)).foregroundColor(.niText2)
                        .lineLimit(1).truncationMode(.tail)
                }
                // 第三行：当前动作 / 审批 / 提问
                if !compact { activity }
                // 计划审批（ExitPlanMode）：读计划 → 批准/驳回
                if !compact, let plan = session.plan, session.requestID != nil, session.state == .waiting {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("📋 计划").font(.system(size: 11).weight(.semibold)).foregroundColor(.niWarn)
                        ScrollView {
                            Text(plan).font(.system(size: 11.5)).foregroundColor(.niText2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 150)
                        .padding(8)
                        .background(Color.black.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        HStack(spacing: 18) {
                            Button { onDecide(true) } label: {
                                Text("批准计划，开始执行").font(.system(size: 12.5).weight(.semibold)).foregroundColor(.niDone)
                            }.buttonStyle(.plain)
                            Button { onDecide(false) } label: {
                                Text("驳回").font(.system(size: 12.5).weight(.semibold)).foregroundColor(.niText2)
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 6)
                }
                // 答题向导（AskUserQuestion）
                else if !compact, let qs = session.questions, session.state == .waiting, session.questionIndex < qs.count {
                    let q = qs[session.questionIndex]
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(qs.count > 1 ? "第 \(session.questionIndex + 1) / \(qs.count) 题" : "Claude 的提问")
                                .font(.system(size: 10.5)).foregroundColor(.niWarn)
                            if q.multiSelect == true {
                                Text("· 多选请在终端操作").font(.system(size: 10)).foregroundColor(.niText3)
                            } else if session.bundleID == nil {
                                Text("· 无法定位终端").font(.system(size: 10)).foregroundColor(.niText3)
                            }
                        }
                        Text(q.question).font(.system(size: 12.5)).foregroundColor(.niText)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(Array(q.options.enumerated()), id: \.offset) { i, opt in
                            Button { onAnswer(i) } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    Text("\(i + 1)").font(.system(size: 10).weight(.bold)).foregroundColor(.niText3)
                                        .frame(width: 16, height: 16)
                                        .background(Color.white.opacity(0.08))
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(opt.label).font(.system(size: 12)).foregroundColor(.niText2)
                                        if let d = opt.description, !d.isEmpty {
                                            Text(d).font(.system(size: 10.5)).foregroundColor(.niText3).lineLimit(2)
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(q.multiSelect == true || session.bundleID == nil)
                            .opacity(q.multiSelect == true || session.bundleID == nil ? 0.55 : 1)
                        }
                    }
                    .padding(.top, 6)
                }
                // 审批按钮（仅在等待你审批且可回写时出现）
                else if !compact, session.requestID != nil, session.state == .waiting {
                    HStack(spacing: 18) {
                        Button { onDecide(true) } label: {
                            Text("允许").font(.system(size: 12.5).weight(.semibold)).foregroundColor(.niDone)
                        }.buttonStyle(.plain)
                        Button { onDecide(false) } label: {
                            Text("拒绝").font(.system(size: 12.5).weight(.semibold)).foregroundColor(.niText2)
                        }.buttonStyle(.plain)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(.horizontal, 13).padding(.vertical, compact ? 10 : 12)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(Color.white.opacity(hovering ? 0.065 : 0.035)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { onJump() }     // 点行跳转到对应终端（审批按钮各自独立响应）
        .contextMenu {
            Button("隐藏此会话") { onHide() }
            Button("屏蔽此项目目录") { onBlockDir() }
        }
    }

    @ViewBuilder private var activity: some View {
        HStack(alignment: .top, spacing: 8) {
            if let glyph = ToolGlyph.from(session.line.tool) {
                HStack(spacing: 5) {
                    Image(systemName: glyph.symbol)
                        .font(.system(size: 10.5, weight: .semibold))
                    Text(glyph.label)
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundColor(glyph.color)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(glyph.color.opacity(0.13))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            Text(session.line.text).font(.system(size: 12))
                .foregroundColor(session.state == .done ? .niDone : .niText3)
                .lineLimit(session.state == .waiting ? 2 : 1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func agentBadge(_ a: AgentKind) -> some View {
        Text(a.displayName).font(.system(size: 10))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(a.color.opacity(0.13)).foregroundColor(a.color)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
    private func badge(_ b: Session.Badge) -> some View {
        let c: Color = b.kind == .auto ? .niDel : .niText2
        return Text(b.text).font(.system(size: 10))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(c.opacity(b.kind == .auto ? 0.14 : 0.08)).foregroundColor(c)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct ProgressLine: View {
    let session: Session

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Circle()
                    .fill(session.state.dotColor)
                    .frame(width: 6, height: 6)
                Text(session.stageLabel)
                    .font(.system(size: 10.8, weight: .medium))
                    .foregroundColor(session.state.dotColor)
                    .lineLimit(1)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.07))
                    Capsule().fill(session.state.dotColor.opacity(0.8))
                        .frame(width: max(8, geo.size.width * session.progressEstimate))
                }
            }
            .frame(height: 5)
            Text(progressText)
                .font(.system(size: 10.5, design: .rounded))
                .foregroundColor(.niText3)
                .frame(width: 34, alignment: .trailing)
        }
    }

    private var progressText: String {
        if session.state == .waiting { return "待办" }
        if session.state == .done { return "完成" }
        if session.state == .idle { return "空闲" }
        if session.state == .compacting { return "压缩" }
        return session.line.tool == nil ? "执行" : "工具"
    }
}
