/// Tracks one or two stationary anchors and independently released taps or vertical swipes.
/// The configurable recognizer owns frame validation and cancellation until hands off.
struct AnchoredTapSession: Sendable {
    static let minimumHoldDuration = 0.15
    private let epsilon = 0.000_000_001
    private let startedAt: Double
    private let anchors: [Int: TouchPoint]
    private var completedTapIDs: Set<Int> = []
    private var tap: AnchoredThirdTap?
    private var cooldownUntil: Double?
    private var pendingTaps: [GestureKind: (releasedAt: Double, origin: TouchPoint)] = [:]
    var pendingRelease: Double? { pendingTaps.values.map(\.releasedAt).min() }
    var anchorCount: Int { anchors.count }
    static let gestures: Set<GestureKind> = [.twoFingerHoldLeftTap, .twoFingerHoldRightTap,
        .oneFingerHoldLeftTap, .oneFingerHoldRightTap, .twoFingerHoldSwipeUp, .twoFingerHoldSwipeDown,
        .twoFingerHoldLeftDoubleTap, .twoFingerHoldRightDoubleTap]
    static let oneFingerGestures: Set<GestureKind> = [.oneFingerHoldLeftTap, .oneFingerHoldRightTap]
    static let twoFingerGestures = gestures.subtracting(oneFingerGestures)

    mutating func flush(timestamp: Double, interval: Double, cooldown: Double, gestures: Set<GestureKind>) -> [GestureKind] {
        guard tap == nil else { return [] }
        var recognized: [GestureKind] = []
        for gesture in pendingTaps.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let pending = pendingTaps[gesture], timestamp + epsilon >= pending.releasedAt + interval else { continue }
            pendingTaps.removeValue(forKey: gesture)
            if gestures.contains(gesture) { recognized.append(gesture) }
        }
        if !recognized.isEmpty { cooldownUntil = timestamp + cooldown }
        return recognized
    }

    private func doubleGesture(for gesture: GestureKind) -> GestureKind? {
        switch gesture {
        case .twoFingerHoldLeftTap: .twoFingerHoldLeftDoubleTap
        case .twoFingerHoldRightTap: .twoFingerHoldRightDoubleTap
        default: nil
        }
    }
    private(set) var isReady = false
    private(set) var isEngaged = false
    private(set) var ownsInput = false

    init(contacts: [TouchContact], timestamp: Double) {
        precondition((1...2).contains(contacts.count))
        startedAt = timestamp
        anchors = Dictionary(uniqueKeysWithValues: contacts.map { ($0.id, $0.position) })
    }

    var tapStartedAt: Double? { tap?.startedAt }

    mutating func excludeOrdinaryTaps() { ownsInput = true }

    /// Native snapshots may retain lift-off records from earlier taps while anchors remain.
    func relevantContacts(in frame: TouchFrame) -> [TouchContact] {
        frame.contacts.filter {
            $0.phase.isActive || anchors[$0.id] != nil || tap?.id == $0.id || !completedTapIDs.contains($0.id)
        }
    }

    mutating func process(
        _ frame: TouchFrame, configuration: TapConfiguration, gestures: Set<GestureKind>, doubleTapInterval: Double
    ) -> AnchoredTapProgress {
        let active = frame.contacts.filter { $0.phase.isActive }
        let activeIDs = Set(active.map(\.id))
        guard anchors.keys.allSatisfy({ activeIDs.contains($0) }) else {
            return ownsInput ? .rejected(.anchorReleased) : .abandoned
        }
        for contact in active where anchors[contact.id] != nil {
            let distance = contact.position.distance(to: anchors[contact.id]!)
            if distance > configuration.maximumMovement + epsilon {
                return .rejected(.movementExceeded(contactID: contact.id, distance: distance))
            }
        }
        let others = relevantContacts(in: frame).filter { anchors[$0.id] == nil }
        if !isEngaged {
            guard frame.timestamp + epsilon >= startedAt + Self.minimumHoldDuration else {
                if others.isEmpty { return .preparing }
                return ownsInput ? .rejected(.onsetWindowExceeded) : .abandoned
            }
            isReady = true
            // Keep ordinary two-finger taps eligible until a third finger actually joins.
            if others.isEmpty { return .ready }
            isEngaged = true
            ownsInput = true
        }
        guard others.count <= 1 else { return .rejected(.tooManyContacts) }
        if var current = tap {
            if let contact = others.first {
                guard contact.id == current.id else { return .rejected(.tooManyContacts) }
                let dx = contact.position.x - current.origin.x
                let dy = contact.position.y - current.origin.y
                let swipesEnabled = anchorCount == 2 && !gestures.isDisjoint(with: [.twoFingerHoldSwipeUp, .twoFingerHoldSwipeDown])
                if current.isSwipe {
                    guard abs(dx) <= configuration.maximumMovement, abs(dy) >= 0.06,
                          (dy > 0) == (current.gesture == .twoFingerHoldSwipeUp) else {
                        return .rejected(.tapNotBesideAnchors)
                    }
                } else if swipesEnabled && abs(dx) <= configuration.maximumMovement && abs(dy) >= 0.06 {
                    current.gesture = dy > 0 ? .twoFingerHoldSwipeUp : .twoFingerHoldSwipeDown
                    current.isSwipe = true
                } else if swipesEnabled && abs(dx) <= configuration.maximumMovement && abs(dy) < 0.06 {
                    // The moving finger may cross the tap threshold before reaching the swipe threshold.
                } else {
                    let distance = contact.position.distance(to: current.origin)
                    guard distance <= configuration.maximumMovement + epsilon else {
                        return .rejected(.movementExceeded(contactID: contact.id, distance: distance))
                    }
                    guard side(of: contact.position, active: active, margin: configuration.maximumMovement) == current.gesture else {
                        return .rejected(.tapNotBesideAnchors)
                    }
                }
                current.lastPosition = contact.position
                current.isActive = contact.phase.isActive
            } else {
                current.isActive = false
            }
            let duration = frame.timestamp - current.startedAt
            guard duration <= configuration.maximumDuration + epsilon else { return .rejected(.durationExceeded) }
            guard !current.isActive else {
                tap = current
                return .claimed(gesture: nil, diagnostics: [])
            }
            tap = nil
            completedTapIDs.insert(current.id)
            guard duration + epsilon >= configuration.minimumThreeFingerOverlap else {
                return .rejected(.insufficientThreeFingerOverlap)
            }
            guard !current.isSuppressed else { return .claimed(gesture: nil, diagnostics: []) }
            if !current.isSwipe && current.lastPosition.distance(to: current.origin) > configuration.maximumMovement + epsilon {
                return .rejected(.tapNotBesideAnchors)
            }
            if !current.isSwipe && (current.gesture == .twoFingerHoldSwipeUp || current.gesture == .twoFingerHoldSwipeDown) {
                return .rejected(.tapNotBesideAnchors)
            }
            if let double = doubleGesture(for: current.gesture), gestures.contains(double) {
                if let previous = pendingTaps[current.gesture],
                   current.startedAt <= previous.releasedAt + doubleTapInterval + epsilon,
                   current.origin.distance(to: previous.origin) <= 0.10 {
                    pendingTaps.removeValue(forKey: current.gesture)
                    cooldownUntil = frame.timestamp + max(configuration.cooldown, doubleTapInterval)
                    return .claimed(gesture: double, diagnostics: [.tapRecognized(duration: duration)])
                }
                pendingTaps[current.gesture] = (frame.timestamp, current.origin)
                return .claimed(gesture: nil, diagnostics: [])
            }
            guard gestures.contains(current.gesture) else { return .claimed(gesture: nil, diagnostics: []) }
            cooldownUntil = frame.timestamp + configuration.cooldown
            return .claimed(gesture: current.gesture, diagnostics: [.tapRecognized(duration: duration)])
        }
        guard let contact = others.first else { return .claimed(gesture: nil, diagnostics: []) }
        guard contact.phase.isActive else { return .rejected(.tooManyContacts) }
        let sideGesture = side(of: contact.position, active: active, margin: configuration.maximumMovement)
        if sideGesture != nil {
            let anchorPoints = active.filter { anchors[$0.id] != nil }.map(\.position)
            let gap = TouchPoint.largestHorizontalGap(anchorPoints + [contact.position])
            if gap > configuration.maximumFingerGap + epsilon { return .rejected(.fingersTooFarApart(gap: gap)) }
        }
        let swipeEnabled = anchorCount == 2 && !gestures.isDisjoint(with: [.twoFingerHoldSwipeUp, .twoFingerHoldSwipeDown])
        guard let gesture = sideGesture ?? (swipeEnabled ? .twoFingerHoldSwipeUp : nil) else {
            return .rejected(.tapNotBesideAnchors)
        }
        let suppressed = cooldownUntil.map { frame.timestamp + epsilon < $0 } ?? false
        completedTapIDs.remove(contact.id)
        tap = AnchoredThirdTap(id: contact.id, origin: contact.position, startedAt: frame.timestamp,
                               gesture: gesture, isSuppressed: suppressed, lastPosition: contact.position)
        return .claimed(gesture: nil, diagnostics: suppressed ? [.cooldownSuppressed] : [.candidateStarted])
    }

    private func side(of point: TouchPoint, active: [TouchContact], margin: Double) -> GestureKind? {
        let positions = active.filter { anchors[$0.id] != nil }.map { $0.position.x }
        guard let left = positions.min(), let right = positions.max() else { return nil }
        if point.x < left - margin - epsilon { return anchorCount == 1 ? .oneFingerHoldLeftTap : .twoFingerHoldLeftTap }
        if point.x > right + margin + epsilon { return anchorCount == 1 ? .oneFingerHoldRightTap : .twoFingerHoldRightTap }
        return nil
    }
}

enum AnchoredTapProgress {
    case preparing
    case ready
    case abandoned
    case claimed(gesture: GestureKind?, diagnostics: [RecognitionDiagnostic])
    case rejected(GestureRejectionReason)
}

private struct AnchoredThirdTap: Sendable {
    let id: Int
    let origin: TouchPoint
    let startedAt: Double
    var gesture: GestureKind
    var isSwipe = false
    let isSuppressed: Bool
    var lastPosition: TouchPoint
    var isActive = true
}
