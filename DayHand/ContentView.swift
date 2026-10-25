import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: TodoStore

    /// The card whose stack is being picked, from a tap.
    @State private var stackPickItem: TodoItem?
    /// The card being edited in full, from a right swipe.
    @State private var editItem: TodoItem?
    @State private var isAdding = false
    @State private var isShowingSettings = false
    /// Narrows the list to the cards asking for attention, so they can be dealt
    /// with among their own stacks rather than in a sheet.
    @State private var attentionOnly = false
    /// When the More popover last closed, so the click that dismissed it is not
    /// also read as a click asking for it back.
    @State private var settingsDismissedAt: Date?
    /// Both empty shows every card; otherwise a card shows if it carries any of
    /// the chosen categories or projects.
    @State private var filterCategoryIDs: Set<UUID> = []
    @State private var filterProjectIDs: Set<UUID> = []
    @State private var isFiltering = false

    /// How many completed cards are on screen. "More…" reveals another page.
    @State private var completedShown = Self.completedPageSize
    private static let completedPageSize = 20

    /// Set once the list has been parked on TODAY, so it only happens on launch.
    @State private var didAnchorToToday = false

    /// The search bar, and what is typed in it. Both empty means not searching:
    /// closing the bar clears the query, so the list is never quietly narrowed
    /// by something that is no longer on screen.
    @State private var isSearching = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    /// Whether the sidebar is open, so the filter button can always bring it
    /// back. The detail column has no navigation bar to hang a toggle in.
    ///
    /// Closed to begin with, and on every launch: the cards are what the app is
    /// for, and a permanent column of machinery beside them is exactly the
    /// clutter this app does without. The filter button opens it when it is
    /// wanted.
    @State private var columns: NavigationSplitViewVisibility = .detailOnly

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// A window wide enough to keep the filter beside the cards rather than on
    /// top of them: the Mac always, an iPad unless it is sharing the screen.
    /// Never a phone — a Max in landscape is horizontally regular too, and a
    /// sidebar there would crowd the cards it exists to explain.
    /// A pointer can click outside a menu to be rid of it, and expects to. The
    /// phone keeps the system's action sheet, which already does that and is
    /// the right shape for a thumb.
    private var usesPopoverMenus: Bool {
        UIDevice.current.userInterfaceIdiom != .phone
    }

    /// How far the corner buttons sit below the titlebar.
    ///
    /// They used to be lifted *into* that strip, level with the traffic
    /// lights, and it looked right — but the strip is the window's drag
    /// region, and a control behind it never receives the click. There is no
    /// public way to carve a hole in it; putting them up there for real means
    /// an `NSToolbar`. Until then they sit just under it, which works.
    #if targetEnvironment(macCatalyst)
    private static let topControlInset: CGFloat = 4
    #else
    private static let topControlInset: CGFloat = 6
    #endif

    private var showsSidebar: Bool {
        horizontalSizeClass == .regular && UIDevice.current.userInterfaceIdiom != .phone
    }

    @ViewBuilder
    var body: some View {
        if showsSidebar {
            // Choosing a project and seeing the cards change are the same
            // moment, not two — the whole point of the filter is the list
            // behind it, which a sheet covers up.
            NavigationSplitView(columnVisibility: $columns) {
                FilterList(
                    categorySelection: $filterCategoryIDs.animation(.easeInOut(duration: 0.2)),
                    projectSelection: $filterProjectIDs.animation(.easeInOut(duration: 0.2)),
                    isSidebar: true
                )
                .navigationTitle("Organise")
                // The system's own toggle sits at the far right of the sidebar
                // header, and floats over the first card when the sidebar is
                // closed. The filter button already opens and closes it, from
                // the corner this app keeps its controls in.
                .toolbar(removing: .sidebarToggle)
            } detail: {
                stack
            }
            .navigationSplitViewStyle(.balanced)
        } else {
            stack
        }
    }

    private var stack: some View {
        ScrollViewReader { proxy in
            // The background paints the whole screen, but the scroll view itself
            // stays inside the safe area so pinned headers park below the status
            // bar rather than sliding under the clock.
            cardStack
                .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .overlay(alignment: .top) {
                // An opaque strip filling just the status-bar inset, so pinned
                // headers scroll away underneath it instead of colliding with
                // the clock. Zero height + ignoresSafeArea = exactly the inset.
                Color(.systemGroupedBackground)
                    .frame(height: 0)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
            }
            // Today sits alone top-right. Filter and Settings live bottom-left,
            // clear of the list's top edge and far from both other controls, so
            // neither is hit by accident.
            .overlay(alignment: .topTrailing) {
                // It stands down for the search bar, which wants the width —
                // and on a handful of results there is nothing to jump over.
                if !isSearching {
                    HStack(spacing: 12) {
                        // Only while something is waiting: a count of nothing
                        // is not worth a permanent control.
                        if waitingCount > 0 || attentionOnly {
                            attentionFilterButton
                        }
                        todayButton(proxy)
                    }
                    .padding(.trailing, 16)
                    .padding(.top, Self.topControlInset)
                    .transition(.opacity)
                }
            }
            .overlay(alignment: .bottomLeading) {
                // 12pt apart so a thumb aimed at one does not catch the
                // other, and high enough to clear the home indicator, which
                // swallows touches in the strip along the bottom edge.
                // Filter leads: on a wide window it is the sidebar's switch,
                // and a switch belongs against the edge the sidebar comes from.
                // The two narrowing tools then sit together, with More last.
                HStack(spacing: 12) {
                    filterButton
                    searchButton
                    settingsButton
                }
                .padding(.leading, 22)
                .padding(.bottom, 42)
            }
            .overlay(alignment: .bottomTrailing) { addButton }
            // Above the buttons rather than among them: it comes and goes, and
            // a control that appears between two permanent ones moves them.
            .overlay(alignment: .bottom) { undoBanner }
            .onAppear {
                guard !didAnchorToToday else { return }
                didAnchorToToday = true
                // One runloop hop so the sections exist before we jump.
                // Dated cards were already filed by the store on load.
                DispatchQueue.main.async {
                    jumpToToday(proxy, animated: false)
                    store.beginLiveSync()
                }
            }
            .sheet(isPresented: $isAdding) { addCardSheet }
            .sheet(isPresented: $isFiltering) {
                FilterSheet(
                    categorySelection: $filterCategoryIDs.animation(.easeInOut(duration: 0.2)),
                    projectSelection: $filterProjectIDs.animation(.easeInOut(duration: 0.2))
                )
                .environmentObject(store)
            }
            // Opening a notification narrows to the day's work rather than
            // landing at the top of the list. The notification was a question
            // about one card, and this is the list that card is in. Outside
            // the Catalyst guard below, because a Mac notification opens the
            // app the same way.
            .onReceive(NotificationCenter.default.publisher(for: .reminderOpened)) { _ in
                withAnimation(.easeInOut(duration: 0.2)) {
                    attentionOnly = true
                    filterCategoryIDs = []
                    filterProjectIDs = []
                }
            }
            #if !targetEnvironment(macCatalyst)
            .sheet(isPresented: $isShowingSettings) {
                SettingsView().environmentObject(store)
            }
            #endif
            .sheet(item: $editItem) { item in
                CardActionsSheet(itemID: item.id).environmentObject(store)
            }
            .confirmationDialog(
                stackPickItem?.title ?? "",
                isPresented: Binding(
                    get: { !usesPopoverMenus && stackPickItem != nil },
                    set: { if !$0 { stackPickItem = nil } }
                ),
                titleVisibility: .visible,
                presenting: stackPickItem
            ) { card in
                // One list, three surfaces — see `CardMenu`. The dialog draws
                // them plainly, because that is what a confirmation dialog
                // gives you and it is the right shape on a phone.
                ForEach(Array(cardActions(for: card).enumerated()), id: \.offset) { _, action in
                    let look = look(action, for: card)
                    Button(role: action == .delete ? .destructive : nil) {
                        stackPickItem = nil
                        look.run()
                    } label: { look.title }
                }
                Button("Cancel", role: .cancel) { }
            }
            .onChange(of: scenePhase) { _, phase in
                // A Mac window that is not frontmost is still a window the
                // user is looking at. Tearing down the watcher there meant a
                // visible list could sit an hour behind the phone and only
                // catch up when clicked into — which looks exactly like sync
                // being broken. Only being properly put away stops it.
                #if targetEnvironment(macCatalyst)
                let watching = phase != .background
                #else
                let watching = phase == .active
                #endif

                guard watching else {
                    store.endLiveSync()
                    return
                }
                // Frontmost or not decides how often the backstop runs, and
                // this fires on every scene change, so the cadence follows the
                // window back and forward.
                store.beginLiveSync(frontmost: phase == .active)
                // The rest is catching up after being away, and only applies
                // on the way back to the front.
                guard phase == .active else { return }
                // Whatever the other device wrote while we were away.
                withAnimation { store.refreshFromSyncFile() }
                store.refreshIfDayChanged()
                // Reminders fire while the app is away, so the badge and the
                // pending set are both stale by the time it comes back.
                store.rescheduleNotifications()
            }
            .onChange(of: store.categories) { _, categories in
                // A category the user deleted must not keep filtering the list.
                let alive = Set(categories.map(\.id))
                if !filterCategoryIDs.isSubset(of: alive) {
                    withAnimation { filterCategoryIDs.formIntersection(alive) }
                }
            }
            .onChange(of: store.projects) { _, projects in
                // Nor a project that was merged away or deleted.
                let alive = Set(projects.map(\.id))
                if !filterProjectIDs.isSubset(of: alive) {
                    withAnimation { filterProjectIDs.formIntersection(alive) }
                }
            }
        }
    }

    // MARK: - Filtering

    /// Cards for a stack, after the filter — any chosen category or project —
    /// and then after the search. Both narrow; neither reorders.
    private func cards(in bucket: Bucket) -> [TodoItem] {
        var all = store.items(in: bucket)
        if attentionOnly {
            all = all.filter { Attention.needed($0) }
        }
        if isFiltered {
            all = all.filter {
                FilterCounts.matches($0, categories: filterCategoryIDs, projects: filterProjectIDs)
            }
        }
        let terms = searchTerms
        guard !terms.isEmpty else { return all }
        return all.filter {
            let project = store.project(for: $0)
            return CardSearch.matches(title: $0.title, project: project?.name,
                                      group: project?.group, terms: terms)
        }
    }

    private var searchTerms: [String] { CardSearch.terms(in: query) }

    private var isFiltered: Bool { !filterCategoryIDs.isEmpty || !filterProjectIDs.isEmpty }

    /// Cards whose reminder has arrived and that are still sitting in Inbox
    /// or Later. Filing one into Today takes it off the count, which is what
    /// makes the number worth acting on.
    private var waitingCount: Int { Attention.count(in: store.items) }

    /// Narrowed by either means, for the empty state.
    private var isNarrowed: Bool { isFiltered || attentionOnly || !searchTerms.isEmpty }

    /// How many cards the narrowing holds, counted exactly as the sidebar
    /// counts its rows. The button used to show how many filters were on,
    /// which reads as a card count when it is sitting a thumb's width from
    /// several real ones.
    private var filteredCardCount: Int {
        FilterCounts.matching(store.items,
                              categories: filterCategoryIDs, projects: filterProjectIDs)
    }

    /// The chosen categories, in the order the user arranged them.
    private var activeFilters: [CardCategory] {
        store.categories.filter { filterCategoryIDs.contains($0.id) }
    }

    /// The chosen projects, by name.
    private var activeProjects: [Project] {
        store.projects
            .filter { filterProjectIDs.contains($0.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Everything chosen, as words — for the empty state and VoiceOver.
    private var filterNames: [String] {
        activeFilters.map(\.label) + activeProjects.map(\.name)
    }

    /// Drop every filter, from a card's right-click menu.
    private func showAll() {
        withAnimation(.easeInOut(duration: 0.2)) {
            filterCategoryIDs = []
            filterProjectIDs = []
        }
    }

    /// Narrow the list to one project, from a card's right-click menu.
    private func showOnly(_ project: Project) {
        withAnimation(.easeInOut(duration: 0.2)) {
            filterCategoryIDs = []
            filterProjectIDs = [project.id]
        }
    }

    private var filterButton: some View {
        Button {
            if showsSidebar {
                withAnimation { columns = columns == .detailOnly ? .all : .detailOnly }
            } else {
                isFiltering = true
            }
        } label: {
            Group {
                if !isFiltered {
                    Image(systemName: "line.3.horizontal.decrease")
                        .foregroundStyle(Color.primary.opacity(0.75))
                } else if activeFilters.count == 1 && activeProjects.isEmpty {
                    Image(systemName: activeFilters[0].symbolName)
                        .foregroundStyle(activeFilters[0].tint)
                } else if activeProjects.count == 1 && activeFilters.isEmpty {
                    Image(systemName: "paperclip")
                        .foregroundStyle(filterTint)
                } else {
                    // Several at once: no single icon can stand for them, so
                    // say how many cards they hold — the same number the
                    // sidebar shows beside the rows that were ticked.
                    Text("\(filteredCardCount)")
                        .monospacedDigit()
                        .foregroundStyle(Color.accentColor)
                }
            }
            .floatingChrome(state: isFiltered ? filterTint : nil)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            isFiltered
                ? "Filter: " + filterNames.joined(separator: ", ")
                : "Filter by category or project"
        )
    }

    /// Opens the bar, or closes it and drops the query with it. ⌘F on the Mac,
    /// where a search field is expected to be one keystroke away.
    private var searchButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isSearching.toggle()
                if !isSearching { query = "" }
            }
            searchFocused = isSearching
        } label: {
            Image(systemName: isSearching ? "magnifyingglass.circle.fill" : "magnifyingglass")
                .foregroundStyle(searchTerms.isEmpty ? Color.primary.opacity(0.75) : Color.accentColor)
                .floatingChrome(state: searchTerms.isEmpty ? nil : .accentColor)
        }
        .buttonStyle(.plain)
        .keyboardShortcut("f", modifiers: .command)
        .accessibilityLabel(isSearching ? "Close search" : "Search tasks")
    }

    /// Above the stack rather than over it: the cards are the answer, and a bar
    /// floating on top of them would cover the first one.
    private var searchField: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search tasks, projects or groups", text: $query)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .focused($searchFocused)
                if !query.isEmpty {
                    Button {
                        query = ""
                        searchFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Capsule().fill(Color(.secondarySystemGroupedBackground)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10)))

            Button("Cancel") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSearching = false
                    query = ""
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    /// The colour of a single active filter, or the accent for several.
    private var filterTint: Color {
        if activeFilters.count == 1 && activeProjects.isEmpty { return activeFilters[0].tint }
        if activeProjects.count == 1 && activeFilters.isEmpty {
            let category = activeProjects[0].categoryID.flatMap { id in store.categories.first { $0.id == id } }
            return category?.color.prefixTint ?? .accentColor
        }
        return .accentColor
    }

    // MARK: - Parking the list on TODAY

    /// TODAY when it has cards; otherwise the nearest section below it, so the
    /// jump never silently does nothing.
    private var anchorBucket: Bucket {
        let preferred: [Bucket] = [.today, .tomorrow, .later, .completed, .inbox]
        return preferred.first { !cards(in: $0).isEmpty } ?? .today
    }

    /// Lifted out of `body`: this file sits at the limit of what the type
    /// checker will infer in one expression, and one more argument to the
    /// sheet below tipped it over — with the error landing on unrelated lines
    /// hundreds of lines away.
    /// The project a new task starts with: the one the list is narrowed to,
    /// when it is narrowed to exactly one. Two or more is not an answer, and
    /// a category on its own does not name a project.
    private var filteredProject: Project? {
        guard filterProjectIDs.count == 1, let id = filterProjectIDs.first else { return nil }
        return store.project(id: id)
    }

    private var addCardSheet: some View {
        AddCardView(
            categories: store.categories,
            projects: store.projects,
            projectLastUsed: store.projectLastUsed,
            projectsInUse: store.projectsInUse,
            defaultCategoryID: store.defaultCategoryID,
            defaultProject: filteredProject,
            onAdd: addCard
        )
        .environmentObject(store)
    }

    private func addCard(title: String, bucket: Bucket, categoryID: UUID?,
                         projectChoice: ProjectChoice, newProjectGroup: String?,
                         remindAt: Date?, deadline: Date?) {
            // A new project is only created now, when the card is, so
            // a cancelled sheet leaves nothing behind. It takes the
            // category chosen for this first card.
            let projectID: UUID?
            switch projectChoice {
            case .none:                  projectID = nil
            case .existing(let project): projectID = project.id
            case .new(let name):
                projectID = store.ensureProject(named: name, categoryID: categoryID,
                                                group: newProjectGroup)?.id
            }
            withAnimation {
                // The sheet already resolved the default, so pass the
                // choice through as-is rather than letting the store
                // substitute one.
                store.add(
                    title: title,
                    bucket: bucket,
                    categoryID: .some(categoryID),
                    projectID: projectID,
                    remindAt: remindAt,
                    deadline: deadline
                )
            }
    }

    private func jumpToToday(_ proxy: ScrollViewProxy, animated: Bool) {
        let target = anchorBucket
        if animated {
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(target, anchor: .top)
            }
        } else {
            proxy.scrollTo(target, anchor: .top)
        }
    }

    /// Shows what is still to be settled: a reminder that has arrived, on a
    /// card still in Inbox or Later. They appear in their own stacks, where
    /// they can be moved, ticked off or swiped like anything else — and doing
    /// any of that takes them off the flag.
    private var attentionFilterButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                attentionOnly.toggle()
                if attentionOnly {
                    // A narrowing replaces the last, as choosing a project does.
                    filterCategoryIDs = []
                    filterProjectIDs = []
                }
            }
        } label: {
            // The same flag the cards carry, so the button and the edge it
            // gathers are plainly the same thing.
            Image(systemName: "flag.fill")
                .foregroundStyle(attentionOnly ? Color.white : Color.red)
                // Solid while it is on. Tinted glass says "a filter is
                // running" more quietly than this needs saying: the list on
                // screen is not the whole list.
                .floatingChrome(state: .red, solid: attentionOnly ? .red : nil)
                // After the fill, so the glass does not draw over it. This
                // is also why these buttons are a plain HStack and not a
                // GlassEffectContainer: a container composites its children's
                // glass into one layer that lands on top of a child's own
                // overlay, and the count ends up half-swallowed by the disc.
                .overlay(alignment: .topTrailing) {
                    if waitingCount > 0 && !attentionOnly {
                        Text("\(waitingCount)")
                            .font(.caption2.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.red))
                            .offset(x: 4, y: -2)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(attentionOnly ? "Show all tasks" : "Show tasks to address")
    }

    private var settingsButton: some View {
        Button {
            // Clicking the button while the popover is open light-dismisses it
            // first, and without this the same click would open it straight
            // back up — the button would look dead. A sheet cannot be closed
            // this way at all: it is modal, and the press never arrives.
            if let at = settingsDismissedAt, Date().timeIntervalSince(at) < 0.35 {
                settingsDismissedAt = nil
                return
            }
            isShowingSettings.toggle()
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(Color.primary.opacity(0.75))
                .floatingChrome()
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More")
        // A popover on the Mac, not a sheet: a sheet is modal, so neither
        // clicking outside it nor clicking this button again can put it away,
        // and More is a menu rather than a task to be finished.
        #if targetEnvironment(macCatalyst)
        .popover(isPresented: $isShowingSettings, arrowEdge: .top) {
            SettingsView()
                .environmentObject(store)
                .frame(minWidth: 420, idealWidth: 460, minHeight: 540, idealHeight: 640)
        }
        .onChange(of: isShowingSettings) { _, open in
            if !open { settingsDismissedAt = Date() }
        }
        #endif
    }

    private func todayButton(_ proxy: ScrollViewProxy) -> some View {
        Button {
            jumpToToday(proxy, animated: true)
        } label: {
            Image(systemName: "sun.max.fill")
                .foregroundStyle(Bucket.today.tint)
                .floatingChrome()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Scroll to Now")
    }

    // MARK: - Stack of cards

    private var cardStack: some View {
        VStack(spacing: 0) {
            if isSearching {
                searchField
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            scrollingCards
        }
    }

    private var scrollingCards: some View {
        ScrollView {
            // Headers scroll with the content rather than pinning: on iOS 26+
            // the scroll view extends under the status bar, and a pinned header
            // parks there permanently, blurred behind the clock.
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(Bucket.allCases) { bucket in
                    let cards = cards(in: bucket)
                    // COMPLETED is capped; every other bucket shows everything.
                    let visible = bucket == .completed ? Array(cards.prefix(completedShown)) : cards

                    if !cards.isEmpty {
                        Section {
                            ForEach(visible) { card in
                                CardRow(
                                    item: card,
                                    category: store.category(for: card),
                                    project: store.project(for: card),
                                    onTap: { stackPickItem = card },
                                    onToggle: { withAnimation { store.toggleCompleted(card) } },
                                    // Left swipe pulls the card into Today, or
                                    // pushes it to Tomorrow if already in Today.
                                    onMove: {
                                        withAnimation {
                                            store.move(card, to: card.bucket.forwardDestination)
                                        }
                                    },
                                    // Right swipe opens the full editor.
                                    onEdit: { editItem = card }
                                )
                                // The right-click menu, on the Mac only: a
                                // phone's long press has no second menu to be
                                // inconsistent with, since tapping already
                                // opens this same list.
                                #if targetEnvironment(macCatalyst)
                                .contextMenu {
                                    ForEach(Array(cardActions(for: card).enumerated()),
                                            id: \.offset) { _, action in
                                        let look = look(action, for: card)
                                        Button(role: action == .delete ? .destructive : nil) {
                                            stackPickItem = nil
                                            look.run()
                                        } label: {
                                            Label { look.title } icon: {
                                                Image(systemName: look.symbol)
                                            }
                                        }
                                    }
                                }
                                #endif
                                .transition(.opacity.combined(with: .move(edge: .top)))
                                // Identity must include the stack. A card that
                                // moves section keeps its id, and SwiftUI then
                                // reuses the old row without feeding it the new
                                // card — so it keeps painting the previous
                                // stack's colour and a date it no longer has.
                                .id("\(card.id)-\(card.bucket.rawValue)")
                                // Bound per row so it opens on the card that
                                // was clicked rather than over the middle of
                                // the list; only ever one can be true.
                                .popover(isPresented: Binding(
                                    get: { usesPopoverMenus && stackPickItem?.id == card.id },
                                    set: { if !$0 { stackPickItem = nil } }
                                )) {
                                    cardMenu(card)
                                }
                            }

                            if bucket == .completed {
                                moreButton(shown: visible.count, total: cards.count)
                            }
                        } header: {
                            SectionHeader(bucket: bucket, count: cards.count)
                                .id(bucket)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 96)
            .animation(.easeInOut(duration: 0.2), value: store.items)
        }
        .overlay {
            if store.items.isEmpty {
                ContentUnavailableView(
                    "No tasks yet",
                    systemImage: "tray",
                    description: Text("Tap + to drop a task into your inbox.")
                )
            } else if isNarrowed,
                      Bucket.allCases.allSatisfy({ cards(in: $0).isEmpty }) {
                if attentionOnly && searchTerms.isEmpty && !isFiltered {
                    ContentUnavailableView(
                        "Nothing to address",
                        systemImage: "flag",
                        description: Text("Nothing due is still sitting in Inbox or Later.")
                    )
                } else if searchTerms.isEmpty {
                    ContentUnavailableView(
                        filterNames.count == 1 ? "Nothing in \(filterNames[0])" : "Nothing matches",
                        systemImage: "line.3.horizontal.decrease",
                        description: Text(filterNames.joined(separator: ", "))
                    )
                } else {
                    // The query is the thing to correct, so it leads — even
                    // when a filter is also on, which the description says.
                    ContentUnavailableView(
                        "No task matches \u{201C}\(query)\u{201D}",
                        systemImage: "magnifyingglass",
                        description: Text(isFiltered
                                          ? "Searching only within \(filterNames.joined(separator: ", "))."
                                          : "Try fewer words.")
                    )
                }
            }
        }
        .macTopScrollEdge()
    }

    // MARK: - The menu a click on a card opens

    /// The same choices the phone's action sheet offers, drawn as rows so the
    /// stacks can wear their own colours — the wash from the cards themselves,
    /// so a destination is recognised rather than read.
    @ViewBuilder
    private func cardMenu(_ card: TodoItem) -> some View {
        let project = store.project(for: card)

        VStack(alignment: .leading, spacing: 4) {
            Text(card.title)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 2)

            // The same list, drawn with the stack colours a click deserves.
            // A divider wherever the kind of action changes, so moving a card
            // and answering its reminder do not read as one run.
            let actions = cardActions(for: card)
            ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                if index > 0, isNewGroup(action, after: actions[index - 1]) {
                    Divider().padding(.vertical, 4)
                }
                let look = look(action, for: card)
                menuRow(look.title, symbol: look.symbol, tint: look.tint, wash: look.wash) {
                    stackPickItem = nil
                    look.run()
                }
            }
        }
        .padding(.bottom, 10)
        .frame(width: 260)
        .presentationCompactAdaptation(.popover)
    }

    /// How one action is drawn and what it does. The three surfaces differ in
    /// how they lay a row out, never in which rows they have or what they say.
    private func look(_ action: CardMenu.Action, for card: TodoItem)
        -> (title: Text, symbol: String, tint: Color, wash: Double, run: () -> Void) {
        switch action {
        case .move(let target):
            return (Text(target.title), target.symbolName, target.tint, target.lightWash,
                    { withAnimation { store.move(card, to: target) } })
        case .snooze:
            return (Text("Snooze until tomorrow"), "bell.badge", .accentColor, 0,
                    { withAnimation { store.answerReminder(card, .snooze) } })
        case .clearReminder:
            return (Text("Clear the reminder"), "bell.slash", .secondary, 0,
                    { withAnimation { store.answerReminder(card, .clear) } })
        case .edit:
            // One hop: a sheet presented from a dialog's own action is
            // swallowed while that dialog is still dismissing.
            return (Text("Edit…"), "square.and.pencil", .accentColor, 0,
                    { DispatchQueue.main.async { editItem = card } })
        case .showOnlyProject:
            let name = store.project(for: card)?.name ?? ""
            return (Text("Show Only \(name)"), "line.3.horizontal.decrease.circle", .accentColor, 0,
                    { showOnly(store.project(for: card)!) })
        case .showAll:
            return (Text("Show All"), "line.3.horizontal.decrease.circle.fill", .accentColor, 0,
                    { showAll() })
        case .delete:
            return (Text("Delete"), "trash", .red, 0,
                    { withAnimation { store.delete(card) } })
        }
    }

    private func cardActions(for card: TodoItem) -> [CardMenu.Action] {
        CardMenu.actions(for: card, isFiltered: isFiltered,
                         hasProject: store.project(for: card) != nil)
    }

    /// Moving, answering a reminder, and everything else are three runs.
    private func isNewGroup(_ action: CardMenu.Action, after previous: CardMenu.Action) -> Bool {
        func rank(_ action: CardMenu.Action) -> Int {
            switch action {
            case .move: return 0
            case .snooze, .clearReminder: return 1
            case .edit, .showOnlyProject, .showAll: return 2
            case .delete: return 3
            }
        }
        return rank(action) != rank(previous)
    }

    /// What just happened, and the way back from it.
    ///
    /// A banner rather than a dialog: undoing is the rare case, and a sheet
    /// that has to be dismissed every time a task is ticked off would cost the
    /// common case to serve the rare one. It says what happened — the house
    /// rule — and offers the way back for as long as anyone is likely to want
    /// it, then goes quietly. ⌘Z keeps working after it has gone.
    @ViewBuilder
    private var undoBanner: some View {
        if let step = store.undoBanner {
            HStack(spacing: 12) {
                Text(step.message)
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button("Undo") { withAnimation { store.undoLast() } }
                    .font(.subheadline.weight(.semibold))
                Button {
                    withAnimation { store.dismissUndoBanner() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            .floatingBar()
            .padding(.horizontal, 22)
            .padding(.bottom, 104)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.snappy(duration: 0.25), value: step.id)
        }
    }

    private func menuRow(_ title: Text, symbol: String, tint: Color,
                         wash: Double, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .foregroundStyle(tint == .clear ? Color.secondary : tint)
                    .frame(width: 22)
                title.foregroundStyle(Color.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(tint.opacity(colorScheme == .dark ? wash * 0.6 : wash))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    // MARK: - COMPLETED paging

    @ViewBuilder
    private func moreButton(shown: Int, total: Int) -> some View {
        let remaining = total - shown

        if remaining > 0 {
            pagingButton("More… (\(remaining))", symbol: "chevron.down") {
                completedShown = min(total, completedShown + Self.completedPageSize)
            }
        } else if total > Self.completedPageSize {
            pagingButton("Show Less", symbol: "chevron.up") {
                completedShown = Self.completedPageSize
            }
        }
    }

    private func pagingButton(
        _ label: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { action() }
        } label: {
            Label(label, systemImage: symbol)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .padding(.top, 2)
    }

    // MARK: - Floating + button

    private var addButton: some View {
        Button {
            isAdding = true
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(Circle().fill(Color.accentColor))
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                .contentShape(Circle())
        }
        // Every other floating button has this. Without it the automatic
        // style draws its own rounded rect behind the label — invisible on
        // iOS, a grey square around the circle on the Mac.
        .buttonStyle(.plain)
        .padding(.trailing, 22)
        .padding(.bottom, 28)
        .accessibilityLabel("Add task to inbox")
    }
}

extension View {
    /// Tightens the band the system draws where scrolling content meets the
    /// top of the window — on the Mac only.
    ///
    /// `.soft` is the default: a long translucent gradient. Under a status bar
    /// that reads as iOS, but the Mac has no status bar for it to belong to,
    /// and it lands below the traffic lights as a tall strip with the first
    /// card half-legible behind it. `.hard` is the same idea at the height of
    /// the titlebar and with a defined edge — a thin band rather than a fade,
    /// which is what the window wanted all along. Removing it entirely left
    /// the traffic lights sitting on top of a card.
    ///
    /// The second and last `#available(iOS 26, *)` fork in the app — see
    /// `floatingChrome` for the other.
    @ViewBuilder
    func macTopScrollEdge() -> some View {
        #if targetEnvironment(macCatalyst)
        if #available(iOS 26.0, macOS 26.0, *) {
            scrollEdgeEffectStyle(.hard, for: .top)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

/// The look of a control that floats over the card stack: a 48pt disc with a
/// ring that defines it whatever happens to be scrolled behind.
///
/// Glass where the system has it. The fill was never carrying state — every
/// one of these buttons says what it is with its icon and its ring — so
/// letting the cards show through costs nothing, and four opaque discs stop
/// reading like holes punched in the list.
///
/// The ring is why this works on glass at all: over an empty stretch of page
/// background there is nothing to refract, and a glass disc would otherwise
/// have only its own rim to prove it is there.
private struct FloatingChrome: ViewModifier {
    /// The colour of whatever this button is currently doing — filtering,
    /// holding a query, waiting on an answer — or nil at rest.
    ///
    /// It thickens the ring *and* tints the glass. The ring alone was enough
    /// on an opaque disc; on glass it is not — measured on the phone, a 2pt
    /// red ring all but disappears against a dark backdrop.
    var state: Color?
    /// A fill that replaces the glass entirely, set while the control is
    /// changing what the list shows. Glass is for chrome at rest; a filter
    /// that is on has to say so louder than a tint can.
    var solid: Color?
    /// A round button, or the wide capsule the undo banner sits in. The shape
    /// is all that differs: both take the same glass, the same ring and the
    /// same fallback, which is the whole point of there being one modifier.
    var bar = false

    private var ring: Color { state?.opacity(0.85) ?? .primary.opacity(0.10) }
    private var lineWidth: CGFloat { state == nil ? 1 : 2 }
    private var corners: CGFloat { bar ? 22 : 24 }

    @ViewBuilder
    func body(content: Content) -> some View {
        let shaped = bar
            ? AnyView(content.font(.subheadline).padding(.horizontal, 16).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading))
            : AnyView(content.font(.body.weight(.semibold)).frame(width: 48, height: 48))

        if let solid {
            edged(shaped.background(shape.fill(solid)), shadowed: true)
        } else if #available(iOS 26.0, macOS 26.0, *) {
            // No shadow: the glass carries its own depth, and a drop shadow
            // under it reads as two light sources.
            edged(shaped.glassEffect(glass, in: .rect(cornerRadius: corners)), shadowed: false)
        } else {
            edged(shaped.background(shape.fill(Color(.secondarySystemGroupedBackground))),
                  shadowed: true)
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: corners, style: .continuous)
    }

    @available(iOS 26.0, macOS 26.0, *)
    private var glass: Glass {
        // Light enough to stay glass rather than becoming a coloured disc:
        // the tint is there to carry the ring, not to replace the fill.
        guard let state else { return .regular.interactive() }
        return .regular.tint(state.opacity(0.28)).interactive()
    }

    private func edged(_ view: some View, shadowed: Bool) -> some View {
        view
            .overlay(shape.strokeBorder(ring, lineWidth: lineWidth))
            .shadow(color: .black.opacity(shadowed ? 0.18 : 0), radius: 6, y: 3)
            .contentShape(shape)
    }
}

extension View {
    /// Applied by every button that floats over the cards. The one place the
    /// glass is decided, so the two paths cannot drift apart.
    func floatingChrome(state: Color? = nil, solid: Color? = nil) -> some View {
        modifier(FloatingChrome(state: state, solid: solid))
    }

    /// The same chrome, as a wide bar. Here rather than in a second modifier
    /// so the `#available(iOS 26, *)` fork stays in one place.
    func floatingBar() -> some View {
        modifier(FloatingChrome(bar: true))
    }
}

#Preview {
    ContentView().environmentObject(TodoStore())
}
