import AppKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let openSettings: () -> Void

    init(openSettings: @escaping () -> Void) {
        self.openSettings = openSettings
        super.init()
        if let button = statusItem.button {
            button.image = AppIconFactory.menuBarImage()
            button.imagePosition = .imageOnly
            button.action = #selector(openWindow)
            button.target = self
            button.toolTip = "SmoothKeys"
        }
    }

    @objc private func openWindow() {
        openSettings()
    }
}
