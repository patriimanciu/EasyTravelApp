import SwiftUI

/// Sample data and wrappers for Xcode Previews — no disk I/O, instant render.
enum PreviewData {
    static let store = TravelStore(
        previewTrips: SampleTrips.make(),
        previewInbox: SampleTrips.previewInbox
    )

    static let emptyStore = TravelStore(previewTrips: [], previewInbox: [])

    static var parisTrip: Trip { store.trips[0] }
    static var parisTripID: Trip.ID { parisTrip.id }
    static var parisLocation: LocationItem { parisTrip.locations[0] }
    static var parisLocationID: LocationItem.ID { parisLocation.id }

    static var inboxLocationID: LocationItem.ID {
        store.inbox.first?.id ?? parisLocationID
    }
}

enum PreviewShell {
    static func withStore<V: View>(
        _ store: TravelStore = PreviewData.store,
        @ViewBuilder content: () -> V
    ) -> some View {
        content()
            .environmentObject(store)
            .appScreenBackground()
    }

    static func navigation<V: View>(@ViewBuilder content: () -> V) -> some View {
        NavigationStack {
            content()
        }
    }
}
