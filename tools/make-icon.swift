// Renders the app icon set in the Barnameh family style: one squircle, vertical
// coral gradient (#FC8464 → #E9643F), soft top-edge highlight, single white glyph.
// Usage: swift tools/make-icon.swift <AppIcon.appiconset dir>
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let sizes = [16, 32, 64, 128, 256, 512, 1024]
let glyph = "CB"

/// The family squircle, from design-system/assets/icons (100×100 space).
func squircle(_ s: CGFloat) -> NSBezierPath {
  let k = s / 100
  let p = NSBezierPath()
  p.move(to: NSPoint(x: 50 * k, y: 0))
  p.curve(to: NSPoint(x: 94 * k, y: 6 * k), controlPoint1: NSPoint(x: 79 * k, y: 0), controlPoint2: NSPoint(x: 88 * k, y: 0))
  p.curve(to: NSPoint(x: 100 * k, y: 50 * k), controlPoint1: NSPoint(x: 100 * k, y: 12 * k), controlPoint2: NSPoint(x: 100 * k, y: 21 * k))
  p.curve(to: NSPoint(x: 94 * k, y: 94 * k), controlPoint1: NSPoint(x: 100 * k, y: 79 * k), controlPoint2: NSPoint(x: 100 * k, y: 88 * k))
  p.curve(to: NSPoint(x: 50 * k, y: 100 * k), controlPoint1: NSPoint(x: 88 * k, y: 100 * k), controlPoint2: NSPoint(x: 79 * k, y: 100 * k))
  p.curve(to: NSPoint(x: 6 * k, y: 94 * k), controlPoint1: NSPoint(x: 21 * k, y: 100 * k), controlPoint2: NSPoint(x: 12 * k, y: 100 * k))
  p.curve(to: NSPoint(x: 0, y: 50 * k), controlPoint1: NSPoint(x: 0, y: 88 * k), controlPoint2: NSPoint(x: 0, y: 79 * k))
  p.curve(to: NSPoint(x: 6 * k, y: 6 * k), controlPoint1: NSPoint(x: 0, y: 21 * k), controlPoint2: NSPoint(x: 0, y: 12 * k))
  p.curve(to: NSPoint(x: 50 * k, y: 0), controlPoint1: NSPoint(x: 12 * k, y: 0), controlPoint2: NSPoint(x: 21 * k, y: 0))
  p.close()
  return p
}

func rgb(_ hex: UInt32) -> NSColor {
  NSColor(
    calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
    green: CGFloat((hex >> 8) & 0xFF) / 255,
    blue: CGFloat(hex & 0xFF) / 255, alpha: 1
  )
}

func render(_ px: Int) -> Data {
  let s = CGFloat(px)
  let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
  )!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

  let shape = squircle(s)
  // icon-top at the top of the icon (AppKit y is up, so angle 90).
  NSGradient(starting: rgb(0xE9643F), ending: rgb(0xFC8464))!.draw(in: shape, angle: 90)

  // Top-edge highlight: white .18 → .10 at 7% → 0 at 38% from the top.
  let highlight = NSGradient(colorsAndLocations:
    (NSColor.white.withAlphaComponent(0), 0.62),
    (NSColor.white.withAlphaComponent(0.10), 0.93),
    (NSColor.white.withAlphaComponent(0.18), 1.0)
  )!
  highlight.draw(in: shape, angle: 90)

  // Glyph: SF Pro Rounded heavy, white, optically centred.
  let base = NSFont.systemFont(ofSize: s * 0.42, weight: .heavy)
  let font = NSFont(descriptor: base.fontDescriptor.withDesign(.rounded)!, size: s * 0.42) ?? base
  let attrs: [NSAttributedString.Key: Any] = [
    .font: font, .foregroundColor: NSColor.white, .kern: -s * 0.012,
  ]
  let text = NSAttributedString(string: glyph, attributes: attrs)
  let size = text.size()
  let capHeight = font.capHeight
  let x = (s - size.width) / 2
  // draw(at:) places the line box's bottom; baseline sits -descender above it.
  let y = (s - capHeight) / 2 + font.descender
  text.draw(at: NSPoint(x: x, y: y))

  NSGraphicsContext.restoreGraphicsState()
  return rep.representation(using: .png, properties: [:])!
}

for px in sizes {
  let url = URL(fileURLWithPath: outDir).appendingPathComponent("icon_\(px).png")
  try! render(px).write(to: url)
  print("wrote \(url.lastPathComponent)")
}
