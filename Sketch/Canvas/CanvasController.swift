import Foundation
import PencilKit
import SwiftUI
import UIKit
import os

enum ActiveTool {
    case pen
    case redPen
    case eraser
}

@MainActor
final class CanvasController: ObservableObject {
    weak var canvas: PKCanvasView?

    @Published var isEmpty: Bool = true
    @Published var toasts: [ToastMessage] = []
    @Published var activeTool: ActiveTool = .pen

    /// Filename reserved for auto-save in the current session.
    /// Set on init and on `newSession()` (when auto-save is on).
    private var reservedURL: URL?

    /// Debounced auto-save task — fires `autoSaveDebounceNs` after the last
    /// drawing change.
    private var autoSaveTask: Task<Void, Never>?

    /// AppSettings is supplied externally by ContentView's `.task` so we can
    /// observe auto-save toggle changes.
    private weak var settings: AppSettings?

    /// 1 s — long enough to coalesce several strokes into a single save
    /// without thrashing the clipboard, short enough that the file is fresh
    /// by the time the user thinks to share it.
    private static let autoSaveDebounceNs: UInt64 = 1_000_000_000

    /// How long a single toast remains visible before fading out.
    private static let toastLifetimeNs: UInt64 = 1_800_000_000

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
        // Snapshot everything we need on the main actor *before* dispatching
        // the heavy work. PKDrawing is a value type so the snapshot is safe to
        // hand off to a detached worker, and we capture `url` by value so a
        // concurrent newSession() that swaps reservedURL can't redirect this
        // save to the new file.
        guard let canvas, let url = reservedURL else { return }
        let drawing = canvas.drawing
        guard !DrawingRenderer.isEmpty(drawing) else { return }
        let shouldCopyImage = settings?.autoCopyOnSave == true

        do {
            // Render + disk write are CPU/IO heavy. Run them off the main
            // actor so a long stroke doesn't visibly stall while a save runs.
            let jpeg = try await Task.detached(priority: .utility) {
                let data = try DrawingRenderer.renderJPEG(drawing: drawing)
                try FileStore.write(data, to: url)
                return data
            }.value

            // Clipboard policy:
            //   autoCopyOnSave ON  → send image + path
            //   autoCopyOnSave OFF → send path only (keeps Claude Code refresh
            //                       working without overwriting an image the
            //                       user copied from elsewhere)
            if shouldCopyImage {
                ClipboardWriter.write(jpeg: jpeg, path: url.path)
                showToast(.success("Copied: \(url.lastPathComponent)"))
            } else {
                ClipboardWriter.writePath(url.path)
                showToast(.info("Path: \(url.lastPathComponent)"))
            }
        } catch {
            log.error("autosave failed: \(String(describing: error), privacy: .public)")
            showToast(.error("Save failed"))
        }
    }

    // MARK: - User actions

    /// "New" button. Clears the canvas. In auto-save mode also reserves a new
    /// filename so subsequent strokes write to a fresh JPEG (the previous file
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
            // A new clipboard target is now active — green dot, same as a save.
            showToast(.success("Path copied: \(url.lastPathComponent)"))
        }
    }

    /// Manual Copy! action. Sends the current drawing to the clipboard (JPEG + path),
    /// writing a file if needed. Used by the Copy! button that appears when either
    /// autoSave or autoCopyOnSave is off.
    func copyToClipboard() {
        guard let canvas else { return }
        let drawing = canvas.drawing
        guard !DrawingRenderer.isEmpty(drawing) else {
            showToast(.info("Nothing to copy"))
            return
        }

        let jpeg: Data
        do {
            jpeg = try DrawingRenderer.renderJPEG(drawing: drawing)
        } catch {
            log.error("render failed: \(String(describing: error), privacy: .public)")
            showToast(.error("Could not render image"))
            return
        }

        var savedURL: URL?
        if settings?.autoSave == true {
            // autoSave ON: write to the session-stable reserved URL.
            if let url = reservedURL {
                do {
                    try FileStore.write(jpeg, to: url)
                    savedURL = url
                } catch {
                    log.error("save (Copy, autoSave) failed: \(String(describing: error), privacy: .public)")
                }
            }
        } else {
            // autoSave OFF: every Copy! creates a brand-new file.
            do {
                savedURL = try FileStore.save(jpeg, at: Date())
            } catch {
                log.error("save (Copy, manual) failed: \(String(describing: error), privacy: .public)")
            }
        }

        ClipboardWriter.write(jpeg: jpeg, path: savedURL?.path)

        if let savedURL {
            showToast(.success("Copied: \(savedURL.lastPathComponent)"))
        } else {
            showToast(.warning("Copied to clipboard (file save failed)"))
        }
    }

    // MARK: - Tool selection

    func selectPen() {
        guard let logging = canvas as? LoggingCanvasView else { return }
        let newTool = PKInkingTool(.monoline, color: .black, width: 3)
        logging.desiredTool = newTool
        logging.tool = newTool
        activeTool = .pen
    }

    func selectRedPen() {
        guard let logging = canvas as? LoggingCanvasView else { return }
        // Vermilion (朱色) — see Theme.vermilionRedUI. Multiply-with-black
        // behaviour is achieved by z-order reordering in CanvasView.Coordinator,
        // not by blend mode. The exact RGB doubles as the red-stroke identifier
        // used during reordering, so it must come from Theme.
        let newTool = PKInkingTool(.monoline, color: Theme.vermilionRedUI, width: 14)
        logging.desiredTool = newTool
        logging.tool = newTool
        activeTool = .redPen
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
        withAnimation(.easeOut(duration: 0.18)) {
            toasts.append(message)
        }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.toastLifetimeNs)
            await MainActor.run {
                guard let self else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.toasts.removeAll { $0.id == message.id }
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
