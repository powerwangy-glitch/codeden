import Foundation
import QuartzCore

/// 欠阻尼弹簧尺寸动画——产生「果冻」般的过冲回弹。
/// 自己积分弹簧方程，每帧回调当前尺寸；用于驱动刘海窗口 + SwiftUI 背景一起回弹。
@MainActor
final class SpringSize {
    private(set) var value: CGSize
    private var target: CGSize
    private var vel = CGVector.zero
    private var timer: Timer?

    /// stiffness 越大越快，damping 越小越「Q弹」(过冲越多)。
    /// zeta = damping / (2*sqrt(stiffness)) ≈ 0.52 → 明显回弹但不过分。
    var stiffness: Double = 260
    var damping: Double = 17

    var onStep: ((CGSize) -> Void)?

    init(_ initial: CGSize) { value = initial; target = initial }

    /// 平滑弹向目标尺寸（保留当前速度，连续手势也顺）。
    func animate(to t: CGSize) {
        target = t
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.step() }
            }
            if let timer { RunLoop.main.add(timer, forMode: .common) } // 拖动菜单时仍跑
        }
    }

    /// 立即吸附（无动画），用于首帧。
    func snap(to t: CGSize) {
        timer?.invalidate(); timer = nil
        value = t; target = t; vel = .zero
        onStep?(value)
    }

    private func step() {
        let dt = 1.0 / 120.0
        for _ in 0..<2 {   // 子步积分，提升数值稳定性
            let fw = -stiffness * (value.width  - target.width)  - damping * vel.dx
            let fh = -stiffness * (value.height - target.height) - damping * vel.dy
            vel.dx += fw * dt; vel.dy += fh * dt
            value.width  += vel.dx * dt
            value.height += vel.dy * dt
        }
        onStep?(value)

        if abs(value.width - target.width) < 0.3, abs(value.height - target.height) < 0.3,
           abs(vel.dx) < 0.5, abs(vel.dy) < 0.5 {
            value = target; onStep?(value)
            timer?.invalidate(); timer = nil
        }
    }
}
