import Foundation

public enum JournalStats {
    /// Consecutive days with an entry, ending today (or yesterday while today is still unwritten).
    public static func streak(entryDates: Set<LocalDate>, today: LocalDate) -> Int {
        var day = entryDates.contains(today) ? today : today.adding(days: -1)
        var count = 0
        while entryDates.contains(day) {
            count += 1
            day = day.adding(days: -1)
        }
        return count
    }

    /// Runs of letters or digits (apostrophes and hyphens inside a word don't split it).
    public static func wordCount(_ text: String) -> Int {
        var count = 0
        var inWord = false
        var previous: Character?
        for ch in text {
            let isWordChar = ch.isLetter || ch.isNumber
                || ((ch == "'" || ch == "’" || ch == "-") && inWord && previous.map { $0.isLetter } == true)
            if isWordChar, !inWord { count += 1 }
            inWord = isWordChar
            previous = ch
        }
        return count
    }

    /// Entries from the same month and day in earlier years, newest first.
    public static func onThisDay(_ dates: [LocalDate], today: LocalDate) -> [LocalDate] {
        dates.filter { $0.month == today.month && $0.day == today.day && $0.year < today.year }
            .sorted(by: >)
    }
}
