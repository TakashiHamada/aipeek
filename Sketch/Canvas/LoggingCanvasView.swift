import UIKit
import PencilKit

/// PKCanvasView subclass that pins canvas.tool to a desiredTool we control.
///
/// On Mac Catalyst, the system shared PKToolPicker (or some other mechanism)
/// periodically resets canvas.tool to a default PKInkingTool(.pen) with width ≈ 2.68
/// regardless of what we set. That default tool is essentially invisible with mouse
/// input because Catalyst's indirect-pointer touches report force = 0 and PKInkingTool
/// modulates stroke width by force. We override touchesBegan and layoutSubviews to
/// re-assert the tool we actually want.
final class LoggingCanvasView: PKCanvasView {

    /// The currently desired tool. Pen/eraser/etc. setters should update this.
    var desiredTool: PKTool = PKInkingTool(.pen, color: .black, width: 10)

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        enforceDesiredTool()
        super.touchesBegan(touches, with: event)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        enforceDesiredTool()
    }

    private func enforceDesiredTool() {
        if let want = desiredTool as? PKInkingTool,
           let cur = tool as? PKInkingTool,
           cur.inkType == want.inkType,
           cur.color == want.color,
           abs(cur.width - want.width) < 0.5 {
            return
        }
        if desiredTool is PKEraserTool, tool is PKEraserTool {
            return
        }
        tool = desiredTool
    }
}
