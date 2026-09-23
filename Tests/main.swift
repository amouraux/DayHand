import Foundation

var failures = 0, checks = 0
func expect(_ ok: @autoclosure () -> Bool, _ what: String) {
    checks += 1
    if !ok() { failures += 1; print("FAIL: \(what)") }
}

// MARK: A — reading a #word while typing
do {
    let t = ProjectToken.find(in: "#lk")
    expect(t == ProjectToken(query: "lk", isFinished: false, remainder: ""), "#lk is a query in progress")
    expect(ProjectToken.find(in: "#")?.query == "", "a bare # shows all projects")
    expect(ProjectToken.find(in: "#lk ")?.isFinished == true, "a space finishes it")
    expect(ProjectToken.find(in: "exam #lk")?.remainder == "exam", "a #word at the end keeps the title before it")
    expect(ProjectToken.find(in: "exam questions") == nil, "no # means no project")
    expect(ProjectToken.find(in: "# ") == nil, "hash-space is not a project")
    expect(ProjectToken.find(in: "#lk  ") == nil, "two spaces: finished long ago, not re-taken")
    expect(ProjectToken.find(in: "use C#") == nil, "a # inside a word is not a project")
    expect(ProjectToken.find(in: "\u{FF03}lk")?.query == "lk", "full-width # from a CJK keyboard works")
}

// MARK: B — names
do {
    expect(Project.clean("#STUDY2026:") == "STUDY2026", "leading # and trailing colon stripped")
    expect(Project.clean("(ALPHA)") == "ALPHA", "brackets stripped")
    expect(Project.key(for: "study2026") == Project.key(for: "#STUDY2026"), "case and # ignored when matching")
    expect(Project.key(for: "Résumé") == Project.key(for: "resume"), "accents ignored when matching")
    expect(Project.clean("  ") == "", "blank is no name")
}

// MARK: C — ranking suggestions
do {
    let lk = Project(name: "ABC1234"), lp = Project(name: "DEF5678"), sf = Project(name: "STUDY2026")
    let blk = Project(name: "XABC"), old = Project(name: "ABCOLD", isArchived: true)
    let all = [lk, lp, sf, blk, old]
    let used: [UUID: Date] = [lp.id: Date(), lk.id: Date(timeIntervalSinceNow: -3600), sf.id: Date(timeIntervalSinceNow: -60)]

    let r = ProjectSuggestions.rank(all, query: "abc", lastUsed: used)
    expect(r.map(\.name) == ["ABC1234", "XABC"], "prefix match first, then contains; archived never — got \(r.map(\.name))")
    let recent = ProjectSuggestions.rank(all, query: "", lastUsed: used, limit: 2)
    expect(recent.map(\.name) == ["DEF5678", "STUDY2026"], "empty query = most recent first — got \(recent.map(\.name))")
    expect(ProjectSuggestions.rank(all, query: "ABC", lastUsed: used).first?.name == "ABC1234", "case-insensitive")
}

// MARK: D — turning title prefixes into projects
do {
    // Titles in the shape people actually write them: codes, and ordinary
    // words that merely start a sentence.
    func card(_ title: String, _ category: UUID? = nil) -> TodoItem {
        TodoItem(title: title, categoryID: category)
    }
    let teaching = UUID(), research = UUID()
    let cards = [
        card("ABC1234 slides", teaching), card("ABC1234 Moodle", teaching), card("ABC1234 exam", research),
        card("STUDY2026 kickoff", research), card("STUDY2026 report", research),
        card("STUDY revise manuscript", research),
        card("NF calibration", research), card("NF Heidelberg", research),
        card("Pay the roofer"), card("Pay the plumber"), card("Pay the vet"),
        card("Email the dean"), card("Email the lab"),
        card("Onur PhD admission", research),
        card("SOLO", research),
    ]

    let found = ProjectConversion.candidates(cards: cards, existing: [])
    let byName = Dictionary(uniqueKeysWithValues: found.map { ($0.name, $0) })

    expect(byName["ABC1234"]?.cardIDs.count == 3, "a code takes every card that starts with it, across categories")
    expect(byName["ABC1234"]?.looksLikeCode == true, "a code is offered ticked")
    expect(byName["NF"]?.looksLikeCode == true, "two capitals count as a code")
    expect(byName["Pay"]?.looksLikeCode == false, "a verb is offered unticked")
    expect(byName["Email"]?.looksLikeCode == false, "so is Email")
    expect(byName["Onur"] == nil, "a word used once, and not code-like, is not offered at all")
    expect(byName["SOLO"] == nil, "a one-word title is never offered: nothing would be left of it")
    expect(byName["STUDY"]?.similar.contains("STUDY2026") == true
           || byName["STUDY2026"]?.similar.contains("STUDY") == true,
           "near-duplicate codes are flagged for merging")

    expect(ProjectConversion.split("ABC1234 - slides")?.rest == "slides", "a dash after the code is dropped")
    expect(ProjectConversion.split("ABC1234: slides")?.word == "ABC1234", "so is a colon")
    expect(ProjectConversion.split("SOLO") == nil, "a one-word title is never emptied")
    expect(ProjectConversion.looksLikeCode("NF") && ProjectConversion.looksLikeCode("ABC1234"), "NF and ABC1234 are codes")
    expect(!ProjectConversion.looksLikeCode("Payer") && !ProjectConversion.looksLikeCode("A"), "Payer and A are not")
}

// Optional: point the suite at a real data file to check it still decodes.
if CommandLine.arguments.count > 1 {
    let data = try! Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
    let doc = try! DocumentCoding.makeDecoder().decode(StoreDocument.self, from: data)
    expect(!doc.cards.isEmpty, "the file given on the command line decodes and holds cards")
}

// MARK: E — the file format
let enc = DocumentCoding.makeEncoder(), dec = DocumentCoding.makeDecoder()
func roundTrip(_ d: StoreDocument) -> StoreDocument { try! dec.decode(StoreDocument.self, from: try! enc.encode(d)) }
do {
    let p = Project(name: "ABC1234", categoryID: UUID())
    var card = TodoItem(title: "slides"); card.projectID = p.id
    let d = StoreDocument(cards: [card], projects: [p])
    expect(roundTrip(d) == d, "projects and card links survive save and load unchanged")

    let old = #"{"cards":[{"id":"\#(UUID().uuidString)","title":"x","bucket":"inbox"}],"categories":[]}"#
    let o = try! dec.decode(StoreDocument.self, from: Data(old.utf8))
    expect(o.projects.isEmpty && o.cards[0].projectID == nil, "a file from before projects still loads")
}

// MARK: F — two devices
do {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    var a = StoreDocument(), b = StoreDocument()
    let shared = Project(name: "ALPHA", modifiedAt: t0)
    a.projects = [shared]; b.projects = [shared]
    var renamed = shared; renamed.name = "ALPHA2"; renamed.modifiedAt = t0.addingTimeInterval(10)
    b.projects = [renamed]
    let onlyA = Project(name: "NF", modifiedAt: t0)
    a.projects.append(onlyA)

    let m1 = a.merged(with: b), m2 = b.merged(with: a)
    expect(m1.projects.first { $0.id == shared.id }?.name == "ALPHA2", "the later rename wins")
    expect(Set(m1.projects.map(\.id)) == Set(m2.projects.map(\.id)), "merge is order-independent")
    expect(m1.projects.contains { $0.id == onlyA.id }, "a project made on one device reaches the other")

    var deleted = a; deleted.projects.removeAll { $0.id == onlyA.id }
    deleted.deletedProjects[onlyA.id.uuidString] = t0.addingTimeInterval(20)
    expect(!deleted.merged(with: a).projects.contains { $0.id == onlyA.id }, "a deletion is not undone by the other device")
}

// MARK: G — the same project created on both devices while offline
do {
    let t0 = Date(timeIntervalSince1970: 2_000_000)
    let phone = Project(name: "NEWCODE", modifiedAt: t0)
    let mac = Project(name: "newcode", modifiedAt: t0.addingTimeInterval(5))
    var c1 = TodoItem(title: "from phone"); c1.projectID = phone.id
    var c2 = TodoItem(title: "from mac"); c2.projectID = mac.id
    let a = StoreDocument(cards: [c1], projects: [phone])
    let b = StoreDocument(cards: [c2], projects: [mac])

    let fromA = a.merged(with: b).canonicalizingProjects()
    let fromB = b.merged(with: a).canonicalizingProjects()
    expect(fromA.projects.count == 1, "the two become one")
    let survivor = [phone, mac].min { $0.id.uuidString < $1.id.uuidString }!
    expect(fromA.projects[0].id == survivor.id, "the lowest id survives")
    expect(fromA.cards.allSatisfy { $0.projectID == survivor.id }, "both cards now point at it")
    expect(Set(fromA.projects.map(\.id)) == Set(fromB.projects.map(\.id)) && fromA.deletedProjects == fromB.deletedProjects,
           "both devices pick the same survivor and write the same tombstone")
    expect(fromA.cards.allSatisfy { $0.modifiedAt == c1.modifiedAt || $0.modifiedAt == c2.modifiedAt },
           "cards moved across are not stamped as edited")

    // A device that has not caught up still holds the loser: the tombstone removes it.
    let stale = b
    let again = fromA.merged(with: stale).canonicalizingProjects()
    expect(again.projects.map(\.id) == [survivor.id], "a stale copy cannot bring the duplicate back")
    expect(again.canonicalizingProjects() == again, "folding is stable")
}

// MARK: H — CSV
do {
    let cat = CardCategory(label: "Teaching", symbolName: "graduationcap", color: .purple)
    let p = Project(name: "ABC1234", categoryID: cat.id)
    var card = TodoItem(title: "slides, part 2", categoryID: cat.id); card.projectID = p.id
    let text = CardCSV.export(cards: [card], categories: [cat], projects: [p])
    expect(text.hasPrefix("id,title,stack,category,due,completed,created,project,group\n"), "project, then group, written last")
    let back = CardCSV.parse(text, categories: [cat])
    expect(back.cards.first?.title == "slides, part 2", "title round-trips")
    expect(back.projectNames[card.id] == "ABC1234", "project round-trips by name")

    let hashTitle = CardCSV.parse("title,category\n#ABC1234 exam questions,Teaching\n", categories: [cat])
    expect(hashTitle.cards.first?.title == "exam questions", "#CODE at the start of an imported title is lifted off")
    expect(hashTitle.projectNames.values.first == "ABC1234", "and becomes the project")

    let course = CardCSV.parse("Task,Course\nslides,DEF5678\n", categories: [])
    expect(course.projectNames.values.first == "DEF5678", "a 'Course' column is read as the project")
    let tagged = CardCSV.parse("title,tag\nslides,Teaching\n", categories: [cat])
    expect(tagged.cards.first?.categoryID == cat.id && tagged.projectNames.isEmpty, "'tag' still means category, as before")

    let headerless = "\(UUID().uuidString),old card,today,Teaching,,,\n"
    let old = CardCSV.parse(headerless, categories: [cat])
    expect(old.cards.first?.title == "old card" && old.cards.first?.bucket == .today && old.cards.first?.categoryID == cat.id,
           "an old export with no header still reads by position")
}


// MARK: I — groups of projects
do {
    let research = UUID(), teaching = UUID()
    expect(Project.cleanGroup("  Bachelor   courses ") == "Bachelor courses", "a group may be several words, tidied")
    expect(Project.cleanGroup("   ") == nil, "a blank group is no group")
    expect(Project.groupKey(for: "grants") == Project.groupKey(for: "Grants"), "group names match without regard to case")

    let a = Project(name: "BETA", categoryID: research, group: "Grants")
    let b = Project(name: "ALPHA", categoryID: research, group: "grants")      // a variant spelling
    let c = Project(name: "GAMMA", categoryID: research, group: "Ongoing")
    let d = Project(name: "DELTA", categoryID: research)
    let e = Project(name: "ABC1234", categoryID: teaching, group: "Bachelor")
    let all = [a, b, c, d, e]

    let layout = ProjectGroups.layout(of: all.filter { $0.categoryID == research })
    expect(layout.groups.map(\.name) == ["Grants", "Ongoing"], "groups alphabetical, one per name — got \(layout.groups.map(\.name))")
    expect(layout.groups.first?.projects.map(\.name) == ["ALPHA", "BETA"], "a variant spelling joins the group; projects alphabetical")
    expect(layout.ungrouped.map(\.name) == ["DELTA"], "a project in no group stays loose")
    expect(ProjectGroups.names(in: teaching, projects: all) == ["Bachelor"], "groups belong to their category")
    expect(ProjectGroups.existingName(for: "ONGOING", in: research, projects: all) == "Ongoing", "choosing an existing group keeps its spelling")
    expect(ProjectGroups.existingName(for: "Ongoing", in: teaching, projects: all) == nil, "another category's group is not reused")
    expect(ProjectGroups.layout(of: []).groups.isEmpty, "no projects, no groups: nothing lingers")

    // File format: an old project has no group; a grouped one survives save and load.
    let old = #"{"id":"\#(UUID().uuidString)","name":"NF","isArchived":false}"#
    expect(try! dec.decode(Project.self, from: Data(old.utf8)).group == nil, "a project from before groups loads with none")
    let doc = StoreDocument(projects: [a, c])
    expect(roundTrip(doc) == doc, "groups survive save and load")

    // Two devices: the later move wins, whichever way round they merge.
    let t0 = Date(timeIntervalSince1970: 3_000_000)
    var phone = Project(name: "NF", categoryID: research, group: "Ongoing", modifiedAt: t0)
    var mac = phone; mac.group = "Grants"; mac.modifiedAt = t0.addingTimeInterval(30)
    phone.modifiedAt = t0
    let m1 = StoreDocument(projects: [phone]).merged(with: StoreDocument(projects: [mac]))
    let m2 = StoreDocument(projects: [mac]).merged(with: StoreDocument(projects: [phone]))
    expect(m1.projects.first?.group == "Grants" && m2.projects.first?.group == "Grants", "the later move to a group wins on both devices")
}

// MARK: J — groups in CSV
do {
    let cat = CardCategory(label: "Research", symbolName: "flask", color: .indigo)
    let grant = Project(name: "BETA", categoryID: cat.id, group: "Grants")
    let loose = Project(name: "DELTA", categoryID: cat.id)
    var c1 = TodoItem(title: "deliverable", categoryID: cat.id); c1.projectID = grant.id
    var c2 = TodoItem(title: "membership", categoryID: cat.id); c2.projectID = loose.id
    let c3 = TodoItem(title: "no project", categoryID: cat.id)
    let text = CardCSV.export(cards: [c1, c2, c3], categories: [cat], projects: [grant, loose])
    let lines = text.split(separator: "\n").map(String.init)
    expect(lines[0].hasSuffix(",project,group"), "group column written last, after project — got \(lines[0])")
    expect(lines[1].hasSuffix(",BETA,Grants"), "a grouped project's cards carry its group")
    expect(lines[2].hasSuffix(",DELTA,"), "no group: empty column")
    expect(lines[3].hasSuffix(",,"), "no project: both empty")

    let back = CardCSV.parse(text, categories: [cat])
    expect(back.projectGroups == [Project.key(for: "BETA"): "Grants"], "round-trip: the group comes back, empty ones do not")

    let clash = CardCSV.parse("title,project,group\na,NF,Ongoing\nb,NF,Grants\nc,NF,\n", categories: [])
    expect(clash.projectGroups[Project.key(for: "NF")] == "Ongoing", "if a file disagrees with itself, the first row wins")

    let cluster = CardCSV.parse("title,project,cluster\na,NF,Grants\n", categories: [])
    expect(cluster.projectGroups[Project.key(for: "NF")] == "Grants", "a 'cluster' column is read as the group")

    let noGroupColumn = CardCSV.parse("title,project\na,NF\n", categories: [])
    expect(noGroupColumn.projectGroups.isEmpty, "a file from before groups names none, so none are changed")

    let headerless = "\(UUID().uuidString),old card,today,Research,,,,NF\n"
    let h = CardCSV.parse(headerless, categories: [cat])
    expect(h.cards.first?.title == "old card" && h.projectNames.values.first == "NF", "last week's export with no header still reads by position")
}


// MARK: K — what a new install arrives with
do {
    let starter = StoreDocument.starter()
    expect(!starter.cards.isEmpty, "a new install is not an empty screen")
    expect(starter.cards.allSatisfy(\.isSample), "every starter card is marked a sample")
    expect(Set(starter.cards.map(\.bucket)).count >= 4, "the cards show several stacks, not one")
    expect(starter.cards.contains { $0.projectID != nil }, "one card carries a tag, to show tags exist")
    expect(starter.cards.contains { $0.isCompleted }, "and one is done, so Completed is not a mystery")
    expect(starter.categories.map(\.label) == ["Home", "Work", "Courses"], "the seeded categories suit anyone — got \(starter.categories.map(\.label))")

    // A Later card may not be dated sooner than the day after tomorrow.
    for card in starter.cards where card.bucket == .later {
        if let due = card.dueDate {
            expect(Scheduler.dayOffset(for: due) >= 2, "a starter card in Later is dated far enough out")
        }
    }
    // The filing pass must leave the starter alone: nothing jumps stack on launch.
    for card in starter.cards where !card.isCompleted {
        if let due = card.dueDate, let implied = Scheduler.autoStack(for: due) {
            expect(implied == card.bucket, "\(card.title) would be re-filed the moment it appeared")
        }
    }
    expect(roundTrip(starter) == starter, "the starter document saves and loads unchanged")
}

// MARK: L — sweeping the samples away
do {
    var starter = StoreDocument.starter()
    expect(starter.hasSampleCards, "samples are recognisable")

    // The user edits one: it becomes theirs and must survive.
    let keptID = starter.cards[0].id
    starter.cards[0].isSample = false
    starter.cards[0].title = "Buy milk"

    let swept = starter.removingSampleCards()
    expect(swept.cards.map(\.id) == [keptID], "only the untouched samples go")
    expect(!swept.hasSampleCards, "and none are left")
    expect(swept.projects.isEmpty, "the starter's tag goes with them when nothing uses it")

    // A tag the user has put on a card of their own is kept.
    var adopted = StoreDocument.starter()
    let tag = adopted.projects[0].id
    adopted.cards.append({
        var mine = TodoItem(title: "book hotel", bucket: .later); mine.projectID = tag; return mine
    }())
    expect(adopted.removingSampleCards().projects.count == 1, "a tag still in use is kept")

    // Nothing to sweep is a no-op, not a rebuild.
    let plain = StoreDocument(cards: [TodoItem(title: "real card")])
    expect(plain.removingSampleCards() == plain, "a document with no samples is untouched")
}


// MARK: M — looking back at a week
do {
    // A calendar whose weeks start on Monday, as they do across Europe.
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Brussels")!
    calendar.firstWeekday = 2

    func at(_ text: String) -> Date {
        let f = DateFormatter()
        f.calendar = calendar; f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: text)!
    }
    // Wednesday 23 September 2026.
    let now = at("2026-09-23 10:00")

    let thisWeek = ReviewWeek.thisWeek.interval(now: now, calendar: calendar)!
    let lastWeek = ReviewWeek.lastWeek.interval(now: now, calendar: calendar)!
    expect(thisWeek.start == at("2026-09-21 00:00"), "this week starts on Monday")
    expect(lastWeek.start == at("2026-09-14 00:00"), "last week is the seven days before it")
    expect(lastWeek.end == thisWeek.start, "the two weeks meet without a gap or an overlap")

    func done(_ title: String, _ when: String) -> TodoItem {
        var card = TodoItem(title: title, bucket: .completed)
        card.completedAt = at(when)
        card.bucketBeforeCompletion = .today
        return card
    }
    var openCard = TodoItem(title: "not done", bucket: .today)
    openCard.completedAt = at("2026-09-22 09:00")   // a stale stamp on an open card

    let cards = [
        done("Monday morning", "2026-09-21 09:00"),
        done("Monday evening", "2026-09-21 18:30"),
        done("Wednesday", "2026-09-23 08:00"),
        done("Sunday, just before the week turned", "2026-09-20 23:59"),
        done("A fortnight ago", "2026-09-10 12:00"),
        openCard,
    ]

    let week = Review.days(completedIn: thisWeek, cards: cards, calendar: calendar)
    expect(week.map(\.cards.count) == [1, 2], "grouped by day, newest day first — got \(week.map(\.cards.count))")
    expect(week.first?.cards.first?.title == "Wednesday", "today's card leads")
    expect(week.last?.cards.map(\.title) == ["Monday evening", "Monday morning"],
           "within a day, the most recent is first")
    expect(Review.count(completedIn: thisWeek, cards: cards, calendar: calendar) == 3, "three finished this week")

    let previous = Review.days(completedIn: lastWeek, cards: cards, calendar: calendar)
    expect(previous.map { $0.cards.map(\.title) } == [["Sunday, just before the week turned"]],
           "a card finished at 23:59 on Sunday belongs to the week that was ending")
    expect(!week.contains { $0.cards.contains { $0.title == "not done" } },
           "an open card with a stale timestamp is not counted as done")
    expect(!week.contains { $0.cards.contains { $0.title == "A fortnight ago" } }, "older weeks are left out")

    // A week with nothing in it is empty, not a row of blank days.
    let quiet = DateInterval(start: at("2026-08-03 00:00"), end: at("2026-08-10 00:00"))
    expect(Review.days(completedIn: quiet, cards: cards, calendar: calendar).isEmpty, "a quiet week has no days")
    expect(Review.count(completedIn: quiet, cards: cards, calendar: calendar) == 0, "and counts nothing")
}

print(failures == 0 ? "All \(checks) assertions passed." : "\(failures) of \(checks) failed.")
exit(failures == 0 ? 0 : 1)
