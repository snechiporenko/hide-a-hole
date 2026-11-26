import CoreGraphics
import XCTest
@testable import hide_a_hole

final class CursorBoundsTests: XCTestCase {
    func testTopEdgeIsIncludedWithoutExpandingOtherEdges() {
        let frame = CGRect(x: 10, y: 949, width: 100, height: 33)
        XCTAssertTrue(containsCursor(CGPoint(x: 20, y: 982), in: frame))
        XCTAssertTrue(containsCursor(CGPoint(x: 20, y: 981.5), in: frame))
        XCTAssertFalse(containsCursor(CGPoint(x: 20, y: 982.5), in: frame))
        XCTAssertFalse(containsCursor(CGPoint(x: 110, y: 982), in: frame))
        XCTAssertFalse(containsCursor(CGPoint(x: 20, y: 949), in: CGRect(x: 10, y: 949, width: 100, height: 0)))
    }
}
