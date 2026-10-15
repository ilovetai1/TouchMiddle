import Foundation
import XCTest
@testable import TouchMiddleCore

final class ModifierRuleTests: XCTestCase {
    func testAllModifierCombinationsResolveExactlyAndRoundTrip() throws {
        let rules = (UInt8(0)...15).map {
            GestureRule(gesture: .fourFingerTap, scope: .global, action: .middleClick,
                        requiredModifiers: ShortcutModifiers(rawValue: $0))
        }
        let config = RuleConfiguration(rules: rules)
        try config.validate()
        let decoded = try JSONDecoder().decode(RuleConfiguration.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(config, decoded)
        XCTAssertEqual(config.version, 2)
        for rule in rules {
            XCTAssertEqual(decoded.resolve(.fourFingerTap, bundleIdentifier: nil, modifiers: rule.requiredModifiers), rule)
        }
    }
    func testLegacyRuleWithoutModifierFieldLoadsAsUnmodified() throws {
        let config = RuleConfiguration(rules: [.init(gesture: .threeFingerTap, scope: .global, action: .middleClick)], version: 1)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any])
        var rules = try XCTUnwrap(json["rules"] as? [[String: Any]])
        rules[0].removeValue(forKey: "requiredModifiers")
        json["rules"] = rules
        let decoded = try JSONDecoder().decode(RuleConfiguration.self, from: JSONSerialization.data(withJSONObject: json))
        try decoded.validate()
        XCTAssertEqual(decoded.rules[0].requiredModifiers, [])
        XCTAssertNotNil(decoded.resolve(.threeFingerTap, bundleIdentifier: nil))
        XCTAssertNil(decoded.resolve(.threeFingerTap, bundleIdentifier: nil, modifiers: .option))
    }
    func testAppPrecedenceAppliesOnlyWithinExactModifierCombination() throws {
        let global = GestureRule(gesture: .fourFingerTap, scope: .global, action: .middleClick, requiredModifiers: .option)
        let specific = GestureRule(gesture: .fourFingerTap, scope: .application(bundleIdentifier: "app", name: "App"),
                                  action: .middleClick, requiredModifiers: .command)
        let config = RuleConfiguration(rules: [global, specific])
        try config.validate()
        XCTAssertEqual(config.resolve(.fourFingerTap, bundleIdentifier: "app", modifiers: .option), global)
        XCTAssertEqual(config.resolve(.fourFingerTap, bundleIdentifier: "app", modifiers: .command), specific)
        XCTAssertNil(config.resolve(.fourFingerTap, bundleIdentifier: "app", modifiers: [.option, .command]))
        XCTAssertNil(config.resolve(.fourFingerTap, bundleIdentifier: "app"))
    }
    func testInvalidMaskAndDuplicateTriggerAreRejected() {
        let invalid = GestureRule(gesture: .fourFingerTap, scope: .global, action: .middleClick,
                                  requiredModifiers: ShortcutModifiers(rawValue: 0x80))
        XCTAssertThrowsError(try RuleConfiguration(rules: [invalid]).validate())
        let rule = GestureRule(gesture: .fourFingerTap, scope: .global, action: .middleClick, requiredModifiers: .option)
        let duplicate = GestureRule(gesture: .fourFingerTap, scope: .global, action: .middleClick, requiredModifiers: .option)
        XCTAssertThrowsError(try RuleConfiguration(rules: [rule, duplicate]).validate())
    }
    func testModifierContextChangeCancelsPendingSingleAndHeldGesture() {
        var r = ConfigurableGestureRecognizer()
        let g: Set<GestureKind> = [.threeFingerTap, .threeFingerDoubleTap]
        let contacts = (0..<3).map { TouchContact(id: $0, position: TouchPoint(x: 0.3 + Double($0) * 0.1, y: 0.5)) }
        _ = r.process(TouchFrame(deviceID: "A", timestamp: 0, contacts: contacts), contextID: "app:1:option", gestures: g)
        _ = r.process(TouchFrame(deviceID: "A", timestamp: 0.04, contacts: []), contextID: "app:1:option", gestures: g)
        XCTAssertTrue(r.flush(deviceID: "A", timestamp: 0.4, contextID: "app:1:command", gestures: g).gestures.isEmpty)
        _ = r.process(TouchFrame(deviceID: "A", timestamp: 0.5, contacts: contacts), contextID: "app:1:option", gestures: g)
        _ = r.process(TouchFrame(deviceID: "A", timestamp: 0.52, contacts: contacts), contextID: "app:1:command", gestures: g)
        XCTAssertTrue(r.process(TouchFrame(deviceID: "A", timestamp: 0.54, contacts: []), contextID: "app:1:command", gestures: g).gestures.isEmpty)
        XCTAssertTrue(r.flush(deviceID: "A", timestamp: 1, contextID: "app:1:command", gestures: g).gestures.isEmpty)
    }
    func testExplicitNullModifierFieldIsInvalidInsteadOfBecomingUnmodified() throws {
        let rule = GestureRule(gesture: .fourFingerTap, scope: .global, action: .middleClick)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(rule)) as? [String: Any])
        json["requiredModifiers"] = NSNull()
        XCTAssertThrowsError(try JSONDecoder().decode(GestureRule.self, from: JSONSerialization.data(withJSONObject: json)))
    }

}
