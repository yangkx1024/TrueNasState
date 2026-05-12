import AppKit
import SwiftUI
import WebKit

struct AppListView: View {
    @Environment(DashboardViewModel.self) private var viewModel

    var body: some View {
        let apps = viewModel.apps.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        let lastID = apps.last?.id
        VStack(alignment: .leading, spacing: 8) {
            BackHeader(title: "Apps")
            Divider()
            if apps.isEmpty {
                Text("No apps installed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                OverlayScrollView(minHeight: 360, maxHeight: 720) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(apps) { app in
                            AppRow(
                                app: app,
                                stat: viewModel.appStats[app.id],
                                iconURL: viewModel.appIcons[app.catalogName ?? app.name],
                                isUpgrading: viewModel.upgradingApps.contains(app.id),
                                onUpgrade: { Task { await viewModel.upgradeApp(app) } }
                            )
                            if app.id != lastID {
                                Divider()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

}

private struct AppRow: View {
    let app: TNApp
    let stat: AppLiveStat?
    let iconURL: URL?
    let isUpgrading: Bool
    let onUpgrade: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            AppIcon(url: iconURL)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(app.name).font(.headline).lineLimit(1)
                    if let version = app.version {
                        Text(version)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if let state = app.state {
                        StateDot(state: state)
                    }
                }
                HStack(spacing: 12) {
                    Label(stat?.cpuText ?? "—", systemImage: "cpu")
                    Label(stat?.memoryText ?? "—", systemImage: "memorychip")
                    Spacer()
                    upgradeIndicator
                }
                .labelStyle(.titleAndIcon)
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var upgradeIndicator: some View {
        if isUpgrading {
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("Updating…").foregroundStyle(.orange)
            }
        } else if app.hasUpgrade {
            LinkButton(label: "Update", action: onUpgrade)
        } else {
            Text("Up to date").foregroundStyle(.green)
        }
    }
}

private struct AppIcon: View {
    let url: URL?

    var body: some View {
        Group {
            if let url, url.pathExtension.lowercased() == "svg" {
                SVGIconView(url: url).padding(2)
            } else {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .padding(2)
                    default:
                        Image(systemName: "shippingbox")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(width: 32, height: 32)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// Third-party SVG libraries (SwiftDraw, SVGView) each fail on different
/// real-world catalog icons. The only renderer that handles every valid SVG
/// is WebKit. We render each unique URL exactly once via an off-screen
/// WKWebView, snapshot the result to an NSImage, and cache that — after the
/// first hit each row reads a plain raster image, no WebKit involved.
private struct SVGIconView: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "shippingbox")
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: url) {
            image = await SVGIconCache.shared.image(for: url)
        }
    }
}

@MainActor
private final class SVGIconCache {
    static let shared = SVGIconCache()

    private var cache: [URL: NSImage] = [:]
    private var inflight: [URL: Task<NSImage?, Never>] = [:]
    private let renderSize = CGSize(width: 64, height: 64)

    func image(for url: URL) async -> NSImage? {
        if let cached = cache[url] { return cached }
        if let task = inflight[url] { return await task.value }
        let task = Task<NSImage?, Never> { [renderSize] in
            await renderSVG(url: url, size: renderSize)
        }
        inflight[url] = task
        let image = await task.value
        inflight[url] = nil
        if let image { cache[url] = image }
        return image
    }
}

@MainActor
private func renderSVG(url: URL, size: CGSize) async -> NSImage? {
    let webView = WKWebView(frame: CGRect(origin: .zero, size: size))
    webView.setValue(false, forKey: "drawsBackground")
    let delegate = SVGWebViewDelegate()
    webView.navigationDelegate = delegate
    let html = """
    <!doctype html><html><head><meta charset='utf-8'>
    <style>html,body{margin:0;padding:0;background:transparent;width:\(Int(size.width))px;height:\(Int(size.height))px;}
    body{display:flex;align-items:center;justify-content:center;}
    img{max-width:100%;max-height:100%;}</style></head>
    <body><img src='\(url.absoluteString)'/></body></html>
    """
    webView.loadHTMLString(html, baseURL: nil)
    await delegate.waitForFinish()
    // Give the <img> a beat to lay out after navigation finishes.
    try? await Task.sleep(nanoseconds: 100_000_000)
    let config = WKSnapshotConfiguration()
    config.rect = CGRect(origin: .zero, size: size)
    return try? await webView.takeSnapshot(configuration: config)
}

private final class SVGWebViewDelegate: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Never>?

    func waitForFinish() async {
        await withCheckedContinuation { self.continuation = $0 }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume(); continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(); continuation = nil
    }
}

private struct StateDot: View {
    let state: AppState

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 4, height: 4)
            Text(state.displayName)
                .font(.caption2)
                .foregroundStyle(color)
        }
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch state {
        case .running: return .green
        case .deploying, .stopping: return .yellow
        case .crashed: return .red
        case .stopped: return .secondary
        }
    }
}

private struct OverlayScrollView<Content: View>: NSViewRepresentable {
    let minHeight: CGFloat
    let maxHeight: CGFloat
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

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        let width = proposal.width ?? nsView.documentView?.fittingSize.width ?? 0
        let docHeight = nsView.documentView?.fittingSize.height ?? 0
        let height = min(maxHeight, max(minHeight, docHeight))
        return CGSize(width: width, height: height)
    }
}
