import SwiftUI

struct ContentView: View {
    @StateObject private var controller = CanvasController()
    @EnvironmentObject private var settings: AppSettings
    @State private var showHelp: Bool = false
    @State private var showAbout: Bool = false
    @State private var showPreferences: Bool = false
    /// 0 = no wipe, 1 = canvas fully covered. Drives the New-session animation.
    @State private var wipeProgress: CGFloat = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            // App-wide background. Filling the safe-area-ignored area with the
            // canvas color removes the seam between the macOS title bar and the
            // canvas itself.
            Theme.canvasBackground
                .ignoresSafeArea()

            CanvasView(controller: controller)
                .ignoresSafeArea()

            // Wipe overlay: a rectangle filled with the canvas color sweeps in
            // from the left to right, painting over the old sketch.
            GeometryReader { geo in
                Theme.canvasBackground
                    .frame(width: geo.size.width * wipeProgress)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Copy button (top-left) — always shown.
            // Inactive when the canvas is empty, or when auto-save + auto-copy
            // are both on (clipboard is already being kept in sync automatically).
            iconActionButton(systemImage: "doc.on.clipboard") {
                controller.copyToClipboard()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(copyButtonDisabled)
            .opacity(copyButtonDisabled ? 0.55 : 1)
            .animation(.easeInOut(duration: 0.2), value: copyButtonDisabled)
            // toolTooltip is applied LAST so the overlay chip stays at full
            // opacity even when the button is dimmed by `.opacity(0.55)`
            // (otherwise the chip inherits the parent's faded opacity).
            .toolTooltip("Copy drawing to clipboard (⌘S) — auto-copy options in Preferences (⌘,)")
            .padding(.top, 12)
            .padding(.leading, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // Tools (left edge, vertically centered)
            VStack(spacing: 18) {
                toggleToolButton(systemImage: "pencil.tip", isActive: controller.activeTool == .pen) {
                    controller.selectPen()
                }
                .toolTooltip("Pen — draw in black ink (P)")
                .keyboardShortcut("p", modifiers: [])
                toggleToolButton(systemImage: "highlighter", isActive: controller.activeTool == .redPen) {
                    controller.selectRedPen()
                }
                .toolTooltip("Red marker — highlight beneath ink (R)")
                .keyboardShortcut("r", modifiers: [])
                toggleToolButton(systemImage: "eraser", isActive: controller.activeTool == .eraser) {
                    controller.selectEraser()
                }
                .toolTooltip("Eraser — remove strokes (E)")
                .keyboardShortcut("e", modifiers: [])
            }
            .padding(.leading, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            // Help (?) + New (bottom-left, stacked)
            VStack(spacing: 8) {
                iconActionButton(systemImage: "questionmark") {
                    showHelp = true
                }
                .toolTooltip("Help & keyboard shortcuts (H)")
                .keyboardShortcut("h", modifiers: [])
                iconActionButton(systemImage: "doc.badge.plus") {
                    startNewSession()
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(controller.isEmpty)
                .opacity(controller.isEmpty ? 0.55 : 1)
                .animation(.easeInOut(duration: 0.2), value: controller.isEmpty)
                .toolTooltip("Clear and start a new canvas (⌘N)")
            }
            .padding(.leading, 16)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

            // Toast stack (bottom-right, compact). New toasts stack above older
            // ones; each fades out independently after its lifetime.
            VStack(alignment: .trailing, spacing: 6) {
                ForEach(controller.toasts) { toast in
                    ToastView(message: toast)
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .trailing)),
                                removal: .opacity
                            )
                        )
                }
            }
            .padding(.trailing, 16)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .allowsHitTesting(false)

            // Help overlay
            if showHelp {
                HelpView { showHelp = false }
                    .transition(.opacity)
            }

            // About overlay (menu-triggered)
            if showAbout {
                AboutView { showAbout = false }
                    .transition(.opacity)
            }

            // Preferences overlay (menu-triggered, ⌘,)
            if showPreferences {
                PreferencesView(onClose: { showPreferences = false })
                    .environmentObject(settings)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: showHelp)
        .animation(.easeInOut(duration: 0.18), value: showAbout)
        .animation(.easeInOut(duration: 0.18), value: showPreferences)
        .onAppear {
            // Idempotent: safe to call on every appearance. Hides the macOS
            // title bar text and pins window resize constraints so the canvas
            // background extends seamlessly into the title-bar area.
            TitleBarTuner.makeTransparent()
            controller.attachSettings(settings)
        }
        // The .showPreferences / .showAbout notifications are posted from the
        // menu-bar `Preferences…` / `About AIPeek` items defined in
        // `SketchApp.commands { ... }`. See Notification.Name extensions in
        // SketchApp.swift.
        .onReceive(NotificationCenter.default.publisher(for: .showPreferences)) { _ in
            showPreferences = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAbout)) { _ in
            showAbout = true
        }
    }

    /// New-session animation:
    ///   1. Wipe overlay sweeps left → right, covering the old sketch.
    ///   2. Once covered, the canvas content is actually cleared and a new
    ///      filename is reserved (the user never sees the abrupt clear).
    ///   3. Overlay slides back out the right side, revealing the fresh canvas.
    private func startNewSession() {
        // Phase 1: wipe in
        withAnimation(.easeInOut(duration: 0.35)) {
            wipeProgress = 1
        }
        // Phase 2: at peak coverage, clear the canvas
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
            controller.newSession()
            // Phase 3: wipe back out (slide overlay off to the right by reusing
            // the same width-driven mechanism: just snap to 0 — the canvas
            // underneath is now blank so the user perceives a fresh page).
            withAnimation(.easeInOut(duration: 0.25)) {
                wipeProgress = 0
            }
        }
    }

    private var copyButtonDisabled: Bool {
        controller.isEmpty || (settings.autoSave && settings.autoCopyOnSave)
    }

    fileprivate static let iconButtonSize: CGFloat = 40

    @ViewBuilder
    private func iconActionButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: Self.iconButtonSize, height: Self.iconButtonSize)
                .background(Theme.action, in: Circle())
                .shadow(color: Theme.action.opacity(0.35), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func toggleToolButton(systemImage: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: Self.iconButtonSize, height: Self.iconButtonSize)
                .background(
                    isActive ? Theme.toolActive : Theme.toolInactive,
                    in: Circle()
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(isActive ? 1.25 : 1.0)
        .shadow(color: isActive ? Theme.toolActive.opacity(0.4) : .clear,
                radius: isActive ? 6 : 0, x: 0, y: 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isActive)
    }
}

/// Small hover chip rendered to the right of a left-edge toolbar button.
/// Appears immediately on hover (no system tooltip delay), and is purely
/// visual — the button stays active and clickable beneath. Accessibility
/// labels remain on the underlying `Button`'s `Image` (the system reads the
/// SF Symbol name; `.accessibilityLabel` could be added if needed).
private struct HoverTooltipChip: ViewModifier {
    let text: String
    @State private var isHovering: Bool = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovering = hovering
            }
            .overlay(alignment: .leading) {
                Text(text)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .fixedSize()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 6))
                    .offset(x: ContentView.iconButtonSize + 12)
                    .opacity(isHovering ? 1 : 0)
                    .animation(.easeInOut(duration: 0.18), value: isHovering)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    fileprivate func toolTooltip(_ text: String) -> some View {
        modifier(HoverTooltipChip(text: text))
    }
}

#Preview {
    ContentView()
}
