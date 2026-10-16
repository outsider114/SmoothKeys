import AppKit
import Darwin
import SwiftUI

@main
struct SmoothKeysApp {
    static func main() {
        if CommandLine.arguments.contains("--self-test") {
            let keyboardPassed = KeyboardMappingSelfTest.run()
            let mousePassed = MouseScrollSelfTest.run()
            exit(keyboardPassed && mousePassed ? EXIT_SUCCESS : EXIT_FAILURE)
        }
        if CommandLine.arguments.contains("--self-test-keyboard") {
            exit(KeyboardMappingSelfTest.run() ? EXIT_SUCCESS : EXIT_FAILURE)
        }
        if CommandLine.arguments.contains("--emit-test-scroll") {
            exit(MouseScrollSelfTest.emitScroll() ? EXIT_SUCCESS : EXIT_FAILURE)
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusItemController?
    private var windowController: SettingsWindowController?
    private let appState = AppState()
    private let launchMode = LaunchMode.current
    private var isSwitchingMode = false
    private var isQuitting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        windowController = SettingsWindowController(appState: appState) { [weak self] in
            self?.switchToAgentMode()
        }
        statusController = StatusItemController { [weak self] in
            self?.showSettingsWindow()
        }
        appState.start()
        if launchMode == .ui {
            showSettingsWindow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.stop(clearKeyboardMappings: !isSwitchingMode)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        isQuitting = true
        return .terminateNow
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettingsWindow()
        return true
    }

    private func showSettingsWindow() {
        if launchMode == .agent {
            isSwitchingMode = true
            RelaunchController.launchUI()
            NSApp.terminate(nil)
            return
        }
        ActivationPolicyController.showDock()
        windowController?.showWindow(nil)
        windowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func switchToAgentMode() {
        guard launchMode == .ui, !isSwitchingMode, !isQuitting else { return }
        isSwitchingMode = true
        RelaunchController.launchAgent()
        NSApp.terminate(nil)
    }
}
