import SwiftUI
import PencilKit
import UIKit

struct CanvasView: UIViewRepresentable {
    @ObservedObject var controller: CanvasController

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .white
        canvas.isOpaque = true
        canvas.alwaysBounceVertical = false
        canvas.alwaysBounceHorizontal = false
        canvas.minimumZoomScale = 1.0
        canvas.maximumZoomScale = 1.0

        controller.bind(canvas)

        DispatchQueue.main.async {
            ToolPickerCoordinator.shared.attach(to: canvas)
        }

        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        // No-op: drawing state is owned by the canvas itself; controller drives it imperatively.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let controller: CanvasController

        init(controller: CanvasController) {
            self.controller = controller
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            controller.refreshIsEmpty()
        }
    }
}
