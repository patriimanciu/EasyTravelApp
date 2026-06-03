import SwiftUI
import MapKit

struct AddLocationView: View {
    @EnvironmentObject private var store: TravelStore
    let tripID: Trip.ID
    @Binding var isPresented: Bool

    @StateObject private var searchVM = PlaceSearchViewModel()

    @State private var name: String = ""
    @State private var category: LocationItem.Category = .landmark
    @State private var notes: String = ""

    private var canSave: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return searchVM.selectedCoordinate != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Search on Maps") {
                    TextField("Search place", text: $searchVM.query)
                        .textInputAutocapitalization(.words)

                    if searchVM.isSearching {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Searching…")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let msg = searchVM.lastErrorMessage {
                        Text(msg)
                            .foregroundStyle(.red)
                    }

                    if let selectedName = searchVM.selectedName,
                       let coord = searchVM.selectedCoordinate {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Selected")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(selectedName)
                                .font(.headline)
                            Text(String(format: "%.5f, %.5f", coord.latitude, coord.longitude))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else if !searchVM.query.isEmpty {
                        ForEach(searchVM.completions, id: \.self) { completion in
                            Button {
                                Task {
                                    await searchVM.select(completion)
                                    if let selectedName = searchVM.selectedName {
                                        name = selectedName
                                    } else {
                                        name = completion.title
                                    }
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(completion.title)
                                    if !completion.subtitle.isEmpty {
                                        Text(completion.subtitle)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } else {
                        Text("Type a place name to search (e.g. “Louvre Museum”).")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Location") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)

                    Picker("Category", selection: $category) {
                        ForEach(LocationItem.Category.allCases.sorted(by: { $0.sortRank < $1.sortRank })) { cat in
                            Text(cat.title).tag(cat)
                        }
                    }

                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("New Location")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        guard let coord = searchVM.selectedCoordinate else { return }
                        let notesTrimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                        let loc = LocationItem(
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            latitude: coord.latitude,
                            longitude: coord.longitude,
                            category: category,
                            notes: notesTrimmed.isEmpty ? nil : notesTrimmed,
                            address: searchVM.selectedAddress,
                            phoneNumber: searchVM.selectedPhoneNumber,
                            url: searchVM.selectedURL,
                            openingHours: nil,
                            source: .manual()
                        )
                        store.addLocation(to: tripID, location: loc)
                        isPresented = false
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}

#Preview("Add location") {
    @Previewable @State var isPresented = true
    AddLocationView(tripID: PreviewData.parisTripID, isPresented: $isPresented)
        .environmentObject(TravelStore.preview)
}