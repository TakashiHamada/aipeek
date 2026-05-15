import Foundation
import PencilKit
import UIKit
import os

@MainActor
final class CanvasController: ObservableObject {
    weak var canvas: PKCanvasView?

    @Published var isEmpty: Bool = true
    @Published var toast: ToastMessage?

    private let log = Logger(subsystem: "com.giftten.sketch", category: "controller")

    func bind(_ canvas: PKCanvasView) {
        self.canvas = canvas
        refreshIsEmpty()
    }

    func refreshIsEmpty() {
        guard let drawing = canvas?.drawing else {
            isEmpty = true
            return
        }
        isEmpty = DrawingRenderer.isEmpty(drawing)
    }

    func copyAndSave() {
        guard let canvas else {
            showToast(.error("キャンバスが利用できません"))
            return
        }
        let drawing = canvas.drawing
        guard !DrawingRenderer.isEmpty(drawing) else {
            showToast(.info("描画がありません"))
            return
        }

        let png: Data
        do {
            png = try DrawingRenderer.renderPNG(drawing: drawing)
        } catch {
            log.error("render failed: \(String(describing: error), privacy: .public)")
            showToast(.error("画像の生成に失敗しました"))
            return
        }

        // Try to save to disk. If it fails, we still copy the image to the clipboard.
        var savedURL: URL?
        do {
            savedURL = try FileStore.save(png, at: Date())
        } catch {
            log.error("save failed: \(String(describing: error), privacy: .public)")
        }

        ClipboardWriter.write(png: png, path: savedURL?.path)

        if let savedURL {
            showToast(.success("保存しました: \(savedURL.lastPathComponent)"))
        } else {
            showToast(.warning("クリップボードにコピー(保存は失敗)"))
        }
    }

    func clear() {
        guard let canvas else { return }
        canvas.drawing = PKDrawing()
        refreshIsEmpty()
    }

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
