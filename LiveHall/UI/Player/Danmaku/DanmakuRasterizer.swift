import AppKit
import CoreText

struct RasterizedDanmaku: @unchecked Sendable {
    let image: CGImage
    let size: CGSize
}

struct DanmakuLook: Sendable, Equatable {
    let style: DanmakuSettings.Style
    let edgeWidth: CGFloat
    let typeface: DanmakuSettings.Typeface
    let weight: DanmakuSettings.Weight
    let fontSize: CGFloat

    init(_ settings: DanmakuSettings) {
        style = settings.style
        edgeWidth = CGFloat(settings.edgeWidth)
        typeface = settings.typeface
        weight = settings.weight
        fontSize = settings.fontSize.points
    }
}

actor DanmakuRasterizer {
    private static let cacheLimit = 256

    private var cache: [String: RasterizedDanmaku] = [:]
    private var cacheScale: CGFloat = 0
    private var cacheWeight: DanmakuSettings.Weight?
    private var cacheLook: DanmakuLook?

    func rasterize(_ messages: [DanmakuMessage], look: DanmakuLook, scale: CGFloat) -> [RasterizedDanmaku] {
        if scale != cacheScale || look != cacheLook {
            cache.removeAll()
            cacheScale = scale
            cacheLook = look
        }
        let font = look.typeface.font(size: look.fontSize, weight: look.weight)
        return messages.compactMap { message in
            if let cached = cache[message.text] { return cached }
            guard let item = rasterize(message.text, font: font, look: look, scale: scale) else { return nil }
            if cache.count >= Self.cacheLimit { cache.removeAll(keepingCapacity: true) }
            cache[message.text] = item
            return item
        }
    }

    private func rasterize(_ text: String, font: NSFont, look: DanmakuLook, scale: CGFloat)
        -> RasterizedDanmaku?
    {
        let trimmed = String(text.prefix(Theme.Danmaku.maxTextLength))
        let attributed = NSAttributedString(
            string: trimmed, attributes: [.font: font, .foregroundColor: NSColor.white])
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let textWidth = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
        let edgeWidth = look.edgeWidth
        let pad = ceil(ceil(edgeWidth) * 1.5 + 2)
        let size = CGSize(width: ceil(textWidth) + pad * 2, height: ceil(ascent + descent) + pad * 2)
        let pixelWidth = Int(ceil(size.width * scale))
        let pixelHeight = Int(ceil(size.height * scale))
        guard pixelWidth > 0, pixelHeight > 0,
            let context = CGContext(
                data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }

        context.scaleBy(x: scale, y: scale)
        let origin = CGPoint(x: pad, y: pad + descent)
        context.textPosition = origin
        switch look.style {
        case .outline:
            context.setLineJoin(.round)
            context.setLineWidth(edgeWidth)
            context.setStrokeColor(CGColor(gray: 0, alpha: 0.9))
            context.setTextDrawingMode(.stroke)
            CTLineDraw(line, context)
            context.textPosition = origin
        case .shadow:
            context.setShadow(
                offset: CGSize(width: 0, height: -edgeWidth / 2 * scale), blur: edgeWidth * scale,
                color: CGColor(gray: 0, alpha: 0.95))
        case .plain:
            break
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.setTextDrawingMode(.fill)
        CTLineDraw(line, context)

        guard let image = context.makeImage() else { return nil }
        return RasterizedDanmaku(image: image, size: size)
    }
}
