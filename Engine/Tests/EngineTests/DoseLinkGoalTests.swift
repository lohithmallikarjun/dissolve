import Foundation
import Testing
@testable import Engine

@Suite("Doses")
struct DoseTests {
    private func d(_ s: String) -> LocalDate { LocalDate(s)! }

    @Test func slotsAndNext() {
        let rule = DoseRule(times: [20 * 60, 8 * 60], start: d("2026-10-01"))
        let today = d("2026-10-16")
        #expect(rule.slots(on: today).map(\.minutes) == [480, 1200])
        let logged = [DoseSlot(date: today, minutes: 480).key: DoseOutcome.taken]
        #expect(DoseMath.next(rule, logged: logged, from: today, nowMinutes: 9 * 60) == DoseSlot(date: today, minutes: 1200))
        // Untaken morning dose stays due for the 2-hour grace window, then drops off.
        #expect(DoseMath.next(rule, logged: [:], from: today, nowMinutes: 9 * 60)?.minutes == 480)
        #expect(DoseMath.next(rule, logged: [:], from: today, nowMinutes: 11 * 60)?.minutes == 1200)
    }

    @Test func weekdayAndEveryNDays() {
        let weekly = DoseRule(times: [540], days: .weekdays([2]), start: d("2026-10-01"))  // Mondays
        #expect(weekly.isDue(on: d("2026-10-19")) && !weekly.isDue(on: d("2026-10-20")))
        let alt = DoseRule(times: [540], days: .everyNDays(2), start: d("2026-10-01"), end: d("2026-10-10"))
        #expect(alt.isDue(on: d("2026-10-03")) && !alt.isDue(on: d("2026-10-04")) && !alt.isDue(on: d("2026-10-11")))
        #expect(DoseRule(times: [], start: d("2026-10-01")).slots(on: d("2026-10-02")).isEmpty)
    }

    @Test func adherence() {
        let rule = DoseRule(times: [480, 1200], start: d("2026-10-14"))
        let taken: [String: DoseOutcome] = [
            "2026-10-14T480": .taken, "2026-10-14T1200": .taken,
            "2026-10-15T480": .skipped, "2026-10-15T1200": .taken,
            "2026-10-16T480": .taken,
        ]
        // 14th ×2, 15th ×2, 16th morning only (evening not yet): 4 of 5 taken.
        #expect(DoseMath.adherence(rule, logged: taken, from: d("2026-10-01"), today: d("2026-10-16"), nowMinutes: 600) == 0.8)
    }

    @Test func refill() {
        let rule = DoseRule(times: [480, 1200], start: d("2026-10-01"), unitsPerDose: 1)
        let refill = DoseMath.refill(rule, unitsLeft: 21, today: d("2026-10-16"))!
        #expect(refill.daysLeft == 10 && refill.runsOut == d("2026-10-26") && refill.remindOn == d("2026-10-19"))
        #expect(DoseMath.refill(DoseRule(times: [], start: d("2026-10-01")), unitsLeft: 10, today: d("2026-10-16")) == nil)
    }
}

@Suite("Links")
struct LinkTests {
    @Test func itemRefURLRoundTrip() {
        let ref = ItemRef(kind: "habit", id: UUID(uuidString: "6F1C8D0E-0000-4000-8000-000000000001")!)
        #expect(ref.url.absoluteString == "dissolve://item/habit/6F1C8D0E-0000-4000-8000-000000000001")
        #expect(ItemRef(url: ref.url) == ref)
        let odd = ItemRef(kind: "note", id: "Work/Plan 100%")
        #expect(ItemRef(url: odd.url) == odd)
        #expect(ItemRef(url: URL(string: "dissolve://item/habit")!) == nil)
        #expect(ItemRef(url: URL(string: "https://item/habit/1")!) == nil)
    }

    @Test func parsesLinkForms() {
        let text = "See [[Plan]], [[Plan#Week 2|this week]] and [[habit:ABC]]. Not [[ ]] or [[a\nb]]."
        let links = WikiLinks.parse(text)
        #expect(links.map(\.target) == [
            .note(title: "Plan", heading: nil),
            .note(title: "Plan", heading: "Week 2"),
            .item(ItemRef(kind: "habit", id: "ABC")),
        ])
        #expect(links[1].displayText == "this week")
        #expect(String(text[links[0].range]) == "[[Plan]]")
    }

    @Test func ignoresCodeAndEscapes() {
        let text = "`[[inline]]` \\[[escaped]] [[real]]\n```\n[[fenced]]\n```\n[[after]]"
        #expect(WikiLinks.outgoingTitles(text) == ["real", "after"])
    }

    @Test func colonInTitleIsANote() {
        #expect(WikiLinks.parse("[[Re: meeting]]").first?.target == .note(title: "Re: meeting", heading: nil))
    }

    @Test func backlinksAndUnresolved() {
        let notes: [(id: Int, title: String, text: String)] = [
            (1, "Plan", "Links to [[Ideas]] and [[ideas]] and [[Missing]]"),
            (2, "Ideas", "Back to [[plan]], self [[Ideas]]"),
            (3, "Café", "[[Plan]]"),
            (4, "Other", "[[cafe]]"),
        ]
        let result = WikiLinks.backlinks(notes)
        #expect(result.backlinks[2] == [1])
        #expect(result.backlinks[1] == [2, 3])
        #expect(result.backlinks[3] == [4])
        #expect(result.unresolved[1] == ["Missing"])
    }

    @Test func rename() {
        let text = "[[Old]] and [[old#H|alias]] but not [[Older]]"
        #expect(WikiLinks.renaming(text, from: "Old", to: "New") == "[[New]] and [[New#H|alias]] but not [[Older]]")
    }

    @Test func itemLinkIsCanonical() {
        let a = ItemRef(kind: "habit", id: "1"), b = ItemRef(kind: "goal", id: "2")
        #expect(ItemLink(a, b) == ItemLink(b, a))
        #expect(ItemLink(a, b).key == "goal:2|habit:1")
        #expect(ItemLink.linked(to: a, in: [ItemLink(a, b), ItemLink(b, ItemRef(kind: "wish", id: "3"))]) == [b])
    }
}

@Suite("Goals")
struct GoalTests {
    @Test func rollsUpFromSourcesAndChildren() {
        let q1 = GoalNode(sources: [.habitStrength(0.8), .tasks(done: 1, total: 4)])  // 0.525
        let q2 = GoalNode(sources: [.keyResult(start: 80, current: 76, target: 72)])  // weight down: 0.5
        let year = GoalNode(children: [q1, q2])
        #expect(abs(q1.progress! - 0.525) < 1e-9)
        #expect(q2.progress == 0.5)
        #expect(abs(year.progress! - 0.5125) < 1e-9)
        #expect(GoalNode(sources: [.tasks(done: 0, total: 0)]).progress == nil)
    }

    @Test func onTrack() {
        let goal = GoalNode(sources: [.manual(0.3)])
        let start = LocalDate("2026-10-01")!, end = LocalDate("2026-12-31")!
        #expect(goal.isOnTrack(periodStart: start, periodEnd: end, today: LocalDate("2026-10-31")!) == true)
        #expect(goal.isOnTrack(periodStart: start, periodEnd: end, today: LocalDate("2026-12-15")!) == false)
    }
}
