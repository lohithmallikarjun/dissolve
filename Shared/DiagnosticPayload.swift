import Foundation

/// The Milestone 0 test file each device writes to `m0/<deviceID>.json`.
struct DiagnosticPayload: Codable, Sendable, Equatable {
    var deviceID: String
    var deviceName: String
    var platform: String
    var writtenAt: Date
    var appGroupValue: Int
}

extension JSONEncoder {
    static var sync: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys, .prettyPrinted]
        return e
    }
}

extension JSONDecoder {
    static var sync: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
