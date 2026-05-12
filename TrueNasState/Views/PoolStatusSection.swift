import SwiftUI

struct PoolStatusSection: View {
    @Environment(DashboardViewModel.self) private var viewModel

    var body: some View {
        SectionContainer(title: "Pools", systemImage: "externaldrive.fill") {
            if viewModel.pools.isEmpty {
                Text("No pools reported.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.pools) { pool in
                    PoolRow(pool: pool)
                }
            }
        }
    }
}

private struct PoolRow: View {
    let pool: Pool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Circle()
                    .fill(pool.isHealthy ? .green : .red)
                    .frame(width: 6, height: 6)
                Text(pool.name).font(.caption).bold()
                if let line = pool.formattedUsage {
                    Text("(\(line))").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Text(pool.displayStatus)
                    .font(.caption2)
                    .foregroundStyle(pool.isHealthy ? Color.secondary : Color.red)
            }
            if let usage = pool.usageFraction {
                ProgressView(value: usage)
                    .controlSize(.mini)
                    .tint(usage > 0.9 ? .red : (usage > 0.75 ? .orange : .accentColor))
            }
        }
    }
}
