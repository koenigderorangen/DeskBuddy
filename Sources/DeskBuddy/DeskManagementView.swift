import SwiftUI

struct DeskManagementView: View {
    @ObservedObject private var controller = DeskController.shared
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                connectionIndicator
                Spacer()
                Button(
                    controller.isScanning ? "Searching…" : "Find Desks",
                    systemImage: controller.isScanning ? "progress.indicator" : "magnifyingglass"
                ) {
                    controller.scan()
                }
                .disabled(controller.isScanning)
            }

            Divider()

            if availableDesks.isEmpty {
                ContentUnavailableView(
                    "No Desks Found",
                    systemImage: "table.furniture",
                    description: Text("Put your desk in pairing mode, then choose Find Desks.")
                )
                .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(availableDesks.enumerated()), id: \.element.id) { index, desk in
                        if index > 0 { Divider() }
                        deskRow(desk)
                            .padding(.vertical, 10)
                    }
                }
            }
        }
    }

    private var connectionIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(controller.state.isConnected ? DeskBuddyDesign.connected : Color.secondary)
                .frame(width: 8, height: 8)
            Text(controller.state.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
        }
    }

    private func deskRow(_ desk: SavedDesk) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "table.furniture")
                .font(.title3)
                .foregroundStyle(desk.id == controller.connectedDeskID ? DeskBuddyDesign.connected : .secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(desk.name)
                    .font(.subheadline.weight(.semibold))
                Text(desk.id == controller.connectedDeskID ? "Connected" : "Available")
                    .font(.caption)
                    .foregroundStyle(desk.id == controller.connectedDeskID ? DeskBuddyDesign.connected : .secondary)
            }

            Spacer()

            if desk.id == controller.connectedDeskID {
                Button("Disconnect", systemImage: "xmark.circle") {
                    controller.disconnect()
                }
            } else {
                Button("Connect", systemImage: "link") {
                    controller.connect(to: desk)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var availableDesks: [SavedDesk] {
        var desks = settings.savedDesks
        for desk in controller.discoveredDesks where !desks.contains(where: { $0.id == desk.id }) {
            desks.append(desk)
        }
        return desks
    }
}