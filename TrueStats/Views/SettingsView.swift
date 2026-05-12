import SwiftUI

struct SettingsView: View {
    @Environment(DashboardViewModel.self) private var viewModel

    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { LoginItemController.isEnabled },
            set: { LoginItemController.setEnabled($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BackHeader(title: "Settings")
            Divider()

            Toggle(isOn: launchAtLogin) {
                Label("Launch at login", systemImage: "power")
                    .font(.callout)
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            Divider()

            Button(role: .destructive) {
                Task { await viewModel.logout() }
            } label: {
                Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
        }
    }

}
