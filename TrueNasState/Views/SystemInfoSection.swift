import SwiftUI

struct SystemInfoSection: View {
    @Environment(DashboardViewModel.self) private var viewModel

    var body: some View {
        SectionContainer(title: "System", systemImage: "info.circle") {
            let info = viewModel.systemInfo
            let stats = viewModel.stats
            if info == nil && stats == nil {
                Text("Loading system info…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                if let uptime = info?.formattedUptime {
                    Row(label: "Uptime", value: uptime)
                }
                if let cpu = stats?.cpuUsagePercent {
                    Row(label: "CPU Usage", value: String(format: "%.1f%%", cpu))
                }
                if let load = info?.loadAverage1m {
                    Row(label: "CPU Load", value: String(format: "%.2f", load))
                }
                if let used = stats?.formattedMemory, let frac = stats?.memoryFraction {
                    Row(label: "Memory Usage", value: "\(used) (\(String(format: "%.0f%%", frac * 100)))")
                }
            }
        }
    }
}

struct Row: View {
    let label: String
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

struct SectionContainer<Content: View>: View {
    let title: String
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
