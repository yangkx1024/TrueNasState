import AppKit
import SwiftUI

struct DashboardView: View {
    @Environment(DashboardViewModel.self) private var viewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.authState == .reconnecting {
                ReconnectingBanner(
                    host: viewModel.endpoint?.host,
                    lastUpdated: viewModel.lastUpdated
                )
            }

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
                Button { openPage("/ui/dashboard") } label: {
                    Text(viewModel.systemInfo?.hostname ?? viewModel.endpoint?.host ?? "TrueNAS")
                        .font(.headline)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.endpoint == nil)
                .pointingHandCursor()
                if let v = viewModel.systemInfo?.version {
                    HStack(spacing: 6) {
                        Text(v).foregroundStyle(.secondary)
                        if viewModel.systemUpdateAvailable {
                            LinkButton(label: "Update available") { openPage("/ui/system/update") }
                        }
                    }
                    .font(.caption)
                }
            }
            Spacer()
            LastUpdatedText(date: viewModel.lastUpdated)
        }
    }

    private struct LastUpdatedText: View {
        let date: Date?
        var body: some View {
            if let date {
                Text(date, format: .dateTime.hour().minute().second())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private struct ReconnectingBanner: View {
        let host: String?
        let lastUpdated: Date?

        var body: some View {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Reconnecting…")
                        .font(.caption).fontWeight(.medium)
                    if let host {
                        Text(host)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                LastUpdatedText(date: lastUpdated)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.yellow.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func openPage(_ path: String) {
        guard let endpoint = viewModel.endpoint,
              let url = URL(string: path, relativeTo: endpoint)
        else { return }
        NSWorkspace.shared.open(url)
    }

    private var footer: some View {
        HStack {
            Button {
                viewModel.navigate(to: .settings)
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.bordered)

            Button {
                Task { await viewModel.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(.bordered)
        }
    }
}
