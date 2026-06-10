import AppKit
import SwiftUI

/// 设置窗口控制器（标准可关闭窗口；agent 应用临时前台化以展示）。
@MainActor
final class SettingsController {
    private var window: NSWindow?
    private let store: AppStore
    init(store: AppStore) { self.store = store }

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 640),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "码岛 设置"
            w.contentViewController = NSHostingController(rootView: SettingsView(store: store))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// 调用打包进 .app 的桥接脚本（开发态回退到仓库路径）。
enum HookInstaller {
    static func scriptPath(_ name: String) -> String? {
        if let u = Bundle.main.resourceURL?.appendingPathComponent("bridge/\(name)"),
           FileManager.default.fileExists(atPath: u.path) { return u.path }
        let dev = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("交易/NotchIsland/bridge/\(name)").path
        return FileManager.default.fileExists(atPath: dev) ? dev : nil
    }

    static func run(_ name: String) -> String {
        guard let p = scriptPath(name) else { return "找不到脚本 \(name)" }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["python3", p]
        let pipe = Pipe()
        proc.standardOutput = pipe; proc.standardError = pipe
        do { try proc.run(); proc.waitUntilExit() }
        catch { return "运行失败：\(error.localizedDescription)" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? "(无输出)"
    }
}

/// 伙伴图鉴：展示各 agent 怪兽的等级 / 称号 / 经验 / 进化形态。
struct DenView: View {
    @ObservedObject var buddies: BuddyStore
    private let agents: [AgentKind] = [.claude, .codex, .gemini, .cursor]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(agents, id: \.self) { a in
                let lv = buddies.level(a)
                let st = buddies.stat(a)
                HStack(spacing: 10) {
                    Image(nsImage: Sprites.image(a, stage: buddies.stage(a)))
                        .interpolation(.none).resizable().frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(a.displayName).font(.system(size: 12, weight: .semibold))
                            Text("Lv.\(lv) · \(buddies.title(a))")
                                .font(.system(size: 10)).foregroundColor(a.color)
                            Spacer()
                            Text("完成 \(st.completed) · 工具 \(st.tools)")
                                .font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                        // EXP 进度条
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.1))
                                Capsule().fill(a.color)
                                    .frame(width: g.size.width * CGFloat(buddies.expInLevel(a)) / 100)
                            }
                        }.frame(height: 4)
                    }
                }
            }
            Text("完成一轮 +20 · 批准 +5 · 工具 +2 · 每 100 升一级（Lv.4 长星星，Lv.12 戴皇冠）")
                .font(.system(size: 9)).foregroundStyle(.tertiary)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store: AppStore
    @State private var hookStatus = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(nsImage: Sprites.image(.claude)).interpolation(.none).resizable()
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text("码岛 CodeDen").font(.title3.bold())
                    Text("刘海 AI agent 基地 · v0.1").font(.caption).foregroundStyle(.secondary)
                }
            }

            GroupBox("通用") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("开机自启", isOn: $store.launchAtLogin)
                    Toggle("显示额度", isOn: $store.showQuota)
                    Toggle("需要审批时自动展开", isOn: $store.autoExpandOnWaiting)
                    HStack {
                        Text("面板宽度 \(Int(store.panelWidth))")
                        Slider(value: $store.panelWidth, in: 380...560, step: 20)
                    }
                    HStack {
                        Text(store.hoverDelay <= 0.01 ? "悬停立即展开" : String(format: "悬停延迟 %.1fs", store.hoverDelay))
                        Slider(value: $store.hoverDelay, in: 0...1.5, step: 0.1)
                    }
                }.padding(8)
            }

            GroupBox("声音") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("提示音（芯片电音）", isOn: $store.soundEnabled)
                    Toggle("夜间静音时段", isOn: $store.quietHoursEnabled)
                    if store.quietHoursEnabled {
                        HStack(spacing: 8) {
                            Picker("从", selection: $store.quietStart) {
                                ForEach(0..<24, id: \.self) { Text("\($0):00").tag($0) }
                            }.frame(width: 110)
                            Picker("到", selection: $store.quietEnd) {
                                ForEach(0..<24, id: \.self) { Text("\($0):00").tag($0) }
                            }.frame(width: 110)
                            if store.inQuietHours {
                                Text("· 静音中").font(.caption).foregroundStyle(.orange)
                            }
                        }
                        Text("结束早于开始则跨午夜。适合 Agent 夜间挂机时防打扰。")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }.padding(8)
            }

            if !store.blockedDirs.isEmpty {
                GroupBox("会话过滤") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("已屏蔽 \(store.blockedDirs.count) 个项目目录（右键会话行可添加）")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("清空过滤规则") { store.clearBlockedDirs() }
                    }.padding(8)
                }
            }

            GroupBox("伙伴图鉴") {
                DenView(buddies: store.buddies).padding(8)
            }

            GroupBox("Claude Code 接入") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("把 hook 合并进 ~/.claude/settings.json（自动备份，不覆盖已有配置）")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("安装 Hook") { hookStatus = HookInstaller.run("install.py") }
                        Button("卸载 Hook") { hookStatus = HookInstaller.run("uninstall.py") }
                    }
                    if !hookStatus.isEmpty {
                        ScrollView { Text(hookStatus).font(.system(size: 11, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                            .frame(height: 70)
                            .background(Color(white: 0.1)).cornerRadius(6)
                    }
                    Text("装好后需开新会话生效。").font(.caption2).foregroundStyle(.tertiary)
                }.padding(8)
            }

            Spacer()
            HStack {
                Button("重看新人引导") { store.openOnboarding() }
                Spacer()
                Button("退出 码岛") { NSApp.terminate(nil) }
            }
        }
        .padding(20)
        .frame(width: 400, height: 640)
    }
}
