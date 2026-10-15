import Foundation

/// Any JSON value, so a change record can carry an entity's fields without the engine
/// knowing the app's model types.
public enum JSONValue: Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public subscript(key: String) -> JSONValue? {
        if case .object(let dict) = self { return dict[key] }
        return nil
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var doubleValue: Double? {
        if case .number(let n) = self { return n }
        return nil
    }

    /// Converts any `Encodable` value (e.g. an entity's DTO) to JSON.
    public init<T: Encodable>(encoding value: T) throws {
        let data = try JSONEncoder.syncFields.encode(value)
        self = try JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// Converts back to a `Decodable` type.
    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let data = try JSONEncoder().encode(self)
        return try JSONDecoder.syncFields.decode(type, from: data)
    }
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? container.decode(Double.self) {
            self = .number(n)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let a = try? container.decode([JSONValue].self) {
            self = .array(a)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let b): try container.encode(b)
        case .number(let n): try container.encode(n)
        case .string(let s): try container.encode(s)
        case .array(let a): try container.encode(a)
        case .object(let o): try container.encode(o)
        }
    }
}

/// Sync dates are whole milliseconds since 1970, so they survive encode → decode exactly.
public enum SyncTime {
    public static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    public static func date(milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(milliseconds) / 1000)
    }

    /// `date` rounded to the millisecond, exactly as it will read back.
    public static func rounded(_ date: Date) -> Date {
        self.date(milliseconds: milliseconds(date))
    }
}

extension JSONEncoder {
    /// Dates as integer milliseconds since 1970, keys sorted for stable output.
    public static var syncFields: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(SyncTime.milliseconds(date))
        }
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }
}

extension JSONDecoder {
    public static var syncFields: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let ms = try? container.decode(Int64.self) { return SyncTime.date(milliseconds: ms) }
            return SyncTime.date(milliseconds: Int64((try container.decode(Double.self)).rounded()))
        }
        return d
    }
}
