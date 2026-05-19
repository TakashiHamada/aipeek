import UIKit
import PencilKit
import GameController
import CoreGraphics

/// `PKCanvasView` subclass that owns the drawing model for AIPeek's inking
/// tools (pen, red marker). Eraser is left to PencilKit's native handling.
///
/// > Historical note — the class name "Logging" comes from an early
/// > debugging session and the class never logged anything. Renaming would
/// > touch many files; see refactor TODO in CLAUDE.md.
///
/// **Single drawing model: drag = preview, touchesEnded = commit**
///
/// While the user is dragging with an inking tool, PencilKit is bypassed
/// entirely. We accumulate the drag into one or more `Segment`s and render
/// the live preview ourselves via a single `CAShapeLayer`. When the drag
/// ends, all segments are converted into a single `PKStroke` and appended
/// to `drawing`.
///
/// **How PencilKit is bypassed**: `hitTest(_:with:)` returns `self` while an
/// inking tool is active, so the touch never resolves to a PencilKit
/// subview (`PKTiledGestureView`, `PKCanvasAttachmentView`, ...). That
/// blocks both their gesture recognizers AND their UIResponder-based touch
/// handlers — the latter is what setups not using `.pencilOnly` previously
/// couldn't suppress, and what produced the parallel live-stroke preview
/// during Shift-line. Eraser falls through to `super.hitTest` so PencilKit's
/// native gesture pipeline can run (see `touchesBegan`).
///
/// A drag can contain a mix of `freehand` and `line` segments. The boundary
/// between segments is whenever the shift key transitions (down ↔ up):
///   - shift goes DOWN → close the current freehand segment, start a new
///     `line` segment anchored at the current cursor position.
///   - shift goes UP   → close the current line segment (snapped end-point
///     becomes fixed), start a new `freehand` segment anchored at the
///     **snapped end-point** (so the join is exact; see `transitionSegment`).
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
final class LoggingCanvasView: PKCanvasView, UIPointerInteractionDelegate {

    // MARK: - Tool

    /// The currently desired tool. Pen/eraser/etc. setters should update this.
    /// `.monoline` keeps stroke width constant; ink color is what
    /// `isRedInkingTool` keys on to enable the red-marker underlay.
    /// PencilKit suppression for inking touches is handled by the
    /// `hitTest(_:with:)` override — no per-tool gesture toggling needed.
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

    // MARK: - Misc layers

    /// Live drag preview. Rebuilt every `renderPreview()` from `dragSegments`.
    private var previewLayer: CAShapeLayer?

    /// Width calibration for the live preview (CAShapeLayer) and the
    /// committed PKStroke. Three empirically-tuned multipliers reconcile two
    /// rendering paths so what the user sees during the drag matches the
    /// final stroke; they're collected here so the relationship stays
    /// auditable. Use `preview(rawWidth:)` and `commit(rawWidth:isRed:)` —
    /// callers should never multiply individual constants by hand.
    private enum WidthCalibration {
        /// Base factor applied to BOTH paths. PencilKit's `.monoline`
        /// rasteriser renders a `PKStrokePoint(size: W)` at roughly W/2
        /// visual width, so doubling brings rendered thickness back up to
        /// the user-facing "N pt" expectation.
        static let base: CGFloat = 2.0

        /// Extra multiplier on the preview only. CAShapeLayer's geometric
        /// stroke comes out ~10% thinner than `.monoline` at the same
        /// numeric width.
        static let previewBoost: CGFloat = 1.15

        /// Multiplier applied to the *committed* red marker only. The
        /// vermilion red rasterises ~35% bolder than black at the same
        /// numeric width (colour-dependent anti-aliasing). Calibrated at
        /// @2x against the default pen (3pt) and red marker (14pt) — revisit
        /// if base widths or PencilKit's rasteriser change.
        static let redCommitScale: CGFloat = 0.65

        /// Width to feed `CAShapeLayer.lineWidth` for the live preview.
        static func preview(rawWidth: CGFloat) -> CGFloat {
            return rawWidth * base * previewBoost
        }

        /// Width to feed `PKStrokePoint.size` at commit time.
        static func commit(rawWidth: CGFloat, isRed: Bool) -> CGFloat {
            return rawWidth * base * (isRed ? redCommitScale : 1)
        }
    }

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

    // MARK: - PencilKit suppression (inking only)

    /// Claim every inking-tool touch at the canvas level. Returning `self`
    /// stops hit-testing from descending into PencilKit's private subviews
    /// (`PKTiledGestureView`, `PKCanvasAttachmentView`, …), which would
    /// otherwise dispatch the touch to their own UIResponder handlers AND
    /// gesture recognizers — both of which render a parallel live freehand
    /// stroke on top of our `previewLayer`. The duplicate is most visible
    /// during Shift-line, where our snapped line and PencilKit's unsnapped
    /// freehand show simultaneously. (Disabling `PKDrawingGestureRecognizer`
    /// alone wasn't enough because the responder route bypasses the gesture
    /// state machine; `drawingPolicy = .pencilOnly` would suppress both but
    /// causes existing strokes to disappear on the next non-pencil touch —
    /// see CLAUDE.md → 重要な設計判断 → `drawingPolicy`.)
    ///
    /// **Side effect**: while an inking tool is active, *any subview of this
    /// canvas — current or future —* won't receive touches. Add new
    /// interactive elements as siblings of the canvas, not children.
    ///
    /// Eraser falls through to `super.hitTest`: it delegates to PencilKit's
    /// native gesture pipeline via `super.touchesBegan/Moved/Ended`, so it
    /// MUST resolve to a deeper subview as normal.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if desiredTool is PKInkingTool, self.point(inside: point, with: event) {
            return self
        }
        return super.hitTest(point, with: event)
    }

    // MARK: - Manual undo

    /// Restore `drawing` to a previous snapshot, registering the inverse so
    /// UndoManager can redo.
    ///
    /// **Recursive registration pattern**: calling this same helper from
    /// inside the registered undo block is the canonical Apple pattern.
    /// UndoManager runs the block while its `isUndoing` (or `isRedoing`) flag
    /// is true, and any `registerUndo(...)` call made during that window is
    /// automatically routed to the redo (or undo) stack rather than the
    /// current one. The recursion is bounded by user undo/redo invocations
    /// and does not loop on its own. See Apple's UndoManager guide
    /// "Performing Undo and Redo".
    private func setDrawingUndoable(_ newDrawing: PKDrawing) {
        let oldDrawing = drawing
        drawing = newDrawing
        undoManager?.registerUndo(withTarget: self) { target in
            target.setDrawingUndoable(oldDrawing)
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
           Self.colorsApproxEqual(cur.color, want.color),
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

        // `drawingPolicy` is pinned to `.anyInput` (see CLAUDE.md); PencilKit
        // suppression is done via `hitTest`, not policy toggling. We only
        // need to drive the crosshair + segment transition here.
        if isShiftDown {
            showCrosshair()
        } else {
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

        // Order matters: add the preview CAShapeLayer FIRST as a sublayer,
        // then the non-red overlay as a SUBVIEW. `addSubview` lands its
        // backing layer on top of any sublayers added so far, so the overlay
        // ends up above the preview → an in-progress red preview ends up
        // visually under the existing non-red strokes (the overlay is a
        // raster snapshot of them), mirroring the post-commit z-order
        // maintained by `pushRedStrokesToBack`.
        showPreviewLayer(color: inking.color, width: inking.width)
        if Self.isRedInkingTool(desiredTool) {
            showNonRedStrokesOverlay()
        }
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
    /// opposite mode anchored at the joining point so consecutive segments
    /// share an endpoint exactly (no floating-point drift at the join — the
    /// dedup in `flattenSegmentsToPoints` relies on bit-exact equality).
    private func transitionSegment() {
        guard dragInProgress, !dragSegments.isEmpty else { return }
        let cursor = cursorLocation
        let idx = dragSegments.count - 1

        // 1. Close the current segment and determine where the next one starts.
        let joinPoint: CGPoint
        if dragSegments[idx].mode == .line {
            // Pin the line's end-point to the snapped cursor position; the
            // next segment anchors there too so the join is exact.
            let end = snapped(from: dragSegments[idx].anchor, to: cursor)
            dragSegments[idx].points = [dragSegments[idx].anchor, end]
            joinPoint = end
        } else {
            // Freehand needs no closing — its last point IS the cursor
            // (touchesMoved appends `cursorLocation` on every move).
            joinPoint = cursor
        }

        // 2. Start a new segment of the opposite mode, anchored at the join.
        let newMode: SegmentMode = globalShiftDown ? .line : .freehand
        dragSegments.append(Segment(mode: newMode, anchor: joinPoint, points: [joinPoint]))

        renderPreview()
    }

    // MARK: - Preview rendering

    /// Rebuild the preview path from `dragSegments` and assign it to the
    /// `CAShapeLayer`. Cheap enough to call on every `touchesMoved` and on
    /// every shift transition (one allocation, no animation).
    ///
    /// Always renders the full segment chain — past freehand and closed line
    /// segments included — because PencilKit's live stroke is suppressed via
    /// `hitTest` and this overlay is the sole renderer for the in-progress
    /// drag. The current segment's end-point is derived live: line → snapped
    /// cursor, freehand → already accumulated in `seg.points`.
    private func renderPreview() {
        guard let preview = previewLayer, !dragSegments.isEmpty else { return }
        let path = UIBezierPath()

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

        let isRed = Self.isRedInkingTool(inking)
        let renderWidth = WidthCalibration.commit(rawWidth: inking.width, isRed: isRed)
        let size = CGSize(width: renderWidth, height: renderWidth)
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

        // `drawingPolicy` is pinned to `.anyInput` for this canvas (see class
        // doc); no re-assignment needed here. PencilKit's auto-undo only fires
        // for gesture-pipeline commits (which we've disabled), so we route
        // the assignment through `setDrawingUndoable` to register the inverse
        // in a single undo step. The `drawing` setter triggers PencilKit's
        // own redraw — no explicit `setNeedsDisplay()` required.
        var newDrawing = drawing
        newDrawing.strokes.append(stroke)
        setDrawingUndoable(newDrawing)
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
                // `transitionSegment` arranges consecutive segments to share
                // an endpoint exactly; skip our first sample when it would
                // re-emit the previous segment's tail.
                let dedupOffset = (i > 0 && !out.isEmpty && out.last == a) ? 1 : 0
                for k in dedupOffset...count {
                    let t = CGFloat(k) / CGFloat(count)
                    out.append(CGPoint(x: a.x + (b.x - a.x) * t,
                                       y: a.y + (b.y - a.y) * t))
                }
            case .freehand:
                let dedupOffset = (i > 0 && !out.isEmpty && out.last == seg.points.first) ? 1 : 0
                out.append(contentsOf: seg.points.dropFirst(dedupOffset))
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
        layer.lineWidth = WidthCalibration.preview(rawWidth: width)
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
        // 0.06 per-channel — wide enough to absorb sRGB ↔ extended sRGB / P3
        // round-trips, still well clear of any other tone in Theme.
        return colorsApproxEqual(color, Theme.vermilionRedUI, tolerance: 0.06)
    }

    /// Per-channel UIColor equality after forcing both inputs to sRGB.
    /// Direct `UIColor.==` between a `Theme.*` literal and a stroke colour
    /// PencilKit has round-tripped through its own colour-space pipeline can
    /// return false even when the colours are visually identical (different
    /// `colorSpace` on the underlying `CGColor`). Normalising to sRGB before
    /// component comparison absorbs that drift.
    private static func colorsApproxEqual(
        _ a: UIColor,
        _ b: UIColor,
        tolerance: CGFloat = 0.04
    ) -> Bool {
        guard let ac = sRGBComponents(of: a),
              let bc = sRGBComponents(of: b) else { return false }
        return abs(ac.r - bc.r) < tolerance
            && abs(ac.g - bc.g) < tolerance
            && abs(ac.b - bc.b) < tolerance
    }

    /// Hoisted once so callers in hot paths (`enforceDesiredTool`,
    /// `isVermilionColor` via `pushRedStrokesToBack`) don't re-allocate.
    private static let sRGBColorSpace: CGColorSpace? = CGColorSpace(name: CGColorSpace.sRGB)

    private static func sRGBComponents(
        of color: UIColor
    ) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
        guard let space = sRGBColorSpace,
              let converted = color.cgColor.converted(
                to: space, intent: .defaultIntent, options: nil
              ),
              let comps = converted.components,
              comps.count >= 3 else { return nil }
        return (comps[0], comps[1], comps[2])
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
