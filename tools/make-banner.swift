// 生成 README/发布用的 hero 横幅。用法： swift tools/make-banner.swift → assets/hero.png
import AppKit

func hex(_ s: String) -> NSColor {
  var v: UInt64 = 0; Scanner(string: s).scanHexInt64(&v)
  return NSColor(srgbRed: CGFloat((v>>16)&0xff)/255, green: CGFloat((v>>8)&0xff)/255, blue: CGFloat(v&0xff)/255, alpha: 1)
}

let sprites: [(rows: [String], pal: [Character: NSColor])] = [
  (["................",".......44.......","......f44f......","......f44f......","....oooooooo....","...oaaaaaaaao...",
    "..oabbbbbbbbao..","..oabbbbbbbbao..","..oabwwbbwwbao..","..oabwkbbwkbao..","..oabbbbbbbbao..","..oabbbbbbbbao..",
    "...oaaaaaaaao...","....oooooooo....","................","................"],
   ["o":hex("3a1d0a"),"a":hex("d97757"),"b":hex("f0a986"),"w":.white,"k":hex("2a1505"),"f":hex("ff8a3d"),"4":hex("ffd24d")]),
  (["................",".......g........","......ggg.......",".......g........","....oooooooo....","...oeeeeeeeeo...",
    "..oennnnnnnneo..","..oennnnnnnneo..","..oennwwwwnneo..","..oennwkkwnneo..","..oennwwwwnneo..","..oennnnnnnneo..",
    "...oeeeeeeeeo...","....oooooooo....","................","................"],
   ["o":hex("0a2e1a"),"e":hex("10a37f"),"n":hex("4fd6a6"),"g":hex("7ee787"),"w":.white,"k":hex("062017")]),
  (["................",".....i....i.....",".....i....i.....","....oooooooo....","...oBBBBBBBBo...","..oBccccccccBo..",
    "..oBccccccccBo..","..oBcwwccwwcBo..","..oBckwccwkcBo..","..oBccccccccBo..","..oBccccccccBo..","...oBBBBBBBBo...",
    "....oooooooo....","................","................","................"],
   ["o":hex("0a1a3a"),"B":hex("1a6dff"),"c":hex("7fb4ff"),"i":hex("5ea0ff"),"w":.white,"k":hex("06122e")]),
  (["................","................","....oooooooo....","...oPPPPPPPPo...","..oPuuuuuuuuPo..","..oPuwwuuwwuPo..",
    "..oPuwkuukwuPo..","..oPuuuuuuuuPo..","..oPuauuuuuuPo..","..oPuaauuuuuPo..","..oPuaaauuuuPo..","..oPuuuuuuuuPo..",
    "...oPPPPPPPPo...","....oooooooo....","................","................"],
   ["o":hex("1f0a3a"),"P":hex("a855f7"),"u":hex("d0a6ff"),"w":.white,"k":hex("160630"),"a":.white]),
]

func drawSprite(_ idx: Int, x: CGFloat, y: CGFloat, cell: CGFloat) {
  let (rows, pal) = sprites[idx]
  for (r, line) in rows.enumerated() {
    for (c, ch) in line.enumerated() {
      guard let col = pal[ch] else { continue }
      col.setFill()
      NSRect(x: x + CGFloat(c)*cell, y: y + CGFloat(15-r)*cell, width: cell+0.5, height: cell+0.5).fill()
    }
  }
}

let W: CGFloat = 1280, H: CGFloat = 640
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H),
  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// 背景渐变
NSGradient(colors: [hex("222a3d"), hex("0b0d12")])!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)

// 顶部刘海意象（贴顶黑色圆角条）
let nW: CGFloat = 300, nH: CGFloat = 46
let notch = NSBezierPath(roundedRect: NSRect(x: (W-nW)/2, y: H-nH, width: nW, height: nH), xRadius: 16, yRadius: 16)
hex("000000").setFill(); notch.fill()
// 刘海里探出 3 只小怪兽
ctx.interpolationQuality = .none
for (i, idx) in [0,1,2].enumerated() {
  drawSprite(idx, x: (W-nW)/2 + 90 + CGFloat(i)*44, y: H-nH+8, cell: 30/16*1.0 * (30/16 > 0 ? 1 : 1))
}

// 主体 4 只大怪兽一排
let big: CGFloat = 150, gap: CGFloat = 40
let totalW = big*4 + gap*3
var sx = (W - totalW)/2
for idx in 0..<4 { drawSprite(idx, x: sx, y: 300, cell: big/16); sx += big + gap }

// 标题 + slogan
func text(_ s: String, _ font: NSFont, _ color: NSColor, _ rect: NSRect) {
  let p = NSMutableParagraphStyle(); p.alignment = .center
  (s as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: p])
}
text("码岛 CodeDen", NSFont.systemFont(ofSize: 76, weight: .bold), .white, NSRect(x: 0, y: 150, width: W, height: 100))
text("把刘海变成 AI 编码助手的实时基地", NSFont.systemFont(ofSize: 30, weight: .medium), hex("a9b0c0"), NSRect(x: 0, y: 95, width: W, height: 44))
text("实时盯梢 · 刘海里审批 · 额度预警 · 怪兽养成", NSFont.systemFont(ofSize: 22, weight: .regular), hex("6e7891"), NSRect(x: 0, y: 52, width: W, height: 34))

NSGraphicsContext.restoreGraphicsState()
try? FileManager.default.createDirectory(atPath: "assets", withIntermediateDirectories: true)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "assets/hero.png"))
print("✅ assets/hero.png")
