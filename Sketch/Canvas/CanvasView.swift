import SwiftUI
import PencilKit
import UIKit

struct CanvasView: UIViewRepresentable {
    @ObservedObject var controller: CanvasController

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = LoggingCanvasView()
        canvas.delegate = context.coordinator
        canvas.drawingPolicy = .anyInput
        // The canvas MUST be opaque. PKInkingTool(.pen) uses a multiply-style
        // blend; on a transparent canvas, black strokes multiply-blend with clear
        // pixels and disappear (colored strokes still show because of hue).
        // Use the same off-white as the exported PNG so what-you-see-is-what-you-save.
        canvas.backgroundColor = DrawingRenderer.canvasBackground
        canvas.isOpaque = true
        canvas.overrideUserInterfaceStyle = .light
        canvas.alwaysBounceVertical = false
        canvas.alwaysBounceHorizontal = false
        canvas.minimumZoomScale = 1.0
        canvas.maximumZoomScale = 1.0

        controller.bind(canvas)

        applyInitialToolWhenReady(canvas: canvas, attempt: 0)

        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        // No-op: drawing state is owned by the canvas itself.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    /// On Mac Catalyst, the canvas needs to be in a window before becomeFirstResponder
    /// and the initial tool assignment will engage the drawing pipeline.
    private func applyInitialToolWhenReady(canvas: PKCanvasView, attempt: Int) {
        DispatchQueue.main.async {
            if canvas.window != nil {
                canvas.setNeedsLayout()
                canvas.layoutIfNeeded()
                _ = canvas.becomeFirstResponder()
                // Do NOT attach PKToolPicker — on Mac Catalyst it has no visible UI and
                // its observer overwrites canvas.tool with its own default. Drawing tool
                // is governed by LoggingCanvasView.desiredTool instead.
                if let logging = canvas as? LoggingCanvasView {
                    canvas.tool = logging.desiredTool
                }
            } else if attempt < 30 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    applyInitialToolWhenReady(canvas: canvas, attempt: attempt + 1)
                }
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let controller: CanvasController

        init(controller: CanvasController) {
            self.controller = controller
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            controller.handleDrawingChange()
        }
    }
}
