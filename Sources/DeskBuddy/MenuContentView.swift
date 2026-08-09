import AppKit
import SwiftUI

struct MenuContentView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var controller: DeskController
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var coach = PostureCoach.shared
    @State private var showDeskSidebar = false
    @State private var editingPreset: DeskPreset?
    @State private var creatingPreset = false
    @State private var showingDiagnostics = false

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 0) {
                if showDeskSidebar {
                    deskSidebar
                        .frame(width: DeskBuddyDesign.sidebarWidth)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    Divider()
                }

                mainPanel
                    .frame(width: DeskBuddyDesign.contentWidth)
            }
        }
        .frame(
            width: DeskBuddyDesign.contentWidth + (showDeskSidebar ? DeskBuddyDesign.sidebarWidth + 1 : 0),
            height: 570
        )
        .animation(.snappy(duration: 0.28), value: showDeskSidebar)
        .sheet(item: $editingPreset) { preset in
            PresetEditorView(preset: preset, currentHeight: controller.heightCm) {
                settings.updatePreset($0)
            }
        }
        .sheet(isPresented: $creatingPreset) {
            PresetEditorView(preset: nil, currentHeight: controller.heightCm) {
                settings.presets.append($0)
            }
        }
    }

    private var mainPanel: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if controller.state.isConnected {
                connectedContent
            } else {
                disconnectedContent
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                showDeskSidebar.toggle()
            } label: {
                Image(systemName: "sidebar.leading")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.glass)
            .help("Desks")

            VStack(alignment: .leading, spacing: 1) {
                Text(connectedDeskName)
                    .font(.headline)
                    .lineLimit(1)
                Text(controller.state.title)
                    .font(.caption2)
                    .foregroundStyle(controller.state.isConnected ? DeskBuddyDesign.connected : .secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.glass)
            .help("Settings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var connectedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if coach.pendingMovement != nil {
                    countdownBanner
                }

                heightControls

                HStack {
                    Text("Saved Positions")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if controller.isMoving {
                        Button("Stop", systemImage: "stop.fill") {
                            controller.stopMovement()
                        }
                        .buttonStyle(.glass(.regular.tint(.red)))
                        .controlSize(.small)
                    }
                }

                presetGrid
            }
            .padding(16)
        }
        .scrollIndicators(.never)
    }

    private var heightControls: some View {
        HStack(spacing: 18) {
            PressAndHoldButton(
                title: "Move down",
                systemImage: "arrow.down",
                direction: .down,
                controller: controller
            )

            Spacer()

            VStack(spacing: 2) {
                Text(controller.heightCm.map(settings.formattedHeight) ?? "–")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if abs(controller.speedCmPerSecond) > 0.1 {
                    Text(controller.speedCmPerSecond > 0 ? "Moving up" : "Moving down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            PressAndHoldButton(
                title: "Move up",
                systemImage: "arrow.up",
                direction: .up,
                controller: controller
            )
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
    }

    private var presetGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(settings.presets) { preset in
                presetCard(preset)
            }

            Button {
                creatingPreset = true
            } label: {
                VStack(spacing: 7) {
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                    Text("Add")
                        .font(.subheadline.weight(.medium))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 100)
            }
            .buttonStyle(.glass)
        }
    }

    private func presetCard(_ preset: DeskPreset) -> some View {
        Button {
            controller.move(to: preset)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: preset.symbol)
                    .font(.title3)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(preset.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(settings.formattedHeight(preset.heightCm))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .frame(height: 100)
            .contentShape(RoundedRectangle(cornerRadius: DeskBuddyDesign.cornerRadius))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: DeskBuddyDesign.cornerRadius))
        .contextMenu {
            Button("Edit", systemImage: "pencil") { editingPreset = preset }
            Button("Update with Current Height", systemImage: "scope") {
                guard let height = controller.heightCm else { return }
                var updated = preset
                updated.heightCm = height
                settings.updatePreset(updated)
            }
            Divider()
            Button("Move Left", systemImage: "arrow.left") { settings.movePreset(preset, offset: -1) }
            Button("Move Right", systemImage: "arrow.right") { settings.movePreset(preset, offset: 1) }
            if preset.resolvedKind == .custom {
                Divider()
                Button("Delete", systemImage: "trash", role: .destructive) { settings.deletePreset(preset) }
            }
        }
    }

    private var countdownBanner: some View {
        GlassCard(tint: .orange.opacity(0.28), interactive: true) {
            HStack(spacing: 12) {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.title3)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Automatic Movement")
                        .font(.subheadline.weight(.semibold))
                    Text("\(coach.pendingMovement?.preset.name ?? "Position") in \(coach.remainingSeconds) seconds")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { coach.cancelPendingMovement() }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
            .padding(12)
        }
    }

    private var disconnectedContent: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "table.furniture")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            VStack(spacing: 5) {
                Text("No Desk Connected").font(.headline)
                Text("Open the desk list and connect your IDÅSEN.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Open Desks", systemImage: "sidebar.leading") {
                showDeskSidebar = true
            }
            .buttonStyle(.glass(.regular.tint(.accentColor)))
            Spacer()
        }
        .padding(24)
    }

    private var deskSidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Desks")
                .font(.headline)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(availableDesks) { desk in
                        GlassCard(
                            tint: desk.id == controller.connectedDeskID ? .green.opacity(0.22) : nil,
                            interactive: true
                        ) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "table.furniture")
                                        .foregroundStyle(desk.id == controller.connectedDeskID ? .green : .secondary)
                                    Text(desk.name).font(.subheadline.weight(.semibold))
                                    Spacer()
                                }
                                if desk.id == controller.connectedDeskID {
                                    HStack {
                                        Label("Connected", systemImage: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                        Spacer()
                                        Button("Disconnect") { controller.disconnect() }
                                            .buttonStyle(.glass)
                                            .controlSize(.small)
                                    }
                                    .font(.caption)
                                } else {
                                    Button("Connect") { controller.connect(to: desk) }
                                        .buttonStyle(.glass)
                                        .controlSize(.small)
                                }
                            }
                            .padding(12)
                        }
                    }
                }
            }
            .scrollIndicators(.never)

            Button(controller.state == .scanning ? "Scanning …" : "Search for New Desks", systemImage: "magnifyingglass") {
                controller.scan()
            }
            .buttonStyle(.glass(.regular.tint(.accentColor)))
            .disabled(controller.state == .scanning)

            DisclosureGroup("Diagnostics", isExpanded: $showingDiagnostics) {
                Text(controller.diagnosticsText)
                    .font(.system(size: 9, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(controller.diagnosticsText, forType: .string)
                }
                .controlSize(.small)
            }
            .font(.caption)

            Divider()
            Button("Quit DeskBuddy", systemImage: "power") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
    }

    private var connectedDeskName: String {
        if let id = controller.connectedDeskID,
           let desk = settings.savedDesks.first(where: { $0.id == id }) {
            return desk.name
        }
        return "DeskBuddy"
    }

    private var availableDesks: [SavedDesk] {
        var result = settings.savedDesks
        for desk in controller.discoveredDesks where !result.contains(where: { $0.id == desk.id }) {
            result.append(desk)
        }
        return result
    }
}

private struct PresetEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: DeskPreset
    let onSave: (DeskPreset) -> Void

    private let symbols = [
        "chair", "figure.stand", "arrow.down.to.line", "arrow.up.to.line",
        "figure.walk", "laptopcomputer", "cup.and.saucer", "star"
    ]

    init(preset: DeskPreset?, currentHeight: Double?, onSave: @escaping (DeskPreset) -> Void) {
        let initial = preset ?? DeskPreset(
            name: "New Position",
            heightCm: currentHeight ?? 90,
            symbol: "star",
            kind: .custom
        )
        _draft = State(initialValue: initial)
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Button("Cancel", systemImage: "xmark") { dismiss() }
                    .buttonStyle(.glass)
                Spacer()
                Text("Saved Position").font(.headline)
                Spacer()
                Button("Done", systemImage: "checkmark") {
                    onSave(draft)
                    dismiss()
                }
                .buttonStyle(.glass(.regular.tint(.accentColor)))
                .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            HStack(spacing: 14) {
                Menu {
                    ForEach(symbols, id: \.self) { symbol in
                        Button { draft.symbol = symbol } label: {
                            Label(symbol, systemImage: symbol)
                        }
                    }
                } label: {
                    Image(systemName: draft.symbol)
                        .font(.title)
                        .frame(width: 62, height: 62)
                }
                .menuStyle(.borderlessButton)
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16))

                VStack(spacing: 10) {
                    TextField("Name", text: $draft.name)
                        .textFieldStyle(.roundedBorder)
                    TextField("Height", value: $draft.heightCm, format: .number.precision(.fractionLength(1)))
                        .textFieldStyle(.roundedBorder)
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Height")
                        Spacer()
                        Text(String(format: "%.1f cm", draft.heightCm)).monospacedDigit()
                    }
                    Slider(
                        value: $draft.heightCm,
                        in: DeskProtocol.minimumHeightCm...DeskProtocol.maximumHeightCm,
                        step: 0.1
                    )
                    HStack {
                        Text("62 cm")
                        Spacer()
                        Text("127 cm")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .padding(14)
            }
        }
        .padding(18)
        .frame(width: 410)
    }
}
