import Cocoa

// 参考 B 方案生成圆底 T 形图标；状态栏使用真实透明镂空，应用图标为白色内底以适应 Finder 与 Dock。
let folder = CommandLine.arguments.dropFirst().first ?? "TokenBadge.iconset"
try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let transform = NSAffineTransform()
        transform.scale(by: CGFloat(pixels) / 1024)
        transform.concat()
        let context = NSGraphicsContext.current!.cgContext
        // 静态应用图标在圆形内部保留白底，防止 Dock 背景影响 T 的对比度。
        context.setFillColor(NSColor.white.cgColor)
        context.fillEllipse(in: CGRect(x: 60, y: 60, width: 904, height: 904))
        context.saveGState()
        context.translateBy(x: 0, y: 1024)
        context.scaleBy(x: 1, y: -1)
        TokenGlyphGeometry.drawBadge(in: context, rect: CGRect(x: 60, y: 60, width: 904, height: 904), color: NSColor.black.cgColor)
        context.restoreGState()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let path = URL(fileURLWithPath: folder).appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        try rep.representation(using: .png, properties: [:])!.write(to: path)
    }
}

// 输出透明菜单图标和深浅底预览，便于检查缩小时的辨识度。
for (pixels, dark, backdrop, filename) in [
    (36, false, false, "menu18-light@2x.png"), (36, true, false, "menu18-dark@2x.png"),
    (512, false, true, "badge-light.png"), (512, true, true, "badge-dark.png")
] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    if backdrop {
        context.setFillColor((dark ? NSColor(srgbRed: 0.13, green: 0.13, blue: 0.13, alpha: 1) : .white).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    }
    context.translateBy(x: 0, y: CGFloat(pixels)); context.scaleBy(x: 1, y: -1)
    let inset = backdrop ? CGFloat(pixels) * 0.08 : 1
    TokenGlyphGeometry.drawBadge(in: context, rect: CGRect(x: inset, y: inset, width: CGFloat(pixels) - inset * 2, height: CGFloat(pixels) - inset * 2), color: (dark ? NSColor.white : .black).cgColor)
    NSGraphicsContext.restoreGraphicsState()
    let output = URL(fileURLWithPath: folder).deletingLastPathComponent().appendingPathComponent(filename)
    try rep.representation(using: .png, properties: [:])!.write(to: output)
    if !backdrop {
        // 实底保持不透明；圆心附近应包含完全透明的 T 形区域。
        let solid = rep.colorAt(x: pixels / 2, y: 3)!.alphaComponent
        let cutout = (10..<26).flatMap { x in (10..<26).map { y in
            rep.colorAt(x: x, y: y)!.alphaComponent
        }}.min()!
        guard solid > 0.9, cutout < 0.1 else {
            fatalError("Badge alpha check failed: solid=\(solid), cutout=\(cutout)")
        }
    }
}
print("PASS: light/dark menu badges have opaque circles and transparent T cutouts")
