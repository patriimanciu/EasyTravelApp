import Foundation
import Combine
import SwiftUI

@MainActor
final class TravelStore: ObservableObject {
    @Published private(set) var trips: [Trip] = []
    @Published private(set) var inbox: [LocationItem] = []

    private let fileName = "easytravel_trips.json"

    init() {
        Task { await load() }
    }

    func addTrip(name: String, startDate: Date? = nil, endDate: Date? = nil) {
        trips.insert(Trip(name: name, startDate: startDate, endDate: endDate), at: 0)
        persistAsync()
    }

    func deleteTrips(at offsets: IndexSet) {
        trips.remove(atOffsets: offsets)
        persistAsync()
    }

    func addLocation(to tripID: Trip.ID, location: LocationItem) {
        guard let idx = trips.firstIndex(where: { $0.id == tripID }) else { return }
        trips[idx].locations.insert(location, at: 0)
        persistAsync()
    }

    func addLocations(to tripID: Trip.ID, locations: [LocationItem]) {
        guard let idx = trips.firstIndex(where: { $0.id == tripID }) else { return }
        guard !locations.isEmpty else { return }
        trips[idx].locations.insert(contentsOf: locations, at: 0)
        persistAsync()
    }

    func addToInbox(_ locations: [LocationItem]) {
        guard !locations.isEmpty else { return }
        inbox.insert(contentsOf: locations, at: 0)
        persistAsync()
    }

    func deleteInboxLocations(at offsets: IndexSet) {
        inbox.remove(atOffsets: offsets)
        persistAsync()
    }

    func deleteInboxLocation(locationID: LocationItem.ID) {
        inbox.removeAll(where: { $0.id == locationID })
        persistAsync()
    }

    func deleteInboxLocations(locationIDs: Set<LocationItem.ID>) {
        guard !locationIDs.isEmpty else { return }
        inbox.removeAll(where: { locationIDs.contains($0.id) })
        persistAsync()
    }

    func moveInboxLocation(_ locationID: LocationItem.ID, to tripID: Trip.ID) {
        guard let inboxIdx = inbox.firstIndex(where: { $0.id == locationID }) else { return }
        let loc = inbox.remove(at: inboxIdx)
        addLocation(to: tripID, location: loc)
        persistAsync()
    }

    func moveInboxLocations(_ locationIDs: Set<LocationItem.ID>, to tripID: Trip.ID) {
        let toMove = inbox.filter { locationIDs.contains($0.id) }
        guard !toMove.isEmpty else { return }
        inbox.removeAll(where: { locationIDs.contains($0.id) })
        addLocations(to: tripID, locations: toMove)
        persistAsync()
    }

    func deleteLocations(tripID: Trip.ID, at offsets: IndexSet) {
        guard let idx = trips.firstIndex(where: { $0.id == tripID }) else { return }
        trips[idx].locations.remove(atOffsets: offsets)
        persistAsync()
    }

    func deleteLocation(tripID: Trip.ID, locationID: LocationItem.ID) {
        guard let idx = trips.firstIndex(where: { $0.id == tripID }) else { return }
        trips[idx].locations.removeAll(where: { $0.id == locationID })
        persistAsync()
    }

    func replaceTrip(_ trip: Trip) {
        guard let idx = trips.firstIndex(where: { $0.id == trip.id }) else { return }
        trips[idx] = trip
        persistAsync()
    }

    /// Returns the location from a trip or from inbox (tripID == nil).
    func location(id: LocationItem.ID, tripID: Trip.ID?) -> LocationItem? {
        if let tripID {
            guard let tripIdx = trips.firstIndex(where: { $0.id == tripID }),
                  let loc = trips[tripIdx].locations.first(where: { $0.id == id })
            else { return nil }
            return loc
        }
        return inbox.first(where: { $0.id == id })
    }

    /// Updates a location (in a trip or in inbox). Pass tripID == nil for inbox.
    func updateLocation(tripID: Trip.ID?, location: LocationItem) {
        if let tripID {
            guard let tripIdx = trips.firstIndex(where: { $0.id == tripID }),
                  let locIdx = trips[tripIdx].locations.firstIndex(where: { $0.id == location.id })
            else { return }
            trips[tripIdx].locations[locIdx] = location
        } else {
            guard let idx = inbox.firstIndex(where: { $0.id == location.id }) else { return }
            inbox[idx] = location
        }
        persistAsync()
    }

    func load() async {
        do {
            let url = try dataURL()
            guard FileManager.default.fileExists(atPath: url.path) else {
                trips = SampleTrips.make()
                inbox = []
                persistAsync()
                return
            }

            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let decoded = try? decoder.decode(TravelData.self, from: data) {
                trips = decoded.trips
                inbox = decoded.inbox
            } else {
                // Backward compatibility: older versions stored only [Trip]
                trips = try decoder.decode([Trip].self, from: data)
                inbox = []
            }

            // If the file exists but is empty (or user previously saved no trips), seed defaults.
            if trips.isEmpty {
                trips = SampleTrips.make()
                persistAsync()
            }
        } catch {
            // If loading fails, fall back to sample data so the app is usable.
            trips = SampleTrips.make()
            inbox = []
            persistAsync()
        }
    }

    private func persistAsync() {
        let snapshot = TravelData(trips: trips, inbox: inbox)
        let url: URL? = try? dataURL()
        Task.detached(priority: .utility) { [fileName, url] in
            do {
                guard let url else { return }
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(snapshot)
                try data.write(to: url, options: [.atomic])
            } catch {
                // Intentionally ignore persistence failures for now.
            }
        }
    }

    private func dataURL() throws -> URL {
        try Self.dataURL(fileName: fileName)
    }

    nonisolated private static func dataURL(fileName: String) throws -> URL {
        let dir = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return dir.appendingPathComponent(fileName)
    }
}

