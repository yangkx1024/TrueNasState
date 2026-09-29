import SwiftUI

/// Header used by subscreens of the dashboard (Apps, Settings): a back chevron
/// that returns to `.dashboard`, a left-aligned title, and optional trailing
/// content (e.g. a screen-level action).
struct BackHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var trailing: () -> Trailing
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
            trailing()
        }
    }
}

extension BackHeader where Trailing == EmptyView {
    init(title: LocalizedStringKey) {
        self.init(title: title) { EmptyView() }
    }
}
