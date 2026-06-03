import SwiftUI

struct InboxView: View {
    @EnvironmentObject private var store: TravelStore

    @State private var isSelectionMode = false
    @State private var selectedIDs: Set<LocationItem.ID> = []
    @State private var isPresentingAssign = false
    @State private var confirmBulkDelete = false
    @State private var isPresentingImport = false
    @State private var categoryFilter: LocationItem.Category?

    private var groupedInbox: [(category: LocationItem.Category, locations: [LocationItem])] {
        let groups = Dictionary(grouping: store.inbox, by: { $0.category })
        return groups
            .map { (category: $0.key, locations: $0.value.sorted(by: { $0.createdAt > $1.createdAt })) }
            .sorted(by: { $0.category.sortRank < $1.category.sortRank })
    }

    private var displayedGroups: [(category: LocationItem.Category, locations: [LocationItem])] {
        guard let categoryFilter else { return groupedInbox }
        return groupedInbox.filter { $0.category == categoryFilter }
    }

    private var visibleLocationCount: Int {
        displayedGroups.reduce(0) { $0 + $1.locations.count }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                HomeHeaderView(
                    greeting: "Inbox",
                    subtitle: "Saved places",
                    onAddTrip: nil
                )
                .padding(.top, 8)

                ImportHeroCard {
                    isPresentingImport = true
                }

                if !store.inbox.isEmpty {
                    CategoryFilterScroll(selectedCategory: $categoryFilter)
                        .padding(.horizontal, -AppTheme.pagePadding)

                    HStack {
                        SectionTitle(
                            title: categoryFilter?.title ?? "All places",
                            trailing: "\(visibleLocationCount)"
                        )
                        Spacer()
                        Button(isSelectionMode ? "Done" : "Select") {
                            if isSelectionMode {
                                isSelectionMode = false
                                selectedIDs = []
                            } else {
                                isSelectionMode = true
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.charcoal)
                    }

                    if isSelectionMode, !selectedIDs.isEmpty {
                        selectionActionBar
                    }
                }

                if store.inbox.isEmpty {
                    AppEmptyState(
                        title: "Nothing in Inbox",
                        systemImage: "tray",
                        message: "Import from a video to collect places before adding them to a trip."
                    )
                } else if displayedGroups.isEmpty {
                    AppEmptyState(
                        title: "No matches",
                        systemImage: categoryFilter?.symbolName ?? "line.3.horizontal.decrease.circle",
                        message: "No inbox places in this category. Try another filter or choose All."
                    )
                } else {
                    ForEach(displayedGroups, id: \.category) { group in
                        VStack(alignment: .leading, spacing: 16) {
                            if categoryFilter == nil {
                                HStack(spacing: 8) {
                                    CategoryIconBadge(category: group.category, size: 32)
                                    Text(group.category.title)
                                        .font(.headline)
                                        .foregroundStyle(AppTheme.charcoal)
                                }
                            }

                            ForEach(group.locations) { loc in
                                rowContent(loc: loc)
                            }
                        }
                    }
                }
            }
            .appPagePadding()
            .padding(.top, 12)
            .appBottomTabPadding()
        }
        .appScreenBackground()
        .confirmationDialog(
            "Delete \(selectedIDs.count) location\(selectedIDs.count == 1 ? "" : "s") from inbox?",
            isPresented: $confirmBulkDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                let ids = selectedIDs
                store.deleteInboxLocations(locationIDs: ids)
                selectedIDs = []
                if store.inbox.isEmpty {
                    isSelectionMode = false
                    categoryFilter = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $isPresentingAssign) {
            AssignToTripView(isPresented: $isPresentingAssign, selectedLocationIDs: selectedIDs)
                .environmentObject(store)
        }
        .sheet(isPresented: $isPresentingImport) {
            ImportFromVideoView(isPresented: $isPresentingImport)
        }
        .onChange(of: isPresentingAssign) { _, isPresented in
            if !isPresented {
                selectedIDs = []
                isSelectionMode = false
            }
        }
        .navigationDestination(for: LocationDetailRoute.self) { route in
            LocationDetailView(locationID: route.locationID, tripID: route.tripID)
                .environmentObject(store)
        }
    }

    private var selectionActionBar: some View {
        HStack(spacing: 12) {
            Button(role: .destructive) {
                confirmBulkDelete = true
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(.caption.weight(.semibold))
            }
            Spacer()
            Button {
                isPresentingAssign = true
            } label: {
                Text("Assign \(selectedIDs.count)…")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(AppTheme.charcoal, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .softCard(cardPadding: 12)
    }

    @ViewBuilder
    private func rowContent(loc: LocationItem) -> some View {
        let isSelected = selectedIDs.contains(loc.id)
        let assignContextMenu: () -> Void = {
            selectedIDs = [loc.id]
            isPresentingAssign = true
        }
        if isSelectionMode {
            Button {
                if selectedIDs.contains(loc.id) {
                    selectedIDs.remove(loc.id)
                } else {
                    selectedIDs.insert(loc.id)
                }
            } label: {
                InboxLocationCard(location: loc, showCheckmark: true, isSelected: isSelected)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Assign to trip…", action: assignContextMenu)
                Button("Delete", role: .destructive) {
                    store.deleteInboxLocations(locationIDs: Set([loc.id]))
                    selectedIDs.remove(loc.id)
                }
            }
        } else {
            NavigationLink(value: LocationDetailRoute(tripID: nil, locationID: loc.id)) {
                InboxLocationCard(location: loc)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Assign to trip…", action: assignContextMenu)
                Button("Delete", role: .destructive) {
                    store.deleteInboxLocation(locationID: loc.id)
                }
            }
        }
    }
}

#Preview("Inbox — with data") {
    PreviewShell.navigation {
        InboxView()
            .toolbar(.hidden, for: .navigationBar)
    }
    .environmentObject(TravelStore.preview)
    .appScreenBackground()
}

#Preview("Inbox — filtered") {
    PreviewShell.navigation {
        InboxView()
            .toolbar(.hidden, for: .navigationBar)
    }
    .environmentObject(TravelStore.preview)
    .appScreenBackground()
}

#Preview("Inbox — empty") {
    PreviewShell.navigation {
        InboxView()
            .toolbar(.hidden, for: .navigationBar)
    }
    .environmentObject(PreviewData.emptyStore)
    .appScreenBackground()
}
