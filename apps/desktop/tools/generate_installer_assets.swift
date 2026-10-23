import AppKit
import Foundation

// 生成 macOS DMG 安装窗口用的背景图和安装说明长图。
// 运行：cd apps/desktop && swift tools/generate_installer_assets.swift

struct Canvas {
    let w: CGFloat
    let h: CGFloat
    let rep: NSBitmapImageRep

    init(w: CGFloat, h: CGFloat, top: NSColor, bottom: NSColor) {
        self.w = w
        self.h = h
        rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(w),
            pixelsHigh: Int(h),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        rep.size = NSSize(width: w, height: h)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        let gradient = NSGradient(starting: top, ending: bottom)!
        gradient.draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: -90)
    }

    func rect(_ x: CGFloat, _ top: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
        NSRect(x: x, y: h - top - height, width: width, height: height)
    }

    func point(_ x: CGFloat, _ top: CGFloat) -> NSPoint {
        NSPoint(x: x, y: h - top)
    }

    func text(
        _ value: String,
        x: CGFloat,
        top: CGFloat,
        width: CGFloat,
        height: CGFloat,
        size: CGFloat,
        bold: Bool = false,
        color: NSColor = .black,
        align: NSTextAlignment = .left,
        lineSpacing: CGFloat = 6
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = align
        paragraph.lineSpacing = lineSpacing
        let font = bold
            ? NSFont.boldSystemFont(ofSize: size)
            : NSFont.systemFont(ofSize: size)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        NSAttributedString(string: value, attributes: attrs)
            .draw(in: rect(x, top, width, height))
    }

    func card(
        _ x: CGFloat,
        _ top: CGFloat,
        _ width: CGFloat,
        _ height: CGFloat,
        fill: NSColor,
        stroke: NSColor
    ) {
        let path = NSBezierPath(
            roundedRect: rect(x, top, width, height),
            xRadius: 16,
            yRadius: 16
        )
        fill.setFill()
        path.fill()
        stroke.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    func circle(_ x: CGFloat, _ top: CGFloat, _ diameter: CGFloat, color: NSColor) {
        let path = NSBezierPath(ovalIn: rect(x, top, diameter, diameter))
        color.setFill()
        path.fill()
    }

    func arrow(
        _ x1: CGFloat,
        _ top1: CGFloat,
        _ x2: CGFloat,
        _ top2: CGFloat,
        color: NSColor
    ) {
        let a = point(x1, top1)
        let b = point(x2, top2)
        let path = NSBezierPath()
        path.move(to: a)
        path.line(to: b)
        path.lineWidth = 2
        color.setStroke()
        path.stroke()

        let angle = atan2(b.y - a.y, b.x - a.x)
        let length: CGFloat = 10
        let p1 = NSPoint(
            x: b.x - length * cos(angle - .pi / 6),
            y: b.y - length * sin(angle - .pi / 6)
        )
        let p2 = NSPoint(
            x: b.x - length * cos(angle + .pi / 6),
            y: b.y - length * sin(angle + .pi / 6)
        )
        let head = NSBezierPath()
        head.move(to: b)
        head.line(to: p1)
        head.line(to: p2)
        head.close()
        color.setFill()
        head.fill()
    }

    func logo(_ path: String, x: CGFloat, top: CGFloat, size: CGFloat) {
        guard let image = NSImage(contentsOfFile: path) else { return }
        image.draw(
            in: rect(x, top, size, size),
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )
    }

    func save(_ path: String) {
        NSGraphicsContext.restoreGraphicsState()
        let data = rep.representation(using: .png, properties: [:])!
        try! data.write(to: URL(fileURLWithPath: path))
    }
}

let fm = FileManager.default
let outDir = "macos/installer"
try! fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let logoPath = "assets/logo.png"
let blue = NSColor(calibratedRed: 0.15, green: 0.45, blue: 0.95, alpha: 1)
let lightBlue = NSColor(calibratedRed: 0.91, green: 0.95, blue: 1.0, alpha: 1)
let softStroke = NSColor(calibratedRed: 0.84, green: 0.89, blue: 0.97, alpha: 1)
let red = NSColor(calibratedRed: 0.82, green: 0.20, blue: 0.20, alpha: 1)
let darkGray = NSColor(calibratedWhite: 0.22, alpha: 1)
let muted = NSColor(calibratedWhite: 0.48, alpha: 1)

// ---------- DMG 背景（800 x 500） ----------
do {
    let c = Canvas(w: 800, h: 500, top: lightBlue, bottom: .white)
    c.logo(logoPath, x: 368, top: 24, size: 64)
    c.text(
        "Downie6",
        x: 0, top: 100, width: 800, height: 40,
        size: 28, bold: true, align: .center
    )
    c.text(
        "适用于 macOS 12.0 或更高版本",
        x: 0, top: 144, width: 800, height: 24,
        size: 14, color: muted, align: .center
    )

    c.card(40, 205, 280, 100, fill: NSColor.white.withAlphaComponent(0.94), stroke: softStroke)
    c.text(
        "安装失败？",
        x: 58, top: 218, width: 244, height: 26,
        size: 17, bold: true, color: red
    )
    c.text(
        "双击左侧「安装说明」\n查看详细步骤",
        x: 58, top: 248, width: 244, height: 48,
        size: 13, color: darkGray
    )
    c.arrow(180, 305, 180, 332, color: red)

    c.card(480, 205, 280, 100, fill: NSColor.white.withAlphaComponent(0.94), stroke: softStroke)
    c.text(
        "安装",
        x: 498, top: 218, width: 244, height: 26,
        size: 17, bold: true, color: darkGray
    )
    c.text(
        "将 Downie6 拖入\n「应用程序」文件夹",
        x: 498, top: 248, width: 244, height: 48,
        size: 13, color: darkGray
    )
    c.arrow(560, 305, 560, 332, color: blue)
    c.arrow(548, 365, 608, 365, color: blue)

    c.text(
        "双击 Downie6 启动 · 详细步骤见左侧安装说明",
        x: 0, top: 440, width: 800, height: 24,
        size: 12, color: muted, align: .center
    )
    c.save("\(outDir)/background.png")
}

// ---------- 安装说明长图（1000 x 1400） ----------
// 正式安装说明现在使用设计稿 macos/installer/install-guide.png；
// 本脚本生成 install-guide-generated.png 作为旧版备份，避免覆盖正式说明。
do {
    let c = Canvas(w: 1000, h: 1400, top: .white, bottom: .white)
    let band = NSBezierPath(rect: c.rect(0, 0, 1000, 170))
    lightBlue.setFill()
    band.fill()

    c.logo(logoPath, x: 56, top: 34, size: 84)
    c.text(
        "Downie6",
        x: 164, top: 38, width: 780, height: 42,
        size: 32, bold: true
    )
    c.text(
        "安装与使用说明 · macOS 12.0 或更高版本",
        x: 164, top: 86, width: 780, height: 28,
        size: 16, color: darkGray
    )

    let steps: [(String, String, CGFloat)] = [
        (
            "把 Downie6 拖进「应用程序」",
            "双击打开下载的 Downie6.dmg，把右侧的 Downie6 图标拖到 Applications（应用程序）文件夹。",
            132
        ),
        (
            "首次打开被拦截：右键 → 打开",
            "如果提示「无法验证开发者」，在 Downie6 上点右键 → 打开；或到 系统设置 → 隐私与安全性 → 安全性，点「仍要打开」。",
            154
        ),
        (
            "提示「已损坏，无法打开」",
            "打开「终端」，输入 xattr -cr （末尾保留一个空格），把 Downie6.app 拖进终端窗口，回车执行，然后再打开应用。",
            186
        ),
        (
            "解析并下载",
            "打开 Downie6，粘贴视频链接，点「解析链接」，选择画质后点「下载」。B 站/抖音等走原生插件；需要登录的站点会弹登录窗口。",
            154
        ),
        (
            "网页嗅探",
            "任意网页里的视频：粘贴页面链接，点「网页嗅探」，在窗口里播放视频，选中捕获到的 m3u8/mpd/mp4 地址，点「使用此地址」再下载。",
            170
        ),
    ]

    var top: CGFloat = 206
    for (index, step) in steps.enumerated() {
        let height = step.2
        c.card(
            40, top, 920, height,
            fill: NSColor(calibratedWhite: 0.985, alpha: 1),
            stroke: softStroke
        )
        c.circle(64, top + 22, 44, color: blue)
        c.text(
            "\(index + 1)",
            x: 64, top: top + 29, width: 44, height: 30,
            size: 20, bold: true, color: .white, align: .center
        )
        c.text(
            step.0,
            x: 128, top: top + 18, width: 800, height: 30,
            size: 20, bold: true
        )
        c.text(
            step.1,
            x: 128, top: top + 54, width: 800, height: height - 64,
            size: 16, color: darkGray, lineSpacing: 7
        )
        top += height + 18
    }

    c.text(
        "提示：Downie6 不会绕过 DRM；Netflix 等受 DRM 保护的内容无法下载。",
        x: 48, top: 1110, width: 904, height: 28,
        size: 14, color: red
    )
    c.text(
        "支持邮箱：huoyongzhuang@qq.com",
        x: 0, top: 1160, width: 1000, height: 24,
        size: 13, color: muted, align: .center
    )
    c.text(
        "Downie6 · 官方安装包",
        x: 0, top: 1330, width: 1000, height: 24,
        size: 13, color: muted, align: .center
    )
    c.save("\(outDir)/install-guide-generated.png")
}

print("generated \(outDir)/background.png and \(outDir)/install-guide-generated.png")
