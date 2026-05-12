import SwiftUI

struct AlertsSection: View {
    @Environment(DashboardViewModel.self) private var viewModel

    var body: some View {
        SectionContainer(title: "Alerts", systemImage: "bell.badge") {
            let active = viewModel.alerts.filter { $0.isActive }
            if active.isEmpty {
                HStack {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                    Text("No active alerts.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("\(active.count) active")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(active.prefix(4)) { alert in
                    AlertRow(alert: alert)
                }
                if active.count > 4 {
                    Text("… and \(active.count - 4) more")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }
}

private struct AlertRow: View {
    let alert: TNAlert

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: style.icon)
                .foregroundStyle(style.color)
                .font(.caption)
            Text(alert.displayText)
                .font(.caption)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var style: (color: Color, icon: String) {
        switch (alert.level ?? "").uppercased() {
        case "CRITICAL", "ALERT", "EMERGENCY": return (.red, "exclamationmark.triangle.fill")
        case "ERROR": return (.orange, "exclamationmark.triangle.fill")
        case "WARNING": return (.yellow, "exclamationmark.circle.fill")
        default: return (.secondary, "info.circle.fill")
        }
    }
}
