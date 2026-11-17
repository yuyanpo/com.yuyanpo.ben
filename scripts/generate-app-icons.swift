import AppKit
import Foundation

// Build-time only: AppKit renders the original SVG directly at each output size.
// Keep reference/logo.svg untouched and put every derived asset in Assets.xcassets.
func generationError(_ message: String) -> NSError {
    NSError(domain: "Ben.IconGeneration", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}

// Match the blue tile in the design. Icon Composer uses this same sRGB color.
let iconBlue = NSColor(srgbRed: 51.0 / 255, green: 109.0 / 255,
                       blue: 250.0 / 255, alpha: 1)

func render(_ image: NSImage, pixels: Int, background: NSColor? = nil,
            roundedBackground: Bool = false, monochrome: Bool = false,
            insetPixels: Int = 0) throws -> NSBitmapImageRep {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw generationError("无法创建 \(pixels)px 图标画布")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let canvas = NSRect(x: 0, y: 0, width: pixels, height: pixels)
    NSColor.clear.setFill()
    canvas.fill(using: .copy)
    if let background {
        background.setFill()
        if roundedBackground {
            let radius = CGFloat(pixels) * 0.205
            NSBezierPath(roundedRect: canvas, xRadius: radius, yRadius: radius).fill()
        } else {
            canvas.fill()
        }
    }
    image.draw(in: canvas.insetBy(dx: CGFloat(insetPixels), dy: CGFloat(insetPixels)),
               from: .zero, operation: .sourceOver, fraction: 1)
    if monochrome {
        NSColor.black.setFill()
        canvas.fill(using: .sourceIn)
    }
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    return bitmap
}

func writePNG(_ bitmap: NSBitmapImageRep, to destination: URL) throws {
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw generationError("无法编码 PNG")
    }
    try png.write(to: destination, options: .atomic)
}

do {
    guard CommandLine.arguments.count == 2 else {
        throw generationError("用法：swift scripts/generate-app-icons.swift <仓库目录>")
    }
    let repo = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let source = repo.appendingPathComponent("reference/logo.svg")
    let assets = repo.appendingPathComponent("Ben/Resources/Assets.xcassets", isDirectory: true)
    let appIcons = assets.appendingPathComponent("AppIcon.appiconset", isDirectory: true)
    let brand = assets.appendingPathComponent("BrandMark.imageset", isDirectory: true)
    let menuBar = assets.appendingPathComponent("MenuBarMark.imageset", isDirectory: true)
    let systemIcon = assets.appendingPathComponent("BenIcon.icon", isDirectory: true)
    let systemIconAssets = systemIcon.appendingPathComponent("Assets", isDirectory: true)
    for directory in [appIcons, brand, menuBar, systemIconAssets] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    guard let logo = NSImage(contentsOf: source) else {
        throw generationError("无法读取 reference/logo.svg")
    }
    for pixels in [16, 32, 64, 128, 256, 512, 1024] {
        // Supply an opaque blue square. macOS applies its own icon mask;
        // transparent margins and a pre-rounded tile produce an extra frame.
        try writePNG(render(logo, pixels: pixels, background: iconBlue),
                     to: appIcons.appendingPathComponent("icon_\(pixels).png"))
    }
    try writePNG(render(logo, pixels: 1024, background: iconBlue, roundedBackground: true),
                 to: brand.appendingPathComponent("logo.png"))

    // reference/logo.svg is the complete transparent white foreground.
    let document = try XMLDocument(contentsOf: source, options: [])
    // A native Icon Composer document gives macOS the background and foreground
    // separately. This prevents the legacy PNG icon's additional gray frame.
    guard let foreground = document.rootElement()?.copy() as? XMLElement else {
        throw generationError("无法提取 App 图标前景")
    }
    for attribute in ["width", "height"] {
        foreground.removeAttribute(forName: attribute)
        foreground.addAttribute(XMLNode.attribute(withName: attribute, stringValue: "1024") as! XMLNode)
    }
    try Data(foreground.xmlString.utf8).write(
        to: systemIconAssets.appendingPathComponent("symbol.svg"), options: .atomic
    )
    let composition: [String: Any] = [
        "fill": ["solid": "extended-srgb:0.20000,0.42745,0.98039,1.00000"],
        "groups": [[
            "name": "Symbol",
            "layers": [["name": "Symbol", "image-name": "symbol.svg", "glass": false]],
            "shadow": ["kind": "none", "opacity": 0]
        ]],
        "supported-platforms": ["squares": ["macOS"]]
    ]
    try JSONSerialization.data(withJSONObject: composition, options: [.prettyPrinted, .sortedKeys])
        .write(to: systemIcon.appendingPathComponent("icon.json"), options: .atomic)

    // Find the visible bounds so the app icon's padding doesn't shrink the menu
    // bar mark. Keep only alpha: AppKit templates choose their own display color.
    let mask = try render(logo, pixels: 512)
    var minX = 512, minY = 512, maxX = -1, maxY = -1
    for y in 0..<512 {
        for x in 0..<512 where (mask.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0 {
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
        }
    }
    guard maxX >= minX, maxY >= minY else {
        throw generationError("Logo 没有可见前景")
    }
    guard let symbol = document.rootElement()?.copy() as? XMLElement,
          let viewBox = symbol.attribute(forName: "viewBox")?.stringValue?
            .split(whereSeparator: { $0.isWhitespace || $0 == "," }).compactMap({ Double($0) }),
          viewBox.count == 4 else {
        throw generationError("Logo 必须包含有效 viewBox")
    }
    let side = Double(max(maxX - minX + 1, maxY - minY + 1))
    let x = (Double(minX + maxX + 1) - side) / 2
    let y = (Double(minY + maxY + 1) - side) / 2
    let croppedViewBox = "\(viewBox[0] + x / 512 * viewBox[2]) \(viewBox[1] + y / 512 * viewBox[3]) \(side / 512 * viewBox[2]) \(side / 512 * viewBox[3])"
    for (name, value) in [("viewBox", croppedViewBox), ("width", "18"), ("height", "18")] {
        symbol.removeAttribute(forName: name)
        symbol.addAttribute(XMLNode.attribute(withName: name, stringValue: value) as! XMLNode)
    }
    guard let mark = NSImage(data: Data(symbol.xmlString.utf8)) else {
        throw generationError("无法渲染菜单栏 SVG")
    }
    for scale in [1, 2] {
        // Keep an 18pt canvas, with a 16pt symbol and 1pt padding on each edge.
        try writePNG(render(mark, pixels: 18 * scale, monochrome: true, insetPixels: scale),
                     to: menuBar.appendingPathComponent("mark_\(scale)x.png"))
    }
    print("已从 reference/logo.svg 生成蓝底 AppIcon（16–1024px）、BrandMark、Icon Composer 和透明菜单栏模板（18/36px）")
} catch {
    fputs("图标生成失败：\(error.localizedDescription)\n", stderr)
    exit(1)
}
