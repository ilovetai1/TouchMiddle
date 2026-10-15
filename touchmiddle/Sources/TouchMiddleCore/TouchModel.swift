import Foundation

/// Coordinates are normalized to the touch surface, independently of display pixels.
public struct TouchPoint: Sendable, Equatable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    func distance(to other: TouchPoint) -> Double {
        hypot(x - other.x, y - other.y)
    }
}

public enum TouchPhase: Sendable, Equatable {
    case began
    case moved
    case stationary
    case ended
    case cancelled

    public var isActive: Bool {
        switch self {
        case .began, .moved, .stationary: true
        case .ended, .cancelled: false
        }
    }
}

public struct TouchContact: Sendable, Equatable {
    public let id: Int
    public let position: TouchPoint
    public let phase: TouchPhase
    /// The adapter may flag a contact when its sensor supplies reliable palm information.
    public let isPalm: Bool

    public init(id: Int, position: TouchPoint, phase: TouchPhase = .stationary, isPalm: Bool = false) {
        self.id = id
        self.position = position
        self.phase = phase
        self.isPalm = isPalm
    }
}

/// One complete contact snapshot from one physical touch surface.
/// Omitted contacts are treated as absent. An empty snapshot completes lift-off.
public struct TouchFrame: Sendable, Equatable {
    public let deviceID: String
    /// Monotonic seconds from the device callback; wall-clock time is unsuitable.
    public let timestamp: Double
    public let sequence: UInt64?
    public let contacts: [TouchContact]

    public init(deviceID: String, timestamp: Double, sequence: UInt64? = nil, contacts: [TouchContact]) {
        self.deviceID = deviceID
        self.timestamp = timestamp
        self.sequence = sequence
        self.contacts = contacts
    }
}

public enum GestureIntent: Sendable, Equatable {
    case middleClick
}

public enum RecognitionPhase: String, Sendable, Equatable {
    case idle
    case collecting
    case tracking
    case blockedUntilRelease
    case cooldown
    case disabled
}

public struct RecognitionSnapshot: Sendable, Equatable {
    public let deviceID: String
    public let phase: RecognitionPhase
    public let activeContactCount: Int
    public let trackedContactCount: Int
    public let elapsed: Double?
    public let threeFingerOverlap: Double
}

public enum FrameValidationError: Sendable, Equatable {
    case emptyDeviceID
    case nonFiniteTimestamp
    case negativeTimestamp
    case duplicateContactID(Int)
    case invalidPosition(contactID: Int)
    case timestampWentBackward(previous: Double, current: Double)
    case sequenceWentBackward(previous: UInt64, current: UInt64)
}

public enum GestureRejectionReason: Sendable, Equatable {
    case tooFewContacts
    case onsetWindowExceeded
    case durationExceeded
    case insufficientThreeFingerOverlap
    case tooManyContacts
    case movementExceeded(contactID: Int, distance: Double)
    case palmContact(contactID: Int)
    case contactCancelled(contactID: Int)
    case contactRestarted(contactID: Int)
    case contactReturnedAfterGap(contactID: Int)
    case frameGapExceeded
    case anchorReleased
    case tapNotBesideAnchors
}

public enum RecognitionDiagnostic: Sendable, Equatable {
    case candidateStarted
    case threeFingerGroupConfirmed
    case tapRecognized(duration: Double)
    case gestureRejected(GestureRejectionReason)
    case frameRejected(FrameValidationError)
    case duplicateFrame
    case cooldownSuppressed
    case disabled
    case reset
}

public struct RecognitionOutcome: Sendable, Equatable {
    public let intents: [GestureIntent]
    public let diagnostics: [RecognitionDiagnostic]
    public let snapshot: RecognitionSnapshot
}
