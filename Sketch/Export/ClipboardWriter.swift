import UIKit
import UniformTypeIdentifiers

enum ClipboardWriter {
    /// Write a single pasteboard item containing both PNG bytes and a UTF-8 path string.
    /// Apps that accept images receive the PNG; plain-text fields receive the absolute path.
    static func write(png: Data, path: String?) {
        var item: [String: Any] = [
            UTType.png.identifier: png
        ]
        if let path, !path.isEmpty {
            item[UTType.utf8PlainText.identifier] = path
        }
        UIPasteboard.general.setItems([item])
    }
}
