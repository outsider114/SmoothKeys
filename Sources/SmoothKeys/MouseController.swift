// Scroll handling portions adapted from Mos by Caldis and contributors.
// Copyright (c) 2017-2026 Caldis. Licensed under CC BY-NC 4.0.
// Source: https://github.com/Caldis/Mos/tree/5dfb2363331cf63f529fdafa27962c41f91feff4
// Changes: SmoothKeys settings, reduced event handling, diagnostics and conflict guard.
// See THIRD_PARTY_NOTICES.md and LICENSE for attribution and warranty disclaimer.

import AppKit
import ApplicationServices

final class MouseController {
    private var settings = MouseSettings()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var keeper: Timer?
    private let smoothEngine = MosScrollEngine()
    private var diagnosticsLock = os_unfair_lock_s()
    private var diagnostics = MouseDiagnostics()
    private(set) var conflictDetected = false

    var isRunning: Bool {
        guard let eventTap else { return false }
        return CGEvent.tapIsEnabled(tap: eventTap)
    }

    func update(settings: MouseSettings) {
        self.settings = settings

        if !conflictDetected,
           settings.enabled && (settings.smoothScroll || settings.reverseVertical || settings.reverseHorizontal) {
            start()
        } else {
            stop()
        }
    }

    func setMosConflict(_ detected: Bool) {
        guard conflictDetected != detected else { return }
        conflictDetected = detected
        if detected {
            stop()
        } else {
            update(settings: settings)
        }
    }

    func diagnosticsSnapshot() -> MouseDiagnostics {
        os_unfair_lock_lock(&diagnosticsLock)
        let snapshot = diagnostics
        os_unfair_lock_unlock(&diagnosticsLock)
        return snapshot
    }

    func start() {
        guard eventTap == nil else {
            if let eventTap, !CGEvent.tapIsEnabled(tap: eventTap), AXIsProcessTrusted() {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return
        }
        guard AXIsProcessTrusted() else { return }

        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let tap = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: MouseController.eventCallback,
            userInfo: refcon
        ) else {
            NSLog("SmoothKeys mouse event tap creation failed")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        smoothEngine.prepare()
        CGEvent.tapEnable(tap: tap, enable: true)
        startKeeper()
    }

    func stop() {
        keeper?.invalidate()
        keeper = nil
        smoothEngine.stop()

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
    }

    private func startKeeper() {
        keeper?.invalidate()
        keeper = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self, let eventTap = self.eventTap else { return }
            if AXIsProcessTrusted(), !CGEvent.tapIsEnabled(tap: eventTap) {
                self.smoothEngine.reset()
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
        }
    }

    private static let eventCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let controller = Unmanaged<MouseController>.fromOpaque(userInfo).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            controller.smoothEngine.reset()
            if let eventTap = controller.eventTap, AXIsProcessTrusted() {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }
        return controller.handleScroll(event)
    }

    private func handleScroll(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        if smoothEngine.isSynthetic(event) {
            return Unmanaged.passUnretained(event)
        }

        var scrollEvent = MosCompatibleScrollEvent(event: event)
        recordReceived(scrollEvent, event: event)
        guard settings.enabled else {
            return Unmanaged.passUnretained(event)
        }
        guard !scrollEvent.isTrackpad else {
            return Unmanaged.passUnretained(event)
        }

        if settings.reverseVertical, scrollEvent.y.valid {
            scrollEvent.reverseVertical()
        }
        if settings.reverseHorizontal, scrollEvent.x.valid {
            scrollEvent.reverseHorizontal()
        }

        guard settings.smoothScroll else {
            recordTransformed()
            return Unmanaged.passUnretained(event)
        }

        var y = scrollEvent.y.valid ? scrollEvent.y.value : 0
        var x = scrollEvent.x.valid ? scrollEvent.x.value : 0
        guard y != 0 || x != 0 else {
            return Unmanaged.passUnretained(event)
        }

        let step = 33.6
        if y != 0, abs(y) < step { y = y > 0 ? step : -step }
        if x != 0, abs(x) < step { x = x > 0 ? step : -step }

        let speed = max(0.4, min(2.2, settings.speed)) * 2.7
        let transition = max(0.04, min(0.22, (1.0 - settings.smoothness) * 0.32))
        if smoothEngine.enqueue(event: event, y: y, x: x, speed: speed, transition: transition) {
            recordTransformed()
            return nil
        }

        // Display link or target-process capture failed. Preserve the native event.
        return Unmanaged.passUnretained(event)
    }

    private func recordReceived(_ scrollEvent: MosCompatibleScrollEvent, event: CGEvent) {
        os_unfair_lock_lock(&diagnosticsLock)
        diagnostics.receivedEvents &+= 1
        if scrollEvent.isTrackpad {
            diagnostics.trackpadEvents &+= 1
        } else {
            diagnostics.mouseEvents &+= 1
        }
        diagnostics.lastTargetPID = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))
        diagnostics.lastSourcePID = pid_t(event.getIntegerValueField(.eventSourceUnixProcessID))
        diagnostics.lastLineY = scrollEvent.y.line
        diagnostics.lastPointY = scrollEvent.y.point
        diagnostics.lastFixedY = scrollEvent.y.fixedPoint
        diagnostics.lastEventAt = Date()
        let shouldLog = diagnostics.receivedEvents <= 8
        os_unfair_lock_unlock(&diagnosticsLock)

        if shouldLog {
            let target = event.getIntegerValueField(.eventTargetUnixProcessID)
            let source = event.getIntegerValueField(.eventSourceUnixProcessID)
            let phase = event.getDoubleValueField(.scrollWheelEventScrollPhase)
            let momentum = event.getDoubleValueField(.scrollWheelEventMomentumPhase)
            let count = event.getDoubleValueField(.scrollWheelEventScrollCount)
            MouseDiagnosticLog.write("received target=\(target) source=\(source) lineY=\(scrollEvent.y.line) pointY=\(scrollEvent.y.point) fixedY=\(scrollEvent.y.fixedPoint) phase=\(phase) momentum=\(momentum) count=\(count) trackpad=\(scrollEvent.isTrackpad)")
        }
    }

    private func recordTransformed() {
        os_unfair_lock_lock(&diagnosticsLock)
        diagnostics.transformedEvents &+= 1
        os_unfair_lock_unlock(&diagnosticsLock)
    }
}

enum MouseDiagnosticLog {
    private static let queue = DispatchQueue(label: "top.horimiya.SmoothKeys.mouse-log", qos: .utility)
    private static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/SmoothKeys-scroll.log")

    static func write(_ message: String) {
        queue.async {
            let line = "\(Date().timeIntervalSince1970) \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            let manager = FileManager.default
            try? manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !manager.fileExists(atPath: url.path) {
                manager.createFile(atPath: url.path, contents: nil)
            }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                return
            }
        }
    }
}

struct MouseDiagnostics: Equatable {
    var receivedEvents: UInt64 = 0
    var mouseEvents: UInt64 = 0
    var trackpadEvents: UInt64 = 0
    var transformedEvents: UInt64 = 0
    var lastTargetPID: pid_t = 0
    var lastSourcePID: pid_t = 0
    var lastLineY: Int64 = 0
    var lastPointY: Double = 0
    var lastFixedY: Double = 0
    var lastEventAt: Date?
}

struct MosCompatibleScrollEvent {
    struct Axis {
        var line: Int64
        var point: Double
        var fixedPoint: Double
        var valid: Bool
        var value: Double
    }

    let event: CGEvent
    var y: Axis
    var x: Axis
    let isTrackpad: Bool

    init(event: CGEvent) {
        self.event = event
        y = Self.axis(
            event: event,
            line: .scrollWheelEventDeltaAxis1,
            point: .scrollWheelEventPointDeltaAxis1,
            fixedPoint: .scrollWheelEventFixedPtDeltaAxis1
        )
        x = Self.axis(
            event: event,
            line: .scrollWheelEventDeltaAxis2,
            point: .scrollWheelEventPointDeltaAxis2,
            fixedPoint: .scrollWheelEventFixedPtDeltaAxis2
        )
        isTrackpad = event.getDoubleValueField(.scrollWheelEventMomentumPhase) != 0
            || event.getDoubleValueField(.scrollWheelEventScrollPhase) != 0
            || event.getDoubleValueField(.scrollWheelEventScrollCount) != 0
    }

    mutating func reverseVertical() {
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -y.line)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: -y.point)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -y.fixedPoint)
        y.value = -y.value
    }

    mutating func reverseHorizontal() {
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: -x.line)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: -x.point)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -x.fixedPoint)
        x.value = -x.value
    }

    private static func axis(
        event: CGEvent,
        line: CGEventField,
        point: CGEventField,
        fixedPoint: CGEventField
    ) -> Axis {
        let lineValue = event.getIntegerValueField(line)
        let pointValue = event.getDoubleValueField(point)
        let fixedPointValue = event.getDoubleValueField(fixedPoint)
        if pointValue != 0 {
            return Axis(line: lineValue, point: pointValue, fixedPoint: fixedPointValue, valid: true, value: pointValue)
        }
        if fixedPointValue != 0 {
            return Axis(line: lineValue, point: pointValue, fixedPoint: fixedPointValue, valid: true, value: fixedPointValue)
        }
        if lineValue != 0 {
            return Axis(line: lineValue, point: pointValue, fixedPoint: fixedPointValue, valid: true, value: Double(lineValue))
        }
        return Axis(line: lineValue, point: pointValue, fixedPoint: fixedPointValue, valid: false, value: 0)
    }
}
