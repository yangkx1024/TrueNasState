import SwiftUI

struct AppsSection: View {
    @Environment(DashboardViewModel.self) private var viewModel

    var body: some View {
        SectionContainer(
            title: "Apps",
            systemImage: "square.grid.2x2.fill",
            onTap: { viewModel.navigate(to: .appList) }
        ) {
            let counts = viewModel.apps.reduce(into: (total: 0, running: 0, upgradeable: 0)) { acc, app in
                acc.total += 1
                if app.isRunning { acc.running += 1 }
                if app.hasUpgrade { acc.upgradeable += 1 }
            }
            let installed = counts.total == counts.running ? "\(counts.total)" : "\(counts.total) (\(counts.running) running)"
            Row(label: "Installed", value: installed)
            Row(label: "Upgradeable", value: "\(counts.upgradeable)")
        }
    }
}
