import Carbon
import Foundation

struct InputSource: Identifiable, Equatable {
    let id: String
    let name: String
}

final class InputMethodController {
    var onSourcesChanged: (([InputSource]) -> Void)?
    private(set) var sources: [InputSource] = []

    private var lockEnabled = false
    private var selectedSourceID: String?
    private var timer: Timer?

    func start() {
        reloadSources()
        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            self?.enforceLockIfNeeded()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func update(lockEnabled: Bool, selectedSourceID: String?) {
        self.lockEnabled = lockEnabled
        self.selectedSourceID = selectedSourceID
        enforceLockIfNeeded()
    }

    func reloadSources() {
        let properties: [String: Any] = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as Any
        ]

        guard let list = TISCreateInputSourceList(properties as CFDictionary, false)?.takeRetainedValue() as? [TISInputSource] else {
            sources = []
            onSourcesChanged?([])
            return
        }

        sources = list.compactMap { source in
            guard isSelectable(source),
                  let id = property(kTISPropertyInputSourceID, source: source),
                  let name = property(kTISPropertyLocalizedName, source: source) else {
                return nil
            }
            return InputSource(id: id, name: name)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        onSourcesChanged?(sources)
    }

    private func enforceLockIfNeeded() {
        guard lockEnabled, let selectedSourceID else { return }
        guard activeSourceID() != selectedSourceID else { return }
        guard let source = source(withID: selectedSourceID) else { return }
        TISSelectInputSource(source)
    }

    private func source(withID id: String) -> TISInputSource? {
        let properties = [kTISPropertyInputSourceID as String: id] as CFDictionary
        let list = TISCreateInputSourceList(properties, false)?.takeRetainedValue() as? [TISInputSource]
        return list?.first
    }

    private func activeSourceID() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return property(kTISPropertyInputSourceID, source: source)
    }

    private func isSelectable(_ source: TISInputSource) -> Bool {
        let selectable = boolProperty(kTISPropertyInputSourceIsSelectCapable, source: source)
        let enabled = boolProperty(kTISPropertyInputSourceIsEnabled, source: source)
        return selectable && enabled
    }

    private func property(_ key: CFString, source: TISInputSource) -> String? {
        guard let value = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
    }

    private func boolProperty(_ key: CFString, source: TISInputSource) -> Bool {
        guard let value = TISGetInputSourceProperty(source, key) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(value).takeUnretainedValue())
    }
}
