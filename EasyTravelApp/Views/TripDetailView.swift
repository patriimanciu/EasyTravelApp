import SwiftUI

struct TripDetailView: View {
    @EnvironmentObject private var store: TravelStore
    let tripID: Trip.ID

    @State private var isPresentingAddLocation = false
    @State private var isPresentingEditTrip = false
    @State private var isPresentingPlanRoute = false
    @State private var selectedTab: Tab = .list
    @State private var listMode: ListMode = .byCategory
    /// Index into `sortedPlannedDays(trip)` for map + multi-day route list.
    @State private var mapSelectedDay: Int = 0
    /// Enables native List reorder controls (`onMove`) within each day.
    @State private var isEditingRouteOrder = false
    /// Shown after swipe “Add to day” when the trip has multiple visit days.
    @State private var addToDayPickerLocationID: UUID?

    enum ListMode: String, CaseIterable, Identifiable {
        case byCategory = "Categories"
        case routeOrder = "Route order"

        var id: String { rawValue }
    }

    enum Tab: String, CaseIterable, Identifiable {
        case list = "List"
        case map = "Map"

        var id: String { rawValue }
    }

    private var trip: Trip? {
        store.trips.first(where: { $0.id == tripID })
    }

    private func routeListAllowsNavigation(for trip: Trip) -> Bool {
        !(listMode == .routeOrder && isEditingRouteOrder && !(trip.plannedDays?.isEmpty ?? true))
    }

    var body: some View {
        Group {
            if let trip {
                VStack(spacing: 0) {
                    Picker("View", selection: $selectedTab) {
                        ForEach(Tab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 8)

                    if selectedTab == .map {
                        mapTabContent(trip: trip)
                    } else {
                        tripListContent(trip: trip)
                    }
                }
                .navigationTitle(trip.name)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if !trip.locations.isEmpty, trip.locations.count >= 2 {
                            Button {
                                isPresentingPlanRoute = true
                            } label: {
                                Label("Plan route", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isPresentingEditTrip = true
                        } label: {
                            Label("Trip settings", systemImage: "gearshape")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        if selectedTab == .list,
                           listMode == .routeOrder,
                           !(trip.plannedDays?.isEmpty ?? true) {
                            Button(isEditingRouteOrder ? "Done" : "Reorder") {
                                isEditingRouteOrder.toggle()
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isPresentingAddLocation = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Add location")
                    }
                }
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
                .onChange(of: selectedTab) { _, tab in
                    if tab == .map, sortedPlannedDays(for: trip).count <= 1 {
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
                    Picker("List mode", selection: $listMode) {
                        ForEach(ListMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            if listMode == .byCategory {
                categoryListSections(trip: trip)
            } else {
                routeOrderSections(trip: trip)
            }
        }
        .environment(
            \.editMode,
            .constant(
                listMode == .routeOrder && !(trip.plannedDays?.isEmpty ?? true) && isEditingRouteOrder
                    ? .active
                    : .inactive
            )
        )
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
                        }
                        .contextMenu {
                            priorityMenu(locationID: loc.id)
                        }
                    }
                    .onDelete { offsets in
                        let idsToDelete = offsets.compactMap { index in
                            group.locations[safe: index]?.id
                        }
                        for id in idsToDelete {
                            store.deleteLocation(tripID: tripID, locationID: id)
                        }
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
                    Text("These stops were not assigned when you last computed the route. Tap + or swipe right to add them to a day.")
                        .font(.caption)
                }
            }
        }
    }

    @ViewBuilder
    private func mapTabContent(trip: Trip) -> some View {
        let planDays = sortedPlannedDays(for: trip)
        VStack(spacing: 0) {
            if planDays.isEmpty, trip.locations.count >= 2 {
                Text("Run Plan route, then Compute, to assign stops to each day and show one day at a time on the map.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(Color(.secondarySystemBackground))
            }
            if planDays.count > 1 {
                mapDayChips(days: planDays, selection: $mapSelectedDay)
            } else if planDays.count == 1 {
                Text("Day 1 (all planned stops)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
            }
            TripMapView(
                trip: trip,
                plannedDayIndex: planDays.isEmpty ? nil : mapSelectedDay
            )
        }
    }

    private func mapDayChips(days: [TripPlannedDay], selection: Binding<Int>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(days.enumerated()), id: \.offset) { idx, day in
                    let isOn = selection.wrappedValue == idx
                    Button {
                        selection.wrappedValue = idx
                    } label: {
                        Text("Day \(day.dayIndex + 1)")
                            .font(.subheadline.weight(isOn ? .semibold : .regular))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .foregroundStyle(isOn ? Color.white : Color.primary)
                            .background(isOn ? Color.accentColor : Color(.secondarySystemFill), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
        .padding(.top, 6)
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
                    .foregroundStyle(Color.accentColor)
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
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(loc.name)
                    .font(.headline)
                Spacer(minLength: 8)
                priorityBadge(loc.visitPriority)
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
    private func priorityBadge(_ priority: LocationItem.VisitPriority) -> some View {
        Text(priority.title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(priorityColor(priority))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(priorityColor(priority).opacity(0.14), in: Capsule())
    }

    private func priorityColor(_ priority: LocationItem.VisitPriority) -> Color {
        switch priority {
        case .mustSee: .orange
        case .high: .blue
        case .normal: .secondary
        case .ifTime: .mint
        case .low: .gray
        }
    }

    private func routeOrderListContent(loc: LocationItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(loc.name)
                    .font(.headline)
                Spacer(minLength: 8)
                priorityBadge(loc.visitPriority)
            }
            Text(loc.category.title)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let address = loc.address?.trimmingCharacters(in: .whitespacesAndNewlines), !address.isEmpty {
                Text(address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func routeOrderRow(index: Int, loc: LocationItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(minWidth: 22, alignment: .leading)
            routeOrderListContent(loc: loc)
        }
    }

    @ViewBuilder
    private func routeOrderRow(index: String, loc: LocationItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(index)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(minWidth: 22, alignment: .leading)
            routeOrderListContent(loc: loc)
        }
    }

    private func groupedLocations(for trip: Trip) -> [(category: LocationItem.Category, locations: [LocationItem])] {
        let groups = Dictionary(grouping: trip.locations, by: { $0.category })
        return groups
            .map { (category: $0.key, locations: $0.value.sorted(by: { $0.createdAt > $1.createdAt })) }
            .sorted(by: { $0.category.sortRank < $1.category.sortRank })
    }
}

