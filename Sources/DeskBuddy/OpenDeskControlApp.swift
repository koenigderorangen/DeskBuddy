import AppKit
import SwiftUI
import UserNotifications

@MainActor
final class DeskBuddyAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.delegate = self
        notificationCenter.setNotificationCategories([
            UNNotificationCategory(
                identifier: DeskBuddyNotification.automaticMovementCategory,
                actions: [
                    UNNotificationAction(
                        identifier: DeskBuddyNotification.stopAutomaticMovementAction,
                        title: "Stop / Cancel",
                        options: [.destructive]
                    )
                ],
                intentIdentifiers: []
            )
        ])
        let workspaceNotifications = NSWorkspace.shared.notificationCenter
        workspaceNotifications.addObserver(
            self,
            selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        workspaceNotifications.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        if SettingsStore.shared.hasCompletedOnboarding {
            DeskController.shared.startBluetooth()
        } else {
            OnboardingWindowController.shared.present()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func systemWillSleep() {
        DeskController.shared.systemWillSleep()
    }

    @objc private func systemDidWake() {
        DeskController.shared.systemDidWake()
        PostureCoach.shared.refreshSchedule()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == DeskBuddyNotification.stopAutomaticMovementAction else { return }
        await MainActor.run {
            PostureCoach.shared.cancelPendingMovement()
            DeskController.shared.stopMovement()
        }
    }
}

@main
struct DeskBuddyApp: App {
    @NSApplicationDelegateAdaptor(DeskBuddyAppDelegate.self) private var appDelegate
    @StateObject private var controller = DeskController.shared
    @StateObject private var settings = SettingsStore.shared
    @StateObject private var softwareUpdates = SoftwareUpdateController.shared

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
                        .labelStyle(.titleAndIcon)
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

        Settings {
            SettingsView(softwareUpdates: softwareUpdates)
                .preferredColorScheme(preferredColorScheme)
                .environment(\.locale, Locale(identifier: "en"))
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch settings.theme {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
