import Foundation

struct VideoRequestDTO: Codable {
    var url: String
}

struct BackendErrorDTO: Codable {
    var detail: String
}

struct LocationDTO: Codable, Hashable {
    var name: String
    var category: String
    var city: String
    /// Present only when backend extraction found an explicit address in video modalities.
    var address: String?
    var phoneNumber: String?
    var url: String?
    var openingHours: String?
    var sourceModalities: [String]?
    var confidence: Double?

    enum CodingKeys: String, CodingKey {
        case name, category, city, address, url, confidence
        case phoneNumber = "phone_number"
        case openingHours = "opening_hours"
        case sourceModalities = "source_modalities"
    }
}

struct LocationExtractionDTO: Codable, Hashable {
    var locations: [LocationDTO]
}

// MARK: - TTDP plan-itinerary (backend Chapter 2.3–2.4)

struct RouteStopDTO: Encodable, Hashable {
    var id: String
    var latitude: Double
    var longitude: Double
    /// 1 = low / if time … 5 = must see (server derives mandatory + drop order).
    var visitPriority: Int
    var weight: Double
    var mandatory: Bool
    var serviceTimeSeconds: Double
    /// App category raw value (e.g. `restaurant`, `cafe`); backend spreads meal-like stops across days after k-means.
    var category: String?
}

struct PlanItineraryRequestDTO: Encodable, Hashable {
    var startLatitude: Double
    var startLongitude: Double
    var stops: [RouteStopDTO]
    var numberOfDays: Int
    /// ISO-8601; with `tripEnd`, server uses inclusive calendar span for k-means day count (overrides manual day count).
    var tripStart: String?
    var tripEnd: String?
    var dailyBudgetSeconds: Double?
    var returnToStart: Bool
    var travelModel: String
    var averageSpeedKmh: Double
    var clusteringSeed: Int
    /// `k_means` or `dbscan` — spatial partition into day clusters (thesis Ch. 2.3).
    var clusteringMethod: String
    var dbscanEpsM: Double
    var dbscanMinSamples: Int
    /// Spread must-see POIs across days after spatial clustering (does not change k-means/DBSCAN).
    var priorityRebalance: Bool
    var accommodationLatitude: Double?
    var accommodationLongitude: Double?
    /// OSRM profile: `foot` (walking), `driving`, or `bike` (server normalizes; invalid values become `foot`).
    var osrmProfile: String
}

struct DayPlanDTO: Decodable, Hashable {
    var dayIndex: Int
    var orderedStopIds: [String]
    var totalTravelSeconds: Double
    var totalServiceSeconds: Double
    var totalSeconds: Double
    var withinBudget: Bool
    var droppedStopIds: [String]
    /// `[[lat, lon], ...]` from OSRM `/route/v1` (foot / walking by default) when available.
    var routePolyline: [[Double]]?
}

struct PlanItineraryResponseDTO: Decodable, Hashable {
    var days: [DayPlanDTO]
    /// Backend returns string metadata (clustering, routing, travel_model).
    var metadata: [String: String]?
}

