import UIKit
import UniformTypeIdentifiers

enum ClipboardWriter {
    /// Write a single pasteboard item containing both JPEG bytes and a UTF-8 path string.
    /// Apps that accept images receive the JPEG; plain-text fields receive the absolute path.
    static func write(jpeg: Data, path: String?) {
        var item: [String: Any] = [
            UTType.jpeg.identifier: jpeg
        ]
        if let path, !path.isEmpty {
            item[UTType.utf8PlainText.identifier] = path
        }
        UIPasteboard.general.setItems([item])
    }

    /// Write only an absolute file path as plain text. Used by auto-save to keep
    /// the reserved path always pasteable into Claude Code without overwriting
    /// the user's image clipboard from elsewhere.
    static func writePath(_ path: String) {
        UIPasteboard.general.setItems([
            [UTType.utf8PlainText.identifier: path]
        ])
    }
}
