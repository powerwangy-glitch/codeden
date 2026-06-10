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
            // 收起态点击：只有一个会话直接跳转，多个则展开
            guard !store.expanded else { return }
            if store.sessions.count == 1 { store.jump(store.sessions[0]) }
            else { store.expanded = true }
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
                    .padding(.trailing, 6)
                Color.clear.frame(width: n.width)
                rightWing.frame(width: NotchLayout.wing, alignment: .leading)
                    .padding(.leading, 6)
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
        if store.pillState == .rest {
            SpriteView(agent: .claude, size: 17, sleeping: true)
        } else if let first = store.sessions.first {
            SpriteView(agent: first.agent, size: 17, running: first.state.isBusy)
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
            if store.sessions.isEmpty {
                VStack(spacing: 8) {
                    Text("z z Z").font(.system(size: 11, design: .monospaced)).foregroundColor(.niText3)
                    Text("没有正在运行的 agent").font(.system(size: 12)).foregroundColor(.niText3)
                }.padding(.vertical, 18).frame(maxWidth: .infinity)
            } else {
                ForEach(Array(store.sessions.enumerated()), id: \.element.id) { idx, s in
                    ItemRow(session: s,
                            onDecide: { allow in store.decide(s, allow: allow) },
                            onJump: { store.jump(s) },
                            onHide: { store.hideSession(s) },
                            onBlockDir: { store.blockDir(s) },
                            onAnswer: { i in store.answer(s, option: i) })
                }
            }
            Color.clear.frame(height: 6)
        }
        .frame(width: CGFloat(store.panelWidth), alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct QuotaHeader: View {
    @ObservedObject var store: AppStore
    var body: some View {
        HStack(spacing: 0) {
            leftGroup
            Spacer(minLength: 10)
            rightGroup
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    @ViewBuilder private var leftGroup: some View {
        HStack(spacing: 12) {
            if store.showQuota {
                if store.quotas.isEmpty {
                    SpriteView(agent: .claude, size: 18)
                    Text("额度读取中…").font(.system(size: 11)).foregroundColor(.niText3)
                } else {
                    ForEach(store.quotas.indices, id: \.self) { i in
                        let q = store.quotas[i]
                        HStack(spacing: 6) {
                            SpriteView(agent: q.agent, size: 16)   // 每个额度配对应 agent 图标
                            quotaSeg(q.fiveHour)
                            Text("|").foregroundColor(.niText3).opacity(0.45)
                            quotaSeg(q.sevenDay)
                        }
                    }
                }
            } else {
                SpriteView(agent: .claude, size: 18)
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
                    SpriteView(agent: session.agent, size: 17, running: session.state.isBusy)
                }
            }
            .frame(width: 40, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                // 第一行：标题 + 标签 + 时间
                HStack(spacing: 8) {
                    Text(session.task.isEmpty ? session.project : "\(session.project) · \(session.task)")
                        .font(.system(size: 13).weight(.semibold)).foregroundColor(.niText)
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
                // 第二行：你说的话
                if !session.user.isEmpty {
                    Text("你：\(session.user)").font(.system(size: 12)).foregroundColor(.niText2)
                        .lineLimit(1).truncationMode(.tail)
                }
                // 第三行：当前动作 / 审批 / 提问
                activity
                // 计划审批（ExitPlanMode）：读计划 → 批准/驳回
                if let plan = session.plan, session.requestID != nil, session.state == .waiting {
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
                else if let qs = session.questions, session.state == .waiting, session.questionIndex < qs.count {
                    let q = qs[session.questionIndex]
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(qs.count > 1 ? "第 \(session.questionIndex + 1) / \(qs.count) 题" : "Claude 的提问")
                                .font(.system(size: 10.5)).foregroundColor(.niWarn)
                            if q.multiSelect == true {
                                Text("· 多选请在终端操作").font(.system(size: 10)).foregroundColor(.niText3)
                            }
                        }
                        Text(q.question).font(.system(size: 12.5)).foregroundColor(.niText)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(Array(q.options.enumerated()), id: \.offset) { i, opt in
                            Button { if q.multiSelect != true { onAnswer(i) } } label: {
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
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 6)
                }
                // 审批按钮（仅在等待你审批且可回写时出现）
                else if session.requestID != nil, session.state == .waiting {
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
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 12).fill(hovering ? Color.white.opacity(0.05) : Color.clear).padding(.horizontal, 6))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { onJump() }     // 点行跳转到对应终端（审批按钮各自独立响应）
        .contextMenu {
            Button("隐藏此会话") { onHide() }
            Button("屏蔽此项目目录") { onBlockDir() }
        }
    }

    @ViewBuilder private var activity: some View {
        HStack(spacing: 6) {
            if let t = session.line.tool {
                Text(t).font(.system(size: 12)).foregroundColor(.niTool)
            }
            Text(session.line.text).font(.system(size: 12))
                .foregroundColor(session.state == .done ? .niDone : .niText3)
                .lineLimit(1).truncationMode(.tail)
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
