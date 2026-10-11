import XCTest
import ServiceManagement
@testable import TouchMiddle

@MainActor
private final class FakeLoginItemService: LoginItemService {
    var status: SMAppService.Status = .notRegistered
    var registrationResult: SMAppService.Status = .enabled
    var failure: Error?
    var registrations = 0
    var removals = 0

    func register() throws {
        registrations += 1
        if let failure { throw failure }
        status = registrationResult
    }
    func unregister() throws {
        removals += 1
        if let failure { throw failure }
        status = .notRegistered
    }
}

final class LoginItemSettingsTests: XCTestCase {
    func testOnlyExplicitToggleRegistersAndUnregisters() async {
        await MainActor.run {
            let service = FakeLoginItemService()
            let settings = LoginItemSettings(service: service)
            settings.refresh()
            XCTAssertEqual(service.registrations, 0)
            XCTAssertFalse(settings.isRegistered)
            settings.setEnabled(true)
            XCTAssertEqual(settings.status, .enabled)
            settings.setEnabled(true)
            XCTAssertEqual(service.registrations, 1)
            settings.setEnabled(false)
            XCTAssertFalse(settings.isRegistered)
            XCTAssertEqual(service.removals, 1)
        }
    }

    func testPendingApprovalIsRegisteredButDoesNotClaimEnabled() async {
        await MainActor.run {
            let service = FakeLoginItemService()
            service.registrationResult = .requiresApproval
            let settings = LoginItemSettings(service: service)
            settings.setEnabled(true)
            XCTAssertTrue(settings.isRegistered)
            XCTAssertEqual(settings.status, .requiresApproval)
            XCTAssertTrue(settings.statusMessage.contains("尚未獲准"))
            settings.setEnabled(false)
            XCTAssertEqual(service.removals, 1)
            XCTAssertEqual(settings.status, .notRegistered)
        }
    }

    func testRegistrationFailureKeepsOSStateAndReportsError() async {
        await MainActor.run {
            let service = FakeLoginItemService()
            service.failure = NSError(domain: "Test", code: 1)
            let settings = LoginItemSettings(service: service)
            settings.setEnabled(true)
            XCTAssertFalse(settings.isRegistered)
            XCTAssertNotNil(settings.errorMessage)
            service.failure = nil
            settings.setEnabled(true)
            XCTAssertTrue(settings.isRegistered)
            XCTAssertNil(settings.errorMessage)
        }
    }

    func testRemovalFailureKeepsEnabledStateAndReportsError() async {
        await MainActor.run {
            let service = FakeLoginItemService()
            service.status = .enabled
            service.failure = NSError(domain: "Test", code: 2)
            let settings = LoginItemSettings(service: service)
            settings.setEnabled(false)
            XCTAssertEqual(settings.status, .enabled)
            XCTAssertNotNil(settings.errorMessage)
        }
    }

    func testExternalChangesAreReadBackBeforeNextToggle() async {
        await MainActor.run {
            let service = FakeLoginItemService()
            service.status = .enabled
            let settings = LoginItemSettings(service: service)
            service.status = .notRegistered
            settings.setEnabled(true)
            XCTAssertEqual(service.registrations, 1)
            service.status = .requiresApproval
            settings.refresh()
            XCTAssertEqual(settings.status, .requiresApproval)
            XCTAssertEqual(service.removals, 0)
        }
    }
}
