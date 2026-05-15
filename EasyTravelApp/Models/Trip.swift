import Foundation

/// Where the traveler stays; each planned day can start and end here (hub routing).
struct TripAccommodation: Codable, Hashable {
    var name: String
    var latitude: Double
    var longitude: Double
}

/// One day from the last applied backend plan (visit order + optional road geometry).
struct TripPlannedDay: Codable, Hashable, Identifiable {
    var dayIndex: Int
    var orderedLocationIds: [UUID]
    var routePolyline: [[Double]]?

    var id: Int { dayIndex }
}

struct Trip: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var startDate: Date?
    var endDate: Date?
    /// Hotel / rental — when set, planning uses it as the hub each day (leave and return).
    var accommodation: TripAccommodation?
    var createdAt: Date
    var locations: [LocationItem]
    /// Per-day OSRM polylines and stop order after “Apply” on a multi-day plan. When set, the map can show one day at a time.
    var plannedDays: [TripPlannedDay]?
    /// Legacy merged polyline (older saves). Ignored by the map when `plannedDays` is non-empty.
    var plannedRoutePolyline: [[Double]]?

    init(
        id: UUID = UUID(),
        name: String,
        startDate: Date? = nil,
        endDate: Date? = nil,
        accommodation: TripAccommodation? = nil,
        createdAt: Date = Date(),
        locations: [LocationItem] = [],
        plannedDays: [TripPlannedDay]? = nil,
        plannedRoutePolyline: [[Double]]? = nil
    ) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.accommodation = accommodation
        self.createdAt = createdAt
        self.locations = locations
        self.plannedDays = plannedDays
        self.plannedRoutePolyline = plannedRoutePolyline
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        startDate = try c.decodeIfPresent(Date.self, forKey: .startDate)
        endDate = try c.decodeIfPresent(Date.self, forKey: .endDate)
        accommodation = try c.decodeIfPresent(TripAccommodation.self, forKey: .accommodation)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        locations = try c.decode([LocationItem].self, forKey: .locations)
        plannedDays = try c.decodeIfPresent([TripPlannedDay].self, forKey: .plannedDays)
        plannedRoutePolyline = try c.decodeIfPresent([[Double]].self, forKey: .plannedRoutePolyline)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(startDate, forKey: .startDate)
        try c.encodeIfPresent(endDate, forKey: .endDate)
        try c.encodeIfPresent(accommodation, forKey: .accommodation)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(locations, forKey: .locations)
        try c.encodeIfPresent(plannedDays, forKey: .plannedDays)
        try c.encodeIfPresent(plannedRoutePolyline, forKey: .plannedRoutePolyline)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, startDate, endDate, accommodation, createdAt, locations, plannedDays, plannedRoutePolyline
    }
}
