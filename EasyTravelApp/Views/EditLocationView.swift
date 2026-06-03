import SwiftUI

struct EditLocationView: View {
    @EnvironmentObject private var store: TravelStore
    @Environment(\.dismiss) private var dismiss

    let locationID: LocationItem.ID
    let tripID: Trip.ID?

    @State private var name: String = ""
    @State private var category: LocationItem.Category = .other
    @State private var address: String = ""
    @State private var phoneNumber: String = ""
    @State private var urlString: String = ""
    @State private var openingHoursDraftText: String = ""
    @State private var notes: String = ""
    @State private var visitPriority: LocationItem.VisitPriority = .normal
    @State private var initialLocation: LocationItem?

    private var categories: [LocationItem.Category] {
        LocationItem.Category.allCases.sorted(by: { $0.sortRank < $1.sortRank })
    }

    private var currentLocation: LocationItem? {
        store.location(id: locationID, tripID: tripID)
    }

    var body: some View {
        Group {
            if initialLocation != nil {
                formContent()
            } else {
                ContentUnavailableView("Location not found", systemImage: "mappin.slash")
            }
        }
        .navigationTitle("Edit")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
            }
        }
        .onAppear(perform: loadFromStore)
        .onChange(of: currentLocation?.id) { _, _ in loadFromStore() }
    }

    @ViewBuilder
    private func formContent() -> some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)
                Picker("Category", selection: $category) {
                    ForEach(categories) { cat in
                        Text(cat.title).tag(cat)
                    }
                }
            } header: {
                Text("Place")
            }

            Section {
                TextField("Address", text: $address)
                    .textInputAutocapitalization(.words)
                TextField("Phone", text: $phoneNumber)
                    .keyboardType(.phonePad)
                TextField("Website", text: $urlString)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                TextEditor(text: $openingHoursDraftText)
                    .frame(minHeight: 140)
            } header: {
                Text("Details")
            } footer: {
                Text("Opening hours: one line per day (e.g. “Monday: 9:00 AM – 5:00 PM”).")
                    .font(.footnote)
            }

            Section {
                Picker("Priority", selection: $visitPriority) {
                    ForEach(LocationItem.VisitPriority.allCases.sorted(by: { $0.rawValue > $1.rawValue })) { p in
                        Text(p.title).tag(p)
                    }
                }
                Text(visitPriority.planningHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Itinerary priority")
            }

            Section {
                TextField("What I want to do here", text: $notes, axis: .vertical)
                    .lineLimit(3...10)
            } header: {
                Text("Notes")
            }
        }
    }

    private func loadFromStore() {
        guard let loc = currentLocation else {
            initialLocation = nil
            return
        }
        initialLocation = loc
        name = loc.name
        category = loc.category
        address = loc.address ?? ""
        phoneNumber = loc.phoneNumber ?? ""
        urlString = loc.url ?? ""
        openingHoursDraftText = (loc.openingHours ?? []).joined(separator: "\n")
        notes = loc.notes ?? ""
        visitPriority = loc.visitPriority
    }

    private func nonBlank(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private func parseHoursLines(_ text: String) -> [String]? {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return lines.isEmpty ? nil : lines
    }

    private func save() {
        guard let loc = initialLocation else { return }

        let updated = LocationItem(
            id: loc.id,
            name: nonBlank(name) ?? loc.name,
            latitude: loc.latitude,
            longitude: loc.longitude,
            category: category,
            notes: nonBlank(notes),
            address: nonBlank(address),
            phoneNumber: nonBlank(phoneNumber),
            url: nonBlank(urlString),
            openingHours: parseHoursLines(openingHoursDraftText),
            visitPriority: visitPriority,
            createdAt: loc.createdAt,
            source: loc.source
        )

        store.updateLocation(tripID: tripID, location: updated)
        dismiss()
    }
}

#Preview("Edit location") {
    PreviewShell.navigation {
        EditLocationView(
            locationID: PreviewData.parisLocationID,
            tripID: PreviewData.parisTripID
        )
    }
    .environmentObject(TravelStore.preview)
}