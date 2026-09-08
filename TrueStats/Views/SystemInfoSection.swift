import SwiftUI

struct SystemInfoSection: View {
    @Environment(DashboardViewModel.self) private var viewModel

    var body: some View {
        SectionContainer(title: "System", systemImage: "cpu.fill") {
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
