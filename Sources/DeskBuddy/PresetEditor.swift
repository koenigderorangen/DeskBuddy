import AppKit
import SwiftUI

@MainActor
final class PresetEditorModel: ObservableObject {
    static let shared = PresetEditorModel()

    @Published var draft = DeskPreset(name: "New Position", heightCm: 90, symbol: "star", kind: .custom)
    @Published var isNew = true

    func beginEditing(_ preset: DeskPreset) {
        draft = preset
        isNew = false
    }

    func beginCreating(currentHeight: Double?) {
        draft = DeskPreset(name: "New Position", heightCm: currentHeight ?? 90, symbol: "star", kind: .custom)
        isNew = true
    }

    func commit() {
        if isNew {
            SettingsStore.shared.presets.append(draft)
        } else {
            SettingsStore.shared.updatePreset(draft)
        }
    }
}

struct PresetEditorView: View {
    @ObservedObject private var model = PresetEditorModel.shared
    let onCancel: () -> Void
    let onSave: () -> Void

    private let symbols: [(name: String, systemName: String)] = [
        ("Sitting", "chair"),
        ("Standing", "figure.stand"),
        ("Lowest Position", "arrow.down.to.line"),
        ("Highest Position", "arrow.up.to.line"),
        ("Walking", "figure.walk"),
        ("Laptop", "laptopcomputer"),
        ("Coffee Break", "cup.and.saucer"),
        ("Favorite", "star")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass(.regular.tint(.red.opacity(0.18))))
                .help("Cancel")
                Spacer()
                Text(model.isNew ? "New Position" : "Edit Position")
                    .font(.headline)
                Spacer()
                Button(action: onSave) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass(.regular.tint(.accentColor)))
                .disabled(model.draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                .help("Save")
            }

            HStack(spacing: 14) {
                Menu {
                    ForEach(symbols, id: \.systemName) { symbol in
                        Button { model.draft.symbol = symbol.systemName } label: {
                            Label(symbol.name, systemImage: symbol.systemName)
                        }
                    }
                } label: {
                    Image(systemName: model.draft.symbol)
                        .font(.title2)
                        .frame(width: 56, height: 56)
                }
                .menuStyle(.borderlessButton)
                .glassEffect(
                    .regular.tint(DeskBuddyDesign.trayGlassTint).interactive(),
                    in: RoundedRectangle(cornerRadius: 12)
                )

                VStack(spacing: 10) {
                    TextField("Name", text: $model.draft.name)
                        .textFieldStyle(.roundedBorder)
                    TextField("Height", value: $model.draft.heightCm, format: .number.precision(.fractionLength(1)))
                        .textFieldStyle(.roundedBorder)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Height")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(String(format: "%.1f cm", model.draft.heightCm))
                        .monospacedDigit()
                }
                Slider(
                    value: $model.draft.heightCm,
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
            .glassEffect(
                .regular.tint(DeskBuddyDesign.trayGlassTint),
                in: RoundedRectangle(cornerRadius: DeskBuddyDesign.compactCornerRadius)
            )

            Spacer(minLength: 0)
        }
        .padding(16)
    }
}
