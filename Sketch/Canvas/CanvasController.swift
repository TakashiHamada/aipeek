import Foundation
import PencilKit
import UIKit
import os

enum ActiveTool {
    case pen
    case eraser
}

@MainActor
final class CanvasController: ObservableObject {
    weak var canvas: PKCanvasView?

    @Published var isEmpty: Bool = true
    @Published var toast: ToastMessage?
    @Published var activeTool: ActiveTool = .pen

    /// Filename reserved for auto-save in the current session.
    /// Set on init and on `newSession()` (when auto-save is on).
    private var reservedURL: URL?

    /// Debounced auto-save task (500ms after the last drawing change).
    private var autoSaveTask: Task<Void, Never>?

    /// AppSettings is supplied externally by ContentView's `.task` so we can
    /// observe auto-save toggle changes.
    private weak var settings: AppSettings?

    /// 500 ms — long enough to coalesce a full stroke, short enough that the
    /// file is fresh by the time the user thinks to share it.
    private static let autoSaveDebounceNs: UInt64 = 500_000_000

    private let log = Logger(subsystem: "com.giftten.aipeek", category: "controller")

    // MARK: - Setup

    func attachSettings(_ settings: AppSettings) {
        self.settings = settings
        if reservedURL == nil {
            reserveNewFilename()
        }
        copyReservedPathIfAutoSave(announce: true)
    }

    func bind(_ canvas: PKCanvasView) {
        self.canvas = canvas
        refreshIsEmpty()
    }

    private func reserveNewFilename() {
        do {
            reservedURL = try FileStore.reserveFilename(at: Date())
        } catch {
            log.error("reserveFilename failed: \(String(describing: error), privacy: .public)")
            reservedURL = nil
        }
    }

    // MARK: - Drawing change callback

    func refreshIsEmpty() {
        guard let drawing = canvas?.drawing else {
            isEmpty = true
            return
        }
        isEmpty = DrawingRenderer.isEmpty(drawing)
    }

    /// Called from PKCanvasViewDelegate.canvasViewDrawingDidChange.
    func handleDrawingChange() {
        refreshIsEmpty()
        guard settings?.autoSave == true else { return }
        scheduleAutoSave()
    }

    private func scheduleAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.autoSaveDebounceNs)
            guard !Task.isCancelled else { return }
            await self?.performAutoSave()
        }
    }

    private func performAutoSave() async {
        guard let canvas, let url = reservedURL else { return }
        let drawing = canvas.drawing
        guard !DrawingRenderer.isEmpty(drawing) else { return }
        do {
            let png = try DrawingRenderer.renderPNG(drawing: drawing)
            try FileStore.write(png, to: url)
            // Clipboard policy:
            //   autoCopyOnSave ON  → send image + path (drop-in for the old Copy! button)
            //   autoCopyOnSave OFF → send path only (keeps Claude Code refresh working
            //                       without overwriting whatever image is on the clipboard)
            if settings?.autoCopyOnSave == true {
                ClipboardWriter.write(png: png, path: url.path)
            } else {
                ClipboardWriter.writePath(url.path)
            }
        } catch {
            log.error("autosave failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - User actions

    /// "New" button. Clears the canvas. In auto-save mode also reserves a new
    /// filename so subsequent strokes write to a fresh PNG (the previous file
    /// is left in place — sessions accumulate).
    func newSession() {
        guard let canvas else { return }
        autoSaveTask?.cancel()
        canvas.drawing = PKDrawing()
        refreshIsEmpty()
        if settings?.autoSave == true {
            reserveNewFilename()
            copyReservedPathIfAutoSave(announce: true)
        }
    }

    /// Put the reserved path into the pasteboard. If `announce` is true, a brief
    /// toast tells the user the path is now copy-pasteable. Auto-save's per-write
    /// updates skip the toast to avoid noise.
    private func copyReservedPathIfAutoSave(announce: Bool) {
        guard settings?.autoSave == true, let url = reservedURL else { return }
        ClipboardWriter.writePath(url.path)
        if announce {
            showToast(.info("パスをクリップボードへ: \(url.lastPathComponent)"))
        }
    }

    // MARK: - Tool selection

    func selectPen() {
        guard let logging = canvas as? LoggingCanvasView else { return }
        let newTool = PKInkingTool(.pen, color: .black, width: 10)
        logging.desiredTool = newTool
        logging.tool = newTool
        activeTool = .pen
    }

    func selectEraser() {
        guard let logging = canvas as? LoggingCanvasView else { return }
        let newTool = PKEraserTool(.bitmap, width: 30)
        logging.desiredTool = newTool
        logging.tool = newTool
        activeTool = .eraser
    }

    // MARK: - Toast

    private func showToast(_ message: ToastMessage) {
        toast = message
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            await MainActor.run {
                guard let self else { return }
                if self.toast?.id == message.id {
                    self.toast = nil
                }
            }
        }
    }
}

struct ToastMessage: Equatable, Identifiable {
    enum Kind { case success, info, warning, error }
    let id = UUID()
    let kind: Kind
    let text: String

    static func success(_ text: String) -> ToastMessage { .init(kind: .success, text: text) }
    static func info(_ text: String) -> ToastMessage { .init(kind: .info, text: text) }
    static func warning(_ text: String) -> ToastMessage { .init(kind: .warning, text: text) }
    static func error(_ text: String) -> ToastMessage { .init(kind: .error, text: text) }
}
