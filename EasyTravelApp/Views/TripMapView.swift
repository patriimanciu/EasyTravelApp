import MapKit
import SwiftUI

struct TripMapView: View {
    let trip: Trip

    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $position) {
            ForEach(trip.locations) { loc in
                Annotation(loc.name, coordinate: CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude)) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(tint(for: loc.category), .white)
                        .shadow(radius: 2)
                }
            }
        }
        .mapControls {
            MapCompass()
            MapPitchToggle()
            MapUserLocationButton()
            MapScaleView()
        }
        .onAppear {
            position = cameraPositionFittingAllLocations()
        }
        .onChange(of: trip.locations) { _, _ in
            position = cameraPositionFittingAllLocations()
        }
    }

    private func tint(for category: LocationItem.Category) -> Color {
        switch category {
        case .landmark: .blue
        case .museum: .purple
        case .park: .green
        case .neighborhood: .mint
        case .city: .cyan
        case .restaurant: .red
        case .cafe: .orange
        case .shopping: .pink
        case .nightlife: .indigo
        case .hotel: .teal
        case .other: .gray
        }
    }

    private func cameraPositionFittingAllLocations() -> MapCameraPosition {
        guard !trip.locations.isEmpty else { return .automatic }

        let lats = trip.locations.map(\.latitude)
        let lons = trip.locations.map(\.longitude)
        guard let minLat = lats.min(),
              let maxLat = lats.max(),
              let minLon = lons.min(),
              let maxLon = lons.max()
        else { return .automatic }

        // Small padding so pins aren't on the edge.
        let latSpan = max(0.01, (maxLat - minLat) * 1.35)
        let lonSpan = max(0.01, (maxLon - minLon) * 1.35)

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2.0,
            longitude: (minLon + maxLon) / 2.0
        )

        let region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: lonSpan)
        )

        return .region(region)
    }
}

