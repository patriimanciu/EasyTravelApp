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
        trips[idx].plannedDays = nil
        trips[idx].plannedRoutePolyline = nil
        persistAsync()
    }

    func addLocations(to tripID: Trip.ID, locations: [LocationItem]) {
        guard let idx = trips.firstIndex(where: { $0.id == tripID }) else { return }
        guard !locations.isEmpty else { return }
        trips[idx].locations.insert(contentsOf: locations, at: 0)
        trips[idx].plannedDays = nil
        trips[idx].plannedRoutePolyline = nil
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
        trips[idx].plannedDays = nil
        trips[idx].plannedRoutePolyline = nil
        persistAsync()
    }

    func deleteLocation(tripID: Trip.ID, locationID: LocationItem.ID) {
        guard let idx = trips.firstIndex(where: { $0.id == tripID }) else { return }
        trips[idx].locations.removeAll(where: { $0.id == locationID })
        trips[idx].plannedDays = nil
        trips[idx].plannedRoutePolyline = nil
        persistAsync()
    }

    func replaceTrip(_ trip: Trip) {
        guard let idx = trips.firstIndex(where: { $0.id == trip.id }) else { return }
        trips[idx] = trip
        persistAsync()
    }

    /// Updates trip name, dates, and optional accommodation hub. Changing dates or accommodation clears an applied route plan.
    func updateTripMetadata(
        id: Trip.ID,
        name: String,
        startDate: Date?,
        endDate: Date?,
        accommodation: TripAccommodation?
    ) {
        guard let idx = trips.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let oldStart = trips[idx].startDate
        let oldEnd = trips[idx].endDate
        let oldAcc = trips[idx].accommodation
        trips[idx].name = trimmed
        trips[idx].startDate = startDate
        trips[idx].endDate = endDate
        trips[idx].accommodation = accommodation
        if oldStart != startDate || oldEnd != endDate || oldAcc != accommodation {
            trips[idx].plannedDays = nil
            trips[idx].plannedRoutePolyline = nil
        }
        persistAsync()
    }

    /// Reorders `trip.locations` to match backend TTDP day plans (flattened by `dayIndex`), then any remaining stops.
    func applyPlannedRoute(tripID: Trip.ID, plan: PlanItineraryResponseDTO) {
        guard let tripIdx = trips.firstIndex(where: { $0.id == tripID }) else { return }
        let trip = trips[tripIdx]
        let sortedDays = plan.days.sorted { $0.dayIndex < $1.dayIndex }
        var planned: [TripPlannedDay] = []
        for day in sortedDays {
            let uuids = day.orderedStopIds.compactMap { UUID(uuidString: $0) }
            planned.append(
                TripPlannedDay(
                    dayIndex: day.dayIndex,
                    orderedLocationIds: uuids,
                    routePolyline: day.routePolyline
                )
            )
        }
        trips[tripIdx].plannedDays = planned.isEmpty ? nil : planned
        trips[tripIdx].plannedRoutePolyline = nil
        syncTripLocationsWithPlannedDays(tripIdx: tripIdx)
        persistAsync()
    }

    /// Adds a stop that is not in any day yet (e.g. after a new import) onto a visit day.
    func addLocationToPlannedDay(tripID: Trip.ID, locationID: UUID, dayIndex: Int) {
        movePlannedLocation(
            tripID: tripID,
            locationID: locationID,
            fromDayIndex: nil,
            toDayIndex: dayIndex,
            beforeLocationID: nil
        )
    }

    /// Moves a stop into another visit day (or reorders within a day). Clears affected day polylines so the map recomputes walking paths.
    func movePlannedLocation(
        tripID: Trip.ID,
        locationID: UUID,
        fromDayIndex: Int?,
        toDayIndex: Int,
        beforeLocationID: UUID?
    ) {
        guard let tripIdx = trips.firstIndex(where: { $0.id == tripID }),
              var days = trips[tripIdx].plannedDays,
              !days.isEmpty,
              let toPos = days.firstIndex(where: { $0.dayIndex == toDayIndex })
        else { return }

        if let fromDayIndex,
           let fromPos = days.firstIndex(where: { $0.dayIndex == fromDayIndex }) {
            days[fromPos].orderedLocationIds.removeAll { $0 == locationID }
            days[fromPos].routePolyline = nil
        }

        var targetIds = days[toPos].orderedLocationIds
        if targetIds.contains(locationID) {
            targetIds.removeAll { $0 == locationID }
        }

        let insertIndex: Int
        if let beforeLocationID, let beforePos = targetIds.firstIndex(of: beforeLocationID) {
            insertIndex = beforePos
        } else {
            insertIndex = targetIds.count
        }
        targetIds.insert(locationID, at: insertIndex)
        days[toPos].orderedLocationIds = targetIds
        days[toPos].routePolyline = nil

        trips[tripIdx].plannedDays = days
        syncTripLocationsWithPlannedDays(tripIdx: tripIdx)
        persistAsync()
    }

    /// Reorders stops within one visit day (List edit mode / onMove).
    func reorderPlannedStops(
        tripID: Trip.ID,
        dayIndex: Int,
        fromOffsets: IndexSet,
        toOffset: Int
    ) {
        guard let tripIdx = trips.firstIndex(where: { $0.id == tripID }),
              var days = trips[tripIdx].plannedDays,
              let dayPos = days.firstIndex(where: { $0.dayIndex == dayIndex })
        else { return }

        var ids = days[dayPos].orderedLocationIds
        ids.move(fromOffsets: fromOffsets, toOffset: toOffset)
        days[dayPos].orderedLocationIds = ids
        days[dayPos].routePolyline = nil
        trips[tripIdx].plannedDays = days
        syncTripLocationsWithPlannedDays(tripIdx: tripIdx)
        persistAsync()
    }

    private func syncTripLocationsWithPlannedDays(tripIdx: Int) {
        let trip = trips[tripIdx]
        let byID = Dictionary(uniqueKeysWithValues: trip.locations.map { ($0.id, $0) })
        var ordered: [LocationItem] = []
        var seen = Set<LocationItem.ID>()
        for day in (trip.plannedDays ?? []).sorted(by: { $0.dayIndex < $1.dayIndex }) {
            for id in day.orderedLocationIds {
                if let loc = byID[id], seen.insert(id).inserted {
                    ordered.append(loc)
                }
            }
        }
        for loc in trip.locations where !seen.contains(loc.id) {
            ordered.append(loc)
        }
        trips[tripIdx].locations = ordered
    }

    func setVisitPriority(tripID: Trip.ID, locationID: LocationItem.ID, priority: LocationItem.VisitPriority) {
        guard let tripIdx = trips.firstIndex(where: { $0.id == tripID }),
              let locIdx = trips[tripIdx].locations.firstIndex(where: { $0.id == locationID })
        else { return }
        guard trips[tripIdx].locations[locIdx].visitPriority != priority else { return }
        trips[tripIdx].locations[locIdx].visitPriority = priority
        trips[tripIdx].plannedDays = nil
        trips[tripIdx].plannedRoutePolyline = nil
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
            let old = trips[tripIdx].locations[locIdx]
            trips[tripIdx].locations[locIdx] = location
            if old.visitPriority != location.visitPriority {
                trips[tripIdx].plannedDays = nil
                trips[tripIdx].plannedRoutePolyline = nil
            }
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

