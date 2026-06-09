// 生成 NotchIsland 的像素风 App 图标（.iconset PNG 序列）。
// 用法： swift tools/make-icon.swift  → 输出到 icon/AppIcon.iconset/，再由 build 脚本跑 iconutil。
import AppKit

let claude: [String] = [
  "................",".......44.......","......f44f......","......f44f......","....oooooooo....","...oaaaaaaaao...",
  "..oabbbbbbbbao..","..oabbbbbbbbao..","..oabwwbbwwbao..","..oabwkbbwkbao..","..oabbbbbbbbao..","..oabbbbbbbbao..",
  "...oaaaaaaaao...","....oooooooo....","................","................"]
let pal: [Character: NSColor] = [
  "o": hex("3a1d0a"), "a": hex("d97757"), "b": hex("f0a986"), "w": .white,
  "k": hex("2a1505"), "f": hex("ff8a3d"), "4": hex("ffd24d")]

func hex(_ s: String) -> NSColor {
  var v: UInt64 = 0; Scanner(string: s).scanHexInt64(&v)
  return NSColor(srgbRed: CGFloat((v>>16)&0xff)/255, green: CGFloat((v>>8)&0xff)/255, blue: CGFloat(v&0xff)/255, alpha: 1)
}

func drawIcon(_ S: CGFloat) -> NSBitmapImageRep {
  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  let ctx = NSGraphicsContext.current!.cgContext

  // 圆角方形背景 + 竖向渐变（深空蓝黑）
  let r = S * 0.2237
  let path = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: S, height: S), xRadius: r, yRadius: r)
  path.addClip()
  let grad = NSGradient(colors: [hex("222838"), hex("0c0e12")])!
  grad.draw(in: NSRect(x: 0, y: 0, width: S, height: S), angle: -90)

  // 顶部刘海意象：一条贴顶的黑色圆角条
  let nW = S * 0.34, nH = S * 0.11
  let notch = NSBezierPath(roundedRect: NSRect(x: (S-nW)/2, y: S-nH, width: nW, height: nH),
                           xRadius: nH*0.45, yRadius: nH*0.45)
  hex("000000").setFill(); notch.fill()

  // 居中的像素吉祥物
  ctx.interpolationQuality = .none
  let side = S * 0.6
  let cell = side / 16
  let ox = (S - side) / 2
  let oy = (S - side) / 2 - S * 0.04
  for (row, line) in claude.enumerated() {
    for (col, ch) in line.enumerated() {
      guard let c = pal[ch] else { continue }
      c.setFill()
      NSRect(x: ox + CGFloat(col)*cell, y: oy + CGFloat(15-row)*cell, width: cell+0.5, height: cell+0.5).fill()
    }
  }
  NSGraphicsContext.restoreGraphicsState()
  return rep
}

let fm = FileManager.default
let outDir = "icon/AppIcon.iconset"
try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let specs: [(String, CGFloat)] = [
  ("icon_16x16", 16), ("icon_16x16@2x", 32),
  ("icon_32x32", 32), ("icon_32x32@2x", 64),
  ("icon_128x128", 128), ("icon_128x128@2x", 256),
  ("icon_256x256", 256), ("icon_256x256@2x", 512),
  ("icon_512x512", 512), ("icon_512x512@2x", 1024)]

for (name, size) in specs {
  let rep = drawIcon(size)
  let data = rep.representation(using: .png, properties: [:])!
  try! data.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
}
print("✅ 已生成 \(specs.count) 张图标到 \(outDir)")
