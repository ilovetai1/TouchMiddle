import Foundation

/// Pure recognition of light taps from complete, normalized touch snapshots.
/// A double tap requires two separately released groups of the same finger count.
public struct ConfigurableGestureRecognizer: Sendable {
    public private(set) var configuration: TapConfiguration
    public private(set) var doubleTapInterval: Double
    private var devices: [String: ConfigurableDeviceState] = [:]
    private var environment: GestureEnvironment?
    private let epsilon = 0.000_000_001
    private let maximumDoubleTapCentroidDistance = 0.10

    public init(configuration: TapConfiguration = TapConfiguration(), doubleTapInterval: Double = 0.35) {
        precondition(doubleTapInterval.isFinite && doubleTapInterval > 0, "Double-tap interval must be finite and positive")
        self.configuration = configuration
        self.doubleTapInterval = doubleTapInterval
    }

    public mutating func reset() {
        devices.removeAll()
        environment = nil
    }

    public mutating func updateConfiguration(_ config: TapConfiguration, doubleTapInterval: Double = 0.35) {
        precondition(doubleTapInterval.isFinite && doubleTapInterval > 0, "Double-tap interval must be finite and positive")
        configuration = config
        self.doubleTapInterval = doubleTapInterval
        reset()
    }

    /// The caller can schedule a monotonic timer even when the sensor stops sending empty frames.
    /// During an eligible second tap, wait for its release or maximum duration instead.
    public func pendingDeadline(deviceID: String) -> Double? {
        guard let state = devices[deviceID], let pending = state.pending else { return nil }
        if let candidate = state.candidate, candidate.startedAt <= pending.releasedAt + doubleTapInterval + epsilon {
            return candidate.startedAt + configuration.maximumDuration
        }
        return pending.releasedAt + doubleTapInterval
    }

    public mutating func process(
        _ frame: TouchFrame, contextID: String, gestures: Set<GestureKind>
    ) -> GestureRecognitionOutcome {
        let active = frame.contacts.filter { $0.phase.isActive }
        _ = reconcileEnvironment(contextID: contextID, gestures: gestures)
        var state = devices[frame.deviceID] ?? ConfigurableDeviceState()

        let errors = validate(frame)
        if !errors.isEmpty {
            cancel(&state, activeCount: active.count, forceBlock: true)
            if !frame.deviceID.isEmpty { devices[frame.deviceID] = state }
            return outcome(state, timestamp: frame.timestamp, diagnostics: errors.map { .frameRejected($0) })
        }
        if let previous = state.lastTimestamp, frame.timestamp < previous {
            cancel(&state, activeCount: active.count)
            state.lastTimestamp = frame.timestamp
            state.lastSequence = frame.sequence
            devices[frame.deviceID] = state
            return outcome(state, timestamp: frame.timestamp, diagnostics: [
                .frameRejected(.timestampWentBackward(previous: previous, current: frame.timestamp)),
            ])
        }
        if let previous = state.lastSequence, let current = frame.sequence, current < previous {
            cancel(&state, activeCount: active.count)
            state.lastTimestamp = frame.timestamp
            state.lastSequence = current
            devices[frame.deviceID] = state
            return outcome(state, timestamp: frame.timestamp, diagnostics: [
                .frameRejected(.sequenceWentBackward(previous: previous, current: current)),
            ])
        }
        if let previous = state.lastSequence, frame.sequence == previous {
            devices[frame.deviceID] = state
            return outcome(state, timestamp: frame.timestamp, diagnostics: [.duplicateFrame])
        }

        let previousTimestamp = state.lastTimestamp
        state.lastTimestamp = frame.timestamp
        state.lastSequence = frame.sequence
        state.lastActiveCount = active.count

        // Invalid physical groups cancel the first tap too; they must never later flush a shortcut.
        let countLimit = gestures.contains(.threeFingerTap) || gestures.contains(.threeFingerDoubleTap) ? 3 : 2
        if Set(frame.contacts.map(\.id)).count > countLimit {
            return reject(.tooManyContacts, frame, &state, activeCount: active.count)
        }
        if let palm = frame.contacts.first(where: { $0.isPalm }) {
            return reject(.palmContact(contactID: palm.id), frame, &state, activeCount: active.count)
        }
        if let cancelled = frame.contacts.first(where: { $0.phase == .cancelled }) {
            return reject(.contactCancelled(contactID: cancelled.id), frame, &state, activeCount: active.count)
        }
        if gestures.isEmpty {
            cancel(&state, activeCount: active.count)
            devices[frame.deviceID] = state
            return outcome(state, timestamp: frame.timestamp, diagnostics: [])
        }
        if state.blocked {
            if active.isEmpty { state.blocked = false }
            devices[frame.deviceID] = state
            return outcome(state, timestamp: frame.timestamp, diagnostics: [])
        }
        if let until = state.suppressionUntil, frame.timestamp + epsilon < until {
            if !active.isEmpty { state.blocked = true }
            devices[frame.deviceID] = state
            return outcome(state, timestamp: frame.timestamp, diagnostics: active.isEmpty ? [] : [.cooldownSuppressed])
        }
        state.cooldownUntil = nil
        state.burstSuppressionUntil = nil

        if let previousTimestamp, state.candidate != nil,
           frame.timestamp - previousTimestamp > configuration.maximumFrameGap + epsilon {
            return reject(.frameGapExceeded, frame, &state, activeCount: active.count)
        }

        if let pending = state.pending, state.candidate == nil,
           frame.timestamp > pending.releasedAt + doubleTapInterval + epsilon {
            let result = expirePending(&state, timestamp: frame.timestamp, gestures: gestures)
            if !result.isEmpty {
                // A fresh touch arriving after the deferred action still respects its cooldown.
                state.blocked = !active.isEmpty
                devices[frame.deviceID] = state
                return outcome(state, timestamp: frame.timestamp, diagnostics: [], recognized: result)
            }
        }

        var diagnostics: [RecognitionDiagnostic] = []
        if state.candidate == nil {
            guard !active.isEmpty else {
                devices[frame.deviceID] = state
                return outcome(state, timestamp: frame.timestamp, diagnostics: [])
            }
            state.candidate = ConfigurableTapCandidate(startedAt: frame.timestamp)
            diagnostics.append(.candidateStarted)
        }
        var candidate = state.candidate!
        if Set(candidate.contacts.keys).union(frame.contacts.map(\.id)).count > countLimit {
            return reject(.tooManyContacts, frame, &state, activeCount: active.count)
        }
        let duration = frame.timestamp - candidate.startedAt
        if duration > configuration.maximumDuration + epsilon {
            return reject(.durationExceeded, frame, &state, activeCount: active.count)
        }
        if let previousTimestamp, (2...3).contains(candidate.previousActiveCount) {
            candidate.overlap[candidate.previousActiveCount, default: 0] += frame.timestamp - previousTimestamp
        }
        for contact in frame.contacts {
            if var tracked = candidate.contacts[contact.id] {
                if contact.phase.isActive {
                    if tracked.explicitlyEnded {
                        return reject(.contactRestarted(contactID: contact.id), frame, &state, activeCount: active.count)
                    }
                    if let since = tracked.missingSince,
                       frame.timestamp - since > configuration.missingContactGrace + epsilon {
                        return reject(.contactReturnedAfterGap(contactID: contact.id), frame, &state, activeCount: active.count)
                    }
                    tracked.missingSince = nil
                } else if contact.phase == .ended { tracked.explicitlyEnded = true }
                let distance = contact.position.distance(to: tracked.origin)
                if distance > configuration.maximumMovement + epsilon {
                    return reject(.movementExceeded(contactID: contact.id, distance: distance), frame, &state, activeCount: active.count)
                }
                candidate.contacts[contact.id] = tracked
            } else if contact.phase.isActive {
                guard duration <= configuration.onsetWindow + epsilon else {
                    return reject(.onsetWindowExceeded, frame, &state, activeCount: active.count)
                }
                candidate.contacts[contact.id] = ConfigurableTrackedContact(origin: contact.position)
            } else {
                // A third finger first seen only at lift-off still invalidates a two-finger group.
                // Its unobserved overlap cannot be inferred from the remaining active fingers.
                return reject(.tooManyContacts, frame, &state, activeCount: active.count)
            }
        }
        let activeIDs = Set(active.map(\.id))
        for id in candidate.contacts.keys where !activeIDs.contains(id) {
            if candidate.contacts[id]?.missingSince == nil { candidate.contacts[id]?.missingSince = frame.timestamp }
        }
        if (2...3).contains(active.count) {
            candidate.confirmedCount = max(candidate.confirmedCount, active.count)
            if active.count == 3, candidate.previousActiveCount != 3 {
                diagnostics.append(.threeFingerGroupConfirmed)
            }
        }
        let eligibleCount = candidate.confirmedCount == 3
            ? (gestures.contains(.threeFingerTap) || gestures.contains(.threeFingerDoubleTap))
            : (candidate.confirmedCount == 2 && gestures.contains(.twoFingerDoubleTap))
        if !eligibleCount, !active.isEmpty, duration > configuration.onsetWindow + epsilon {
            return reject(.onsetWindowExceeded, frame, &state, activeCount: active.count)
        }
        candidate.previousActiveCount = active.count
        state.candidate = candidate
        guard active.isEmpty else {
            devices[frame.deviceID] = state
            return outcome(state, timestamp: frame.timestamp, diagnostics: diagnostics)
        }

        let fingerCount = candidate.contacts.count
        guard eligibleCount, fingerCount == candidate.confirmedCount else {
            return reject(.tooFewContacts, frame, &state, activeCount: 0)
        }
        // The legacy configuration name is retained; this minimum applies to the chosen group size.
        guard candidate.overlap[fingerCount, default: 0] + epsilon >= configuration.minimumThreeFingerOverlap else {
            return reject(.insufficientThreeFingerOverlap, frame, &state, activeCount: 0)
        }
        state.candidate = nil
        diagnostics.append(.tapRecognized(duration: duration))
        let centroid = TouchPoint(
            x: candidate.contacts.values.reduce(0) { $0 + $1.origin.x } / Double(fingerCount),
            y: candidate.contacts.values.reduce(0) { $0 + $1.origin.y } / Double(fingerCount)
        )
        let doubleGesture: GestureKind = fingerCount == 2 ? .twoFingerDoubleTap : .threeFingerDoubleTap
        var recognized: [GestureKind] = []
        if gestures.contains(doubleGesture), let pending = state.pending,
           pending.fingerCount == fingerCount,
           candidate.startedAt <= pending.releasedAt + doubleTapInterval + epsilon,
           centroid.distance(to: pending.centroid) <= maximumDoubleTapCentroidDistance + epsilon {
            recognized = [doubleGesture]
            state.pending = nil
            state.cooldownUntil = frame.timestamp + configuration.cooldown
            // A fast third tap belongs to the same burst and cannot become a trailing single.
            state.burstSuppressionUntil = frame.timestamp + doubleTapInterval
        } else if gestures.contains(doubleGesture) {
            state.pending = PendingConfigurableTap(fingerCount: fingerCount, releasedAt: frame.timestamp, centroid: centroid)
        } else if fingerCount == 3, gestures.contains(.threeFingerTap) {
            state.pending = nil
            recognized = [.threeFingerTap]
            state.cooldownUntil = frame.timestamp + configuration.cooldown
        }
        devices[frame.deviceID] = state
        return outcome(state, timestamp: frame.timestamp, diagnostics: diagnostics, recognized: recognized)
    }

    public mutating func flush(
        deviceID: String, timestamp: Double, contextID: String, gestures: Set<GestureKind>
    ) -> GestureRecognitionOutcome {
        _ = reconcileEnvironment(contextID: contextID, gestures: gestures)
        var state = devices[deviceID] ?? ConfigurableDeviceState()
        let errors = validate(TouchFrame(deviceID: deviceID, timestamp: timestamp, contacts: []))
        if !errors.isEmpty {
            cancel(&state, activeCount: state.lastActiveCount, forceBlock: true)
            if !deviceID.isEmpty { devices[deviceID] = state }
            return outcome(state, timestamp: timestamp, diagnostics: errors.map { .frameRejected($0) })
        }
        if let previous = state.lastTimestamp, timestamp < previous {
            cancel(&state, activeCount: state.lastActiveCount)
            devices[deviceID] = state
            return outcome(state, timestamp: timestamp, diagnostics: [
                .frameRejected(.timestampWentBackward(previous: previous, current: timestamp)),
            ])
        }
        if let candidate = state.candidate {
            if timestamp + epsilon >= candidate.startedAt + configuration.maximumDuration {
                cancel(&state, activeCount: state.lastActiveCount)
                devices[deviceID] = state
                return outcome(state, timestamp: timestamp, diagnostics: [.gestureRejected(.durationExceeded)])
            }
            return outcome(state, timestamp: timestamp, diagnostics: [])
        }
        let recognized = expirePending(&state, timestamp: timestamp, gestures: gestures)
        devices[deviceID] = state
        return outcome(state, timestamp: timestamp, diagnostics: [], recognized: recognized)
    }

    private mutating func reconcileEnvironment(contextID: String, gestures: Set<GestureKind>) -> Bool {
        let next = GestureEnvironment(contextID: contextID, gestures: gestures)
        guard let previous = environment else { environment = next; return false }
        guard previous != next else { return false }
        for id in devices.keys {
            var state = devices[id]!
            cancel(&state, activeCount: state.lastActiveCount)
            devices[id] = state
        }
        environment = next
        return true
    }

    private func expirePending(
        _ state: inout ConfigurableDeviceState, timestamp: Double, gestures: Set<GestureKind>
    ) -> [GestureKind] {
        guard let pending = state.pending, timestamp + epsilon >= pending.releasedAt + doubleTapInterval else { return [] }
        state.pending = nil
        if pending.fingerCount == 3 && gestures.contains(.threeFingerTap) {
            state.cooldownUntil = timestamp + configuration.cooldown
            return [.threeFingerTap]
        }
        return []
    }

    private func validate(_ frame: TouchFrame) -> [FrameValidationError] {
        var errors: [FrameValidationError] = []
        if frame.deviceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errors.append(.emptyDeviceID) }
        if !frame.timestamp.isFinite { errors.append(.nonFiniteTimestamp) }
        else if frame.timestamp < 0 { errors.append(.negativeTimestamp) }
        var seen: Set<Int> = []
        for contact in frame.contacts {
            if !seen.insert(contact.id).inserted { errors.append(.duplicateContactID(contact.id)) }
            if !contact.position.x.isFinite || !contact.position.y.isFinite
                || !(0...1).contains(contact.position.x) || !(0...1).contains(contact.position.y) {
                errors.append(.invalidPosition(contactID: contact.id))
            }
        }
        return errors
    }

    private func cancel(_ state: inout ConfigurableDeviceState, activeCount: Int, forceBlock: Bool = false) {
        state.candidate = nil
        state.pending = nil
        state.cooldownUntil = nil
        state.burstSuppressionUntil = nil
        state.blocked = forceBlock || activeCount > 0
    }

    private mutating func reject(
        _ reason: GestureRejectionReason, _ frame: TouchFrame, _ state: inout ConfigurableDeviceState, activeCount: Int
    ) -> GestureRecognitionOutcome {
        cancel(&state, activeCount: activeCount)
        devices[frame.deviceID] = state
        return outcome(state, timestamp: frame.timestamp, diagnostics: [.gestureRejected(reason)])
    }

    private func outcome(
        _ state: ConfigurableDeviceState, timestamp: Double,
        diagnostics: [RecognitionDiagnostic], recognized: [GestureKind] = []
    ) -> GestureRecognitionOutcome {
        let phase: RecognitionPhase
        if state.blocked { phase = .blockedUntilRelease }
        else if let candidate = state.candidate { phase = candidate.confirmedCount >= 2 ? .tracking : .collecting }
        else if let until = state.suppressionUntil, timestamp < until { phase = .cooldown }
        else { phase = .idle }
        return GestureRecognitionOutcome(gestures: recognized, diagnostics: diagnostics, phase: phase)
    }
}

public struct GestureRecognitionOutcome: Sendable, Equatable {
    public let gestures: [GestureKind]
    public let diagnostics: [RecognitionDiagnostic]
    public let phase: RecognitionPhase
}

private struct GestureEnvironment: Sendable, Equatable {
    let contextID: String
    let gestures: Set<GestureKind>
}

private struct ConfigurableDeviceState: Sendable {
    var lastTimestamp: Double?
    var lastSequence: UInt64?
    var lastActiveCount = 0
    var candidate: ConfigurableTapCandidate?
    var pending: PendingConfigurableTap?
    var blocked = false
    var cooldownUntil: Double?
    var burstSuppressionUntil: Double?
    var suppressionUntil: Double? {
        switch (cooldownUntil, burstSuppressionUntil) {
        case (let first?, let second?): max(first, second)
        case (let first?, nil): first
        case (nil, let second?): second
        case (nil, nil): nil
        }
    }
}

private struct ConfigurableTapCandidate: Sendable {
    let startedAt: Double
    var contacts: [Int: ConfigurableTrackedContact] = [:]
    var confirmedCount = 0
    var previousActiveCount = 0
    var overlap: [Int: Double] = [:]
}

private struct ConfigurableTrackedContact: Sendable {
    let origin: TouchPoint
    var missingSince: Double?
    var explicitlyEnded = false
}

private struct PendingConfigurableTap: Sendable {
    let fingerCount: Int
    let releasedAt: Double
    let centroid: TouchPoint
}
