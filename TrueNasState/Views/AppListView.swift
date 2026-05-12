import AppKit
import SwiftUI

struct AppListView: View {
    @Environment(DashboardViewModel.self) private var viewModel

    var body: some View {
        let apps = viewModel.apps.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        let lastID = apps.last?.id
        VStack(alignment: .leading, spacing: 8) {
            header
            Divider()
            if apps.isEmpty {
                Text("No apps installed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                OverlayScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(apps) { app in
                            AppRow(app: app)
                            if app.id != lastID {
                                Divider()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 360)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.navigate(to: .dashboard)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            Text("Apps")
                .font(.headline)
            Spacer()
        }
    }
}

private struct AppRow: View {
    let app: TNApp

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).font(.caption).bold()
                if let state = app.state {
                    Text(state.rawValue).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if app.hasUpgrade {
                Label("Update", systemImage: "arrow.up.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var dotColor: Color {
        switch app.state {
        case .running: return .green
        case .deploying, .stopping: return .yellow
        case .crashed: return .red
        case .stopped, .none: return .secondary
        }
    }
}

private struct OverlayScrollView<Content: View>: NSViewRepresentable {
    @ViewBuilder var content: () -> Content

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        let host = NSHostingView(rootView: content())
        host.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = host
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            host.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            host.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        (scroll.documentView as? NSHostingView<Content>)?.rootView = content()
    }
}
