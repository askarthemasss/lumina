import SwiftUI

/// Lumina uses a manually managed single window (see `AppDelegate`) so that
/// Quick Search can reopen it from anywhere. SwiftUI still supplies the
/// native Settings window and application menus.
@main
@MainActor
struct LuminaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            Group {
                if let model = AppEnvironment.shared.model {
                    SettingsView(isStandaloneWindow: true)
                        .environment(model)
                        .environment(model.settings)
                        .tint(model.settings.accent.color)
                } else {
                    StartupFailureView(
                        message: AppEnvironment.shared.startupError
                            ?? "Lumina couldn't open its local database."
                    )
                }
            }
            .frame(width: 840, height: 700)
        }
        .commands {
            LuminaCommands()
        }
    }
}
