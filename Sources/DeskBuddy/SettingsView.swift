import ServiceManagement
import SwiftUI

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case interactions
    case shortcuts
    case coach
    case about

    var id: Self { self }
    var title: String {
        switch self {
        case .general: "General"
        case .interactions: "Interactions"
        case .shortcuts: "Keyboard Shortcuts"
        case .coach: "Posture Coach"
        case .about: "About"
        }
    }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .interactions: "hand.tap"
        case .shortcuts: "keyboard"
        case .coach: "figure.mind.and.body"
        case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @State private var selection: SettingsSection? = .general
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
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
        switch selection ?? .general {
        case .general: generalSettings
        case .interactions: interactionSettings
        case .shortcuts: shortcutSettings
        case .coach: coachSettings
        case .about: aboutSettings
        }
    }

    private var generalSettings: some View {
        settingsScroll {
            settingsGroup("Menu Bar", subtitle: "Choose what DeskBuddy displays in the macOS menu bar.") {
                Picker("Presentation", selection: $settings.menuBarPresentation) {
                    ForEach(MenuBarPresentation.allCases) { option in Text(option.title).tag(option) }
                }
                .pickerStyle(.segmented)
            }

            settingsGroup("Display") {
                Picker("Precision", selection: $settings.heightPrecision) {
                    ForEach(HeightPrecision.allCases) { option in Text(option.title).tag(option) }
                }
                .pickerStyle(.segmented)
                Picker("Unit", selection: $settings.useInches) {
                    Text("Metric (cm)").tag(false)
                    Text("Imperial (inches)").tag(true)
                }
                .pickerStyle(.segmented)
            }

            settingsGroup("Appearance") {
                Picker("Theme", selection: $settings.theme) {
                    ForEach(DeskBuddyTheme.allCases) { theme in Text(theme.title).tag(theme) }
                }
                .pickerStyle(.segmented)
                Toggle("Automatically reconnect", isOn: $settings.autoReconnect)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in updateLoginItem(enabled) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
        }
    }

    private var interactionSettings: some View {
        settingsScroll {
            settingsGroup(
                "Double-Tap Gesture",
                subtitle: "Tap the physical desk control twice: down twice for sitting, up twice for standing."
            ) {
                Toggle("Enable double-tap gesture", isOn: $settings.doubleTapEnabled)
            }

            settingsGroup("Safety") {
                Label("Releasing the control stops manual movement immediately.", systemImage: "hand.raised.fill")
                Label("Targeted movements stop after 30 seconds at the latest.", systemImage: "timer")
                Label("DeskBuddy stops sending commands if the connection is lost.", systemImage: "antenna.radiowaves.left.and.right.slash")
            }
        }
    }

    private var shortcutSettings: some View {
        settingsScroll {
            settingsGroup("Global Keyboard Shortcuts", subtitle: "Available from any app.") {
                Toggle("Enable keyboard shortcuts", isOn: $settings.shortcutsEnabled)
                shortcutRow("First saved position", symbol: "1.circle", shortcut: "⌃⌥1")
                shortcutRow("Second saved position", symbol: "2.circle", shortcut: "⌃⌥2")
                shortcutRow("Move up (hold)", symbol: "arrow.up", shortcut: "⌃⌥↑")
                shortcutRow("Move down (hold)", symbol: "arrow.down", shortcut: "⌃⌥↓")
                shortcutRow("Stop immediately", symbol: "stop.fill", shortcut: "⌃⌥0")
            }

            settingsGroup("Shortcuts & Siri") {
                Label("Sitting, standing, target height, stop, and current height actions are available in Shortcuts.", systemImage: "command")
            }
        }
    }

    private var coachSettings: some View {
        settingsScroll {
            settingsGroup("Posture Coach") {
                Toggle("Enable Posture Coach", isOn: $settings.coachEnabled)
                    .onChange(of: settings.coachEnabled) { _, enabled in
                        if enabled { PostureCoach.shared.requestPermission() }
                        PostureCoach.shared.resetSchedule()
                    }
                Toggle("Gently remind me to change position", isOn: $settings.coachReminderEnabled)
                    .disabled(!settings.coachEnabled)
                Toggle("Automatically move desk after countdown", isOn: $settings.automaticMovementEnabled)
                    .disabled(!settings.coachEnabled)

                if settings.automaticMovementEnabled {
                    Stepper(
                        "Cancel countdown: \(settings.movementCountdownSeconds) seconds",
                        value: $settings.movementCountdownSeconds,
                        in: 5...60,
                        step: 5
                    )
                }
            }

            settingsGroup("Intervals") {
                intervalRow("Sitting interval", symbol: "chair", value: $settings.sittingIntervalMinutes, range: 10...120)
                Divider()
                intervalRow("Standing interval", symbol: "figure.stand", value: $settings.standingIntervalMinutes, range: 5...60)
            }

            settingsGroup("Schedule", subtitle: "The coach stays quiet outside these hours.") {
                HStack {
                    Picker("From", selection: $settings.activeStartHour) {
                        ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                    }
                    Picker("To", selection: $settings.activeEndHour) {
                        ForEach(1...24, id: \.self) { Text(String(format: "%02d:00", $0 % 24)).tag($0) }
                    }
                }
                HStack(spacing: 7) {
                    ForEach(weekdayOptions, id: \.number) { day in
                        Button(day.label) {
                            if settings.activeWeekdays.contains(day.number) {
                                settings.activeWeekdays.remove(day.number)
                            } else {
                                settings.activeWeekdays.insert(day.number)
                            }
                        }
                        .buttonStyle(.glass(
                            .regular.tint(settings.activeWeekdays.contains(day.number) ? .accentColor.opacity(0.45) : nil)
                        ))
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private var aboutSettings: some View {
        settingsScroll {
            settingsGroup("DeskBuddy") {
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
            }
        }
    }

    private func settingsScroll<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(selection?.title ?? "DeskBuddy")
                    .font(.title2.bold())
                    .padding(.bottom, 2)
                content()
            }
                .padding(24)
                .frame(maxWidth: 700, alignment: .leading)
        }
        .scrollIndicators(.never)
    }

    private func settingsGroup<Content: View>(
        _ title: String,
        subtitle: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.headline)
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

    private func shortcutRow(_ title: String, symbol: String, shortcut: String) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            Text(shortcut)
                .font(.system(.body, design: .rounded).weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .glassEffect(.clear, in: Capsule())
        }
    }

    private func intervalRow(
        _ title: String,
        symbol: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                Text("\(value.wrappedValue) min").monospacedDigit()
            }
            Slider(
                value: Binding(
                    get: { Double(value.wrappedValue) },
                    set: { value.wrappedValue = Int($0.rounded()) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 5
            )
        }
    }

    private var weekdayOptions: [(number: Int, label: String)] {
        [(2, "Mon"), (3, "Tue"), (4, "Wed"), (5, "Thu"), (6, "Fri"), (7, "Sat"), (1, "Sun")]
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
    }

    private func updateLoginItem(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
