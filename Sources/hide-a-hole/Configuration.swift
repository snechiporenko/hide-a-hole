import Foundation
import CoreFoundation

struct GradientColor: Equatable {
    let value: UInt32
    static let transparent = GradientColor(value: 0x00000000)
    static let black = GradientColor(value: 0x000000FF)

    init(value: UInt32) { self.value = value }

    init(_ text: String) throws {
        guard text.utf8.count == 9, text.first == "#",
              text.dropFirst().utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
              let value = UInt32(text.dropFirst(), radix: 16) else {
            throw NSError(domain: "hide-a-hole", code: 1, userInfo: [NSLocalizedDescriptionKey: "Color must be in #RRGGBBAA format."])
        }
        self.value = value
    }

    var hex: String { String(format: "#%08X", value) }
}

struct Configuration {
    let url: URL

    private func contents() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let value = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        guard let object = value as? [String: Any] else {
            throw NSError(domain: "hide-a-hole", code: 1, userInfo: [NSLocalizedDescriptionKey: "Configuration must be a JSON object."])
        }
        return object
    }

    private func color(in object: [String: Any]) throws -> GradientColor {
        if let value = object["cursorColor"] {
            guard let text = value as? String else {
                throw NSError(domain: "hide-a-hole", code: 1, userInfo: [NSLocalizedDescriptionKey: "cursorColor must be a #RRGGBBAA string."])
            }
            return try GradientColor(text)
        }
        if let value = object["holeEnabled"] {
            guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
                throw NSError(domain: "hide-a-hole", code: 1, userInfo: [NSLocalizedDescriptionKey: "holeEnabled must be true or false."])
            }
            return number.boolValue ? .transparent : .black
        }
        return .transparent
    }

    static func validateRadius(_ value: Double) throws -> Double {
        guard value.isFinite, value >= 1, value <= 10000 else {
            throw NSError(domain: "hide-a-hole", code: 1, userInfo: [NSLocalizedDescriptionKey: "cursorRadius must be a number between 1 and 10000."])
        }
        return value
    }

    func cursorRadius() throws -> Double {
        let object = try contents()
        guard let value = object["cursorRadius"] else { return 100 }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else {
            throw NSError(domain: "hide-a-hole", code: 1, userInfo: [NSLocalizedDescriptionKey: "cursorRadius must be a number between 1 and 10000."])
        }
        return try Self.validateRadius(number.doubleValue)
    }

    func setCursorRadius(_ radius: Double) throws {
        let radius = try Self.validateRadius(radius)
        var object = try contents()
        _ = try cursorRadius()
        object["cursorRadius"] = radius
        try save(object)
    }

    func cursorColor() throws -> GradientColor { try color(in: contents()) }

    func setCursorColor(_ color: GradientColor) throws {
        var object = try contents()
        _ = try self.color(in: object)
        object.removeValue(forKey: "holeEnabled")
        object["cursorColor"] = color.hex
        try save(object)
    }

    private func save(_ object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
