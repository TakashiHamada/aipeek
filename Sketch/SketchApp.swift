import SwiftUI

extension Notification.Name {
    static let showPreferences = Notification.Name("com.giftten.aipeek.showPreferences")
}

@main
struct SketchApp: App {
    @StateObject private var settings: AppSettings

    init() {
        try? FileStore.ensureAppSupportRoot()
        let initial = AppSettings()
        self._settings = StateObject(wrappedValue: initial)
        CleanupRunner.runOnLaunch(retentionDays: initial.retentionDays)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .frame(minWidth: 600, minHeight: 400)
                // Force light appearance for the whole app. PencilKit's PKInkingTool
                // colors auto-invert based on the interface style (black ↔ white) so
                // on a dark-mode Mac, .black ink renders as white and is invisible.
                .preferredColorScheme(.light)
        }
        .defaultSize(width: 1000, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {
                EmptyView()
            }
            CommandGroup(after: .appSettings) {
                Button("環境設定...") {
                    NotificationCenter.default.post(name: .showPreferences, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
