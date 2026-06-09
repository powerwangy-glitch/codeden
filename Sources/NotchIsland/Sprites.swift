import SwiftUI
import AppKit

/// 16x16 像素怪兽数据（与网页原型一致）：每行 16 个字符，字符映射到调色板。
enum Sprites {
    struct Def { let palette: [Character: NSColor]; let rows: [String] }

    static let defs: [AgentKind: Def] = [
        .claude: Def(palette: pal(["o":"#3a1d0a","a":"#d97757","b":"#f0a986","w":"#ffffff","k":"#2a1505","f":"#ff8a3d","4":"#ffd24d"]),
            rows: ["................",".......44.......","......f44f......","......f44f......","....oooooooo....","...oaaaaaaaao...",
                   "..oabbbbbbbbao..","..oabbbbbbbbao..","..oabwwbbwwbao..","..oabwkbbwkbao..","..oabbbbbbbbao..","..oabbbbbbbbao..",
                   "...oaaaaaaaao...","....oooooooo....","................","................"]),
        .codex: Def(palette: pal(["o":"#0a2e1a","e":"#10a37f","n":"#4fd6a6","g":"#7ee787","w":"#ffffff","k":"#062017"]),
            rows: ["................",".......g........","......ggg.......",".......g........","....oooooooo....","...oeeeeeeeeo...",
                   "..oennnnnnnneo..","..oennnnnnnneo..","..oennwwwwnneo..","..oennwkkwnneo..","..oennwwwwnneo..","..oennnnnnnneo..",
                   "...oeeeeeeeeo...","....oooooooo....","................","................"]),
        .gemini: Def(palette: pal(["o":"#0a1a3a","B":"#1a6dff","c":"#7fb4ff","i":"#5ea0ff","w":"#ffffff","k":"#06122e"]),
            rows: ["................",".....i....i.....",".....i....i.....","....oooooooo....","...oBBBBBBBBo...","..oBccccccccBo..",
                   "..oBccccccccBo..","..oBcwwccwwcBo..","..oBckwccwkcBo..","..oBccccccccBo..","..oBccccccccBo..","...oBBBBBBBBo...",
                   "....oooooooo....","................","................","................"]),
        .cursor: Def(palette: pal(["o":"#1f0a3a","P":"#a855f7","u":"#d0a6ff","w":"#ffffff","k":"#160630","a":"#ffffff"]),
            rows: ["................","................","....oooooooo....","...oPPPPPPPPo...","..oPuuuuuuuuPo..","..oPuwwuuwwuPo..",
                   "..oPuwkuukwuPo..","..oPuuuuuuuuPo..","..oPuauuuuuuPo..","..oPuaauuuuuPo..","..oPuaaauuuuPo..","..oPuuuuuuuuPo..",
                   "...oPPPPPPPPo...","....oooooooo....","................","................"]),
    ]

    private static func pal(_ m: [String: String]) -> [Character: NSColor] {
        var out: [Character: NSColor] = [:]
        for (k, v) in m { out[Character(k)] = NSColor(hex: v) }
        return out
    }

    /// 渲染成 NSImage（点对点，禁插值）。stage 为进化阶段：2 长星星 / 3 戴皇冠。
    static func image(_ agent: AgentKind, stage: Int = 1) -> NSImage {
        let def = defs[agent] ?? defs[.claude]!
        let n = 16
        let img = NSImage(size: NSSize(width: n, height: n))
        img.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .none
        for (y, row) in def.rows.enumerated() {
            for (x, ch) in row.enumerated() {
                guard let c = def.palette[ch] else { continue }
                c.setFill()
                // NSImage 坐标系 y 向上翻转
                NSRect(x: x, y: n - 1 - y, width: 1, height: 1).fill()
            }
        }
        // 进化外观（画在顶部 row0/1 → y=15/14）
        let gold = NSColor(hex: "ffd24d")
        gold.setFill()
        if stage >= 3 {
            for x in [5, 7, 9, 11] { NSRect(x: x, y: 15, width: 1, height: 1).fill() } // 皇冠尖
            for x in 5...11 { NSRect(x: x, y: 14, width: 1, height: 1).fill() }          // 皇冠带
        } else if stage >= 2 {
            NSRect(x: 12, y: 14, width: 1, height: 1).fill()                              // 星星点
            NSRect(x: 13, y: 15, width: 1, height: 1).fill()
        }
        img.unlockFocus()
        img.isTemplate = false
        return img
    }
}

/// SwiftUI 里显示像素精灵，支持运行跳动 / 睡眠灰化。
struct SpriteView: View {
    let agent: AgentKind
    var size: CGFloat = 17
    var running: Bool = false
    var sleeping: Bool = false
    var stage: Int = 1
    @State private var bob = false

    var body: some View {
        Image(nsImage: Sprites.image(agent, stage: stage))
            .interpolation(.none)
            .resizable()
            .frame(width: size, height: size)
            .saturation(sleeping ? 0 : 1)
            .brightness(sleeping ? -0.15 : 0)
            .offset(y: (running && bob) ? -2 : 0)
            .onAppear {
                guard running else { return }
                withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) { bob = true }
            }
    }
}

extension NSColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0; Scanner(string: s).scanHexInt64(&v)
        let r = CGFloat((v & 0xFF0000) >> 16) / 255
        let g = CGFloat((v & 0x00FF00) >> 8) / 255
        let b = CGFloat(v & 0x0000FF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}
