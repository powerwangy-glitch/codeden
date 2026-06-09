import AppKit

/// 物理刘海几何（每台机器不同，运行时从 NSScreen 读取）。
struct NotchMetrics: Equatable {
    var height: CGFloat   // 刘海高 = safeAreaInsets.top
    var width: CGFloat    // 刘海宽 = 右侧翼区 minX - 左侧翼区 maxX

    var hasNotch: Bool { height > 0 && width > 0 }
    static let none = NotchMetrics(height: 0, width: 0)

    static func read(_ screen: NSScreen) -> NotchMetrics {
        let h = screen.safeAreaInsets.top
        var w: CGFloat = 0
        if #available(macOS 12.0, *),
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            w = right.minX - left.maxX
        }
        guard h > 0, w > 0 else { return .none }
        return NotchMetrics(height: h, width: w)
    }

    /// 选有刘海的屏幕，没有就主屏。
    static func current() -> (screen: NSScreen, metrics: NotchMetrics)? {
        if let notched = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return (notched, read(notched))
        }
        if let main = NSScreen.main { return (main, .none) }
        return nil
    }
}

/// 收起态翼区宽度（刘海两侧各放内容的固定宽）。
enum NotchLayout {
    static let wing: CGFloat = 78             // 刘海两侧翼区宽（只够放图标/短文字 + 呼吸感）
    static let fallbackHeight: CGFloat = 32   // 无刘海时收起态高
}
