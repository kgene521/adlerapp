// AdlerCRM/Views/RoutePlannerView.swift  28/03/2026 22:28:54
import SwiftUI
import MapKit
import CoreLocation
import Combine

// MARK: - Starting Location Presets

struct StartLocation: Identifiable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

let startLocationPresets: [StartLocation] = [
    StartLocation(id: "current",     name: "Current Location",  subtitle: "GPS",                 latitude: 0, longitude: 0),
    StartLocation(id: "roanoke",     name: "Roanoke",           subtitle: "Downtown, VA",        latitude: 37.2710, longitude: -79.9414),
    StartLocation(id: "front_royal", name: "Front Royal",       subtitle: "VA",                  latitude: 38.9182, longitude: -78.1944),
    StartLocation(id: "boones_mill", name: "Boones Mill",       subtitle: "Adler HQ, 101 Depot", latitude: 37.1182, longitude: -79.9428),
]

private let defaultStartCoord = CLLocationCoordinate2D(latitude: 37.2710, longitude: -79.9414)

// MARK: - Route Planner View

struct RoutePlannerView: View {
    @StateObject private var locationManager = LocationHelper()
    @State private var candidates: [RouteCandidate] = []
    @State private var route: [RouteStop] = []
    @State private var originalRoute: [RouteStop] = []
    @State private var loading = true
    @State private var errorMsg = ""
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var nextReadyDate: Date?
    @State private var nextReadyCount = 0
    @State private var isDirty = false

    // Starting location
    @State private var selectedStartId: String = "current"
    @State private var startCoord: CLLocationCoordinate2D = defaultStartCoord
    @State private var showStartPicker = false

    // Region
    @State private var regionOptions: [RegionInfo] = []
    @State private var selectedRegionId: Int = -1
    @State private var regionAutoSelected = false

    // Collapse
    @State private var showControls = false
    @State private var showMap = true
    @State private var showSaveSheet = false

    var body: some View {
        VStack(spacing: 0) {
            if loading {
                Spacer()
                ProgressView("Calculating routes…")
                    .font(.custom("DMSans-Regular", size: 14))
                Spacer()
            } else if !errorMsg.isEmpty {
                errorView
            } else if route.isEmpty {
                controlBar
                RouteEmptyView(
                    regionName: selectedRegionId >= 0 ? currentRegionName : nil,
                    nextReadyDate: nextReadyDate,
                    nextReadyCount: nextReadyCount
                )
            } else {
                // Compact summary bar (always visible)
                compactBar

                // Expanded controls (collapsible)
                if showControls {
                    controlBar
                }

                // Route map + list
                RouteMapListView(
                    route: $route,
                    startCoord: startCoord,
                    regionName: currentRegionName,
                    startName: currentStartName,
                    cameraPosition: $cameraPosition,
                    isDirty: $isDirty,
                    showMap: $showMap,
                    onReset: {
                        route = originalRoute
                        isDirty = false
                        cameraPosition = .automatic
                    }
                )
            }
        }
        .navigationTitle("Today's Route")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 14) {
                    if !route.isEmpty {
                        Button(action: { showSaveSheet = true }) {
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
                    Button(action: reload) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(Color(hex: "7a7f94"))
                    }
                }
            }
        }
        .task { await loadAndCompute() }
        .onChange(of: selectedRegionId) { _, _ in
            if regionAutoSelected { regionAutoSelected = false; return }
            recompute()
        }
        .sheet(isPresented: $showStartPicker) {
            StartLocationPickerSheet(
                selectedId: $selectedStartId,
                currentCoord: locationManager.lastLocation?.coordinate,
                onSelect: { applyStartLocation($0) }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSaveSheet) {
            TodayRouteSaveSheet(
                route: route,
                startName: currentStartName,
                startCoord: startCoord,
                regionName: currentRegionName,
                onSaved: {
                    originalRoute = route
                    isDirty = false
                }
            )
        }
    }

    // MARK: - Compact Summary Bar

    private var compactBar: some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() } }) {
            HStack(spacing: 8) {
                Image(systemName: selectedStartId == "current" ? "location.fill" : "mappin.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "2d6a4f"))
                Text(currentStartName)
                    .font(.custom("DMSans-SemiBold", size: 12))
                    .foregroundColor(Color(hex: "0f1117"))
                    .lineLimit(1)

                if let name = currentRegionName {
                    Text("·").foregroundColor(Color(hex: "e2dfd6"))
                    Text(name)
                        .font(.custom("DMSans-Medium", size: 12))
                        .foregroundColor(Color(hex: "c8893a"))
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: showControls ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(hex: "7a7f94"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .background(Color.white)
        .overlay(Rectangle().fill(Color(hex: "e2dfd6")).frame(height: 1), alignment: .bottom)
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        VStack(spacing: 0) {
            Button(action: { showStartPicker = true }) {
                HStack(spacing: 10) {
                    Image(systemName: selectedStartId == "current" ? "location.fill" : "mappin.circle.fill")
                        .font(.system(size: 14))
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
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(hex: "e2dfd6"))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .background(Color.white)
            .overlay(Rectangle().fill(Color(hex: "e2dfd6")).frame(height: 1), alignment: .bottom)

            if regionOptions.count > 1 {
                RegionPickerBar(options: regionOptions, selectedId: $selectedRegionId)
            }
        }
    }

    // MARK: - Error

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
            Button("Retry") { reload() }
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

    // MARK: - Logic

    private func reload() { Task { await loadAndCompute() } }

    private func loadAndCompute() async {
        loading = true; errorMsg = ""
        try? await Task.sleep(nanoseconds: 500_000_000)
        resolveStartCoord()
        do {
            candidates = try await APIClient.shared.getRouteCandidates()
            regionOptions = RouteEngine.buildRegions(from: candidates)
            regionAutoSelected = true
            selectedRegionId = RouteEngine.closestRegionId(to: startCoord, from: regionOptions)
            recompute()
        } catch { errorMsg = error.localizedDescription }
        loading = false
    }

    private func recompute() {
        cameraPosition = .automatic
        isDirty = false
        let result = RouteEngine.computeRoute(
            candidates: candidates, targetDate: Date(),
            regionId: selectedRegionId, startCoord: startCoord
        )
        route = result.stops
        originalRoute = result.stops
        nextReadyDate = result.nextReadyDate
        nextReadyCount = result.nextReadyCount
    }

    private func resolveStartCoord() {
        if selectedStartId == "current" {
            startCoord = locationManager.lastLocation?.coordinate ?? defaultStartCoord
        } else if let preset = startLocationPresets.first(where: { $0.id == selectedStartId }) {
            startCoord = preset.coordinate
        }
    }

    private func applyStartLocation(_ loc: StartLocation) {
        selectedStartId = loc.id
        resolveStartCoord()
        regionAutoSelected = true
        selectedRegionId = RouteEngine.closestRegionId(to: startCoord, from: regionOptions)
        recompute()
    }

    private var currentRegionName: String? {
        regionOptions.first { $0.id == selectedRegionId }?.name
    }

    private var currentStartName: String {
        if selectedStartId == "current" {
            return locationManager.lastLocation != nil ? "Current Location" : "Roanoke, VA (default)"
        }
        return startLocationPresets.first { $0.id == selectedStartId }?.name ?? "Unknown"
    }
}

// MARK: - Start Location Picker Sheet

struct StartLocationPickerSheet: View {
    @Binding var selectedId: String
    let currentCoord: CLLocationCoordinate2D?
    let onSelect: (StartLocation) -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(startLocationPresets) { loc in
                    Button(action: { onSelect(loc); dismiss() }) {
                        HStack(spacing: 14) {
                            Image(systemName: loc.id == "current" ? "location.fill" : "mappin.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(loc.id == "current" ? Color(hex: "2d6a4f") : Color(hex: "c8893a"))
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(loc.name).font(.custom("DMSans-SemiBold", size: 15)).foregroundColor(Color(hex: "0f1117"))
                                Text(startSubtitle(loc)).font(.custom("DMSans-Regular", size: 12)).foregroundColor(Color(hex: "7a7f94"))
                            }
                            Spacer()
                            if selectedId == loc.id {
                                Image(systemName: "checkmark.circle.fill").font(.system(size: 18)).foregroundColor(Color(hex: "2d6a4f"))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Starting Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.font(.custom("DMSans-Medium", size: 14)).foregroundColor(Color(hex: "c8893a"))
                }
            }
        }
    }

    private func startSubtitle(_ loc: StartLocation) -> String {
        if loc.id == "current" {
            if let coord = currentCoord { return String(format: "%.4f, %.4f", coord.latitude, coord.longitude) }
            return "GPS unavailable — defaults to Roanoke"
        }
        return loc.subtitle
    }
}

// MARK: - Shared Region Picker Bar

struct RegionPickerBar: View {
    let options: [RegionInfo]
    @Binding var selectedId: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options) { option in
                    Button(action: { selectedId = option.id }) {
                        HStack(spacing: 5) {
                            if option.id == -1 { Image(systemName: "globe").font(.system(size: 10)) }
                            Text(option.name).font(.custom("DMSans-SemiBold", size: 12))
                        }
                        .foregroundColor(selectedId == option.id ? .white : Color(hex: "3a3d4a"))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(selectedId == option.id ? Color(hex: "c8893a") : Color.white)
                        .cornerRadius(50)
                        .overlay(RoundedRectangle(cornerRadius: 50).stroke(selectedId == option.id ? Color.clear : Color(hex: "e2dfd6"), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .background(Color(hex: "f5f4f0"))
        .overlay(Rectangle().fill(Color(hex: "e2dfd6")).frame(height: 1), alignment: .bottom)
    }
}

// MARK: - Shared Route Map + List View

struct RouteMapListView: View {
    @Binding var route: [RouteStop]
    let startCoord: CLLocationCoordinate2D
    let regionName: String?
    let startName: String
    @Binding var cameraPosition: MapCameraPosition
    @Binding var isDirty: Bool
    @Binding var showMap: Bool
    var onReset: (() -> Void)? = nil
    @State private var selectedStop: RouteStop?
    @State private var highlightedStopId: Int?
    @State private var showStartDetail = false
    @State private var selectedBusinessId: Int?
    @State private var mapHeight: CGFloat = 250
    @GestureState private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            // Stats bar with map toggle
            HStack {
                Label("\(route.count) stops", systemImage: "mappin.circle.fill")
                    .font(.custom("DMSans-SemiBold", size: 12))
                    .foregroundColor(Color(hex: "2d6a4f"))
                if isDirty {
                    Text("·").foregroundColor(Color(hex: "e2dfd6"))
                    Button(action: { onReset?() }) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 9, weight: .bold))
                            Text("Reset")
                                .font(.custom("DMSans-SemiBold", size: 12))
                        }
                        .foregroundColor(Color(hex: "c1121f"))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                let totalGal = route.reduce(0) { $0 + $1.fillLevel }
                Label("~\(Int(totalGal))g", systemImage: "drop.fill")
                    .font(.custom("DMSans-SemiBold", size: 12))
                    .foregroundColor(Color(hex: "c8893a"))
                Text("·").foregroundColor(Color(hex: "e2dfd6"))
                let totalMiles = totalRouteMiles()
                Label(String(format: "%.1f mi", totalMiles), systemImage: "road.lanes")
                    .font(.custom("DMSans-SemiBold", size: 12))
                    .foregroundColor(Color(hex: "7a7f94"))
                Text("·").foregroundColor(Color(hex: "e2dfd6"))
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showMap.toggle() } }) {
                    Image(systemName: showMap ? "map.fill" : "map")
                        .font(.system(size: 13))
                        .foregroundColor(showMap ? Color(hex: "2d6a4f") : Color(hex: "7a7f94"))
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Color(hex: "f5f4f0"))

            // Map (collapsible)
            if showMap {
            Map(position: $cameraPosition) {
                Annotation("Start", coordinate: startCoord) {
                    Button(action: { showStartDetail = true }) {
                        ZStack {
                            Circle().fill(Color(hex: "0f1117")).frame(width: 28, height: 28)
                            Image(systemName: "house.fill").font(.system(size: 12)).foregroundColor(.white)
                        }
                    }
                }

                ForEach(route) { stop in
                    Annotation(stop.candidate.business_name ?? "", coordinate: stop.coordinate) {
                        Button(action: { pinTapped(stop) }) {
                            ZStack {
                                Circle().fill(stopColor(stop)).frame(width: 30, height: 30)
                                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                                Text("\(stop.stopNumber)").font(.custom("Syne-Bold", size: 13)).foregroundColor(.white)
                            }
                        }
                    }
                }

                if route.count >= 1 {
                    let coords = [startCoord] + route.map { $0.coordinate } + [startCoord]
                    MapPolyline(coordinates: coords).stroke(Color(hex: "c8893a"), lineWidth: 3)
                }

                ForEach(Array(segmentDistances().enumerated()), id: \.offset) { _, seg in
                    Annotation("", coordinate: seg.midpoint) {
                        Text(seg.label)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: "0f1117"))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.9))
                            .cornerRadius(4)
                            .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat))
            .mapControls { MapCompass(); MapScaleView() }
            .frame(height: min(max(mapHeight + dragOffset, 120), 500))

                // Resize handle
                mapResizeHandle
            }

            // Stop list with reorder + scroll-to support
            ScrollViewReader { proxy in
                List {
                    ForEach(route) { stop in
                        StopRow(stop: stop, onBusinessTap: { bizId in
                            selectedBusinessId = bizId
                        })
                            .id(stop.id)
                            .listRowBackground(highlightedStopId == stop.id ? Color(hex: "fff3e0") : Color.white)
                    }
                    .onMove { from, to in
                        route.move(fromOffsets: from, toOffset: to)
                        renumberStops()
                        cameraPosition = .automatic
                        isDirty = true
                    }
                }
                .listStyle(.plain)
                .environment(\.editMode, .constant(.active))
                .onChange(of: highlightedStopId) { _, newId in
                    if let id = newId {
                        withAnimation {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
        }
        .sheet(item: $selectedStop) { stop in
            StopNavigateSheet(stop: stop, startCoord: startCoord)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showStartDetail) {
            StartLocationDetailSheet(name: startName, coordinate: startCoord)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: Binding(
            get: { selectedBusinessId != nil },
            set: { if !$0 { selectedBusinessId = nil } }
        )) {
            if let bizId = selectedBusinessId {
                NavigationStack {
                    BusinessDetailLoadingView(businessId: bizId)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") { selectedBusinessId = nil }
                                    .font(.custom("DMSans-Medium", size: 14))
                                    .foregroundColor(Color(hex: "c8893a"))
                            }
                        }
                }
            }
        }
    }

    private func stopColor(_ stop: RouteStop) -> Color {
        if stop.fillPercent >= 1.5 { return Color(hex: "c1121f") }
        if stop.fillPercent >= 1.0 { return Color(hex: "c8893a") }
        return Color(hex: "2d6a4f")
    }

    private var mapResizeHandle: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: "c8893a").opacity(0.5))
                .frame(width: 40, height: 4)
                .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity)
        .background(Color(hex: "f5f4f0"))
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .updating($dragOffset) { value, state, _ in
                    state = value.translation.height
                }
                .onEnded { value in
                    let newHeight = mapHeight + value.translation.height
                    mapHeight = min(max(newHeight, 120), 500)
                }
        )
        .overlay(Rectangle().fill(Color(hex: "e2dfd6")).frame(height: 1), alignment: .bottom)
    }

    private func pinTapped(_ stop: RouteStop) {
        highlightedStopId = stop.id
        selectedStop = stop
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if highlightedStopId == stop.id {
                highlightedStopId = nil
            }
        }
    }

    private func renumberStops() {
        for i in 0..<route.count {
            route[i].stopNumber = i + 1
        }
    }

    private struct SegmentInfo {
        let midpoint: CLLocationCoordinate2D
        let label: String
    }

    private func segmentDistances() -> [SegmentInfo] {
        var segments: [SegmentInfo] = []
        let allCoords = [startCoord] + route.map { $0.coordinate } + [startCoord]

        for i in 0..<(allCoords.count - 1) {
            let a = allCoords[i]
            let b = allCoords[i + 1]
            let distMeters = RouteEngine.haversine(from: a, to: b)
            let distMiles = distMeters / 1609.344

            // Only show label if segment is > 0.1 miles
            if distMiles > 0.1 {
                let midLat = (a.latitude + b.latitude) / 2
                let midLng = (a.longitude + b.longitude) / 2
                let label = distMiles < 10 ? String(format: "%.1f mi", distMiles) : String(format: "%.0f mi", distMiles)
                segments.append(SegmentInfo(
                    midpoint: CLLocationCoordinate2D(latitude: midLat, longitude: midLng),
                    label: label
                ))
            }
        }
        return segments
    }

    private func totalRouteMiles() -> Double {
        let allCoords = [startCoord] + route.map { $0.coordinate } + [startCoord]
        var total = 0.0
        for i in 0..<(allCoords.count - 1) {
            total += RouteEngine.haversine(from: allCoords[i], to: allCoords[i + 1])
        }
        return total / 1609.344
    }
}

// MARK: - Stop Navigate Sheet

struct StopNavigateSheet: View {
    let stop: RouteStop
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
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(Color(hex: "c8893a")).frame(width: 40, height: 40)
                            Text("\(stop.stopNumber)").font(.custom("Syne-Bold", size: 16)).foregroundColor(.white)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stop.candidate.business_name ?? "Unknown")
                                .font(.custom("Syne-Bold", size: 18))
                                .foregroundColor(Color(hex: "0f1117"))
                            Text("Stop \(stop.stopNumber) of route")
                                .font(.custom("DMSans-Regular", size: 13))
                                .foregroundColor(Color(hex: "7a7f94"))
                        }
                    }

                    Divider()

                    // Address
                    if !stop.addressLine.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(Color(hex: "2d6a4f"))
                                .frame(width: 20)
                            Text(stop.addressLine)
                                .font(.custom("DMSans-Regular", size: 14))
                                .foregroundColor(Color(hex: "0f1117"))
                        }
                    }

                    // Info grid
                    HStack(spacing: 16) {
                        infoItem(icon: "drop.fill", label: "Fill Level", value: "\(Int(stop.fillLevel))/\(Int(routeContainerCapacity))g", color: Color(hex: "c8893a"))
                        infoItem(icon: "clock", label: "Last Pickup", value: "\(stop.daysSincePickup)d ago", color: Color(hex: "7a7f94"))
                        infoItem(icon: "arrow.up.right", label: "Est. Rate", value: "\(stop.estimatedGallons)g/wk", color: Color(hex: "2d6a4f"))
                    }

                    // Distance from start
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
        let placemark = MKPlacemark(coordinate: stop.coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = stop.candidate.business_name ?? "Collection Stop"
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }

    private func infoItem(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 14)).foregroundColor(color)
            Text(value).font(.custom("DMSans-SemiBold", size: 12)).foregroundColor(Color(hex: "0f1117"))
            Text(label).font(.custom("DMSans-Regular", size: 9)).foregroundColor(Color(hex: "7a7f94"))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(hex: "f5f4f0"))
        .cornerRadius(8)
    }
}

// MARK: - Start Location Detail Sheet

struct StartLocationDetailSheet: View {
    let name: String
    let coordinate: CLLocationCoordinate2D
    @Environment(\.dismiss) var dismiss
    @State private var copiedFeedback = false

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
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(Color(hex: "0f1117")).frame(width: 40, height: 40)
                            Image(systemName: "house.fill").font(.system(size: 14)).foregroundColor(.white)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name)
                                .font(.custom("Syne-Bold", size: 18))
                                .foregroundColor(Color(hex: "0f1117"))
                            Text("Starting Location")
                                .font(.custom("DMSans-Regular", size: 13))
                                .foregroundColor(Color(hex: "7a7f94"))
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
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: "e2dfd6"), lineWidth: 1))
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Start Location")
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
        String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude)
    }

    private func copyCoordinates() {
        UIPasteboard.general.string = coordString
        copiedFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedFeedback = false }
    }

    private func openInMaps() {
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = name
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }
}

// MARK: - Today Route Save Sheet

struct TodayRouteSaveSheet: View {
    let route: [RouteStop]
    let startName: String
    let startCoord: CLLocationCoordinate2D
    let regionName: String?
    let onSaved: () -> Void

    @Environment(\.dismiss) var dismiss
    @State private var routeName = ""
    @State private var saving = false
    @State private var errorMsg = ""

    private var stopsData: [[String: Any]] {
        route.map { stop in
            var dict: [String: Any] = [
                "name": stop.candidate.business_name ?? "Unknown",
                "address": stop.addressLine.isEmpty ? "No address" : stop.addressLine,
                "latitude": stop.coordinate.latitude,
                "longitude": stop.coordinate.longitude,
                "source_type": "business",
                "business_id": stop.candidate.business_id,
                "location_id": stop.id
            ]
            return dict
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if !errorMsg.isEmpty {
                        Text(errorMsg)
                            .font(.custom("DMSans-Regular", size: 13))
                            .foregroundColor(Color(hex: "c1121f"))
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(Color(hex: "ffe5e7"))
                            .cornerRadius(8)
                    }

                    // Save as custom route
                    VStack(alignment: .leading, spacing: 12) {
                        Text("SAVE AS CUSTOM ROUTE")
                            .font(.custom("DMSans-SemiBold", size: 9))
                            .foregroundColor(Color(hex: "7a7f94"))
                            .tracking(0.4)

                        Text("Save this route with a name so you can load it later from the Custom tab.")
                            .font(.custom("DMSans-Regular", size: 12))
                            .foregroundColor(Color(hex: "7a7f94"))

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

                        Button(action: saveAsCustom) {
                            HStack {
                                if saving { ProgressView().scaleEffect(0.8).tint(.white) }
                                else { Image(systemName: "square.and.arrow.down").font(.system(size: 14)) }
                                Text("Save as Custom Route").font(.custom("DMSans-SemiBold", size: 15))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(hex: "2d6a4f"))
                            .cornerRadius(12)
                        }
                        .disabled(saving)
                    }

                    // Route summary
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ROUTE SUMMARY")
                            .font(.custom("DMSans-SemiBold", size: 9))
                            .foregroundColor(Color(hex: "7a7f94"))
                            .tracking(0.4)

                        HStack(spacing: 16) {
                            Label("\(route.count) stops", systemImage: "mappin.circle.fill")
                                .font(.custom("DMSans-Medium", size: 13))
                                .foregroundColor(Color(hex: "2d6a4f"))
                            Label("from \(startName)", systemImage: "house.fill")
                                .font(.custom("DMSans-Medium", size: 13))
                                .foregroundColor(Color(hex: "7a7f94"))
                        }

                        if let region = regionName {
                            Label(region, systemImage: "map.circle.fill")
                                .font(.custom("DMSans-Medium", size: 13))
                                .foregroundColor(Color(hex: "c8893a"))
                        }

                        ForEach(route) { stop in
                            HStack(spacing: 8) {
                                Text("\(stop.stopNumber).")
                                    .font(.custom("DMSans-SemiBold", size: 12))
                                    .foregroundColor(Color(hex: "c8893a"))
                                    .frame(width: 20, alignment: .trailing)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(stop.candidate.business_name ?? "Unknown")
                                        .font(.custom("DMSans-SemiBold", size: 13))
                                        .foregroundColor(Color(hex: "0f1117"))
                                        .lineLimit(1)
                                    Text(stop.addressLine)
                                        .font(.custom("DMSans-Regular", size: 11))
                                        .foregroundColor(Color(hex: "7a7f94"))
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(Color(hex: "f5f4f0"))
                    .cornerRadius(10)
                }
                .padding(20)
            }
            .navigationTitle("Save Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.custom("DMSans-Regular", size: 14))
                        .foregroundColor(Color(hex: "7a7f94"))
                }
            }
        }
    }

    private func saveAsCustom() {
        let trimmed = routeName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            errorMsg = "Please enter a name for this route before saving."
            return
        }
        saving = true; errorMsg = ""
        Task {
            do {
                _ = try await APIClient.shared.saveRoute(
                    name: trimmed,
                    startName: startName,
                    startLat: startCoord.latitude,
                    startLng: startCoord.longitude,
                    stops: stopsData
                )
                onSaved()
                dismiss()
            } catch { errorMsg = error.localizedDescription }
            saving = false
        }
    }
}

// MARK: - Shared Empty Route View

struct RouteEmptyView: View {
    let regionName: String?
    let nextReadyDate: Date?
    let nextReadyCount: Int

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(Color(hex: "2d6a4f"))
            Text("All caught up!")
                .font(.custom("Syne-ExtraBold", size: 24))
                .foregroundColor(Color(hex: "0f1117"))

            if let name = regionName {
                Text("No locations in \(name) have reached container capacity.")
                    .font(.custom("DMSans-Regular", size: 14))
                    .foregroundColor(Color(hex: "7a7f94"))
                    .multilineTextAlignment(.center).lineSpacing(4)
            } else {
                Text("No locations have reached container capacity.\nAll containers are below 50 gallons.")
                    .font(.custom("DMSans-Regular", size: 14))
                    .foregroundColor(Color(hex: "7a7f94"))
                    .multilineTextAlignment(.center).lineSpacing(4)
            }

            if let date = nextReadyDate {
                VStack(spacing: 8) {
                    Divider().padding(.horizontal, 60)
                    HStack(spacing: 8) {
                        Image(systemName: "calendar.badge.clock").font(.system(size: 18)).foregroundColor(Color(hex: "c8893a"))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Next collection trip").font(.custom("DMSans-SemiBold", size: 13)).foregroundColor(Color(hex: "0f1117"))
                            let fmt = DateFormatter(); let _ = fmt.dateFormat = "EEEE, MMM d"
                            Text("\(fmt.string(from: date)) — \(nextReadyCount) location\(nextReadyCount == 1 ? "" : "s") will be ready")
                                .font(.custom("DMSans-Regular", size: 13))
                                .foregroundColor(Color(hex: "7a7f94"))
                        }
                    }
                    .padding(16).background(Color.white).cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
                }
                .padding(.horizontal, 32)
            }
            Spacer()
        }
        .padding()
    }
}

// MARK: - Stop Row

struct StopRow: View {
    let stop: RouteStop
    var onBusinessTap: ((Int) -> Void)? = nil

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(badgeColor).frame(width: 32, height: 32)
                Text("\(stop.stopNumber)").font(.custom("Syne-Bold", size: 14)).foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                Button(action: { onBusinessTap?(stop.candidate.business_id) }) {
                    Text(stop.candidate.business_name ?? "Unknown")
                        .font(.custom("DMSans-SemiBold", size: 15)).foregroundColor(Color(hex: "c8893a")).lineLimit(1)
                        .underline()
                }
                .buttonStyle(.plain)
                if !stop.addressLine.isEmpty {
                    Text(stop.addressLine).font(.custom("DMSans-Regular", size: 12)).foregroundColor(Color(hex: "7a7f94")).lineLimit(1)
                }
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        fillGauge
                        Text("\(Int(stop.fillLevel))/\(Int(routeContainerCapacity))g")
                            .font(.custom("DMSans-SemiBold", size: 11)).foregroundColor(fillColor)
                    }
                    Label("\(stop.daysSincePickup)d ago", systemImage: "clock")
                        .font(.custom("DMSans-Regular", size: 11)).foregroundColor(Color(hex: "7a7f94"))
                    Label("\(stop.estimatedGallons)g/wk", systemImage: "arrow.up.right")
                        .font(.custom("DMSans-Regular", size: 11)).foregroundColor(Color(hex: "7a7f94"))
                }
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }

    private var fillGauge: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3).fill(Color(hex: "e2dfd6")).frame(width: 32, height: 6)
            RoundedRectangle(cornerRadius: 3).fill(fillColor)
                .frame(width: min(32, 32 * CGFloat(stop.fillPercent)), height: 6)
        }
    }
    private var fillColor: Color {
        if stop.fillPercent >= 1.5 { return Color(hex: "c1121f") }
        if stop.fillPercent >= 1.0 { return Color(hex: "c8893a") }
        if stop.fillPercent >= 0.75 { return Color(hex: "e8a84e") }
        return Color(hex: "2d6a4f")
    }
    private var badgeColor: Color {
        if stop.fillPercent >= 1.5 { return Color(hex: "c1121f") }
        if stop.fillPercent >= 1.0 { return Color(hex: "c8893a") }
        return Color(hex: "2d6a4f")
    }
}

// MARK: - Business Detail Loading View

struct BusinessDetailLoadingView: View {
    let businessId: Int

    @State private var business: Business?
    @State private var regions: [Region] = []
    @State private var loading = true
    @State private var errorMsg = ""

    var body: some View {
        Group {
            if loading {
                VStack {
                    Spacer()
                    ProgressView("Loading business…")
                        .font(.custom("DMSans-Regular", size: 14))
                    Spacer()
                }
            } else if let business = business {
                BusinessDetailView(
                    business: business,
                    regions: regions,
                    canManageRegions: false,
                    onUpdate: { Task { await loadData() } }
                )
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(Color(hex: "c1121f"))
                    Text(errorMsg.isEmpty ? "Business not found" : errorMsg)
                        .font(.custom("DMSans-Regular", size: 14))
                        .foregroundColor(Color(hex: "3a3d4a"))
                    Spacer()
                }
            }
        }
        .task { await loadData() }
    }

    private func loadData() async {
        loading = true
        do {
            async let bizReq = APIClient.shared.getBusiness(id: businessId)
            async let regReq = APIClient.shared.getRegions()
            business = try await bizReq
            regions = try await regReq
        } catch {
            errorMsg = error.localizedDescription
        }
        loading = false
    }
}

// MARK: - Location Helper

class LocationHelper: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var lastLocation: CLLocation?
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastLocation = locations.last
        manager.stopUpdatingLocation()
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { }
}

#Preview {
    NavigationStack { RoutePlannerView() }.environmentObject(AuthManager())
}
