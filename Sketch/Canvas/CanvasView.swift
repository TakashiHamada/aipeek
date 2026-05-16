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

    /// On Mac Catalyst, the canvas needs to be in a window before
    /// becomeFirstResponder and the initial tool assignment will engage the
    /// drawing pipeline. Retries every 50ms up to ~1.5s.
    /// The canvas is captured weakly so a transient view reload doesn't keep
    /// it alive past its useful life.
    private func applyInitialToolWhenReady(canvas: PKCanvasView, attempt: Int) {
        DispatchQueue.main.async { [weak canvas] in
            guard let canvas else { return }
            if canvas.window != nil {
                canvas.setNeedsLayout()
                canvas.layoutIfNeeded()
                _ = canvas.becomeFirstResponder()
                // Do NOT attach PKToolPicker — on Mac Catalyst it has no
                // visible UI and its observer overwrites canvas.tool with its
                // own default. Drawing tool is governed by
                // LoggingCanvasView.desiredTool instead.
                if let logging = canvas as? LoggingCanvasView {
                    canvas.tool = logging.desiredTool
                }
            } else if attempt < 30 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak canvas] in
                    guard let canvas else { return }
                    applyInitialToolWhenReady(canvas: canvas, attempt: attempt + 1)
                }
            }
        }
    }

    /// PKCanvasViewDelegate adapter. Two responsibilities:
    ///   1. Forward drawing-change notifications to `CanvasController`
    ///      (which triggers debounced auto-save).
    ///   2. Maintain stroke z-order so that "red marker" strokes always sit
    ///      below other strokes — this is what gives the red marker its
    ///      multiply-with-black look once a stroke is committed.
    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let controller: CanvasController
        /// Reentrancy guard: assigning `.drawing` inside drawingDidChange
        /// re-fires drawingDidChange synchronously. Without this flag the
        /// reorder logic would recurse on its own write.
        private var isReorderingStrokes = false

        init(controller: CanvasController) {
            self.controller = controller
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            if !isReorderingStrokes {
                pushRedStrokesToBack(in: canvasView)
            }
            controller.handleDrawingChange()
        }

        /// Keep all "red marker" strokes at the BOTTOM of the drawing stack
        /// (i.e. drawn first, behind every other stroke). Effect: drawing a
        /// red stroke over a black one leaves the black on top — same visual
        /// outcome as a multiply blend.
        private func pushRedStrokesToBack(in canvas: PKCanvasView) {
            let strokes = canvas.drawing.strokes
            guard strokes.count >= 2 else { return }

            // Only act if at least one red stroke appears AFTER a non-red one.
            var needsReorder = false
            var sawNonRed = false
            for s in strokes {
                if Self.isRedStroke(s) {
                    if sawNonRed { needsReorder = true; break }
                } else {
                    sawNonRed = true
                }
            }
            guard needsReorder else { return }

            // Stable partition: reds first, others after.
            var reds: [PKStroke] = []
            var others: [PKStroke] = []
            reds.reserveCapacity(strokes.count)
            others.reserveCapacity(strokes.count)
            for s in strokes {
                if Self.isRedStroke(s) {
                    reds.append(s)
                } else {
                    others.append(s)
                }
            }
            var newDrawing = canvas.drawing
            newDrawing.strokes = reds + others

            // Avoid drawing-policy related rejection that can happen while
            // shift is held (LoggingCanvasView pins .pencilOnly there).
            // Restore the policy by consulting the canvas's live shift state
            // rather than a snapshot — pollShift may have transitioned between
            // the snapshot and the restore.
            canvas.drawingPolicy = .anyInput
            isReorderingStrokes = true
            canvas.drawing = newDrawing
            isReorderingStrokes = false
            let shiftActive = (canvas as? LoggingCanvasView)?.isShiftPolicyActive ?? false
            canvas.drawingPolicy = shiftActive ? .pencilOnly : .anyInput
        }

        private static func isRedStroke(_ stroke: PKStroke) -> Bool {
            return LoggingCanvasView.isRedStroke(stroke)
        }
    }
}
