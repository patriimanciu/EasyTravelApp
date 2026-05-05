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
    @Published private(set) var selectedPhoneNumber: String?
    @Published private(set) var selectedURL: String?
    @Published private(set) var isSearching: Bool = false
    @Published private(set) var lastErrorMessage: String?

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func clearSelection() {
        selectedName = nil
        selectedCoordinate = nil
        selectedAddress = nil
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
            let pm = item.placemark
            selectedName = item.name ?? completion.title
            selectedCoordinate = pm.coordinate
            selectedAddress = formatAddress(pm)
            selectedPhoneNumber = item.phoneNumber
            selectedURL = item.url?.absoluteString
            isSearching = false
        } catch {
            lastErrorMessage = "Search failed. Try a different query."
            isSearching = false
        }
    }

    private func formatAddress(_ placemark: MKPlacemark) -> String? {
        var parts: [String] = []
        if let sub = placemark.subThoroughfare { parts.append(sub) }
        if let thoroughfare = placemark.thoroughfare { parts.append(thoroughfare) }
        if let locality = placemark.locality { parts.append(locality) }
        if let admin = placemark.administrativeArea, !parts.contains(admin) { parts.append(admin) }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

extension PlaceSearchViewModel: MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        completions = Array(completer.results.prefix(12))
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        completions = []
        lastErrorMessage = "Autocomplete failed. Check network/location settings."
    }
}

