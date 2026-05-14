import SwiftUI

@main
struct OpenClawFloatingClientApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppStateModel.shared

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
