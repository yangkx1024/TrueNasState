import AppKit
import SwiftUI

/// Plain-text button that renders like an orange underlined link with a
/// pointing-hand cursor on hover. Used for inline "Update" affordances
/// that either trigger an in-app action or open a URL.
struct LinkButton: View {
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label).foregroundStyle(.orange).underline()
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }
}

extension View {
    func pointingHandCursor() -> some View {
        modifier(PointingHandCursor())
    }
}

/// Pushes `NSCursor.pointingHand` while the pointer is over the view, balancing
/// the push on hover-exit and on view removal. Without the `isHovering` guard
/// a stray `.onDisappear` would pop an unrelated cursor frame and shift the
/// system cursor stack permanently.
private struct PointingHandCursor: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                guard inside != isHovering else { return }
                isHovering = inside
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .onDisappear {
                if isHovering { NSCursor.pop(); isHovering = false }
            }
    }
}
