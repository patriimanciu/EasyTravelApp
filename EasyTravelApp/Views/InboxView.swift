import SwiftUI

struct InboxView: View {
    @EnvironmentObject private var store: TravelStore

    @State private var isSelectionMode = false
    @State private var selectedIDs: Set<LocationItem.ID> = []
    @State private var isPresentingAssign = false
    @State private var confirmBulkDelete = false
    @State private var isPresentingImport = false

    private var groupedInbox: [(category: LocationItem.Category, locations: [LocationItem])] {
        let groups = Dictionary(grouping: store.inbox, by: { $0.category })
        return groups
            .map { (category: $0.key, locations: $0.value.sorted(by: { $0.createdAt > $1.createdAt })) }
            .sorted(by: { $0.category.sortRank < $1.category.sortRank })
    }

    var body: some View {
        List {
            if store.inbox.isEmpty {
                ContentUnavailableView("Nothing in Inbox", systemImage: "tray")
            } else {
                ForEach(groupedInbox, id: \.category) { group in
                    Section(group.category.title) {
                        ForEach(group.locations) { loc in
                            rowContent(loc: loc)
                        }
                        .onDelete { offsets in
                            guard !isSelectionMode else { return }
                            let idsToDelete = offsets.compactMap { index in
                                group.locations[safe: index]?.id
                            }
                            for id in idsToDelete {
                                store.deleteInboxLocation(locationID: id)
                                selectedIDs.remove(id)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Inbox")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if isSelectionMode {
                    Button("Done") {
                        isSelectionMode = false
                        selectedIDs = []
                    }
                } else {
                    Button {
                        isPresentingImport = true
                    } label: {
                        Image(systemName: "tray.and.arrow.down")
                    }
                    .accessibilityLabel("Import from video")
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if isSelectionMode {
                    Menu {
                        Button("Select All") {
                            selectedIDs = Set(store.inbox.map(\.id))
                        }
                        .disabled(store.inbox.isEmpty)
                        if !selectedIDs.isEmpty {
                            Button("Clear Selection") {
                                selectedIDs = []
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    if !selectedIDs.isEmpty {
                        Button(role: .destructive) {
                            confirmBulkDelete = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button("Assign \(selectedIDs.count)…") {
                            isPresentingAssign = true
                        }
                        .fontWeight(.semibold)
                    }
                } else {
                    Button("Select") {
                        isSelectionMode = true
                    }
                }
            }
        }
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
                rowLabel(loc: loc, isSelected: isSelected, showCheckmark: true)
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
                rowLabel(loc: loc, isSelected: false, showCheckmark: false)
            }
            .contextMenu {
                Button("Assign to trip…", action: assignContextMenu)
                Button("Delete", role: .destructive) {
                    store.deleteInboxLocation(locationID: loc.id)
                }
            }
        }
    }

    private func rowLabel(loc: LocationItem, isSelected: Bool, showCheckmark: Bool) -> some View {
        HStack(spacing: 12) {
            if showCheckmark {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(loc.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if let notes = loc.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
