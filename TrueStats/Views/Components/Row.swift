import SwiftUI

/// A label/value line inside a `SectionContainer`.
struct Row: View {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).foregroundStyle(.primary)
        }
        .font(.caption)
    }
}
