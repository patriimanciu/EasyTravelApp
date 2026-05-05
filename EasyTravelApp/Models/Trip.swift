import Foundation

struct Trip: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var startDate: Date?
    var endDate: Date?
    var createdAt: Date
    var locations: [LocationItem]

    init(
        id: UUID = UUID(),
        name: String,
        startDate: Date? = nil,
        endDate: Date? = nil,
        createdAt: Date = Date(),
        locations: [LocationItem] = []
    ) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.createdAt = createdAt
        self.locations = locations
    }
}

