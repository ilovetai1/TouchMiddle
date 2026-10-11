import Foundation

/// Deterministic recognition only. This type does not read devices or inject mouse events.
/// Call it serially, using the callback's monotonic timestamp and complete device snapshots.
public struct ThreeFingerTapRecognizer: Sendable {
    public private(set) var isEnabled = true
    public private(set) var configuration: TapConfiguration
    private var devices: [String: DeviceState] = [:]
    private let epsilon = 0.000_000_001

    public init(configuration: TapConfiguration = TapConfiguration()) {
        self.configuration = configuration
    }

    @discardableResult
    public mutating func setEnabled(_ enabled: Bool) -> [RecognitionDiagnostic] {
        isEnabled = enabled
        devices.removeAll()
        return enabled ? [.reset] : [.disabled]
    }

    @discardableResult
    public mutating func reset(deviceID: String? = nil) -> [RecognitionDiagnostic] {
        if let deviceID { devices.removeValue(forKey: deviceID) }
        else { devices.removeAll() }
        return [.reset]
    }

    @discardableResult
    public mutating func updateConfiguration(_ configuration: TapConfiguration) -> [RecognitionDiagnostic] {
        self.configuration = configuration
        return reset()
    }

    public mutating func process(_ frame: TouchFrame) -> RecognitionOutcome {
        var state = devices[frame.deviceID] ?? DeviceState()
        let active = frame.contacts.filter { $0.phase.isActive }
        var diagnostics: [RecognitionDiagnostic] = []

        let errors = validate(frame)
        if !errors.isEmpty {
            state.candidate = nil
            state.blocked = true
            if !frame.deviceID.isEmpty { devices[frame.deviceID] = state }
            return outcome(frame, state, activeCount: active.count, diagnostics: errors.map { .frameRejected($0) })
        }

        if !isEnabled {
            return outcome(frame, state, activeCount: active.count, diagnostics: [.disabled])
        }

        if let previous = state.lastTimestamp, frame.timestamp < previous {
            state.candidate = nil
            state.blocked = !active.isEmpty
            state.cooldownUntil = nil
            state.lastTimestamp = frame.timestamp
            state.lastSequence = frame.sequence
            devices[frame.deviceID] = state
            return outcome(frame, state, activeCount: active.count, diagnostics: [
                .frameRejected(.timestampWentBackward(previous: previous, current: frame.timestamp)),
            ])
        }
        if let previous = state.lastSequence, let current = frame.sequence, current < previous {
            state.candidate = nil
            state.blocked = !active.isEmpty
            state.cooldownUntil = nil
            state.lastTimestamp = frame.timestamp
            state.lastSequence = current
            devices[frame.deviceID] = state
            return outcome(frame, state, activeCount: active.count, diagnostics: [
                .frameRejected(.sequenceWentBackward(previous: previous, current: current)),
            ])
        }
        if let previous = state.lastSequence, frame.sequence == previous {
            return outcome(frame, state, activeCount: active.count, diagnostics: [.duplicateFrame])
        }

        let previousTimestamp = state.lastTimestamp
        state.lastTimestamp = frame.timestamp
        state.lastSequence = frame.sequence

        if state.blocked {
            if active.isEmpty { state.blocked = false }
            devices[frame.deviceID] = state
            return outcome(frame, state, activeCount: active.count, diagnostics: [])
        }
        if let until = state.cooldownUntil {
            if frame.timestamp + epsilon < until {
                if !active.isEmpty {
                    // A contact that starts during cooldown must finish before a new candidate.
                    state.blocked = true
                    diagnostics.append(.cooldownSuppressed)
                }
                devices[frame.deviceID] = state
                return outcome(frame, state, activeCount: active.count, diagnostics: diagnostics)
            }
            state.cooldownUntil = nil
        }

        if let previousTimestamp, state.candidate != nil,
           frame.timestamp - previousTimestamp > configuration.maximumFrameGap + epsilon {
            return reject(.frameGapExceeded, frame, &state, activeCount: active.count)
        }
        if active.count > 3 {
            return reject(.tooManyContacts, frame, &state, activeCount: active.count)
        }
        if let palm = frame.contacts.first(where: { $0.isPalm }) {
            return reject(.palmContact(contactID: palm.id), frame, &state, activeCount: active.count)
        }
        if let cancelled = frame.contacts.first(where: { $0.phase == .cancelled }) {
            return reject(.contactCancelled(contactID: cancelled.id), frame, &state, activeCount: active.count)
        }

        if state.candidate == nil {
            guard !active.isEmpty else {
                devices[frame.deviceID] = state
                return outcome(frame, state, activeCount: 0, diagnostics: [])
            }
            state.candidate = Candidate(startedAt: frame.timestamp)
            diagnostics.append(.candidateStarted)
        }
        var candidate = state.candidate!
        // An unobserved fourth contact can first appear in its lift-off frame.
        // It must not turn a four-finger group into an apparent three-finger tap.
        if Set(candidate.contacts.keys).union(frame.contacts.map(\.id)).count > 3 {
            return reject(.tooManyContacts, frame, &state, activeCount: active.count)
        }
        let duration = frame.timestamp - candidate.startedAt
        if duration > configuration.maximumDuration + epsilon {
            return reject(.durationExceeded, frame, &state, activeCount: active.count)
        }
        if let previousTimestamp, candidate.previousActiveCount == 3 {
            candidate.threeFingerOverlap += frame.timestamp - previousTimestamp
        }

        // First evaluate known contacts, including final positions on explicit lift-off.
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
                } else if contact.phase == .ended {
                    tracked.explicitlyEnded = true
                }
                let distance = contact.position.distance(to: tracked.origin)
                if distance > configuration.maximumMovement + epsilon {
                    return reject(.movementExceeded(contactID: contact.id, distance: distance), frame, &state, activeCount: active.count)
                }
                candidate.contacts[contact.id] = tracked
            } else if contact.phase.isActive {
                guard duration <= configuration.onsetWindow + epsilon else {
                    return reject(.onsetWindowExceeded, frame, &state, activeCount: active.count)
                }
                guard candidate.contacts.count < 3 else {
                    return reject(.tooManyContacts, frame, &state, activeCount: active.count)
                }
                candidate.contacts[contact.id] = TrackedContact(origin: contact.position)
            }
        }
        let activeIDs = Set(active.map(\.id))
        for id in candidate.contacts.keys where !activeIDs.contains(id) {
            if candidate.contacts[id]?.missingSince == nil {
                candidate.contacts[id]?.missingSince = frame.timestamp
            }
        }
        if active.count == 3, !candidate.confirmed {
            guard duration <= configuration.onsetWindow + epsilon else {
                return reject(.onsetWindowExceeded, frame, &state, activeCount: active.count)
            }
            candidate.confirmed = true
            diagnostics.append(.threeFingerGroupConfirmed)
        }
        if !candidate.confirmed, !active.isEmpty, duration > configuration.onsetWindow + epsilon {
            return reject(.onsetWindowExceeded, frame, &state, activeCount: active.count)
        }
        candidate.previousActiveCount = active.count
        state.candidate = candidate

        if active.isEmpty {
            guard candidate.confirmed else {
                return reject(.tooFewContacts, frame, &state, activeCount: 0)
            }
            guard candidate.threeFingerOverlap + epsilon >= configuration.minimumThreeFingerOverlap else {
                return reject(.insufficientThreeFingerOverlap, frame, &state, activeCount: 0)
            }
            state.candidate = nil
            state.cooldownUntil = frame.timestamp + configuration.cooldown
            devices[frame.deviceID] = state
            diagnostics.append(.tapRecognized(duration: duration))
            return outcome(frame, state, activeCount: 0, diagnostics: diagnostics, intents: [.middleClick])
        }
        devices[frame.deviceID] = state
        return outcome(frame, state, activeCount: active.count, diagnostics: diagnostics)
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

    private mutating func reject(
        _ reason: GestureRejectionReason,
        _ frame: TouchFrame,
        _ state: inout DeviceState,
        activeCount: Int
    ) -> RecognitionOutcome {
        state.candidate = nil
        state.blocked = activeCount > 0
        devices[frame.deviceID] = state
        return outcome(frame, state, activeCount: activeCount, diagnostics: [.gestureRejected(reason)])
    }

    private func outcome(
        _ frame: TouchFrame,
        _ state: DeviceState,
        activeCount: Int,
        diagnostics: [RecognitionDiagnostic],
        intents: [GestureIntent] = []
    ) -> RecognitionOutcome {
        let phase: RecognitionPhase
        if !isEnabled { phase = .disabled }
        else if state.blocked { phase = .blockedUntilRelease }
        else if let candidate = state.candidate { phase = candidate.confirmed ? .tracking : .collecting }
        else if let until = state.cooldownUntil, frame.timestamp < until { phase = .cooldown }
        else { phase = .idle }
        return RecognitionOutcome(
            intents: intents,
            diagnostics: diagnostics,
            snapshot: RecognitionSnapshot(
                deviceID: frame.deviceID,
                phase: phase,
                activeContactCount: activeCount,
                trackedContactCount: state.candidate?.contacts.count ?? 0,
                elapsed: state.candidate.map { frame.timestamp - $0.startedAt },
                threeFingerOverlap: state.candidate?.threeFingerOverlap ?? 0
            )
        )
    }
}

private struct DeviceState: Sendable {
    var lastTimestamp: Double?
    var lastSequence: UInt64?
    var candidate: Candidate?
    var blocked = false
    var cooldownUntil: Double?
}

private struct Candidate: Sendable {
    let startedAt: Double
    var contacts: [Int: TrackedContact] = [:]
    var confirmed = false
    var previousActiveCount = 0
    var threeFingerOverlap = 0.0
}

private struct TrackedContact: Sendable {
    let origin: TouchPoint
    var missingSince: Double?
    var explicitlyEnded = false
}
