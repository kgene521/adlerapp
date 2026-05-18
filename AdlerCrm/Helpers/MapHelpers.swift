// /AdlerCRM/Helpers/MapHelpers.swift  17/04/2026 02:08:00 EDT
import MapKit

// Isolates MKPlacemark deprecation (iOS 26) to a single location.
// Update this helper once Apple provides the replacement initializer.
enum MapHelpers {
    @available(iOS, deprecated: 26.0, message: "Replace with new MKMapItem initializer when available")
    static func makeMapItem(coordinate: CLLocationCoordinate2D, name: String? = nil) -> MKMapItem {
        let placemark = MKPlacemark(coordinate: coordinate)
        let item = MKMapItem(placemark: placemark)
        item.name = name
        return item
    }

    /// Open directions in external Apple Maps app (fallback)
    static func openDirectionsExternal(to coordinate: CLLocationCoordinate2D, name: String?) {
        let item = makeMapItem(coordinate: coordinate, name: name)
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }

    /// Legacy name — kept for any remaining call sites, now opens external Maps
    static func openDirections(to coordinate: CLLocationCoordinate2D, name: String?) {
        openDirectionsExternal(to: coordinate, name: name)
    }
}
