import Foundation

/// Money in minor units (paise for ₹), so sums never drift.
public struct Money: Hashable, Comparable, Sendable, Codable {
    public var minor: Int

    public init(minor: Int) { self.minor = minor }
    public init(rupees: Int, paise: Int = 0) { self.minor = rupees * 100 + paise }

    /// Parses "1,23,456.78", "₹ 499", "1200.5". Nil for anything else.
    public init?(parsing text: String) {
        var s = text.trimmingCharacters(in: .whitespaces)
        for token in ["₹", "Rs.", "Rs", "INR"] { s = s.replacingOccurrences(of: token, with: "") }
        s = s.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        var negative = false
        if s.hasPrefix("-") { negative = true; s.removeFirst() }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), let whole = Int(parts[0]), whole >= 0 else { return nil }
        var paise = 0
        if parts.count == 2 {
            let frac = parts[1]
            guard (1...2).contains(frac.count), frac.allSatisfy(\.isNumber), let f = Int(frac) else { return nil }
            paise = frac.count == 1 ? f * 10 : f
        }
        minor = (whole * 100 + paise) * (negative ? -1 : 1)
    }

    public static let zero = Money(minor: 0)
    public static func + (a: Money, b: Money) -> Money { Money(minor: a.minor + b.minor) }
    public static func - (a: Money, b: Money) -> Money { Money(minor: a.minor - b.minor) }
    public static func < (a: Money, b: Money) -> Bool { a.minor < b.minor }

    /// Indian grouping: ₹1,23,456.78 (paise dropped when zero unless `alwaysPaise`).
    public func formattedINR(alwaysPaise: Bool = false) -> String {
        let negative = minor < 0
        let absMinor = abs(minor)
        let digits = String(absMinor / 100)
        var grouped = ""
        if digits.count <= 3 {
            grouped = digits
        } else {
            let last3 = digits.suffix(3)
            var head = Array(digits.dropLast(3))
            var chunks: [String] = []
            while head.count > 2 {
                chunks.insert(String(head.suffix(2)), at: 0)
                head.removeLast(2)
            }
            if !head.isEmpty { chunks.insert(String(head), at: 0) }
            grouped = chunks.joined(separator: ",") + "," + last3
        }
        let paise = absMinor % 100
        let tail = (paise != 0 || alwaysPaise) ? "." + (paise < 10 ? "0" : "") + String(paise) : ""
        return (negative ? "-" : "") + "₹" + grouped + tail
    }
}

public struct ExpenseItem: Hashable, Sendable {
    public var amount: Money
    public var category: String
    public var date: LocalDate

    public init(amount: Money, category: String, date: LocalDate) {
        self.amount = amount
        self.category = category
        self.date = date
    }
}

public struct BudgetStatus: Equatable, Sendable {
    public let category: String
    public let limit: Money
    public let spent: Money
    public var remaining: Money { limit - spent }
    public var fraction: Double { limit.minor > 0 ? Double(spent.minor) / Double(limit.minor) : 0 }
    public var isOver: Bool { spent > limit }
    /// Spend at the current pace by month end.
    public let projected: Money
    public var onPace: Bool { projected <= limit }
}

public enum BudgetMath {
    public static func spentByCategory(_ expenses: [ExpenseItem], month: String) -> [String: Money] {
        expenses.filter { $0.date.monthKey == month }
            .reduce(into: [:]) { $0[$1.category, default: .zero] = $0[$1.category, default: .zero] + $1.amount }
    }

    public static func total(_ expenses: [ExpenseItem], month: String) -> Money {
        expenses.filter { $0.date.monthKey == month }.reduce(.zero) { $0 + $1.amount }
    }

    /// Status of each budget for the month containing `today`.
    public static func status(budgets: [String: Money], expenses: [ExpenseItem], today: LocalDate) -> [BudgetStatus] {
        let spent = spentByCategory(expenses, month: today.monthKey)
        let daysInMonth = LocalDate.daysInMonth(year: today.year, month: today.month)
        return budgets.keys.sorted().map { category in
            let s = spent[category] ?? .zero
            let projected = Money(minor: Int((Double(s.minor) * Double(daysInMonth) / Double(today.day)).rounded()))
            return BudgetStatus(category: category, limit: budgets[category]!, spent: s, projected: projected)
        }
    }
}

// MARK: Subscriptions

public enum BillingCycle: Hashable, Sendable, Codable {
    case weekly
    case months(Int)
    case yearly

    public static let monthly = BillingCycle.months(1)
}

public struct SubscriptionPlan: Hashable, Sendable {
    public var amount: Money
    public var cycle: BillingCycle
    /// The first billing date; renewals repeat from it.
    public var start: LocalDate

    public init(amount: Money, cycle: BillingCycle, start: LocalDate) {
        self.amount = amount
        self.cycle = cycle
        self.start = start
    }

    /// The n-th renewal (0 = start). Month-based cycles clamp to the month's last day,
    /// so a plan started on the 31st renews on Feb 28/29.
    public func renewal(_ n: Int) -> LocalDate {
        switch cycle {
        case .weekly: return start.adding(days: 7 * n)
        case .months(let m): return Self.addMonths(start, max(m, 1) * n)
        case .yearly: return Self.addMonths(start, 12 * n)
        }
    }

    /// The first renewal on or after `date`.
    public func nextRenewal(onOrAfter date: LocalDate) -> LocalDate {
        guard date > start else { return start }
        // Estimate, then step forward.
        let approxDays: Double = switch cycle {
        case .weekly: 7
        case .months(let m): 30.44 * Double(max(m, 1))
        case .yearly: 365.25
        }
        var n = max(0, Int(Double(start.days(to: date)) / approxDays) - 1)
        while renewal(n) < date { n += 1 }
        return renewal(n)
    }

    public var monthlyEquivalent: Money {
        let m: Double = switch cycle {
        case .weekly: 52.0 / 12.0
        case .months(let n): 1.0 / Double(max(n, 1))
        case .yearly: 1.0 / 12.0
        }
        return Money(minor: Int((Double(amount.minor) * m).rounded()))
    }

    public var yearlyEquivalent: Money {
        let y: Double = switch cycle {
        case .weekly: 52
        case .months(let n): 12.0 / Double(max(n, 1))
        case .yearly: 1
        }
        return Money(minor: Int((Double(amount.minor) * y).rounded()))
    }

    static func addMonths(_ date: LocalDate, _ months: Int) -> LocalDate {
        let total = date.year * 12 + (date.month - 1) + months
        let year = total / 12, month = total % 12 + 1
        let day = min(date.day, LocalDate.daysInMonth(year: year, month: month))
        return LocalDate(year: year, month: month, day: day)!
    }
}

// MARK: CSV import

public enum CSV {
    /// RFC 4180-ish: quoted fields, "" escapes, CRLF or LF, a custom delimiter.
    public static func parse(_ text: String, delimiter: Character = ",") -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = Array(text).makeIterator()
        var pending: Character? = nil
        while let c = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if c == "\"" {
                    if let n = iterator.next() {
                        if n == "\"" { field.append("\"") } else { inQuotes = false; pending = n }
                    } else { inQuotes = false }
                } else {
                    field.append(c)
                }
            } else if c == "\"" && field.isEmpty {
                inQuotes = true
            } else if c == delimiter {
                row.append(field); field = ""
            } else if c == "\n" || c == "\r\n" || c == "\r" {
                row.append(field); field = ""
                rows.append(row); row = []
            } else {
                field.append(c)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows.filter { !($0.count == 1 && $0[0].isEmpty) }
    }

    /// Which column holds what, chosen on the column-mapping screen.
    public struct Mapping: Hashable, Sendable {
        public var date: Int
        public var amount: Int?
        /// Banks often split money out / in; debits become expenses.
        public var debit: Int?
        public var description: Int?
        public var dateFormat: DateFormat
        public var skipHeader: Bool

        public enum DateFormat: String, Sendable, CaseIterable { case dmy, mdy, ymd }

        public init(date: Int, amount: Int? = nil, debit: Int? = nil, description: Int? = nil,
                    dateFormat: DateFormat = .dmy, skipHeader: Bool = true) {
            self.date = date
            self.amount = amount
            self.debit = debit
            self.description = description
            self.dateFormat = dateFormat
            self.skipHeader = skipHeader
        }
    }

    public struct ImportedRow: Hashable, Sendable {
        public let date: LocalDate
        public let amount: Money
        public let description: String
    }

    /// Rows that parse; the rest are counted so the screen can say "3 rows skipped".
    public static func importRows(_ rows: [[String]], mapping: Mapping) -> (rows: [ImportedRow], skipped: Int) {
        var out: [ImportedRow] = []
        var skipped = 0
        for (i, row) in rows.enumerated() {
            if i == 0 && mapping.skipHeader { continue }
            func cell(_ index: Int?) -> String? {
                guard let index, index < row.count else { return nil }
                let v = row[index].trimmingCharacters(in: .whitespaces)
                return v.isEmpty ? nil : v
            }
            guard let dateText = cell(mapping.date), let date = parseDate(dateText, mapping.dateFormat),
                  let amountText = cell(mapping.debit) ?? cell(mapping.amount),
                  let amount = Money(parsing: amountText) else {
                skipped += 1
                continue
            }
            out.append(ImportedRow(date: date, amount: Money(minor: abs(amount.minor)),
                                   description: cell(mapping.description) ?? ""))
        }
        return (out, skipped)
    }

    static func parseDate(_ text: String, _ format: Mapping.DateFormat) -> LocalDate? {
        let parts = text.split(whereSeparator: { "/-. ".contains($0) }).compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let (y0, m, d): (Int, Int, Int) = switch format {
        case .dmy: (parts[2], parts[1], parts[0])
        case .mdy: (parts[2], parts[0], parts[1])
        case .ymd: (parts[0], parts[1], parts[2])
        }
        return LocalDate(year: y0 < 100 ? y0 + 2000 : y0, month: m, day: d)
    }
}
