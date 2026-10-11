import SwiftUI
import AppKit
import UniformTypeIdentifiers
import TouchMiddleCore

@main
struct TouchMiddleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        MenuBarExtra("TouchMiddle", systemImage: "hand.tap") {
            TouchMiddleMenu(controller: delegate.controller, showWindow: delegate.showWindow)
        }
    }
}

private struct TouchMiddleMenu: View {
    @ObservedObject var controller: TouchController
    let showWindow: () -> Void
    var body: some View {
        Button(controller.enabled ? "暫停手勢" : "啟用手勢") { controller.setEnabled(!controller.enabled) }
        Button("開啟手勢與設定", action: showWindow)
        Divider()
        Button("結束 TouchMiddle") { NSApp.terminate(nil) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = TouchController()
    private var window: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) { showWindow() }
    func applicationWillTerminate(_ notification: Notification) { controller.shutdown() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }
    func showWindow() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 740),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "TouchMiddle"
            w.minSize = NSSize(width: 760, height: 640)
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: Dashboard(controller: controller))
            w.center(); window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct RuleEditorItem: Identifiable {
    let id = UUID()
    let rule: GestureRule?
}

struct Dashboard: View {
    @ObservedObject var controller: TouchController
    @StateObject private var loginItem = LoginItemSettings()
    @State private var editor: RuleEditorItem?
    @State private var ruleError: String?

    var body: some View {
        TabView {
            rulesPage
                .tabItem { Text("手勢規則") }
            ScrollView { settingsPage }
                .tabItem { Text("狀態與設定") }
        }
        .padding(16)
        .sheet(item: $editor) { item in
            RuleEditor(controller: controller, rule: item.rule)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem.refresh()
        }
    }

    private var rulesPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "hand.tap").font(.system(size: 32)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("手勢與快捷鍵").font(.title2.bold())
                    Text("為全域或指定 App 設定觸控板手勢。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("啟用手勢", isOn: Binding(get: { controller.enabled }, set: { controller.setEnabled($0) }))
                    .toggleStyle(.switch)
            }
            GroupBox("手勢規則") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Spacer()
                        Button("新增規則", systemImage: "plus") { openEditor(nil) }
                    }
                    List {
                        ForEach(controller.rules) { rule in
                            ruleRow(rule)
                        }
                    }
                    .listStyle(.inset)
                    .overlay {
                        if controller.rules.isEmpty {
                            Text("尚無規則。新增手勢，再選擇快捷鍵與 App 範圍。")
                                .foregroundStyle(.secondary)
                                .padding(20)
                        }
                    }
                    Text("指定 App 的已啟用規則優先於全域；指定規則停用時，使用全域規則。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("雙擊是連續兩次輕點，每次完全放開；不需要按下觸控板。")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(8)
            }
            if let ruleError { Text(ruleError).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            if let message = controller.errorMessage {
                Text(message).font(.callout).foregroundStyle(.red).textSelection(.enabled)
            }
            Text("編輯規則時暫停動作輸出。觸控狀態、輔助使用權限與點按設定位於「狀態與設定」。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(16)
    }

    private var settingsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("啟動設定") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("登入 macOS 時自動啟動 TouchMiddle", isOn: Binding(
                        get: { loginItem.isRegistered }, set: { loginItem.setEnabled($0) }
                    ))
                    .toggleStyle(.switch)
                    Text(loginItem.statusMessage).font(.caption).foregroundStyle(.secondary)
                    Text("開機後登入此帳號時生效；啟動後手勢仍預設暫停。")
                        .font(.caption).foregroundStyle(.secondary)
                    if loginItem.status == .requiresApproval {
                        Button("開啟系統登入項目設定") { loginItem.openSystemSettings() }
                    }
                    if let message = loginItem.errorMessage {
                        Text(message).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }
            GroupBox("觸控狀態") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(controller.sourceStatus)
                        Spacer()
                        Text(controller.phase).foregroundStyle(.secondary)
                    }
                    if !controller.foregroundName.isEmpty {
                        Text("前景 App：\(controller.foregroundName)").font(.callout).foregroundStyle(.secondary)
                    }
                    Text("最近動作：\(controller.lastAction)").font(.callout).textSelection(.enabled)
                    HStack {
                        Text("影格 \(controller.frames)"); Spacer(); Text("接觸手指 \(controller.contacts)")
                        Spacer(); Text("辨識 \(controller.recognized)"); Spacer(); Text("送出 \(controller.posted)")
                    }.font(.caption)
                    Text("觀察到輸入事件按下／放開：\(controller.observedPairs) 組")
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }
            HStack {
                Label(controller.permissionGranted ? "輔助使用權限已允許" : "輸出動作需要輔助使用權限",
                      systemImage: controller.permissionGranted ? "checkmark.circle" : "lock").font(.callout)
                Spacer()
                Button("開啟權限設定") { controller.requestPermission() }
            }
            if let message = controller.errorMessage {
                Text(message).font(.callout).foregroundStyle(.red).textSelection(.enabled)
            }
            GroupBox("點按設定") {
                VStack(alignment: .leading, spacing: 8) {
                    settingLine("可移動距離（觸控板比例）", value: controller.movement.formatted(.percent.precision(.fractionLength(1))))
                    Slider(value: $controller.movement, in: 0.01...0.05, step: 0.001)
                    settingLine("單次輕點最長時間", value: "\(Int(controller.duration * 1000)) ms")
                    Slider(value: $controller.duration, in: 0.15...0.4, step: 0.01)
                    settingLine("雙擊兩次輕點的最長間隔", value: "\(Int(controller.doubleTapInterval * 1000)) ms")
                    Slider(value: $controller.doubleTapInterval, in: 0.15...0.6, step: 0.01)
                    Button("套用點按設定") { controller.applyConfiguration() }
                }.padding(6)
            }
            Text("只處理內建觸控板。移動、捲動與四指手勢會取消候選點按。啟用或喚醒後，先碰一下再完全放開。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("4 秒後測試中鍵輸出") { controller.delayedOutputTest() }
                    .disabled(!controller.permissionGranted)
                Button("顯示診斷記錄") {
                    if !controller.logPath.isEmpty {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: controller.logPath)])
                    }
                }
                Spacer()
            }
            Spacer(minLength: 0)
        }.padding(16)
        .onAppear { loginItem.refresh() }
    }

    private func settingLine(_ label: String, value: String) -> some View {
        HStack { Text(label); Spacer(); Text(value).monospacedDigit() }
    }

    private func openEditor(_ rule: GestureRule?) {
        ruleError = nil
        controller.setEditingRule(true)
        editor = RuleEditorItem(rule: rule)
    }

    private func ruleRow(_ rule: GestureRule) -> some View {
        HStack(spacing: 12) {
            Toggle("啟用 \(rule.scope.title) 的 \(rule.gesture.title)", isOn: Binding(get: { rule.isEnabled }, set: { value in
                do { try controller.setRuleEnabled(id: rule.id, enabled: value); ruleError = nil }
                catch { ruleError = error.localizedDescription }
            }))
            .labelsHidden().toggleStyle(.switch)
            VStack(alignment: .leading, spacing: 3) {
                Text(rule.gesture.title).font(.body.weight(.medium))
                Label(rule.scope.title, systemImage: rule.scope.bundleIdentifier == nil ? "globe" : "app")
                    .font(.caption).foregroundStyle(.secondary)
                    .help(rule.scope.bundleIdentifier ?? "所有 App")
            }.frame(width: 175, alignment: .leading)
            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            Text(rule.action.title).font(.body.weight(.medium)).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("編輯") { openEditor(rule) }
            Button {
                do { try controller.removeRule(id: rule.id); ruleError = nil }
                catch { ruleError = error.localizedDescription }
            } label: { Image(systemName: "trash") }
                .help("刪除此規則")
                .accessibilityLabel("刪除 \(rule.scope.title) 的 \(rule.gesture.title)")
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 5)
        .accessibilityElement(children: .contain)
    }
}

private enum ScopeChoice: Hashable { case global, application }
private enum ActionChoice: Hashable { case shortcut, middleClick }

private struct RuleEditor: View {
    @ObservedObject var controller: TouchController
    @Environment(\.dismiss) private var dismiss
    private let ruleID: UUID
    private let isNew: Bool
    @State private var gesture: GestureKind
    @State private var scopeChoice: ScopeChoice
    @State private var applicationScope: RuleScope?
    @State private var actionChoice: ActionChoice
    @State private var shortcut: TouchMiddleCore.KeyboardShortcut?
    @State private var enabled: Bool
    @State private var isRecording = false
    @State private var error: String?

    init(controller: TouchController, rule: GestureRule?) {
        self.controller = controller
        ruleID = rule?.id ?? UUID()
        isNew = rule == nil
        _gesture = State(initialValue: rule?.gesture ?? .twoFingerDoubleTap)
        _scopeChoice = State(initialValue: rule?.scope.bundleIdentifier == nil ? .global : .application)
        _applicationScope = State(initialValue: rule?.scope.bundleIdentifier == nil ? nil : rule?.scope)
        _enabled = State(initialValue: rule?.isEnabled ?? true)
        if case .shortcut(let value) = rule?.action {
            _actionChoice = State(initialValue: .shortcut)
            _shortcut = State(initialValue: value)
        } else {
            _actionChoice = State(initialValue: rule == nil ? .shortcut : .middleClick)
            _shortcut = State(initialValue: nil)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(isNew ? "新增手勢規則" : "編輯手勢規則").font(.title2.bold())
            Text("編輯期間暫停手勢輸出，儲存後重新等待手指完全放開。")
                .font(.callout).foregroundStyle(.secondary)
            Form {
                Picker("手勢", selection: $gesture) {
                    ForEach(GestureKind.allCases) { Text($0.title).tag($0) }
                }
                Picker("套用範圍", selection: $scopeChoice) {
                    Text("全域（所有 App）").tag(ScopeChoice.global)
                    Text("指定 App").tag(ScopeChoice.application)
                }
                if scopeChoice == .application {
                    HStack {
                        if let applicationScope {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(applicationScope.title)
                                Text(applicationScope.bundleIdentifier ?? "").font(.caption).foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        } else {
                            Text("尚未選擇 App").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("選擇 App…") { selectApplication() }.disabled(isRecording)
                    }
                }
                Picker("觸發動作", selection: $actionChoice) {
                    Text("鍵盤快捷鍵").tag(ActionChoice.shortcut)
                    Text("中鍵（游標位置）").tag(ActionChoice.middleClick)
                }
                if actionChoice == .shortcut {
                    VStack(alignment: .leading, spacing: 10) {
                        ShortcutRecorderView(shortcut: $shortcut, isRecording: $isRecording).frame(height: 48)
                        HStack {
                            Button(isRecording ? "停止錄製" : "錄製快捷鍵") { isRecording.toggle() }
                            if shortcut != nil { Button("清除") { isRecording = false; shortcut = nil } }
                            Spacer()
                        }
                        Text("按下「錄製快捷鍵」後輸入組合鍵，可包含 ⌘、⌥、⌃、⇧。Escape 停止錄製，不會送出快捷鍵。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text("在目前游標位置送出中鍵。若要開啟連結的新分頁，游標需位於連結上。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("啟用此規則", isOn: $enabled)
            }.formStyle(.grouped)
            if let error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Spacer()
                Button("取消") { isRecording = false; dismiss() }.keyboardShortcut(.cancelAction)
                Button("儲存") { save() }.keyboardShortcut(.defaultAction).disabled(isRecording)
            }
        }
        .padding(24).frame(width: 590)
        .onAppear { controller.setEditingRule(true) }
        .onDisappear { controller.setEditingRule(false) }
        .onChange(of: actionChoice) { _, _ in isRecording = false }
        .onChange(of: gesture) { _, _ in isRecording = false }
        .onChange(of: scopeChoice) { _, _ in isRecording = false }
    }

    private func selectApplication() {
        let panel = NSOpenPanel()
        panel.title = "選擇套用規則的 App"
        panel.prompt = "選擇 App"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier,
              !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error = "所選 App 沒有有效的 bundle identifier，請選擇另一個 App。"
            return
        }
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        applicationScope = .application(bundleIdentifier: identifier, name: name)
        error = nil
    }

    private func save() {
        let scope: RuleScope
        if scopeChoice == .global { scope = .global }
        else if let applicationScope { scope = applicationScope }
        else { error = "請先選擇要套用規則的 App。"; return }
        let action: RuleAction
        if actionChoice == .middleClick { action = .middleClick }
        else if let shortcut { action = .shortcut(shortcut) }
        else { error = "請先錄製要觸發的快捷鍵。"; return }
        do {
            try controller.saveRule(GestureRule(id: ruleID, gesture: gesture, scope: scope, action: action, isEnabled: enabled))
            isRecording = false
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
