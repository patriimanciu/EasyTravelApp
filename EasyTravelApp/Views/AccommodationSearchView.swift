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
    @State private var hasSearched = false
    @State private var searchTask: Task<Void, Never>?
    @State private var activeSearch: MKLocalSearch?

    private let debounceNanos: UInt64 = 450_000_000
    private let minQueryLength = 2

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    searchField

                    Text(footerMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    resultsContent
                }
                .appPagePadding()
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .appScreenBackground()
            .navigationTitle("Search stay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppTheme.charcoal)
                }
            }
            .onChange(of: query) { _, newValue in
                scheduleSearch(for: newValue)
            }
            .onDisappear {
                searchTask?.cancel()
                activeSearch?.cancel()
            }
        }
        .tint(AppTheme.charcoal)
    }

    private var footerMessage: String {
        if let searchNote { return searchNote }
        if isSearching { return "Searching Apple Maps…" }
        if query.trimmingCharacters(in: .whitespacesAndNewlines).count < minQueryLength {
            return "Type at least \(minQueryLength) characters — results are biased near your trip stops when possible."
        }
        return "Results are biased near your trip stops when possible."
    }

    @ViewBuilder
    private var searchField: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppTheme.categoryPastelFill(.hotel))
                    .frame(width: 44, height: 44)
                Image(systemName: "bed.double.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.categoryTint(.hotel))
            }

            TextField("Hotel, street, neighborhood…", text: $query)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { scheduleSearch(for: query, immediate: true) }

            if isSearching {
                ProgressView()
                    .controlSize(.small)
            } else if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                    searchNote = nil
                    hasSearched = false
                    searchTask?.cancel()
                    activeSearch?.cancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(14)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .shadow(color: AppTheme.cardShadow, radius: AppTheme.cardShadowRadius, x: 0, y: AppTheme.cardShadowY)
    }

    @ViewBuilder
    private var resultsContent: some View {
        if isSearching, results.isEmpty {
            HStack(spacing: 10) {
                ProgressView()
                Text("Looking for places…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        } else if hasSearched, results.isEmpty {
            AppEmptyState(
                title: "No matches",
                systemImage: "magnifyingglass",
                message: "Try a shorter query or include the city name."
            )
        } else if !results.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: "Results", trailing: "\(results.count)")

                ForEach(Array(results.enumerated()), id: \.offset) { _, item in
                    Button {
                        pick(item)
                    } label: {
                        stayResultRow(item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func stayResultRow(_ item: MKMapItem) -> some View {
        HStack(alignment: .top, spacing: AppTheme.rowSpacing) {
            CategoryIconBadge(category: .hotel, size: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(primaryTitle(for: item))
                    .font(.headline)
                    .foregroundStyle(AppTheme.charcoal)
                    .multilineTextAlignment(.leading)
                if let subtitle = secondaryLine(for: item) {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .shadow(color: AppTheme.cardShadow, radius: AppTheme.cardShadowRadius, x: 0, y: AppTheme.cardShadowY)
    }

    private func scheduleSearch(for text: String, immediate: Bool = false) {
        searchTask?.cancel()
        activeSearch?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.count >= minQueryLength else {
            isSearching = false
            results = []
            searchNote = nil
            hasSearched = false
            return
        }

        searchTask = Task {
            if !immediate {
                try? await Task.sleep(nanoseconds: debounceNanos)
            }
            guard !Task.isCancelled else { return }
            await runSearch(query: trimmed)
        }
    }

    private func primaryTitle(for item: MKMapItem) -> String {
        if let name = item.name, !name.isEmpty { return name }
        return MapPlaceFormatting.shortAddress(from: item) ?? "Place"
    }

    private func secondaryLine(for item: MKMapItem) -> String? {
        if let cityWithContext = item.addressRepresentations?.cityWithContext {
            return cityWithContext
        }
        return MapPlaceFormatting.postalLine(from: item)
    }

    private func pick(_ item: MKMapItem) {
        let c = MapPlaceFormatting.coordinate(from: item)
        guard c.latitude >= -90, c.latitude <= 90, c.longitude >= -180, c.longitude <= 180 else {
            searchNote = "That result has no usable coordinates. Try another."
            return
        }
        let title = primaryTitle(for: item)
        onPick(title, c.latitude, c.longitude)
        dismiss()
    }

    @MainActor
    private func runSearch(query searchQuery: String) async {
        guard !searchQuery.isEmpty else { return }

        isSearching = true
        searchNote = nil

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchQuery
        request.resultTypes = [.address, .pointOfInterest]
        if let biasRegion {
            request.region = biasRegion
        }

        activeSearch?.cancel()
        let search = MKLocalSearch(request: request)
        activeSearch = search

        do {
            let response = try await search.start()
            guard !Task.isCancelled else { return }
            results = response.mapItems
            hasSearched = true
            if results.isEmpty {
                searchNote = "No results. Try adding the city or a landmark nearby."
            }
        } catch {
            guard !Task.isCancelled else { return }
            if (error as NSError).domain == MKErrorDomain, (error as NSError).code == MKError.loadingThrottled.rawValue {
                return
            }
            if error is CancellationError { return }
            results = []
            hasSearched = true
            if (error as NSError).domain == MKErrorDomain, (error as NSError).code == MKError.placemarkNotFound.rawValue {
                searchNote = "No results. Try adding the city or a landmark nearby."
            } else {
                searchNote = error.localizedDescription
            }
        }

        isSearching = false
    }
}

#Preview("Accommodation search") {
    AccommodationSearchView(
        biasRegion: MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522),
            span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
        ),
        onPick: { _, _, _ in }
    )
}
