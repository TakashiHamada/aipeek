import SwiftUI

@main
struct SketchApp: App {
    init() {
        do {
            try FileStore.ensureAppSupportRoot()
        } catch {
            // Non-fatal: cleanup and save may still fail later and surface to the user.
        }
        let config = AppConfig.load(from: FileStore.configFileURL)
        CleanupRunner.runOnLaunch(retentionDays: config.retentionDays)
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ContentView()
            }
            .frame(minWidth: 600, minHeight: 400)
        }
        .defaultSize(width: 1000, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {
                // Hide default "New Window" / "New Document" since we are single-window.
                EmptyView()
            }
        }
    }
}
