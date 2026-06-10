import AppKit
import SwiftUI

/// 首次启动的新人引导窗口（4 步）。完成后写 onboarded 标记；设置页可重看。
@MainActor
final class OnboardingController {
    private var window: NSWindow?
    private let store: AppStore
    init(store: AppStore) { self.store = store }

    static var shouldShow: Bool { !UserDefaults.standard.bool(forKey: "onboarded") }

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 540, height: 460),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "欢迎使用 码岛"
            w.isReleasedWhenClosed = false
            w.center()
            w.contentViewController = NSHostingController(
                rootView: OnboardingView(store: store, onFinish: { [weak self] in
                    UserDefaults.standard.set(true, forKey: "onboarded")
                    self?.window?.close()
                }))
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// 环境扫描：检测已装的 AI CLI 和终端/IDE。
enum EnvDetect {
    struct Item { let name: String; let found: Bool }
    static func scan() -> [Item] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fm = FileManager.default
        func dir(_ p: String) -> Bool { fm.fileExists(atPath: p) }
        func app(_ n: String) -> Bool { dir("/Applications/\(n).app") || dir("\(home)/Applications/\(n).app") }
        var out: [Item] = [
            Item(name: "Claude Code", found: dir("\(home)/.claude")),
            Item(name: "Codex CLI",   found: dir("\(home)/.codex")),
            Item(name: "Gemini CLI",  found: dir("\(home)/.gemini")),
        ]
        let terms: [(String, String)] = [("iTerm2","iTerm"), ("Warp","Warp"), ("Ghostty","Ghostty"),
                                          ("kitty","kitty"), ("VS Code","Visual Studio Code"), ("Cursor","Cursor")]
        let found = terms.filter { app($0.1) }.map(\.0)
        out.append(Item(name: found.isEmpty ? "终端 & IDE" : "终端 & IDE（\(found.joined(separator: " · "))）",
                        found: !found.isEmpty || dir("/System/Applications/Utilities/Terminal.app")))
        return out
    }
}

struct OnboardingView: View {
    @ObservedObject var store: AppStore
    var onFinish: () -> Void
    @State private var step = 0
    @State private var hookStatus = ""
    private let total = 5

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 36).padding(.top, 36)

            // 底部：页点 + 按钮
            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<total, id: \.self) { i in
                        Circle().fill(i == step ? Color.primary : Color.secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                    }
                }
                Spacer()
                if step > 0 {
                    Button("上一步") { withAnimation { step -= 1 } }
                }
                Button(step == total - 1 ? "开始使用" : "下一步") {
                    if step == total - 1 { onFinish() } else { withAnimation { step += 1 } }
                }.keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 540, height: 460)
    }

    @ViewBuilder private var content: some View {
        switch step {
        case 0: welcome
        case 1: environment
        case 2: features
        case 3: connect
        default: ready
        }
    }

    // 步骤 2：环境检测（已检测 ✓ 即信任感）
    private var environment: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("你的环境").font(.title2.bold())
            Text("码岛扫描了这台 Mac，以下工具可以直接接入：")
                .font(.callout).foregroundStyle(.secondary)
            ForEach(EnvDetect.scan(), id: \.name) { item in
                HStack(spacing: 10) {
                    Text(item.found ? "✓" : "—")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(item.found ? Color.green : Color.secondary.opacity(0.5))
                        .frame(width: 18)
                    Text(item.name).font(.system(size: 13))
                    Spacer()
                    Text(item.found ? "已检测" : "未发现")
                        .font(.caption).foregroundStyle(item.found ? Color.green : Color.secondary.opacity(0.5))
                }
                .padding(.vertical, 2)
            }
            Text("零配置 — 下一步一键接入，无需手动改任何文件。")
                .font(.caption).foregroundStyle(.tertiary).padding(.top, 4)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    // 步骤 1：欢迎
    private var welcome: some View {
        VStack(spacing: 16) {
            Image(nsImage: Sprites.image(.claude, stage: 3)).interpolation(.none).resizable()
                .frame(width: 96, height: 96)
            Text("码岛 CodeDen").font(.system(size: 30, weight: .bold))
            Text("把 MacBook 刘海变成 AI 编码助手的实时基地").font(.title3).foregroundStyle(.secondary)
            Text("每个 agent 是一只像素小怪兽，帮你盯着它们干活——\n不用一直盯着终端。")
                .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxHeight: .infinity)
    }

    // 步骤 2：能做什么
    private var features: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("它能帮你做什么").font(.title2.bold())
            featureRow("👀", "实时盯梢", "刘海显示所有 agent 状态：在跑 / 需要你 / 完成 / 休息")
            featureRow("✅", "不切终端就审批", "弹出「允许 / 拒绝」直接回传给 Claude Code")
            featureRow("📊", "额度一眼清", "顶栏看 5h / 7d 用量，快撞墙自动报警")
            featureRow("🎮", "怪兽养成", "agent 干得越多，怪兽升级进化（长星星、戴皇冠）")
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func featureRow(_ emoji: String, _ title: String, _ desc: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(emoji).font(.system(size: 24))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(desc).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    // 步骤 3：接入 Claude Code
    private var connect: some View {
        VStack(spacing: 14) {
            Text("接入 Claude Code").font(.title2.bold())
            Text("点一下，把 hook 合并进 ~/.claude/settings.json\n（自动备份，不覆盖你已有的任何配置）")
                .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("一键安装 Hook") { hookStatus = HookInstaller.run("install.py") }
                .controlSize(.large)
            if !hookStatus.isEmpty {
                ScrollView { Text(hookStatus).font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                    .frame(height: 90).background(Color(white: 0.1)).cornerRadius(6)
            }
            Text("装好后开一个新的 Claude Code 会话即可生效。也可稍后在设置里安装。")
                .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
        }.frame(maxHeight: .infinity)
    }

    // 步骤 4：完成
    private var ready: some View {
        VStack(spacing: 16) {
            Image(nsImage: Sprites.image(.claude, stage: 2)).interpolation(.none).resizable()
                .frame(width: 72, height: 72)
            Text("一切就绪 🎉").font(.title.bold())
            Text("把鼠标移到屏幕顶部的刘海上，它会果冻般展开。")
                .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Toggle("开机自启（推荐）", isOn: $store.launchAtLogin).fixedSize()
            Text("随时点刘海右上角 ⚙ 调整设置、查看伙伴图鉴。")
                .font(.caption).foregroundStyle(.tertiary)
        }.frame(maxHeight: .infinity)
    }
}
