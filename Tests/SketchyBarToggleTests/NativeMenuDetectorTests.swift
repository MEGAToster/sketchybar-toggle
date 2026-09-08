import CoreGraphics
import XCTest
@testable import SketchyBarToggleCore

final class NativeMenuDetectorTests: XCTestCase {

    private let popUpLevel = CGWindowLevelForKey(.popUpMenuWindow)

    private func windowDict(layer: Int32, owner: String? = nil) -> [String: Any] {
        var dict: [String: Any] = [kCGWindowLayer as String: NSNumber(value: layer)]
        if let owner = owner {
            dict[kCGWindowOwnerName as String] = owner
        }
        return dict
    }

    // MARK: - SketchyBar's own popup windows are ignored

    func testPopupLevelSketchybarOwnerIsNotANativeMenu() {
        let dict = windowDict(layer: popUpLevel, owner: "sketchybar")
        XCTAssertFalse(NativeMenuDetector.isNativeMenuWindow(dict, popUpMenuLevel: popUpLevel))
    }

    func testPopupLevelSketchybarOwnerIsIgnoredCaseInsensitively() {
        let dict = windowDict(layer: popUpLevel, owner: "SketchyBar")
        XCTAssertFalse(NativeMenuDetector.isNativeMenuWindow(dict, popUpMenuLevel: popUpLevel))
    }

    func testPopupLevelSketchybarChildItemWindowIsIgnored() {
        // Items inside a SketchyBar popup are separate windows at the same level,
        // still owned by the sketchybar process.
        let dict = windowDict(layer: popUpLevel, owner: "sketchybar")
        XCTAssertFalse(NativeMenuDetector.isNativeMenuWindow(dict, popUpMenuLevel: popUpLevel))
    }

    // MARK: - Genuine native menus are still detected

    func testPopupLevelForeignOwnerIsANativeMenu() {
        let dict = windowDict(layer: popUpLevel, owner: "Mail")
        XCTAssertTrue(NativeMenuDetector.isNativeMenuWindow(dict, popUpMenuLevel: popUpLevel))
    }

    func testPopupLevelMissingOwnerIsANativeMenu() {
        let dict = windowDict(layer: popUpLevel)
        XCTAssertTrue(NativeMenuDetector.isNativeMenuWindow(dict, popUpMenuLevel: popUpLevel))
    }

    // MARK: - Non-popup windows never count

    func testNormalLevelWindowIsNotANativeMenu() {
        let dict = windowDict(layer: 0, owner: "Mail")
        XCTAssertFalse(NativeMenuDetector.isNativeMenuWindow(dict, popUpMenuLevel: popUpLevel))
    }

    func testNormalLevelSketchybarWindowIsNotANativeMenu() {
        let dict = windowDict(layer: 0, owner: "sketchybar")
        XCTAssertFalse(NativeMenuDetector.isNativeMenuWindow(dict, popUpMenuLevel: popUpLevel))
    }

    func testStatusLevelWindowIsNotANativeMenu() {
        let statusLevel = CGWindowLevelForKey(.statusWindow)
        let dict = windowDict(layer: statusLevel, owner: "Control Center")
        XCTAssertFalse(NativeMenuDetector.isNativeMenuWindow(dict, popUpMenuLevel: popUpLevel))
    }
}
