import Foundation
import XCTest
@testable import hide_a_hole

final class ConfigurationTests: XCTestCase {
    func testColorsAndLegacySettings() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("config.json")
        let config = Configuration(url: url)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertEqual(try config.cursorColor(), .transparent)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{\"holeEnabled\":false,\"other\":42}".utf8).write(to: url)
        XCTAssertEqual(try config.cursorColor(), .black)
        try config.setCursorColor(try GradientColor("#ff000080"))
        XCTAssertEqual(try config.cursorColor().hex, "#FF000080")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(object["other"] as? Int, 42)
        XCTAssertNil(object["holeEnabled"])
        XCTAssertThrowsError(try GradientColor("#123456"))
        XCTAssertThrowsError(try GradientColor("#FF0000GG"))
        let invalid = Data("{\"cursorColor\":1}".utf8)
        try invalid.write(to: url)
        XCTAssertThrowsError(try config.setCursorColor(.black))
        XCTAssertEqual(try Data(contentsOf: url), invalid)
        try Data("{".utf8).write(to: url)
        XCTAssertThrowsError(try config.cursorColor())
    }
}

extension ConfigurationTests {
    func testRadius() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("config.json")
        let config = Configuration(url: url)
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertEqual(try config.cursorRadius(), 100)
        try config.setCursorColor(try GradientColor("#FF000080"))
        try config.setCursorRadius(37.5)
        XCTAssertEqual(try config.cursorRadius(), 37.5)
        XCTAssertEqual(try config.cursorColor().hex, "#FF000080")
        XCTAssertThrowsError(try config.setCursorRadius(0))
        XCTAssertThrowsError(try config.setCursorRadius(.infinity))
        XCTAssertEqual(try config.cursorRadius(), 37.5)
        try Data("{\"cursorRadius\":true}".utf8).write(to: url)
        XCTAssertThrowsError(try config.cursorRadius())
    }
}
