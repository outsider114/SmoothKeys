import AppKit
import Combine
import ServiceManagement

@MainActor
final class AppState: ObservableObject {
    @Published var selectedTab: AppTab = .mouse

    @Published var settings: AppSettings {
        didSet {
            guard !isLoading else { return }
            SettingsStore.save(settings)
            applySettings()
        }
    }

    @Published var keyboards: [KeyboardDevice] = []
    @Published var inputSources: [InputSource] = []
    @Published var accessibilityTrusted: Bool = false
    @Published var inputMonitoringTrusted: Bool = false
    @Published var eventTapRunning: Bool = false
    @Published var mouseDiagnostics = MouseDiagnostics()
    @Published var mouseConflictDetected: Bool = false
    @Published var keyboardMappingStatus: String = "未选择外接键盘"
    @Published var mappedKeyboardIDs: Set<String> = []
    @Published var launchAtLoginEnabled: Bool = false
    @Published var appLocation: String = Bundle.main.bundlePath

    private let mouseController = MouseController()
    private let keyboardController = KeyboardMappingController()
    private let inputController = InputMethodController()
    private var permissionTimer: Timer?
    private var isLoading = true

    init() {
        settings = SettingsStore.load()
        refreshSystemState()
        isLoading = false
    }

    func start() {
        if !accessibilityTrusted || !inputMonitoringTrusted {
            selectedTab = .system
        }

        keyboardController.onDevicesChanged = { [weak self] devices in
            Task { @MainActor in
                guard let self else { return }
                self.keyboards = devices
                self.migrateLegacyKeyboardIDs(using: devices)
            }
        }
        keyboardController.onMappingStatusChanged = { [weak self] status, mappedIDs in
            Task { @MainActor in
                self?.keyboardMappingStatus = status
                self?.mappedKeyboardIDs = mappedIDs
            }
        }
        inputController.onSourcesChanged = { [weak self] sources in
            Task { @MainActor in
                self?.inputSources = sources
            }
        }

        keyboardController.start()
        inputController.start()
        applySettings()

        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshSystemState()
            }
        }
    }

    func stop(clearKeyboardMappings: Bool = true) {
        permissionTimer?.invalidate()
        mouseController.stop()
        keyboardController.stop(clearMappings: clearKeyboardMappings)
        inputController.stop()
    }

    func applySettings() {
        mouseController.update(settings: settings.mouse)
        keyboardController.update(selectedDeviceIDs: settings.keyboard.selectedDeviceIDs, enabled: settings.keyboard.enabled)
        inputController.update(lockEnabled: settings.inputMethod.lockEnabled, selectedSourceID: settings.inputMethod.selectedSourceID)
        refreshSystemState()
    }

    func refreshSystemState() {
        let wasAccessibilityTrusted = accessibilityTrusted
        accessibilityTrusted = PermissionController.isAccessibilityTrusted(prompt: false)
        inputMonitoringTrusted = PermissionController.isInputMonitoringTrusted(prompt: false)
        mouseConflictDetected = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.caldis.Mos" && !$0.isTerminated
        }
        mouseController.setMosConflict(mouseConflictDetected)
        eventTapRunning = mouseController.isRunning
        mouseDiagnostics = mouseController.diagnosticsSnapshot()
        launchAtLoginEnabled = LoginItemController.isEnabled
        keyboards = keyboardController.devices
        keyboardMappingStatus = keyboardController.mappingStatus
        mappedKeyboardIDs = keyboardController.mappedDeviceIDs
        inputSources = inputController.sources

        if !wasAccessibilityTrusted && accessibilityTrusted {
            mouseController.update(settings: settings.mouse)
            eventTapRunning = mouseController.isRunning
        }
    }

    func refreshInputSources() {
        inputController.reloadSources()
        inputSources = inputController.sources
    }

    func requestAccessibility() {
        _ = PermissionController.isAccessibilityTrusted(prompt: true)
        PermissionController.openAccessibilitySettings()
        refreshSystemState()
    }

    func openInputMonitoringSettings() {
        inputMonitoringTrusted = PermissionController.isInputMonitoringTrusted(prompt: true)
        PermissionController.openInputMonitoringSettings()
        refreshSystemState()
    }

    func toggleLaunchAtLogin(_ enabled: Bool) {
        LoginItemController.setEnabled(enabled)
        refreshSystemState()
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func migrateLegacyKeyboardIDs(using devices: [KeyboardDevice]) {
        var selectedIDs = settings.keyboard.selectedDeviceIDs
        var changed = false
        for device in devices where selectedIDs.contains(device.legacyRegistryID) {
            selectedIDs.remove(device.legacyRegistryID)
            selectedIDs.insert(device.id)
            changed = true
        }
        if changed {
            settings.keyboard.selectedDeviceIDs = selectedIDs
        }
    }
}

enum LoginItemController {
    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    static func setEnabled(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("SmoothKeys login item update failed: \(error.localizedDescription)")
        }
    }
}
