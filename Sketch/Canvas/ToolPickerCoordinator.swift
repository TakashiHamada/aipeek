import UIKit
import PencilKit

/// Holds a single PKToolPicker for the app lifetime and wires it up to a canvas.
final class ToolPickerCoordinator {
    static let shared = ToolPickerCoordinator()

    let toolPicker: PKToolPicker

    private init() {
        self.toolPicker = PKToolPicker()
    }

    func attach(to canvas: PKCanvasView) {
        toolPicker.setVisible(true, forFirstResponder: canvas)
        toolPicker.addObserver(canvas)
        if !canvas.isFirstResponder {
            canvas.becomeFirstResponder()
        }
    }

    func detach(from canvas: PKCanvasView) {
        toolPicker.setVisible(false, forFirstResponder: canvas)
        toolPicker.removeObserver(canvas)
    }
}
