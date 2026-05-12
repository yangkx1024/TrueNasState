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
        .onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
