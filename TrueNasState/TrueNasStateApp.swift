import SwiftUI

@main
struct TrueNasStateApp: App {
    @State private var viewModel = DashboardViewModel()

    var body: some Scene {
        MenuBarExtra {
            RootMenuView()
                .environment(viewModel)
        } label: {
            MenuBarLabel(state: viewModel.authState, alertCount: viewModel.activeAlertCount)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabel: View {
    let state: AuthState
    let alertCount: Int

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "externaldrive.connected.to.line.below")
            statusDot
            if alertCount > 0 {
                Text("\(alertCount)")
                    .font(.system(size: 10, weight: .bold))
            }
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
    }

    private var color: Color {
        switch state {
        case .loggedIn: return .green
        case .connecting, .reconnecting: return .yellow
        case .loggedOut: return .red
        }
    }
}
