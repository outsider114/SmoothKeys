import ApplicationServices
import Foundation

enum MouseScrollSelfTest {
    static func emitScroll() -> Bool {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 1,
            wheel1: 1,
            wheel2: 0,
            wheel3: 0
        ) else {
            fputs("FAIL: unable to create test scroll event\n", stderr)
            return false
        }
        event.location = CGPoint(x: 800, y: 400)
        event.post(tap: .cghidEventTap)
        print("PASS: posted one test scroll event")
        return true
    }

    static func run() -> Bool {
        var failures: [String] = []

        guard let event = makeEvent() else {
            print("FAIL: unable to create CGEvent")
            return false
        }
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: 2)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: 11)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 3.5)
        var parsed = MosCompatibleScrollEvent(event: event)
        check(parsed.y.value == 11, "point delta priority", failures: &failures)
        check(abs(parsed.y.fixedPoint - 3.5) < 0.001, "fractional fixed-point parsing", failures: &failures)

        parsed.reverseVertical()
        check(event.getIntegerValueField(.scrollWheelEventDeltaAxis1) == -2, "line reverse", failures: &failures)
        check(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1) == -11, "point reverse", failures: &failures)
        check(abs(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1) + 3.5) < 0.001, "fixed-point reverse", failures: &failures)

        if let trackpad = makeEvent() {
            trackpad.setDoubleValueField(.scrollWheelEventScrollPhase, value: 1)
            check(MosCompatibleScrollEvent(event: trackpad).isTrackpad, "trackpad phase detection", failures: &failures)
        }

        if let continuousMouse = makeEvent() {
            continuousMouse.setDoubleValueField(.scrollWheelEventIsContinuous, value: 1)
            check(!MosCompatibleScrollEvent(event: continuousMouse).isTrackpad, "continuous mouse eligibility", failures: &failures)
        }

        if let dispatchEvent = makeEvent() {
            dispatchEvent.setIntegerValueField(
                .eventTargetUnixProcessID,
                value: Int64(ProcessInfo.processInfo.processIdentifier)
            )
            dispatchEvent.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: 1)
            let engine = MosScrollEngine()
            engine.prepare()
            check(
                engine.enqueue(event: dispatchEvent, y: 12, x: 0, speed: 1, transition: 0.1),
                "display-link target dispatch startup",
                failures: &failures
            )
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            engine.stop()
        }

        if failures.isEmpty {
            print("PASS: mouse scroll event regression checks")
            return true
        }
        failures.forEach { print("FAIL: \($0)") }
        return false
    }

    private static func makeEvent() -> CGEvent? {
        CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: 0,
            wheel2: 0,
            wheel3: 0
        )
    }

    private static func check(_ condition: Bool, _ name: String, failures: inout [String]) {
        if !condition { failures.append(name) }
    }
}
