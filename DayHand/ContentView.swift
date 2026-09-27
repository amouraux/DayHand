import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: TodoStore

    @State private var dateItem: TodoItem?
    /// The card whose stack is being picked, from a tap.
    @State private var stackPickItem: TodoItem?
    /// The card being edited in full, from a right swipe.
    @State private var editItem: TodoItem?
    @State private var isAdding = false
    @State private var isShowingSettings = false
    @State private var isShowingReminders = false
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
                    projectSelection: $filterProjectIDs.animation(.easeInOut(duration: 0.2))
                )
                .navigationTitle("Filter")
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
                    todayButton(proxy)
                        .padding(.trailing, 16)
                        .padding(.top, 6)
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
                    // Only while something is waiting. A permanent bell would
                    // be a button that usually does nothing; this one appearing
                    // is itself the news.
                    if !store.outstandingReminders.isEmpty {
                        remindersButton
                    }
                }
                .padding(.leading, 22)
                .padding(.bottom, 42)
            }
            .overlay(alignment: .bottomTrailing) { addButton }
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
            .sheet(isPresented: $isAdding) {
                AddCardView(
                    categories: store.categories,
                    projects: store.projects,
                    projectLastUsed: store.projectLastUsed,
                    defaultCategoryID: store.defaultCategoryID
                ) { title, bucket, categoryID, projectChoice, deadline, remindAt in
                    // A new project is only created now, when the card is, so
                    // a cancelled sheet leaves nothing behind. It takes the
                    // category chosen for this first card.
                    let projectID: UUID?
                    switch projectChoice {
                    case .none:                  projectID = nil
                    case .existing(let project): projectID = project.id
                    case .new(let name):
                        projectID = store.ensureProject(named: name, categoryID: categoryID)?.id
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
                            deadline: deadline,
                            remindAt: remindAt
                        )
                    }
                }
            }
            .sheet(item: $dateItem) { item in
                DatePickerSheet(item: item) { date in
                    store.setDeadline(item, to: date)
                }
            }
            .sheet(isPresented: $isFiltering) {
                FilterSheet(
                    categorySelection: $filterCategoryIDs.animation(.easeInOut(duration: 0.2)),
                    projectSelection: $filterProjectIDs.animation(.easeInOut(duration: 0.2))
                )
                .environmentObject(store)
            }
            #if !targetEnvironment(macCatalyst)
            .sheet(isPresented: $isShowingReminders) {
                ReminderReviewView().environmentObject(store)
            }
            // Opening a notification goes to the review, not to the top of the
            // list: the notification was a question, and this is where it is
            // answered.
            .onReceive(NotificationCenter.default.publisher(for: .reminderOpened)) { _ in
                isShowingReminders = true
            }
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
                // The stacks it is not already in come first, so the common
                // move stays a single tap with nothing in the way.
                ForEach(Bucket.quickMoveTargets.filter { $0 != card.bucket }) { target in
                    Button(target.title) {
                        withAnimation { store.move(card, to: target) }
                    }
                }
                // Then the editor, so it is reachable from a plain click. On
                // the Mac it was behind a right-click, which is not where
                // anyone looks after learning that clicking a card does
                // something.
                Button("Edit…") {
                    stackPickItem = nil
                    // One hop: a sheet presented from the dialog's own action
                    // is swallowed while that dialog is still dismissing.
                    DispatchQueue.main.async { editItem = card }
                }
                // Narrowing to what is in front of you was a right-click, so it
                // did not exist on a phone at all — where the only route to a
                // project was to open the filter and find a name already
                // printed on the card. While a filter is on the useful move is
                // back out of it, on every card, since a category filter shows
                // cards carrying no project.
                if isFiltered {
                    Button("Show All") { showAll() }
                } else if let project = store.project(for: card) {
                    Button("Show Only \(project.name)") { showOnly(project) }
                }
                Button("Cancel", role: .cancel) { }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else {
                    // Nothing to watch for while we are not on screen.
                    store.endLiveSync()
                    return
                }
                store.beginLiveSync()
                // Whatever the other device wrote while we were away.
                withAnimation { store.refreshFromSyncFile() }
                store.refreshIfDayChanged()
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
        if isFiltered {
            all = all.filter { card in
                if let id = card.categoryID, filterCategoryIDs.contains(id) { return true }
                if let id = card.projectID, filterProjectIDs.contains(id) { return true }
                return false
            }
        }
        let terms = searchTerms
        guard !terms.isEmpty else { return all }
        return all.filter {
            CardSearch.matches(title: $0.title, project: store.project(for: $0)?.name, terms: terms)
        }
    }

    private var searchTerms: [String] { CardSearch.terms(in: query) }

    private var isFiltered: Bool { !filterCategoryIDs.isEmpty || !filterProjectIDs.isEmpty }

    /// Narrowed by either means, for the empty state.
    private var isNarrowed: Bool { isFiltered || !searchTerms.isEmpty }

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
                    Image(systemName: "number")
                        .foregroundStyle(filterTint)
                } else {
                    // Several at once: the count says more than any one icon.
                    Text("\(activeFilters.count + activeProjects.count)")
                        .monospacedDigit()
                        .foregroundStyle(Color.accentColor)
                }
            }
            .font(.body.weight(.semibold))
            .frame(width: 48, height: 48)
            .background(Circle().fill(Color(.secondarySystemGroupedBackground)))
            .overlay(
                Circle().strokeBorder(
                    isFiltered ? filterTint.opacity(0.85) : Color.primary.opacity(0.10),
                    lineWidth: isFiltered ? 2 : 1
                )
            )
            .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
            .contentShape(Circle())
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
                .font(.body.weight(.semibold))
                .foregroundStyle(searchTerms.isEmpty ? Color.primary.opacity(0.75) : Color.accentColor)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Color(.secondarySystemGroupedBackground)))
                .overlay(
                    Circle().strokeBorder(
                        searchTerms.isEmpty ? Color.primary.opacity(0.10) : Color.accentColor.opacity(0.85),
                        lineWidth: searchTerms.isEmpty ? 1 : 2
                    )
                )
                .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("f", modifiers: .command)
        .accessibilityLabel(isSearching ? "Close search" : "Search cards")
    }

    /// Above the stack rather than over it: the cards are the answer, and a bar
    /// floating on top of them would cover the first one.
    private var searchField: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search cards", text: $query)
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

    private var remindersButton: some View {
        Button { isShowingReminders = true } label: {
            Image(systemName: "bell.badge.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.red)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Color(.secondarySystemGroupedBackground)))
                .overlay(Circle().strokeBorder(Color.red.opacity(0.85), lineWidth: 2))
                .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Reminders waiting")
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
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.primary.opacity(0.75))
                .frame(width: 48, height: 48)
                .background(Circle().fill(Color(.secondarySystemGroupedBackground)))
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.10)))
                .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
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
                .font(.body.weight(.semibold))
                .foregroundStyle(Bucket.today.tint)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Color(.secondarySystemGroupedBackground)))
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.10)))
                .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Scroll to Today")
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
                                    onEdit: { editItem = card },
                                    onShowProject: store.project(for: card).map { project in
                                        { showOnly(project) }
                                    },
                                    onShowAll: isFiltered ? { showAll() } : nil
                                )
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
                    "No cards yet",
                    systemImage: "tray",
                    description: Text("Tap + to drop a card into your inbox.")
                )
            } else if isNarrowed,
                      Bucket.allCases.allSatisfy({ cards(in: $0).isEmpty }) {
                if searchTerms.isEmpty {
                    ContentUnavailableView(
                        filterNames.count == 1 ? "Nothing in \(filterNames[0])" : "Nothing matches",
                        systemImage: "line.3.horizontal.decrease",
                        description: Text(filterNames.joined(separator: ", "))
                    )
                } else {
                    // The query is the thing to correct, so it leads — even
                    // when a filter is also on, which the description says.
                    ContentUnavailableView(
                        "No card matches \u{201C}\(query)\u{201D}",
                        systemImage: "magnifyingglass",
                        description: Text(isFiltered
                                          ? "Searching only within \(filterNames.joined(separator: ", "))."
                                          : "Try fewer words.")
                    )
                }
            }
        }
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

            ForEach(Bucket.quickMoveTargets.filter { $0 != card.bucket }) { target in
                menuRow(Text(target.title), symbol: target.symbolName, tint: target.tint,
                        wash: target.lightWash) {
                    stackPickItem = nil
                    withAnimation { store.move(card, to: target) }
                }
            }

            Divider().padding(.vertical, 4)

            menuRow(Text("Edit…"), symbol: "square.and.pencil", tint: .accentColor, wash: 0) {
                stackPickItem = nil
                DispatchQueue.main.async { editItem = card }
            }
            if isFiltered {
                menuRow(Text("Show All"), symbol: "line.3.horizontal.decrease.circle.fill",
                        tint: .accentColor, wash: 0) {
                    stackPickItem = nil
                    showAll()
                }
            } else if let project {
                menuRow(Text("Show Only \(project.name)"), symbol: "line.3.horizontal.decrease.circle",
                        tint: .accentColor, wash: 0) {
                    stackPickItem = nil
                    showOnly(project)
                }
            }
        }
        .padding(.bottom, 10)
        .frame(width: 260)
        .presentationCompactAdaptation(.popover)
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
        }
        .padding(.trailing, 22)
        .padding(.bottom, 28)
        .accessibilityLabel("Add card to inbox")
    }
}

#Preview {
    ContentView().environmentObject(TodoStore())
}
