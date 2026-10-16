import AppKit
import Carbon

@MainActor
enum ActivationPolicyController {
    static func showDock() {
        transform(to: ProcessApplicationTransformState(kProcessTransformToForegroundApplication))
        NSApp.setActivationPolicy(.regular)
    }

    static func hideDock() {
        NSApp.hide(nil)
        transform(to: ProcessApplicationTransformState(kProcessTransformToUIElementApplication))
        NSApp.setActivationPolicy(.accessory)
    }

    private static func transform(to state: ProcessApplicationTransformState) {
        var psn = ProcessSerialNumber(highLongOfPSN: 0, lowLongOfPSN: UInt32(kCurrentProcess))
        TransformProcessType(&psn, state)
    }
}
