import Combine
import Foundation
import ServiceManagement

@MainActor
protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

@MainActor
private struct MainAppLoginItemService: LoginItemService {
    var status: SMAppService.Status { SMAppService.mainApp.status }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}

/// The OS owns this setting. Do not persist a separate preference that could
/// disagree with changes made in System Settings.
@MainActor
final class LoginItemSettings: ObservableObject {
    @Published private(set) var status: SMAppService.Status
    @Published private(set) var errorMessage: String?
    private let service: any LoginItemService

    init(service: any LoginItemService) {
        self.service = service
        status = service.status
    }

    convenience init() { self.init(service: MainAppLoginItemService()) }

    var isRegistered: Bool { status == .enabled || status == .requiresApproval }

    var statusMessage: String {
        switch status {
        case .notRegistered: "已關閉登入時自動啟動。"
        case .enabled: "已啟用，下次登入此 macOS 帳號時會自動啟動。"
        case .requiresApproval: "已登記，但尚未獲准自動啟動。請在系統的登入項目設定中允許 TouchMiddle。"
        case .notFound: "系統找不到此應用程式。請從安裝位置啟動 TouchMiddle.app 後重試。"
        @unknown default: "無法確認登入項目狀態。"
        }
    }

    func refresh() { status = service.status }

    func setEnabled(_ enabled: Bool) {
        refresh()
        errorMessage = nil
        guard enabled != isRegistered else { return }
        do {
            if enabled { try service.register() }
            else { try service.unregister() }
        } catch {
            errorMessage = "無法\(enabled ? "啟用" : "關閉")登入時自動啟動：\(error.localizedDescription)"
        }
        // Registration can succeed while still requiring user approval.
        refresh()
    }

    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
