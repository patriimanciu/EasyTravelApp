import MapKit
import SwiftUI

/// Search Apple’s map index for a hotel / address and return WGS84 coordinates (no manual lat/lon).
struct AccommodationSearchView: View {
    @Environment(\.dismiss) private var dismiss

    let biasRegion: MKCoordinateRegion?
    let onPick: (String, Double, Double) -> Void

    @State private var query: String = ""
    @State private var results: [MKMapItem] = []
    @State private var isSearching = false
    @State private var searchNote: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Hotel, street, neighborhood…", text: $query)
                        .textInputAutocapitalization(.sentences)
                        .onSubmit { Task { await runSearch() } }
                    Button {
                        Task { await runSearch() }
                    } label: {
                        if isSearching {
                            HStack {
                                Text("Searching…")
                                Spacer()
                                ProgressView()
                            }
                        } else {
                            Text("Search")
                        }
                    }
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
                } footer: {
                    if let searchNote {
                        Text(searchNote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Results are biased near your trip stops when possible.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Results") {
                    if !isSearching, results.isEmpty, !query.isEmpty, searchNote == nil {
                        ContentUnavailableView(
                            "No matches",
                            systemImage: "magnifyingglass",
                            description: Text("Try a shorter query or include the city name.")
                        )
                    }
                    ForEach(Array(results.enumerated()), id: \.offset) { _, item in
                        Button {
                            pick(item)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(primaryTitle(for: item))
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                if let subtitle = secondaryLine(for: item) {
                                    Text(subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Search stay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func primaryTitle(for item: MKMapItem) -> String {
        if let name = item.name, !name.isEmpty { return name }
        return item.placemark.title ?? "Place"
    }

    private func secondaryLine(for item: MKMapItem) -> String? {
        let lines = [
            item.placemark.thoroughfare,
            item.placemark.locality,
            item.placemark.country,
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        let s = lines.joined(separator: ", ")
        return s.isEmpty ? nil : s
    }

    private func pick(_ item: MKMapItem) {
        let c = item.placemark.coordinate
        guard c.latitude >= -90, c.latitude <= 90, c.longitude >= -180, c.longitude <= 180 else {
            searchNote = "That result has no usable coordinates. Try another."
            return
        }
        let title = primaryTitle(for: item)
        onPick(title, c.latitude, c.longitude)
        dismiss()
    }

    private func runSearch() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isSearching = true
        searchNote = nil

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = q
        request.resultTypes = [.address, .pointOfInterest]
        if let biasRegion {
            request.region = biasRegion
        }

        let search = MKLocalSearch(request: request)
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            search.start { response, error in
                Task { @MainActor in
                    isSearching = false
                    if let error {
                        results = []
                        searchNote = error.localizedDescription
                    } else {
                        results = response?.mapItems ?? []
                        if results.isEmpty {
                            searchNote = "No results. Try adding the city or a landmark nearby."
                        } else {
                            searchNote = nil
                        }
                    }
                    cont.resume()
                }
            }
        }
    }
}
