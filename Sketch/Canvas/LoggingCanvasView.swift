import UIKit
import PencilKit
import GameController
import CoreGraphics

/// `PKCanvasView` subclass that owns the drawing model for AIPeek's inking
/// tools (pen, red marker). Eraser is left to PencilKit's native handling.
///
/// **Single drawing model: drag = preview, touchesEnded = commit**
///
/// While the user is dragging with an inking tool, PencilKit is bypassed
/// entirely. We accumulate the drag into one or more `Segment`s and render
/// the live preview ourselves via a single `CAShapeLayer`. When the drag
/// ends, all segments are converted into a single `PKStroke` and appended
/// to `drawing`.
///
/// A drag can contain a mix of `freehand` and `line` segments. The boundary
/// between segments is whenever the shift key transitions (down ↔ up):
///   - shift goes DOWN → close the current freehand segment, start a new
///     `line` segment anchored at the current cursor position.
///   - shift goes UP   → close the current line segment (snapped end-point
///     becomes fixed), start a new `freehand` segment anchored at the
///     current cursor position.
///
/// The shift state is polled at 60fps via `CADisplayLink` (the only reliable
/// way to observe modifier-only key presses on Mac Catalyst — see `pollShift`).
///
/// This class also owns:
///   - **Tool pinning** — re-applies `desiredTool` whenever something else
///     tries to revert it.
///   - **Crosshair cursor** — while shift is held, hide the system pointer
///     and stamp a 22pt crosshair `CALayer` at the live cursor position.
///   - **Red-marker underlay** — rasterise the existing non-red strokes into
///     a `UIImageView` placed *above* the canvas, so the in-progress red
///     preview ends up visually beneath them. Mirrors the post-commit z-order
///     reordering done by `CanvasView.Coordinator.pushRedStrokesToBack`.
///
/// The class name "Logging" is a historical artefact from an early debugging
/// session — the class never logged anything. Renaming would touch a lot of
/// files; see refactor TODO in CLAUDE.md.
final class LoggingCanvasView: PKCanvasView, UIPointerInteractionDelegate {

    // MARK: - Tool

    /// The currently desired tool. Pen/eraser/etc. setters should update this.
    /// `.monoline` keeps stroke width constant; ink color is what
    /// `isRedInkingTool` keys on to enable the red-marker underlay.
    var desiredTool: PKTool = PKInkingTool(.monoline, color: .black, width: 3)

    // MARK: - Drag state (the new unified model)

    /// One slice of a drag. Drags are stored as `[Segment]`; the live preview
    /// and the eventual committed `PKStroke` are derived from this list.
    private struct Segment {
        let mode: SegmentMode
        /// First point of this segment. For `.line` this is the fixed start;
        /// for `.freehand` it's the first point and also `points.first`.
        let anchor: CGPoint
        /// For `.freehand`: the accumulated touch positions, starting with
        ///   `anchor`. Grows on every touchesMoved.
        /// For `.line` while it's the **current** segment: just `[anchor]`;
        ///   the end-point is computed live from `cursorLocation`.
        /// For `.line` after it's been closed (because shift transitioned):
        ///   `[anchor, snappedEnd]` — fixed two-point representation.
        var points: [CGPoint]
    }
    private enum SegmentMode { case freehand, line }

    private var dragSegments: [Segment] = []
    private var dragInProgress: Bool = false

    // MARK: - Shift state (owned by pollShift)

    private var displayLink: CADisplayLink?
    /// Live snapshot of the physical shift key, sampled by `pollShift`.
    private var globalShiftDown: Bool = false

    /// Read-only flag exposed to other code paths (e.g. the coordinator's
    /// reorder logic) so they can restore `drawingPolicy` correctly after a
    /// temporary `.anyInput` excursion.
    var isShiftPolicyActive: Bool { globalShiftDown }

    // MARK: - Misc layers

    /// Live drag preview. Rebuilt every `renderPreview()` from `dragSegments`.
    private var previewLayer: CAShapeLayer?

    /// Latest mouse position. Updated by `UIHoverGestureRecognizer` and on
    /// every touchesMoved. Used to position the crosshair and to compute the
    /// live end-point of the in-progress `.line` segment.
    private var cursorLocation: CGPoint = .zero
    private var crosshairLayer: CALayer?
    private weak var pointerInteractionRef: UIPointerInteraction?

    /// Image view used to simulate "red marker is drawn beneath the black
    /// strokes" during the drag. Holds a rasterised snapshot of the non-red
    /// portion of the drawing.
    private var nonRedStrokesOverlay: UIImageView?

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
            // Tear down any in-flight overlays / preview state — the canvas
            // is being detached and we don't want layers leaking into a
            // later re-attached window.
            cleanupDragState()
            hideCrosshair()
            globalShiftDown = false
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
            drawingPolicy = .pencilOnly
            showCrosshair()
        } else {
            drawingPolicy = .anyInput
            hideCrosshair()
        }
        pointerInteractionRef?.invalidate()

        // If a drag is in progress, switch segment mode immediately so the
        // preview tracks the new shift state.
        if dragInProgress { transitionSegment() }
    }

    // MARK: - Touch handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        enforceDesiredTool()
        guard let touch = touches.first else {
            super.touchesBegan(touches, with: event)
            return
        }

        // Eraser is delegated to PencilKit's native gesture system.
        if desiredTool is PKEraserTool {
            super.touchesBegan(touches, with: event)
            return
        }
        guard let inking = desiredTool as? PKInkingTool else {
            super.touchesBegan(touches, with: event)
            return
        }

        let start = touch.location(in: self)
        cursorLocation = start
        dragInProgress = true

        let mode: SegmentMode = globalShiftDown ? .line : .freehand
        dragSegments = [Segment(mode: mode, anchor: start, points: [start])]

        if Self.isRedInkingTool(desiredTool) {
            showNonRedStrokesOverlay()
        }

        showPreviewLayer(color: inking.color, width: inking.width)
        renderPreview()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first {
            cursorLocation = touch.location(in: self)
            if globalShiftDown { updateCrosshairPosition() }
        }
        guard dragInProgress, !dragSegments.isEmpty else {
            super.touchesMoved(touches, with: event)
            return
        }

        // For freehand, accumulate cursor positions; for line we don't store
        // anything — the end-point is derived from `cursorLocation`.
        let lastIdx = dragSegments.count - 1
        if dragSegments[lastIdx].mode == .freehand {
            dragSegments[lastIdx].points.append(cursorLocation)
        }
        renderPreview()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first { cursorLocation = touch.location(in: self) }
        guard dragInProgress else {
            super.touchesEnded(touches, with: event)
            return
        }
        finalizeDrag()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if dragInProgress {
            cleanupDragState()
            return
        }
        super.touchesCancelled(touches, with: event)
    }

    // MARK: - Segment transitions

    /// Called by `pollShift` when shift goes down or up mid-drag. Closes the
    /// current segment in its "fixed" form, then starts a new segment of the
    /// opposite mode anchored at the current cursor position.
    private func transitionSegment() {
        guard dragInProgress, !dragSegments.isEmpty else { return }
        let cursor = cursorLocation
        let idx = dragSegments.count - 1

        // 1. Close the current segment
        if dragSegments[idx].mode == .line {
            // Pin the line's end-point to the snapped cursor position.
            let end = snapped(from: dragSegments[idx].anchor, to: cursor)
            dragSegments[idx].points = [dragSegments[idx].anchor, end]
        }
        // freehand needs no closing — its points are already accumulated.

        // 2. Start a new segment anchored at the cursor, in the opposite mode.
        let newMode: SegmentMode = globalShiftDown ? .line : .freehand
        dragSegments.append(Segment(mode: newMode, anchor: cursor, points: [cursor]))

        renderPreview()
    }

    // MARK: - Preview rendering

    /// Rebuild the preview path from `dragSegments` and assign it to the
    /// `CAShapeLayer`. Cheap enough to call on every `touchesMoved` and on
    /// every shift transition (one allocation, no animation).
    ///
    /// **Preview policy**:
    ///   - While shift is held, preview shows ONLY the current line segment.
    ///     Any earlier freehand portion is hidden from preview (it still
    ///     exists in `dragSegments` and will be part of the committed stroke).
    ///   - While shift is not held, preview shows the full segment chain
    ///     (including any earlier line segment that has been closed).
    private func renderPreview() {
        guard let preview = previewLayer, !dragSegments.isEmpty else { return }
        let path = UIBezierPath()

        if globalShiftDown, let last = dragSegments.last, last.mode == .line {
            // Shift-held preview: just the current line segment.
            let end = snapped(from: last.anchor, to: cursorLocation)
            path.move(to: last.anchor)
            path.addLine(to: end)
        } else {
            // Full chain.
            let first = dragSegments[0]
            path.move(to: first.anchor)
            for (i, seg) in dragSegments.enumerated() {
                let isCurrent = (i == dragSegments.count - 1)
                switch seg.mode {
                case .line:
                    let end: CGPoint
                    if isCurrent {
                        end = snapped(from: seg.anchor, to: cursorLocation)
                    } else if seg.points.count >= 2 {
                        end = seg.points[1]
                    } else {
                        end = seg.anchor
                    }
                    path.addLine(to: end)
                case .freehand:
                    for p in seg.points.dropFirst() {
                        path.addLine(to: p)
                    }
                }
            }
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        preview.path = path.cgPath
        CATransaction.commit()
    }

    // MARK: - Commit

    private func finalizeDrag() {
        // Pin the last segment to its fixed form before committing.
        if let idx = dragSegments.indices.last {
            switch dragSegments[idx].mode {
            case .line:
                let end = snapped(from: dragSegments[idx].anchor, to: cursorLocation)
                dragSegments[idx].points = [dragSegments[idx].anchor, end]
            case .freehand:
                if dragSegments[idx].points.last != cursorLocation {
                    dragSegments[idx].points.append(cursorLocation)
                }
            }
        }

        let inking = desiredTool as? PKInkingTool
        let segments = dragSegments
        cleanupDragState()

        guard let inking, !segments.isEmpty else { return }

        // Flatten segments to a single list of locations.
        let locations = flattenSegmentsToPoints(segments)
        guard locations.count >= 2 else { return }

        let size = CGSize(width: inking.width, height: inking.width)
        let ink = PKInk(inking.inkType, color: inking.color)
        let strokePoints = locations.enumerated().map { i, p in
            PKStrokePoint(
                location: p,
                timeOffset: TimeInterval(i) * 0.01,
                size: size,
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        let stroke = PKStroke(
            ink: ink,
            path: PKStrokePath(controlPoints: strokePoints, creationDate: Date())
        )

        // Drop drawingPolicy to .anyInput just for the assignment so PencilKit
        // doesn't reject a programmatic edit while in .pencilOnly; restore
        // based on the *current* shift state, not a saved snapshot, because
        // pollShift may have transitioned between snapshot and restore.
        drawingPolicy = .anyInput
        var newDrawing = drawing
        newDrawing.strokes.append(stroke)
        drawing = newDrawing
        drawingPolicy = globalShiftDown ? .pencilOnly : .anyInput
        setNeedsDisplay()
    }

    /// Convert segment list to a flat point list. Line segments are densified
    /// (8pt spacing, 4–64 samples) so PencilKit renders them at the same
    /// thickness as the surrounding freehand portions.
    private func flattenSegmentsToPoints(_ segments: [Segment]) -> [CGPoint] {
        var out: [CGPoint] = []
        for (i, seg) in segments.enumerated() {
            switch seg.mode {
            case .line:
                guard seg.points.count == 2 else { continue }
                let a = seg.points[0], b = seg.points[1]
                let len = hypot(b.x - a.x, b.y - a.y)
                let count = min(64, max(4, Int(len / 8)))
                // Skip the first point if it duplicates the previous segment's
                // last point (consecutive segments share an endpoint).
                let startIndex = (i > 0 && !out.isEmpty && out.last == a) ? 1 : 0
                for k in startIndex...count {
                    let t = CGFloat(k) / CGFloat(count)
                    out.append(CGPoint(x: a.x + (b.x - a.x) * t,
                                       y: a.y + (b.y - a.y) * t))
                }
            case .freehand:
                let startIndex = (i > 0 && !out.isEmpty && out.last == seg.points.first) ? 1 : 0
                out.append(contentsOf: seg.points.dropFirst(startIndex))
            }
        }
        return out
    }

    private func cleanupDragState() {
        removePreviewLayer()
        hideNonRedStrokesOverlay()
        dragSegments = []
        dragInProgress = false
    }

    // MARK: - Snap helper

    private func snapped(from start: CGPoint, to current: CGPoint) -> CGPoint {
        let dx = abs(current.x - start.x)
        let dy = abs(current.y - start.y)
        return dx >= dy
            ? CGPoint(x: current.x, y: start.y)
            : CGPoint(x: start.x, y: current.y)
    }

    // MARK: - Preview layer

    private func showPreviewLayer(color: UIColor, width: CGFloat) {
        removePreviewLayer()
        let layer = CAShapeLayer()
        layer.strokeColor = color.cgColor
        layer.fillColor = UIColor.clear.cgColor
        // Raw tool width: preview and inject use the same value so they look
        // alike. Any discrepancy between CAShapeLayer and PKStroke rendering
        // is left as a small visual delta until empirical tuning is needed.
        layer.lineWidth = width
        layer.lineCap = .round
        layer.lineJoin = .round
        self.layer.addSublayer(layer)
        previewLayer = layer
    }

    private func removePreviewLayer() {
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
    }

    // MARK: - Shift crosshair indicator

    /// The crosshair is centred exactly on the cursor — the system pointer is
    /// hidden while shift is held, so the crosshair effectively *is* the cursor.
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
        layer.position = cursorLocation
        CATransaction.commit()
    }

    // MARK: - Red-marker overlay

    private func showNonRedStrokesOverlay() {
        // Skip if the canvas hasn't been laid out yet — rendering into a zero
        // rect would just produce a transparent image and add a useless view.
        guard !bounds.isEmpty else { return }
        let nonRedStrokes = drawing.strokes.filter { !Self.isRedStroke($0) }
        guard !nonRedStrokes.isEmpty else { return }
        let bottomDrawing = PKDrawing(strokes: nonRedStrokes)
        // Render against the visible viewport. PKCanvasView is a UIScrollView,
        // so honour the current contentOffset so the overlay aligns with the
        // underlying strokes if the user has scrolled.
        let renderRect = CGRect(origin: contentOffset, size: bounds.size)
        let scale = window?.screen.scale ?? 2.0
        let image = bottomDrawing.image(from: renderRect, scale: scale)

        let iv = UIImageView(image: image)
        iv.frame = CGRect(origin: contentOffset, size: bounds.size)
        iv.isUserInteractionEnabled = false
        iv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(iv)
        nonRedStrokesOverlay = iv
    }

    private func hideNonRedStrokesOverlay() {
        nonRedStrokesOverlay?.removeFromSuperview()
        nonRedStrokesOverlay = nil
    }

    static func isRedInkingTool(_ tool: PKTool) -> Bool {
        guard let inking = tool as? PKInkingTool else { return false }
        return isVermilionColor(inking.color)
    }

    static func isRedStroke(_ stroke: PKStroke) -> Bool {
        return isVermilionColor(stroke.ink.color)
    }

    /// Tolerant equality against `Theme.vermilionRedUI`. We compare against
    /// the single canonical red rather than using a broad RGB range, so other
    /// warm UI accents (terracotta r≈0.85, mustard r≈0.76) can never trigger
    /// a false positive — even if they drift across colour-space conversions.
    private static func isVermilionColor(_ color: UIColor) -> Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else { return false }
        var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 0
        guard Theme.vermilionRedUI.getRed(&tr, green: &tg, blue: &tb, alpha: &ta) else { return false }
        let dr = r - tr, dg = g - tg, db = b - tb
        // Allow ~0.06 per-channel drift to absorb sRGB ↔ extended sRGB / P3
        // round-trips, but still well clear of any other tone in Theme.
        return abs(dr) < 0.06 && abs(dg) < 0.06 && abs(db) < 0.06
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
