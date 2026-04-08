// /AdlerCRM/Views/CollectionMapView.swift  08/04/2026 00:51:00 EDT
import SwiftUI
import MapKit
import Combine

// MARK: - Region Color Palette (matches web app)

private let regionColors: [Color] = [
    Color(hex: "e6194b"), Color(hex: "3cb44b"), Color(hex: "4363d8"), Color(hex: "f58231"),
    Color(hex: "911eb4"), Color(hex: "42d4f4"), Color(hex: "f032e6"), Color(hex: "bfef45"),
    Color(hex: "469990"), Color(hex: "dcbeff"), Color(hex: "9A6324"), Color(hex: "800000"),
    Color(hex: "aaffc3"), Color(hex: "808000"), Color(hex: "000075"), Color(hex: "ffd8b1"),
    Color(hex: "a9a9a9"), Color(hex: "ffe119")
]
private let unassignedColor = Color(hex: "999999")

// MARK: - Map Location Item

struct MapLocation: Identifiable {
    let id: Int
    let coordinate: CLLocationCoordinate2D
    let businessName: String
    let businessId: Int
    let address: String
    let estimatedGallons: Int
    let pickupFreq: String
    let regionName: String?
    let color: Color
}

// MARK: - Region Legend Item

struct RegionLegendItem: Identifiable {
    let id = UUID()
    let name: String
    let color: Color
}

// MARK: - Collection Map View

struct CollectionMapView: View {
    @EnvironmentObject var auth: AuthManager
    @State private var locations: [Location] = []
    @State private var businesses: [Business] = []
    @State private var loading = true
    @State private var errorMsg = ""
    @State private var selectedLocation: MapLocation?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var copiedFeedback = false

    // Derived data
    private var bizMap: [Int: Business] {
        Dictionary(uniqueKeysWithValues: businesses.map { ($0.id, $0) })
    }

    private var regionColorMap: [Int: Color] {
        var terrIds: [Int] = []
        var seen = Set<Int>()
        for b in businesses {
            if let tid = b.region_id, !seen.contains(tid) {
                terrIds.append(tid)
                seen.insert(tid)
            }
        }
        var map: [Int: Color] = [:]
        for (i, tid) in terrIds.enumerated() {
            map[tid] = regionColors[i % regionColors.count]
        }
        return map
    }

    private var mapLocations: [MapLocation] {
        locations.compactMap { loc in
            guard let lat = loc.latitude, let lng = loc.longitude else { return nil }
            let biz = bizMap[loc.business_id]
            let color: Color
            if let tid = biz?.region_id, let tc = regionColorMap[tid] {
                color = tc
            } else {
                color = unassignedColor
            }
            let addr = [loc.address, loc.city, loc.state, loc.zip]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")

            return MapLocation(
                id: loc.id,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                businessName: loc.business_name ?? biz?.name ?? "Unknown",
                businessId: loc.business_id,
                address: addr.isEmpty ? "No address" : addr,
                estimatedGallons: loc.estimated_gallons ?? 0,
                pickupFreq: loc.pickup_freq ?? "weekly",
                regionName: biz?.region_name,
                color: color
            )
        }
    }

    private var legendItems: [RegionLegendItem] {
        var items: [RegionLegendItem] = []
        var seen = Set<Int>()
        for b in businesses {
            if let tid = b.region_id, !seen.contains(tid),
               let color = regionColorMap[tid] {
                items.append(RegionLegendItem(name: b.region_name ?? "Region \(tid)", color: color))
                seen.insert(tid)
            }
        }
        return items
    }

    private var missingCoordCount: Int {
        locations.filter { $0.latitude == nil || $0.longitude == nil }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            if loading {
                Spacer()
                ProgressView("Loading map data…")
                    .font(.custom("DMSans-Regular", size: 14))
                Spacer()
            } else if !errorMsg.isEmpty {
                errorView
            } else if mapLocations.isEmpty {
                emptyState
            } else {
                mapContent
            }
        }
        .navigationTitle("Collection Map")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: loadData) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(Color(hex: "7a7f94"))
                }
            }
        }
        .task { await loadDataAsync() }
        .sheet(item: $selectedLocation) { loc in
            LocationDetailSheet(location: loc, copiedFeedback: $copiedFeedback)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Map Content

    private var mapContent: some View {
        VStack(spacing: 0) {
            // Stats bar
            HStack {
                Text("\(mapLocations.count) of \(locations.count) locations mapped")
                    .font(.custom("DMSans-Regular", size: 12))
                    .foregroundColor(Color(hex: "7a7f94"))
                Spacer()
                if missingCoordCount > 0 {
                    Label("\(missingCoordCount) missing coords", systemImage: "exclamationmark.triangle.fill")
                        .font(.custom("DMSans-Medium", size: 11))
                        .foregroundColor(Color(hex: "c8893a"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(hex: "f5f4f0"))

            // Map
            Map(position: $cameraPosition) {
                ForEach(mapLocations) { loc in
                    Annotation(loc.businessName, coordinate: loc.coordinate) {
                        PinView(color: loc.color)
                            .onTapGesture {
                                selectedLocation = loc
                            }
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat))
            .mapControls {
                MapCompass()
                MapScaleView()
                MapUserLocationButton()
            }

            // Region legend
            if legendItems.count > 1 {
                legendBar
            }
        }
    }

    // MARK: - Pin View

    struct PinView: View {
        let color: Color

        var body: some View {
            ZStack {
                // Pin shape
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(color)
                    .background(
                        Circle()
                            .fill(.white)
                            .frame(width: 18, height: 18)
                            .offset(y: -1)
                    )
            }
        }
    }

    // MARK: - Legend

    private var legendBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(legendItems) { item in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(item.color)
                            .frame(width: 10, height: 10)
                            .overlay(
                                Circle()
                                    .stroke(Color.black.opacity(0.15), lineWidth: 1)
                            )
                        Text(item.name)
                            .font(.custom("DMSans-Medium", size: 12))
                            .foregroundColor(Color(hex: "3a3d4a"))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color.white)
        .overlay(Rectangle().fill(Color(hex: "e2dfd6")).frame(height: 1), alignment: .top)
    }

    // MARK: - Empty & Error

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "map")
                .font(.system(size: 40))
                .foregroundColor(Color(hex: "7a7f94").opacity(0.4))
            Text("No locations with coordinates")
                .font(.custom("Syne-Bold", size: 17))
                .foregroundColor(Color(hex: "3a3d4a"))
            Text("Add latitude and longitude to your locations to see them on the map.")
                .font(.custom("DMSans-Regular", size: 14))
                .foregroundColor(Color(hex: "7a7f94"))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    private var errorView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundColor(Color(hex: "c1121f"))
            Text(errorMsg)
                .font(.custom("DMSans-Regular", size: 14))
                .foregroundColor(Color(hex: "3a3d4a"))
                .multilineTextAlignment(.center)
            Button("Retry") { loadData() }
                .font(.custom("DMSans-SemiBold", size: 14))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(Color(hex: "0f1117"))
                .cornerRadius(8)
            Spacer()
        }
        .padding()
    }

    // MARK: - Data

    private func loadData() {
        Task { await loadDataAsync() }
    }

    private func loadDataAsync() async {
        loading = true
        errorMsg = ""
        do {
            async let locsResult = APIClient.shared.getAllLocations()
            async let bizResult = APIClient.shared.getBusinesses()
            let (locs, biz) = try await (locsResult, bizResult)
            locations = locs
            businesses = biz
        } catch {
            errorMsg = error.localizedDescription
        }
        loading = false
    }
}

// MARK: - Location Detail Sheet

struct LocationDetailSheet: View {
    let location: MapLocation
    @Binding var copiedFeedback: Bool
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Business name & address
                    VStack(alignment: .leading, spacing: 6) {
                        Text(location.businessName)
                            .font(.custom("Syne-Bold", size: 22))
                            .foregroundColor(Color(hex: "0f1117"))

                        Text(location.address)
                            .font(.custom("DMSans-Regular", size: 14))
                            .foregroundColor(Color(hex: "7a7f94"))
                    }

                    Divider()

                    // Info grid
                    HStack(spacing: 24) {
                        infoItem(icon: "drop.fill", label: "Capacity", value: "\(location.estimatedGallons) gal/wk", color: Color(hex: "2d6a4f"))
                        infoItem(icon: "clock.fill", label: "Frequency", value: location.pickupFreq.capitalized, color: Color(hex: "1d4e89"))
                        if let terr = location.regionName {
                            infoItem(icon: "map.circle.fill", label: "Region", value: terr, color: Color(hex: "c8893a"))
                        }
                    }

                    Divider()

                    // Coordinates
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("COORDINATES")
                                .font(.custom("DMSans-SemiBold", size: 9))
                                .foregroundColor(Color(hex: "7a7f94"))
                                .tracking(0.5)
                            Text(coordString)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(Color(hex: "0f1117"))
                                .textSelection(.enabled)
                        }

                        Spacer()

                        Button(action: copyCoordinates) {
                            HStack(spacing: 4) {
                                Image(systemName: copiedFeedback ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 11))
                                Text(copiedFeedback ? "Copied" : "Copy")
                                    .font(.custom("DMSans-SemiBold", size: 11))
                            }
                            .foregroundColor(copiedFeedback ? Color(hex: "2d6a4f") : Color(hex: "3a3d4a"))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(hex: "f5f4f0"))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(hex: "e2dfd6"), lineWidth: 1)
                            )
                        }
                    }

                    // Navigate button
                    Button(action: openInMaps) {
                        HStack {
                            Image(systemName: "map.fill")
                                .font(.system(size: 14))
                            Text("Navigate")
                                .font(.custom("DMSans-SemiBold", size: 15))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(hex: "0f1117"))
                        .cornerRadius(12)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Location Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.custom("DMSans-Medium", size: 14))
                        .foregroundColor(Color(hex: "c8893a"))
                }
            }
        }
    }

    private var coordString: String {
        String(format: "%.6f, %.6f", location.coordinate.latitude, location.coordinate.longitude)
    }

    private func copyCoordinates() {
        UIPasteboard.general.string = coordString
        copiedFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copiedFeedback = false
        }
    }

    private func openInMaps() {
        MapHelpers.openDirections(to: location.coordinate, name: location.businessName)
    }

    private func infoItem(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)
            Text(label.uppercased())
                .font(.custom("DMSans-SemiBold", size: 8))
                .foregroundColor(Color(hex: "7a7f94"))
                .tracking(0.4)
            Text(value)
                .font(.custom("DMSans-Medium", size: 12))
                .foregroundColor(Color(hex: "0f1117"))
                .lineLimit(1)
        }
    }
}

#Preview {
    NavigationStack {
        CollectionMapView()
    }
    .environmentObject(AuthManager())
}
