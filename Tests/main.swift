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
    expect(text.hasPrefix("id,title,stack,category,deadline,completed,created,project,group,remind\n"),
           "the deadline keeps the old date column's place; new ones go last")
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
    // Every new column goes last, so an older export still reads by position.
    expect(lines[0].hasSuffix(",project,group,remind"),
           "the newest columns are the last ones — got \(lines[0])")
    expect(lines[1].contains(",BETA,Grants,"), "a grouped project's cards carry its group")
    expect(lines[2].contains(",DELTA,,"), "no group: empty column")
    expect(lines[3].hasSuffix(",,,"), "no project, no group, no reminder: empty to the end")

    // An older export still carries a "reminds" column. It records something
    // that no longer exists, and is read as the unknown column it now is.
    let withDead = CardCSV.parse("title,remind,reminds\nold card,2026-10-02T09:00:00Z,no\n",
                                 categories: [])
    expect(withDead.cards.first?.remindAt != nil, "an older export's reminder still imports")

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

    // A starter card may carry a deadline; none of them may arrive with a
    // reminder already armed, which would go off at someone who has not yet
    // written a card.
    expect(starter.cards.allSatisfy { $0.remindAt == nil }, "a new install reminds you of nothing")
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

// MARK: N — what the filter rows promise
do {
    let research = UUID(), teaching = UUID()
    let grant = Project(name: "FRIA", categoryID: research, group: "Grants")
    let idle = Project(name: "GD-EQP", categoryID: research, group: "Grants")   // everything in it is done
    let course = Project(name: "ABC1234", categoryID: teaching)

    func card(_ title: String, _ bucket: Bucket, _ category: UUID?, _ project: Project?) -> TodoItem {
        var item = TodoItem(title: title, bucket: bucket)
        item.categoryID = category
        item.projectID = project?.id
        return item
    }

    let cards = [
        card("write the case for support", .today, research, grant),
        card("chase the letter", .later, research, grant),
        card("order the rig", .completed, research, idle),
        card("mark the exams", .completed, teaching, course),
        card("book the room", .inbox, teaching, course),
        card("nothing filed", .today, nil, nil),
    ]

    let byProject = FilterCounts.byProject(cards)
    expect(byProject[grant.id] == 2, "a project counts the cards still to do")
    expect(byProject[idle.id] == nil, "a project whose cards are all done counts none")
    expect(byProject[course.id] == 1, "the finished exam is not waiting to be marked again")

    let byCategory = FilterCounts.byCategory(cards)
    expect(byCategory[research] == 2 && byCategory[teaching] == 1, "categories count the same way")

    // The bug this replaces: the heading showed how many projects were in the
    // group, so a group holding one finished project offered "All 1" and then
    // filtered to nothing.
    expect(FilterCounts.total(of: [idle], in: byProject) == 0, "a group of finished projects offers nothing")
    expect(FilterCounts.total(of: [grant, idle], in: byProject) == 2, "a group is worth its projects' cards, not its projects")
    expect(FilterCounts.total(of: [], in: byProject) == 0, "an empty group counts nothing")

    // The promise itself: whatever a row shows, filtering by it finds at least
    // that many cards to show, using the test the list actually applies.
    func filtered(categories: Set<UUID>, projects: Set<UUID>) -> [TodoItem] {
        cards.filter { card in
            if let id = card.categoryID, categories.contains(id) { return true }
            if let id = card.projectID, projects.contains(id) { return true }
            return false
        }
    }
    for project in [grant, idle, course] {
        let shown = byProject[project.id] ?? 0
        expect(filtered(categories: [], projects: [project.id]).count >= shown,
               "\(project.name) promised \(shown) and must not show fewer")
    }
    for category in [research, teaching] {
        let shown = byCategory[category] ?? 0
        expect(filtered(categories: [category], projects: []).count >= shown,
               "a category promising \(shown) must not show fewer")
    }
    expect(filtered(categories: [], projects: [grant.id, idle.id]).count
           >= FilterCounts.total(of: [grant, idle], in: byProject), "nor may a group")
}

// MARK: O — finding a card by what it shows
do {
    func hit(_ query: String, _ title: String, _ project: String? = nil) -> Bool {
        CardSearch.matches(title: title, project: project, terms: CardSearch.terms(in: query))
    }

    expect(hit("flight", "book flights"), "a word inside the title")
    expect(hit("FLIGHT", "book flights"), "case is ignored")
    expect(hit("creche", "réserver la crèche"), "accents are ignored, so a plain keyboard finds them")
    expect(hit("crèche", "reserver la creche"), "and the other way round")
    expect(hit("flight book", "book the flights"), "every word must appear, in any order")
    expect(!hit("flight hotel", "book the flights"), "a word that appears nowhere fails the match")
    expect(hit("  ", "anything"), "a blank query hides nothing")
    expect(CardSearch.terms(in: "   ").isEmpty, "and reads as no terms at all")

    // The project is printed in front of the title, so it is part of the card.
    expect(hit("fria", "write the case for support", "FRIA"), "the project prefix is searched too")
    expect(hit("fria support", "write the case for support", "FRIA"), "across the project and the title")
    expect(!hit("fria", "write the case for support", "SPINEP"), "another project does not match")
    expect(!hit("fria", "write the case for support"), "nor does a card with no project")

    // Whole-string matching would make a two-word query useless: the words are
    // separated by the project name or by other words.
    expect(hit("book crèche", "book the crèche", "TRIP"), "words either side of other words")
}

// MARK: P — putting a project away
do {
    let research = UUID()
    let course = Project(name: "ABC1234", categoryID: research)
    let other = Project(name: "FRIA", categoryID: research)

    func card(_ title: String, _ bucket: Bucket, _ project: Project?) -> TodoItem {
        var item = TodoItem(title: title, bucket: bucket)
        item.projectID = project?.id
        return item
    }

    let cards = [
        card("mark the exams", .today, course),
        card("upload the slides", .later, course),
        card("last year's exams", .completed, course),
        card("write the case", .today, other),
        card("no project at all", .today, nil),
    ]

    let open = Archiving.openCards(of: course, in: cards)
    expect(open.map(\.title) == ["mark the exams", "upload the slides"],
           "what archiving would have to finish — got \(open.map(\.title))")
    expect(!Archiving.isFinished(course, in: cards), "a project with work left is not finished")
    expect(Archiving.openCards(of: other, in: cards).count == 1, "another project's cards are its own")

    // A card already done, and one belonging to nothing, are never swept in.
    expect(!open.contains { $0.title == "last year's exams" }, "a finished card needs no finishing")
    expect(!open.contains { $0.title == "no project at all" }, "a card with no project is not in one")

    let done = cards.map { c -> TodoItem in
        guard c.projectID == course.id, !c.isCompleted else { return c }
        var card = c
        card.bucketBeforeCompletion = card.bucket
        card.bucket = .completed
        return card
    }
    expect(Archiving.isFinished(course, in: done), "once they are ticked off, it can be put away")
    expect(!Archiving.isFinished(other, in: done), "and only that project is affected")

    // Nothing in it at all counts as finished: a project typed and never used.
    expect(Archiving.isFinished(Project(name: "EMPTY", categoryID: research), in: cards),
           "an empty project has nothing to finish")
}

// MARK: Q — what a sync actually did
do {
    let cat = UUID()
    func card(_ title: String, _ bucket: Bucket = .today) -> TodoItem {
        var item = TodoItem(title: title, bucket: bucket)
        item.categoryID = cat
        return item
    }

    let a = card("write the case"), b = card("chase the letter"), c = card("mark the exams")
    let before = StoreDocument(cards: [a, b])

    expect(before.change(from: before).isNothing, "a document that did not move reports nothing")

    // One new card.
    let arrived = StoreDocument(cards: [a, b, c])
    expect(arrived.change(from: before) == StoreDocument.Change(arrived: 1, changed: 0, removed: 0),
           "a card that was not there before has arrived")

    // One card edited: same id, different content.
    var edited = b; edited.title = "chase the letter again"
    let changed = StoreDocument(cards: [a, edited])
    expect(changed.change(from: before) == StoreDocument.Change(arrived: 0, changed: 1, removed: 0),
           "the same card with new contents counts as updated, not as arrived")

    // One card gone.
    let gone = StoreDocument(cards: [a])
    expect(gone.change(from: before) == StoreDocument.Change(arrived: 0, changed: 0, removed: 1),
           "a card that is no longer there was removed")

    // All three at once, which is what a real merge looks like.
    let mixed = StoreDocument(cards: [edited, c])
    expect(mixed.change(from: before) == StoreDocument.Change(arrived: 1, changed: 1, removed: 1),
           "arrived, updated and removed are counted separately — got \(mixed.change(from: before))")

    // Moving a card between stacks is an edit, not an arrival: same id.
    var moved = a; moved.bucket = .later
    expect(StoreDocument(cards: [moved, b]).change(from: before)
           == StoreDocument.Change(arrived: 0, changed: 1, removed: 0),
           "a card that changed stack is the same card")

    expect(StoreDocument.Change().isNothing, "an empty change is nothing")
    expect(!StoreDocument.Change(arrived: 1, changed: 0, removed: 0).isNothing, "one arrival is something")
}

// MARK: R — a project takes its cards with it
do {
    let research = UUID(), teaching = UUID()
    let course = Project(name: "ABC1234", categoryID: teaching)
    let other = Project(name: "FRIA", categoryID: research)

    func card(_ title: String, _ project: Project?, _ category: UUID?) -> TodoItem {
        var item = TodoItem(title: title, bucket: .today)
        item.projectID = project?.id
        item.categoryID = category
        return item
    }

    let cards = [
        card("mark the exams", course, teaching),          // follows the project
        card("book the room", course, research),           // filed elsewhere
        card("no category at all", course, nil),
        card("write the case", other, research),           // another project
        card("loose card", nil, teaching),                 // no project
    ]

    // Everything in the project moves, wherever it was — except a card that is
    // already in the destination, which needs no edit and must not be stamped
    // for a change that did not happen.
    let moving = ProjectCategory.cardsToRefile(course, to: research, in: cards)
    expect(moving.map(\.title).sorted() == ["mark the exams", "no category at all"].sorted(),
           "every card in the project moves — got \(moving.map(\.title))")
    expect(!moving.contains { $0.title == "book the room" },
           "a card already in the destination is not touched")
    expect(!moving.contains { $0.title == "write the case" }, "another project's cards stay put")
    expect(!moving.contains { $0.title == "loose card" }, "a card with no project is not in one")

    // A card already in the destination needs no edit, so it is not stamped.
    let already = ProjectCategory.cardsToRefile(course, to: teaching, in: cards)
    expect(already.map(\.title).sorted() == ["book the room", "no category at all"].sorted(),
           "a card already in the destination is left alone — got \(already.map(\.title))")

    // Moving to no category at all is a move like any other.
    let cleared = ProjectCategory.cardsToRefile(course, to: nil, in: cards)
    expect(cleared.map(\.title).sorted() == ["book the room", "mark the exams"].sorted(),
           "clearing the category moves the ones that had one")

    expect(ProjectCategory.cardsToRefile(Project(name: "EMPTY", categoryID: nil), to: research, in: cards).isEmpty,
           "a project with no cards moves nothing")
}

// MARK: S — a fresh install must not outrank a real edit
do {
    // The seeded three share their ids with every other install's, so any
    // merge has to choose between two versions of the same category. This is
    // the case that reset a real user's renames back to the defaults.
    expect(CardCategory.defaults.allSatisfy { $0.modifiedAt == .distantPast },
           "seeded categories are stamped distantPast, not with the install's clock")
    expect(StoreDocument.starter().projects.allSatisfy { $0.modifiedAt == .distantPast },
           "and so is the seeded project")

    // Someone renamed the three, weeks ago.
    let renamedAt = Date(timeIntervalSince1970: 1_000_000)
    var renamed = CardCategory.defaults
    let names = ["Research", "Teaching", "Personal"]
    for i in renamed.indices {
        renamed[i].label = names[i]
        renamed[i].modifiedAt = renamedAt
    }
    var theirs = StoreDocument(categories: renamed)
    theirs.cards = [TodoItem(title: "write the case", bucket: .today)]

    // A brand-new install, seeded today, meets that file.
    let fresh = StoreDocument.starter()

    for (merged, side) in [(theirs.merged(with: fresh), "existing device merging the newcomer"),
                           (fresh.merged(with: theirs), "newcomer merging the existing file")] {
        let labels = merged.categories.sorted { $0.id.uuidString < $1.id.uuidString }.map(\.label)
        expect(labels == names, "the renames survive — \(side) got \(labels)")
    }

    // And a real edit still beats another real edit, by date as before.
    var later = renamed
    later[0].label = "Grants"
    later[0].modifiedAt = renamedAt.addingTimeInterval(60)
    let newest = StoreDocument(categories: renamed).merged(with: StoreDocument(categories: later))
    expect(newest.categories.first { $0.id == renamed[0].id }?.label == "Grants",
           "distantPast has not broken ordinary last-edit-wins")
}

// MARK: T — the reminder says when to start, and moves nothing
do {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Brussels")!
    func at(_ s: String) -> Date {
        let f = DateFormatter()
        f.calendar = calendar; f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: s)!
    }
    let now = at("2026-10-01 09:00")

    expect(Urgency.of(nil, now: now, calendar: calendar) == Urgency.none,
           "no reminder, no colour")
    expect(Urgency.of(at("2026-09-30 00:00"), now: now, calendar: calendar) == .overdue,
           "yesterday is overdue")
    expect(Urgency.of(at("2026-10-01 23:00"), now: now, calendar: calendar) == .due,
           "today is due, whatever the clock says — the day is what is being asked about")
    expect(Urgency.of(at("2026-10-02 00:00"), now: now, calendar: calendar) == .approaching,
           "tomorrow is approaching")
    expect(Urgency.of(at("2026-10-04 00:00"), now: now, calendar: calendar) == .approaching,
           "and so is the last day inside the window")
    expect(Urgency.of(at("2026-10-05 00:00"), now: now, calendar: calendar) == Urgency.none,
           "a day past the window is not yet worth colouring")

    // The deadline is the far end of a job already started. Colouring it too
    // would put two things on one card competing to say "now".
    var dated = TodoItem(title: "write the case", bucket: .later)
    dated.deadline = at("2026-09-28 00:00")
    expect(Urgency.of(dated.remindAt, now: now, calendar: calendar) == Urgency.none,
           "a deadline on its own colours nothing")

    // The point of the whole change: a date in the past does not imply a
    // stack, so a four-day job can sit in Today for four days.
    var card = TodoItem(title: "write the case", bucket: .later,
                        remindAt: at("2026-09-28 09:00"),
                        deadline: at("2026-10-02 00:00"))
    expect(card.bucket == .later, "an overdue reminder leaves the card where it was put")
    card.bucket = .today
    expect(card.remindAt == at("2026-09-28 09:00") && card.deadline == at("2026-10-02 00:00"),
           "moving a card keeps both dates")
}

// MARK: U — a reminder waits to be answered
do {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Brussels")!
    func at(_ s: String) -> Date {
        let f = DateFormatter()
        f.calendar = calendar; f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: s)!
    }
    let now = at("2026-10-01 09:00")
    let fired = at("2026-10-01 08:00")

    let card = TodoItem(title: "chase the letter", bucket: .later, remindAt: fired)
    expect(Reminders.isOutstanding(card, now: now), "a reminder that has gone off is waiting")

    var later = card; later.remindAt = at("2026-10-02 08:00")
    expect(!Reminders.isOutstanding(later, now: now), "one still to come is not")

    var done = card; done.bucket = .completed
    expect(!Reminders.isOutstanding(done, now: now), "finishing the work answers the reminder")

    // Dismissing the notification is not an answer; only these are.
    var moved = card
    ReminderAnswer.move(.today).apply(to: &moved, now: now, calendar: calendar)
    expect(moved.bucket == .today && moved.remindAt == nil, "Move to Today moves it and is done")
    expect(!Reminders.isOutstanding(moved, now: now), "and it leaves the list")

    var snoozed = card
    ReminderAnswer.snooze.apply(to: &snoozed, now: now, calendar: calendar)
    expect(snoozed.bucket == .later, "snoozing moves nothing")
    expect(snoozed.remindAt == at("2026-10-02 08:00"), "it asks again at the same time tomorrow")

    // Counted from now, not from the reminder. A week-old reminder snoozed by
    // adding a day would land in the past, go quiet and never ask again —
    // which reads exactly like the button having eaten the card.
    var stale = card; stale.remindAt = at("2026-09-24 08:00")
    ReminderAnswer.snooze.apply(to: &stale, now: now, calendar: calendar)
    expect(stale.remindAt == at("2026-10-02 08:00"), "a long-ignored reminder still lands tomorrow")
    expect(Reminders.isOutstanding(stale, now: at("2026-10-02 09:00")), "and asks again then")
    expect(!Reminders.isOutstanding(snoozed, now: now), "and is quiet until then")
    expect(Reminders.isOutstanding(snoozed, now: at("2026-10-02 09:00")),
           "then it is waiting again — the answer given was to the last one")

    var cleared = card
    cleared.deadline = at("2026-10-09 00:00")
    ReminderAnswer.clear.apply(to: &cleared, now: now, calendar: calendar)
    expect(cleared.remindAt == nil, "clearing removes the reminder")
    expect(cleared.deadline == at("2026-10-09 00:00"), "and leaves the deadline alone")
    expect(cleared.bucket == .later, "and moves nothing")

    // Only the future is scheduled, and only for cards still to do.
    let cards = [card, later, done, moved]
    expect(Reminders.scheduled(in: cards, now: now).map(\.title) == ["chase the letter"],
           "one notification pending, for the one reminder still to come")
    expect(Reminders.outstanding(in: cards, now: now).count == 1, "and one waiting to be answered")
}

// MARK: V — an old file's date becomes the day to start, and moves nothing
do {
    let id = UUID().uuidString
    let old = #"{"id":"\#(id)","title":"renew the passports","bucket":"later","dueDate":"2026-09-20T00:00:00.000Z"}"#
    let card = try! dec.decode(TodoItem.self, from: Data(old.utf8))
    expect(card.deadline != nil, "a date written by a version that filed cards is read at all")
    expect(card.bucket == .later, "and the card stays exactly where that version left it")
    expect(card.remindAt == nil, "the promotion needs a clock, so it happens in the document pass")

    // The old key is never written back: a version that files cards cannot
    // file a date it cannot see.
    let written = String(data: try! enc.encode(card), encoding: .utf8)!
    expect(written.contains("deadline"), "the deadline is written under its own name")
    expect(!written.contains("dueDate"), "and the old key is gone, which is what disarms old versions")

    // A newer file wins over the legacy key when both somehow appear.
    let both = #"{"id":"\#(id)","title":"x","deadline":"2026-10-02T00:00:00.000Z","dueDate":"2026-01-01T00:00:00.000Z"}"#
    let mixed = try! dec.decode(TodoItem.self, from: Data(both.utf8))
    expect(mixed.deadline.map { $0 > Date(timeIntervalSince1970: 1_767_000_000) } == true,
           "the deadline key is preferred over the legacy one")
}

// MARK: W — one flag gathers the cards to pick up now
do {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Brussels")!
    func at(_ s: String) -> Date {
        let f = DateFormatter()
        f.calendar = calendar; f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: s)!
    }
    let now = at("2026-10-01 09:00")

    func card(_ title: String, _ bucket: Bucket,
              remind: String? = nil, due: String? = nil) -> TodoItem {
        TodoItem(title: title, bucket: bucket,
                 remindAt: remind.map(at), deadline: due.map(at))
    }

    let overdue = card("renew the passports", .later, remind: "2026-09-29 09:00")
    let thisMorning = card("chase the letter", .later, remind: "2026-10-01 08:00")
    // Not fired yet, so the review is not holding it — but it is today's work.
    let thisEvening = card("ring the surveyor", .inbox, remind: "2026-10-01 17:00")
    let tomorrow = card("book the hall", .inbox, remind: "2026-10-02 09:00")
    let distant = card("plan the trip", .later, remind: "2026-10-30 09:00")
    // A long job: started days ago, due at the end of the month.
    let running = card("write the case", .today, remind: "2026-09-28 09:00", due: "2026-10-31 00:00")
    var done = card("collect the keys", .completed, remind: "2026-09-26 09:00")
    done.bucket = .completed

    expect(Attention.needed(overdue, now: now, calendar: calendar),
           "a reminder that came and went asks to be picked up")
    expect(Attention.needed(thisMorning, now: now, calendar: calendar), "so does one that fired today")
    expect(Attention.needed(thisEvening, now: now, calendar: calendar),
           "and one set for later today, which the review has not got yet")
    expect(!Reminders.isOutstanding(thisEvening, now: now),
           "the flag is wider than the review, on purpose")
    expect(!Attention.needed(tomorrow, now: now, calendar: calendar),
           "tomorrow is orange — being shown, not asked about")
    expect(!Attention.needed(distant, now: now, calendar: calendar), "and a distant one is neither")
    expect(Attention.needed(running, now: now, calendar: calendar),
           "a four-day job is gathered by its start, not by its far-off deadline")
    expect(!Attention.needed(done, now: now, calendar: calendar),
           "and a finished card asks for nothing, however late it was")

    let all = [overdue, thisMorning, thisEvening, tomorrow, distant, running, done]
    expect(Attention.count(in: all, now: now) == 4, "so the badge reads four")

    // The flag and the red edge must agree, or the badge counts cards the user
    // cannot see the mark on.
    for item in all {
        let red = !item.isCompleted && Urgency.of(item.remindAt, now: now, calendar: calendar).isRed
        expect(Attention.needed(item, now: now, calendar: calendar) == red,
               "the filter takes exactly the cards the list draws a red edge on")
    }
}

// MARK: X — a deadline with no start becomes the day to start
do {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Brussels")!
    func at(_ s: String) -> Date {
        let f = DateFormatter()
        f.calendar = calendar; f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: s)!
    }
    let now = at("2026-10-01 09:00")

    var past = TodoItem(title: "renew the passports", bucket: .later)
    past.deadline = at("2026-09-20 00:00")
    let edited = past.modifiedAt

    var future = TodoItem(title: "book the hall", bucket: .inbox)
    future.deadline = at("2026-10-20 00:00")

    // Already has both: written by this version, so nothing to promote.
    let whole = TodoItem(title: "write the case", bucket: .today,
                         remindAt: at("2026-10-05 09:00"), deadline: at("2026-10-31 00:00"))

    var document = StoreDocument.starter()
    document.cards = [past, future, whole]
    let after = document.promotingOrphanDeadlines(now: now, calendar: calendar)

    expect(after.cards[0].remindAt == at("2026-09-20 09:00"),
           "the old date becomes the day to pick the card up, at nine")
    expect(after.cards[0].deadline == nil, "and is no longer a finish line with no start")
    expect(after.cards[0].bucket == .later, "the card does not move")
    expect(after.cards[0].modifiedAt == edited,
           "and is not stamped as edited: every device computes this from the same file")
    expect(after.cards[0].reminderAnsweredAt == at("2026-09-20 09:00"),
           "a moment already past arrives answered, so a year of old dates is not a backlog")
    expect(!Reminders.isOutstanding(after.cards[0], now: now), "so the review stays empty")
    expect(Attention.needed(after.cards[0], now: now, calendar: calendar),
           "but the card is still red, which is the part worth seeing")

    expect(after.cards[1].remindAt == at("2026-10-20 09:00"), "a date still to come is promoted too")
    expect(after.cards[1].reminderAnsweredAt == nil, "and will ask, because it has not yet")

    expect(after.cards[2].remindAt == at("2026-10-05 09:00")
           && after.cards[2].deadline == at("2026-10-31 00:00"),
           "a card that already has both is left alone")

    expect(after.promotingOrphanDeadlines(now: now, calendar: calendar) == after,
           "and promoting is stable, so a merge does not keep rewriting the file")
}

print(failures == 0 ? "All \(checks) assertions passed." : "\(failures) of \(checks) failed.")
exit(failures == 0 ? 0 : 1)
