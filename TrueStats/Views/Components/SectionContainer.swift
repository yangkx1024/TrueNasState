import SwiftUI

/// A titled dashboard section, optionally tappable to drill into a subscreen.
struct SectionContainer<Content: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    var onTap: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let onTap {
                Button(action: onTap) { header }
                    .buttonStyle(.plain)
            } else {
                header
            }
            content()
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
                .font(.caption)
            Text(title)
                .font(.caption)
                .bold()
                .foregroundStyle(.secondary)
            if onTap != nil {
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }
}
