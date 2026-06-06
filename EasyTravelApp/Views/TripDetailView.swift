import SwiftUI

struct TripDetailView: View {
    @EnvironmentObject private var store: TravelStore
    let tripID: Trip.ID

    @State private var isPresentingAddLocation = false
    @State private var isPresentingEditTrip = false
    @State private var isPresentingPlanRoute = false
    @State private var listMode: ListMode = .byCategory
    /// Index into `sortedPlannedDays(trip)` for map + multi-day route list.
    @State private var mapSelectedDay: Int = 0
    /// Enables native List reorder controls (`onMove`) within each day.
    @State private var isEditingRouteOrder = false
    /// Shown after swipe “Add to day” when the trip has multiple visit days.
    @State private var addToDayPickerLocationID: UUID?
    @State private var pendingRouteResetDeleteIDs: Set<LocationItem.ID> = []
    @State private var confirmRouteResetDelete = false

    enum ListMode: String, CaseIterable, Identifiable {
        case byCategory = "Categories"
        case routeOrder = "Route order"

        var id: String { rawValue }
    }

    private var trip: Trip? {
        store.trips.first(where: { $0.id == tripID })
    }

    private func routeListAllowsNavigation(for trip: Trip) -> Bool {
        !(listMode == .routeOrder && isEditingRouteOrder && !(trip.plannedDays?.isEmpty ?? true))
    }

    @ViewBuilder
    private func tripActionBar(trip: Trip) -> some View {
        HStack(spacing: 12) {
            if trip.locations.count >= 2 {
                Button {
                    isPresentingPlanRoute = true
                } label: {
                    Label("Plan route", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(AppTheme.charcoal, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if listMode == .routeOrder, !(trip.plannedDays?.isEmpty ?? true) {
                Button(isEditingRouteOrder ? "Done" : "Reorder") {
                    isEditingRouteOrder.toggle()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.charcoal)
            }

            Button {
                isPresentingEditTrip = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.body)
                    .frame(width: 40, height: 40)
                    .background(AppTheme.elevatedFill, in: Circle())
            }
            .buttonStyle(.plain)

            Button {
                isPresentingAddLocation = true
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(AppTheme.charcoal, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add location")
        }
    }

    var body: some View {
        Group {
            if let trip {
                VStack(spacing: 0) {
                    TripHeroBanner(trip: trip)

                    VStack(spacing: AppTheme.sectionSpacing) {
                        tripActionBar(trip: trip)
                            .padding(.horizontal, AppTheme.pagePadding)
                            .padding(.top, 14)

                        tripListContent(trip: trip)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(AppTheme.cardBackground)
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: AppTheme.cornerRadius,
                            topTrailingRadius: AppTheme.cornerRadius
                        )
                    )
                    .offset(y: -AppTheme.tripHeroOverlap)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(AppTheme.screenBackground.ignoresSafeArea())
                .navigationBarBackButtonHidden(true)
                .toolbar(.hidden, for: .navigationBar)
                .sheet(isPresented: $isPresentingAddLocation) {
                    AddLocationView(tripID: tripID, isPresented: $isPresentingAddLocation)
                }
                .sheet(isPresented: $isPresentingEditTrip) {
                    EditTripView(isPresented: $isPresentingEditTrip, tripID: tripID)
                        .environmentObject(store)
                }
                .sheet(isPresented: $isPresentingPlanRoute) {
                    PlanRouteSheet(isPresented: $isPresentingPlanRoute, tripID: tripID, trip: trip)
                        .environmentObject(store)
                }
                .onChange(of: trip.plannedDays?.count ?? 0) { _, newCount in
                    if newCount > 0 {
                        mapSelectedDay = min(mapSelectedDay, max(0, newCount - 1))
                        listMode = .routeOrder
                    } else {
                        mapSelectedDay = 0
                    }
                }
                .confirmationDialog(
                    "Add to which day?",
                    isPresented: Binding(
                        get: { addToDayPickerLocationID != nil },
                        set: { if !$0 { addToDayPickerLocationID = nil } }
                    ),
                    titleVisibility: .visible
                ) {
                    if let locationID = addToDayPickerLocationID {
                        ForEach(sortedPlannedDays(for: trip)) { day in
                            Button("Day \(day.dayIndex + 1)") {
                                store.addLocationToPlannedDay(
                                    tripID: tripID,
                                    locationID: locationID,
                                    dayIndex: day.dayIndex
                                )
                                addToDayPickerLocationID = nil
                            }
                        }
                    }
                    Button("Cancel", role: .cancel) {
                        addToDayPickerLocationID = nil
                    }
                }
                .alert(routeResetDeleteTitle, isPresented: $confirmRouteResetDelete) {
                    Button("Delete and reset route", role: .destructive) {
                        performPendingRouteResetDeletes()
                    }
                    Button("Cancel", role: .cancel) {
                        pendingRouteResetDeleteIDs = []
                    }
                } message: {
                    Text("Deleting this item will reset the routing.")
                }
                .navigationDestination(for: LocationDetailRoute.self) { route in
                    LocationDetailView(locationID: route.locationID, tripID: route.tripID)
                        .environmentObject(store)
                }
            } else {
                ContentUnavailableView("Trip not found", systemImage: "exclamationmark.triangle")
            }
        }
    }

    @ViewBuilder
    private func tripListContent(trip: Trip) -> some View {
        List {
            if !trip.locations.isEmpty {
                Section {
                    embeddedMapSection(trip: trip)
                }
                .listRowInsets(EdgeInsets(
                    top: 0,
                    leading: AppTheme.pagePadding,
                    bottom: 8,
                    trailing: AppTheme.pagePadding
                ))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                Section {
                    Picker("List mode", selection: $listMode) {
                        ForEach(ListMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(
                    top: 4,
                    leading: AppTheme.pagePadding,
                    bottom: 4,
                    trailing: AppTheme.pagePadding
                ))
            }

            if listMode == .byCategory {
                categoryListSections(trip: trip)
            } else {
                routeOrderSections(trip: trip)
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(AppTheme.sectionSpacing)
        .scrollContentBackground(.hidden)
        .background(AppTheme.cardBackground)
        .safeAreaPadding(.bottom, AppTheme.floatingTabClearance)
        .environment(
            \.editMode,
            .constant(
                listMode == .routeOrder && !(trip.plannedDays?.isEmpty ?? true) && isEditingRouteOrder
                    ? .active
                    : .inactive
            )
        )
    }

    private var listRowInsets: EdgeInsets {
        EdgeInsets(
            top: AppTheme.listRowVerticalPadding,
            leading: AppTheme.pagePadding,
            bottom: AppTheme.listRowVerticalPadding,
            trailing: AppTheme.pagePadding
        )
    }

    @ViewBuilder
    private func embeddedMapSection(trip: Trip) -> some View {
        let planDays = sortedPlannedDays(for: trip)
        VStack(alignment: .leading, spacing: 12) {
            if !trip.hasItineraryDates, trip.locations.count >= 2 {
                AppTipBanner(
                    text: "Set trip dates in Trip settings to draw walking routes on the map.",
                    systemImage: "calendar"
                )
            } else if planDays.isEmpty, trip.locations.count >= 2 {
                AppTipBanner(
                    text: "Plan your route to split stops across days — the map updates as you pick each day.",
                    systemImage: "map"
                )
            }

            if trip.hasItineraryDates, planDays.count > 1 {
                mapDayChips(days: planDays, selection: $mapSelectedDay)
            }

            TripMapView(
                trip: trip,
                plannedDayIndex: (trip.hasItineraryDates && !planDays.isEmpty) ? mapSelectedDay : nil
            )
            .frame(height: AppTheme.embeddedMapHeight)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        }
    }

    @ViewBuilder
    private func categoryListSections(trip: Trip) -> some View {
        if trip.locations.isEmpty {
            Section("Locations") {
                ContentUnavailableView("No locations yet", systemImage: "mappin.and.ellipse")
            }
        } else {
            ForEach(groupedLocations(for: trip), id: \.category) { group in
                Section(group.category.title) {
                    ForEach(group.locations) { loc in
                        NavigationLink(value: LocationDetailRoute(tripID: tripID, locationID: loc.id)) {
                            categoryListRow(loc: loc)
                                .padding(.vertical, 4)
                        }
                        .listRowInsets(listRowInsets)
                        .contextMenu {
                            priorityMenu(locationID: loc.id)
                        }
                    }
                    .onDelete { offsets in
                        let idsToDelete = offsets.compactMap { index in
                            group.locations[safe: index]?.id
                        }
                        requestDeleteLocations(idsToDelete)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func routeOrderSections(trip: Trip) -> some View {
        if trip.locations.isEmpty {
            Section {
                ContentUnavailableView("No locations yet", systemImage: "mappin.and.ellipse")
            }
        } else if sortedPlannedDays(for: trip).isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Daily visits not assigned yet", systemImage: "calendar.badge.clock")
                        .font(.headline)
                    Text("Tap Plan route in the toolbar, adjust options, then Compute. The server splits stops across your trip days; results save automatically and appear here in day sections, and each day has its own map.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            Section("All stops (list order)") {
                ForEach(Array(trip.locations.enumerated()), id: \.element.id) { index, loc in
                    locationRowLink(trip: trip, locationID: loc.id) {
                        routeOrderRow(index: index + 1, loc: loc)
                    }
                }
                .onDelete { offsets in
                    store.deleteLocations(tripID: tripID, at: offsets)
                }
            }
        } else {
            let days = sortedPlannedDays(for: trip)
            let inPlan = Set(days.flatMap(\.orderedLocationIds))
            Section {
                Text("Set priority per stop (long-press → Priority). Must-see stops are always scheduled; lower priorities fill in when time allows. Tap + for unplanned stops; Reorder to drag ≡ within a day.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(days) { day in
                plannedDaySection(trip: trip, day: day, allDays: days, allowsNavigation: routeListAllowsNavigation(for: trip))
            }
            let extra = trip.locations.filter { !inPlan.contains($0.id) }
            if !extra.isEmpty {
                Section {
                    ForEach(extra) { loc in
                        unplannedStopRow(trip: trip, loc: loc, days: days)
                    }
                } header: {
                    Text("Not in plan")
                } footer: {
                    Text("These stops are not on any visit day yet — newly added places appear here until you add them to a day.")
                        .font(.caption)
                }
            }
        }
    }

    @ViewBuilder
    private func mapDayChips(days: [TripPlannedDay], selection: Binding<Int>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(days.enumerated()), id: \.offset) { idx, day in
                    DayChip(
                        title: "Day \(day.dayIndex + 1)",
                        isSelected: selection.wrappedValue == idx
                    ) {
                        selection.wrappedValue = idx
                    }
                }
            }
        }
    }

    private var routeResetDeleteTitle: String {
        let count = pendingRouteResetDeleteIDs.count
        if count <= 1 { return "Delete location?" }
        return "Delete \(count) locations?"
    }

    private func requestDeleteLocations(_ ids: [LocationItem.ID]) {
        guard !ids.isEmpty else { return }
        let resetIDs = ids.filter {
            store.tripLocationDeletionImpact(tripID: tripID, locationID: $0) == .resetsRoute
        }
        let safeIDs = ids.filter { !resetIDs.contains($0) }
        for id in safeIDs {
            store.deleteLocation(tripID: tripID, locationID: id)
        }
        if !resetIDs.isEmpty {
            pendingRouteResetDeleteIDs = Set(resetIDs)
            confirmRouteResetDelete = true
        }
    }

    private func performPendingRouteResetDeletes() {
        let ids = pendingRouteResetDeleteIDs
        pendingRouteResetDeleteIDs = []
        for id in ids {
            store.deleteLocation(tripID: tripID, locationID: id, confirmRouteReset: true)
        }
    }

    private func sortedPlannedDays(for trip: Trip) -> [TripPlannedDay] {
        (trip.plannedDays ?? []).sorted { $0.dayIndex < $1.dayIndex }
    }

    @ViewBuilder
    private func plannedDaySection(
        trip: Trip,
        day: TripPlannedDay,
        allDays: [TripPlannedDay],
        allowsNavigation: Bool
    ) -> some View {
        Section {
            if day.orderedLocationIds.isEmpty {
                Text("No stops on this day")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(day.orderedLocationIds.enumerated()), id: \.element) { index, uid in
                    if let loc = trip.locations.first(where: { $0.id == uid }) {
                        Group {
                            if allowsNavigation {
                                NavigationLink(value: LocationDetailRoute(tripID: tripID, locationID: loc.id)) {
                                    routeOrderRow(index: index + 1, loc: loc)
                                }
                            } else {
                                routeOrderRow(index: index + 1, loc: loc)
                            }
                        }
                        .contextMenu {
                            priorityMenu(locationID: loc.id)
                            moveToDayMenu(locationID: loc.id, fromDayIndex: day.dayIndex, days: allDays)
                        }
                    }
                }
                .onMove { source, destination in
                    store.reorderPlannedStops(
                        tripID: tripID,
                        dayIndex: day.dayIndex,
                        fromOffsets: source,
                        toOffset: destination
                    )
                }
            }
        } header: {
            Text("Day \(day.dayIndex + 1)")
        }
    }

    private func unplannedStopRow(trip: Trip, loc: LocationItem, days: [TripPlannedDay]) -> some View {
        let allowsNav = routeListAllowsNavigation(for: trip)
        return HStack(alignment: .top, spacing: 10) {
            Group {
                if allowsNav {
                    NavigationLink(value: LocationDetailRoute(tripID: tripID, locationID: loc.id)) {
                        routeOrderRow(index: "—", loc: loc)
                    }
                } else {
                    routeOrderRow(index: "—", loc: loc)
                }
            }

            Menu {
                addToDayMenu(locationID: loc.id, days: days)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AppTheme.charcoal)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add to a day")
        }
        .contextMenu {
            priorityMenu(locationID: loc.id)
            addToDayMenu(locationID: loc.id, days: days)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: days.count == 1) {
            if days.count == 1, let only = days.first {
                Button {
                    store.addLocationToPlannedDay(tripID: tripID, locationID: loc.id, dayIndex: only.dayIndex)
                } label: {
                    Label("Add to Day \(only.dayIndex + 1)", systemImage: "plus.circle")
                }
                .tint(.accentColor)
            } else {
                Button {
                    addToDayPickerLocationID = loc.id
                } label: {
                    Label("Add to day…", systemImage: "plus.circle")
                }
                .tint(.accentColor)
            }
        }
    }

    @ViewBuilder
    private func priorityMenu(locationID: UUID) -> some View {
        Menu("Priority") {
            ForEach(LocationItem.VisitPriority.allCases.sorted(by: { $0.rawValue > $1.rawValue })) { p in
                Button {
                    store.setVisitPriority(tripID: tripID, locationID: locationID, priority: p)
                } label: {
                    Label(p.title, systemImage: p.rawValue >= 4 ? "star.fill" : "star")
                }
            }
        }
    }

    @ViewBuilder
    private func addToDayMenu(locationID: UUID, days: [TripPlannedDay]) -> some View {
        ForEach(days) { day in
            Button {
                store.addLocationToPlannedDay(tripID: tripID, locationID: locationID, dayIndex: day.dayIndex)
            } label: {
                Label("Add to Day \(day.dayIndex + 1)", systemImage: "plus.circle")
            }
        }
    }

    @ViewBuilder
    private func moveToDayMenu(locationID: UUID, fromDayIndex: Int?, days: [TripPlannedDay]) -> some View {
        ForEach(days) { day in
            if day.dayIndex != fromDayIndex {
                Button {
                    store.movePlannedLocation(
                        tripID: tripID,
                        locationID: locationID,
                        fromDayIndex: fromDayIndex,
                        toDayIndex: day.dayIndex,
                        beforeLocationID: nil
                    )
                } label: {
                    Label("Move to Day \(day.dayIndex + 1)", systemImage: "calendar")
                }
            }
        }
    }

    @ViewBuilder
    private func locationRowLink<Content: View>(
        trip: Trip,
        locationID: UUID,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if routeListAllowsNavigation(for: trip) {
            NavigationLink(value: LocationDetailRoute(tripID: tripID, locationID: locationID)) {
                content()
            }
        } else {
            content()
        }
    }

    @ViewBuilder
    private func categoryListRow(loc: LocationItem) -> some View {
        HStack(alignment: .top, spacing: AppTheme.rowSpacing) {
            CategoryIconBadge(category: loc.category, size: 38)
            locationDetailsColumn(loc: loc, showCategory: false)
        }
    }

    private func locationDetailsColumn(loc: LocationItem, showCategory: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(loc.name)
                    .font(.headline)
                Spacer(minLength: 8)
                PriorityPill(priority: loc.visitPriority)
            }

            if showCategory {
                Text(loc.category.title)
                    .font(.caption)
                    .foregroundStyle(AppTheme.categoryTint(loc.category))
            }

            if let address = loc.address?.trimmingCharacters(in: .whitespacesAndNewlines), !address.isEmpty {
                Text(address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let hours = OpeningHoursFormatter.condensedListLine(openingHours: loc.openingHours, category: loc.category) {
                Label(hours, systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let notes = loc.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                Text(notes)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func routeOrderRow(index: Int, loc: LocationItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RouteStopIndexBadge(label: "\(index)")
            locationDetailsColumn(loc: loc, showCategory: true)
        }
    }

    @ViewBuilder
    private func routeOrderRow(index: String, loc: LocationItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RouteStopIndexBadge(label: index)
            locationDetailsColumn(loc: loc, showCategory: true)
        }
    }

    private func groupedLocations(for trip: Trip) -> [(category: LocationItem.Category, locations: [LocationItem])] {
        let groups = Dictionary(grouping: trip.locations, by: { $0.category })
        return groups
            .map { (category: $0.key, locations: $0.value.sorted(by: { $0.createdAt > $1.createdAt })) }
            .sorted(by: { $0.category.sortRank < $1.category.sortRank })
    }
}

#Preview("Trip detail") {
    PreviewShell.navigation {
        TripDetailView(tripID: PreviewData.parisTripID)
    }
    .environmentObject(TravelStore.preview)
    .appScreenBackground()
}
