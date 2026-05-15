import UIKit
import PencilKit
import GameController
import CoreGraphics

/// PKCanvasView subclass that pins canvas.tool to a desiredTool we control and
/// implements Shift-to-snap straight-line drawing in real time:
///   - A CADisplayLink polls the global modifier-flag state at 60fps. When
///     shift goes down, drawingPolicy flips to .pencilOnly so PencilKit
///     stops responding to mouse input entirely.
///   - During the shift-held mouse drag, a CAShapeLayer preview line tracks
///     the cursor live, snapped to horizontal or vertical.
///   - On stroke end, the preview is removed and a clean dense-point stroke
///     is injected directly into `drawing`.
final class LoggingCanvasView: PKCanvasView {

    /// The currently desired tool.
    /// `.monoline` keeps stroke width constant — `.pen` modulates width by
    /// drawing speed which looks dramatic with mouse input.
    var desiredTool: PKTool = PKInkingTool(.monoline, color: .black, width: 3)

    /// True while a shift-snap stroke is in progress (between touchesBegan and
    /// touchesEnded). When true, touches are NOT forwarded to PencilKit.
    var shiftHeldForCurrentStroke: Bool = false

    private var shiftStrokeStart: CGPoint?
    private var previewLayer: CAShapeLayer?
    private var displayLink: CADisplayLink?
    private var globalShiftDown: Bool = false

    /// Renders should look the same thickness as a free-hand stroke. With
    /// monoline, the size value lands at roughly half the visual width once
    /// PencilKit rasterizes it, so we double it.
    private static let strokeWidthBoost: CGFloat = 2.0

    // MARK: - Lifecycle

    override var canBecomeFirstResponder: Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            startShiftPolling()
        } else {
            stopShiftPolling()
        }
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

    // MARK: - Shift polling

    private func startShiftPolling() {
        stopShiftPolling()
        let link = CADisplayLink(target: self, selector: #selector(pollShift))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopShiftPolling() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func pollShift() {
        let isShiftDown = CGEventSource.flagsState(.combinedSessionState).contains(.maskShift)
        guard isShiftDown != globalShiftDown else { return }
        globalShiftDown = isShiftDown
        if isShiftDown {
            // Prevent PencilKit from responding to any mouse touch while
            // shift is held — we take over drawing.
            drawingPolicy = .pencilOnly
        } else {
            drawingPolicy = .anyInput
            // If shift was released mid-stroke, drop any in-flight preview.
            if shiftHeldForCurrentStroke {
                removePreviewLayer()
                shiftStrokeStart = nil
                shiftHeldForCurrentStroke = false
            }
        }
    }

    // MARK: - Touch handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        enforceDesiredTool()
        if globalShiftDown,
           let touch = touches.first,
           let inking = desiredTool as? PKInkingTool {
            shiftHeldForCurrentStroke = true
            let start = touch.location(in: self)
            shiftStrokeStart = start
            showPreviewLayer(color: inking.color, width: inking.width)
            updatePreviewLayer(from: start, to: start)
            return
        }
        shiftHeldForCurrentStroke = false
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if shiftHeldForCurrentStroke,
           let start = shiftStrokeStart,
           let touch = touches.first {
            let snapped = snapped(from: start, to: touch.location(in: self))
            updatePreviewLayer(from: start, to: snapped)
            return
        }
        super.touchesMoved(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if shiftHeldForCurrentStroke,
           let start = shiftStrokeStart,
           let touch = touches.first {
            let end = snapped(from: start, to: touch.location(in: self))
            finishShiftStroke(from: start, to: end)
            return
        }
        super.touchesEnded(touches, with: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if shiftHeldForCurrentStroke {
            removePreviewLayer()
            shiftStrokeStart = nil
            shiftHeldForCurrentStroke = false
            return
        }
        super.touchesCancelled(touches, with: event)
    }

    private func snapped(from start: CGPoint, to current: CGPoint) -> CGPoint {
        let dx = abs(current.x - start.x)
        let dy = abs(current.y - start.y)
        return dx >= dy
            ? CGPoint(x: current.x, y: start.y)
            : CGPoint(x: start.x, y: current.y)
    }

    private func finishShiftStroke(from start: CGPoint, to end: CGPoint) {
        removePreviewLayer()
        shiftStrokeStart = nil
        shiftHeldForCurrentStroke = false

        // Don't write degenerate "tap with no movement" strokes.
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 4 else { return }

        guard let inking = desiredTool as? PKInkingTool else { return }
        let ink = PKInk(inking.inkType, color: inking.color)
        let renderWidth = inking.width * Self.strokeWidthBoost
        let size = CGSize(width: renderWidth, height: renderWidth)

        let length = sqrt(lengthSquared)
        let segments = max(4, Int(length / 4))
        var points: [PKStrokePoint] = []
        points.reserveCapacity(segments + 1)
        for i in 0...segments {
            let t = CGFloat(i) / CGFloat(segments)
            let location = CGPoint(
                x: start.x + dx * t,
                y: start.y + dy * t
            )
            points.append(PKStrokePoint(
                location: location,
                timeOffset: TimeInterval(i) * 0.01,
                size: size,
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            ))
        }
        let path = PKStrokePath(controlPoints: points, creationDate: Date())
        let stroke = PKStroke(ink: ink, path: path)

        var newDrawing = drawing
        newDrawing.strokes.append(stroke)
        drawing = newDrawing
    }

    // MARK: - Preview layer

    private func showPreviewLayer(color: UIColor, width: CGFloat) {
        removePreviewLayer()
        let layer = CAShapeLayer()
        layer.strokeColor = color.cgColor
        layer.fillColor = UIColor.clear.cgColor
        // Visually match a finished stroke (PencilKit's monoline renders a bit
        // wider than its declared width).
        layer.lineWidth = width * Self.strokeWidthBoost
        layer.lineCap = .round
        layer.lineJoin = .round
        self.layer.addSublayer(layer)
        previewLayer = layer
    }

    private func updatePreviewLayer(from start: CGPoint, to end: CGPoint) {
        guard let preview = previewLayer else { return }
        let path = UIBezierPath()
        path.move(to: start)
        path.addLine(to: end)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        preview.path = path.cgPath
        CATransaction.commit()
    }

    private func removePreviewLayer() {
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
    }
}
