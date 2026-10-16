import Foundation

/// A stable reference to any item in the app, used by links, search, quick capture and deep links.
public struct ItemRef: Hashable, Sendable, Codable, CustomStringConvertible {
    public var kind: String
    public var id: String

    public init(kind: String, id: String) {
        self.kind = kind
        self.id = id
    }

    public init(kind: String, id: UUID) {
        self.init(kind: kind, id: id.uuidString)
    }

    public static let scheme = "dissolve"

    /// `dissolve://item/<kind>/<id>`
    public var url: URL {
        URL(string: "\(Self.scheme)://item/\(Self.escape(kind))/\(Self.escape(id))")!
    }

    public init?(url: URL) {
        guard url.scheme == Self.scheme, url.host == "item",
              let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath else { return nil }
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count == 2,
              let kind = parts[0].removingPercentEncoding, let id = parts[1].removingPercentEncoding,
              !kind.isEmpty, !id.isEmpty else { return nil }
        self.init(kind: kind, id: id)
    }

    /// `kind:id`, as written inside `[[...]]`.
    public var description: String { "\(kind):\(id)" }

    private static func escape(_ s: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}

/// One `[[...]]` link in Markdown text.
public struct WikiLink: Hashable, Sendable {
    public enum Target: Hashable, Sendable {
        /// `[[Note title]]` or `[[Note title#Heading]]`.
        case note(title: String, heading: String?)
        /// `[[habit:UUID]]` — any app item.
        case item(ItemRef)
    }

    public let target: Target
    /// `[[target|alias]]` shows the alias.
    public let alias: String?
    /// Range in the source text.
    public let range: Range<String.Index>

    public var displayText: String {
        if let alias { return alias }
        switch target {
        case .note(let title, let heading): return heading.map { "\(title) › \($0)" } ?? title
        case .item(let ref): return ref.description
        }
    }
}

public enum WikiLinks {
    /// Item kinds that `[[kind:id]]` may name. Anything else is treated as a note title.
    public static let itemKinds: Set<String> = [
        "habit", "countdown", "goal", "wish", "task", "event", "journal", "note", "person",
        "document", "list", "book", "deck", "card", "expense", "subscription", "medicine",
    ]

    /// All links, skipping fenced code blocks (```), inline code (`...`) and escaped `\[[`.
    public static func parse(_ text: String) -> [WikiLink] {
        var links: [WikiLink] = []
        var i = text.startIndex
        var inFence = false
        var atLineStart = true
        while i < text.endIndex {
            let c = text[i]
            if atLineStart, text[i...].hasPrefix("```") {
                inFence.toggle()
                i = text[i...].firstIndex(of: "\n").map { text.index(after: $0) } ?? text.endIndex
                atLineStart = true
                continue
            }
            atLineStart = c == "\n"
            if inFence { i = text.index(after: i); continue }
            if c == "\\" {
                i = text.index(after: i)
                if i < text.endIndex { i = text.index(after: i) }
                continue
            }
            if c == "`" {
                let after = text.index(after: i)
                if let close = text[after...].firstIndex(where: { $0 == "`" || $0 == "\n" }), text[close] == "`" {
                    i = text.index(after: close)
                    continue
                }
            }
            if text[i...].hasPrefix("[["),
               let close = text[text.index(i, offsetBy: 2)...].range(of: "]]") {
                let inner = text[text.index(i, offsetBy: 2)..<close.lowerBound]
                if !inner.contains("\n"), !inner.contains("[["), let link = makeLink(String(inner), range: i..<close.upperBound) {
                    links.append(link)
                    i = close.upperBound
                    continue
                }
            }
            i = text.index(after: i)
        }
        return links
    }

    static func makeLink(_ inner: String, range: Range<String.Index>) -> WikiLink? {
        var body = inner
        var alias: String?
        if let bar = body.firstIndex(of: "|") {
            alias = String(body[body.index(after: bar)...]).trimmingCharacters(in: .whitespaces)
            body = String(body[..<bar])
            if alias?.isEmpty == true { alias = nil }
        }
        body = body.trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return nil }
        if let colon = body.firstIndex(of: ":") {
            let kind = String(body[..<colon]).lowercased()
            let id = String(body[body.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if itemKinds.contains(kind), !id.isEmpty {
                return WikiLink(target: .item(ItemRef(kind: kind, id: id)), alias: alias, range: range)
            }
        }
        var heading: String?
        if let hash = body.firstIndex(of: "#") {
            heading = String(body[body.index(after: hash)...]).trimmingCharacters(in: .whitespaces)
            body = String(body[..<hash]).trimmingCharacters(in: .whitespaces)
            if heading?.isEmpty == true { heading = nil }
            guard !body.isEmpty else { return nil }
        }
        return WikiLink(target: .note(title: body, heading: heading), alias: alias, range: range)
    }

    /// Titles compare case- and diacritic-insensitively, ignoring surrounding spaces.
    public static func normalize(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespaces)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Note titles each note links to.
    public static func outgoingTitles(_ text: String) -> [String] {
        var seen = Set<String>()
        return parse(text).compactMap {
            guard case .note(let title, _) = $0.target, seen.insert(normalize(title)).inserted else { return nil }
            return title
        }
    }

    /// Backlinks: for each note title, the notes that link to it. Unresolved links are returned separately.
    public static func backlinks<ID: Hashable>(_ notes: [(id: ID, title: String, text: String)])
        -> (backlinks: [ID: [ID]], unresolved: [ID: [String]]) {
        var byTitle: [String: ID] = [:]
        for note in notes where byTitle[normalize(note.title)] == nil { byTitle[normalize(note.title)] = note.id }
        var back: [ID: [ID]] = [:]
        var unresolved: [ID: [String]] = [:]
        for note in notes {
            for title in outgoingTitles(note.text) {
                if let target = byTitle[normalize(title)] {
                    if target != note.id { back[target, default: []].append(note.id) }
                } else {
                    unresolved[note.id, default: []].append(title)
                }
            }
        }
        return (back, unresolved)
    }

    /// Rewrites `[[Old]]` (and `[[Old#h]]`, `[[Old|alias]]`) to the new title after a rename.
    public static func renaming(_ text: String, from old: String, to new: String) -> String {
        let target = normalize(old)
        var result = ""
        var cursor = text.startIndex
        for link in parse(text) {
            guard case .note(let title, let heading) = link.target, normalize(title) == target else { continue }
            result += text[cursor..<link.range.lowerBound]
            result += "[[" + new + (heading.map { "#" + $0 } ?? "") + (link.alias.map { "|" + $0 } ?? "") + "]]"
            cursor = link.range.upperBound
        }
        result += text[cursor...]
        return result
    }
}

/// An undirected link between two items, stored once in a canonical order.
public struct ItemLink: Hashable, Sendable, Codable {
    public let a: ItemRef
    public let b: ItemRef

    public init(_ x: ItemRef, _ y: ItemRef) {
        if (x.kind, x.id) <= (y.kind, y.id) { (a, b) = (x, y) } else { (a, b) = (y, x) }
    }

    public func other(than ref: ItemRef) -> ItemRef? {
        ref == a ? b : ref == b ? a : nil
    }

    /// Stable id so two devices creating the same link merge into one record.
    public var key: String { "\(a)|\(b)" }

    public static func linked(to ref: ItemRef, in links: [ItemLink]) -> [ItemRef] {
        links.compactMap { $0.other(than: ref) }
    }
}
