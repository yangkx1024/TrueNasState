import SwiftUI

/// Header used by subscreens of the dashboard (Apps, Settings): a back chevron
/// that returns to `.dashboard` plus a left-aligned title.
struct BackHeader: View {
    let title: LocalizedStringKey
    @Environment(DashboardViewModel.self) private var viewModel

    var body: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.navigate(to: .dashboard)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            Text(title)
                .font(.headline)
            Spacer()
        }
    }
}
