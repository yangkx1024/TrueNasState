import SwiftUI

struct SettingsView: View {
    @Environment(DashboardViewModel.self) private var viewModel
    @State private var loginItemError: String?

    /// The getter reads the live `SMAppService` status rather than a cached copy, so
    /// a rejected or approval-pending registration snaps the switch back to the
    /// truth. Writing `loginItemError` is what re-renders the view to make that
    /// snap-back visible.
    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { LoginItemController.isEnabled },
            set: { newValue in
                do {
                    try LoginItemController.setEnabled(newValue)
                    loginItemError = nil
                } catch {
                    loginItemError = error.localizedDescription
                }
            }
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

            if let loginItemError {
                Text(loginItemError)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

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
