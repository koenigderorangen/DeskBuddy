import AppKit
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case desks
    case general
    case interactions
    case shortcuts
    case coach
    case diagnostics
    case about

    static let storageKey = "selectedSettingsSection"

    var id: Self { self }
    var title: String {
        switch self {
        case .desks: "Desks"
        case .general: "General"
        case .interactions: "Interactions"
        case .shortcuts: "Keyboard Shortcuts"
        case .coach: "Posture Coach"
        case .diagnostics: "Diagnostics"
        case .about: "About"
        }
    }
    var symbol: String {
        switch self {
        case .desks: "table.furniture"
        case .general: "gearshape"
        case .interactions: "hand.tap"
        case .shortcuts: "keyboard"
        case .coach: "figure.mind.and.body"
        case .diagnostics: "stethoscope"
        case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var softwareUpdates: SoftwareUpdateController
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var controller = DeskController.shared
    @ObservedObject private var coach = PostureCoach.shared
    @AppStorage(SettingsSection.storageKey) private var selectedSection = SettingsSection.general.rawValue
    @State private var launchAtLogin = LoginItemManager.isEnabled
    @State private var loginError: String?

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: selection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(min: 190, ideal: 190, max: 190)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 10) {
                    Image(systemName: "table.furniture")
                        .font(.title3)
                        .frame(width: 34, height: 34)
                        .glassEffect(.regular.tint(.accentColor.opacity(0.3)), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("DeskBuddy").font(.subheadline.weight(.semibold))
                        Text("For IDÅSEN & LINAK").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
            }
        } detail: {
            detailView
        }
        .frame(minWidth: 820, minHeight: 570)
        .toggleStyle(.switch)
    }

    @ViewBuilder
    private var detailView: some View {
        switch currentSection {
        case .desks: deskSettings
        case .general: generalSettings
        case .interactions: interactionSettings
        case .shortcuts: shortcutSettings
        case .coach: coachSettings
        case .diagnostics: diagnosticsSettings
        case .about: aboutSettings
        }
    }

    private var deskSettings: some View {
        settingsScroll {
            settingsGroup(
                "Desk Connection",
                subtitle: "Find, connect, and switch between compatible Bluetooth desks."
            ) {
                DeskManagementView()
            }
        }
    }

    private var generalSettings: some View {
        settingsScroll {
            settingsGroup("Menu Bar", subtitle: "Choose what DeskBuddy displays in the macOS menu bar.") {
                settingsControlRow("Presentation") {
                    Picker("", selection: $settings.menuBarPresentation) {
                        ForEach(MenuBarPresentation.allCases) { option in Text(option.title).tag(option) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            settingsGroup("Display") {
                settingsControlRow("Precision") {
                    Picker("", selection: $settings.heightPrecision) {
                        ForEach(HeightPrecision.allCases) { option in Text(option.title).tag(option) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                settingsControlRow("Unit") {
                    Picker("", selection: $settings.useInches) {
                        Text("Metric (cm)").tag(false)
                        Text("Imperial (inches)").tag(true)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            settingsGroup("Appearance") {
                settingsControlRow("Theme") {
                    Picker("", selection: $settings.theme) {
                        ForEach(DeskBuddyTheme.allCases) { theme in Text(theme.title).tag(theme) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                settingsToggleRow("Automatically reconnect", isOn: $settings.autoReconnect)
                settingsToggleRow("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in updateLoginItem(enabled) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }

            settingsGroup("Setup") {
                settingsControlRow("Onboarding") {
                    Button("Run Setup Again…", systemImage: "sparkles") {
                        OnboardingWindowController.shared.present(force: true)
                    }
                }
            }
        }
    }

    private var interactionSettings: some View {
        settingsScroll {
            settingsGroup(
                "Physical Paddle Gestures",
                subtitle: "Use short taps on the desk paddle to move to assigned presets. Triple taps take priority over double taps when both are assigned."
            ) {
                settingsToggleRow("Enable paddle gestures", isOn: $settings.paddleGesturesEnabled)
                ForEach(HardwareGesture.allCases) { gesture in
                    settingsControlRow(gesture.title) {
                        gesturePresetPicker(gesture)
                    }
                    .disabled(!settings.paddleGesturesEnabled)
                    .opacity(settings.paddleGesturesEnabled ? 1 : 0.5)
                }
            }

            settingsGroup("Movement Behavior") {
                Label("Releasing the control stops manual movement immediately.", systemImage: "hand.raised.fill")
                Label("If a target is not reached within 30 seconds, DeskBuddy stops retrying.", systemImage: "timer")
                Label("DeskBuddy stops sending commands if the connection is lost.", systemImage: "antenna.radiowaves.left.and.right.slash")
            }
        }
    }

    private var shortcutSettings: some View {
        settingsScroll {
            settingsGroup(
                "Global Keyboard Shortcuts",
                subtitle: "Click a shortcut to replace it. Hold Escape for one second to turn it off."
            ) {
                settingsToggleRow("Enable keyboard shortcuts", isOn: $settings.shortcutsEnabled)
                shortcutRow(.firstPreset)
                shortcutRow(.secondPreset)
                shortcutRow(.moveUp)
                shortcutRow(.moveDown)
                shortcutRow(.stop)
            }

            settingsGroup("Apple Shortcuts") {
                Label("Sitting, standing, target height, stop, and current height actions are available in Shortcuts.", systemImage: "command")
            }
        }
    }

    private var coachSettings: some View {
        settingsScroll {
            settingsGroup("Posture Coach") {
                settingsToggleRow("Enable Posture Coach", isOn: $settings.coachEnabled)
                    .onChange(of: settings.coachEnabled) { _, enabled in
                        if enabled { PostureCoach.shared.requestPermission() }
                        PostureCoach.shared.resetSchedule()
                    }
                settingsToggleRow(
                    "Gently remind me to change position",
                    isOn: $settings.coachReminderEnabled,
                    disabled: !settings.coachEnabled
                )
                    .disabled(!settings.coachEnabled)
                settingsToggleRow(
                    "Automatically move desk after countdown",
                    isOn: $settings.automaticMovementEnabled,
                    disabled: !settings.coachEnabled
                )
                    .disabled(!settings.coachEnabled)

                if settings.automaticMovementEnabled {
                    settingsControlRow("Cancel countdown") {
                        HStack(spacing: 10) {
                            Text("\(settings.movementCountdownSeconds) seconds")
                                .monospacedDigit()
                            Stepper(
                                "",
                                value: $settings.movementCountdownSeconds,
                                in: 5...60,
                                step: 5
                            )
                            .labelsHidden()
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }

            settingsGroup("Intervals") {
                settingsControlRow("Next reminder in") {
                    if let pendingMovement = coach.pendingMovement {
                        Text("\(coach.remainingSeconds) sec to \(pendingMovement.preset.name)")
                            .monospacedDigit()
                    } else if let nextReminder = coach.nextReminder {
                        Text(nextReminder, style: .timer)
                            .monospacedDigit()
                    } else {
                        Text("Not scheduled")
                            .foregroundStyle(.secondary)
                    }
                }
                intervalRow("Sitting interval", symbol: "chair", value: $settings.sittingIntervalMinutes, range: 10...120)
                Divider()
                intervalRow("Standing interval", symbol: "figure.stand", value: $settings.standingIntervalMinutes, range: 5...60)
            }

            settingsGroup("Schedule", subtitle: "The coach stays quiet outside these hours.") {
                settingsControlRow("From") {
                    Picker("", selection: $settings.activeStartHour) {
                        ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                settingsControlRow("To") {
                    Picker("", selection: $settings.activeEndHour) {
                        ForEach(1...24, id: \.self) { Text(String(format: "%02d:00", $0 % 24)).tag($0) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                settingsControlRow("Active days") {
                    HStack(spacing: 7) {
                        ForEach(weekdayOptions, id: \.number) { day in
                            let isActive = settings.activeWeekdays.contains(day.number)
                            Button(day.label) {
                                if isActive {
                                    settings.activeWeekdays.remove(day.number)
                                } else {
                                    settings.activeWeekdays.insert(day.number)
                                }
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                            .frame(minWidth: 34)
                            .padding(.vertical, 6)
                            .foregroundStyle(isActive ? Color.white : Color.primary)
                            .glassEffect(
                                .regular.tint(isActive ? .accentColor : nil).interactive(),
                                in: Capsule()
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

#if DEBUG
            settingsGroup(
                "Developer Testing",
                subtitle: "These controls are compiled only into development builds."
            ) {
                settingsControlRow("Notification") {
                    Button("Send Test Notification", systemImage: "bell.badge") {
                        coach.sendTestNotification()
                    }
                }
                settingsControlRow("Automatic movement") {
                    Button("Trigger Coach Countdown", systemImage: "timer") {
                        coach.triggerTestCountdown()
                    }
                    .disabled(!controller.state.isConnected)
                }
            }
#endif
        }
    .onChange(of: settings.coachEnabled) { _, _ in coach.refreshSchedule() }
    .onChange(of: settings.coachReminderEnabled) { _, _ in coach.refreshSchedule() }
    .onChange(of: settings.automaticMovementEnabled) { _, _ in coach.refreshSchedule() }
    .onChange(of: settings.sittingIntervalMinutes) { _, _ in coach.refreshSchedule() }
    .onChange(of: settings.standingIntervalMinutes) { _, _ in coach.refreshSchedule() }
    .onChange(of: settings.activeStartHour) { _, _ in coach.refreshSchedule() }
    .onChange(of: settings.activeEndHour) { _, _ in coach.refreshSchedule() }
    .onChange(of: settings.activeWeekdays) { _, _ in coach.refreshSchedule() }
    }

    private var diagnosticsSettings: some View {
        settingsScroll {
            settingsGroup(
                "Diagnostic Report",
                subtitle: "Include this report when opening an issue. It contains app, macOS, Bluetooth, connection, and recent event details."
            ) {
                ScrollView {
                    Text(controller.diagnosticsReport)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(height: 280)
                .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))

                settingsControlRow("Export") {
                    HStack(spacing: 10) {
                        Button("Copy Report", systemImage: "doc.on.doc") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(controller.diagnosticsReport, forType: .string)
                        }
                        ShareLink(
                            item: controller.diagnosticsReport,
                            subject: Text("DeskBuddy Diagnostics")
                        ) {
                            Label("Share Report", systemImage: "square.and.arrow.up")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    private var aboutSettings: some View {
        settingsScroll {
            settingsGroup(nil) {
                HStack(spacing: 14) {
                    Image(systemName: "table.furniture")
                        .font(.system(size: 32, weight: .medium))
                        .frame(width: 58, height: 58)
                        .glassEffect(.regular.tint(.accentColor.opacity(0.32)), in: RoundedRectangle(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("DeskBuddy").font(.title2.bold())
                        Text("Version \(appVersion)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("A small, native macOS app for your height-adjustable IDÅSEN or LINAK desk.")
                    .foregroundStyle(.secondary)
                settingsControlRow("Software Update") {
                    Button("Check for Updates…", systemImage: "arrow.triangle.2.circlepath") {
                        softwareUpdates.checkForUpdates()
                    }
                    .disabled(!softwareUpdates.canCheckForUpdates)
                }
            }
        }
    }

    private func settingsScroll<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(currentSection.title)
                    .font(.title2.bold())
                content()
            }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
                .frame(maxWidth: 700, alignment: .leading)
        }
        .scrollIndicators(.never)
    }

    private func settingsGroup<Content: View>(
        _ title: String?,
        subtitle: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            if let title {
                Text(title).font(.headline)
            }
            GlassCard {
                VStack(alignment: .leading, spacing: 14, content: content)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let subtitle {
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func settingsToggleRow(
        _ title: String,
        isOn: Binding<Bool>,
        disabled: Bool = false
    ) -> some View {
        settingsControlRow(title) {
            Toggle("", isOn: isOn)
                .labelsHidden()
                .frame(width: 44, alignment: .trailing)
        }
        .opacity(disabled ? 0.5 : 1)
    }

    private func shortcutRow(_ action: ShortcutAction) -> some View {
        settingsLabeledControlRow {
            Label(action.title, systemImage: action.symbol)
        } control: {
            ShortcutRecorder(action: action)
        }
        .opacity(settings.shortcutsEnabled ? 1 : 0.5)
        .disabled(!settings.shortcutsEnabled)
    }

    private func intervalRow(
        _ title: String,
        symbol: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        settingsLabeledControlRow {
            Label(title, systemImage: symbol)
        } control: {
            VStack(alignment: .trailing, spacing: 6) {
                Text("\(value.wrappedValue) min").monospacedDigit()
                Slider(
                    value: Binding(
                        get: { Double(value.wrappedValue) },
                        set: { value.wrappedValue = Int($0.rounded()) }
                    ),
                    in: Double(range.lowerBound)...Double(range.upperBound),
                    step: 5
                )
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func gesturePresetPicker(_ gesture: HardwareGesture) -> some View {
        Picker("", selection: Binding(
            get: { settings.presetID(for: gesture) },
            set: { settings.setPresetID($0, for: gesture) }
        )) {
            Text("None").tag(nil as UUID?)
            ForEach(settings.presets) { preset in
                Label(preset.name, systemImage: preset.symbol).tag(preset.id as UUID?)
            }
        }
        .labelsHidden()
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func settingsControlRow<Control: View>(
        _ title: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        settingsLabeledControlRow {
            Text(title)
        } control: {
            control()
        }
    }

    private func settingsLabeledControlRow<LabelContent: View, Control: View>(
        @ViewBuilder label: () -> LabelContent,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            label()
            Spacer(minLength: 16)
            control()
                .frame(minWidth: 260, idealWidth: 340, maxWidth: 340, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
    }

    private var weekdayOptions: [(number: Int, label: String)] {
        [(2, "Mon"), (3, "Tue"), (4, "Wed"), (5, "Thu"), (6, "Fri"), (7, "Sat"), (1, "Sun")]
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
    }

    private var currentSection: SettingsSection {
        SettingsSection(rawValue: selectedSection) ?? .general
    }

    private var selection: Binding<SettingsSection?> {
        Binding(
            get: { currentSection },
            set: { selectedSection = ($0 ?? .general).rawValue }
        )
    }

    private func updateLoginItem(_ enabled: Bool) {
        do {
            try LoginItemManager.setEnabled(enabled)
            loginError = nil
        } catch {
            loginError = error.localizedDescription
            launchAtLogin = LoginItemManager.isEnabled
        }
    }
}
