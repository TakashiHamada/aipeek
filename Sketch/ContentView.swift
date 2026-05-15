import SwiftUI

struct ContentView: View {
    @StateObject private var controller = CanvasController()
    @EnvironmentObject private var settings: AppSettings
    @State private var showAbout: Bool = false
    @State private var showPreferences: Bool = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            CanvasView(controller: controller)
                .ignoresSafeArea()

            // Copy! (top-left) — clipboard send
            Button {
                controller.copyToClipboard()
            } label: {
                Text("Copy!")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Theme.action, in: Capsule())
                    .shadow(color: Theme.action.opacity(0.35), radius: 6, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("s", modifiers: .command)
            .help("Copy & Save (⌘S)")
            .padding(.top, 12)
            .padding(.leading, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // Tools (left edge, vertically centered)
            VStack(spacing: 8) {
                toggleToolButton(systemImage: "pencil.tip", help: "ペン (P)", isActive: controller.activeTool == .pen) {
                    controller.selectPen()
                }
                .keyboardShortcut("p", modifiers: [])
                toggleToolButton(systemImage: "eraser", help: "消しゴム (E)", isActive: controller.activeTool == .eraser) {
                    controller.selectEraser()
                }
                .keyboardShortcut("e", modifiers: [])
            }
            .padding(.leading, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            // Help (?) + New (bottom-left, stacked)
            VStack(spacing: 8) {
                iconActionButton(systemImage: "questionmark", help: "このアプリについて") {
                    showAbout = true
                }
                iconActionButton(systemImage: "doc.badge.plus", help: "新規 (⌘N)") {
                    controller.newSession()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            .padding(.leading, 16)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

            // Toast (bottom-center)
            if let toast = controller.toast {
                VStack {
                    Spacer()
                    ToastView(message: toast)
                        .padding(.bottom, 24)
                        .id(toast.id)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.2), value: controller.toast)
            }

            // About overlay
            if showAbout {
                AboutView { showAbout = false }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: showAbout)
        .onAppear {
            TitleBarTuner.makeTransparent()
            controller.attachSettings(settings)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showPreferences)) { _ in
            showPreferences = true
        }
        .sheet(isPresented: $showPreferences) {
            PreferencesView()
                .environmentObject(settings)
                .preferredColorScheme(.light)
        }
    }

    private static let iconButtonSize: CGFloat = 40

    @ViewBuilder
    private func iconActionButton(systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: Self.iconButtonSize, height: Self.iconButtonSize)
                .background(Theme.action, in: Circle())
                .shadow(color: Theme.action.opacity(0.35), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    @ViewBuilder
    private func toggleToolButton(systemImage: String, help: String, isActive: Bool, action: @escaping () -> Void) -> some View {
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
        .help(help)
    }
}

#Preview {
    ContentView()
}
