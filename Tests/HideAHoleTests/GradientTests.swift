import AppKit
import XCTest
@testable import hide_a_hole

final class GradientTests: XCTestCase {
    func testGradientEndsAtOpaqueBlackWithoutAClipEdge() throws {
        let width = 120
        let height = 120
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(NSColor.black.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            drawCursorGradient(in: context, center: CGPoint(x: 60.25, y: 60.25), radius: 30, color: .transparent)
        }
        func pixel(_ x: Int, _ y: Int) -> [UInt8] {
            let i = y * bytesPerRow + x * 4
            return Array(pixels[i..<(i + 4)])
        }
        XCTAssertLessThan(pixel(60, 60)[3], 20)
        for x in 92...110 { XCTAssertEqual(pixel(x, 60), [0, 0, 0, 255]) }
        for y in 92...110 { XCTAssertEqual(pixel(60, y), [0, 0, 0, 255]) }
    }
}
