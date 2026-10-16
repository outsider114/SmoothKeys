import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let onWindowClosed: () -> Void

    init(appState: AppState, onWindowClosed: @escaping () -> Void) {
        self.onWindowClosed = onWindowClosed
        let hostingController = NSHostingController(rootView: ContentView(appState: appState))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "SmoothKeys"
        window.setContentSize(NSSize(width: 460, height: 560))
        window.minSize = NSSize(width: 440, height: 520)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func showWindow(_ sender: Any?) {
        ActivationPolicyController.showDock()
        super.showWindow(sender)
    }

    func windowWillClose(_ notification: Notification) {
        onWindowClosed()
    }
}
