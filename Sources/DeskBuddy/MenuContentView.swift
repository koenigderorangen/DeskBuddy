import AppKit
import SwiftUI

struct MenuContentView: View {
    @Environment(\.openSettings) private var openSettings
    @ObservedObject var controller: DeskController
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var coach = PostureCoach.shared
    @State private var sidebarVisible = false
    @State private var editorPresented = false
    @State private var hoveredPresetID: UUID?

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            ZStack(alignment: .leading) {
                mainPanel

                if sidebarVisible {
                    deskSidebar
                        .frame(width: DeskBuddyDesign.sidebarWidth)
                        .background(.regularMaterial)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                        .zIndex(1)
                }
            }
        }
        .frame(width: DeskBuddyDesign.contentWidth, height: 480)
        .clipped()
    }

    private func editPreset(_ preset: DeskPreset) {
        PresetEditorModel.shared.beginEditing(preset)
        withAnimation(.snappy(duration: 0.32)) {
            editorPresented = true
        }
    }

    private func createPreset() {
        PresetEditorModel.shared.beginCreating(currentHeight: controller.heightCm)
        withAnimation(.snappy(duration: 0.32)) {
            editorPresented = true
        }
    }

    private func closeEditor() {
        withAnimation(.snappy(duration: 0.32)) {
            editorPresented = false
        }
    }

    private func saveEditor() {
        PresetEditorModel.shared.commit()
        closeEditor()
    }

    private func setSidebarVisible(_ visible: Bool) {
        guard visible != sidebarVisible else { return }
        withAnimation(.snappy(duration: 0.28)) {
            sidebarVisible = visible
        }
    }

    private var mainPanel: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ZStack {
                if editorPresented {
                    PresetEditorView(onCancel: closeEditor, onSave: saveEditor)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else if controller.state.isConnected {
                    connectedContent
                        .transition(.move(edge: .leading).combined(with: .opacity))
                } else {
                    disconnectedContent
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .frame(maxHeight: .infinity)
            .clipped()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                setSidebarVisible(!sidebarVisible)
            } label: {
                Image(systemName: "sidebar.leading")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.glass(.regular.tint(DeskBuddyDesign.trayGlassTint)))
            .help("Desks")

            Text(connectedDeskName)
                .font(.headline)
                .lineLimit(1)

            if controller.state.isConnected {
                Circle()
                    .fill(DeskBuddyDesign.connected)
                    .frame(width: 7, height: 7)
                    .help(controller.state.title)
            } else {
                Text(controller.state.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.glass(.regular.tint(DeskBuddyDesign.trayGlassTint)))
            .help("Settings")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var connectedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if coach.pendingMovement != nil {
                    countdownBanner
                }

                heightControls

                HStack {
                    Text("Saved Positions")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if controller.isMoving {
                        Button("Stop", systemImage: "stop.fill") {
                            controller.stopMovement()
                        }
                        .buttonStyle(.glass(.regular.tint(.red)))
                        .controlSize(.small)
                    } else {
                        Button {
                            createPreset()
                        } label: {
                            Image(systemName: "plus")
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.glass(.regular.tint(DeskBuddyDesign.trayGlassTint)))
                        .controlSize(.small)
                        .help("Add Position")
                    }
                }

                presetGrid
            }
            .padding(14)
        }
        .scrollIndicators(.never)
    }

    private var heightControls: some View {
        HStack(spacing: 14) {
            PressAndHoldButton(
                title: "Move down",
                systemImage: "arrow.down",
                direction: .down,
                controller: controller
            )

            Spacer()

            VStack(spacing: 2) {
                Text(controller.heightCm.map(settings.formattedHeight) ?? "–")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: true, vertical: false)
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
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    private var presetGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(settings.presets) { preset in
                presetCard(preset)
            }
        }
    }

    private func presetCard(_ preset: DeskPreset) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                controller.move(to: preset)
            } label: {
                VStack(spacing: 5) {
                    Image(systemName: preset.symbol)
                        .font(.title3)
                    Text(preset.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(settings.formattedHeight(preset.heightCm))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity)
                .frame(height: 104)
                .contentShape(RoundedRectangle(cornerRadius: DeskBuddyDesign.cornerRadius))
            }
            .buttonStyle(.plain)

            if hoveredPresetID == preset.id {
                Button {
                    editPreset(preset)
                } label: {
                    Image(systemName: "pencil")
                        .font(.caption.weight(.semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.glass(.regular.tint(.accentColor)))
                .controlSize(.small)
                .padding(6)
                .transition(.scale.combined(with: .opacity))
                .help("Edit \(preset.name)")
            }
        }
        .glassEffect(
            .regular.tint(DeskBuddyDesign.trayGlassTint).interactive(),
            in: RoundedRectangle(cornerRadius: DeskBuddyDesign.cornerRadius)
        )
        .onHover { isHovered in
            withAnimation(.easeOut(duration: 0.16)) {
                hoveredPresetID = isHovered ? preset.id : nil
            }
        }
        .contextMenu {
            Button("Edit", systemImage: "pencil") { editPreset(preset) }
            Button("Update with Current Height", systemImage: "scope") {
                guard let height = controller.heightCm else { return }
                var updated = preset
                updated.heightCm = height
                settings.updatePreset(updated)
            }
            Divider()
            Button("Move Left", systemImage: "arrow.left") {
                settings.movePreset(preset, offset: -1)
            }
            Button("Move Right", systemImage: "arrow.right") {
                settings.movePreset(preset, offset: 1)
            }
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
                setSidebarVisible(true)
            }
            .buttonStyle(.glass(.regular.tint(.accentColor)))
            Spacer()
        }
        .padding(24)
    }

    private var deskSidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Desks")
                    .font(.headline)
                Spacer()
                Button {
                    setSidebarVisible(false)
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.glass(.regular.tint(DeskBuddyDesign.trayGlassTint)))
                .help("Close Desks")
            }
            .padding(14)

            List(selection: deskSelection) {
                Section {
                    ForEach(availableDesks) { desk in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(desk.name)
                                    .font(.subheadline.weight(.semibold))
                                if desk.id == controller.connectedDeskID {
                                    Text("Connected")
                                        .font(.caption2)
                                        .foregroundStyle(DeskBuddyDesign.connected)
                                }
                            }
                        } icon: {
                            Image(systemName: "table.furniture")
                                .foregroundStyle(
                                    desk.id == controller.connectedDeskID ? DeskBuddyDesign.connected : .secondary
                                )
                        }
                        .tag(desk.id)
                        .contextMenu {
                            if desk.id == controller.connectedDeskID {
                                Button("Disconnect", systemImage: "xmark.circle") { controller.disconnect() }
                            } else {
                                Button("Connect", systemImage: "link") { controller.connect(to: desk) }
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            VStack(alignment: .leading, spacing: 10) {
                Button(controller.isScanning ? "Searching …" : "Find Desks", systemImage: "magnifyingglass") {
                    controller.scan()
                }
                .buttonStyle(.glass(.regular.tint(DeskBuddyDesign.trayGlassTint)))
                .disabled(controller.isScanning)

                if controller.connectedDeskID != nil {
                    Button("Disconnect", systemImage: "xmark.circle") {
                        controller.disconnect()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                Divider()
                Button("Quit DeskBuddy", systemImage: "power") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(14)
        }
    }

    private var deskSelection: Binding<UUID?> {
        Binding(
            get: { controller.connectedDeskID },
            set: { selectedID in
                guard let selectedID,
                      let desk = availableDesks.first(where: { $0.id == selectedID }) else { return }
                controller.connect(to: desk)
            }
        )
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
