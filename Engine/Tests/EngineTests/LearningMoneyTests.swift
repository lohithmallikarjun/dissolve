import Foundation
import Testing
@testable import Engine

@Suite("Spaced repetition")
struct SpacedRepetitionTests {
    let day = LocalDate("2026-10-16")!

    @Test func goodReviewsGrowIntervals() {
        var card = CardSchedule.new(on: day)
        #expect(card.isDue(on: day))
        card = SM2.review(card, grade: .good, on: day)
        #expect(card.intervalDays == 1 && card.due == day.adding(days: 1))
        card = SM2.review(card, grade: .good, on: card.due)
        #expect(card.intervalDays == 6)
        card = SM2.review(card, grade: .good, on: card.due)
        #expect(card.intervalDays == 15)  // 6 × 2.5
        #expect(card.ease == 2.5)
    }

    @Test func againResetsAndCountsLapse() {
        var card = CardSchedule.new(on: day)
        for _ in 0..<3 { card = SM2.review(card, grade: .good, on: card.due) }
        card = SM2.review(card, grade: .again, on: card.due)
        #expect(card.repetitions == 0 && card.intervalDays == 1 && card.lapses == 1)
        #expect(card.ease < 2.5)
    }

    @Test func easeNeverBelowMinimum() {
        var card = CardSchedule.new(on: day)
        for _ in 0..<20 { card = SM2.review(card, grade: .again, on: day) }
        #expect(card.ease == SM2.minimumEase)
        #expect(card.lapses == 0)  // never learned, so no lapses
    }

    @Test func hardGrowsSlowerThanGoodAndEasyFaster() {
        var base = CardSchedule.new(on: day)
        for _ in 0..<2 { base = SM2.review(base, grade: .good, on: base.due) }
        let hard = SM2.review(base, grade: .hard, on: base.due)
        let good = SM2.review(base, grade: .good, on: base.due)
        let easy = SM2.review(base, grade: .easy, on: base.due)
        #expect(hard.intervalDays < good.intervalDays && good.intervalDays < easy.intervalDays)
        #expect(hard.intervalDays > base.intervalDays)
    }

    @Test func dueQueueAndForecast() {
        let cards: [(id: Int, schedule: CardSchedule)] = [
            (1, CardSchedule(due: day.adding(days: -2))),
            (2, CardSchedule(due: day)),
            (3, CardSchedule(due: day.adding(days: 3))),
        ]
        #expect(SM2.dueQueue(cards, on: day) == [1, 2])
        #expect(SM2.dueQueue(cards, on: day, limit: 1) == [1])
        #expect(SM2.forecast(cards.map(\.schedule), from: day, days: 5) == [2, 0, 0, 1, 0])
    }
}

@Suite("Money")
struct MoneyTests {
    private func d(_ s: String) -> LocalDate { LocalDate(s)! }

    @Test func indianGrouping() {
        #expect(Money(rupees: 123456, paise: 78).formattedINR() == "₹1,23,456.78")
        #expect(Money(rupees: 999).formattedINR() == "₹999")
        #expect(Money(rupees: 1000).formattedINR() == "₹1,000")
        #expect(Money(rupees: 10_000_000).formattedINR() == "₹1,00,00,000")
        #expect(Money(minor: -505).formattedINR() == "-₹5.05")
        #expect(Money(rupees: 5).formattedINR(alwaysPaise: true) == "₹5.00")
    }

    @Test func parsing() {
        #expect(Money(parsing: "₹ 1,23,456.78") == Money(rupees: 123456, paise: 78))
        #expect(Money(parsing: "1200.5") == Money(rupees: 1200, paise: 50))
        #expect(Money(parsing: "Rs. 499") == Money(rupees: 499))
        #expect(Money(parsing: "-20") == Money(minor: -2000))
        #expect(Money(parsing: "abc") == nil)
        #expect(Money(parsing: "1.234") == nil)
    }

    @Test func budgetsAndPace() {
        let expenses = [
            ExpenseItem(amount: Money(rupees: 3000), category: "Food", date: d("2026-10-02")),
            ExpenseItem(amount: Money(rupees: 2000), category: "Food", date: d("2026-10-10")),
            ExpenseItem(amount: Money(rupees: 900), category: "Travel", date: d("2026-10-11")),
            ExpenseItem(amount: Money(rupees: 9999), category: "Food", date: d("2026-09-30")),
        ]
        let today = d("2026-10-15")
        #expect(BudgetMath.total(expenses, month: "2026-10") == Money(rupees: 5900))
        let status = BudgetMath.status(budgets: ["Food": Money(rupees: 8000), "Travel": Money(rupees: 2000)],
                                       expenses: expenses, today: today)
        let food = status.first { $0.category == "Food" }!
        #expect(food.spent == Money(rupees: 5000) && food.remaining == Money(rupees: 3000) && !food.isOver)
        // 5000 over 15 days → ~10,333 by Oct 31: over pace.
        #expect(food.projected == Money(minor: 1_033_333) && !food.onPace)
        #expect(status.first { $0.category == "Travel" }!.onPace)
    }

    @Test func subscriptionRenewals() {
        let monthly = SubscriptionPlan(amount: Money(rupees: 199), cycle: .monthly, start: d("2026-01-31"))
        #expect(monthly.renewal(1) == d("2026-02-28"))
        #expect(monthly.renewal(2) == d("2026-03-31"))
        #expect(monthly.nextRenewal(onOrAfter: d("2026-10-16")) == d("2026-10-31"))
        #expect(monthly.nextRenewal(onOrAfter: d("2025-12-01")) == d("2026-01-31"))
        #expect(monthly.yearlyEquivalent == Money(rupees: 2388))

        let yearly = SubscriptionPlan(amount: Money(rupees: 1200), cycle: .yearly, start: d("2024-02-29"))
        #expect(yearly.nextRenewal(onOrAfter: d("2026-03-01")) == d("2027-02-28"))
        #expect(yearly.monthlyEquivalent == Money(rupees: 100))

        let weekly = SubscriptionPlan(amount: Money(rupees: 10), cycle: .weekly, start: d("2026-10-01"))
        #expect(weekly.nextRenewal(onOrAfter: d("2026-10-09")) == d("2026-10-15"))
        #expect(weekly.nextRenewal(onOrAfter: d("2026-10-15")) == d("2026-10-15"))
    }

    @Test func csvParsing() {
        let text = "Date,Narration,Debit,Credit\r\n01/10/2026,\"Swiggy, order\",\"1,250.00\",\n02/10/2026,\"He said \"\"hi\"\"\",,500\n"
        let rows = CSV.parse(text)
        #expect(rows.count == 3)
        #expect(rows[1] == ["01/10/2026", "Swiggy, order", "1,250.00", ""])
        #expect(rows[2][1] == "He said \"hi\"")
        let result = CSV.importRows(rows, mapping: CSV.Mapping(date: 0, debit: 2, description: 1))
        #expect(result.rows == [CSV.ImportedRow(date: d("2026-10-01"), amount: Money(rupees: 1250), description: "Swiggy, order")])
        #expect(result.skipped == 1)  // credit-only row
    }

    @Test func csvDateFormats() {
        #expect(CSV.parseDate("2026-10-05", .ymd) == d("2026-10-05"))
        #expect(CSV.parseDate("10/05/26", .mdy) == d("2026-10-05"))
        #expect(CSV.parseDate("31.02.2026", .dmy) == nil)
    }
}
