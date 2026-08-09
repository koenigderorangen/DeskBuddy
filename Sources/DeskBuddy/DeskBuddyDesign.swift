import SwiftUI

enum DeskBuddyDesign {
    static let cornerRadius: CGFloat = 18
    static let compactCornerRadius: CGFloat = 14
    static let contentWidth: CGFloat = 420
    static let sidebarWidth: CGFloat = 250

    static let accent = Color.accentColor
    static let connected = Color.green
}

struct GlassCard<Content: View>: View {
    var tint: Color?
    var interactive = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .glassEffect(
                Glass.regular.tint(tint).interactive(interactive),
                in: RoundedRectangle(cornerRadius: DeskBuddyDesign.cornerRadius, style: .continuous)
            )
    }
}
