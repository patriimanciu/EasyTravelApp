import Foundation
import Combine
import SwiftUI
import CoreLocation

enum TripLocationDeletionImpact: Equatable {
    /// No applied route, or stop is not assigned to any visit day.
    case unplanned
    /// Stop is removed from its day(s); the rest of the route stays.
    case adjustPlan
    /// Stop is the only one on at least one visit day — removing it clears the route.
    case resetsRoute
}

private func videoImportNonBlank(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? nil : t
}

private func videoImportHoursLines(from raw: String?) -> [String]? {
    guard let raw = videoImportNonBlank(raw) else { return nil }
    let lines = raw
        .split(whereSeparator: \.isNewline)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    return lines.isEmpty ? nil : lines
}

private func resolveVideoImportLocation(
    next: LocationDTO,
    trimmedVideoURL: String,
    placesKey: String
) async -> LocationItem? {
    do {
        let trimmedBackendAddr = videoImportNonBlank(next.address)
        let place = try await LocationResolver.resolvePlace(
            name: next.name,
            city: next.city,
            address: trimmedBackendAddr
        )
        let latitude = place.coordinate.latitude
        let longitude = place.coordinate.longitude
        let address = place.formattedAddress ?? trimmedBackendAddr
        let phoneNumber = videoImportNonBlank(place.phoneNumber) ?? videoImportNonBlank(next.phoneNumber)
        let url = videoImportNonBlank(place.url) ?? videoImportNonBlank(next.url)
        let backendHoursLines = videoImportHoursLines(from: next.openingHours)
        let mergedHoursLines: [String]?
        if let backendHoursLines {
            mergedHoursLines = backendHoursLines
        } else if placesKey.isEmpty {
            mergedHoursLines = nil
        } else {
            let (hours, _) = await PlacesOpeningHoursFetcher.weekdayDescriptionsWithDebug(
                placeName: next.name,
                city: next.city,
                coordinate: place.coordinate,
                apiKey: placesKey
            )
            mergedHoursLines = hours
        }
        let notesParts = ["Imported from video", next.city]
        return LocationItem(
            name: next.name,
            latitude: latitude,
            longitude: longitude,
            category: LocationItem.category(fromBackendString: next.category),
            notes: notesParts.joined(separator: " • "),
            address: address,
            city: next.city,
            country: place.country,
            phoneNumber: phoneNumber,
            url: url,
            openingHours: mergedHoursLines,
            source: .init(
                kind: .videoExtraction,
                videoURL: trimmedVideoURL,
                rawPayload: nil
            )
        )
    } catch {
        return nil
    }
}

@MainActor
final class TravelStore: ObservableObject {
    @Published private(set) var trips: [Trip] = []
    @Published private(set) var inbox: [LocationItem] = []
    @Published private(set) var videoImportPhase: VideoImportPhase = .idle
    @Published private(set) var routePlanPhase: RoutePlanPhase = .idle

    private let fileName = "easytravel_trips.json"
    private var videoImportSuccessDismissTask: Task<Void, Never>?
    private var routePlanDismissTask: Task<Void, Never>?

    init() {
        Task { await load() }
    }

    /// Synchronous in-memory store for SwiftUI previews (skips disk load).
    init(previewTrips: [Trip], previewInbox: [LocationItem] = []) {
        trips = previewTrips
        inbox = previewInbox
    }

    static var preview: TravelStore { PreviewData.store }

    // MARK: - Video import banner

    func beginVideoImport() {
        videoImportSuccessDismissTask?.cancel()
        videoImportPhase = .running(
            message: "Extracting places from your video…",
            progress: nil
        )
    }

    func updateVideoImport(message: String, progress: Double?) {
        guard case .running = videoImportPhase else { return }
        videoImportPhase = .running(message: message, progress: progress)
    }

    func completeVideoImport(count: Int) {
        videoImportPhase = .success(count: count)
        videoImportSuccessDismissTask?.cancel()
        videoImportSuccessDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, case .success = self.videoImportPhase else { return }
                self.videoImportPhase = .idle
            }
        }
    }

    func failVideoImport(message: String) {
        videoImportSuccessDismissTask?.cancel()
        videoImportPhase = .failure(message: message)
    }

    func dismissVideoImportBanner() {
        videoImportSuccessDismissTask?.cancel()
        videoImportPhase = .idle
    }

    func importFromVideo(url videoURL: String, baseURL: String, googlePlacesAPIKey: String) async {
        beginVideoImport()
        let trimmedVideoURL = videoURL.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let client = BackendClient(baseURLString: baseURL)
            updateVideoImport(
                message: "Talking to the server — extracting places from your video…",
                progress: 0.08
            )
            let extraction = try await client.processVideo(url: trimmedVideoURL)

            if extraction.locations.isEmpty {
                failVideoImport(message: "Backend returned 0 locations.")
                return
            }

            let total = extraction.locations.count
            updateVideoImport(
                message: "Resolving \(total) place\(total == 1 ? "" : "s") on Maps…",
                progress: 0.12
            )

            let placesKey = googlePlacesAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            var resolved = 0

            let created: [LocationItem] = try await withThrowingTaskGroup(of: LocationItem?.self) { group in
                var iterator = extraction.locations.makeIterator()

                func enqueueNext() {
                    guard let next = iterator.next() else { return }
                    group.addTask {
                        await resolveVideoImportLocation(
                            next: next,
                            trimmedVideoURL: trimmedVideoURL,
                            placesKey: placesKey
                        )
                    }
                }

                for _ in 0..<min(3, extraction.locations.count) { enqueueNext() }

                var acc: [LocationItem] = []
                acc.reserveCapacity(extraction.locations.count)

                while let result = try await group.next() {
                    if let result { acc.append(result) }
                    resolved += 1
                    let fraction = 0.12 + (0.86 * Double(resolved) / Double(total))
                    updateVideoImport(
                        message: "Resolved \(resolved) of \(total)…",
                        progress: fraction
                    )
                    enqueueNext()
                }

                return acc
            }

            if created.isEmpty {
                failVideoImport(message: "Couldn’t find coordinates for any returned locations.")
                return
            }

            addToInbox(created)
            completeVideoImport(count: created.count)
        } catch {
            failVideoImport(
                message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
    }

    // MARK: - Route planning overlay

    func planItinerary(tripID: Trip.ID, baseURL: String, body: PlanItineraryRequestDTO) async {
        routePlanDismissTask?.cancel()
        routePlanPhase = .running(message: "Computing route…", progress: 0.08)

        do {
            routePlanPhase = .running(message: "Contacting server…", progress: 0.22)
            let client = BackendClient(baseURLString: baseURL)
            routePlanPhase = .running(message: "Splitting stops across days…", progress: 0.55)
            let response = try await client.planItinerary(body)
            routePlanPhase = .running(message: "Saving to your trip…", progress: 0.88)
            applyPlannedRoute(tripID: tripID, plan: response)
            routePlanPhase = .success
            routePlanDismissTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, case .success = self.routePlanPhase else { return }
                    self.routePlanPhase = .idle
                }
            }
        } catch {
            routePlanPhase = .failure(
                message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
    }

    func dismissRoutePlanOverlay() {
        routePlanDismissTask?.cancel()
        routePlanPhase = .idle
    }

    func addTrip(
        name: String,
        country: String,
        city: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) {
        let trimmedCountry = country.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCountry.isEmpty else { return }
        let trimmedCity = city?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cityValue = (trimmedCity?.isEmpty ?? true) ? nil : trimmedCity
        trips.insert(
            Trip(name: name, country: trimmedCountry, city: cityValue, startDate: startDate, endDate: endDate),
            at: 0
        )
        persistAsync()
    }

    func deleteTrips(at offsets: IndexSet) {
        trips.remove(atOffsets: offsets)
        persistAsync()
    }

    func addLocation(to tripID: Trip.ID, location: LocationItem) {
        guard let idx = trips.firstIndex(where: { $0.id == tripID }) else { return }
        if trips[idx].plannedDays != nil {
            trips[idx].locations.append(location)
            syncTripLocationsWithPlannedDays(tripIdx: idx)
        } else {
            trips[idx].locations.insert(location, at: 0)
        }
        persistAsync()
    }

    func addLocations(to tripID: Trip.ID, locations: [LocationItem]) {
        guard let idx = trips.firstIndex(where: { $0.id == tripID }) else { return }
        guard !locations.isEmpty else { return }
        if trips[idx].plannedDays != nil {
            trips[idx].locations.append(contentsOf: locations)
            syncTripLocationsWithPlannedDays(tripIdx: idx)
        } else {
            trips[idx].locations.insert(contentsOf: locations, at: 0)
        }
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

    func tripLocationDeletionImpact(tripID: Trip.ID, locationID: LocationItem.ID) -> TripLocationDeletionImpact {
        guard let trip = trips.first(where: { $0.id == tripID }),
              let plannedDays = trip.plannedDays,
              !plannedDays.isEmpty
        else { return .unplanned }

        let containingDays = plannedDays.filter { $0.orderedLocationIds.contains(locationID) }
        guard !containingDays.isEmpty else { return .unplanned }

        if containingDays.contains(where: { $0.orderedLocationIds.count == 1 }) {
            return .resetsRoute
        }
        return .adjustPlan
    }

    func deleteLocations(tripID: Trip.ID, at offsets: IndexSet) {
        guard let idx = trips.firstIndex(where: { $0.id == tripID }) else { return }
        let ids = offsets.compactMap { offset -> LocationItem.ID? in
            guard trips[idx].locations.indices.contains(offset) else { return nil }
            return trips[idx].locations[offset].id
        }
        for id in ids {
            deleteLocation(tripID: tripID, locationID: id, confirmRouteReset: true)
        }
    }

    func deleteLocation(tripID: Trip.ID, locationID: LocationItem.ID, confirmRouteReset: Bool = false) {
        guard let idx = trips.firstIndex(where: { $0.id == tripID }) else { return }

        let impact = tripLocationDeletionImpact(tripID: tripID, locationID: locationID)
        if impact == .resetsRoute, !confirmRouteReset { return }

        switch impact {
        case .unplanned:
            trips[idx].locations.removeAll { $0.id == locationID }
        case .adjustPlan:
            if var days = trips[idx].plannedDays {
                for dayIndex in days.indices {
                    if days[dayIndex].orderedLocationIds.contains(locationID) {
                        days[dayIndex].orderedLocationIds.removeAll { $0 == locationID }
                        days[dayIndex].routePolyline = nil
                    }
                }
                trips[idx].plannedDays = days
            }
            trips[idx].locations.removeAll { $0.id == locationID }
            syncTripLocationsWithPlannedDays(tripIdx: idx)
        case .resetsRoute:
            trips[idx].locations.removeAll { $0.id == locationID }
            trips[idx].plannedDays = nil
            trips[idx].plannedRoutePolyline = nil
        }
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
        country: String,
        city: String?,
        startDate: Date?,
        endDate: Date?,
        accommodation: TripAccommodation?
    ) {
        guard let idx = trips.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCountry = country.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmedCountry.isEmpty else { return }
        let trimmedCity = city?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cityValue = (trimmedCity?.isEmpty ?? true) ? nil : trimmedCity
        let oldStart = trips[idx].startDate
        let oldEnd = trips[idx].endDate
        let oldAcc = trips[idx].accommodation
        let oldCountry = trips[idx].country
        let oldCity = trips[idx].city
        trips[idx].name = trimmed
        trips[idx].country = trimmedCountry
        trips[idx].city = cityValue
        trips[idx].startDate = startDate
        trips[idx].endDate = endDate
        trips[idx].accommodation = accommodation
        if oldStart != startDate || oldEnd != endDate || oldAcc != accommodation {
            trips[idx].plannedDays = nil
            trips[idx].plannedRoutePolyline = nil
        }
        if oldCountry != trimmedCountry || oldCity != cityValue {
            trips[idx].plannedDays = nil
            trips[idx].plannedRoutePolyline = nil
        }
        persistAsync()
    }

    /// Reorders `trip.locations` to match backend TTDP day plans (flattened by `dayIndex`), then any remaining stops.
    func applyPlannedRoute(tripID: Trip.ID, plan: PlanItineraryResponseDTO) {
        guard let tripIdx = trips.firstIndex(where: { $0.id == tripID }) else { return }
        let _ = trips[tripIdx]
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
            if old.latitude != location.latitude || old.longitude != location.longitude,
               var days = trips[tripIdx].plannedDays,
               days.contains(where: { $0.orderedLocationIds.contains(location.id) })
            {
                for dayIndex in days.indices where days[dayIndex].orderedLocationIds.contains(location.id) {
                    days[dayIndex].routePolyline = nil
                }
                trips[tripIdx].plannedDays = days
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
        guard let url = try? dataURL() else { return }

        let data: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            data = try encoder.encode(snapshot)
        } catch {
            return
        }

        Task.detached(priority: .utility) {
            do {
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

