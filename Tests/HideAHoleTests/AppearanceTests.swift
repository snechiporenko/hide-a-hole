import AppKit
import XCTest
@testable import hide_a_hole

final class AppearanceTests: XCTestCase {
    func testBackdropOnlyAppearsForDarkMenuBarAppearance() {
        XCTAssertTrue(shouldShowBackdrop(for: NSAppearance(named: .darkAqua)))
        XCTAssertFalse(shouldShowBackdrop(for: NSAppearance(named: .aqua)))
        XCTAssertFalse(shouldShowBackdrop(for: nil))
    }
}

extension AppearanceTests {
    func testCollapsedFramePreservesCenterAndHeight() {
        let frame = CGRect(x: -1512, y: 949, width: 1512, height: 33)
        let collapsed = collapsedFrame(frame)
        XCTAssertEqual(collapsed.midX, frame.midX)
        XCTAssertEqual(collapsed.width, 1)
        XCTAssertEqual(collapsed.minY, frame.minY)
        XCTAssertEqual(collapsed.height, frame.height)
    }
}
