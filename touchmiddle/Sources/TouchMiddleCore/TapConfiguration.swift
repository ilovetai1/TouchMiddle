public enum TapConfigurationError: Error, Sendable, Equatable {
    case invalidValue(field: String)
    case onsetWindowExceedsDuration
    case overlapExceedsDuration
}

public struct TapConfiguration: Sendable, Equatable {
    public let maximumMovement: Double
    public let maximumDuration: Double
    public let onsetWindow: Double
    public let minimumThreeFingerOverlap: Double
    public let missingContactGrace: Double
    public let maximumFrameGap: Double
    public let cooldown: Double

    public init() {
        maximumMovement = 0.025
        maximumDuration = 0.25
        onsetWindow = 0.065
        minimumThreeFingerOverlap = 0.015
        missingContactGrace = 0.04
        maximumFrameGap = 0.12
        cooldown = 0.25
    }

    /// Custom values are rejected explicitly rather than clamped to an unnoticed fallback.
    public init(
        maximumMovement: Double,
        maximumDuration: Double = 0.25,
        onsetWindow: Double = 0.065,
        minimumThreeFingerOverlap: Double = 0.015,
        missingContactGrace: Double = 0.04,
        maximumFrameGap: Double = 0.12,
        cooldown: Double = 0.25
    ) throws {
        for (field, value) in [
            ("maximumMovement", maximumMovement),
            ("maximumDuration", maximumDuration),
            ("onsetWindow", onsetWindow),
            ("minimumThreeFingerOverlap", minimumThreeFingerOverlap),
            ("maximumFrameGap", maximumFrameGap),
        ] {
            guard value.isFinite, value > 0 else {
                throw TapConfigurationError.invalidValue(field: field)
            }
        }
        for (field, value) in [("missingContactGrace", missingContactGrace), ("cooldown", cooldown)] {
            guard value.isFinite, value >= 0 else {
                throw TapConfigurationError.invalidValue(field: field)
            }
        }
        guard onsetWindow <= maximumDuration else { throw TapConfigurationError.onsetWindowExceedsDuration }
        guard minimumThreeFingerOverlap <= maximumDuration else { throw TapConfigurationError.overlapExceedsDuration }
        self.maximumMovement = maximumMovement
        self.maximumDuration = maximumDuration
        self.onsetWindow = onsetWindow
        self.minimumThreeFingerOverlap = minimumThreeFingerOverlap
        self.missingContactGrace = missingContactGrace
        self.maximumFrameGap = maximumFrameGap
        self.cooldown = cooldown
    }
}
