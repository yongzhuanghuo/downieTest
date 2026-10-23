import AppKit
import Foundation

// 旧版 4KDownle 6 图标生成脚本：紫色圆角方块 + 白色云下载符号。
// 当前品牌图标已换成 Downie6，勿运行本脚本覆盖 assets/logo6.png。
// 如确需恢复旧图标，运行：cd apps/desktop && swift tools/generate_brand_icon.swift
// 输出：assets/logo6-original.png（1024x1024）。

let size: CGFloat = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size),
    pixelsHigh: Int(size),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!
rep.size = NSSize(width: size, height: size)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high

let rect = NSRect(x: 32, y: 32, width: 960, height: 960)
let squircle = NSBezierPath(roundedRect: rect, xRadius: 220, yRadius: 220)
NSGraphicsContext.saveGraphicsState()
squircle.addClip()

let gradient = NSGradient(
    starting: NSColor(calibratedRed: 0.62, green: 0.48, blue: 1.0, alpha: 1),
    ending: NSColor(calibratedRed: 0.32, green: 0.12, blue: 0.62, alpha: 1)
)!
gradient.draw(in: rect, angle: -45)

// 白色云朵
NSColor.white.setFill()
NSBezierPath(ovalIn: NSRect(x: 300, y: 560, width: 200, height: 200)).fill()
NSBezierPath(ovalIn: NSRect(x: 412, y: 600, width: 220, height: 220)).fill()
NSBezierPath(ovalIn: NSRect(x: 560, y: 560, width: 200, height: 200)).fill()
NSBezierPath(
    roundedRect: NSRect(x: 330, y: 540, width: 364, height: 160),
    xRadius: 80,
    yRadius: 80
).fill()

// 向下箭头
NSBezierPath(
    roundedRect: NSRect(x: 472, y: 380, width: 80, height: 180),
    xRadius: 30,
    yRadius: 30
).fill()

let head = NSBezierPath()
head.move(to: NSPoint(x: 390, y: 390))
head.line(to: NSPoint(x: 634, y: 390))
head.line(to: NSPoint(x: 512, y: 250))
head.close()
head.fill()

NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.restoreGraphicsState()

let data = rep.representation(using: .png, properties: [:])!
try! data.write(to: URL(fileURLWithPath: "assets/logo6-original.png"))
print("generated assets/logo6-original.png (1024x1024)")
