import SwiftUI

struct InboxView: View {
    @EnvironmentObject private var store: TravelStore

    @State private var isSelectionMode = false
    @State private var selectedIDs: Set<LocationItem.ID> = []
    @State private var isPresentingAssign = false

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
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if isSelectionMode {
                    if !selectedIDs.isEmpty {
                        HStack(spacing: 16) {
                            Button("Clear") {
                                selectedIDs = []
                            }
                            Button("Assign \(selectedIDs.count)…") {
                                isPresentingAssign = true
                            }
                            .fontWeight(.semibold)
                        }
                    }
                } else {
                    Button("Select") {
                        isSelectionMode = true
                    }
                }
            }
        }
        .sheet(isPresented: $isPresentingAssign) {
            AssignToTripView(isPresented: $isPresentingAssign, selectedLocationIDs: selectedIDs)
                .environmentObject(store)
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
            }
        } else {
            NavigationLink(value: LocationDetailRoute(tripID: nil, locationID: loc.id)) {
                rowLabel(loc: loc, isSelected: false, showCheckmark: false)
            }
            .contextMenu {
                Button("Assign to trip…", action: assignContextMenu)
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
