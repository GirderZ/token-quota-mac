import CoreGraphics

// 参考 B 方案：两条横向流线与三条竖向轨道，适合状态栏的小尺寸。
enum TokenGlyphGeometry {
    static func path(in rect: CGRect) -> CGPath {
        let strokes = CGMutablePath()
        strokes.move(to: CGPoint(x: 0, y: 28)); strokes.addLine(to: CGPoint(x: 155, y: 28))
        strokes.move(to: CGPoint(x: 185, y: 28)); strokes.addLine(to: CGPoint(x: 300, y: 28))
        strokes.addCurve(to: CGPoint(x: 500, y: 300), control1: CGPoint(x: 412, y: 28), control2: CGPoint(x: 500, y: 147))
        strokes.addLine(to: CGPoint(x: 500, y: 500))
        strokes.move(to: CGPoint(x: 500, y: 532)); strokes.addLine(to: CGPoint(x: 500, y: 850))
        strokes.move(to: CGPoint(x: 0, y: 124)); strokes.addLine(to: CGPoint(x: 300, y: 124))
        strokes.addCurve(to: CGPoint(x: 414, y: 320), control1: CGPoint(x: 390, y: 124), control2: CGPoint(x: 414, y: 240))
        strokes.addLine(to: CGPoint(x: 414, y: 850))
        strokes.move(to: CGPoint(x: 1000, y: 28)); strokes.addLine(to: CGPoint(x: 720, y: 28))
        strokes.addCurve(to: CGPoint(x: 462, y: 150), control1: CGPoint(x: 620, y: 28), control2: CGPoint(x: 560, y: 64))
        strokes.move(to: CGPoint(x: 1000, y: 124)); strokes.addLine(to: CGPoint(x: 850, y: 124))
        strokes.move(to: CGPoint(x: 818, y: 124)); strokes.addLine(to: CGPoint(x: 720, y: 124))
        strokes.addCurve(to: CGPoint(x: 586, y: 270), control1: CGPoint(x: 650, y: 124), control2: CGPoint(x: 586, y: 190))
        strokes.addLine(to: CGPoint(x: 586, y: 650))
        strokes.move(to: CGPoint(x: 586, y: 684)); strokes.addLine(to: CGPoint(x: 586, y: 850))
        let ink = strokes.copy(strokingWithWidth: 56, lineCap: .butt, lineJoin: .round, miterLimit: 4)
        // 先归一化原始轮廓；圆内的最终视觉位置统一由 glyphRect 决定。
        let bounds = ink.boundingBoxOfPath
        let scale = min(rect.width / bounds.width, rect.height / bounds.height)
        var transform = CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
            tx: rect.midX - bounds.midX * scale, ty: rect.midY - bounds.midY * scale)
        return ink.copy(using: &transform)!
    }
    static func glyphRect(in rect: CGRect) -> CGRect {
        // T 的横笔使重心偏上：略缩窄并向下补偿，避免小尺寸下看起来贴顶。
        rect.insetBy(dx: rect.width * 0.15, dy: rect.height * 0.16)
            .offsetBy(dx: 0, dy: rect.height * 0.075)
    }
    // 在独立透明层中清除 T 形，外部背景不会被擦除；模板图标可由系统自动反白。
    static func drawBadge(in context: CGContext, rect: CGRect, color: CGColor) {
        context.saveGState()
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.setFillColor(color)
        context.fillEllipse(in: rect)
        context.setBlendMode(.clear)
        context.addPath(path(in: glyphRect(in: rect)))
        context.fillPath()
        context.endTransparencyLayer()
        context.restoreGState()
    }
}
