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
    expect(ProjectToken.find(in: "#lk exam")?.remainder == "exam", "the rest of the line is the title")
    expect(ProjectToken.find(in: "exam questions") == nil, "no # means no project")
    expect(ProjectToken.find(in: "# ") == nil, "hash-space is not a project")
    expect(ProjectToken.find(in: "use C#") == nil, "a # inside a word is not a project")

    // The whole rule: a tag is the first word or it is nothing. Anything else
    // is a title that happens to contain a hash, and there are plenty.
    expect(ProjectToken.find(in: "exam #lk") == nil, "a #word at the end is just text now")
    expect(ProjectToken.find(in: "fix issue #42") == nil, "and so is a bug number")
    expect(ProjectToken.find(in: "buy a #2 pencil") == nil, "and so is one in the middle")
    expect(ProjectToken.find(in: "#lk  exam")?.remainder == "exam",
           "extra spaces after the tag are not part of the title")
    expect(ProjectToken.find(in: "\u{FF03}lk")?.query == "lk", "full-width # from a CJK keyboard works")
}

// MARK: B — names
do {
    expect(Project.clean("#STUDY2026:") == "STUDY2026", "leading # and trailing colon stripped")
    expect(Project.clean("(ALPHA)") == "ALPHA", "brackets stripped")
    expect(Project.key(for: "study2026") == Project.key(for: "#STUDY2026"), "case and # ignored when matching")
    expect(Project.key(for: "Résumé") == Project.key(for: "resume"), "accents ignored when matching")
    expect(Project.clean("  ") == "", "blank is no name")

    // Capitals belong to creation, not to cleaning: `looksLikeCode` asks
    // whether a word has no lowercase in it, so a clean that capitalised
    // would make every word in the language look like a code.
    expect(Project.clean("trip") == "trip", "cleaning leaves the case alone")
    expect(Project.canonicalName("trip") == "TRIP", "a project is created in capitals")
    expect(Project.canonicalName("#bio2140:") == "BIO2140", "and cleaned on the way")
    expect(Project.key(for: "trip") == Project.key(for: "TRIP"),
           "which changes no matching, because names were already folded")
    expect(!ProjectConversion.looksLikeCode("trip"), "an ordinary word is not a code")
    expect(ProjectConversion.looksLikeCode("TRIP"), "a word in capitals is")
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
    expect(text.hasPrefix("id,title,stack,category,deadline,completed,created,project,group,remind,notes,entered\n"),
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
    expect(lines[0].hasSuffix(",project,group,remind,notes,entered"),
           "the newest columns are the last ones — got \(lines[0])")
    expect(lines[1].contains(",BETA,Grants,"), "a grouped project's cards carry its group")
    expect(lines[2].contains(",DELTA,,"), "no group: empty column")
    expect(lines[3].contains(",,,"), "no project, no group, no reminder: empty columns")

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
    func hit(_ query: String, _ title: String, _ project: String? = nil,
             group: String? = nil) -> Bool {
        CardSearch.matches(title: title, project: project, group: group,
                           terms: CardSearch.terms(in: query))
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

    // The group is the one part of the haystack the card does not print: it is
    // how a project is remembered once there are enough of them.
    expect(hit("grants", "write the case for support", "FRIA", group: "Grants"),
           "the project's group is searched, though no card shows it")
    expect(hit("grants support", "write the case for support", "FRIA", group: "Grants"),
           "across the group and the title")
    expect(hit("grants fria", "write the case for support", "FRIA", group: "Grants"),
           "across the group and the project")
    expect(!hit("grants", "write the case for support", "FRIA", group: "Manuscripts"),
           "another group does not match")
    expect(!hit("grants", "write the case for support", "FRIA"),
           "nor does a project in no group")
    expect(hit("GRANTS", "x", "FRIA", group: "Grants"), "a group matches whatever the case")

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

    // Dismissing the notification is not an answer. Moving the card is, but
    // that happens on the card — see AA.
    var moved = card
    moved.bucket = .today
    moved.reminderAnsweredAt = now
    expect(!Reminders.isOutstanding(moved, now: now), "answering stops it asking")
    expect(moved.remindAt == fired, "without throwing the date away")

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

// MARK: W — the flag gathers what is still to be settled
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
    // Already in Today: the user has said when they will do it, so the flag
    // has no question left to ask. The card still wears its red edge.
    expect(!Attention.needed(running, now: now, calendar: calendar),
           "a card already filed into Today is not still to be settled")
    expect(Urgency.of(running.remindAt, now: now, calendar: calendar).isRed,
           "though it is still red, which is what says it is today's work")
    expect(!Attention.needed(done, now: now, calendar: calendar),
           "and a finished card asks for nothing, however late it was")

    let all = [overdue, thisMorning, thisEvening, tomorrow, distant, running, done]
    expect(Attention.count(in: all, now: now) == 3, "so the badge reads three")

    // Every flagged card is one the list draws a red edge on. Not the other
    // way round any more: filing a card into Today keeps the edge and drops
    // the flag, which is the whole point — the number goes down as work is
    // decided about.
    for item in all where Attention.needed(item, now: now, calendar: calendar) {
        expect(Urgency.of(item.remindAt, now: now, calendar: calendar).isRed,
               "the flag never counts a card the user can see no mark on")
        expect(!item.bucket.isAddressed, "and never one already filed")
    }

    // Filing it is what clears it, and un-filing brings it back.
    var settled = overdue
    settled.bucket = .today
    expect(!Attention.needed(settled, now: now, calendar: calendar), "filing it settles it")
    settled.bucket = .tomorrow
    expect(!Attention.needed(settled, now: now, calendar: calendar), "Tomorrow counts as decided too")
    settled.bucket = .later
    expect(Attention.needed(settled, now: now, calendar: calendar),
           "and putting it back in Later is un-deciding, so it asks again")
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
    past.dateSemanticsVersion = 0
    let edited = past.modifiedAt

    var future = TodoItem(title: "book the hall", bucket: .inbox)
    future.deadline = at("2026-10-20 00:00")
    future.dateSemanticsVersion = 0

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

// MARK: Y — a backup says what it is in its own name
do {
    let day = BackupKind.dayTag.date(from: "2026-09-28")!

    expect(BackupKind.day.tag == "1day" && BackupKind.week.tag == "1week",
           "the rotating copies are named for how far back they are")
    expect(BackupKind.manual(day).tag == "2026-09-28", "one taken by hand is named for its day")
    expect(BackupKind.manual(day).isManual && !BackupKind.week.isManual, "and knows which it is")

    let phone = BackupFilename.device(from: "Fatima's iPhone", id: "9c3f")
    expect(phone == "Fatima-s-iPhone-9c3f",
           "a device name is reduced to what a filesystem and a mail attachment can both carry")
    expect(BackupFilename.device(from: "andres-macbook-pro.local", id: "6d67")
           == "andres-macbook-pro-6d67",
           "the Bonjour suffix is dropped: every device has it, so it names none of them")
    expect(BackupFilename.device(from: "", id: "9c3f") == "9c3f",
           "and a device that will not say its name still gets a unique one")
    expect(BackupFilename.device(from: "iPhone", id: "0001")
           != BackupFilename.device(from: "iPhone", id: "0002"),
           "two phones that both call themselves iPhone do not overwrite each other")

    // Round-trip, which is the whole promise: a folder of these still makes
    // sense to someone who has lost the app.
    for kind in [BackupKind.day, .twoDays, .week, .manual(day)] {
        let name = BackupFilename.make(kind: kind, device: phone)
        guard let back = BackupFilename.parse(name) else {
            expect(false, "\(name) parses back"); continue
        }
        expect(back.kind == kind && back.device == phone, "\(name) round-trips")
    }

    // The date tag holds dashes of its own, so it is read by width. This is
    // the case that breaks a naive split.
    expect(BackupFilename.parse("DayHand-2026-09-28-Mac-Pro-1a2b")?.device == nil,
           "a name with no .json is not a backup")
    let dated = BackupFilename.parse("DayHand-2026-09-28-Mac-Pro-1a2b.json")
    expect(dated?.kind == .manual(day) && dated?.device == "Mac-Pro-1a2b",
           "a dated name splits after the date, not at its first dash")
    expect(BackupFilename.parse("cards.json") == nil, "the live file is not mistaken for a backup")
    expect(BackupFilename.parse("DayHand-1day-.json") == nil, "and neither is one with no device")
}

// MARK: Z — rotation ages copies down the chain, once a day
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
    func plan(_ day: String?, _ twoDays: String?, _ week: String?) -> BackupRotation.Plan {
        BackupRotation.plan(day: day.map(at), twoDays: twoDays.map(at), week: week.map(at),
                            now: now, calendar: calendar)
    }

    expect(plan("2026-10-01 07:00", "2026-09-30 09:00", "2026-09-20 09:00") == .init(),
           "one already taken today means nothing happens — the usual outcome")

    var first = BackupRotation.Plan(); first.writeDay = true
    expect(plan(nil, nil, nil) == first, "a first run writes one and has nothing to age")

    let fresh = plan("2026-09-30 09:00", "2026-09-29 09:00", "2026-09-28 09:00")
    expect(fresh == .init(ageTwoDaysToWeek: false, ageDayToTwoDays: true, writeDay: true),
           "a weekly copy only three days old keeps its place, or it would just track the dailies")

    let stale = plan("2026-09-30 09:00", "2026-09-29 09:00", "2026-09-20 09:00")
    expect(stale == .init(ageTwoDaysToWeek: true, ageDayToTwoDays: true, writeDay: true),
           "one genuinely a week behind steps aside")

    expect(plan("2026-09-30 09:00", nil, nil)
           == .init(ageTwoDaysToWeek: false, ageDayToTwoDays: true, writeDay: true),
           "nothing is aged into a slot from a file that is not there")
}

// MARK: AA — dealing with a card answers the reminder that asked
do {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Brussels")!
    func at(_ s: String) -> Date {
        let f = DateFormatter()
        f.calendar = calendar; f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: s)!
    }
    let now = at("2026-10-01 10:00")
    let fired = at("2026-10-01 08:00")

    // What the store does on a move. Answered, not cleared.
    var card = TodoItem(title: "chase the letter", bucket: .later, remindAt: fired)
    expect(Reminders.isOutstanding(card, now: now), "it is asking to begin with")

    card.bucket = .today
    card.reminderAnsweredAt = now

    expect(!Reminders.isOutstanding(card, now: now),
           "moving it is an answer: a card dealt with must not go on asking")
    expect(card.remindAt == fired,
           "but the date stays — moving a card keeps both fields, as it always has")
    expect(Urgency.of(card.remindAt, now: now, calendar: calendar).isRed,
           "so it keeps its red edge: it is still today's work")
    expect(!Attention.needed(card, now: now, calendar: calendar),
           "but it is off the flag — moving it was the decision the flag was asking for")

    // Snooze re-arms, and the old answer must not carry over to the new ask.
    var snoozed = card
    ReminderAnswer.snooze.apply(to: &snoozed, now: now, calendar: calendar)
    expect(snoozed.remindAt == at("2026-10-02 08:00"), "snoozing asks again tomorrow")
    expect(snoozed.bucket == .today, "and moves nothing")
    expect(!Reminders.isOutstanding(snoozed, now: now), "quiet until then")
    expect(Reminders.isOutstanding(snoozed, now: at("2026-10-02 09:00")),
           "then asking again — the answer given was to the previous one")

    // Clearing is the way to silence a reminder for good.
    var cleared = card
    cleared.deadline = at("2026-10-31 00:00")
    ReminderAnswer.clear.apply(to: &cleared, now: now, calendar: calendar)
    expect(cleared.remindAt == nil, "clearing takes the date with it")
    expect(cleared.deadline == at("2026-10-31 00:00"), "and leaves the deadline alone")
    expect(!Attention.needed(cleared, now: now, calendar: calendar),
           "so the edge goes too — nothing is asking for this card any more")

    // Completing already answered it, and still does.
    var done = TodoItem(title: "collect the keys", bucket: .today, remindAt: fired)
    done.bucket = .completed
    expect(!Reminders.isOutstanding(done, now: now), "finishing the work answers the reminder")
}

// MARK: AB — the filter button counts what the sidebar counts
do {
    let work = CardCategory(label: "Work", symbolName: "briefcase", color: .indigo)
    let home = CardCategory(label: "Home", symbolName: "house", color: .teal)
    let fresco = Project(name: "FRESCO", categoryID: work.id, group: "Projects")
    let qspr = Project(name: "QSPR", categoryID: work.id, group: "Projects")

    func card(_ title: String, _ bucket: Bucket = .later,
              project: Project? = nil, category: CardCategory? = nil) -> TodoItem {
        var c = TodoItem(title: title, bucket: bucket)
        c.projectID = project?.id
        c.categoryID = category?.id ?? project.map { _ in work.id }
        return c
    }

    // The case from the screenshot: the Projects group ticked, which ticks the
    // two projects under it. FRESCO holds three cards, QSPR none.
    let cards = [
        card("DMP", project: fresco),
        card("plan secondments", project: fresco),
        card("training event Brussels date", project: fresco),
        card("Deliverables D8.6", .completed, project: qspr),
        card("Reply Monir PKPD manuscript", .completed, project: qspr),
        card("ERD/ERS lecture", .completed, project: fresco),
        card("tidy the loft", .inbox, category: home)
    ]
    let chosen: Set<UUID> = [fresco.id, qspr.id]

    let counts = FilterCounts.byProject(cards)
    expect(counts[fresco.id] == 3, "the sidebar says FRESCO holds three")
    expect(counts[qspr.id] == nil, "and QSPR none, its cards all being done")
    expect(FilterCounts.total(of: [fresco, qspr], in: counts) == 3, "so the group heading says three")

    // The button used to read 2 here — the number of filters switched on, one
    // per project — which is indistinguishable from a card count.
    expect(FilterCounts.matching(cards, categories: [], projects: chosen) == 3,
           "and the button says three, not two: it counts cards, like every other number")
    expect(FilterCounts.matching(cards, categories: [], projects: chosen)
           == FilterCounts.total(of: [fresco, qspr], in: counts),
           "the button and the group heading cannot drift apart — same rule, one function")

    // The two sets are an either/or.
    expect(FilterCounts.matching(cards, categories: [home.id], projects: []) == 1,
           "a category filter finds a card carrying no project at all")
    expect(FilterCounts.matching(cards, categories: [home.id], projects: chosen) == 4,
           "and choosing both widens rather than narrows")
    expect(FilterCounts.matching(cards, categories: [], projects: []) == 0,
           "nothing chosen, nothing counted")

    // Completed cards are left out of both, which is what makes the two agree.
    expect(cards.filter { $0.isCompleted }.count == 3, "three of these are done")
    expect(FilterCounts.matching(cards, categories: [work.id], projects: []) == 3,
           "and none of them is counted")

    // The list and the button must agree about what is in the narrowing.
    for item in cards {
        let inList = FilterCounts.matches(item, categories: [], projects: chosen)
        expect(inList == (item.projectID == fresco.id || item.projectID == qspr.id),
               "the list's predicate is the button's predicate")
    }
}

// MARK: AC — the icon badge is the flag's count, worked out ahead of time
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
    func count(_ cards: [TodoItem], _ moment: Date) -> Int {
        Attention.count(in: cards, now: moment, calendar: calendar)
    }

    func card(_ title: String, _ bucket: Bucket, _ remind: String) -> TodoItem {
        TodoItem(title: title, bucket: bucket, remindAt: at(remind))
    }

    let already = card("chase the letter", .later, "2026-10-01 08:00")   // red now
    let noon = card("ring the surveyor", .inbox, "2026-10-01 12:00")     // red now: same day
    let tomorrow = card("book the hall", .later, "2026-10-02 09:00")     // orange now
    let filed = card("write the grant case", .today, "2026-10-02 09:00") // never counts
    let cards = [already, noon, tomorrow, filed]

    expect(count(cards, now) == 2, "two are red and unfiled this morning")

    // The badge a notification carries is this function at the moment it
    // fires, which is why the whole set has to be handed to the scheduler.
    expect(count(cards, at("2026-10-01 12:00")) == 2,
           "a reminder arriving on a card already red adds nothing to the count")
    expect(count(cards, at("2026-10-02 09:00")) == 3,
           "and tomorrow's card counts from the moment its day starts")
    expect(count(cards, at("2026-10-02 00:01")) == 3,
           "which is midnight, not the reminder's hour — no notification announces that")
    expect(count(cards, at("2026-10-09 09:00")) == 3,
           "the filed one never joins, however late it gets")

    // The old arithmetic was "those waiting, plus this one, plus everything
    // before it". These are the two cases that breaks on.
    let running = 2 + 1  // what the running total would have said at noon
    expect(count(cards, at("2026-10-01 12:00")) != running,
           "a running total would have over-counted the reminder on an already-red card")

    // Filing or finishing a card takes it off, and only the app being opened
    // can see that — which is why it corrects the badge on launch.
    var settled = cards
    settled[0].bucket = .today
    expect(count(settled, now) == 1, "filing one drops the count the app will set on opening")
    settled[1].bucket = .completed
    expect(count(settled, now) == 0, "and finishing the other empties it")
}

// MARK: AD — every card the flag shows offers the choices that go with it
do {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Brussels")!
    func at(_ s: String) -> Date {
        let f = DateFormatter()
        f.calendar = calendar; f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: s)!
    }
    let now = at("2026-10-03 09:00")
    func snooze(_ c: TodoItem) -> Bool { Reminders.canSnooze(c, now: now, calendar: calendar) }
    func flagged(_ c: TodoItem) -> Bool { Attention.needed(c, now: now, calendar: calendar) }

    // The two cases the old gate got wrong, both reachable in a normal day.
    var laterToday = TodoItem(title: "ring the surveyor", bucket: .inbox,
                              remindAt: at("2026-10-03 17:00"))
    expect(flagged(laterToday), "a reminder due this afternoon is on the flag from the morning")
    expect(!Reminders.isOutstanding(laterToday, now: now), "without having fired yet")
    expect(snooze(laterToday), "and it can still be pushed to tomorrow")

    var answeredThenBack = TodoItem(title: "chase the letter", bucket: .later,
                                    remindAt: at("2026-10-03 08:00"))
    answeredThenBack.reminderAnsweredAt = at("2026-10-03 08:30")   // moved, then moved back
    expect(flagged(answeredThenBack), "a card dealt with and put back in Later is on the flag again")
    expect(!Reminders.isOutstanding(answeredThenBack, now: now), "with its answer still stamped")
    expect(snooze(answeredThenBack), "and it must offer the same choices as any other flagged card")

    // The invariant that was broken: nothing the flag shows is without a snooze.
    for card in [laterToday, answeredThenBack] {
        expect(!flagged(card) || snooze(card), "a flagged card always offers snooze")
    }

    // Still excluded, for the reason the word demands.
    let nextWeek = TodoItem(title: "plan the trip", bucket: .later,
                            remindAt: at("2026-10-10 09:00"))
    expect(!snooze(nextWeek), "a reminder still to come is not snoozed — tomorrow is earlier than it")
    var done = laterToday; done.bucket = .completed
    expect(!snooze(done), "and a finished card has nothing to be reminded about")
    let dateless = TodoItem(title: "tidy the loft", bucket: .inbox)
    expect(!snooze(dateless), "nor has one with no reminder at all")

    // Snoozing always lands later than now, which is the point of excluding
    // the future ones.
    for card in [laterToday, answeredThenBack] {
        let next = Reminders.again(after: card.remindAt!, now: now, calendar: calendar)
        expect(next != nil && next! > now, "snoozing \(card.title) moves it forward, never back")
    }
}

// MARK: AE — a reminder is a day, fired at a fixed hour
do {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Brussels")!
    func at(_ s: String) -> Date {
        let f = DateFormatter()
        f.calendar = calendar; f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: s)!
    }

    // Whatever time of day comes out of the picker, the reminder is the day.
    for messy in ["2026-10-07 00:00", "2026-10-07 13:42", "2026-10-07 23:59"] {
        expect(Scheduler.reminderTime(on: at(messy), calendar: calendar) == at("2026-10-07 09:00"),
               "\(messy) is a reminder for the 7th, and fires at nine like every other")
    }

    let now = at("2026-10-03 15:00")
    expect(Scheduler.defaultReminderTime(now) == Scheduler.reminderTime(on: at("2026-10-04 12:00"),
                                                                        calendar: calendar),
           "the opening suggestion is tomorrow at the same hour as everything else")
    expect(Scheduler.defaultReminderTime(now) > now,
           "and never a moment that has already gone by")

    // Snoozing keeps the hour, so a day-granular reminder stays day-granular.
    let tomorrow = Reminders.again(after: Scheduler.reminderTime(on: at("2026-10-03 09:00"),
                                                                 calendar: calendar),
                                   now: now, calendar: calendar)
    expect(tomorrow == at("2026-10-04 09:00"), "snoozing lands on the next day at nine")

    // A reminder set by an older version at some other hour is left alone: it
    // fires when it was told to, and moving it would be a change nobody asked
    // for. Only the day matters to everything that reads it.
    var legacy = TodoItem(title: "chase the letter", bucket: .later,
                          remindAt: at("2026-10-03 17:00"))
    expect(Urgency.of(legacy.remindAt, now: now, calendar: calendar).isRed,
           "it is red on its day whatever hour it holds")
    expect(Attention.needed(legacy, now: now, calendar: calendar), "and the flag gathers it")
    legacy.remindAt = Scheduler.reminderTime(on: legacy.remindAt!, calendar: calendar)
    expect(legacy.remindAt == at("2026-10-03 09:00"), "editing its date snaps it to the hour")
}

// MARK: AF — Waiting is not your move, and the flag still chases it
do {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Brussels")!
    func at(_ s: String) -> Date {
        let f = DateFormatter()
        f.calendar = calendar; f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: s)!
    }
    let now = at("2026-10-04 09:00")

    // Everything above Waiting is work you can pick up; Waiting and Completed
    // are not. The order is what puts them below the line on screen.
    expect(Bucket.allCases.map(\.rawValue)
           == ["inbox", "today", "tomorrow", "later", "waiting", "completed"],
           "Waiting sits after Later and before Completed")
    expect(Bucket.quickMoveTargets.contains(.waiting),
           "and a card can be moved there in one tap, like any other stack")
    expect(!Bucket.quickMoveTargets.contains(.completed),
           "while Completed is still reached by ticking, not by moving")

    // The point of the whole thing: a reminder on a waiting card is a chase,
    // and the flag must go on gathering it.
    expect(!Bucket.waiting.isAddressed,
           "Waiting is not an answer — somebody else still has it")
    var chase = TodoItem(title: "chase the co-author", bucket: .waiting,
                         remindAt: at("2026-10-04 09:00"))
    expect(Attention.needed(chase, now: now, calendar: calendar),
           "so a reminder that has arrived on a waiting card is still flagged")
    expect(Reminders.canSnooze(chase, now: now, calendar: calendar),
           "and can be pushed to tomorrow like any other")

    // A waiting card with nothing due is quiet. That is the relief it buys.
    let parked = TodoItem(title: "quote from the supplier", bucket: .waiting)
    expect(!Attention.needed(parked, now: now, calendar: calendar),
           "a waiting card with no reminder asks for nothing at all")

    // It survives a save, and a build that has never heard of it is not harmed.
    chase.remindAt = at("2026-10-04 09:00")
    let saved = try! enc.encode(chase)
    expect(String(data: saved, encoding: .utf8)!.contains("\"bucket\" : \"waiting\""),
           "it is stored under its own name")
    let back = try! dec.decode(TodoItem.self, from: saved)
    expect(back.bucket == .waiting, "and reads back as itself")

    // An older build: `decodeIfPresent` answers nil for a raw value it does not
    // know, so the card lands in Inbox and the rest of the file is untouched.
    // Verified against the shipped decoder before this case was added.
    let unknown = #"{"id":"\#(UUID().uuidString)","title":"x","bucket":"someFutureStack"}"#
    let tolerated = try! dec.decode(TodoItem.self, from: Data(unknown.utf8))
    expect(tolerated.bucket == .inbox,
           "an unknown stack falls back rather than throwing the document away")
}

// MARK: AG — a project can be created straight into a group
do {
    let research = UUID(), teaching = UUID()
    var projects = [Project(name: "GRANT", categoryID: research, group: "Grants"),
                    Project(name: "PAPER", categoryID: research, group: "Manuscripts")]

    expect(ProjectGroups.names(in: research, projects: projects) == ["Grants", "Manuscripts"],
           "the groups offered are the ones that category's projects already carry")
    expect(ProjectGroups.names(in: teaching, projects: projects).isEmpty,
           "and a category with no projects has none to offer — nothing to put a card in")

    // A typed label that already exists keeps the spelling it has, so "grants"
    // does not become a second group sitting beside "Grants".
    expect(ProjectGroups.existingName(for: "grants", in: research, projects: projects) == "Grants",
           "a label already in use keeps its spelling")
    expect(ProjectGroups.existingName(for: "Ongoing", in: research, projects: projects) == nil,
           "and one that is not is taken as typed")

    // What the store does when a project is created with a group.
    func created(_ name: String, group: String?) -> Project {
        var p = Project(name: name, categoryID: research)
        p.group = group.flatMap(Project.cleanGroup).map {
            ProjectGroups.existingName(for: $0, in: research, projects: projects) ?? $0
        }
        return p
    }
    expect(created("STUDY", group: "grants").group == "Grants",
           "a new project joins the existing group rather than making a near-duplicate")
    expect(created("STUDY", group: "Ongoing").group == "Ongoing", "or starts a new one")
    expect(created("STUDY", group: nil).group == nil, "and none is still none")
    expect(created("STUDY", group: "   ").group == nil, "whitespace is not a group name")

    // The layout the sidebar draws: a group exists only while something is in
    // it, which is why a group cannot be offered before there is a project.
    projects.append(created("STUDY", group: "Ongoing"))
    let names = ProjectGroups.names(in: research, projects: projects)
    expect(names == ["Grants", "Manuscripts", "Ongoing"],
           "and once a project carries it, the group is there for the next one to pick")
}

// MARK: AH — a hash in a title is no longer a gesture at all
do {
    // The bug this used to pin: opening the editor on a card whose name
    // carried a #word, typing nothing, and closing it renamed the card and
    // invented a project. It cannot happen now for a better reason than a
    // guard — nothing is ever taken from a title without being chosen, so a
    // title may say whatever it likes.
    let untouched = "#1 priority for the week"
    expect(Project.clean("#1") == "1", "a hash is only punctuation on a name now")
    expect(ProjectConversion.split(untouched)?.word == "1",
           "the first word reads the same with or without it")
    expect(!ProjectConversion.looksLikeCode("priority"),
           "and an ordinary first word is never offered as a project")

    expect(ProjectToken.find(in: "a plain title") == nil, "no hash, no token")
}

// MARK: AI — the word that brought a project up is the word that leaves
do {
    let cat = UUID()
    let nocions = Project(name: "NOCIONS", categoryID: cat)
    let grant = Project(name: "GRANT", categoryID: cat)

    // The report: typing NOCIO and taking the NOCIONS it offered left NOCIO
    // behind as the title. Equality said they were different words; they are
    // not — one is why the other was on screen.
    expect(ProjectSuggestions.matches(name: nocions.name, query: "NOCIO"),
           "a half-typed name is why the whole one came up")
    expect(ProjectSuggestions.matches(name: nocions.name, query: "nocions"),
           "and the whole name matches itself, in any case")
    expect(ProjectSuggestions.matches(name: nocions.name, query: "ION"),
           "rank gathers on contains as well as prefix, and so does this")

    // The guard this is really protecting: choosing a project from the recents
    // while typing an ordinary title must not eat the first word.
    expect(!ProjectSuggestions.matches(name: grant.name, query: "Buy"),
           "a recent project picked while typing a title keeps that title")
    expect(!ProjectSuggestions.matches(name: grant.name, query: ""),
           "and nothing typed brings nothing up")

    // Whatever `rank` offers for a query, `matches` agrees was offered for it.
    let ranked = ProjectSuggestions.rank([nocions, grant], query: "NOCIO", lastUsed: [:])
    expect(ranked.first?.name == "NOCIONS", "the half-typed name ranks its project first")
    expect(ranked.allSatisfy { ProjectSuggestions.matches(name: $0.name, query: "NOCIO") },
           "the two tests cannot drift: everything offered counts as offered")
}

// MARK: AI — what Tab completes a half-typed tag to
do {
    let cat = UUID()
    let projects = [Project(name: "NOCIONS", categoryID: cat),
                    Project(name: "NOTES", categoryID: cat),
                    Project(name: "PAPER", categoryID: cat)]

    /// The field's rule, as a function: the tag still being typed, and the
    /// project Tab would take.
    func completion(_ typed: String) -> String? {
        guard let token = ProjectToken.find(in: typed), !token.isFinished,
              !token.query.isEmpty else { return nil }
        return ProjectSuggestions.rank(projects, query: token.query, lastUsed: [:]).first?.name
    }

    expect(completion("#NOC") == "NOCIONS", "half a name reaches the whole one")
    expect(completion("#noc") == "NOCIONS", "case is not part of the question")
    expect(completion("#NO") == "NOCIONS",
           "and where two could match, the ranking decides — prefix, then recency")
    expect(completion("#XYZ") == nil, "nothing matching, nothing to complete to")
    expect(completion("#") == nil, "and a bare hash is not a question yet")
    expect(completion("#NOCIONS book flights") == nil,
           "a tag already finished by a space is not completed again")

    // The bug: a tab left in the text is whitespace, and whitespace finishes a
    // tag. Pressing Tab on "#NOC" committed a project called NOC rather than
    // completing it, because the key arrives as a character and nothing
    // stripped it first.
    let withTab = ProjectToken.find(in: "#NOC\t")
    expect(withTab?.isFinished == true && withTab?.query == "NOC",
           "which is why the tab has to come out of the text before it is read")
    expect(completion("#NOC\t".replacingOccurrences(of: "\t", with: "")) == "NOCIONS",
           "with it gone, the half-typed name completes as it should")
}

// MARK: Project drag destinations share the menu's filing rules
do {
    let source = UUID(), destination = UUID()
    let project = Project(name: "PAPER", categoryID: source, group: "Research")
    let open = TodoItem(title: "Draft", categoryID: source, projectID: project.id)
    let done = TodoItem(title: "Outline", bucket: .completed, categoryID: source, projectID: project.id)
    let unrelated = TodoItem(title: "Other", categoryID: source, projectID: UUID())
    let cards = [open, done, unrelated]

    expect(ProjectFiling.move(project, toCategory: source, group: "research", cards: cards) == nil,
           "dropping into the same group is a no-op, including case variants")
    let regroup = ProjectFiling.move(project, toCategory: source, group: "Clients", cards: cards)
    expect(regroup?.group == "Clients" && regroup?.cards == 0,
           "a group move leaves card categories alone")
    let ungroup = ProjectFiling.move(project, toCategory: source, group: nil, cards: cards)
    expect(ungroup != nil && ungroup?.group == nil && ungroup?.cards == 0,
           "dropping on the current category removes the group without moving cards")
    let across = ProjectFiling.move(project, toCategory: destination, group: "Clients", cards: cards)
    expect(across?.categoryID == destination && across?.group == "Clients" && across?.cards == 2,
           "a group in another category moves open and completed cards, excluding other projects")
    let category = ProjectFiling.move(project, toCategory: destination, group: nil, cards: cards)
    expect(category?.categoryID == destination && category?.group == nil && category?.cards == 2,
           "a category target clears the group and asks about affected cards")
    let empty = ProjectFiling.move(project, toCategory: destination, group: nil, cards: [])
    expect(empty?.cards == 0, "an empty project can move without card confirmation")
}

// MARK: A confirmed sidebar move uses current data and one edit timestamp
do {
    let source = CardCategory(label: "Source", symbolName: "folder", color: .purple)
    let target = CardCategory(label: "Target", symbolName: "folder", color: .purple)
    let categories = [source, target]
    let stamp = Date(timeIntervalSince1970: 1000)
    let project = Project(name: "PAPER", categoryID: source.id, group: "Drafts")
    let neighbor = Project(name: "BOOK", categoryID: target.id, group: "Clients")
    let open = TodoItem(title: "Draft", categoryID: source.id, projectID: project.id,
                        remindAt: stamp, deadline: stamp.addingTimeInterval(100))
    let done = TodoItem(title: "Outline", bucket: .completed, categoryID: source.id, projectID: project.id)
    let unrelated = TodoItem(title: "Other", categoryID: source.id)
    var projects = [project, neighbor]
    var cards = [open, done, unrelated]

    expect(ProjectFiling.apply(projectID: project.id, toCategory: target.id, group: " clients ",
                               projects: &projects, cards: &cards, categories: categories, now: stamp),
           "a complete move applies category and group together")
    expect(projects[0].categoryID == target.id && projects[0].group == "Clients",
           "the final destination uses the existing group's spelling")
    expect(projects[0].modifiedAt == stamp && cards[0].modifiedAt == stamp && cards[1].modifiedAt == stamp,
           "project and affected cards carry one edit timestamp")
    expect(cards[0].categoryID == target.id && cards[1].categoryID == target.id,
           "both open and completed cards follow the project")
    expect(cards[0].remindAt == open.remindAt && cards[0].deadline == open.deadline && cards[1].isCompleted,
           "refiling preserves dates and completion")
    expect(projects[1] == neighbor && cards[2] == unrelated, "unrelated data is untouched")

    let filedProjects = projects, filedCards = cards
    expect(!ProjectFiling.apply(projectID: project.id, toCategory: target.id, group: "clients",
                                projects: &projects, cards: &cards, categories: categories,
                                now: stamp.addingTimeInterval(1)), "an already-applied move does nothing")
    expect(projects == filedProjects && cards == filedCards, "a repeated confirmation stamps nothing")

    // The destination disappeared through sync while the confirmation was open.
    expect(!ProjectFiling.apply(projectID: project.id, toCategory: source.id, group: nil,
                                projects: &projects, cards: &cards, categories: [target], now: stamp),
           "a deleted destination rejects the pending move")
    expect(projects == filedProjects && cards == filedCards, "a deleted destination cannot orphan cards")

    projects.removeFirst()
    let remaining = projects
    expect(!ProjectFiling.apply(projectID: project.id, toCategory: source.id, group: nil,
                                projects: &projects, cards: &cards, categories: categories, now: stamp),
           "a deleted project rejects the pending move")
    expect(projects == remaining && cards == filedCards, "a deleted project cannot move any remaining cards")

    // An old menu snapshot says Source, but the live project is now in Target.
    projects = filedProjects
    expect(ProjectFiling.apply(projectID: project.id, toCategory: source.id, group: nil,
                               projects: &projects, cards: &cards, categories: categories, now: stamp),
           "the current category, rather than the menu snapshot, decides the move")
    expect(projects[0].categoryID == source.id && projects[0].group == nil && cards[0].categoryID == source.id,
           "a move back to the snapshot's category still refiles the live project and cards")
    let beforeRegroup = cards
    expect(ProjectFiling.apply(projectID: project.id, toCategory: source.id, group: "New group",
                               projects: &projects, cards: &cards, categories: categories, now: stamp),
           "a same-category regroup applies")
    expect(cards == beforeRegroup, "a same-category regroup never edits card timestamps")
}

// MARK: — which projects the filter shows
do {
    let live = Project(name: "LIVE")
    let done = Project(name: "DONE")
    let put = Project(name: "PUT", isArchived: true)
    let all = [live, done, put]
    // DONE is open but has nothing left to do; PUT is archived.
    let open = [live.id: 3, done.id: 0, put.id: 2]
    func names(_ scope: ProjectScope, pinned: Set<UUID> = []) -> [String] {
        scope.select(all, openCards: { open[$0.id] ?? 0 }, pinned: pinned).map(\.name).sorted()
    }

    expect(names(.unfinished) == ["LIVE"],
           "with open tasks leaves out the archived one and the finished one")
    expect(names(.active) == ["DONE", "LIVE"],
           "not archived keeps a project whose tasks are all done")
    expect(names(.all) == ["DONE", "LIVE", "PUT"], "all projects shows every one")
    expect(names(.archived) == ["PUT"], "archived shows only the put-away ones")

    // A project filtering the card list must stay on screen whatever the
    // scope says, or the cards shown would have no visible reason to be.
    expect(names(.unfinished, pinned: [put.id]) == ["LIVE", "PUT"],
           "a selected archived project survives a scope that excludes it")
    expect(names(.archived, pinned: [done.id]) == ["DONE", "PUT"],
           "a selected finished project survives the archived scope")
    expect(names(.unfinished, pinned: [live.id]) == ["LIVE"],
           "pinning a project the scope already shows does not duplicate it")

    expect(ProjectScope(rawValue: "active") == .active,
           "the stored scope decodes, so a remembered choice survives a launch")
}

// MARK: — the timeline of finished work
do {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    func at(_ text: String) -> Date {
        let f = DateFormatter()
        f.calendar = cal; f.timeZone = cal.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: text)!
    }
    func done(_ stamp: String, _ title: String = "x") -> TodoItem {
        var c = TodoItem(title: title)
        c.bucket = .completed
        c.completedAt = at(stamp)
        return c
    }
    // Two days in October, one in August, plus noise that must not appear.
    var open = TodoItem(title: "still going")
    var untimed = TodoItem(title: "unticked but stamped")
    untimed.completedAt = at("2026-10-05 09:00")      // not in the completed bucket
    let cards = [done("2026-10-20 09:00", "a"), done("2026-10-20 17:00", "b"),
                 done("2026-10-02 09:00", "c"),
                 done("2026-08-14 09:00", "d"),
                 open, untimed]

    let months = Timeline.months(of: cards, calendar: cal)
    expect(months.count == 2, "months with nothing finished are left out entirely")
    expect(months.map(\.completedCount) == [3, 1], "newest month first, counting its own days")
    expect(months[0].days.map(\.cards.count) == [2, 1], "days within a month run newest first")
    expect(months[0].days[0].cards.map(\.title) == ["b", "a"],
           "and the cards within a day run newest-finished first")
    expect(!months.flatMap(\.days).flatMap(\.cards).contains { $0.title == "still going" },
           "an unfinished task is not on the timeline")
    expect(!months.flatMap(\.days).flatMap(\.cards).contains { $0.title == "unticked but stamped" },
           "nor is one that was un-completed but kept its stamp")

    expect(Timeline.busiestDay(in: months) == 2, "the bars scale to the busiest day anywhere")
    expect(Timeline.busiestDay(in: []) == 0, "and an empty timeline has no busiest day")
    expect(Timeline.months(of: [open], calendar: cal).isEmpty,
           "a project with nothing finished has no timeline at all")

    // The month key is the first of the month at midnight, so two cards in the
    // same month always land in one bucket whatever time of day they carry.
    let spread = [done("2026-10-01 00:30"), done("2026-10-31 23:30")]
    expect(Timeline.months(of: spread, calendar: cal).count == 1,
           "the ends of a month belong to the same month")
    expect(Timeline.months(of: spread, calendar: cal)[0].days.count == 2,
           "but to different days")
}

// MARK: — reading a stamp without a formatter
do {
    // The fast path must agree with Foundation exactly, or not answer at all.
    let precise: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    let whole: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    func foundation(_ text: String) -> Date? { precise.date(from: text) ?? whole.date(from: text) }

    // Every month against every day 1...31, across a leap year and a century
    // that is not one, with and without the fractional part. This is where
    // 30 February is settled: Foundation rolls it into March rather than
    // refusing it, so the arithmetic has to roll it the same way.
    var compared = 0, disagreed = 0, declined = 0
    for year in [1583, 1600, 1970, 1999, 2000, 2024, 2026, 2100] {
        for month in 1...12 {
            for day in 1...31 {
                for suffix in [".123Z", "Z", ".000Z", ".999Z"] {
                    let text = String(format: "%04d-%02d-%02dT13:45:07", year, month, day) + suffix
                    compared += 1
                    guard let fast = DocumentCoding.stamp(from: text) else { declined += 1; continue }
                    if fast != foundation(text) { disagreed += 1 }
                }
            }
        }
    }
    expect(compared > 8_000, "the sweep is wide enough to mean something")
    expect(declined == 0, "every well-formed stamp is answered by the fast path")
    expect(disagreed == 0, "and answered with exactly what Foundation would have said")

    // Midnight, the last second of a day, and the epoch itself.
    for text in ["1970-01-01T00:00:00.000Z", "2026-12-31T23:59:59.999Z", "2024-02-29T00:00:00.000Z"] {
        expect(DocumentCoding.stamp(from: text) == foundation(text), "boundary stamp \(text)")
    }

    // Anything else is handed back for the formatters to answer, not guessed at.
    for text in ["2026-09-26T09:15:00.123+02:00",   // an offset rather than Z
                 "2026-13-01T09:15:00.123Z",        // month 13
                 "2026-09-26T25:15:00.123Z",        // hour 25
                 "2026-09-26T09:60:00.123Z",        // minute 60
                 "2026-09-26T09:15:60.123Z",        // second 60
                 "2026-09-00T09:15:00.123Z",        // day 0
                 "2026-09-26T09:15:00.1234Z",       // too many digits
                 "2026-09-26T09:15:00.12Z",         // too few
                 "2026-09-26 09:15:00.123Z",        // a space for the T
                 "2026-09-26T09:15:00.123z",        // lower case
                 "0001-01-01T00:00:00.000Z",        // before the Gregorian reform
                 "1582-10-04T00:00:00.000Z",        // the day before it
                 "202X-09-26T09:15:00.123Z",        // not a number
                 "", "Z", "not a date at all"] {
        expect(DocumentCoding.stamp(from: text) == nil, "declines \(text.isEmpty ? "an empty string" : text)")
    }

    // `.distantPast` stamps every seeded row, and the encoder writes it as
    // 0001-01-01. Foundation reads that back through the Julian cutover, two
    // days from where proleptic arithmetic would put it, so the fast path has
    // to stand aside and let it — or a merge would stop seeing seeded data as
    // older than every real edit.
    expect(DocumentCoding.stamp(from: "0001-01-01T00:00:00.000Z") == nil,
           "the fast path declines a pre-Gregorian date rather than disagreeing about it")
    let seeded = StoreDocument(cards: [], projects: [])
    let seededBack = try! DocumentCoding.makeDecoder()
        .decode(StoreDocument.self, from: DocumentCoding.makeEncoder().encode(seeded))
    expect(seededBack.defaultCategoryChangedAt == seeded.defaultCategoryChangedAt,
           "so .distantPast still survives save and load exactly")

    // What matters in the end: a document still survives save and load.
    var card = TodoItem(title: "round trip")
    card.completedAt = Date(timeIntervalSince1970: 1_767_000_000.123)
    card.remindAt = Date(timeIntervalSince1970: 1_767_086_400)
    let doc = StoreDocument(cards: [card])
    let coded = try! DocumentCoding.makeDecoder()
        .decode(StoreDocument.self, from: DocumentCoding.makeEncoder().encode(doc))
    expect(coded == doc, "a document still survives save and load through the fast path")
}

// MARK: — what a card's menu offers
do {
    func menu(_ card: TodoItem, filtered: Bool = false, project: Bool = false) -> [CardMenu.Action] {
        CardMenu.actions(for: card, isFiltered: filtered, hasProject: project)
    }
    var plain = TodoItem(title: "plain"); plain.bucket = .tomorrow

    let moves = menu(plain).compactMap { if case .move(let b) = $0 { return b } else { return nil } }
    expect(!moves.contains(.tomorrow), "the stack a card is already in is not offered")
    expect(moves == Bucket.quickMoveTargets.filter { $0 != .tomorrow },
           "the others are offered in their usual order, and first")
    expect(menu(plain).last == .delete, "Delete is last wherever the menu is shown")
    expect(menu(plain, filtered: true, project: true).last == .delete, "and stays last")
    expect(menu(plain).dropLast().last == .edit,
           "with nothing to filter by, Edit is the last of the ordinary actions")
    expect(menu(plain).filter { $0 == .delete }.count == 1, "and is offered once, not twice")

    // Reminders add two, and only when they apply.
    expect(!menu(plain).contains(.snooze), "no reminder, nothing to snooze")
    expect(!menu(plain).contains(.clearReminder), "and nothing to clear")
    var reminded = TodoItem(title: "reminded")
    reminded.remindAt = Date().addingTimeInterval(60 * 60 * 24 * 7)
    expect(menu(reminded).contains(.clearReminder), "a reminder can always be cleared")
    expect(menu(reminded).contains(.snooze) == Reminders.canSnooze(reminded),
           "snooze follows the same rule the flag uses to gather the card")

    // Filtering is either/or, never both.
    expect(menu(plain, project: true).contains(.showOnlyProject),
           "a card with a project can narrow to it")
    expect(!menu(plain, project: true).contains(.showAll), "and is not also offered the way out")
    expect(menu(plain, filtered: true, project: true) .contains(.showAll),
           "while a filter is on, the useful move is back out of it")
    expect(!menu(plain, filtered: true, project: true).contains(.showOnlyProject),
           "and narrowing again is not offered")
    expect(menu(plain, filtered: true).contains(.showAll),
           "Show All is offered even with no project, since a category filter shows those too")
    expect(!menu(plain).contains(.showOnlyProject), "a card with no project cannot narrow to one")

    // Edit is always there: a menu that will move a card but not open it
    // reads as broken, which is why it is on every surface.
    for card in [plain, reminded] {
        for filtered in [true, false] {
            expect(menu(card, filtered: filtered, project: true).contains(.edit),
                   "Edit is offered whatever else is")
        }
    }
}

// MARK: — putting tasks back
do {
    let then = Date(timeIntervalSince1970: 1_700_000_000)
    let now  = Date(timeIntervalSince1970: 1_800_000_000)

    var card = TodoItem(title: "book the flights", bucket: .today)
    card.modifiedAt = then

    // Undoing an edit: the task is still there, so it is overwritten.
    var edited = card
    edited.bucket = .completed
    edited.completedAt = now
    edited.modifiedAt = now
    let afterEdit = StoreDocument(cards: [edited])
    let undone = afterEdit.restoring(Restoration(cards: [card]), now: now)
    expect(undone.cards.count == 1, "undoing an edit does not add a second copy")
    expect(undone.cards[0].bucket == .today, "the task is back in the stack it came from")
    expect(undone.cards[0].completedAt == nil, "and is no longer completed")
    expect(undone.cards[0].modifiedAt == now,
           "stamped now, not with the time it used to carry, or the other device wins")

    // Undoing a delete: the task is gone and its tombstone is standing.
    var afterDelete = StoreDocument(cards: [])
    afterDelete.deletedCards[card.id.uuidString] = now
    let revived = afterDelete.restoring(Restoration(cards: [card]), now: now)
    expect(revived.cards.map(\.id) == [card.id], "a deleted task comes back")
    expect(revived.deletedCards[card.id.uuidString] == nil,
           "and its tombstone goes, or this device hands the deletion back to everyone else")
    expect(revived.cards[0].modifiedAt > now,
           "stamped past the tombstone, because a merge gives a tie to the deletion")

    // The restored copy must beat the tombstone by the app's own merge rule.
    var tombstoned = StoreDocument(cards: [])
    tombstoned.deletedCards[card.id.uuidString] = now
    let merged = revived.merged(with: tombstoned)
    expect(merged.cards.map(\.id) == [card.id],
           "and survives a merge against a device that still thinks it was deleted")

    // Several at once, and a mix of present and absent.
    var other = TodoItem(title: "pack", bucket: .later)
    other.modifiedAt = then
    var doc = StoreDocument(cards: [other])
    doc.deletedCards[card.id.uuidString] = now
    let both = doc.restoring(Restoration(cards: [card, other]), now: now)
    expect(both.cards.count == 2, "one re-added and one overwritten, not duplicated")

    expect(StoreDocument.empty.restoring(Restoration(cards: []), now: now) == StoreDocument.empty,
           "restoring nothing changes nothing")
    expect(Restoration(cards: []).isEmpty, "and nothing is what an empty restoration holds")

    // A project move rewrites the project's row and its tasks together, so
    // undoing one without the other would leave them disagreeing.
    let research = UUID(), teaching = UUID()
    var project = Project(name: "FRIA", categoryID: research, group: "Grants")
    project.modifiedAt = then
    var task = TodoItem(title: "write the case", categoryID: research)
    task.projectID = project.id
    task.modifiedAt = then

    var moved = project
    moved.categoryID = teaching
    moved.group = nil
    moved.modifiedAt = now
    var movedTask = task
    movedTask.categoryID = teaching
    movedTask.modifiedAt = now

    let after = StoreDocument(cards: [movedTask], projects: [moved])
    let back = after.restoring(Restoration(cards: [task], projects: [project]), now: now)
    expect(back.projects[0].categoryID == research, "the project goes back to the category it came from")
    expect(back.projects[0].group == "Grants", "and back into the group the move took it out of")
    expect(back.cards[0].categoryID == research, "its tasks come back with it")
    expect(back.projects[0].modifiedAt == now && back.cards[0].modifiedAt == now,
           "both stamped now, so neither loses to the copy on another device")

    // Deleting a project is the same shape: tombstone out, row back.
    var afterDelete2 = StoreDocument(cards: [], projects: [])
    afterDelete2.deletedProjects[project.id.uuidString] = now
    let revivedProject = afterDelete2.restoring(Restoration(projects: [project]), now: now)
    expect(revivedProject.projects.map(\.id) == [project.id], "a deleted project comes back")
    expect(revivedProject.deletedProjects[project.id.uuidString] == nil, "and loses its tombstone")
    expect(revivedProject.projects[0].modifiedAt > now,
           "stamped past the tombstone, for the same reason a task is")
}

// MARK: One-time Reminders import — a pure plan, without opening app data
do {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Europe/Brussels")!
    let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 12))!
    let due = cal.date(from: DateComponents(year: 2026, month: 10, day: 26))!
    let original = TodoItem(title: "Already here")
    let category = CardCategory(label: "Home", symbolName: "house", color: .teal)
    let existing = Project(name: "HOUSE", categoryID: category.id)
    let doc = StoreDocument(categories: [category], cards: [original], projects: [existing])
    let record = TaskImportRecord(id: "r1", listID: "l1", title: "#Keep title literally",
                                     notes: "  Notes, with a \"quote\"\nand a second line.  ",
                                     dueDate: due, createdAt: now.addingTimeInterval(-86400))
    var options = TaskImport.Options(destinations: ["l1": .init(projectID: existing.id)])
    let plan = try! TaskImport.plan(records: [record], options: options, document: doc, now: now, calendar: cal)
    let card = plan.document.cards.last!
    expect(plan.added == 1 && plan.document.cards.count == 2, "import adds without replacing existing tasks")
    expect(plan.document.cards.first == original && doc.cards == [original], "planning does not edit existing tasks or its input")
    expect(card.title == record.title && card.notes == record.notes, "source titles and multiline notes are preserved literally")
    expect(card.projectID == existing.id && card.categoryID == category.id, "an explicit project brings its category")
    expect(card.bucket == .inbox, "import defaults to Inbox")
    expect(card.remindAt == Scheduler.reminderTime(on: due, calendar: cal) && card.deadline == nil,
           "due dates map to a 9am reminder, never a deadline or automatic stack move")
    expect(card.reminderAnsweredAt == nil, "a future reminder remains unanswered")
    expect(card.createdAt == record.createdAt && card.modifiedAt == now, "creation is preserved while import is a new edit")
    expect(plan.document.importedReminderIDs.contains("apple-reminders:r1"), "the successful import records its source identifier")
    let again = try! TaskImport.plan(records: [record, record], options: options, document: plan.document, now: now, calendar: cal)
    expect(again.added == 0 && again.duplicates == 2, "reimport skips already imported identifiers")
    var deleted = plan.document
    deleted.cards.removeLast()
    deleted.deletedCards[card.id.uuidString] = now
    let afterDelete = try! TaskImport.plan(records: [record], options: options, document: deleted, now: now)
    expect(afterDelete.added == 0 && afterDelete.document.cards == [original], "reimport does not resurrect a deleted imported task")
    let twice = try! TaskImport.plan(records: [record, record], options: options, document: doc, now: now)
    expect(twice.added == 1 && twice.duplicates == 1, "duplicate identifiers within a batch only import once")
    var sameTitle = record; sameTitle.id = "r2"
    let separate = try! TaskImport.plan(records: [record, sameTitle], options: options, document: doc, now: now)
    expect(separate.added == 2, "equal titles with different source identifiers remain separate tasks")
    let unselected = try! TaskImport.plan(records: [record], options: .init(), document: doc, now: now)
    expect(unselected.document == doc && unselected.added == 0, "an unselected list changes nothing")
    options.excludedIDs.insert(record.id)
    let excluded = try! TaskImport.plan(records: [record], options: options, document: doc, now: now)
    expect(excluded.added == 0 && excluded.skipped == 1 && excluded.document == doc, "excluded records leave no import marker or empty project")
    options.excludedIDs = []
    var recurring = record; recurring.isRecurring = true
    let recurrence = try! TaskImport.plan(records: [recurring], options: options, document: doc, now: now)
    expect(recurrence.added == 0 && recurrence.skipped == 1, "recurring reminders are not silently converted to one-off tasks")
    var completed = record; completed.isCompleted = true
    let finishedOff = try! TaskImport.plan(records: [completed], options: options, document: doc, now: now)
    expect(finishedOff.added == 0, "completed tasks require an explicit opt-in")
    options.includeCompleted = true
    options.bucket = .waiting
    let finished = try! TaskImport.plan(records: [completed], options: options, document: doc, now: now)
    expect(finished.document.cards.last?.bucket == .completed && finished.document.cards.last?.completedAt == nil,
           "an unknown completion time is not fabricated")
    expect(finished.document.cards.last?.bucketBeforeCompletion == .waiting, "reopening imported completed tasks restores the chosen stack")
    completed.completedAt = now.addingTimeInterval(-3600)
    let datedFinished = try! TaskImport.plan(records: [completed], options: options, document: doc, now: now)
    expect(datedFinished.document.cards.last?.completedAt == completed.completedAt, "a known completion date survives")
    options.importDates = false
    let noDates = try! TaskImport.plan(records: [record], options: options, document: doc, now: now)
    expect(noDates.document.cards.last?.remindAt == nil && noDates.document.cards.last?.notes == record.notes,
           "dates can stay only in notes")
    options.importDates = true
    var past = record; past.dueDate = now.addingTimeInterval(-86400)
    let pastPlan = try! TaskImport.plan(records: [past], options: options, document: doc, now: now)
    expect(pastPlan.document.cards.last?.reminderAnsweredAt == pastPlan.document.cards.last?.remindAt,
           "past imported reminders arrive answered instead of generating a notification backlog")
    var blank = record; blank.title = " \n "
    let blankPlan = try! TaskImport.plan(records: [blank], options: options, document: doc, now: now)
    expect(blankPlan.added == 0 && blankPlan.skipped == 1, "empty titles are reported and skipped")
    options.destinations = ["l1": .init(categoryID: category.id, newProjectName: "Garden work")]
    let newProject = try! TaskImport.plan(records: [record], options: options, document: doc, now: now)
    expect(newProject.projectsCreated == 1 && newProject.document.projects.last?.name == "GARDENWORK",
           "new projects use DayHand's canonical names")
    expect(newProject.document.projects.last?.modifiedAt == now && newProject.document.cards.last?.categoryID == category.id,
           "a new project's category and edit stamp are explicit")
    var otherList = sameTitle; otherList.listID = "l2"
    options.destinations["l2"] = options.destinations["l1"]
    let shared = try! TaskImport.plan(records: [record, otherList], options: options, document: doc, now: now)
    expect(shared.projectsCreated == 1 && shared.added == 2, "two lists can intentionally share a newly named project")
    options.destinations = ["l1": .init(newProjectName: "house")]
    do {
        _ = try TaskImport.plan(records: [record], options: options, document: doc, now: now)
        expect(false, "a new-project name collision must be explicit")
    } catch { expect(error is TaskImportFailure, "name collision is reported without modifying an existing project") }
    options.destinations = ["l1": .init(projectID: UUID())]
    do {
        _ = try TaskImport.plan(records: [record], options: options, document: doc, now: now)
        expect(false, "a disappeared project cannot be imported into")
    } catch { expect(error is TaskImportFailure, "a stale destination is rejected") }
    options.destinations = ["l1": .init(categoryID: UUID())]
    do {
        _ = try TaskImport.plan(records: [record], options: options, document: doc, now: now)
        expect(false, "a disappeared category cannot be imported into")
    } catch { expect(error is TaskImportFailure, "a stale category is rejected") }
    let roundTrip = try! DocumentCoding.makeDecoder().decode(StoreDocument.self,
        from: DocumentCoding.makeEncoder().encode(plan.document))
    expect(roundTrip == plan.document, "import notes and identifiers survive document save/load")
    let merged = deleted.merged(with: doc)
    expect(merged.importedReminderIDs == deleted.importedReminderIDs, "sync with an older document retains import history")
    var remote = doc; remote.importedReminderIDs.insert("apple-reminders:remote")
    expect(deleted.merged(with: remote).importedReminderIDs == ["apple-reminders:r1", "apple-reminders:remote"],
           "import history merges by union")
    let old = try! DocumentCoding.makeDecoder().decode(StoreDocument.self, from: Data("{\"cards\":[{\"title\":\"old\"}]}".utf8))
    expect(old.cards.first?.notes == "" && old.importedReminderIDs.isEmpty, "old documents decode without notes or import history")
    let csv = CardCSV.export(cards: [card], categories: [category], projects: [existing])
    expect(CardCSV.parse(csv, categories: [category]).cards.first?.notes == record.notes, "multiline quoted notes survive CSV export/import")
    var losAngeles = Calendar(identifier: .gregorian)
    losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    let allDay = DateComponents(year: 2026, month: 10, day: 25)
    let local = TaskImport.date(from: allDay, calendar: losAngeles)!
    expect(losAngeles.component(.day, from: local) == 25 && losAngeles.component(.hour, from: local) == 0,
           "floating date-only reminders stay on the source day west of UTC")
    let dstDay = TaskImport.date(from: allDay, calendar: cal)!
    expect(cal.component(.day, from: dstDay) == 25 && cal.component(.hour, from: Scheduler.reminderTime(on: dstDay, calendar: cal)) == 9,
           "date-only reminders still become 9am on a daylight-saving transition")
    expect(TaskImport.date(from: nil) == nil && TaskImport.date(from: DateComponents(hour: 9)) == nil,
           "missing or partial dates stay absent")
}


// MARK: Todoist CSV imports — documented export format and the official template
do {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Europe/Brussels")!
    let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 12))!
    let fixtureURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures/todoist-official-template.csv")
    let fixture = try! String(contentsOf: fixtureURL, encoding: .utf8)
    let file = try! TodoistCSV.parse(fixture, fileID: "official", name: "Example.csv", calendar: cal)
    expect(file.records.count == 4 && file.ignoredRows == 0, "Todoist's official CSV template yields four tasks without importing metadata as tasks")
    expect(file.unparsedDateIDs.count == 3, "relative and recurring expressions in the official template need review")
    expect(file.records[0].notes.contains("Only available on Tuesdays and Thursdays"), "comment rows attach to the preceding task")
    expect(file.records[1].deadlineDate != nil && file.records[1].dueDate == nil, "the official template has a real deadline without a reminder")
    expect(file.records[2].notes.contains("Parent task: **Household chores**:"), "subtask parent context is retained in Notes")
    let options = TaskImport.Options(destinations: [file.id: TaskImportDestination()], bucket: .later)
    let baseline = StoreDocument(cards: [TodoItem(title: "Existing")])
    let safe = try! TodoistCSV.plan(files: [file], options: options, includeUnparsedDates: false,
                                   document: baseline, now: now, calendar: cal)
    expect(safe.added == 1 && safe.skipped == 3, "unrecognised and recurring dates are excluded until opted in")
    expect(safe.document.cards.last?.bucket == .later && safe.document.cards.first == baseline.cards.first,
           "Todoist import respects the selected stack and leaves existing tasks unchanged")
    expect(safe.document.cards.last?.deadline != nil && safe.document.cards.last?.remindAt == nil,
           "an explicit deadline imports as a deadline without inventing a reminder")
    let reloaded = try! DocumentCoding.makeDecoder().decode(StoreDocument.self,
        from: DocumentCoding.makeEncoder().encode(safe.document)).promotingOrphanDeadlines(now: now, calendar: cal)
    expect(reloaded == safe.document, "explicit modern deadlines and import history survive reload and legacy migration")
    expect(safe.document.importedReminderIDs.isEmpty && safe.document.importedTodoistIDs.count == 1,
           "Todoist history is separate from Apple Reminders history")
    let all = try! TodoistCSV.plan(files: [file], options: options, includeUnparsedDates: true,
                                  document: baseline, now: now, calendar: cal)
    expect(all.added == 4 && all.document.cards.filter { $0.remindAt != nil }.isEmpty,
           "opting in imports unsupported date expressions once without inventing schedules")
    expect(all.document.cards.contains { $0.notes.contains("every Friday") }, "recurring source text is retained in Notes")
    let savedText = String(data: try! DocumentCoding.makeEncoder().encode(all.document), encoding: .utf8)!
    let savedCSV = CardCSV.export(cards: all.document.cards, categories: [])
    expect(savedText.contains("every Friday") && savedText.contains("Only available on Tuesdays") && savedCSV.contains("Only available on Tuesdays"),
           "Todoist date text and comments persist in the existing Notes field and CSV")
    let persisted = try! DocumentCoding.makeDecoder().decode(StoreDocument.self,
        from: DocumentCoding.makeEncoder().encode(all.document))
    expect(persisted.cards.map(\.notes) == all.document.cards.map(\.notes),
           "imported descriptions, comments and metadata survive save/load without duplication")
    let repeatPlan = try! TodoistCSV.plan(files: [file], options: options, includeUnparsedDates: true,
                                         document: all.document, now: now, calendar: cal)
    expect(repeatPlan.added == 0 && repeatPlan.duplicates == 4, "unchanged files do not import their tasks twice")
    var editedNotes = all.document
    editedNotes.cards[1].notes = "Notes edited in DayHand"
    let repeatedEdited = try! TodoistCSV.plan(files: [file], options: options, includeUnparsedDates: true,
                                             document: editedNotes, now: now, calendar: cal)
    expect(repeatedEdited.document.cards[1].notes == "Notes edited in DayHand" && repeatedEdited.added == 0,
           "repeat import never overwrites Notes edited in DayHand")
    let csvBack = CardCSV.parse(CardCSV.export(cards: all.document.cards, categories: []), categories: [])
    expect(csvBack.cards.map(\.notes) == all.document.cards.map(\.notes),
           "Todoist descriptions, comments and source metadata survive CSV export and import")
    var deleted = all.document
    deleted.cards.removeLast()
    let afterDelete = try! TodoistCSV.plan(files: [file], options: options, includeUnparsedDates: true,
                                         document: deleted, now: now, calendar: cal)
    expect(afterDelete.added == 0 && afterDelete.document.cards == deleted.cards, "deleted imported tasks are not resurrected by repeat imports")
    expect(all.document.merged(with: baseline).importedTodoistIDs == all.document.importedTodoistIDs,
           "Todoist import history survives merging an older document")
    var otherHistory = baseline; otherHistory.importedTodoistIDs.insert("remote:1")
    expect(all.document.merged(with: otherHistory).importedTodoistIDs.count == 5,
           "Todoist import history merges by union")
    var noDates = options; noDates.importDates = false
    let without = try! TodoistCSV.plan(files: [file], options: noDates, includeUnparsedDates: true,
                                      document: baseline, now: now, calendar: cal)
    expect(without.document.cards.allSatisfy { $0.remindAt == nil && $0.deadline == nil },
           "turning dates off omits both dates while retaining their source text in Notes")
    var excluded = options; excluded.excludedIDs.insert(file.records[1].id)
    let subset = try! TodoistCSV.plan(files: [file], options: excluded, includeUnparsedDates: true,
                                     document: baseline, now: now, calendar: cal)
    expect(subset.added == 3 && !subset.document.importedTodoistIDs.contains("todoist-csv:" + file.records[1].id),
           "individual exclusions do not get recorded as imported")
    let unselected = try! TodoistCSV.plan(files: [file], options: .init(), includeUnparsedDates: true,
                                         document: baseline, now: now, calendar: cal)
    expect(unselected.document == baseline, "unselected files change nothing")
    let quoted = "\u{FEFF}DESCRIPTION,CONTENT,TYPE,INDENT,DATE,DEADLINE,TIMEZONE\r\n\"Line one\nLine two, \"\"quoted\"\"\",@keep label,task,1,2026-10-26 10:30,2026-10-29,Europe/Brussels\r\n"
    let parsed = try! TodoistCSV.parse(quoted, fileID: "quoted", name: "Quoted.csv", calendar: cal)
    expect(parsed.records.count == 1 && parsed.records[0].notes.contains("Line two, \"quoted\""),
           "BOM, reordered headers, CRLF, multiline fields, commas and escaped quotes parse correctly")
    expect(parsed.records[0].title == "@keep label", "labels and original titles are not stripped or reinterpreted")
    expect(parsed.unparsedDateIDs.isEmpty && parsed.records[0].dueDate != nil && parsed.records[0].deadlineDate != nil,
           "absolute dates and time zones are recognised independently from deadlines")
    let mappedOptions = TaskImport.Options(destinations: [parsed.id: .init()])
    let mapped = try! TodoistCSV.plan(files: [parsed], options: mappedOptions, includeUnparsedDates: false,
                                     document: .empty, now: now, calendar: cal)
    expect(cal.component(.hour, from: mapped.document.cards[0].remindAt!) == 9,
           "recognised task times map to DayHand's standard 9am reminder")
    expect(mapped.document.cards[0].deadline == cal.date(from: DateComponents(year: 2026, month: 10, day: 29)),
           "a recognised deadline retains its civil day")
    let hierarchy = "TYPE,CONTENT,INDENT,DESCRIPTION\ntask,Root,1,\ntask,Child,2,\ntask,Grandchild,3,\nnote,First comment,,\ntask,Sibling,2,\nsection,New section,,Section description\nnote,Orphan comment,,\ntask,Next root,1,\nunknown,Unsupported,,\nnote,Another orphan,,\n"
    let tree = try! TodoistCSV.parse(hierarchy, fileID: "tree", name: "Tree.csv")
    expect(tree.records[2].notes.contains("Root › Child") && tree.records[2].notes.contains("First comment"),
           "nested parents and comments follow CSV order")
    expect(tree.records[3].notes.contains("Parent task: Root") && !tree.records[3].notes.contains("Root › Child"),
           "a sibling is attached to the correct parent")
    expect(tree.records[4].notes.contains("Section: New section") && tree.records[4].notes.contains("Section description"),
           "section context and its description are preserved")
    expect(!tree.records[4].notes.contains("Parent task:") && !tree.records[4].notes.contains("Orphan"),
           "section boundaries reset hierarchy and orphan comments never attach to another task")
    expect(tree.ignoredRows == 3, "unsupported and orphan note rows are counted explicitly")
    let badDates = try! TodoistCSV.parse("TYPE,CONTENT,DATE,DEADLINE,TIMEZONE\ntask,Impossible,2026-02-30,,\ntask,French,demain,,\ntask,Bad zone,2026-10-26,,Invalid/Zone\n", fileID: "bad", name: "Dates.csv")
    expect(badDates.unparsedDateIDs.count == 3, "invalid dates, natural-language dates and unknown time zones need explicit review")
    expect(TodoistCSV.date("2026-10-25T13:30:00Z") != nil && TodoistCSV.date("2026-10-25T13:30:00.123+02:00") != nil,
           "ISO timestamps with offsets and fractional seconds are accepted")
    expect(TodoistCSV.date("25/10/2026") == nil && TodoistCSV.date("2026-10-25 tomorrow") == nil,
           "ambiguous or partially parsed dates are never guessed")
    expect(TodoistCSV.date("2026-02-30T13:00:00Z") == nil,
           "invalid ISO civil dates are not silently rolled into the following month")
    for bad in ["", "title,notes\nOther format,Note", "TYPE,CONTENT,CONTENT\ntask,A,A", "TYPE,CONTENT\ntask,\"unterminated", "TYPE,CONTENT\ntask,\"closed\"junk", "TYPE,CONTENT\ntask,a\"b", "TYPE,CONTENT\ntask,A,unexpected"] {
        do { _ = try TodoistCSV.parse(bad, fileID: "bad", name: "Bad.csv"); expect(false, "invalid Todoist CSV must be rejected") }
        catch { expect(error is TodoistCSV.Failure, "malformed CSV is rejected before any import") }
    }
    let empty = try! TodoistCSV.parse("TYPE,CONTENT\nmeta,view_style=list\nsection,Empty\n", fileID: "empty", name: "Empty.csv")
    expect(empty.records.isEmpty, "empty projects have no invented tasks")
    let emptyPlan = try! TodoistCSV.plan(files: [empty], options: .init(destinations: [empty.id: .init(newProjectName: "EMPTY")]),
        includeUnparsedDates: true, document: baseline)
    expect(emptyPlan.document == baseline && emptyPlan.projectsCreated == 0, "empty projects create no destination and make no changes")
    let legacy = CardCSV.parse("title,due\nOld,2026-10-26\n", categories: [])
    let modern = CardCSV.parse("title,deadline\nNew,2026-10-26\n", categories: [])
    expect(StoreDocument(cards: legacy.cards).promotingOrphanDeadlines().cards[0].remindAt != nil,
           "old due-column CSV dates still migrate to reminders")
    expect(StoreDocument(cards: modern.cards).promotingOrphanDeadlines().cards[0].remindAt == nil,
           "explicit modern CSV deadlines survive migration")
}

// MARK: — how long a task has been sitting in its stack
do {
    let enc = DocumentCoding.makeEncoder(), dec = DocumentCoding.makeDecoder()
    let made = Date(timeIntervalSince1970: 1_700_000_000)

    // A file written before the field existed knows nothing about moves. The
    // day the task was made is the one honest answer; falling back to *now*
    // would have every task claim it had just arrived.
    let old = #"{"cards":[{"id":"\#(UUID().uuidString)","title":"x","bucket":"later","createdAt":"2023-11-14T22:13:20.000Z"}],"categories":[]}"#
    let loaded = try! dec.decode(StoreDocument.self, from: Data(old.utf8))
    expect(loaded.cards[0].enteredStackAt == loaded.cards[0].createdAt,
           "an older file falls back to when the task was made, not to now")

    // A real value survives a round trip.
    var card = TodoItem(title: "sitting", bucket: .later)
    card.createdAt = made
    card.enteredStackAt = Date(timeIntervalSince1970: 1_750_000_000)
    let back = try! dec.decode(StoreDocument.self, from: try! enc.encode(StoreDocument(cards: [card])))
    expect(back.cards[0].enteredStackAt == card.enteredStackAt,
           "and a known arrival survives save and load")
    expect(back.cards[0].enteredStackAt != back.cards[0].createdAt,
           "without collapsing back onto createdAt")

    // The CSV carries it too, or exporting and re-importing would reset every
    // task to today — and tasks are matched by id, so that would overwrite.
    let cat = CardCategory(label: "Home", symbolName: "house", color: .teal)
    let text = CardCSV.export(cards: [card], categories: [cat], projects: [])
    let parsed = CardCSV.parse(text, categories: [cat])
    expect(parsed.cards.count == 1, "the row comes back")
    expect(parsed.cards[0].enteredStackAt == card.enteredStackAt,
           "and carries the arrival through a CSV round trip")

    // An export written before the column existed must not reset anything.
    let headerless = "id,title,stack,created\n\(card.id.uuidString),x,later,2023-11-14T22:13:20.000Z"
    let older = CardCSV.parse(headerless, categories: [cat])
    expect(older.cards[0].enteredStackAt == older.cards[0].createdAt,
           "a CSV with no entered column falls back to created, not to now")
}

print(failures == 0 ? "All \(checks) assertions passed." : "\(failures) of \(checks) failed.")
exit(failures == 0 ? 0 : 1)
