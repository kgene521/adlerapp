// /AdlerCRM/Views/CustomRouteView.swift  17/04/2026 02:08:00 EDT
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
    @ObservedObject private var travelManager = RouteTravelManager.shared

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

    // Unsaved changes
    @State private var showUnsavedAlert = false
    @State private var pendingAction: PendingAction?
    @State private var showRenameSheet = false
    @State private var showRecurrenceSheet = false
    @State private var savingDirect = false
    // Recurrence tracking for current route
    @State private var currentRecurrenceStart: String?
    @State private var currentRecurrenceInterval: Int?
    @State private var currentRecurrenceUnit: String?

    enum PendingAction {
        case clear
        case loadRoute
    }

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

                        // Save bar (visible when stops exist)
                        if !stops.isEmpty {
                            saveBar
                        }

                        // Stops list
                        if stops.isEmpty {
                            emptyState
                        } else {
                            stopsSection
                        }
                    }
                }
            }
            // Travel controls
            if !stops.isEmpty {
                RouteTravelBar(
                    routeName: currentRouteName.isEmpty ? "Custom Route" : currentRouteName,
                    routeId: currentRouteId,
                    totalStops: stops.count,
                    onStopNavigate: nil
                )
            }
        }
        .background(Color.theme.background)
        .navigationTitle(navTitle)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    Button(action: { guardUnsaved(.loadRoute) { showLoadRoutes = true } }) {
                        Image(systemName: "folder")
                            .font(.system(size: 14))
                            .foregroundColor(Color.theme.textSecondary)
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
                        Button(action: { guardUnsaved(.clear) { clearRoute() } }) {
                            Text("Clear")
                                .font(.custom("DMSans-Medium", size: 12))
                                .foregroundColor(Color(hex: "c1121f"))
                        }
                    }
                }
            }
        }
        .task { await loadData(); await travelManager.syncWithServer() }
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
            CustomStopDetailSheet(stop: stop, startCoord: startCoord, stopIndex: stops.firstIndex(where: { $0.id == stop.id }) ?? 0)
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
        .sheet(isPresented: $showRenameSheet) {
            RouteRenameSheet(currentName: currentRouteName) { newName in
                guard let routeId = currentRouteId else { return }
                Task {
                    do {
                        let saved = try await APIClient.shared.updateRoute(
                            id: routeId, name: newName, startName: currentStartName,
                            startLat: startCoord.latitude, startLng: startCoord.longitude,
                            stops: customStopsData
                        )
                        currentRouteId = saved.id
                        currentRouteName = saved.name
                        originalStops = stops
                        isDirty = false
                    } catch { }
                }
            }
        }
        .sheet(isPresented: $showRecurrenceSheet) {
            RouteRecurrenceSheet(
                routeId: currentRouteId,
                routeName: currentRouteName.isEmpty ? "New Route" : currentRouteName,
                currentStart: currentRecurrenceStart,
                currentInterval: currentRecurrenceInterval,
                currentUnit: currentRecurrenceUnit
            ) { rStart, rInterval, rUnit in
                currentRecurrenceStart = rStart
                currentRecurrenceInterval = rInterval
                currentRecurrenceUnit = rUnit
                isDirty = true
            }
        }
        .alert("Unsaved changes", isPresented: $showUnsavedAlert) {
            Button("Save", role: nil) {
                showSaveRoute = true
            }
            Button("Don't Save", role: .destructive) {
                executePendingAction()
            }
            Button("Cancel", role: .cancel) {
                pendingAction = nil
            }
        } message: {
            Text("Your route has unsaved changes. What would you like to do?")
        }
    }

    // MARK: - Unsaved Changes Guard

    private func guardUnsaved(_ action: PendingAction, otherwise perform: () -> Void) {
        if isDirty {
            pendingAction = action
            showUnsavedAlert = true
        } else {
            perform()
        }
    }

    private func executePendingAction() {
        switch pendingAction {
        case .clear:
            clearRoute()
        case .loadRoute:
            showLoadRoutes = true
        case .none:
            break
        }
        pendingAction = nil
    }

    private func clearRoute() {
        stops.removeAll()
        originalStops.removeAll()
        cameraPosition = .automatic
        currentRouteId = nil
        currentRouteName = ""
        isDirty = false
        currentRecurrenceStart = nil
        currentRecurrenceInterval = nil
        currentRecurrenceUnit = nil
    }

    private func handleSave() {
        if currentRouteId != nil {
            directSave()
        } else {
            showSaveRoute = true
        }
    }

    private var customStopsData: [[String: Any]] {
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

    private func directSave() {
        guard let routeId = currentRouteId else { return }
        savingDirect = true
        Task {
            do {
                let saved = try await APIClient.shared.updateRoute(
                    id: routeId, name: currentRouteName, startName: currentStartName,
                    startLat: startCoord.latitude, startLng: startCoord.longitude,
                    stops: customStopsData,
                    recurrenceStart: currentRecurrenceStart, recurrenceInterval: currentRecurrenceInterval, recurrenceUnit: currentRecurrenceUnit
                )
                currentRouteId = saved.id
                currentRouteName = saved.name
                originalStops = stops
                isDirty = false
            } catch { }
            savingDirect = false
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
                        .foregroundColor(Color.theme.textSecondary)
                        .tracking(0.4)
                    Text(currentStartName)
                        .font(.custom("DMSans-SemiBold", size: 13))
                        .foregroundColor(Color.theme.text)
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
        .background(Color.theme.surface)
        .overlay(Rectangle().fill(Color.theme.border).frame(height: 1), alignment: .bottom)
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

    // MARK: - Save Bar

    private var saveBar: some View {
        HStack {
            // Route info
            VStack(alignment: .leading, spacing: 2) {
                if !currentRouteName.isEmpty {
                    Text(currentRouteName)
                        .font(.custom("DMSans-SemiBold", size: 13))
                        .foregroundColor(Color.theme.text)
                        .lineLimit(1)
                } else {
                    Text("Unsaved route")
                        .font(.custom("DMSans-Medium", size: 13))
                        .foregroundColor(Color.theme.textSecondary)
                }
                if isDirty {
                    Text("Modified — tap Save")
                        .font(.custom("DMSans-Regular", size: 11))
                        .foregroundColor(Color(hex: "c1121f"))
                }
                if currentRecurrenceUnit != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "repeat")
                            .font(.system(size: 9))
                        Text(recurrenceLabel)
                            .font(.custom("DMSans-Regular", size: 11))
                    }
                    .foregroundColor(Color(hex: "2d6a4f"))
                }
            }

            Spacer()

            // Repeat button
            Button(action: { showRecurrenceSheet = true }) {
                Image(systemName: currentRecurrenceUnit != nil ? "repeat.circle.fill" : "repeat")
                    .font(.system(size: 16))
                    .foregroundColor(currentRecurrenceUnit != nil ? Color(hex: "2d6a4f") : Color.theme.textSecondary)
            }

            Spacer()

            // Save As button
            if currentRouteId != nil {
                Button(action: { showRenameSheet = true }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 16))
                        .foregroundColor(Color.theme.textSecondary)
                }
            }

            Spacer()

            // Save button
            Button(action: { handleSave() }) {
                Group {
                    if savingDirect {
                        ProgressView().scaleEffect(0.7).tint(.white)
                    } else {
                        Image(systemName: "tray.and.arrow.down.fill")
                            .font(.system(size: 16))
                    }
                }
                .frame(width: 36, height: 36)
                .foregroundColor(.white)
                .background(isDirty ? Color(hex: "c1121f") : Color(hex: "2d6a4f"))
                .cornerRadius(8)
            }
            .disabled(savingDirect)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isDirty ? Color(hex: "c1121f").opacity(0.06) : Color.theme.surface)
        .overlay(Rectangle().fill(isDirty ? Color(hex: "c1121f").opacity(0.3) : Color.theme.border).frame(height: 1), alignment: .top)
        .overlay(Rectangle().fill(isDirty ? Color(hex: "c1121f").opacity(0.3) : Color.theme.border).frame(height: 1), alignment: .bottom)
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
                Label(String(format: "%.0f mi total", totalMiles), systemImage: "road.lanes")
                    .font(.custom("DMSans-SemiBold", size: 12))
                    .foregroundColor(Color.theme.textSecondary)
                Text("·").foregroundColor(Color.theme.border)
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
            .background(Color.theme.background)
        }
    }

    // MARK: - Stops Section

    private var stopsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("STOPS")
                    .font(.custom("DMSans-SemiBold", size: 9))
                    .foregroundColor(Color.theme.textSecondary)
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
                    .foregroundColor(Color.theme.border)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            List {
                ForEach(Array(stops.enumerated()), id: \.element.id) { idx, stop in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(travelManager.isTraveling && travelManager.isStopVisited(idx) ? Color(hex: "2d6a4f") : Color(hex: "c8893a")).frame(width: 28, height: 28)
                            if travelManager.isTraveling && travelManager.isStopVisited(idx) {
                                Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                            } else {
                                Text("\(idx + 1)").font(.custom("Syne-Bold", size: 12)).foregroundColor(.white)
                            }
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(stop.name)
                                .font(.custom("DMSans-SemiBold", size: 14))
                                .foregroundColor(Color.theme.text)
                                .lineLimit(1)
                            Text(stop.address)
                                .font(.custom("DMSans-Regular", size: 12))
                                .foregroundColor(Color.theme.textSecondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        let dist = distanceFromPrevious(index: idx)
                        if dist > 0 {
                            Text(String(format: "%.0f mi", dist))
                                .font(.custom("DMSans-Regular", size: 11))
                                .foregroundColor(Color.theme.textSecondary)
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
                        Circle().fill(Color.theme.text).frame(width: 28, height: 28)
                        Image(systemName: "house.fill").font(.system(size: 10)).foregroundColor(.white)
                    }
                    Text("Return to start")
                        .font(.custom("DMSans-Regular", size: 13))
                        .foregroundColor(Color.theme.textSecondary)
                        .italic()
                    Spacer()
                    if let last = stops.last {
                        let dist = RouteEngine.haversine(from: last.coordinate, to: startCoord) / 1609.344
                        Text(String(format: "%.0f mi", dist))
                            .font(.custom("DMSans-Regular", size: 11))
                            .foregroundColor(Color.theme.textSecondary)
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.theme.background)
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
                .foregroundColor(Color.theme.border)
            Text("Build Your Route")
                .font(.custom("Syne-Bold", size: 20))
                .foregroundColor(Color.theme.text)
            Text("Add businesses from your list or enter any address to create a custom collection route.")
                .font(.custom("DMSans-Regular", size: 14))
                .foregroundColor(Color.theme.textSecondary)
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
                let label = String(format: "%.0f mi", distMiles)
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

        // Restore recurrence
        currentRecurrenceStart = saved.recurrence_start
        currentRecurrenceInterval = saved.recurrence_interval
        currentRecurrenceUnit = saved.recurrence_unit
    }

    private var recurrenceLabel: String {
        guard let unit = currentRecurrenceUnit, let interval = currentRecurrenceInterval else { return "" }
        let u: String
        switch unit {
        case "day": u = interval == 1 ? "day" : "days"
        case "week": u = interval == 1 ? "week" : "weeks"
        case "month": u = interval == 1 ? "month" : "months"
        default: u = unit
        }
        return interval == 1 ? "Every \(u)" : "Every \(interval) \(u)"
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
                .background(Color.theme.background)

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
            FlowLayout(spacing: 8) {
                ForEach(regionNames, id: \.id) { region in
                    Button(action: { filterRegion = region.id }) {
                        Text(region.name)
                            .font(.custom("DMSans-SemiBold", size: 12))
                            .foregroundColor(filterRegion == region.id ? .white : Color.theme.text)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(filterRegion == region.id ? Color(hex: "c8893a") : Color.theme.surface)
                            .cornerRadius(50)
                            .overlay(RoundedRectangle(cornerRadius: 50).stroke(filterRegion == region.id ? Color.clear : Color.theme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                Toggle(isOn: $showInactive) {
                    Text("Inactive")
                        .font(.custom("DMSans-Medium", size: 11))
                        .foregroundColor(Color.theme.textSecondary)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(Color(hex: "c8893a"))
                .fixedSize()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.theme.background.opacity(0.5))

            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundColor(Color.theme.textSecondary)
                TextField("Search by name, address, or city", text: $searchText)
                    .font(.custom("DMSans-Regular", size: 14))
                    .foregroundColor(Color.theme.text)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Color.theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color.theme.surface)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.theme.border, lineWidth: 1))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // Results count
            HStack {
                Text("\(filteredLocations.count) location\(filteredLocations.count == 1 ? "" : "s")")
                    .font(.custom("DMSans-Regular", size: 11))
                    .foregroundColor(Color.theme.textSecondary)
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
                                    .foregroundColor(Color.theme.text)
                                    .lineLimit(1)
                                let addr = [loc.address, loc.city, loc.state]
                                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
                                if !addr.isEmpty {
                                    Text(addr)
                                        .font(.custom("DMSans-Regular", size: 12))
                                        .foregroundColor(Color.theme.textSecondary)
                                        .lineLimit(1)
                                }
                            }

                            Spacer()

                            if loc.is_deleted == true {
                                Text("Inactive")
                                    .font(.custom("DMSans-SemiBold", size: 9))
                                    .foregroundColor(Color.theme.textSecondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.theme.border)
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
                        .background(Color.theme.red.opacity(0.08))
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
                    Rectangle().fill(Color.theme.border).frame(height: 1)
                    Text("or enter coordinates")
                        .font(.custom("DMSans-Regular", size: 11))
                        .foregroundColor(Color.theme.textSecondary)
                        .layoutPriority(1)
                    Rectangle().fill(Color.theme.border).frame(height: 1)
                }
                .padding(.vertical, 4)

                HStack(spacing: 10) {
                    manualField(label: "Latitude", text: $manualLat, placeholder: "e.g. 37.2710", keyboard: .numbersAndPunctuation)
                    manualField(label: "Longitude", text: $manualLng, placeholder: "e.g. -79.9414", keyboard: .numbersAndPunctuation)
                }
                .coordinatePaste(latitude: $manualLat, longitude: $manualLng)

                Text("Provide either a full address (street, city, state) or coordinates. If both are provided, coordinates take priority.")
                    .font(.custom("DMSans-Regular", size: 11))
                    .foregroundColor(Color.theme.textSecondary)
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
                    .background(manualCanAdd && !geocoding ? Color(hex: "2d6a4f") : Color.theme.textSecondary)
                    .cornerRadius(12)
                }
                .disabled(!manualCanAdd || geocoding)
            }
            .padding(20)
        }
        .background(Color.theme.background)
    }

    // MARK: - Helpers

    private func manualField(label: String, text: Binding<String>, placeholder: String, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.custom("DMSans-SemiBold", size: 9))
                .foregroundColor(Color.theme.textSecondary)
                .tracking(0.4)
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .font(.custom("DMSans-Regular", size: 14))
                .padding(12)
                .background(Color.theme.surface)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.theme.border, lineWidth: 1))
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
    var stopIndex: Int = 0
    @Environment(\.dismiss) var dismiss
    @State private var copiedFeedback = false

    private var distanceMiles: Double {
        RouteEngine.haversine(from: startCoord, to: stop.coordinate) / 1609.344
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Navigate button (travel-aware)
                    NavigateAndVisitButton(
                        coordinate: stop.coordinate,
                        name: stop.name,
                        stopIndex: stopIndex
                    )

                    // Header
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stop.name)
                            .font(.custom("Syne-Bold", size: 18))
                            .foregroundColor(Color.theme.text)
                        Text(stop.address)
                            .font(.custom("DMSans-Regular", size: 14))
                            .foregroundColor(Color.theme.textSecondary)
                    }

                    Divider()

                    // Distance
                    HStack(spacing: 10) {
                        Image(systemName: "road.lanes")
                            .font(.system(size: 14))
                            .foregroundColor(Color.theme.textSecondary)
                            .frame(width: 20)
                        Text(String(format: "%.0f miles from start", distanceMiles))
                            .font(.custom("DMSans-Regular", size: 13))
                            .foregroundColor(Color.theme.textSecondary)
                    }

                    Divider()

                    // Coordinates
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("COORDINATES")
                                .font(.custom("DMSans-SemiBold", size: 9))
                                .foregroundColor(Color.theme.textSecondary)
                                .tracking(0.5)
                            Text(coordString)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(Color.theme.text)
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
                            .foregroundColor(copiedFeedback ? Color(hex: "2d6a4f") : Color.theme.text)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.theme.background)
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.theme.border, lineWidth: 1))
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
    @State private var makeRecurring = false
    @State private var recurrenceStart = Date()
    @State private var recurrenceInterval = 1
    @State private var recurrenceUnit = "week"

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
                            .background(Color.theme.red.opacity(0.08))
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
                        .foregroundColor(Color.theme.textSecondary)
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
                    .foregroundColor(Color.theme.textSecondary)
                    .tracking(0.4)
                TextField("e.g. Monday Roanoke Run", text: $routeName)
                    .font(.custom("DMSans-Regular", size: 14))
                    .padding(12)
                    .background(Color.theme.surface)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.theme.border, lineWidth: 1))
            }

            // Recurrence toggle
            Toggle(isOn: $makeRecurring) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Make recurring")
                        .font(.custom("DMSans-SemiBold", size: 14))
                        .foregroundColor(Color.theme.text)
                    Text("Repeat this route on a schedule")
                        .font(.custom("DMSans-Regular", size: 12))
                        .foregroundColor(Color.theme.textSecondary)
                }
            }
            .tint(Color(hex: "c8893a"))

            if makeRecurring {
                VStack(alignment: .leading, spacing: 12) {
                    DatePicker("Start Date", selection: $recurrenceStart, displayedComponents: .date)
                        .font(.custom("DMSans-Medium", size: 14))
                        .tint(Color(hex: "c8893a"))

                    HStack(spacing: 12) {
                        Text("Every")
                            .font(.custom("DMSans-Medium", size: 14))
                            .foregroundColor(Color.theme.text)
                        Picker("Interval", selection: $recurrenceInterval) {
                            ForEach(1..<31) { n in Text("\(n)").tag(n) }
                        }
                        .pickerStyle(.menu)
                        .tint(Color(hex: "c8893a"))
                        Picker("Unit", selection: $recurrenceUnit) {
                            Text("Days").tag("day")
                            Text("Weeks").tag("week")
                            Text("Months").tag("month")
                        }
                        .pickerStyle(.menu)
                        .tint(Color(hex: "c8893a"))
                    }
                }
                .padding(14).background(Color.theme.surface).cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.theme.border, lineWidth: 1))
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
                        .foregroundColor(Color.theme.textSecondary)
                        .tracking(0.4)
                    Text(existingRouteName)
                        .font(.custom("DMSans-SemiBold", size: 15))
                        .foregroundColor(Color.theme.text)
                }
                Spacer()
            }
            .padding(14)
            .background(Color.theme.background)
            .cornerRadius(10)

            // Save (overwrite)
            Button(action: saveOverwrite) {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.down").font(.system(size: 16))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Save").font(.custom("DMSans-SemiBold", size: 15))
                        Text("Update \"\(existingRouteName)\" with current stops")
                            .font(.custom("DMSans-Regular", size: 11))
                            .foregroundColor(Color.theme.textSecondary)
                    }
                    Spacer()
                    if saving { ProgressView().scaleEffect(0.8) }
                }
                .foregroundColor(Color.theme.text)
                .padding(16)
                .background(Color.theme.surface)
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
                    .foregroundColor(Color.theme.textSecondary)
                    .tracking(0.4)
                TextField("New name", text: $routeName)
                    .font(.custom("DMSans-Regular", size: 14))
                    .padding(12)
                    .background(Color.theme.surface)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.theme.border, lineWidth: 1))

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
                    .foregroundColor(Color.theme.textSecondary)
                    .tracking(0.4)
                Text("Creates a new saved route with the stops below.")
                    .font(.custom("DMSans-Regular", size: 12))
                    .foregroundColor(Color.theme.textSecondary)

                Button(action: saveAsCopy) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.on.doc").font(.system(size: 14))
                        Text("Save as Copy").font(.custom("DMSans-SemiBold", size: 14))
                    }
                    .foregroundColor(Color.theme.text)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.theme.surface)
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.theme.border, lineWidth: 1))
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
                .foregroundColor(Color.theme.textSecondary)
                .tracking(0.4)

            HStack(spacing: 16) {
                Label("\(stops.count) stops", systemImage: "mappin.circle.fill")
                    .font(.custom("DMSans-Medium", size: 13))
                    .foregroundColor(Color(hex: "2d6a4f"))
                Label("from \(startName)", systemImage: "house.fill")
                    .font(.custom("DMSans-Medium", size: 13))
                    .foregroundColor(Color.theme.textSecondary)
            }

            ForEach(Array(stops.enumerated()), id: \.element.id) { idx, stop in
                HStack(spacing: 8) {
                    Text("\(idx + 1).")
                        .font(.custom("DMSans-SemiBold", size: 12))
                        .foregroundColor(Color(hex: "c8893a"))
                        .frame(width: 20, alignment: .trailing)
                    Text(stop.name)
                        .font(.custom("DMSans-Regular", size: 13))
                        .foregroundColor(Color.theme.text)
                        .lineLimit(1)
                }
            }
        }
        .padding(16)
        .background(Color.theme.background)
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
        let rStart = makeRecurring ? recurrenceStart.formatted(.iso8601).prefix(10).description : nil
        let rInterval = makeRecurring ? recurrenceInterval : nil
        let rUnit = makeRecurring ? recurrenceUnit : nil
        Task {
            do {
                let saved = try await APIClient.shared.createRoute(
                    name: trimmed, startName: startName,
                    startLat: startCoord.latitude, startLng: startCoord.longitude,
                    stops: stopsData,
                    recurrenceStart: rStart, recurrenceInterval: rInterval, recurrenceUnit: rUnit
                )
                try await APIClient.shared.saveRouteToCollection(routeId: saved.id)
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
                let saved = try await APIClient.shared.updateRoute(
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
                let saved = try await APIClient.shared.updateRoute(
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
                let saved = try await APIClient.shared.createRoute(
                    name: copyName, startName: startName,
                    startLat: startCoord.latitude, startLng: startCoord.longitude,
                    stops: stopsData
                )
                try await APIClient.shared.saveRouteToCollection(routeId: saved.id)
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
    @State private var showDeleteConfirm = false
    @State private var routeToDelete: SavedRoute?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
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
                            .foregroundColor(Color.theme.border)
                        Text("No saved routes")
                            .font(.custom("DMSans-SemiBold", size: 16))
                            .foregroundColor(Color.theme.textSecondary)
                        Text("Build a custom route and tap the save icon to save it here.")
                            .font(.custom("DMSans-Regular", size: 13))
                            .foregroundColor(Color.theme.textSecondary)
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
                                            .foregroundColor(Color.theme.text)
                                            .lineLimit(1)

                                        HStack(spacing: 10) {
                                            Label("\(route.stops?.count ?? 0) stops", systemImage: "mappin.circle.fill")
                                                .font(.custom("DMSans-Regular", size: 11))
                                                .foregroundColor(Color(hex: "2d6a4f"))

                                            if let startName = route.start_name {
                                                Label(startName, systemImage: "house.fill")
                                                    .font(.custom("DMSans-Regular", size: 11))
                                                    .foregroundColor(Color.theme.textSecondary)
                                                    .lineLimit(1)
                                            }
                                        }

                                        HStack(spacing: 10) {
                                            Label(formatDate(route.created_at), systemImage: "clock")
                                                .font(.custom("DMSans-Regular", size: 11))
                                                .foregroundColor(Color.theme.textSecondary)

                                            if let creatorName = route.created_by_name {
                                                Label(creatorName, systemImage: "person.fill")
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

    // MARK: - Actions

    private func fetchRoutes() async {
        loading = true
        do {
            routes = try await APIClient.shared.getSavedRoutesList(search: searchText)
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
                _ = try await APIClient.shared.unsaveRoute(id: route.id)
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
                        Circle().fill(Color.theme.text).frame(width: 28, height: 28)
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

                    // Distance labels at midpoints between stops
                    ForEach(0..<(coords.count - 1), id: \.self) { i in
                        let mid = CLLocationCoordinate2D(
                            latitude: (coords[i].latitude + coords[i + 1].latitude) / 2,
                            longitude: (coords[i].longitude + coords[i + 1].longitude) / 2
                        )
                        let dist = RouteEngine.haversine(from: coords[i], to: coords[i + 1]) / 1609.344
                        Annotation("", coordinate: mid) {
                            Text(String(format: "%.0f mi", dist))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(4)
                        }
                    }
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
                    Label(String(format: "%.0f mi", totalMiles), systemImage: "road.lanes")
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

// MARK: - Flow Layout (wrapping)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview {
    NavigationStack { CustomRouteView() }.environmentObject(AuthManager())
}
