import AppKit
import ApplicationServices
import Combine
import CTouchBridge
import TouchMiddleCore

@MainActor
final class TouchController: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var sourceStatus = "尚未啟動"
    @Published private(set) var frames = 0
    @Published private(set) var contacts = 0
    @Published private(set) var recognized = 0
    @Published private(set) var posted = 0
    @Published private(set) var observedPairs = 0
    @Published private(set) var permissionGranted = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var phase = "等待手指離開觸控板"
    @Published private(set) var logPath = ""
    @Published private(set) var maximumDelayMS = 0.0
    @Published private(set) var rules: [GestureRule] = []
    @Published private(set) var isEditingRule = false
    @Published private(set) var lastAction = "尚未觸發"
    @Published private(set) var foregroundName = ""
    @Published var movement = 0.025
    @Published var duration = 0.25
    @Published var doubleTapInterval = 0.35
    private var recognizer = ConfigurableGestureRecognizer()
    private var adapter = NativeContactAdapter()
    private let output = MiddleClickOutput()
    private let keyboardOutput = KeyboardShortcutOutput()
    private var ruleStore: RuleStore?
    private var rulesLoadFailed = false
    private var issues: [String: String] = [:]
    private var log: SessionLog?
    private var delivery: FrameDelivery?
    private var generation = 0
    private var acceptFramesAfter = DispatchTime.now().uptimeNanoseconds
    private var timer: Timer?
    private var recognitionTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var pending: [Int64: Set<String>] = [:]
    private var manualTest: Task<Void, Never>?
    private var sleeping = false
    private let trace = CommandLine.arguments.contains("--trace")
    private var shuttingDown = false
    private var contextID = ""
    private struct DeviceClock { let timestamp: Double; let receivedUptime: UInt64 }
    private var clocks: [String: DeviceClock] = [:]

    init() {
        do { log = try SessionLog(); logPath = log!.path.path }
        catch { setIssue("log", "診斷記錄無法建立：\(error.localizedDescription)") }
        do {
            let defaults = UserDefaults.standard
            let loadedMovement = defaults.object(forKey: "maximumMovement") == nil ? 0.025 : defaults.double(forKey: "maximumMovement")
            let loadedDuration = defaults.object(forKey: "maximumDuration") == nil ? 0.25 : defaults.double(forKey: "maximumDuration")
            let loadedInterval = defaults.object(forKey: "doubleTapInterval") == nil ? 0.35 : defaults.double(forKey: "doubleTapInterval")
            guard loadedMovement.isFinite, (0.01...0.05).contains(loadedMovement),
                  loadedDuration.isFinite, (0.15...0.4).contains(loadedDuration) else {
                throw NSError(domain: "TouchMiddleSettings", code: 2, userInfo: [NSLocalizedDescriptionKey: "位移必須為 1–5%，單次輕點時間必須為 150–400 ms。"])
            }
            guard loadedInterval.isFinite, (0.15...0.6).contains(loadedInterval) else {
                throw NSError(domain: "TouchMiddleSettings", code: 1, userInfo: [NSLocalizedDescriptionKey: "雙擊間隔必須為 150–600 ms。"])
            }
            let config = try TapConfiguration(maximumMovement: loadedMovement, maximumDuration: loadedDuration)
            movement = loadedMovement; duration = loadedDuration; doubleTapInterval = loadedInterval
            recognizer.updateConfiguration(config, doubleTapInterval: loadedInterval)
        } catch { setIssue("settings", "點按設定載入失敗，請重新套用有效設定：\(error.localizedDescription)") }
        do {
            let store = try RuleStore(); ruleStore = store
            rules = try store.load().rules
        } catch { rulesLoadFailed = true; setIssue("rules", "規則載入失敗：\(error.localizedDescription)") }
        refreshPermissions()
        if errorMessage == nil { startSource() }
        if permissionGranted && errorMessage == nil { setEnabled(true) }
        installMonitors()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.heartbeat() }
        }
        recognitionTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.flushPendingSingles() }
        }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.applicationChanged() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.sleep() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(800))
                guard let self, !self.shuttingDown else { return }
                self.sleeping = false; self.startSource(); self.record(["type": "wake", "enabled": self.enabled])
            }
        })
    }

    private func validatedTapConfiguration() throws -> TapConfiguration {
        guard movement.isFinite, (0.01...0.05).contains(movement),
              duration.isFinite, (0.15...0.4).contains(duration) else {
            throw NSError(domain: "TouchMiddleSettings", code: 2, userInfo: [NSLocalizedDescriptionKey: "位移必須為 1–5%，單次輕點時間必須為 150–400 ms。"])
        }
        guard doubleTapInterval.isFinite, (0.15...0.6).contains(doubleTapInterval) else {
            throw NSError(domain: "TouchMiddleSettings", code: 1, userInfo: [NSLocalizedDescriptionKey: "雙擊間隔必須為 150–600 ms。"])
        }
        return try TapConfiguration(maximumMovement: movement, maximumDuration: duration)
    }
    private func resetRecognition(preserveArming: Bool = false, cancelManual: Bool = true) {
        if !preserveArming { adapter.reset() }
        recognizer.reset(); clocks.removeAll()
        acceptFramesAfter = DispatchTime.now().uptimeNanoseconds
        if cancelManual { manualTest?.cancel(); manualTest = nil }
    }
    private func foregroundTarget() -> NSRunningApplication? {
        guard let app = NSWorkspace.shared.frontmostApplication, app.isActive, !app.isTerminated,
              app.bundleIdentifier != nil else { return nil }
        return app
    }
    private func synchronizeContext(_ app: NSRunningApplication?) -> String {
        let key = app.map { "\($0.bundleIdentifier ?? "unknown"):\($0.processIdentifier)" } ?? "unknown"
        updateForegroundName(app)
        if contextID != key { contextID = key; resetRecognition(preserveArming: contacts == 0, cancelManual: false) }
        return key
    }
    private func updateForegroundName(_ app: NSRunningApplication?) {
        let name = app?.localizedName ?? "無法取得前景 App"
        if foregroundName != name { foregroundName = name }
    }
    private func applicationChanged() {
        guard !shuttingDown else { return }
        _ = synchronizeContext(foregroundTarget())
        phase = "App 已切換，等待手指放開"
    }

    private func startSource() {
        guard delivery == nil, log != nil, issues.isEmpty, !shuttingDown else { return }
        generation += 1; let epoch = generation; resetRecognition()
        let box = FrameDelivery { [weak self] frame in
            DispatchQueue.main.async {
                guard let self, self.generation == epoch, !self.shuttingDown else { return }; self.receive(frame)
            }
        }
        delivery = box
        var message = [CChar](repeating: 0, count: 1024)
        let count = TMStart(nativeFrameSink, Unmanaged.passUnretained(box).toOpaque(), &message, Int32(message.count))
        if count <= 0 {
            TMStop(); delivery = nil; generation += 1; sourceStatus = "啟動失敗"
            setIssue("source", String(decoding: message.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self))
            record(["type": "sourceError", "message": errorMessage ?? "unknown"]); return
        }
        sourceStatus = "已連接內建觸控板（\(count) 台）"; phase = "請碰一下再放開，完成啟動校準"
        record(["type": "sourceStarted", "deviceCount": count, "runningCount": TMRunningDeviceCount(),
                "contactABIBytes": TMNativeContactSize(), "pid": ProcessInfo.processInfo.processIdentifier])
    }
    private func stopSource() {
        generation += 1; TMStop(); delivery = nil; resetRecognition(); contacts = 0
    }
    private func receive(_ frame: NativeFrame) {
        guard delivery != nil, frame.receivedUptime >= acceptFramesAfter else { return }
        frames += 1
        let delay = Double(DispatchTime.now().uptimeNanoseconds - frame.receivedUptime) / 1_000_000
        maximumDelayMS = max(maximumDelayMS, delay)
        let foreground = foregroundTarget(); let currentContext = synchronizeContext(foreground)
        contacts = frame.contacts.filter { $0.state == 3 || $0.state == 4 }.count
        // Context changes discard already queued input as well as pending taps.
        guard frame.receivedUptime >= acceptFramesAfter else { return }
        if trace {
            record(["type": "frame", "device": String(frame.device), "timestamp": frame.timestamp,
                    "receivedWallTime": frame.receivedWallTime, "sequence": frame.sequence,
                    "delayMS": delay, "invalidReason": frame.invalidReason,
                    "foreground": foreground?.bundleIdentifier ?? "unknown", "foregroundPID": foreground?.processIdentifier ?? 0,
                    "contacts": frame.contacts.map { ["id": $0.id, "state": $0.state, "x": $0.x, "y": $0.y] as [String: Any] }])
        }
        guard frame.invalidReason == 0 else {
            enabled = false; resetRecognition(); setIssue("source", "觸控資料無效（\(frame.invalidReason)），已暫停手勢。")
            record(["type": "invalidFrame", "reason": frame.invalidReason]); return
        }
        guard delay <= 120 else {
            resetRecognition(); phase = "資料延遲，等待手指放開"; record(["type": "delayedFrame", "delayMS": delay]); return
        }
        guard !isEditingRule, foreground != nil else { return }
        let device = String(frame.device)
        clocks[device] = DeviceClock(timestamp: frame.timestamp, receivedUptime: frame.receivedUptime)
        guard let mapped = adapter.map(deviceID: device, timestamp: frame.timestamp,
            sequence: UInt64(UInt32(bitPattern: frame.sequence)),
            contacts: frame.contacts.map { RawTouchContact(id: $0.id, state: $0.state, position: TouchPoint(x: $0.x, y: $0.y)) }) else {
            phase = adapter.isArmed(deviceID: device) ? "校準完成，等待點按" : "等待所有手指放開"; return
        }
        let gestures = RuleConfiguration(rules: rules).gestures(bundleIdentifier: foreground?.bundleIdentifier)
        let result = recognizer.process(mapped, contextID: currentContext, gestures: gestures)
        handleRecognition(result, deviceTimestamp: frame.timestamp, app: foreground)
    }
    private func flushPendingSingles() {
        guard delivery != nil, !shuttingDown, !sleeping, !isEditingRule,
              clocks.keys.contains(where: { recognizer.pendingDeadline(deviceID: $0) != nil }) else { return }
        let app = foregroundTarget(); let key = synchronizeContext(app)
        guard app != nil else { return }
        let gestures = RuleConfiguration(rules: rules).gestures(bundleIdentifier: app?.bundleIdentifier)
        let now = DispatchTime.now().uptimeNanoseconds
        for (device, clock) in clocks where recognizer.pendingDeadline(deviceID: device) != nil {
            let timestamp = clock.timestamp + Double(now - clock.receivedUptime) / 1_000_000_000
            let result = recognizer.flush(deviceID: device, timestamp: timestamp, contextID: key, gestures: gestures)
            handleRecognition(result, deviceTimestamp: timestamp, app: app)
        }
    }
    private func handleRecognition(_ result: GestureRecognitionOutcome, deviceTimestamp: Double, app: NSRunningApplication?) {
        phase = phaseLabel(result.phase)
        for diagnostic in result.diagnostics {
            if case .gestureRejected(let reason) = diagnostic, trace {
                record(["type": "rejected", "reason": String(describing: reason), "deviceTimestamp": deviceTimestamp])
            } else if case .frameRejected(let reason) = diagnostic {
                enabled = false; resetRecognition(); setIssue("source", "觸控影格未通過驗證：\(reason)，已暫停手勢。")
                record(["type": "frameRejected", "reason": String(describing: reason)])
            }
        }
        for gesture in result.gestures {
            recognized += 1
            record(["type": "recognized", "gesture": recognized, "gestureKind": gesture.rawValue,
                    "deviceTimestamp": deviceTimestamp, "foreground": app?.bundleIdentifier ?? "unknown", "enabled": enabled])
            guard enabled, let app,
                  let rule = RuleConfiguration(rules: rules).resolve(gesture, bundleIdentifier: app.bundleIdentifier) else { continue }
            postAction(rule.action, app: app, kind: "gesture", gesture: recognized, rule: rule)
        }
    }

    func setEnabled(_ value: Bool) {
        refreshPermissions()
        guard !value || (permissionGranted && delivery != nil && errorMessage == nil) else {
            if !permissionGranted { setIssue("permission", "請允許 TouchMiddle 的輔助使用權限，再啟用手勢。") }; return
        }
        enabled = value; resetRecognition(); phase = "等待手指放開後開始新手勢"
        record(["type": "enabledChanged", "enabled": enabled])
    }
    func setEditingRule(_ value: Bool) {
        isEditingRule = value; resetRecognition()
        phase = value ? "編輯規則中，手勢暫停" : "等待手指放開後開始新手勢"
    }
    func saveRule(_ rule: GestureRule) throws {
        var updated = rules
        if let i = updated.firstIndex(where: { $0.id == rule.id }) { updated[i] = rule } else { updated.append(rule) }
        try persistRules(updated)
    }
    func removeRule(id: UUID) throws { try persistRules(rules.filter { $0.id != id }) }
    func setRuleEnabled(id: UUID, enabled: Bool) throws {
        var updated = rules
        guard let index = updated.firstIndex(where: { $0.id == id }) else {
            throw NSError(domain: "TouchMiddleRules", code: 2, userInfo: [NSLocalizedDescriptionKey: "找不到要編輯的規則。"])
        }
        updated[index].isEnabled = enabled; try persistRules(updated)
    }
    private func persistRules(_ updated: [GestureRule]) throws {
        guard let store = ruleStore else {
            throw NSError(domain: "TouchMiddleRules", code: 3, userInfo: [NSLocalizedDescriptionKey: "規則儲存位置無法使用。"])
        }
        try store.save(RuleConfiguration(rules: updated)); rules = updated; resetRecognition()
        if rulesLoadFailed { rulesLoadFailed = false; setIssue("rules", nil); startSource() }
        phase = "規則已儲存，等待手指放開"
        record(["type": "rulesSaved", "count": rules.count])
    }
    func applyConfiguration() {
        do {
            recognizer.updateConfiguration(try validatedTapConfiguration(), doubleTapInterval: doubleTapInterval)
            resetRecognition(); UserDefaults.standard.set(movement, forKey: "maximumMovement")
            UserDefaults.standard.set(duration, forKey: "maximumDuration")
            UserDefaults.standard.set(doubleTapInterval, forKey: "doubleTapInterval")
            record(["type": "configuration", "maximumMovement": movement, "maximumDuration": duration, "doubleTapInterval": doubleTapInterval])
            setIssue("settings", nil); startSource()
            phase = "設定已套用，等待手指放開"
        } catch { enabled = false; resetRecognition(); setIssue("settings", "設定無效：\(error.localizedDescription)") }
    }
    func requestPermission() {
        TMRequestAccessibilityPrompt()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!); refreshPermissions()
    }
    private func refreshPermissions() {
        permissionGranted = AXIsProcessTrusted() && CGPreflightPostEventAccess()
        if permissionGranted {
            setIssue("permission", nil)
            if delivery == nil, !sleeping, !shuttingDown, issues.isEmpty { startSource() }
        }
        if !permissionGranted, enabled { enabled = false; resetRecognition(); setIssue("permission", "輔助使用權限已撤回，手勢已暫停。") }
    }
    func delayedOutputTest() {
        manualTest?.cancel()
        manualTest = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(4)) } catch { return }
            guard let self, !self.shuttingDown, !self.sleeping, !self.isEditingRule, let app = self.foregroundTarget() else { return }
            self.postAction(.middleClick, app: app, kind: "manualTest", gesture: nil, rule: nil)
        }
    }
    private func postAction(_ action: RuleAction, app: NSRunningApplication, kind: String, gesture: Int?, rule: GestureRule?) {
        guard !shuttingDown, !sleeping, !isEditingRule, delivery != nil else { return }
        guard let current = foregroundTarget(), current.processIdentifier == app.processIdentifier else {
            lastAction = "App 已切換，本次手勢取消"; resetRecognition(); record(["type": "targetChanged"]); return
        }
        do {
            let marker: Int64
            switch action {
            case .middleClick: marker = try output.post()
            case .shortcut(let shortcut): marker = try keyboardOutput.post(shortcut, targetPID: app.processIdentifier)
            }
            posted += 1; pending[marker] = []
            lastAction = "\(app.localizedName ?? "App")：\(action.title)"
            var values: [String: Any] = ["type": "posted", "kind": kind, "marker": marker,
                "actionKind": action == .middleClick ? "middleClick" : "shortcut", "foreground": app.bundleIdentifier ?? "unknown"]
            if let gesture { values["gesture"] = gesture }
            if let rule { values["ruleID"] = rule.id.uuidString; values["gestureKind"] = rule.gesture.rawValue; values["scope"] = rule.scope.bundleIdentifier ?? "global" }
            record(values)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard let self, self.pending.removeValue(forKey: marker) != nil else { return }
                self.record(["type": "receiptUnconfirmed", "marker": marker])
            }
        } catch ShortcutOutputError.targetChanged {
            lastAction = "App 已切換，本次手勢取消"; resetRecognition(); record(["type": "targetChanged"])
        } catch {
            enabled = false; resetRecognition(); setIssue("output", error.localizedDescription)
            record(["type": "outputError", "message": error.localizedDescription])
        }
    }
    private func installMonitors() {
        let observe: @Sendable (NSEvent) -> Void = { [weak self] event in
            guard let cg = event.cgEvent else { return }
            let marker = cg.getIntegerValueField(.eventSourceUserData)
            let isMiddle = marker & MiddleClickOutput.markerMask == MiddleClickOutput.markerPrefix && event.buttonNumber == 2
            let isKeyboard = marker & KeyboardShortcutOutput.markerMask == KeyboardShortcutOutput.markerPrefix
            guard isMiddle || isKeyboard else { return }
            let type = (event.type == .otherMouseDown || event.type == .keyDown) ? "down" : "up"
            DispatchQueue.main.async { self?.receiveReceipt(marker: marker, type: type) }
        }
        let mask: NSEvent.EventTypeMask = [.otherMouseDown, .otherMouseUp, .keyDown, .keyUp]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: observe)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { event in observe(event); return event }
    }
    private func receiveReceipt(marker: Int64, type: String) {
        guard var parts = pending[marker] else { return }
        parts.insert(type); pending[marker] = parts; record(["type": "observed", "marker": marker, "event": type])
        if parts == ["down", "up"] { observedPairs += 1; pending.removeValue(forKey: marker) }
    }
    private func heartbeat() {
        guard !shuttingDown else { return }; refreshPermissions()
        if delivery != nil, TMRunningDeviceCount() == 0 {
            enabled = false; stopSource(); sourceStatus = "觸控來源已停止"; setIssue("source", "觸控板未回報運作中，請重新啟動 TouchMiddle。")
        }
        updateForegroundName(foregroundTarget())
        record(["type": "status", "frames": frames, "activeContacts": contacts, "recognized": recognized, "posted": posted,
                "observedPairs": observedPairs, "enabled": enabled, "editingRule": isEditingRule, "ruleCount": rules.count,
                "accessibility": AXIsProcessTrusted(), "postEventAccess": CGPreflightPostEventAccess(), "listenEventAccess": CGPreflightListenEventAccess(),
                "sourceRunning": TMRunningDeviceCount(), "maximumDeliveryDelayMS": maximumDelayMS,
                "foreground": foregroundTarget()?.bundleIdentifier ?? "unknown"])
    }
    private func setIssue(_ category: String, _ value: String?) {
        issues[category] = value
        let messages = issues.keys.sorted().compactMap { issues[$0] }
        let nextMessage = messages.isEmpty ? nil : messages.joined(separator: "\n")
        if errorMessage != nextMessage { errorMessage = nextMessage }
    }
    private func record(_ values: [String: Any]) {
        guard let log else { return }
        do { try log.write(values) }
        catch { setIssue("log", "診斷記錄寫入失敗：\(error.localizedDescription)"); enabled = false; self.log = nil; stopSource(); sourceStatus = "記錄失敗，已停止" }
    }
    private func sleep() {
        sleeping = true; manualTest?.cancel(); manualTest = nil; record(["type": "sleep"]); stopSource(); sourceStatus = "Mac 睡眠，觸控來源已停止"
    }
    func shutdown() {
        guard !shuttingDown else { return }; shuttingDown = true; timer?.invalidate(); recognitionTimer?.invalidate(); stopSource()
        manualTest?.cancel(); manualTest = nil
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }; if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        record(["type": "stopped", "runningCount": TMRunningDeviceCount()])
        do { try log?.close() } catch { FileHandle.standardError.write(Data("TouchMiddle log close failed: \(error)\n".utf8)) }
    }
    private func phaseLabel(_ state: RecognitionPhase) -> String {
        switch state {
        case .idle: "等待手勢"
        case .collecting: "正在收集手指"
        case .tracking: "手指已接觸"
        case .blockedUntilRelease: "滑動或多指，等待放開"
        case .cooldown: "手勢完成"
        case .disabled: "已暫停"
        }
    }
}
