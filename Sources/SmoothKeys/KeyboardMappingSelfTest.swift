import Foundation

enum KeyboardMappingSelfTest {
    static func run() -> Bool {
        var failures: [String] = []
        func check(_ condition: Bool, _ name: String) {
            if !condition { failures.append(name) }
        }
        let first = matcher(serial: "keyboard-1")
        let second = matcher(serial: "keyboard-2")
        check((first?["IOPropertyMatch"] as? [String: String])?["SerialNumber"] == "keyboard-1", "first serial matcher")
        check((second?["IOPropertyMatch"] as? [String: String])?["SerialNumber"] == "keyboard-2", "second serial matcher")
        check(first?["VendorID"] as? Int == 1234, "vendor matcher")
        check(first?["ProductID"] as? Int == 5678, "product matcher")
        check(first?["Transport"] as? String == "USB", "transport matcher")
        check(first?["LocationID"] == nil, "omit unknown location")
        let fallback = matcher(serial: "", location: 42, name: "Keyboard \"USB\"")
        check(fallback?["LocationID"] as? Int == 42, "location fallback")
        check(fallback?["Product"] as? String == "Keyboard \"USB\"", "JSON escaping")
        check(fallback?["IOPropertyMatch"] == nil, "omit unknown serial")

        let data = Data(KeyboardMappingController.pcModifierMapJSON.utf8)
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: [[String: UInt64]]]
        let mappings = object?["UserKeyMapping"] ?? []
        let page: UInt64 = 0x700000000
        for (source, target): (UInt64, UInt64) in [
            (0xE0, 0xE3), (0xE4, 0xE7), (0xE3, 0xE0),
            (0xE7, 0xE4), (0xE2, 0xE2), (0xE6, 0xE6)
        ] {
            check(mappings.contains {
                $0["HIDKeyboardModifierMappingSrc"] == page | source
                    && $0["HIDKeyboardModifierMappingDst"] == page | target
            }, "modifier \(source) -> \(target)")
        }
        check(mappings.count == 6, "six modifier mappings")
        failures.forEach { print("FAIL: \($0)") }
        if failures.isEmpty { print("PASS: keyboard device matching and modifier regression checks") }
        return failures.isEmpty
    }

    private static func matcher(serial: String, location: Int = 0, name: String = "Keyboard") -> [String: Any]? {
        let device = KeyboardDevice(
            id: "test", legacyRegistryID: "1", name: name, transport: "USB",
            vendorID: 1234, productID: 5678, locationID: location,
            serialNumber: serial, isExternal: true
        )
        guard let json = KeyboardMappingController.matchingJSON(for: device) else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any]
    }
}
