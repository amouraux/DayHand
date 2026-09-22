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

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
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
                todayButton(proxy)
                    .padding(.trailing, 16)
                    .padding(.top, 6)
            }
            .overlay(alignment: .bottomLeading) {
                // 12pt apart so a thumb aimed at one does not catch the
                // other, and high enough to clear the home indicator, which
                // swallows touches in the strip along the bottom edge.
                HStack(spacing: 12) {
                    filterButton
                    settingsButton
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
                ) { title, bucket, categoryID, projectChoice, dueDate in
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
                            dueDate: dueDate
                        )
                    }
                }
            }
            .sheet(item: $dateItem) { item in
                DatePickerSheet(item: item) { date in
                    store.setDate(item, to: date)
                }
            }
            .sheet(isPresented: $isFiltering) {
                FilterSheet(
                    categorySelection: $filterCategoryIDs.animation(.easeInOut(duration: 0.2)),
                    projectSelection: $filterProjectIDs.animation(.easeInOut(duration: 0.2))
                )
                .environmentObject(store)
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView().environmentObject(store)
            }
            .sheet(item: $editItem) { item in
                CardActionsSheet(itemID: item.id).environmentObject(store)
            }
            .confirmationDialog(
                stackPickItem?.title ?? "",
                isPresented: Binding(
                    get: { stackPickItem != nil },
                    set: { if !$0 { stackPickItem = nil } }
                ),
                titleVisibility: .visible,
                presenting: stackPickItem
            ) { card in
                // Stacks only, and only the ones it is not already in, so
                // choosing one is a single tap with nothing else in the way.
                ForEach(Bucket.quickMoveTargets.filter { $0 != card.bucket }) { target in
                    Button(target.title) {
                        withAnimation { store.move(card, to: target) }
                    }
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
                withAnimation { _ = store.applyScheduledDates() }
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
            .overlay(alignment: .top) {
                if let notice = store.autoFileNotice {
                    AutoFileBanner(notice: notice) {
                        withAnimation(.easeOut(duration: 0.2)) { store.dismissAutoFileNotice() }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: store.autoFileNotice)
        }
    }

    // MARK: - Filtering

    /// Cards for a stack, after the filter: any chosen category or project.
    private func cards(in bucket: Bucket) -> [TodoItem] {
        let all = store.items(in: bucket)
        guard isFiltered else { return all }
        return all.filter { card in
            if let id = card.categoryID, filterCategoryIDs.contains(id) { return true }
            if let id = card.projectID, filterProjectIDs.contains(id) { return true }
            return false
        }
    }

    private var isFiltered: Bool { !filterCategoryIDs.isEmpty || !filterProjectIDs.isEmpty }

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
            isFiltering = true
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

    private var settingsButton: some View {
        Button {
            isShowingSettings = true
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.primary.opacity(0.75))
                .frame(width: 48, height: 48)
                .background(Circle().fill(Color(.secondarySystemGroupedBackground)))
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.10)))
                .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
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
            } else if isFiltered,
                      Bucket.allCases.allSatisfy({ cards(in: $0).isEmpty }) {
                ContentUnavailableView(
                    filterNames.count == 1 ? "Nothing in \(filterNames[0])" : "Nothing matches",
                    systemImage: "line.3.horizontal.decrease",
                    description: Text(filterNames.joined(separator: ", "))
                )
            }
        }
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
