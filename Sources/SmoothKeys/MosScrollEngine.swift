// Adapted for SmoothKeys from Mos ScrollPoster, ScrollDispatchContext,
// ScrollEvent, ScrollFilter, and Interpolator.
// Mos copyright (c) 2017-2026 Caldis and contributors.
// Licensed under CC BY-NC 4.0. SmoothKeys changes: reduced configuration,
// isolated target-PID dispatch, simplified phase handling, and fail-open startup.
// Source: https://github.com/Caldis/Mos/tree/5dfb2363331cf63f529fdafa27962c41f91feff4
// See THIRD_PARTY_NOTICES.md and LICENSE for attribution and warranty disclaimer.

import AppKit
import CoreVideo
import os

final class MosScrollEngine {
    private let syntheticMarker: Int64 = 0x534D4B594D4F5331
    private let eventTTL: CFTimeInterval = 5.0
    private let postQueue = DispatchQueue(label: "top.horimiya.SmoothKeys.mouse-post", qos: .userInteractive)

    private var stateLock = os_unfair_lock_s()
    private var displayLink: CVDisplayLink?
    private var eventTemplate: CGEvent?
    private var targetPID: pid_t = 0
    private var generation: UInt64 = 0
    private var capturedAt: CFTimeInterval = 0
    private var current = (y: 0.0, x: 0.0)
    private var buffer = (y: 0.0, x: 0.0)
    private var direction = (y: 0.0, x: 0.0)
    private var filtered = (y: 0.0, x: 0.0)
    private var transition = 0.09
    private var postedFrames: UInt64 = 0

    var isRunning: Bool {
        displayLink.map { CVDisplayLinkIsRunning($0) } ?? false
    }

    deinit {
        stop()
    }

    func prepare() {
        guard displayLink == nil else { return }
        var newDisplayLink: CVDisplayLink?
        guard CVDisplayLinkCreateWithActiveCGDisplays(&newDisplayLink) == kCVReturnSuccess,
              let newDisplayLink else {
            return
        }
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        CVDisplayLinkSetOutputCallback(newDisplayLink, { _, _, _, _, _, context in
            guard let context else { return kCVReturnError }
            let engine = Unmanaged<MosScrollEngine>.fromOpaque(context).takeUnretainedValue()
            engine.processFrame()
            return kCVReturnSuccess
        }, context)
        displayLink = newDisplayLink
    }

    func enqueue(event: CGEvent, y: Double, x: Double, speed: Double, transition: Double) -> Bool {
        prepare()
        guard let displayLink,
              let template = event.copy() else {
            return false
        }
        let pid = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))
        guard pid > 0 else { return false }

        os_unfair_lock_lock(&stateLock)
        eventTemplate = template
        targetPID = pid
        capturedAt = CFAbsoluteTimeGetCurrent()
        self.transition = transition
        if y * direction.y > 0 {
            buffer.y += y * speed
        } else {
            buffer.y = y * speed
            current.y = 0
            filtered.y = 0
        }
        if x * direction.x > 0 {
            buffer.x += x * speed
        } else {
            buffer.x = x * speed
            current.x = 0
            filtered.x = 0
        }
        direction = (y, x)
        os_unfair_lock_unlock(&stateLock)

        if !CVDisplayLinkIsRunning(displayLink) {
            guard CVDisplayLinkStart(displayLink) == kCVReturnSuccess else {
                reset()
                return false
            }
        }
        return true
    }

    func isSynthetic(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == syntheticMarker
    }

    func stop() {
        if let displayLink, CVDisplayLinkIsRunning(displayLink) {
            CVDisplayLinkStop(displayLink)
        }
        reset()
        displayLink = nil
    }

    func reset() {
        os_unfair_lock_lock(&stateLock)
        generation &+= 1
        eventTemplate = nil
        targetPID = 0
        capturedAt = 0
        current = (0, 0)
        buffer = (0, 0)
        direction = (0, 0)
        filtered = (0, 0)
        os_unfair_lock_unlock(&stateLock)
    }

    private struct PostingSnapshot {
        let event: CGEvent
        let pid: pid_t
        let generation: UInt64
        let capturedAt: CFTimeInterval
        let delta: (y: Double, x: Double)
    }

    private func processFrame() {
        var snapshot: PostingSnapshot?
        var shouldStop = false

        os_unfair_lock_lock(&stateLock)
        if let event = eventTemplate?.copy(), targetPID > 0 {
            let frame = (
                y: (buffer.y - current.y) * transition,
                x: (buffer.x - current.x) * transition
            )
            current.y += frame.y
            current.x += frame.x

            let output = filtered
            filtered.y += (frame.y - filtered.y) * 0.23
            filtered.x += (frame.x - filtered.x) * 0.23

            let residual = max(abs(buffer.y - current.y), abs(buffer.x - current.x))
            let outputMagnitude = max(abs(output.y), abs(output.x))
            if outputMagnitude > 0.5 {
                snapshot = PostingSnapshot(
                    event: event,
                    pid: targetPID,
                    generation: generation,
                    capturedAt: capturedAt,
                    delta: output
                )
            }
            shouldStop = residual <= 0.5 && outputMagnitude <= 0.5
            if shouldStop {
                generation &+= 1
                eventTemplate = nil
                targetPID = 0
                current = (0, 0)
                buffer = (0, 0)
                direction = (0, 0)
                filtered = (0, 0)
            }
        } else {
            shouldStop = true
        }
        let idleGeneration = generation
        os_unfair_lock_unlock(&stateLock)

        if let snapshot { post(snapshot) }
        if shouldStop {
            // Serialize lifecycle with enqueue; never stop a display link inside its callback.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                os_unfair_lock_lock(&self.stateLock)
                let stillIdle = self.eventTemplate == nil && self.generation == idleGeneration
                os_unfair_lock_unlock(&self.stateLock)
                if stillIdle, let displayLink = self.displayLink, CVDisplayLinkIsRunning(displayLink) {
                    CVDisplayLinkStop(displayLink)
                }
            }
        }
    }

    private func post(_ snapshot: PostingSnapshot) {
        snapshot.event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: snapshot.delta.y)
        snapshot.event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: snapshot.delta.x)
        snapshot.event.setDoubleValueField(.scrollWheelEventIsContinuous, value: 1)
        snapshot.event.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)

        postQueue.async { [weak self] in
            guard let self else { return }
            os_unfair_lock_lock(&self.stateLock)
            let valid = snapshot.generation == self.generation
                && CFAbsoluteTimeGetCurrent() - snapshot.capturedAt <= self.eventTTL
            os_unfair_lock_unlock(&self.stateLock)
            guard valid else { return }
            snapshot.event.postToPid(snapshot.pid)
            os_unfair_lock_lock(&self.stateLock)
            self.postedFrames &+= 1
            let shouldLog = self.postedFrames <= 5
            os_unfair_lock_unlock(&self.stateLock)
            if shouldLog {
                MouseDiagnosticLog.write("posted target=\(snapshot.pid) y=\(snapshot.delta.y) x=\(snapshot.delta.x)")
            }
        }
    }
}
