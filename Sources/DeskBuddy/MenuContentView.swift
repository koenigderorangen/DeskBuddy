import AppKit
import SwiftUI

struct MenuContentView: View {
    @Environment(\.openSettings) private var openSettings
    @ObservedObject var controller: DeskController
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var coach = PostureCoach.shared
    @State private var editorPresented = false
    @State private var hoveredPresetID: UUID?

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            mainPanel
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
                Text("Open Settings to find and connect your desk.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Manage Desks…", systemImage: "table.furniture") {
                openDeskSettings()
            }
            .buttonStyle(.glass(.regular.tint(.accentColor)))
            Spacer()
        }
        .padding(24)
    }

    private var connectedDeskName: String {
        if let id = controller.connectedDeskID,
           let desk = settings.savedDesks.first(where: { $0.id == id }) {
            return desk.name
        }
        return "DeskBuddy"
    }

    private func openDeskSettings() {
        UserDefaults.standard.set(SettingsSection.desks.rawValue, forKey: SettingsSection.storageKey)
        NSApplication.shared.activate(ignoringOtherApps: true)
        openSettings()
    }
}
