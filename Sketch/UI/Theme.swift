import SwiftUI
import UIKit

/// App-wide warm color palette. Designed for a sketch-tool feel
/// (warm parchment background, terracotta highlights, mustard actions).
enum Theme {
    // MARK: - Canvas
    /// Off-white — kinder on the eyes than pure #FFFFFF, but neutral enough not to read as cream.
    static let canvasBackgroundUI: UIColor = UIColor(red: 0.97, green: 0.96, blue: 0.94, alpha: 1.0)
    static let canvasBackground = Color(canvasBackgroundUI)

    // MARK: - Tool buttons (Pen / Eraser)
    /// Espresso brown for inactive tool — strong contrast against cream.
    static let toolInactive = Color(red: 0.24, green: 0.18, blue: 0.15)
    /// Terracotta — vivid warm orange for the currently selected tool.
    static let toolActive = Color(red: 0.85, green: 0.47, blue: 0.34)

    // MARK: - Action buttons (Copy! / ? / Clear)
    /// Mustard amber — warm and distinct from the terracotta active state.
    static let action = Color(red: 0.76, green: 0.53, blue: 0.25)

    // MARK: - Red marker
    /// Vermilion (朱色). The single source of truth for the "red marker" tool —
    /// CanvasController uses this when constructing PKInkingTool, and the
    /// stroke-reorder code compares against this RGB to detect red strokes.
    /// Don't introduce other reds that would match the same threshold.
    static let vermilionRedUI = UIColor(red: 0.94, green: 0.30, blue: 0.20, alpha: 1.0)
}
