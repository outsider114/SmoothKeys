import Foundation
import IOKit
import IOKit.hid

struct KeyboardDevice: Identifiable, Equatable {
    let id: String
    let legacyRegistryID: String
    let name: String
    let transport: String
    let vendorID: Int
    let productID: Int
    let locationID: Int
    let serialNumber: String
    let isExternal: Bool

    var subtitle: String {
        let ids = String(format: "VID %04X  PID %04X", vendorID, productID)
        return transport.isEmpty ? ids : "\(transport)  \(ids)"
    }
}

final class KeyboardMappingController {
    var onDevicesChanged: (([KeyboardDevice]) -> Void)?
    var onMappingStatusChanged: ((String, Set<String>) -> Void)?
    private(set) var devices: [KeyboardDevice] = []
    private(set) var mappingStatus = "未选择外接键盘"
    private(set) var mappedDeviceIDs: Set<String> = []

    private var manager: IOHIDManager?
    private var selectedDeviceIDs: Set<String> = []
    private var enabled = true
    private let mappingQueue = DispatchQueue(label: "top.horimiya.SmoothKeys.keyboard-mapping")
    private var appliedMatchers: [String: String] = [:]

    func start() {
        let hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matches: [[String: Any]] = [
            [
                kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
                kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard
            ],
            [
                kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
                kIOHIDDeviceUsageKey: kHIDUsage_GD_Keypad
            ]
        ]
        IOHIDManagerSetDeviceMatchingMultiple(hidManager, matches as CFArray)

        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterDeviceMatchingCallback(hidManager, { context, _, _, _ in
            guard let context else { return }
            let controller = Unmanaged<KeyboardMappingController>.fromOpaque(context).takeUnretainedValue()
            controller.refreshDevices()
            controller.applyMappings()
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(hidManager, { context, _, _, _ in
            guard let context else { return }
            let controller = Unmanaged<KeyboardMappingController>.fromOpaque(context).takeUnretainedValue()
            controller.refreshDevices()
            controller.applyMappings()
        }, context)

        IOHIDManagerScheduleWithRunLoop(hidManager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(hidManager, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = hidManager
        refreshDevices()
        applyMappings()
    }

    func stop(clearMappings: Bool = true) {
        guard let manager else { return }
        if clearMappings {
            clearMappingsWithHIDUtil()
        }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
    }

    func update(selectedDeviceIDs: Set<String>, enabled: Bool) {
        self.selectedDeviceIDs = selectedDeviceIDs
        self.enabled = enabled
        applyMappings()
    }

    private func refreshDevices() {
        guard let manager else {
            devices = []
            onDevicesChanged?([])
            return
        }
        let hidDevices = Self.allDevices(from: manager)

        let discovered = hidDevices.compactMap { device -> KeyboardDevice? in
            guard let registryID = Self.registryID(for: device) else { return nil }
            let name = Self.stringProperty(kIOHIDProductKey, device: device) ?? "Unknown Keyboard"
            let transport = Self.stringProperty(kIOHIDTransportKey, device: device) ?? ""
            let vendorID = Self.intProperty(kIOHIDVendorIDKey, device: device) ?? 0
            let productID = Self.intProperty(kIOHIDProductIDKey, device: device) ?? 0
            let locationID = Self.intProperty(kIOHIDLocationIDKey, device: device) ?? 0
            let serialNumber = Self.stringProperty(kIOHIDSerialNumberKey, device: device) ?? ""
            let lowerName = name.lowercased()
            let lowerTransport = transport.lowercased()
            let isBuiltInName = lowerName.contains("internal keyboard") || lowerName.contains("built-in")
            let isEmbeddedTransport = lowerTransport.contains("appleembedded") || lowerTransport.contains("internal")
            let isBuiltInProperty = Self.boolProperty("Built-In", device: device) ?? false
            let stableID = Self.stableID(
                name: name,
                transport: transport,
                vendorID: vendorID,
                productID: productID,
                locationID: locationID,
                serialNumber: serialNumber
            )
            return KeyboardDevice(
                id: stableID,
                legacyRegistryID: registryID,
                name: name,
                transport: transport,
                vendorID: vendorID,
                productID: productID,
                locationID: locationID,
                serialNumber: serialNumber,
                isExternal: !(isBuiltInProperty || isBuiltInName || isEmbeddedTransport)
            )
        }

        devices = Dictionary(grouping: discovered, by: \.id)
            .compactMap { $0.value.first }
        .sorted { lhs, rhs in
            if lhs.isExternal != rhs.isExternal { return lhs.isExternal && !rhs.isExternal }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        onDevicesChanged?(devices)
    }

    private func applyMappings() {
        let enabledSnapshot = enabled
        let selectedIDsSnapshot = selectedDeviceIDs
        let targets = enabledSnapshot
            ? devices.filter { $0.isExternal && selectedDeviceIDs.contains($0.id) }
            : []
        let targetMatchers = Dictionary(uniqueKeysWithValues: targets.compactMap { device in
            Self.matchingJSON(for: device).map { (device.id, $0) }
        })

        mappingQueue.async { [weak self] in
            guard let self else { return }

            let obsoleteIDs = self.appliedMatchers.keys.filter { targetMatchers[$0] == nil }
            for id in obsoleteIDs {
                if let matcher = self.appliedMatchers.removeValue(forKey: id) {
                    _ = Self.setMapping(Self.emptyMappingJSON, matching: matcher)
                }
            }

            var mapped = Set<String>()
            var failed = false
            for (id, matcher) in targetMatchers {
                if Self.setMapping(Self.pcModifierMapJSON, matching: matcher) {
                    self.appliedMatchers[id] = matcher
                    mapped.insert(id)
                } else {
                    failed = true
                }
            }

            let status: String
            if !enabledSnapshot {
                status = "键盘映射已关闭"
            } else if selectedIDsSnapshot.isEmpty {
                status = "未选择外接键盘"
            } else if targets.isEmpty {
                status = "等待所选键盘连接"
            } else if failed {
                status = "部分键盘映射应用失败"
            } else {
                status = "映射已应用到 \(mapped.count) 个键盘"
            }

            DispatchQueue.main.async {
                self.mappingStatus = status
                self.mappedDeviceIDs = mapped
                self.onMappingStatusChanged?(status, mapped)
            }
        }
    }

    private func clearMappingsWithHIDUtil() {
        mappingQueue.sync {
            for matcher in appliedMatchers.values {
                _ = Self.setMapping(Self.emptyMappingJSON, matching: matcher)
            }
            appliedMatchers.removeAll()
        }
    }

    private static let pcModifierMap: [[String: UInt64]] = [
        // USB HID keyboard page usages: Ctrl -> Command, GUI/Windows -> Control.
        [kIOHIDKeyboardModifierMappingSrcKey: usage(0xE0), kIOHIDKeyboardModifierMappingDstKey: usage(0xE3)],
        [kIOHIDKeyboardModifierMappingSrcKey: usage(0xE4), kIOHIDKeyboardModifierMappingDstKey: usage(0xE7)],
        [kIOHIDKeyboardModifierMappingSrcKey: usage(0xE3), kIOHIDKeyboardModifierMappingDstKey: usage(0xE0)],
        [kIOHIDKeyboardModifierMappingSrcKey: usage(0xE7), kIOHIDKeyboardModifierMappingDstKey: usage(0xE4)],
        [kIOHIDKeyboardModifierMappingSrcKey: usage(0xE2), kIOHIDKeyboardModifierMappingDstKey: usage(0xE2)],
        [kIOHIDKeyboardModifierMappingSrcKey: usage(0xE6), kIOHIDKeyboardModifierMappingDstKey: usage(0xE6)]
    ]

    static let pcModifierMapJSON = mappingJSON(pcModifierMap)
    private static let emptyMappingJSON = mappingJSON([])

    private static func usage(_ keyUsage: UInt64) -> UInt64 {
        (UInt64(kHIDPage_KeyboardOrKeypad) << 32) | keyUsage
    }

    private static func registryID(for device: IOHIDDevice) -> String? {
        let service = IOHIDDeviceGetService(device)
        var entryID: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS else { return nil }
        return String(entryID)
    }

    private static func stableID(
        name: String,
        transport: String,
        vendorID: Int,
        productID: Int,
        locationID: Int,
        serialNumber: String
    ) -> String {
        let discriminator = serialNumber.isEmpty ? "location:\(locationID)" : "serial:\(serialNumber)"
        return "v:\(vendorID)|p:\(productID)|\(discriminator)|t:\(transport)|n:\(name)"
    }

    static func matchingJSON(for device: KeyboardDevice) -> String? {
        var matching: [String: Any] = [
            "VendorID": device.vendorID,
            "ProductID": device.productID,
            "Product": device.name
        ]
        if device.locationID != 0 {
            matching["LocationID"] = device.locationID
        }
        if !device.serialNumber.isEmpty {
            matching["IOPropertyMatch"] = [kIOHIDSerialNumberKey: device.serialNumber]
        }
        if !device.transport.isEmpty {
            matching["Transport"] = device.transport
        }
        guard let data = try? JSONSerialization.data(withJSONObject: matching, options: [.sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func mappingJSON(_ mappings: [[String: UInt64]]) -> String {
        let object: [String: Any] = ["UserKeyMapping": mappings]
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)!
    }

    private static func setMapping(_ mappingJSON: String, matching: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = ["property", "--matching", matching, "--set", mappingJSON]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            NSLog("SmoothKeys hidutil failed: \(error.localizedDescription)")
            return false
        }
    }

    private static func allDevices(from manager: IOHIDManager) -> [IOHIDDevice] {
        guard let cfSet = IOHIDManagerCopyDevices(manager) else { return [] }
        let count = CFSetGetCount(cfSet)
        guard count > 0 else { return [] }
        let values = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: count)
        defer { values.deallocate() }
        CFSetGetValues(cfSet, values)
        return (0..<count).compactMap { index in
            guard let pointer = values[index] else { return nil }
            return unsafeBitCast(pointer, to: IOHIDDevice.self)
        }
    }

    private static func stringProperty(_ key: String, device: IOHIDDevice) -> String? {
        IOHIDDeviceGetProperty(device, key as CFString) as? String
    }

    private static func intProperty(_ key: String, device: IOHIDDevice) -> Int? {
        if let number = IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber {
            return number.intValue
        }
        return nil
    }

    private static func boolProperty(_ key: String, device: IOHIDDevice) -> Bool? {
        if let number = IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber {
            return number.boolValue
        }
        return nil
    }
}
