import AppKit
import CoreBluetooth
import SwiftUI
import UserNotifications

private enum OnboardingStep: Int, CaseIterable {
    case welcome
    case bluetooth
    case notifications
    case startup
    case desk
    case ready

    var title: String {
        switch self {
        case .welcome: "Welcome to DeskBuddy"
        case .bluetooth: "Connect over Bluetooth"
        case .notifications: "Stay on top of your posture"
        case .startup: "Make DeskBuddy effortless"
        case .desk: "Find your desk"
        case .ready: "You are ready"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome: "A faster, more thoughtful way to control your sit-stand desk."
        case .bluetooth: "Bluetooth access is required to discover, connect to, and control your desk."
        case .notifications: "Notifications are optional and used only for Posture Coach reminders."
        case .startup: "Choose how DeskBuddy should behave when you sign in to your Mac."
        case .desk: "Put your desk in pairing mode, then find it here."
        case .ready: "Your choices can be changed at any time in Settings."
        }
    }

    var symbol: String {
        switch self {
        case .welcome: "sparkles"
        case .bluetooth: "antenna.radiowaves.left.and.right"
        case .notifications: "bell.badge"
        case .startup: "power"
        case .desk: "table.furniture"
        case .ready: "checkmark.circle.fill"
        }
    }
}

struct OnboardingView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var controller = DeskController.shared
    @State private var step = OnboardingStep.welcome
    @State private var notificationStatus = UNAuthorizationStatus.notDetermined
    @State private var launchAtLogin = LoginItemManager.isEnabled
    @State private var loginError: String?
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            onboardingHeader
            Divider()
            stepProgress
                .padding(.horizontal, 34)
                .padding(.top, 24)

            VStack(spacing: 20) {
                Image(systemName: step.symbol)
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(step == .ready ? DeskBuddyDesign.connected : Color.accentColor)
                    .contentTransition(.symbolEffect(.replace))

                VStack(spacing: 7) {
                    Text(step.title)
                        .font(.title.bold())
                    Text(step.subtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                }

                stepContent
                    .frame(maxWidth: 560)
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Divider()
            navigation
        }
        .frame(width: 680, height: 610)
        .background(Color(nsColor: .windowBackgroundColor))
        .task { await refreshNotificationStatus() }
    }

    private var onboardingHeader: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
            Text("DeskBuddy")
                .font(.headline)
            Spacer()
            Text("STEP \(step.rawValue + 1) OF \(OnboardingStep.allCases.count)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }

    private var stepProgress: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { candidate in
                Capsule()
                    .fill(candidate.rawValue <= step.rawValue ? Color.accentColor : Color.secondary.opacity(0.2))
                    .frame(height: 5)
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            welcomeStep
        case .bluetooth:
            bluetoothStep
        case .notifications:
            notificationsStep
        case .startup:
            startupStep
        case .desk:
            deskStep
        case .ready:
            readyStep
        }
    }

    private var welcomeStep: some View {
        HStack(spacing: 12) {
            onboardingFeature("Double-tap presets", symbol: "hand.tap")
            onboardingFeature("Menu bar control", symbol: "menubar.rectangle")
            onboardingFeature("Posture reminders", symbol: "figure.mind.and.body")
        }
    }

    private var bluetoothStep: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                statusRow(
                    bluetoothStatus.title,
                    detail: bluetoothStatus.detail,
                    symbol: bluetoothStatus.symbol,
                    color: bluetoothStatus.color
                )

                if controller.bluetoothAuthorization == .notDetermined {
                    Button("Allow Bluetooth Access", systemImage: "antenna.radiowaves.left.and.right") {
                        controller.startBluetooth()
                    }
                    .buttonStyle(.borderedProminent)
                } else if controller.bluetoothAuthorization == .denied {
                    Button("Open Bluetooth Privacy Settings…", systemImage: "gear") {
                        openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth")
                    }
                } else if controller.bluetoothAuthorization == .allowedAlways,
                          controller.bluetoothState == .poweredOff {
                    Button("Open Bluetooth Settings…", systemImage: "gear") {
                        openSystemSettings("x-apple.systempreferences:com.apple.BluetoothSettings")
                    }
                }
            }
            .padding(18)
        }
    }

    private var notificationsStep: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                statusRow(
                    notificationStatusTitle,
                    detail: notificationStatusDetail,
                    symbol: notificationStatus == .authorized ? "checkmark.circle.fill" : "bell.badge",
                    color: notificationStatus == .authorized ? DeskBuddyDesign.connected : .secondary
                )

                if notificationStatus == .notDetermined {
                    Button("Allow Notifications", systemImage: "bell.badge") {
                        Task { await requestNotificationAccess() }
                    }
                    .buttonStyle(.borderedProminent)
                } else if notificationStatus == .denied {
                    Button("Open Notification Settings…", systemImage: "gear") {
                        openSystemSettings("x-apple.systempreferences:com.apple.Notifications-Settings.extension")
                    }
                }
            }
            .padding(18)
        }
    }

    private var startupStep: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Launch DeskBuddy at login", isOn: launchAtLoginBinding)
                Divider()
                Toggle("Automatically reconnect to the last desk", isOn: $settings.autoReconnect)
                if let loginError {
                    Text(loginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(18)
        }
    }

    private var deskStep: some View {
        GlassCard {
            DeskManagementView()
                .padding(18)
        }
        .frame(maxHeight: 250)
    }

    private var readyStep: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                statusRow(
                    "Bluetooth",
                    detail: bluetoothStatus.detail,
                    symbol: bluetoothStatus.symbol,
                    color: bluetoothStatus.color
                )
                Divider()
                statusRow(
                    "Notifications",
                    detail: notificationStatusDetail,
                    symbol: notificationStatus == .authorized ? "checkmark.circle.fill" : "bell.slash",
                    color: notificationStatus == .authorized ? DeskBuddyDesign.connected : .secondary
                )
                Divider()
                statusRow(
                    "Launch at Login",
                    detail: launchAtLogin ? "Enabled" : "Disabled",
                    symbol: launchAtLogin ? "checkmark.circle.fill" : "minus.circle",
                    color: launchAtLogin ? DeskBuddyDesign.connected : .secondary
                )
            }
            .padding(18)
        }
    }

    private var navigation: some View {
        HStack {
            if step != .welcome {
                Button("Back", systemImage: "chevron.left") {
                    move(to: step.rawValue - 1)
                }
            }

            Spacer()

            Button(step == .ready ? "Finish" : step == .welcome ? "Get Started" : "Continue") {
                if step == .ready {
                    settings.hasCompletedOnboarding = true
                    controller.startBluetooth()
                    onFinish()
                } else {
                    move(to: step.rawValue + 1)
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private func onboardingFeature(_ title: String, symbol: String) -> some View {
        VStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
            Text(title)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 92)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }

    private func statusRow(_ title: String, detail: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var bluetoothStatus: (title: String, detail: String, symbol: String, color: Color) {
        switch controller.bluetoothAuthorization {
        case .notDetermined:
            ("Bluetooth access is needed", "DeskBuddy has not requested access yet.", "antenna.radiowaves.left.and.right", .secondary)
        case .denied:
            ("Bluetooth access is denied", "Allow DeskBuddy in System Settings to connect a desk.", "xmark.circle.fill", .red)
        case .restricted:
            ("Bluetooth access is restricted", "This Mac does not currently allow DeskBuddy to use Bluetooth.", "exclamationmark.triangle.fill", .orange)
        case .allowedAlways:
            switch controller.bluetoothState {
            case .poweredOn:
                ("Bluetooth is ready", "DeskBuddy can discover and connect to nearby desks.", "checkmark.circle.fill", DeskBuddyDesign.connected)
            case .poweredOff:
                ("Bluetooth is turned off", "Turn on Bluetooth before connecting your desk.", "antenna.radiowaves.left.and.right.slash", .orange)
            default:
                ("Checking Bluetooth", "DeskBuddy is waiting for Bluetooth to become available.", "progress.indicator", .secondary)
            }
        @unknown default:
            ("Bluetooth status is unknown", "Check Bluetooth access in System Settings.", "questionmark.circle", .secondary)
        }
    }

    private var notificationStatusTitle: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: "Notifications are allowed"
        case .denied: "Notifications are disabled"
        case .notDetermined: "Notifications have not been requested"
        @unknown default: "Notification status is unknown"
        }
    }

    private var notificationStatusDetail: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: "Posture Coach can send sitting and standing reminders."
        case .denied: "Posture reminders will stay inside DeskBuddy until access is allowed."
        case .notDetermined: "Allow notifications to receive Posture Coach reminders."
        @unknown default: "Review notification access in System Settings."
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { enabled in
                do {
                    try LoginItemManager.setEnabled(enabled)
                    launchAtLogin = enabled
                    loginError = nil
                } catch {
                    loginError = error.localizedDescription
                    launchAtLogin = LoginItemManager.isEnabled
                }
            }
        )
    }

    private func move(to rawValue: Int) {
        guard let next = OnboardingStep(rawValue: rawValue) else { return }
        withAnimation(.snappy(duration: 0.28)) {
            step = next
        }
        if next == .notifications {
            Task { await refreshNotificationStatus() }
        }
    }

    private func refreshNotificationStatus() async {
        notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private func requestNotificationAccess() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        await refreshNotificationStatus()
    }

    private func openSystemSettings(_ value: String) {
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }
}

@MainActor
final class OnboardingWindowController {
    static let shared = OnboardingWindowController()

    private var windowController: NSWindowController?

    private init() {}

    func present(force: Bool = false) {
        guard force || !SettingsStore.shared.hasCompletedOnboarding else { return }
        if let window = windowController?.window {
            NSApplication.shared.activate(ignoringOtherApps: true)
            windowController?.showWindow(nil)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let content = OnboardingView { [weak self] in
            self?.windowController?.close()
            self?.windowController = nil
        }
        .environment(\.locale, Locale(identifier: "en"))

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 610),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to DeskBuddy"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content)
        window.center()

        let controller = NSWindowController(window: window)
        windowController = controller
        NSApplication.shared.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }
}