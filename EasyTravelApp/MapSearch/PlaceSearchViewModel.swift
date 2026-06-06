import Combine
import Foundation
import MapKit

@MainActor
final class PlaceSearchViewModel: NSObject, ObservableObject {
    @Published var query: String = "" {
        didSet { completer.queryFragment = query }
    }

    @Published private(set) var completions: [MKLocalSearchCompletion] = []
    @Published private(set) var selectedName: String?
    @Published private(set) var selectedCoordinate: CLLocationCoordinate2D?
    @Published private(set) var selectedAddress: String?
    @Published private(set) var selectedCity: String?
    @Published private(set) var selectedCountry: String?
    @Published private(set) var selectedPhoneNumber: String?
    @Published private(set) var selectedURL: String?
    @Published private(set) var isSearching: Bool = false
    @Published private(set) var lastErrorMessage: String?
    /// True when no results matched city/country filter and unfiltered results are shown.
    @Published private(set) var isShowingUnfilteredFallback = false

    private let completer = MKLocalSearchCompleter()
    private var filterCity: String?
    private var filterCountry: String?

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func applyTripContext(_ context: TripPlaceSearchContext) {
        if let region = context.region {
            completer.region = region
        }
        updatePlaceFilter(city: context.city, country: context.country)
    }

    func updatePlaceFilter(city: String?, country: String?) {
        filterCity = Self.normalizedFilterToken(city)
        filterCountry = Self.normalizedFilterToken(country)
        if !completions.isEmpty || !query.isEmpty {
            completer.queryFragment = query
        }
    }

    func clearSelection() {
        selectedName = nil
        selectedCoordinate = nil
        selectedAddress = nil
        selectedCity = nil
        selectedCountry = nil
        selectedPhoneNumber = nil
        selectedURL = nil
        lastErrorMessage = nil
    }

    func select(_ completion: MKLocalSearchCompletion) async {
        isSearching = true
        lastErrorMessage = nil

        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)

        do {
            let response = try await search.start()
            guard let item = response.mapItems.first else {
                lastErrorMessage = "No result found for that place."
                isSearching = false
                return
            }
            selectedName = item.name ?? completion.title
            selectedCoordinate = MapPlaceFormatting.coordinate(from: item)
            selectedAddress = MapPlaceFormatting.postalLine(from: item)
            selectedCity = MapPlaceFormatting.city(from: item)
            selectedCountry = MapPlaceFormatting.country(from: item)
            selectedPhoneNumber = item.phoneNumber
            selectedURL = item.url?.absoluteString
            isSearching = false
        } catch {
            lastErrorMessage = "Search failed. Try a different query."
            isSearching = false
        }
    }

    private func applyFilters(to results: [MKLocalSearchCompletion]) -> [MKLocalSearchCompletion] {
        guard filterCity != nil || filterCountry != nil else { return results }
        return results.filter { matchesPlaceFilter($0) }
    }

    private func matchesPlaceFilter(_ completion: MKLocalSearchCompletion) -> Bool {
        let haystack = "\(completion.title) \(completion.subtitle)".lowercased()
        if let country = filterCountry, !haystack.contains(country) {
            return false
        }
        if let city = filterCity, !haystack.contains(city) {
            return false
        }
        return true
    }

    private static func normalizedFilterToken(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return t.isEmpty ? nil : t
    }
}

extension PlaceSearchViewModel: MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let raw = completer.results
        let filtered = applyFilters(to: raw)
        if filtered.isEmpty, !raw.isEmpty, filterCity != nil || filterCountry != nil {
            completions = Array(raw.prefix(12))
            isShowingUnfilteredFallback = true
        } else {
            completions = Array(filtered.prefix(12))
            isShowingUnfilteredFallback = false
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        completions = []
        isShowingUnfilteredFallback = false
        lastErrorMessage = "Autocomplete failed. Check network/location settings."
    }
}
