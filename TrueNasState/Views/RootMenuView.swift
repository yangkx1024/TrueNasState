import SwiftUI

struct RootMenuView: View {
    @Environment(DashboardViewModel.self) private var viewModel

    var body: some View {
        Group {
            switch viewModel.authState {
            case .loggedIn, .reconnecting:
                switch viewModel.screen {
                case .dashboard: DashboardView()
                case .appList:   AppListView()
                }
            case .connecting:
                ConnectingView()
            case .loggedOut:
                LoginView()
            }
        }
        .frame(width: 260)
        .padding(12)
    }
}

private struct ConnectingView: View {
    @Environment(DashboardViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Connecting to TrueNAS…")
                .font(.callout)
                .foregroundStyle(.secondary)
            if let host = viewModel.endpoint?.host {
                Text(host).font(.caption).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }
}
