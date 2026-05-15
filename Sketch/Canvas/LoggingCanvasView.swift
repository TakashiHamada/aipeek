import UIKit
import PencilKit
import GameController
import CoreGraphics

/// PKCanvasView subclass that pins canvas.tool to a desiredTool we control,
/// shows a crosshair-shaped cursor while shift is held, and implements
/// Shift-to-snap straight-line drawing in real time:
///   - A CADisplayLink polls the global modifier-flag state at 60fps. When
///     shift goes down, drawingPolicy flips to .pencilOnly so PencilKit
///     stops responding to mouse input entirely.
///   - During the shift-held mouse drag, a CAShapeLayer preview line tracks
///     the cursor live, snapped to horizontal or vertical.
///   - On stroke end, the preview is removed and a clean dense-point stroke
///     is injected directly into `drawing`.
final class LoggingCanvasView: PKCanvasView, UIPointerInteractionDelegate {

    /// The currently desired tool.
    /// `.monoline` keeps stroke width constant — `.pen` modulates width by
    /// drawing speed which looks dramatic with mouse input.
    var desiredTool: PKTool = PKInkingTool(.monoline, color: .black, width: 3)

    /// True while a shift-snap stroke is in progress (between touchesBegan and
    /// touchesEnded). When true, touches are NOT forwarded to PencilKit.
    var shiftHeldForCurrentStroke: Bool = false

    private var shiftStrokeStart: CGPoint?
    /// Last cursor location seen while a shift-snap stroke is in flight. Used to
    /// commit the line when the user releases shift mid-drag.
    private var lastShiftCursor: CGPoint?
    /// True after a shift-snap stroke is committed because shift was released
    /// mid-drag. Suppresses the rest of the drag so PencilKit doesn't kick in
    /// with a free-hand stroke from the release point.
    private var ignoreRestOfDrag: Bool = false
    private var previewLayer: CAShapeLayer?
    private var displayLink: CADisplayLink?
    private var globalShiftDown: Bool = false

    /// Tracks the current mouse position so we can pin the shift-indicator
    /// crosshair to it.
    private var cursorLocation: CGPoint = .zero
    private var crosshairLayer: CALayer?
    private weak var pointerInteractionRef: UIPointerInteraction?

    /// While drawing with the red marker, the existing non-red strokes are
    /// rendered into this image view and placed *on top* of the canvas. The
    /// in-progress red stroke ends up visually beneath them — same effect as
    /// the post-stroke z-order reordering done by the coordinator, but live.
    private var blackStrokesOverlay: UIImageView?
    private var isInRedDrawingMode: Bool = false

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
            installHoverGestureIfNeeded()
            installPointerInteractionIfNeeded()
        } else {
            stopShiftPolling()
        }
    }

    private func installPointerInteractionIfNeeded() {
        guard pointerInteractionRef == nil else { return }
        let interaction = UIPointerInteraction(delegate: self)
        addInteraction(interaction)
        pointerInteractionRef = interaction
    }

    // MARK: UIPointerInteractionDelegate

    func pointerInteraction(_ interaction: UIPointerInteraction,
                            styleFor region: UIPointerRegion) -> UIPointerStyle? {
        // Hide the system pointer while shift is held — the crosshair
        // overlay layer takes over as the cursor.
        if globalShiftDown { return UIPointerStyle.hidden() }
        return nil
    }

    private var hoverRecognizer: UIHoverGestureRecognizer?

    private func installHoverGestureIfNeeded() {
        guard hoverRecognizer == nil else { return }
        let hover = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
        addGestureRecognizer(hover)
        hoverRecognizer = hover
    }

    @objc private func handleHover(_ recognizer: UIHoverGestureRecognizer) {
        cursorLocation = recognizer.location(in: self)
        if globalShiftDown {
            updateCrosshairPosition()
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
            showCrosshair()
            pointerInteractionRef?.invalidate()
        } else {
            // Shift released. If a shift-snap stroke is in progress, commit
            // it as a real stroke so the user doesn't lose what they drew.
            // The rest of the drag is then ignored.
            if shiftHeldForCurrentStroke,
               let start = shiftStrokeStart,
               let cursor = lastShiftCursor {
                let end = snapped(from: start, to: cursor)
                finishShiftStroke(from: start, to: end)
                ignoreRestOfDrag = true
            } else {
                // No active shift drag — just clean up.
                removePreviewLayer()
                shiftStrokeStart = nil
                lastShiftCursor = nil
                shiftHeldForCurrentStroke = false
            }
            drawingPolicy = .anyInput
            hideCrosshair()
            pointerInteractionRef?.invalidate()
        }
    }

    // MARK: - Touch handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        enforceDesiredTool()
        ignoreRestOfDrag = false
        if globalShiftDown,
           let touch = touches.first,
           let inking = desiredTool as? PKInkingTool {
            shiftHeldForCurrentStroke = true
            let start = touch.location(in: self)
            shiftStrokeStart = start
            lastShiftCursor = start
            showPreviewLayer(color: inking.color, width: inking.width)
            updatePreviewLayer(from: start, to: start)
            return
        }
        shiftHeldForCurrentStroke = false

        // Red marker: overlay existing non-red strokes on top of the canvas so
        // the in-progress red stroke ends up visually beneath them, mirroring
        // the z-order the coordinator will apply once the stroke finishes.
        if Self.isRedInkingTool(desiredTool) {
            showBlackStrokesOverlay()
            isInRedDrawingMode = true
        }

        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first {
            cursorLocation = touch.location(in: self)
            if globalShiftDown { updateCrosshairPosition() }
        }
        if ignoreRestOfDrag { return }
        if shiftHeldForCurrentStroke,
           let start = shiftStrokeStart,
           let touch = touches.first {
            let cur = touch.location(in: self)
            lastShiftCursor = cur
            let snapped = snapped(from: start, to: cur)
            updatePreviewLayer(from: start, to: snapped)
            return
        }
        super.touchesMoved(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if ignoreRestOfDrag {
            ignoreRestOfDrag = false
            return
        }
        if shiftHeldForCurrentStroke,
           let start = shiftStrokeStart,
           let touch = touches.first {
            let end = snapped(from: start, to: touch.location(in: self))
            finishShiftStroke(from: start, to: end)
            return
        }
        if isInRedDrawingMode {
            hideBlackStrokesOverlay()
            isInRedDrawingMode = false
        }
        super.touchesEnded(touches, with: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if ignoreRestOfDrag {
            ignoreRestOfDrag = false
            return
        }
        if shiftHeldForCurrentStroke {
            removePreviewLayer()
            shiftStrokeStart = nil
            lastShiftCursor = nil
            shiftHeldForCurrentStroke = false
            return
        }
        if isInRedDrawingMode {
            hideBlackStrokesOverlay()
            isInRedDrawingMode = false
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
        lastShiftCursor = nil
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

        // Temporarily relax drawingPolicy while assigning, in case PencilKit
        // rejects programmatic edits while in .pencilOnly mode.
        let savedPolicy = drawingPolicy
        drawingPolicy = .anyInput
        var newDrawing = drawing
        newDrawing.strokes.append(stroke)
        drawing = newDrawing
        drawingPolicy = savedPolicy
        setNeedsDisplay()
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

    // MARK: - Shift crosshair indicator

    /// The crosshair is centred exactly on the cursor (system pointer is
    /// hidden while shift is held, so the crosshair *is* the cursor).
    private static let crosshairOffset = CGSize(width: 0, height: 0)
    private static let crosshairSize: CGFloat = 22

    private func showCrosshair() {
        if crosshairLayer != nil { return }
        let layer = makeCrosshairLayer()
        self.layer.addSublayer(layer)
        crosshairLayer = layer
        updateCrosshairPosition()
    }

    private func hideCrosshair() {
        crosshairLayer?.removeFromSuperlayer()
        crosshairLayer = nil
    }

    private func updateCrosshairPosition() {
        guard let layer = crosshairLayer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.position = CGPoint(
            x: cursorLocation.x + Self.crosshairOffset.width,
            y: cursorLocation.y + Self.crosshairOffset.height
        )
        CATransaction.commit()
    }

    // MARK: - Red-marker overlay

    private func showBlackStrokesOverlay() {
        let nonRedStrokes = drawing.strokes.filter { !Self.isRedStroke($0) }
        guard !nonRedStrokes.isEmpty else { return }
        let bottomDrawing = PKDrawing(strokes: nonRedStrokes)
        let renderRect = CGRect(origin: .zero, size: bounds.size)
        let scale = window?.screen.scale ?? 2.0
        let image = bottomDrawing.image(from: renderRect, scale: scale)

        let iv = UIImageView(image: image)
        iv.frame = renderRect
        iv.isUserInteractionEnabled = false
        iv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(iv)
        blackStrokesOverlay = iv
    }

    private func hideBlackStrokesOverlay() {
        blackStrokesOverlay?.removeFromSuperview()
        blackStrokesOverlay = nil
    }

    static func isRedInkingTool(_ tool: PKTool) -> Bool {
        guard let inking = tool as? PKInkingTool else { return false }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        inking.color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return r > 0.85 && g < 0.25 && b < 0.25
    }

    static func isRedStroke(_ stroke: PKStroke) -> Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        stroke.ink.color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return r > 0.85 && g < 0.25 && b < 0.25
    }

    // MARK: - Crosshair helper

    private func makeCrosshairLayer() -> CALayer {
        let size = Self.crosshairSize
        let container = CALayer()
        container.bounds = CGRect(x: 0, y: 0, width: size, height: size)

        let strokeColor = (desiredTool as? PKInkingTool)?.color.cgColor ?? UIColor.black.cgColor
        let lineWidth: CGFloat = 1.6

        let hLine = CAShapeLayer()
        let hPath = UIBezierPath()
        hPath.move(to: CGPoint(x: 0, y: size / 2))
        hPath.addLine(to: CGPoint(x: size, y: size / 2))
        hLine.path = hPath.cgPath
        hLine.strokeColor = strokeColor
        hLine.lineWidth = lineWidth
        hLine.lineCap = .round

        let vLine = CAShapeLayer()
        let vPath = UIBezierPath()
        vPath.move(to: CGPoint(x: size / 2, y: 0))
        vPath.addLine(to: CGPoint(x: size / 2, y: size))
        vLine.path = vPath.cgPath
        vLine.strokeColor = strokeColor
        vLine.lineWidth = lineWidth
        vLine.lineCap = .round

        container.addSublayer(hLine)
        container.addSublayer(vLine)
        return container
    }
}
