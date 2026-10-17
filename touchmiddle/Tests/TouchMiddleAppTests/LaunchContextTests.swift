import AppKit
import Carbon
import XCTest
@testable import TouchMiddle

final class LaunchContextTests: XCTestCase {
    func testLoginOpenApplicationEventStartsInBackground() {
        XCTAssertTrue(LaunchContext.isLoginItem(event(id: kAEOpenApplication, property: keyAELaunchedAsLogInItem)))
    }

    func testManualOpenAndMissingEventKeepSettingsAvailable() {
        XCTAssertFalse(LaunchContext.isLoginItem(event(id: kAEOpenApplication)))
        XCTAssertFalse(LaunchContext.isLoginItem(nil))
    }

    func testOtherLaunchReasonsAndUnrelatedEventsAreNotLoginLaunches() {
        XCTAssertFalse(LaunchContext.isLoginItem(event(id: kAEOpenApplication, property: keyAELaunchedAsServiceItem)))
        XCTAssertFalse(LaunchContext.isLoginItem(event(id: kAEReopenApplication, property: keyAELaunchedAsLogInItem)))
    }

    private func event(id: AEEventID, property: OSType? = nil) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(
            eventClass: kCoreEventClass, eventID: id,
            targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        if let property {
            event.setParam(NSAppleEventDescriptor(enumCode: property), forKeyword: keyAEPropData)
        }
        return event
    }
}
