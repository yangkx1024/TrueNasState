import AppKit
import Observation
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var lastBadge: (AuthState, Int)?
    private let viewModel = DashboardViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.image = Self.driveIcon
            button.imagePosition = .imageLeft
        }

        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: RootMenuView().environment(viewModel)
        )

        renderStatusItem()
    }

    private func renderStatusItem() {
        withObservationTracking {
            let state = viewModel.authState
            let count = viewModel.activeAlertCount
            if lastBadge?.0 != state || lastBadge?.1 != count {
                lastBadge = (state, count)
                statusItem.button?.attributedTitle = composeBadge(state: state, alertCount: count)
            }
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.renderStatusItem()
            }
        }
    }

    @objc private func handleClick(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            viewModel.navigate(to: .settings)
            showPopover()
        } else {
            togglePopover(sender)
        }
    }

    private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeFirstResponder(nil)
    }

    private static let driveIcon: NSImage = {
        let image = NSImage(named: "MenuBarIcon")!
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }()

    private func composeBadge(state: AuthState, alertCount: Int) -> NSAttributedString {
        let dotColor: NSColor?
        switch state {
        case .loggedIn: dotColor = nil
        case .connecting, .reconnecting: dotColor = .systemYellow
        case .loggedOut: dotColor = .systemRed
        }

        let result = NSMutableAttributedString()

        if let dotColor {
            result.append(NSAttributedString(
                string: " ●",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 8),
                    .foregroundColor: dotColor,
                    .baselineOffset: 1,
                ]
            ))
        }

        if alertCount > 0 {
            result.append(NSAttributedString(
                string: " \(alertCount)",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: .bold),
                    .foregroundColor: NSColor.labelColor,
                ]
            ))
        }

        return result
    }
}
