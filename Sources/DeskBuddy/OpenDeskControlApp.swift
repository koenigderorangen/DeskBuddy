import AppKit
import SwiftUI

@main
struct DeskBuddyApp: App {
    @StateObject private var controller = DeskController.shared
    @StateObject private var settings = SettingsStore.shared

    init() {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
        _ = PostureCoach.shared
        _ = GlobalShortcutCenter.shared
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(controller: controller)
                .preferredColorScheme(preferredColorScheme)
                .environment(\.locale, Locale(identifier: "en"))
        } label: {
            switch settings.menuBarPresentation {
            case .symbolAndValue:
                if let height = controller.heightCm {
                    Label(settings.formattedHeight(height), systemImage: "arrow.up.and.down")
                } else {
                    Image(systemName: "arrow.up.and.down")
                }
            case .symbol:
                Image(systemName: "arrow.up.and.down")
            case .value:
                Text(controller.heightCm.map(settings.formattedHeight) ?? "–")
            }
        }
        .menuBarExtraStyle(.window)

        Window("DeskBuddy Settings", id: "settings") {
            SettingsView()
                .preferredColorScheme(preferredColorScheme)
                .environment(\.locale, Locale(identifier: "en"))
        }
        .defaultSize(width: 900, height: 620)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.suppressed)
    }

    private var preferredColorScheme: ColorScheme? {
        switch settings.theme {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
