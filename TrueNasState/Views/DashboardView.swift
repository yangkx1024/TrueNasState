import AppKit
import SwiftUI

struct DashboardView: View {
    @Environment(DashboardViewModel.self) private var viewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Divider()

            SystemInfoSection()
            PoolStatusSection()
            AppsSection()
            AlertsSection()

            Divider()

            footer
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.systemInfo?.hostname ?? viewModel.endpoint?.host ?? "TrueNAS")
                    .font(.headline)
                if let v = viewModel.systemInfo?.version {
                    HStack(spacing: 6) {
                        Text(v).foregroundStyle(.secondary)
                        if viewModel.systemUpdateAvailable {
                            LinkButton(label: "Update available", action: openSystemUpdatePage)
                        }
                    }
                    .font(.caption)
                }
            }
            Spacer()
            if let last = viewModel.lastUpdated {
                Text(last, format: .dateTime.hour().minute().second())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func openSystemUpdatePage() {
        guard let endpoint = viewModel.endpoint,
              let url = URL(string: "/ui/system/update", relativeTo: endpoint)
        else { return }
        NSWorkspace.shared.open(url)
    }

    private var footer: some View {
        HStack {
            Button {
                Task { await viewModel.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)

            Spacer()

            Button(role: .destructive) {
                Task { await viewModel.logout() }
            } label: {
                Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .buttonStyle(.bordered)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(.bordered)
        }
    }
}
