import AppKit
import ApplicationServices
import IOKit.hid

enum PermissionController {
    static func isAccessibilityTrusted(prompt: Bool) -> Bool {
        if AXIsProcessTrusted() {
            return true
        }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func isInputMonitoringTrusted(prompt: Bool) -> Bool {
        let requestType = kIOHIDRequestTypeListenEvent
        if IOHIDCheckAccess(requestType) == kIOHIDAccessTypeGranted {
            return true
        }
        if prompt {
            return IOHIDRequestAccess(requestType)
        }
        return false
    }

    static func openAccessibilitySettings() {
        openPrivacyPane(anchor: "Privacy_Accessibility")
    }

    static func openInputMonitoringSettings() {
        _ = isInputMonitoringTrusted(prompt: true)
        openPrivacyPane(anchor: "Privacy_ListenEvent")
    }

    private static func openPrivacyPane(anchor: String) {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
