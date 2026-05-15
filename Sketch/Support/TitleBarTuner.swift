import UIKit

enum TitleBarTuner {
    /// Hide the macOS title bar's title so it blends with the white canvas, and
    /// ensure the window stays resizable with sensible minimums.
    /// Traffic-light window buttons (close/minimize/zoom) remain functional.
    static func makeTransparent() {
        DispatchQueue.main.async {
            for scene in UIApplication.shared.connectedScenes {
                guard let windowScene = scene as? UIWindowScene else { continue }

                if let titlebar = windowScene.titlebar {
                    titlebar.titleVisibility = .hidden
                    titlebar.toolbar = nil
                    // Note: do NOT set titlebar.toolbarStyle = .unified — that
                    // appears to lock the window's resize behavior on Catalyst.
                }

                if let sizeRestrictions = windowScene.sizeRestrictions {
                    sizeRestrictions.minimumSize = CGSize(width: 600, height: 400)
                    sizeRestrictions.maximumSize = CGSize(
                        width: CGFloat.greatestFiniteMagnitude,
                        height: CGFloat.greatestFiniteMagnitude
                    )
                }
            }
        }
    }
}
