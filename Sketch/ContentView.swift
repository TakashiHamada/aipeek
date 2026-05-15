import SwiftUI

struct ContentView: View {
    @StateObject private var controller = CanvasController()

    var body: some View {
        ZStack {
            CanvasView(controller: controller)
                .ignoresSafeArea(edges: .bottom)

            VStack {
                Spacer()
                if let toast = controller.toast {
                    ToastView(message: toast)
                        .padding(.bottom, 24)
                        .id(toast.id)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: controller.toast)
            .allowsHitTesting(false)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    controller.copyAndSave()
                } label: {
                    Label("Copy & Save", systemImage: "doc.on.clipboard")
                }
                .keyboardShortcut("s", modifiers: .command)
                .help("Copy & Save (⌘S)")
            }
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    controller.clear()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .keyboardShortcut("n", modifiers: .command)
                .help("Clear (⌘N)")
            }
        }
        .navigationTitle("Sketch")
    }
}

#Preview {
    NavigationStack {
        ContentView()
    }
}
