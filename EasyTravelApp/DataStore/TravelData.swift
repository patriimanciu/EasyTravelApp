import Foundation

struct TravelData: Codable, Hashable {
    var trips: [Trip]
    var inbox: [LocationItem]

    init(trips: [Trip] = [], inbox: [LocationItem] = []) {
        self.trips = trips
        self.inbox = inbox
    }
}

