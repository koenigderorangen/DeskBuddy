import SwiftUI

struct PressAndHoldButton: View {
    let title: String
    let systemImage: String
    let direction: ManualDirection
    @ObservedObject var controller: DeskController
    var size: CGFloat = 52
    @State private var pressed = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 20, weight: .semibold))
            .frame(width: size, height: size)
            .contentShape(Circle())
            .glassEffect(
                Glass.regular
                    .tint(pressed ? Color.accentColor.opacity(0.55) : DeskBuddyDesign.trayGlassTint)
                    .interactive(),
                in: Circle()
            )
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressed else { return }
                        pressed = true
                        controller.startManual(direction)
                    }
                    .onEnded { _ in release() }
            )
            .onDisappear { release() }
            .accessibilityLabel(title)
            .accessibilityHint("Press and hold to move, release to stop")
    }

    private func release() {
        if pressed { controller.stopMovement() }
        pressed = false
    }
}
