import UIKit
import PencilKit

enum DrawingRenderer {
    static let margin: CGFloat = 20
    static let scale: CGFloat = 2.0
    /// JPEG compression quality. 0.9 is visually lossless for sketches and
    /// keeps file sizes small.
    static let jpegQuality: CGFloat = 0.9
    /// Canvas/background color. Same for live canvas and exported image so
    /// what you see matches what you save. Lives in Theme so the whole app stays in sync.
    static var canvasBackground: UIColor { Theme.canvasBackgroundUI }

    enum RenderError: Error {
        case emptyDrawing
        case encodingFailed
    }

    /// Returns true if the drawing has no visible content.
    static func isEmpty(_ drawing: PKDrawing) -> Bool {
        let bounds = drawing.bounds
        return bounds.isNull || bounds.isEmpty || bounds.size == .zero
    }

    /// Render the drawing into a UIImage with the canvas background color and a fixed margin.
    ///
    /// `PKDrawing.image(from:scale:)` rasterizes against `UITraitCollection.current`,
    /// and on macOS when the system is in dark mode PencilKit auto-inverts ink
    /// colors (`.black` → `.white`). The live canvas is pinned to light via
    /// `preferredColorScheme(.light)`, but offscreen rasterization doesn't
    /// inherit that, so the exported JPEG ends up with white strokes on a
    /// background that's still the off-white canvas color. Wrap the call in
    /// a light trait collection so the export matches what the user sees.
    static func render(drawing: PKDrawing) throws -> UIImage {
        guard !isEmpty(drawing) else { throw RenderError.emptyDrawing }

        let expanded = drawing.bounds.insetBy(dx: -margin, dy: -margin)
        // Declared as `var` with a placeholder; populated inside the trait
        // block below. `UITraitCollection.performAsCurrent` returns `Void`
        // (no value forwarding from the closure), so we capture the result
        // through the outer variable instead.
        var drawingImage = UIImage()
        let lightTraits = UITraitCollection(userInterfaceStyle: .light)
        lightTraits.performAsCurrent {
            drawingImage = drawing.image(from: expanded, scale: scale)
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = true
        format.preferredRange = .standard

        let renderer = UIGraphicsImageRenderer(size: expanded.size, format: format)
        return renderer.image { ctx in
            canvasBackground.setFill()
            ctx.fill(CGRect(origin: .zero, size: expanded.size))
            drawingImage.draw(in: CGRect(origin: .zero, size: expanded.size))
        }
    }

    /// Render and return JPEG data.
    static func renderJPEG(drawing: PKDrawing) throws -> Data {
        let image = try render(drawing: drawing)
        guard let data = image.jpegData(compressionQuality: jpegQuality) else {
            throw RenderError.encodingFailed
        }
        return data
    }
}
