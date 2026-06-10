import AppKit
import SwiftUI
import Combine

/// 管理贴在刘海下方的无边框置顶窗口。
/// 尺寸由 SpringSize 弹簧驱动（果冻过冲），每帧同步窗口 frame + SwiftUI 背景，
/// 并保持顶部居中。目标尺寸用一个离屏 NSHostingView 测量内容自然尺寸得到。
@MainActor
final class NotchController {
    private let store: AppStore
    private let panel: NSPanel
    private let hosting: NSHostingController<IslandView>
    private let measure: NSHostingView<ContentOnly>   // 离屏测量
    private let spring: SpringSize
    private var bag = Set<AnyCancellable>()

    init(store: AppStore) {
        self.store = store
        hosting = NSHostingController(rootView: IslandView(store: store))
        measure = NSHostingView(rootView: ContentOnly(store: store))
        spring = SpringSize(store.islandSize)

        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: store.islandSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.contentViewController = hosting

        // 弹簧每帧 → 更新 SwiftUI 背景尺寸 + 窗口 frame（顶部居中）
        spring.onStep = { [weak self] size in
            guard let self else { return }
            // 下限 = 刘海尺寸：收起回弹时绝不缩到刘海以内（否则会露出物理刘海，出现两个黑框）
            let n = self.store.notch
            let clamped = n.hasNotch
                ? CGSize(width: max(size.width, n.width), height: max(size.height, n.height))
                : size
            self.store.islandSize = clamped
            self.applyFrame(clamped)
        }

        // 展开/收起切换 → 测量目标自然尺寸 → 弹过去
        store.$expanded
            .removeDuplicates()
            .sink { [weak self] _ in self?.retarget() }
            .store(in: &bag)

        Publishers.Merge3(
            store.$sessions.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            store.$quotas.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            store.$panelWidth.dropFirst().map { _ in () }.eraseToAnyPublisher()
        )
        .debounce(for: .milliseconds(80), scheduler: RunLoop.main)
        .sink { [weak self] _ in self?.retarget() }
        .store(in: &bag)

        // 屏幕变化（插拔显示器/分辨率）→ 重新读刘海几何
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshNotch(); self?.retarget() }
        }
    }

    private func refreshNotch() {
        store.notch = NotchMetrics.current()?.metrics ?? .none
    }

    func show() {
        refreshNotch()
        // 等 SwiftUI 用上新几何后再测量首帧
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.spring.snap(to: self.measuredTargetSize())
            self.panel.orderFrontRegardless()
        }
    }

    /// 测量当前状态（pill 或 panel）的内容自然尺寸。
    private func measuredTargetSize() -> CGSize {
        measure.layoutSubtreeIfNeeded()
        var s = measure.fittingSize
        if s.width < 40 { s.width = 280 }
        if s.height < 20 { s.height = 34 }
        return s
    }

    private func retarget() {
        // 等 SwiftUI 提交本次状态变更后再测量
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.spring.animate(to: self.measuredTargetSize())
        }
    }

    private func applyFrame(_ size: CGSize) {
        let screen = notchScreen ?? NSScreen.main
        guard let screen else { return }
        let vf = screen.frame
        let x = (vf.midX - size.width / 2).rounded()
        let y = (vf.maxY - size.height).rounded()   // 顶边贴屏幕顶
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    private var notchScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
    }
}
