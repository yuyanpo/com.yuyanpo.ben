import AppKit
import Foundation

// Build-time only: AppKit renders the original SVG directly at each output size.
// Keep reference/logo.svg untouched and put every derived asset in Assets.xcassets.
func generationError(_ message: String) -> NSError {
    NSError(domain: "Ben.IconGeneration", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}

func render(_ image: NSImage, pixels: Int, insetFraction: CGFloat = 0,
            whiteBackground: Bool = false, to destination: URL) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: whiteBackground ? 3 : 4,
        hasAlpha: !whiteBackground, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw generationError("无法创建 \(pixels)px 图标画布")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let canvas = NSRect(x: 0, y: 0, width: pixels, height: pixels)
    (whiteBackground ? NSColor.white : NSColor.clear).setFill()
    canvas.fill(using: .copy)
    let inset = (CGFloat(pixels) * insetFraction).rounded()
    image.draw(in: canvas.insetBy(dx: inset, dy: inset),
               from: .zero, operation: .sourceOver, fraction: 1)
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw generationError("无法编码 \(pixels)px PNG")
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
        // Supply an opaque white square. macOS applies its own icon mask;
        // transparent margins and a pre-rounded tile produce an extra frame.
        try render(logo, pixels: pixels, whiteBackground: true,
                   to: appIcons.appendingPathComponent("icon_\(pixels).png"))
    }
    try render(logo, pixels: 1024, insetFraction: 100.0 / 1024,
               to: brand.appendingPathComponent("logo.png"))

    // The supplied SVG places its foreground symbol in a nested SVG. Extract that
    // vector, excluding the white tile, for a transparent monochrome template.
    let document = try XMLDocument(contentsOf: source, options: [])
    // A native Icon Composer document gives macOS the background and foreground
    // separately. This prevents the legacy PNG icon's additional gray frame.
    guard let foreground = document.rootElement()?.copy() as? XMLElement else {
        throw generationError("无法提取 App 图标前景")
    }
    for child in foreground.children ?? [] {
        if let element = child as? XMLElement, element.localName != "svg" {
            element.detach()
        }
    }
    for attribute in ["width", "height"] {
        foreground.removeAttribute(forName: attribute)
        foreground.addAttribute(XMLNode.attribute(withName: attribute, stringValue: "1024") as! XMLNode)
    }
    try Data(foreground.xmlString.utf8).write(
        to: systemIconAssets.appendingPathComponent("symbol.svg"), options: .atomic
    )
    let composition: [String: Any] = [
        "fill": ["solid": "extended-srgb:1.00000,1.00000,1.00000,1.00000"],
        "groups": [[
            "name": "Symbol",
            "layers": [["name": "Symbol", "image-name": "symbol.svg", "glass": false]],
            "shadow": ["kind": "none", "opacity": 0]
        ]],
        "supported-platforms": ["squares": ["macOS"]]
    ]
    try JSONSerialization.data(withJSONObject: composition, options: [.prettyPrinted, .sortedKeys])
        .write(to: systemIcon.appendingPathComponent("icon.json"), options: .atomic)

    guard let symbol = document.rootElement()?.children?
        .compactMap({ $0 as? XMLElement })
        .first(where: { $0.localName == "svg" })?.copy() as? XMLElement,
        symbol.attribute(forName: "viewBox") != nil else {
        throw generationError("Logo 必须包含带 viewBox 的前景 SVG，以便生成菜单栏符号")
    }
    for attribute in ["x", "y", "width", "height", "style", "alignment-baseline"] {
        symbol.removeAttribute(forName: attribute)
    }
    symbol.addAttribute(XMLNode.attribute(withName: "width", stringValue: "18") as! XMLNode)
    symbol.addAttribute(XMLNode.attribute(withName: "height", stringValue: "18") as! XMLNode)
    symbol.addAttribute(XMLNode.attribute(withName: "color", stringValue: "#000000") as! XMLNode)
    let symbolData = Data(symbol.xmlString.utf8)
    guard let mark = NSImage(data: symbolData) else {
        throw generationError("无法渲染菜单栏 SVG")
    }
    for scale in [1, 2] {
        try render(mark, pixels: 18 * scale,
                   to: menuBar.appendingPathComponent("mark_\(scale)x.png"))
    }
    print("已从 reference/logo.svg 生成 AppIcon（16–1024px）、BrandMark 和菜单栏模板（18/36px）")
} catch {
    fputs("图标生成失败：\(error.localizedDescription)\n", stderr)
    exit(1)
}
