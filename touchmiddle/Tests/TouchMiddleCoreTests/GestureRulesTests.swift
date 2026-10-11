import Foundation
import XCTest
@testable import TouchMiddleCore

final class GestureRulesTests: XCTestCase {
    private func shortcut(_ keyCode: UInt16 = 17, label: String = "T", modifiers: ShortcutModifiers = .command) -> KeyboardShortcut {
        KeyboardShortcut(keyCode: keyCode, modifiers: modifiers, keyLabel: label)
    }

    private func rule(_ gesture: GestureKind = .twoFingerDoubleTap, scope: RuleScope = .global,
                      action: RuleAction = .middleClick, enabled: Bool = true) -> GestureRule {
        GestureRule(gesture: gesture, scope: scope, action: action, isEnabled: enabled)
    }

    func testApplicationRuleOverridesGlobalAndOrderDoesNotChangePrecedence() throws {
        let global = rule(action: .shortcut(shortcut(45, label: "N")))
        let safari = rule(scope: .application(bundleIdentifier: "com.apple.Safari", name: "Safari"),
                          action: .shortcut(shortcut()))
        for orderedRules in [[global, safari], [safari, global]] {
            let configuration = RuleConfiguration(rules: orderedRules)
            try configuration.validate()
            XCTAssertEqual(configuration.resolve(.twoFingerDoubleTap, bundleIdentifier: "com.apple.Safari"), safari)
            XCTAssertEqual(configuration.resolve(.twoFingerDoubleTap, bundleIdentifier: "com.apple.finder"), global)
            XCTAssertEqual(configuration.resolve(.twoFingerDoubleTap, bundleIdentifier: nil), global)
        }
    }

    func testDisabledApplicationRuleFallsBackToEnabledGlobal() throws {
        let global = rule(action: .shortcut(shortcut(45, label: "N")))
        let disabledSafari = rule(scope: .application(bundleIdentifier: "com.apple.Safari", name: "Safari"),
                                 action: .shortcut(shortcut()), enabled: false)
        let configuration = RuleConfiguration(rules: [disabledSafari, global])
        try configuration.validate()
        XCTAssertEqual(configuration.resolve(.twoFingerDoubleTap, bundleIdentifier: "com.apple.Safari"), global)
    }

    func testUnrelatedApplicationAndGestureDoNotTriggerRules() throws {
        let safari = rule(scope: .application(bundleIdentifier: "com.apple.Safari", name: "Safari"))
        let disabledGlobal = rule(.threeFingerDoubleTap, enabled: false)
        let configuration = RuleConfiguration(rules: [safari, disabledGlobal])
        try configuration.validate()
        XCTAssertNil(configuration.resolve(.twoFingerDoubleTap, bundleIdentifier: "com.apple.finder"))
        XCTAssertNil(configuration.resolve(.threeFingerDoubleTap, bundleIdentifier: "com.apple.Safari"))
        XCTAssertNil(configuration.resolve(.threeFingerTap, bundleIdentifier: "com.apple.Safari"))
        XCTAssertEqual(configuration.gestures(bundleIdentifier: "com.apple.Safari"), [.twoFingerDoubleTap])
        XCTAssertTrue(configuration.gestures(bundleIdentifier: "com.apple.finder").isEmpty)
    }

    func testDisablingAllScopesProducesNoAction() {
        let global = rule(enabled: false)
        let app = rule(scope: .application(bundleIdentifier: "com.apple.Safari", name: "Safari"), enabled: false)
        let configuration = RuleConfiguration(rules: [global, app])
        XCTAssertNil(configuration.resolve(.twoFingerDoubleTap, bundleIdentifier: "com.apple.Safari"))
    }

    func testDuplicateAppScopeIsRejectedEvenWhenDisplayNamesDifferOrOneRuleIsDisabled() {
        let configuration = RuleConfiguration(rules: [
            rule(scope: .application(bundleIdentifier: "com.apple.Safari", name: "Safari")),
            rule(scope: .application(bundleIdentifier: "com.apple.Safari", name: "瀏覽器"), enabled: false)
        ])
        XCTAssertThrowsError(try configuration.validate()) { XCTAssertEqual($0 as? RuleValidationError, .duplicateRule) }
    }

    func testDifferentGesturesInSameScopeAreValid() throws {
        let app = RuleScope.application(bundleIdentifier: "com.apple.Safari", name: "Safari")
        let configuration = RuleConfiguration(rules: [rule(scope: app), rule(.threeFingerDoubleTap, scope: app)])
        try configuration.validate()
        XCTAssertEqual(configuration.gestures(bundleIdentifier: "com.apple.Safari"), [.twoFingerDoubleTap, .threeFingerDoubleTap])
    }

    func testDuplicateGlobalScopeAndDuplicateIdentifiersAreRejected() {
        XCTAssertThrowsError(try RuleConfiguration(rules: [rule(), rule()]).validate()) {
            XCTAssertEqual($0 as? RuleValidationError, .duplicateRule)
        }
        let first = rule()
        var another = rule(.threeFingerDoubleTap)
        another.id = first.id
        XCTAssertThrowsError(try RuleConfiguration(rules: [first, another]).validate()) {
            XCTAssertEqual($0 as? RuleValidationError, .duplicateIdentifier)
        }
    }

    func testUnsupportedVersionAndEmptyApplicationAreRejected() {
        XCTAssertThrowsError(try RuleConfiguration(rules: [], version: 2).validate()) {
            XCTAssertEqual($0 as? RuleValidationError, .unsupportedVersion)
        }
        XCTAssertThrowsError(try RuleConfiguration(rules: [
            rule(scope: .application(bundleIdentifier: " \n ", name: "Unknown"))
        ]).validate()) { XCTAssertEqual($0 as? RuleValidationError, .invalidApplication) }
    }

    func testInvalidShortcutFieldsAreRejectedBeforeDispatch() {
        let invalid = [shortcut(128), shortcut(label: " \n "),
                       shortcut(modifiers: ShortcutModifiers(rawValue: 0x80)),
                       shortcut(55, label: "⌘"), shortcut(63, label: "Fn")]
        for shortcut in invalid {
            XCTAssertThrowsError(try shortcut.validate()) { XCTAssertEqual($0 as? RuleValidationError, .invalidShortcut) }
            XCTAssertThrowsError(try RuleConfiguration(rules: [rule(action: .shortcut(shortcut))]).validate()) {
                XCTAssertEqual($0 as? RuleValidationError, .invalidShortcut)
            }
        }
    }

    func testRuleConfigurationRoundTripPreservesActionsScopesAndEnabledState() throws {
        let configuration = RuleConfiguration(rules: [
            rule(.threeFingerTap),
            rule(action: .shortcut(shortcut(modifiers: [.control, .option, .shift, .command]))),
            rule(.threeFingerDoubleTap, scope: .application(bundleIdentifier: "com.apple.Safari", name: "Safari"),
                 action: .shortcut(shortcut(45, label: "N")), enabled: false)
        ])
        try configuration.validate()
        let decoded = try JSONDecoder().decode(RuleConfiguration.self, from: JSONEncoder().encode(configuration))
        try decoded.validate()
        XCTAssertEqual(decoded, configuration)
        XCTAssertEqual(decoded.rules[1].action.title, "⌃⌥⇧⌘T")
    }

    func testInitialRulesPreserveExistingThreeFingerMiddleClickOnly() throws {
        let configuration = RuleConfiguration.initial
        try configuration.validate()
        XCTAssertEqual(configuration.resolve(.threeFingerTap, bundleIdentifier: "com.apple.Safari")?.action, .middleClick)
        XCTAssertNil(configuration.resolve(.twoFingerDoubleTap, bundleIdentifier: "com.apple.Safari"))
        XCTAssertNil(configuration.resolve(.threeFingerDoubleTap, bundleIdentifier: "com.apple.Safari"))
    }
}
