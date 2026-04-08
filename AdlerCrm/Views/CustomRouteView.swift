// /AdlerCRM/Views/CustomRouteView.swift  08/04/2026 00:51:00 EDT  02/04/2026 23:44:23
import SwiftUI
import MapKit
import CoreLocation

// MARK: - Custom Stop Model

struct CustomStop: Identifiable {
    let id = UUID()
    var name: String
    var address: String
    var coordinate: CLLocationCoordinate2D
    var source: StopSource

    enum StopSource {
        case business(businessId: Int, locationId: Int)
        case manual
    }
}

// MARK: - Custom Route View

struct CustomRouteView: View {
    @EnvironmentObject var auth: AuthManager
    @State private var stops: [CustomStop] = []
    @State private var originalStops: [CustomStop] = []
    @State private var businesses: [Business] = []
    @State private var locations: [Location] = []
    @State private var loading = true
    @State private var errorMsg = ""

    // Start location
    @State private var selectedStartId: String = "current"
    @State private var startCoord: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 37.2710, longitude: -79.9414)
    @State private var showStartPicker = false
    @StateObject private var locationManager = LocationHelper()

    // Add stop
    @State private var showAddStop = false
    @State private var showSaveRoute = false
    @State private var showLoadRoutes = false

    // Current saved route tracking
    @State private var currentRouteId: Int?
    @State private var currentRouteName: String = ""
    @State private var isDirty = false

    // Map
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedStop: CustomStop?
    @State private var showStartDetail = false
    @State private var showCustomMap = false

    var body: some View {
        VStack(spacing: 0) {
            if loading {
                Spacer()
                ProgressView("Loading businesses…")
                    .font(.custom("DMSans-Regular", size: 14))
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        // Start location bar
                        startLocationBar

                        // Map (shown when stops exist)
                        if !stops.isEmpty {
                            routeMap
                        }

                        // Add stop buttons
                        addStopBar

                        // Stops list
                        if stops.isEmpty {
                            emptyState
                        } else {
                            stopsSection
                        }
                    }
                }
            }
        }
        .background(Color(hex: "f5f4f0"))
        .navigationTitle(navTitle)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    Button(action: { showLoadRoutes = true }) {
                        Image(systemName: "folder")
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "7a7f94"))
                    }
                    if !stops.isEmpty {
                        Button(action: { showSaveRoute = true }) {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 14))
                                    .foregroundColor(Color(hex: "2d6a4f"))
                                if isDirty {
                                    Circle()
                                        .fill(Color(hex: "c8893a"))
                                        .frame(width: 8, height: 8)
                                        .offset(x: 4, y: -4)
                                }
                            }
                        }
                    }
                    if stops.count >= 2 {
                        Button(action: optimizeRoute) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.swap")
                                    .font(.system(size: 12))
                                Text("Optimize")
                                    .font(.custom("DMSans-SemiBold", size: 12))
                            }
                            .foregroundColor(Color(hex: "2d6a4f"))
                        }
                    }
                    if !stops.isEmpty {
                        Button(action: { stops.removeAll(); originalStops.removeAll(); cameraPosition = .automatic; currentRouteId = nil; currentRouteName = ""; isDirty = false }) {
                            Text("Clear")
                                .font(.custom("DMSans-Medium", size: 12))
                                .foregroundColor(Color(hex: "c1121f"))
                        }
                    }
                }
            }
        }
        .task { await loadData() }
        .sheet(isPresented: $showStartPicker) {
            StartLocationPickerSheet(
                selectedId: $selectedStartId,
                currentCoord: locationManager.lastLocation?.coordinate,
                onSelect: { applyStartLocation($0) }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAddStop) {
            AddStopSheet(
                businesses: businesses,
                locations: locations,
                existingStopIds: existingLocationIds,
                onAdd: { stop in
                    stops.append(stop)
                    cameraPosition = .automatic
                    isDirty = true
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedStop) { stop in
            CustomStopDetailSheet(stop: stop, startCoord: startCoord)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showStartDetail) {
            StartLocationDetailSheet(name: currentStartName, coordinate: startCoord)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCustomMap) {
            CustomRouteMapSheet(
                stops: stops,
                startCoord: startCoord,
                startName: currentStartName,
                onStopTap: { stop in
                    showCustomMap = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        selectedStop = stop
                    }
                }
            )
        }
        .sheet(isPresented: $showSaveRoute) {
            SaveRouteSheet(
                stops: stops,
                startName: currentStartName,
                startCoord: startCoord,
                existingRouteId: currentRouteId,
                existingRouteName: currentRouteName,
                onSaved: { id, name in
                    currentRouteId = id
                    currentRouteName = name
                    isDirty = false
                    originalStops = stops
                }
            )
        }
        .sheet(isPresented: $showLoadRoutes) {
            LoadRoutesSheet(
                isAdmin: auth.currentUser?.role == "Administrator",
                onLoad: { savedRoute in
                    loadSavedRoute(savedRoute)
                }
            )
        }
    }

    private var existingLocationIds: Set<Int> {
        Set(stops.compactMap { stop in
            if case .business(_, let locId) = stop.source { return locId }
            return nil
        })
    }

    // MARK: - Start Location Bar

    private var startLocationBar: some View {
        Button(action: { showStartPicker = true }) {
            HStack(spacing: 10) {
                Image(systemName: selectedStartId == "current" ? "location.fill" : "mappin.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: "2d6a4f"))
                VStack(alignment: .leading, spacing: 1) {
                    Text("STARTING FROM")
                        .font(.custom("DMSans-SemiBold", size: 8))
                        .foregroundColor(Color(hex: "7a7f94"))
                        .tracking(0.4)
                    Text(currentStartName)
                        .font(.custom("DMSans-SemiBold", size: 13))
                        .foregroundColor(Color(hex: "0f1117"))
                }
                Spacer()
                Text("Change")
                    .font(.custom("DMSans-Medium", size: 12))
                    .foregroundColor(Color(hex: "c8893a"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .background(Color.white)
        .overlay(Rectangle().fill(Color(hex: "e2dfd6")).frame(height: 1), alignment: .bottom)
    }

    // MARK: - Add Stop Bar

    private var addStopBar: some View {
        HStack(spacing: 12) {
            Button(action: { showAddStop = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 13))
                    Text("Add Stop")
                        .font(.custom("DMSans-SemiBold", size: 13))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(hex: "c8893a"))
                .cornerRadius(8)
            }

            Spacer()
        }
        .padding(16)
    }

    // MARK: - Route Stats Bar

    private var routeMap: some View {
        VStack(spacing: 0) {
            HStack {
                Label("\(stops.count) stops", systemImage: "mappin.circle.fill")
                    .font(.custom("DMSans-SemiBold", size: 12))
                    .foregroundColor(Color(hex: "2d6a4f"))
                Spacer()
                let totalMiles = totalRouteMiles()
                Label(String(format: "%.1f mi total", totalMiles), systemImage: "road.lanes")
                    .font(.custom("DMSans-SemiBold", size: 12))
                    .foregroundColor(Color(hex: "7a7f94"))
                Text("·").foregroundColor(Color(hex: "e2dfd6"))
                Button(action: { showCustomMap = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "map.fill")
                            .font(.system(size: 11))
                        Text("Map")
                            .font(.custom("DMSans-SemiBold", size: 11))
                    }
                    .foregroundColor(Color(hex: "2d6a4f"))
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Color(hex: "f5f4f0"))
        }
    }

    // MARK: - Stops Section

    private var stopsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("STOPS")
                    .font(.custom("DMSans-SemiBold", size: 9))
                    .foregroundColor(Color(hex: "7a7f94"))
                    .tracking(0.5)

                if isDirty {
                    Button(action: resetRoute) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 8, weight: .bold))
                            Text("Reset")
                                .font(.custom("DMSans-SemiBold", size: 9))
                        }
                        .foregroundColor(Color(hex: "c1121f"))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Text("Hold & drag to reorder")
                    .font(.custom("DMSans-Regular", size: 10))
                    .foregroundColor(Color(hex: "e2dfd6"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            List {
                ForEach(Array(stops.enumerated()), id: \.element.id) { idx, stop in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(Color(hex: "c8893a")).frame(width: 28, height: 28)
                            Text("\(idx + 1)").font(.custom("Syne-Bold", size: 12)).foregroundColor(.white)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(stop.name)
                                .font(.custom("DMSans-SemiBold", size: 14))
                                .foregroundColor(Color(hex: "0f1117"))
                                .lineLimit(1)
                            Text(stop.address)
                                .font(.custom("DMSans-Regular", size: 12))
                                .foregroundColor(Color(hex: "7a7f94"))
                                .lineLimit(1)
                        }

                        Spacer()

                        let dist = distanceFromPrevious(index: idx)
                        if dist > 0 {
                            Text(String(format: "%.1f mi", dist))
                                .font(.custom("DMSans-Regular", size: 11))
                                .foregroundColor(Color(hex: "7a7f94"))
                        }

                        Button(action: { removeStop(at: idx) }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(Color(hex: "c1121f").opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
                .onMove { from, to in
                    stops.move(fromOffsets: from, toOffset: to)
                    cameraPosition = .automatic
                    isDirty = true
                }

                // Return to start row
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Color(hex: "0f1117")).frame(width: 28, height: 28)
                        Image(systemName: "house.fill").font(.system(size: 10)).foregroundColor(.white)
                    }
                    Text("Return to start")
                        .font(.custom("DMSans-Regular", size: 13))
                        .foregroundColor(Color(hex: "7a7f94"))
                        .italic()
                    Spacer()
                    if let last = stops.last {
                        let dist = RouteEngine.haversine(from: last.coordinate, to: startCoord) / 1609.344
                        Text(String(format: "%.1f mi", dist))
                            .font(.custom("DMSans-Regular", size: 11))
                            .foregroundColor(Color(hex: "7a7f94"))
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color(hex: "f9f8f6"))
                .moveDisabled(true)
            }
            .listStyle(.plain)
            .environment(\.editMode, .constant(.active))
            .frame(height: CGFloat(stops.count + 1) * 56)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.system(size: 44))
                .foregroundColor(Color(hex: "e2dfd6"))
            Text("Build Your Route")
                .font(.custom("Syne-Bold", size: 20))
                .foregroundColor(Color(hex: "0f1117"))
            Text("Add businesses from your list or enter any address to create a custom collection route.")
                .font(.custom("DMSans-Regular", size: 14))
                .foregroundColor(Color(hex: "7a7f94"))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding(.vertical, 40)
    }

    // MARK: - Logic

    private func loadData() async {
        loading = true
        try? await Task.sleep(nanoseconds: 300_000_000)
        resolveStartCoord()
        do {
            businesses = try await APIClient.shared.getBusinesses()
            locations = try await APIClient.shared.getAllLocationsIncludingInactive()
        } catch {
            errorMsg = error.localizedDescription
        }
        loading = false
    }

    private func resolveStartCoord() {
        if selectedStartId == "current" {
            startCoord = locationManager.lastLocation?.coordinate ?? CLLocationCoordinate2D(latitude: 37.2710, longitude: -79.9414)
        } else if let preset = startLocationPresets.first(where: { $0.id == selectedStartId }) {
            startCoord = preset.coordinate
        }
    }

    private func applyStartLocation(_ loc: StartLocation) {
        selectedStartId = loc.id
        resolveStartCoord()
        cameraPosition = .automatic
    }

    private func removeStop(at index: Int) {
        stops.remove(at: index)
        cameraPosition = .automatic
        isDirty = true
    }

    private func resetRoute() {
        stops = originalStops
        isDirty = false
        cameraPosition = .automatic
    }

    private func optimizeRoute() {
        guard stops.count >= 2 else { return }
        var remaining = stops
        var ordered: [CustomStop] = []
        var currentPos = startCoord

        while !remaining.isEmpty {
            var nearestIdx = 0
            var nearestDist = Double.infinity
            for (i, s) in remaining.enumerated() {
                let dist = RouteEngine.haversine(from: currentPos, to: s.coordinate)
                if dist < nearestDist {
                    nearestDist = dist
                    nearestIdx = i
                }
            }
            let next = remaining.remove(at: nearestIdx)
            ordered.append(next)
            currentPos = next.coordinate
        }

        stops = ordered
        cameraPosition = .automatic
        isDirty = true
    }

    private func distanceFromPrevious(index: Int) -> Double {
        let from = index == 0 ? startCoord : stops[index - 1].coordinate
        return RouteEngine.haversine(from: from, to: stops[index].coordinate) / 1609.344
    }

    private var navTitle: String {
        if currentRouteName.isEmpty {
            return "Custom Route"
        }
        return isDirty ? "\(currentRouteName) •" : currentRouteName
    }

    private var currentStartName: String {
        if selectedStartId == "current" {
            return locationManager.lastLocation != nil ? "Current Location" : "Roanoke, VA (default)"
        }
        return startLocationPresets.first { $0.id == selectedStartId }?.name ?? "Unknown"
    }

    private struct SegmentInfo {
        let midpoint: CLLocationCoordinate2D
        let label: String
    }

    private func segmentDistances() -> [SegmentInfo] {
        var segments: [SegmentInfo] = []
        let allCoords = [startCoord] + stops.map { $0.coordinate } + [startCoord]
        for i in 0..<(allCoords.count - 1) {
            let a = allCoords[i]
            let b = allCoords[i + 1]
            let distMiles = RouteEngine.haversine(from: a, to: b) / 1609.344
            if distMiles > 0.1 {
                let mid = CLLocationCoordinate2D(latitude: (a.latitude + b.latitude) / 2, longitude: (a.longitude + b.longitude) / 2)
                let label = distMiles < 10 ? String(format: "%.1f mi", distMiles) : String(format: "%.0f mi", distMiles)
                segments.append(SegmentInfo(midpoint: mid, label: label))
            }
        }
        return segments
    }

    private func totalRouteMiles() -> Double {
        let allCoords = [startCoord] + stops.map { $0.coordinate } + [startCoord]
        var total = 0.0
        for i in 0..<(allCoords.count - 1) {
            total += RouteEngine.haversine(from: allCoords[i], to: allCoords[i + 1])
        }
        return total / 1609.344
    }

    private func loadSavedRoute(_ saved: SavedRoute) {
        // Track loaded route
        currentRouteId = saved.id
        currentRouteName = saved.name
        isDirty = false

        // Restore start location
        if let lat = saved.start_lat, let lng = saved.start_lng {
            startCoord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            // Try to match a preset
            if let preset = startLocationPresets.first(where: {
                $0.id != "current" && abs($0.latitude - lat) < 0.001 && abs($0.longitude - lng) < 0.001
            }) {
                selectedStartId = preset.id
            } else {
                selectedStartId = "current"
            }
        }

        // Restore stops
        stops = (saved.stops ?? []).map { s in
            CustomStop(
                name: s.name,
                address: s.address,
                coordinate: CLLocationCoordinate2D(latitude: s.latitude, longitude: s.longitude),
                source: s.source_type == "business" && s.business_id != nil && s.location_id != nil
                    ? .business(businessId: s.business_id!, locationId: s.location_id!)
                    : .manual
            )
        }
        originalStops = stops
        cameraPosition = .automatic
    }
}

// MARK: - Add Business Stop Sheet

struct AddStopSheet: View {
    let businesses: [Business]
    let locations: [Location]
    let existingStopIds: Set<Int>
    let onAdd: (CustomStop) -> Void

    @Environment(\.dismiss) var dismiss
    @State private var mode = 0  // 0 = Businesses, 1 = Manual
    @State private var searchText = ""
    @State private var filterRegion = "all"
    @State private var showInactive = false

    // Manual entry fields
    @State private var manualName = ""
    @State private var manualAddress = ""
    @State private var manualCity = ""
    @State private var manualState = ""
    @State private var manualLat = ""
    @State private var manualLng = ""
    @State private var manualError = ""
    @State private var geocoding = false

    private var filteredLocations: [Location] {
        locations.filter { loc in
            guard loc.latitude != nil, loc.longitude != nil else { return false }
            if existingStopIds.contains(loc.id) { return false }
            if !showInactive && loc.is_deleted == true { return false }
            if !searchText.isEmpty {
                let bizName = loc.business_name ?? ""
                let addr = [loc.address, loc.city, loc.state].compactMap { $0 }.joined(separator: " ")
                let combined = "\(bizName) \(addr)"
                if !combined.localizedCaseInsensitiveContains(searchText) { return false }
            }
            if filterRegion != "all" {
                let biz = businesses.first { $0.id == loc.business_id }
                if let regionId = Int(filterRegion) {
                    if biz?.region_id != regionId { return false }
                }
            }
            return true
        }
    }

    private var regionNames: [(id: String, name: String)] {
        var seen = Set<Int>()
        var result: [(id: String, name: String)] = [("all", "All Regions")]
        for biz in businesses {
            if let rid = biz.region_id, let rname = biz.region_name, !seen.contains(rid) {
                result.append((String(rid), rname))
                seen.insert(rid)
            }
        }
        return result
    }

    private var manualHasAddress: Bool {
        !manualAddress.trimmingCharacters(in: .whitespaces).isEmpty &&
        !manualCity.trimmingCharacters(in: .whitespaces).isEmpty &&
        !manualState.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var manualHasCoords: Bool {
        !manualLat.isEmpty && !manualLng.isEmpty
    }

    private var manualCanAdd: Bool {
        manualHasAddress || manualHasCoords
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segmented control
                Picker("Mode", selection: $mode) {
                    Text("Businesses").tag(0)
                    Text("Manual Address").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(hex: "f5f4f0"))

                if mode == 0 {
                    businessSearchView
                } else {
                    manualEntryView
                }
            }
            .navigationTitle("Add Stop")
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

    // MARK: - Business Search View

    private var businessSearchView: some View {
        VStack(spacing: 0) {
            // Region filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(regionNames, id: \.id) { region in
                        Button(action: { filterRegion = region.id }) {
                            Text(region.name)
                                .font(.custom("DMSans-SemiBold", size: 12))
                                .foregroundColor(filterRegion == region.id ? .white : Color(hex: "3a3d4a"))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(filterRegion == region.id ? Color(hex: "c8893a") : Color.white)
                                .cornerRadius(50)
                                .overlay(RoundedRectangle(cornerRadius: 50).stroke(filterRegion == region.id ? Color.clear : Color(hex: "e2dfd6"), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }

                    Toggle(isOn: $showInactive) {
                        Text("Inactive")
                            .font(.custom("DMSans-Medium", size: 11))
                            .foregroundColor(Color(hex: "7a7f94"))
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .tint(Color(hex: "c8893a"))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background(Color(hex: "f5f4f0").opacity(0.5))

            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "7a7f94"))
                TextField("Search by name, address, or city", text: $searchText)
                    .font(.custom("DMSans-Regular", size: 14))
                    .foregroundColor(Color(hex: "0f1117"))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "7a7f94"))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color.white)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "e2dfd6"), lineWidth: 1))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // Results count
            HStack {
                Text("\(filteredLocations.count) location\(filteredLocations.count == 1 ? "" : "s")")
                    .font(.custom("DMSans-Regular", size: 11))
                    .foregroundColor(Color(hex: "7a7f94"))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)

            // Location list
            List {
                ForEach(filteredLocations) { loc in
                    Button(action: { addLocation(loc) }) {
                        HStack(spacing: 12) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(Color(hex: "2d6a4f"))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(loc.business_name ?? "Unknown")
                                    .font(.custom("DMSans-SemiBold", size: 14))
                                    .foregroundColor(Color(hex: "0f1117"))
                                    .lineLimit(1)
                                let addr = [loc.address, loc.city, loc.state]
                                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
                                if !addr.isEmpty {
                                    Text(addr)
                                        .font(.custom("DMSans-Regular", size: 12))
                                        .foregroundColor(Color(hex: "7a7f94"))
                                        .lineLimit(1)
                                }
                            }

                            Spacer()

                            if loc.is_deleted == true {
                                Text("Inactive")
                                    .font(.custom("DMSans-SemiBold", size: 9))
                                    .foregroundColor(Color(hex: "7a7f94"))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(hex: "e2dfd6"))
                                    .cornerRadius(50)
                            }

                            if let gal = loc.estimated_gallons, gal > 0 {
                                Text("\(gal)g")
                                    .font(.custom("DMSans-Medium", size: 11))
                                    .foregroundColor(Color(hex: "2d6a4f"))
                            }
                        }
                        .opacity(loc.is_deleted == true ? 0.5 : 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
        }
    }

    // MARK: - Manual Entry View

    private var manualEntryView: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !manualError.isEmpty {
                    Text(manualError)
                        .font(.custom("DMSans-Regular", size: 13))
                        .foregroundColor(Color(hex: "c1121f"))
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(Color(hex: "ffe5e7"))
                        .cornerRadius(8)
                }

                manualField(label: "Stop Name", text: $manualName, placeholder: "e.g. Drop-off Point A (optional)")
                manualField(label: "Street Address", text: $manualAddress, placeholder: "123 Main St")

                HStack(spacing: 10) {
                    manualField(label: "City", text: $manualCity, placeholder: "City")
                    manualField(label: "State", text: $manualState, placeholder: "VA")
                        .frame(width: 60)
                }

                HStack {
                    Rectangle().fill(Color(hex: "e2dfd6")).frame(height: 1)
                    Text("or enter coordinates")
                        .font(.custom("DMSans-Regular", size: 11))
                        .foregroundColor(Color(hex: "7a7f94"))
                        .layoutPriority(1)
                    Rectangle().fill(Color(hex: "e2dfd6")).frame(height: 1)
                }
                .padding(.vertical, 4)

                HStack(spacing: 10) {
                    manualField(label: "Latitude", text: $manualLat, placeholder: "e.g. 37.2710", keyboard: .numbersAndPunctuation)
                    manualField(label: "Longitude", text: $manualLng, placeholder: "e.g. -79.9414", keyboard: .numbersAndPunctuation)
                }

                Text("Provide either a full address (street, city, state) or coordinates. If both are provided, coordinates take priority.")
                    .font(.custom("DMSans-Regular", size: 11))
                    .foregroundColor(Color(hex: "7a7f94"))
                    .padding(.top, 4)

                Button(action: addManualStop) {
                    HStack {
                        if geocoding {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Stop")
                                .font(.custom("DMSans-SemiBold", size: 15))
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(manualCanAdd && !geocoding ? Color(hex: "2d6a4f") : Color(hex: "7a7f94"))
                    .cornerRadius(12)
                }
                .disabled(!manualCanAdd || geocoding)
            }
            .padding(20)
        }
        .background(Color(hex: "f5f4f0"))
    }

    // MARK: - Helpers

    private func manualField(label: String, text: Binding<String>, placeholder: String, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.custom("DMSans-SemiBold", size: 9))
                .foregroundColor(Color(hex: "7a7f94"))
                .tracking(0.4)
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .font(.custom("DMSans-Regular", size: 14))
                .padding(12)
                .background(Color.white)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "e2dfd6"), lineWidth: 1))
        }
    }

    private func addLocation(_ loc: Location) {
        guard let lat = loc.latitude, let lng = loc.longitude else { return }
        let addr = [loc.address, loc.city, loc.state]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        let stop = CustomStop(
            name: loc.business_name ?? "Unknown",
            address: addr.isEmpty ? "No address" : addr,
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
            source: .business(businessId: loc.business_id, locationId: loc.id)
        )
        onAdd(stop)
    }

    private func addManualStop() {
        manualError = ""
        let addrParts = [manualAddress, manualCity, manualState].filter { !$0.isEmpty }
        let addrString = addrParts.joined(separator: ", ")
        let stopName = manualName.trimmingCharacters(in: .whitespaces).isEmpty
            ? (addrString.isEmpty ? "Manual Stop" : addrString)
            : manualName.trimmingCharacters(in: .whitespaces)

        if manualHasCoords {
            guard let lat = Double(manualLat), let lng = Double(manualLng) else {
                manualError = "Please enter valid latitude and longitude values."
                return
            }
            let stop = CustomStop(
                name: stopName,
                address: addrString.isEmpty ? String(format: "%.4f, %.4f", lat, lng) : addrString,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                source: .manual
            )
            onAdd(stop)
            dismiss()
            return
        }

        guard manualHasAddress else {
            manualError = "Please enter a full address (street, city, state) or coordinates."
            return
        }

        geocoding = true
        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(addrString) { placemarks, error in
            DispatchQueue.main.async {
                geocoding = false
                if let error = error {
                    manualError = "Could not find coordinates: \(error.localizedDescription)"
                    return
                }
                guard let location = placemarks?.first?.location else {
                    manualError = "No matching location found. Please check the address or enter coordinates manually."
                    return
                }
                let stop = CustomStop(
                    name: stopName,
                    address: addrString,
                    coordinate: location.coordinate,
                    source: .manual
                )
                onAdd(stop)
                dismiss()
            }
        }
    }
}

// MARK: - Custom Stop Detail Sheet

struct CustomStopDetailSheet: View {
    let stop: CustomStop
    let startCoord: CLLocationCoordinate2D
    @Environment(\.dismiss) var dismiss
    @State private var copiedFeedback = false

    private var distanceMiles: Double {
        RouteEngine.haversine(from: startCoord, to: stop.coordinate) / 1609.344
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Navigate button
                    Button(action: openInMaps) {
                        HStack {
                            Image(systemName: "map.fill").font(.system(size: 14))
                            Text("Navigate").font(.custom("DMSans-SemiBold", size: 15))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(hex: "0f1117"))
                        .cornerRadius(12)
                    }

                    // Header
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stop.name)
                            .font(.custom("Syne-Bold", size: 18))
                            .foregroundColor(Color(hex: "0f1117"))
                        Text(stop.address)
                            .font(.custom("DMSans-Regular", size: 14))
                            .foregroundColor(Color(hex: "7a7f94"))
                    }

                    Divider()

                    // Distance
                    HStack(spacing: 10) {
                        Image(systemName: "road.lanes")
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "7a7f94"))
                            .frame(width: 20)
                        Text(String(format: "%.1f miles from start", distanceMiles))
                            .font(.custom("DMSans-Regular", size: 13))
                            .foregroundColor(Color(hex: "7a7f94"))
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
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: "e2dfd6"), lineWidth: 1))
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Stop Details")
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
        String(format: "%.6f, %.6f", stop.coordinate.latitude, stop.coordinate.longitude)
    }

    private func copyCoordinates() {
        UIPasteboard.general.string = coordString
        copiedFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedFeedback = false }
    }

    private func openInMaps() {
        MapHelpers.openDirections(to: stop.coordinate, name: stop.name)
    }
}

// MARK: - Save Route Sheet

struct SaveRouteSheet: View {
    let stops: [CustomStop]
    let startName: String
    let startCoord: CLLocationCoordinate2D
    let existingRouteId: Int?
    let existingRouteName: String
    let onSaved: (Int, String) -> Void

    @Environment(\.dismiss) var dismiss
    @State private var routeName = ""
    @State private var saving = false
    @State private var errorMsg = ""

    private var isExisting: Bool { existingRouteId != nil }

    private var stopsData: [[String: Any]] {
        stops.map { stop in
            var dict: [String: Any] = [
                "name": stop.name,
                "address": stop.address,
                "latitude": stop.coordinate.latitude,
                "longitude": stop.coordinate.longitude
            ]
            switch stop.source {
            case .business(let bizId, let locId):
                dict["source_type"] = "business"
                dict["business_id"] = bizId
                dict["location_id"] = locId
            case .manual:
                dict["source_type"] = "manual"
            }
            return dict
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Error message
                    if !errorMsg.isEmpty {
                        Text(errorMsg)
                            .font(.custom("DMSans-Regular", size: 13))
                            .foregroundColor(Color(hex: "c1121f"))
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(Color(hex: "ffe5e7"))
                            .cornerRadius(8)
                    }

                    if isExisting {
                        // Existing route — show action options
                        existingRouteActions
                    } else {
                        // New route — just name + save
                        newRouteForm
                    }

                    // Summary
                    routeSummary
                }
                .padding(20)
            }
            .navigationTitle(isExisting ? "Save Route" : "Save New Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.custom("DMSans-Regular", size: 14))
                        .foregroundColor(Color(hex: "7a7f94"))
                }
            }
            .onAppear {
                routeName = existingRouteName
            }
        }
    }

    // MARK: - New Route Form

    private var newRouteForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ROUTE NAME")
                    .font(.custom("DMSans-SemiBold", size: 9))
                    .foregroundColor(Color(hex: "7a7f94"))
                    .tracking(0.4)
                TextField("e.g. Monday Roanoke Run", text: $routeName)
                    .font(.custom("DMSans-Regular", size: 14))
                    .padding(12)
                    .background(Color.white)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "e2dfd6"), lineWidth: 1))
            }

            Button(action: saveNew) {
                HStack {
                    if saving { ProgressView().scaleEffect(0.8).tint(.white) }
                    else { Image(systemName: "square.and.arrow.down").font(.system(size: 14)) }
                    Text("Save Route").font(.custom("DMSans-SemiBold", size: 15))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(hex: "2d6a4f"))
                .cornerRadius(12)
            }
            .disabled(saving)
        }
    }

    // MARK: - Existing Route Actions

    private var existingRouteActions: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Current route info
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: "c8893a"))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current Route")
                        .font(.custom("DMSans-SemiBold", size: 9))
                        .foregroundColor(Color(hex: "7a7f94"))
                        .tracking(0.4)
                    Text(existingRouteName)
                        .font(.custom("DMSans-SemiBold", size: 15))
                        .foregroundColor(Color(hex: "0f1117"))
                }
                Spacer()
            }
            .padding(14)
            .background(Color(hex: "f5f4f0"))
            .cornerRadius(10)

            // Save (overwrite)
            Button(action: saveOverwrite) {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.down").font(.system(size: 16))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Save").font(.custom("DMSans-SemiBold", size: 15))
                        Text("Update \"\(existingRouteName)\" with current stops")
                            .font(.custom("DMSans-Regular", size: 11))
                            .foregroundColor(Color(hex: "7a7f94"))
                    }
                    Spacer()
                    if saving { ProgressView().scaleEffect(0.8) }
                }
                .foregroundColor(Color(hex: "0f1117"))
                .padding(16)
                .background(Color.white)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "2d6a4f"), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .disabled(saving)

            Divider()

            // Rename
            VStack(alignment: .leading, spacing: 8) {
                Text("RENAME")
                    .font(.custom("DMSans-SemiBold", size: 9))
                    .foregroundColor(Color(hex: "7a7f94"))
                    .tracking(0.4)
                TextField("New name", text: $routeName)
                    .font(.custom("DMSans-Regular", size: 14))
                    .padding(12)
                    .background(Color.white)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "e2dfd6"), lineWidth: 1))

                Button(action: renameRoute) {
                    HStack(spacing: 8) {
                        Image(systemName: "pencil").font(.system(size: 14))
                        Text("Rename & Save").font(.custom("DMSans-SemiBold", size: 14))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(hex: "c8893a"))
                    .cornerRadius(10)
                }
                .disabled(saving)
            }

            Divider()

            // Save as Copy
            VStack(alignment: .leading, spacing: 8) {
                Text("SAVE AS COPY")
                    .font(.custom("DMSans-SemiBold", size: 9))
                    .foregroundColor(Color(hex: "7a7f94"))
                    .tracking(0.4)
                Text("Creates a new saved route with the stops below.")
                    .font(.custom("DMSans-Regular", size: 12))
                    .foregroundColor(Color(hex: "7a7f94"))

                Button(action: saveAsCopy) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.on.doc").font(.system(size: 14))
                        Text("Save as Copy").font(.custom("DMSans-SemiBold", size: 14))
                    }
                    .foregroundColor(Color(hex: "0f1117"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "e2dfd6"), lineWidth: 1))
                }
                .disabled(saving)
            }
        }
    }

    // MARK: - Summary

    private var routeSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ROUTE SUMMARY")
                .font(.custom("DMSans-SemiBold", size: 9))
                .foregroundColor(Color(hex: "7a7f94"))
                .tracking(0.4)

            HStack(spacing: 16) {
                Label("\(stops.count) stops", systemImage: "mappin.circle.fill")
                    .font(.custom("DMSans-Medium", size: 13))
                    .foregroundColor(Color(hex: "2d6a4f"))
                Label("from \(startName)", systemImage: "house.fill")
                    .font(.custom("DMSans-Medium", size: 13))
                    .foregroundColor(Color(hex: "7a7f94"))
            }

            ForEach(Array(stops.enumerated()), id: \.element.id) { idx, stop in
                HStack(spacing: 8) {
                    Text("\(idx + 1).")
                        .font(.custom("DMSans-SemiBold", size: 12))
                        .foregroundColor(Color(hex: "c8893a"))
                        .frame(width: 20, alignment: .trailing)
                    Text(stop.name)
                        .font(.custom("DMSans-Regular", size: 13))
                        .foregroundColor(Color(hex: "0f1117"))
                        .lineLimit(1)
                }
            }
        }
        .padding(16)
        .background(Color(hex: "f5f4f0"))
        .cornerRadius(10)
    }

    // MARK: - Actions

    private func saveNew() {
        let trimmed = routeName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            errorMsg = "Please enter a name for this route before saving."
            return
        }
        saving = true; errorMsg = ""
        Task {
            do {
                let saved = try await APIClient.shared.saveRoute(
                    name: trimmed, startName: startName,
                    startLat: startCoord.latitude, startLng: startCoord.longitude,
                    stops: stopsData
                )
                onSaved(saved.id, saved.name)
                dismiss()
            } catch { errorMsg = error.localizedDescription }
            saving = false
        }
    }

    private func saveOverwrite() {
        guard let routeId = existingRouteId else { return }
        saving = true; errorMsg = ""
        Task {
            do {
                let saved = try await APIClient.shared.updateSavedRoute(
                    id: routeId, name: existingRouteName, startName: startName,
                    startLat: startCoord.latitude, startLng: startCoord.longitude,
                    stops: stopsData
                )
                onSaved(saved.id, saved.name)
                dismiss()
            } catch { errorMsg = error.localizedDescription }
            saving = false
        }
    }

    private func renameRoute() {
        let trimmed = routeName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            errorMsg = "Please enter a new name for this route."
            return
        }
        guard let routeId = existingRouteId else { return }
        saving = true; errorMsg = ""
        Task {
            do {
                let saved = try await APIClient.shared.updateSavedRoute(
                    id: routeId, name: trimmed, startName: startName,
                    startLat: startCoord.latitude, startLng: startCoord.longitude,
                    stops: stopsData
                )
                onSaved(saved.id, saved.name)
                dismiss()
            } catch { errorMsg = error.localizedDescription }
            saving = false
        }
    }

    private func saveAsCopy() {
        let trimmed = routeName.trimmingCharacters(in: .whitespaces)
        let copyName = trimmed.isEmpty ? "\(existingRouteName) (Copy)" : trimmed
        saving = true; errorMsg = ""
        Task {
            do {
                let saved = try await APIClient.shared.saveRoute(
                    name: copyName, startName: startName,
                    startLat: startCoord.latitude, startLng: startCoord.longitude,
                    stops: stopsData
                )
                onSaved(saved.id, saved.name)
                dismiss()
            } catch { errorMsg = error.localizedDescription }
            saving = false
        }
    }
}

// MARK: - Load Routes Sheet

struct LoadRoutesSheet: View {
    let isAdmin: Bool
    let onLoad: (SavedRoute) -> Void

    @Environment(\.dismiss) var dismiss
    @State private var routes: [SavedRoute] = []
    @State private var loading = true
    @State private var errorMsg = ""
    @State private var searchText = ""
    @State private var scope = "mine"
    @State private var period = ""
    @State private var showDeleteConfirm = false
    @State private var routeToDelete: SavedRoute?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filters bar
                VStack(spacing: 8) {
                    // Admin scope toggle
                    if isAdmin {
                        HStack(spacing: 8) {
                            scopeButton("My Routes", value: "mine")
                            scopeButton("All Routes", value: "all")
                            Spacer()
                        }
                    }

                    // Period filter
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            periodButton("All Time", value: "")
                            periodButton("Today", value: "day")
                            periodButton("This Week", value: "week")
                            periodButton("This Month", value: "month")
                            periodButton("This Year", value: "year")
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(hex: "f5f4f0"))
                .overlay(Rectangle().fill(Color(hex: "e2dfd6")).frame(height: 1), alignment: .bottom)

                // Content
                if loading {
                    Spacer()
                    ProgressView("Loading routes…")
                        .font(.custom("DMSans-Regular", size: 14))
                    Spacer()
                } else if routes.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "folder")
                            .font(.system(size: 36))
                            .foregroundColor(Color(hex: "e2dfd6"))
                        Text("No saved routes")
                            .font(.custom("DMSans-SemiBold", size: 16))
                            .foregroundColor(Color(hex: "7a7f94"))
                        Text("Build a custom route and tap the save icon to save it here.")
                            .font(.custom("DMSans-Regular", size: 13))
                            .foregroundColor(Color(hex: "7a7f94"))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(routes) { route in
                            Button(action: { loadRoute(route) }) {
                                HStack(spacing: 14) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(route.name)
                                            .font(.custom("DMSans-SemiBold", size: 15))
                                            .foregroundColor(Color(hex: "0f1117"))
                                            .lineLimit(1)

                                        HStack(spacing: 10) {
                                            Label("\(route.stops?.count ?? 0) stops", systemImage: "mappin.circle.fill")
                                                .font(.custom("DMSans-Regular", size: 11))
                                                .foregroundColor(Color(hex: "2d6a4f"))

                                            if let startName = route.start_name {
                                                Label(startName, systemImage: "house.fill")
                                                    .font(.custom("DMSans-Regular", size: 11))
                                                    .foregroundColor(Color(hex: "7a7f94"))
                                                    .lineLimit(1)
                                            }
                                        }

                                        HStack(spacing: 10) {
                                            Label(formatDate(route.created_at), systemImage: "clock")
                                                .font(.custom("DMSans-Regular", size: 11))
                                                .foregroundColor(Color(hex: "7a7f94"))

                                            if scope == "all", let userName = route.user_name {
                                                Label(userName, systemImage: "person.fill")
                                                    .font(.custom("DMSans-Regular", size: 11))
                                                    .foregroundColor(Color(hex: "c8893a"))
                                            }
                                        }
                                    }

                                    Spacer()

                                    Button(action: { routeToDelete = route; showDeleteConfirm = true }) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 14))
                                            .foregroundColor(Color(hex: "c1121f").opacity(0.5))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listStyle(.plain)
                }
                }
            .searchable(text: $searchText, prompt: "Search by route name")
            .navigationTitle("Saved Routes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.custom("DMSans-Medium", size: 14))
                        .foregroundColor(Color(hex: "c8893a"))
                }
            }
            .task { await fetchRoutes() }
            .onChange(of: scope) { _, _ in Task { await fetchRoutes() } }
            .onChange(of: period) { _, _ in Task { await fetchRoutes() } }
            .onChange(of: searchText) { _, _ in Task { await fetchRoutes() } }
            .confirmationDialog("Delete this route?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let route = routeToDelete { deleteRoute(route) }
                }
                Button("Cancel", role: .cancel) { routeToDelete = nil }
            } message: {
                Text("This saved route will be permanently removed.")
            }
        }
    }

    // MARK: - Filter Buttons

    private func scopeButton(_ label: String, value: String) -> some View {
        Button(action: { scope = value }) {
            Text(label)
                .font(.custom("DMSans-SemiBold", size: 12))
                .foregroundColor(scope == value ? .white : Color(hex: "3a3d4a"))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(scope == value ? Color(hex: "0f1117") : Color.white)
                .cornerRadius(50)
                .overlay(RoundedRectangle(cornerRadius: 50).stroke(scope == value ? Color.clear : Color(hex: "e2dfd6"), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func periodButton(_ label: String, value: String) -> some View {
        Button(action: { period = value }) {
            Text(label)
                .font(.custom("DMSans-SemiBold", size: 11))
                .foregroundColor(period == value ? .white : Color(hex: "3a3d4a"))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(period == value ? Color(hex: "c8893a") : Color.white)
                .cornerRadius(50)
                .overlay(RoundedRectangle(cornerRadius: 50).stroke(period == value ? Color.clear : Color(hex: "e2dfd6"), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func fetchRoutes() async {
        loading = true
        do {
            routes = try await APIClient.shared.getSavedRoutes(scope: scope, search: searchText, period: period)
        } catch {
            errorMsg = error.localizedDescription
        }
        loading = false
    }

    private func loadRoute(_ route: SavedRoute) {
        onLoad(route)
        dismiss()
    }

    private func deleteRoute(_ route: SavedRoute) {
        Task {
            do {
                _ = try await APIClient.shared.deleteSavedRoute(id: route.id)
                await fetchRoutes()
            } catch { }
            routeToDelete = nil
        }
    }

    private func formatDate(_ dateStr: String?) -> String {
        guard let str = dateStr else { return "—" }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = iso.date(from: str) ?? ISO8601DateFormatter().date(from: str) else {
            return String(str.prefix(10))
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, yyyy h:mm a"
        return fmt.string(from: date)
    }
}

// MARK: - Custom Route Map Sheet

struct CustomRouteMapSheet: View {
    let stops: [CustomStop]
    let startCoord: CLLocationCoordinate2D
    let startName: String
    var onStopTap: ((CustomStop) -> Void)? = nil

    @Environment(\.dismiss) var dismiss
    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        NavigationStack {
            Map(position: $cameraPosition) {
                Annotation("Start", coordinate: startCoord) {
                    ZStack {
                        Circle().fill(Color(hex: "0f1117")).frame(width: 28, height: 28)
                        Image(systemName: "house.fill").font(.system(size: 12)).foregroundColor(.white)
                    }
                }

                ForEach(Array(stops.enumerated()), id: \.element.id) { idx, stop in
                    Annotation(stop.name, coordinate: stop.coordinate) {
                        Button(action: { onStopTap?(stop) }) {
                            ZStack {
                                Circle().fill(Color(hex: "c8893a")).frame(width: 30, height: 30)
                                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                                Text("\(idx + 1)").font(.custom("Syne-Bold", size: 13)).foregroundColor(.white)
                            }
                        }
                    }
                }

                if stops.count >= 1 {
                    let coords = [startCoord] + stops.map { $0.coordinate } + [startCoord]
                    MapPolyline(coordinates: coords).stroke(Color(hex: "c8893a"), lineWidth: 3)
                }
            }
            .mapStyle(.standard(elevation: .flat))
            .mapControls { MapCompass(); MapScaleView() }
            .overlay(alignment: .bottom) {
                HStack(spacing: 8) {
                    Label("\(stops.count) stops", systemImage: "mappin.circle.fill")
                        .font(.custom("DMSans-SemiBold", size: 12))
                        .foregroundColor(Color(hex: "2d6a4f"))
                    Text("·").foregroundColor(.white.opacity(0.4))
                    let totalMiles = totalRouteMiles()
                    Label(String(format: "%.1f mi", totalMiles), systemImage: "road.lanes")
                        .font(.custom("DMSans-SemiBold", size: 12))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .cornerRadius(12)
                .padding(.bottom, 12)
            }
            .navigationTitle("Route Map")
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

    private func totalRouteMiles() -> Double {
        guard !stops.isEmpty else { return 0 }
        let allCoords = [startCoord] + stops.map { $0.coordinate } + [startCoord]
        var total = 0.0
        for i in 0..<(allCoords.count - 1) {
            total += RouteEngine.haversine(from: allCoords[i], to: allCoords[i + 1])
        }
        return total / 1609.344
    }
}

#Preview {
    NavigationStack { CustomRouteView() }.environmentObject(AuthManager())
}
