import UIKit
import PencilKit

enum DrawingRenderer {
    static let margin: CGFloat = 20
    static let scale: CGFloat = 2.0

    enum RenderError: Error {
        case emptyDrawing
        case pngEncodingFailed
    }

    /// Returns true if the drawing has no visible content.
    static func isEmpty(_ drawing: PKDrawing) -> Bool {
        let bounds = drawing.bounds
        return bounds.isNull || bounds.isEmpty || bounds.size == .zero
    }

    /// Render the drawing into a UIImage with a white background and a fixed margin.
    static func render(drawing: PKDrawing) throws -> UIImage {
        guard !isEmpty(drawing) else { throw RenderError.emptyDrawing }

        let expanded = drawing.bounds.insetBy(dx: -margin, dy: -margin)
        let drawingImage = drawing.image(from: expanded, scale: scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = true
        format.preferredRange = .standard

        let renderer = UIGraphicsImageRenderer(size: expanded.size, format: format)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: expanded.size))
            drawingImage.draw(in: CGRect(origin: .zero, size: expanded.size))
        }
    }

    /// Convenience: render and return PNG data.
    static func renderPNG(drawing: PKDrawing) throws -> Data {
        let image = try render(drawing: drawing)
        guard let data = image.pngData() else {
            throw RenderError.pngEncodingFailed
        }
        return data
    }
}
