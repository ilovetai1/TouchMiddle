/// Native sensor phases, before converting them into the recognizer's contact model.
/// Positions and the ABI are validated by the native input boundary, not by this adapter.
public struct RawTouchContact: Sendable, Equatable {
    public let id: Int
    public let state: Int
    public let position: TouchPoint
    /// Sensor ellipse major axis in the private framework's units; zero when unavailable.
    public let majorAxis: Double

    public init(id: Int, state: Int, position: TouchPoint, majorAxis: Double = 0) {
        self.id = id
        self.state = state
        self.position = position
        self.majorAxis = majorAxis
    }
}

/// Arms each device only after observing hands off. This prevents enabling in the
/// middle of an existing gesture from treating that gesture as a new three-finger tap.
public struct NativeContactAdapter: Sendable {
    /// Fingertip contacts on the built-in trackpad measured 5.7–14.9 (p99 11.6) in local traces.
    /// The palm limit is set clear of that range; it has not yet been calibrated against palm traces.
    public static let defaultPalmMajorAxis = 20.0
    public let palmMajorAxis: Double
    private var devices: [String: AdapterDeviceState] = [:]

    public init(palmMajorAxis: Double = NativeContactAdapter.defaultPalmMajorAxis) {
        precondition(palmMajorAxis.isFinite && palmMajorAxis > 0, "Palm major axis must be finite and positive")
        self.palmMajorAxis = palmMajorAxis
    }

    public func isArmed(deviceID: String) -> Bool {
        devices[deviceID]?.armed ?? false
    }

    /// Reset the recognizer separately when resetting this adapter.
    public mutating func reset() {
        devices.removeAll()
    }

    /// Returns nil until this device has produced a zero-active-contact frame.
    /// The frame that first establishes hands off arms the device and returns nil.
    public mutating func map(
        deviceID: String,
        timestamp: Double,
        sequence: UInt64? = nil,
        contacts: [RawTouchContact]
    ) -> TouchFrame? {
        var state = devices[deviceID] ?? AdapterDeviceState()
        let active = contacts.filter { $0.state == 3 || $0.state == 4 }

        guard state.armed else {
            if active.isEmpty { state.armed = true }
            devices[deviceID] = state
            return nil
        }

        state.knownIDs.formUnion(active.map(\.id))
        let mapped = contacts.compactMap { contact -> TouchContact? in
            let phase: TouchPhase
            switch contact.state {
            case 3: phase = .began
            case 4: phase = .moved
            case 5...7:
                // Near/hover contacts can end without ever touching. Their IDs
                // must not make an otherwise valid tap appear to have four fingers.
                guard state.knownIDs.contains(contact.id) else { return nil }
                phase = .ended
            default: return nil
            }
            return TouchContact(id: contact.id, position: contact.position, phase: phase,
                                isPalm: contact.majorAxis >= palmMajorAxis)
        }
        if active.isEmpty { state.knownIDs.removeAll() }
        devices[deviceID] = state
        return TouchFrame(deviceID: deviceID, timestamp: timestamp, sequence: sequence, contacts: mapped)
    }
}

private struct AdapterDeviceState: Sendable {
    var armed = false
    var knownIDs: Set<Int> = []
}
