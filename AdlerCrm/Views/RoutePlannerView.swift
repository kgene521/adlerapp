// /AdlerCRM/Views/RoutePlannerView.swift  17/04/2026 02:08:00 EDT
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
    @EnvironmentObject var auth: AuthManager
    @StateObject private var locationManager = LocationHelper()
    @ObservedObject private var travelManager = RouteTravelManager.shared
    @State private var route: [RouteStop] = []
    @State private var originalRoute: [RouteStop] = []
    @State private var loading = true
    @State private var errorMsg = ""
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isDirty = false

    // Route mode: 0 = Assigned, 1 = Manual, 2 = Saved
    @State private var routeMode = 0

    // Starting location
    @State private var selectedStartId: String = "current"
    @State private var startCoord: CLLocationCoordinate2D = defaultStartCoord
    @State private var showStartPicker = false

    // Collapse
    @State private var showControls = false
    @State private var showSaveSheet = false
    @State private var showTodayTasks = false

    // Assigned mode
    @State private var assignedRoutes: [SavedRoute] = []
    @State private var selectedAssignedRoute: SavedRoute?

    // Manual mode
    @State private var manualBusinesses: [Business] = []
    @State private var manualLocations: [Location] = []
    @State private var manualStops: [CustomStop] = []
    @State private var showAddStop = false
    @State private var manualLoading = false

    // Saved mode
    @State private var showLoadRoutes = false
    @State private var loadedRouteName: String = ""
    @State private var currentRouteId: Int?

    // Unsaved changes
    @State private var showUnsavedAlert = false
    @State private var pendingAction: PendingAction?
    @State private var showRenameSheet = false
    @State private var showRecurrenceSheet = false
    @State private var savingDirect = false
    @State private var currentRecurrenceStart: String?
    @State private var currentRecurrenceInterval: Int?
    @State private var currentRecurrenceUnit: String?

    enum PendingAction {
        case switchMode(Int)
        case loadRoute
    }

    private var isAdmin: Bool { auth.currentUser?.role == "Administrator" }

    private var travelRouteName: String {
        if routeMode == 0, let ar = selectedAssignedRoute { return ar.name }
        if !loadedRouteName.isEmpty { return loadedRouteName }
        return "Manual Route"
    }
    private var travelRouteId: Int? {
        if routeMode == 0, let ar = selectedAssignedRoute { return ar.id }
        return currentRouteId
    }
    private var travelStopCount: Int {
        route.count
    }

    private var manualExistingIds: Set<Int> {
        Set(manualStops.compactMap { stop in
            if case .business(_, let locId) = stop.source { return locId }
            return nil
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            // Mode picker
            Picker("Route Mode", selection: $routeMode) {
                Text("Assigned").tag(0)
                Text("Manual").tag(1)
                Text("Saved").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.theme.background)
            .overlay(Rectangle().fill(Color.theme.border).frame(height: 1), alignment: .bottom)

            // Mode content
            switch routeMode {
            case 0: assignedModeContent
            case 1: manualModeContent
            case 2: savedModeContent
            default: EmptyView()
            }

            // Travel controls
            if !route.isEmpty {
                RouteTravelBar(routeName: travelRouteName, routeId: travelRouteId, totalStops: travelStopCount, onStopNavigate: nil)
            }
        }
        .navigationTitle("Today's Route")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 14) {
                    Button(action: { showTodayTasks = true }) {
                        Image(systemName: "checklist")
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "c8893a"))
                    }
                    if routeMode == 0 {
                        Button(action: { Task { await loadAssigned() } }) {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(Color.theme.textSecondary)
                        }
                    }
                }
            }
        }
        .task { resolveStartCoord(); await loadAssigned(); await travelManager.syncWithServer() }
        .onChange(of: routeMode) { oldMode, newMode in
            if isDirty {
                routeMode = oldMode
                pendingAction = .switchMode(newMode)
                showUnsavedAlert = true
            } else {
                applyModeSwitch(newMode)
            }
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
            RouteSaveAssignSheet(
                route: route,
                startName: currentStartName,
                startCoord: startCoord,
                isAdmin: isAdmin,
                currentUserId: auth.currentUser?.id ?? 0,
                onSaved: { id, name in
                    currentRouteId = id
                    loadedRouteName = name
                    originalRoute = route
                    isDirty = false
                }
            )
        }
        .sheet(isPresented: $showTodayTasks) {
            TodayTasksSheet()
        }
        .sheet(isPresented: $showAddStop) {
            AddStopSheet(
                businesses: manualBusinesses,
                locations: manualLocations,
                existingStopIds: manualExistingIds,
                onAdd: { stop in
                    manualStops.append(stop)
                    route = manualStopsToRoute()
                    originalRoute = route
                    cameraPosition = .automatic
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showLoadRoutes) {
            LoadRoutesSheet(
                isAdmin: isAdmin,
                onLoad: { savedRoute in
                    loadSavedRoute(savedRoute)
                }
            )
        }
        .sheet(isPresented: $showRenameSheet) {
            RouteRenameSheet(currentName: loadedRouteName) { newName in
                guard let routeId = currentRouteId else { return }
                Task {
                    do {
                        let saved = try await APIClient.shared.updateRoute(
                            id: routeId, name: newName, startName: currentStartName,
                            startLat: startCoord.latitude, startLng: startCoord.longitude,
                            stops: routeStopsData
                        )
                        currentRouteId = saved.id
                        loadedRouteName = saved.name
                        originalRoute = route
                        isDirty = false
                    } catch { }
                }
            }
        }
        .sheet(isPresented: $showRecurrenceSheet) {
            RouteRecurrenceSheet(
                routeId: currentRouteId,
                routeName: loadedRouteName.isEmpty ? "New Route" : loadedRouteName,
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
                showSaveSheet = true
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

    private func applyModeSwitch(_ newMode: Int) {
        route = []; originalRoute = []; isDirty = false; cameraPosition = .automatic
        selectedAssignedRoute = nil; loadedRouteName = ""; currentRouteId = nil
        currentRecurrenceStart = nil; currentRecurrenceInterval = nil; currentRecurrenceUnit = nil
        switch newMode {
        case 0: Task { await loadAssigned() }
        case 1: Task { await loadManualData() }
        case 2: showLoadRoutes = true
        default: break
        }
    }

    private func executePendingAction() {
        switch pendingAction {
        case .switchMode(let mode):
            routeMode = mode
            applyModeSwitch(mode)
        case .loadRoute:
            showLoadRoutes = true
        case .none:
            break
        }
        pendingAction = nil
    }

    private func handleSave() {
        if currentRouteId != nil {
            directSave()
        } else {
            showSaveSheet = true
        }
    }

    private var routeStopsData: [[String: Any]] {
        route.map { stop in
            [
                "name": stop.candidate.business_name ?? "Unknown",
                "address": stop.addressLine.isEmpty ? "No address" : stop.addressLine,
                "latitude": stop.coordinate.latitude,
                "longitude": stop.coordinate.longitude,
                "source_type": stop.candidate.business_id > 0 ? "business" : "manual",
                "business_id": stop.candidate.business_id,
                "location_id": stop.id
            ] as [String: Any]
        }
    }

    private func directSave() {
        guard let routeId = currentRouteId else { return }
        savingDirect = true
        Task {
            do {
                let saved = try await APIClient.shared.updateRoute(
                    id: routeId, name: loadedRouteName, startName: currentStartName,
                    startLat: startCoord.latitude, startLng: startCoord.longitude,
                    stops: routeStopsData,
                    recurrenceStart: currentRecurrenceStart, recurrenceInterval: currentRecurrenceInterval, recurrenceUnit: currentRecurrenceUnit
                )
                currentRouteId = saved.id
                loadedRouteName = saved.name
                originalRoute = route
                isDirty = false
            } catch { }
            savingDirect = false
        }
    }

    // MARK: - Route Editability

    private var isRouteEditable: Bool {
        guard let ar = selectedAssignedRoute else { return true }
        let userId = auth.currentUser?.id ?? 0
        return ar.assigned_by == userId || ar.created_by == userId || isAdmin
    }

    private func readOnlyBanner(_ ar: SavedRoute) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 12))
            Text("Assigned by \(ar.assigned_by_name ?? "another user"). View only.")
                .font(.custom("DMSans-Medium", size: 12))
        }
        .foregroundColor(Color(hex: "c8893a"))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(hex: "c8893a").opacity(0.06))
        .overlay(Rectangle().fill(Color(hex: "c8893a").opacity(0.2)).frame(height: 1), alignment: .top)
        .overlay(Rectangle().fill(Color(hex: "c8893a").opacity(0.2)).frame(height: 1), alignment: .bottom)
    }

    // MARK: - Save Bar

    private var saveBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if !loadedRouteName.isEmpty {
                    Text(loadedRouteName)
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

            if currentRouteId != nil {
                Button(action: { showRenameSheet = true }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 16))
                        .foregroundColor(Color.theme.textSecondary)
                }
            }

            Spacer()

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

    // MARK: - Assigned Mode

    private var assignedModeContent: some View {
        Group {
            if loading {
                Spacer()
                ProgressView("Loading assigned routes…")
                    .font(.custom("DMSans-Regular", size: 14))
                Spacer()
            } else if !errorMsg.isEmpty {
                errorView
            } else if assignedRoutes.isEmpty && route.isEmpty {
                assignedEmptyView
            } else if let selected = selectedAssignedRoute, !route.isEmpty {
                // Viewing a specific assigned route
                assignedRouteHeader(selected)
                if !isRouteEditable {
                    readOnlyBanner(selected)
                } else {
                    saveBar
                }
                RouteMapListView(
                    route: $route,
                    startCoord: startCoord,
                    regionName: nil,
                    startName: currentStartName,
                    cameraPosition: $cameraPosition,
                    isDirty: $isDirty,
                    showFillData: false,
                    isEditable: isRouteEditable,
                    onReset: {
                        route = originalRoute
                        isDirty = false
                        cameraPosition = .automatic
                    }
                )
            } else {
                // List of assigned routes
                assignedRouteList
            }
        }
    }

    private var assignedEmptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 44))
                .foregroundColor(Color.theme.border)
            Text("No routes assigned for today")
                .font(.custom("Syne-Bold", size: 18))
                .foregroundColor(Color.theme.text)
            Text("Routes assigned to you will appear here.\nUse Manual mode to create a new route.")
                .font(.custom("DMSans-Regular", size: 13))
                .foregroundColor(Color.theme.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(32)
    }

    private var assignedRouteList: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(assignedRoutes) { ar in
                    Button(action: { selectAssignedRoute(ar) }) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(Color(hex: "2d6a4f"))
                                Text(ar.name)
                                    .font(.custom("DMSans-SemiBold", size: 15))
                                    .foregroundColor(Color.theme.text)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(Color.theme.border)
                            }
                            HStack(spacing: 12) {
                                Label("\(ar.stops?.count ?? 0) stops", systemImage: "mappin.circle.fill")
                                    .font(.custom("DMSans-Medium", size: 12))
                                    .foregroundColor(Color(hex: "c8893a"))
                                if let by = ar.assigned_by_name {
                                    Label("by \(by)", systemImage: "person.fill")
                                        .font(.custom("DMSans-Regular", size: 12))
                                        .foregroundColor(Color.theme.textSecondary)
                                }
                            }
                        }
                        .padding(14)
                        .background(Color.theme.surface)
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.theme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .background(Color.theme.background)
    }

    private func assignedRouteHeader(_ ar: SavedRoute) -> some View {
        HStack(spacing: 8) {
            Button(action: {
                selectedAssignedRoute = nil
                route = []; originalRoute = []; isDirty = false; cameraPosition = .automatic
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "c8893a"))
            }
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "2d6a4f"))
            Text(ar.name)
                .font(.custom("DMSans-SemiBold", size: 12))
                .foregroundColor(Color.theme.text)
                .lineLimit(1)
            if let by = ar.assigned_by_name {
                Text("·").foregroundColor(Color.theme.border)
                Text("by \(by)")
                    .font(.custom("DMSans-Regular", size: 12))
                    .foregroundColor(Color.theme.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Color.theme.surface)
        .overlay(Rectangle().fill(Color.theme.border).frame(height: 1), alignment: .bottom)
    }

    // MARK: - Manual Mode

    private var manualModeContent: some View {
        Group {
            if manualLoading {
                Spacer()
                ProgressView("Loading businesses…")
                    .font(.custom("DMSans-Regular", size: 14))
                Spacer()
            } else if route.isEmpty {
                controlBar
                manualAddBar
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "hand.point.up.left.fill")
                        .font(.system(size: 36))
                        .foregroundColor(Color.theme.border)
                    Text("Add stops to build your route")
                        .font(.custom("DMSans-Regular", size: 14))
                        .foregroundColor(Color.theme.textSecondary)
                    Spacer()
                }
            } else {
                compactBar
                if showControls { controlBar }
                manualAddBar
                saveBar
                RouteMapListView(
                    route: $route,
                    startCoord: startCoord,
                    regionName: nil,
                    startName: currentStartName,
                    cameraPosition: $cameraPosition,
                    isDirty: $isDirty,
                    showFillData: false,
                    onReset: {
                        route = originalRoute
                        isDirty = false
                        cameraPosition = .automatic
                    }
                )
            }
        }
    }

    // MARK: - Saved Mode

    private var savedModeContent: some View {
        Group {
            if route.isEmpty {
                controlBar
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "folder")
                        .font(.system(size: 36))
                        .foregroundColor(Color.theme.border)
                    if loadedRouteName.isEmpty {
                        Text("Select a saved route")
                            .font(.custom("DMSans-Regular", size: 14))
                            .foregroundColor(Color.theme.textSecondary)
                    } else {
                        Text("Route has no stops")
                            .font(.custom("DMSans-Regular", size: 14))
                            .foregroundColor(Color.theme.textSecondary)
                    }
                    Button(action: { showLoadRoutes = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 12))
                            Text("Load Route")
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
            } else {
                // Show loaded route name
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "c8893a"))
                    Text(loadedRouteName)
                        .font(.custom("DMSans-SemiBold", size: 12))
                        .foregroundColor(Color.theme.text)
                        .lineLimit(1)
                    Spacer()
                    Button(action: { showLoadRoutes = true }) {
                        Text("Change")
                            .font(.custom("DMSans-Medium", size: 12))
                            .foregroundColor(Color(hex: "c8893a"))
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Color.theme.surface)
                .overlay(Rectangle().fill(Color.theme.border).frame(height: 1), alignment: .bottom)

                if showControls { controlBar }
                saveBar
                RouteMapListView(
                    route: $route,
                    startCoord: startCoord,
                    regionName: nil,
                    startName: currentStartName,
                    cameraPosition: $cameraPosition,
                    isDirty: $isDirty,
                    showFillData: false,
                    onReset: {
                        route = originalRoute
                        isDirty = false
                        cameraPosition = .automatic
                    }
                )
            }
        }
    }

    // MARK: - Manual Add Bar

    private var manualAddBar: some View {
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

            if !manualStops.isEmpty {
                Button(action: {
                    manualStops.removeAll()
                    route = []; originalRoute = []; isDirty = false; cameraPosition = .automatic
                }) {
                    Text("Clear")
                        .font(.custom("DMSans-SemiBold", size: 13))
                        .foregroundColor(Color(hex: "c1121f"))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.theme.surface)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.theme.border, lineWidth: 1))
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Color.theme.background)
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
                    .foregroundColor(Color.theme.text)
                    .lineLimit(1)
                Spacer()
                Image(systemName: showControls ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color.theme.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .background(Color.theme.surface)
        .overlay(Rectangle().fill(Color.theme.border).frame(height: 1), alignment: .bottom)
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
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color.theme.border)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .background(Color.theme.surface)
            .overlay(Rectangle().fill(Color.theme.border).frame(height: 1), alignment: .bottom)
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
                .foregroundColor(Color.theme.text)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await loadAssigned() } }
                .font(.custom("DMSans-SemiBold", size: 14))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(Color.theme.text)
                .cornerRadius(8)
            Spacer()
        }
        .padding()
    }

    // MARK: - Logic

    private func loadAssigned() async {
        loading = true; errorMsg = ""
        let today = Date().formatted(.iso8601).prefix(10)
        do {
            assignedRoutes = try await APIClient.shared.getAssignedRoutes(date: String(today))
        } catch { errorMsg = error.localizedDescription }
        loading = false
    }

    private func selectAssignedRoute(_ ar: SavedRoute) {
        selectedAssignedRoute = ar
        if let sLat = ar.start_lat, let sLng = ar.start_lng {
            startCoord = CLLocationCoordinate2D(latitude: sLat, longitude: sLng)
        }
        guard let stops = ar.stops, !stops.isEmpty else {
            route = []; originalRoute = []; return
        }
        route = stopsToRouteStops(stops)
        originalRoute = route
        isDirty = false
        cameraPosition = .automatic
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
    }

    private var currentStartName: String {
        if selectedStartId == "current" {
            return locationManager.lastLocation != nil ? "Current Location" : "Roanoke, VA (default)"
        }
        return startLocationPresets.first { $0.id == selectedStartId }?.name ?? "Unknown"
    }

    // MARK: - Manual Mode Logic

    private func loadManualData() async {
        manualLoading = true
        do {
            manualBusinesses = try await APIClient.shared.getBusinesses()
            manualLocations = try await APIClient.shared.getAllLocationsIncludingInactive()
        } catch { }
        manualLoading = false
    }

    private func manualStopsToRoute() -> [RouteStop] {
        manualStops.enumerated().map { idx, stop in
            let locId: Int
            let bizId: Int
            if case .business(let bId, let lId) = stop.source {
                bizId = bId; locId = lId
            } else {
                bizId = 0; locId = -(idx + 1)
            }
            let candidate = RouteCandidate(
                id: locId, business_id: bizId,
                address: stop.address, city: nil, state: nil, zip: nil, phone: nil,
                estimated_gallons: nil, pickup_freq: nil,
                latitude: stop.coordinate.latitude, longitude: stop.coordinate.longitude,
                business_name: stop.name, business_status: nil,
                region_id: nil, region_name: nil,
                last_pickup_date: nil, collection_count: nil, total_collected: nil
            )
            return RouteStop(
                id: locId, stopNumber: idx + 1,
                candidate: candidate, coordinate: stop.coordinate,
                fillLevel: 0, fillPercent: 0, daysSincePickup: 0, estimatedGallons: 0
            )
        }
    }

    // MARK: - Saved Route Logic

    private func loadSavedRoute(_ savedRoute: SavedRoute) {
        currentRouteId = savedRoute.id
        loadedRouteName = savedRoute.name

        if let sLat = savedRoute.start_lat, let sLng = savedRoute.start_lng {
            startCoord = CLLocationCoordinate2D(latitude: sLat, longitude: sLng)
            if let preset = startLocationPresets.first(where: { abs($0.coordinate.latitude - sLat) < 0.001 && abs($0.coordinate.longitude - sLng) < 0.001 }) {
                selectedStartId = preset.id
            } else {
                selectedStartId = "saved"
            }
        }

        guard let stops = savedRoute.stops, !stops.isEmpty else {
            route = []; originalRoute = []; return
        }

        route = stopsToRouteStops(stops)
        originalRoute = route
        isDirty = false
        cameraPosition = .automatic

        currentRecurrenceStart = savedRoute.recurrence_start
        currentRecurrenceInterval = savedRoute.recurrence_interval
        currentRecurrenceUnit = savedRoute.recurrence_unit
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

    // MARK: - Shared Helpers

    private func stopsToRouteStops(_ stops: [SavedRouteStop]) -> [RouteStop] {
        stops.enumerated().map { idx, stop in
            let locId = stop.location_id ?? -(idx + 1)
            let bizId = stop.business_id ?? 0
            let candidate = RouteCandidate(
                id: locId, business_id: bizId,
                address: stop.address, city: nil, state: nil, zip: nil, phone: nil,
                estimated_gallons: nil, pickup_freq: nil,
                latitude: stop.latitude, longitude: stop.longitude,
                business_name: stop.name, business_status: nil,
                region_id: nil, region_name: nil,
                last_pickup_date: nil, collection_count: nil, total_collected: nil
            )
            return RouteStop(
                id: locId, stopNumber: idx + 1,
                candidate: candidate,
                coordinate: CLLocationCoordinate2D(latitude: stop.latitude, longitude: stop.longitude),
                fillLevel: 0, fillPercent: 0, daysSincePickup: 0, estimatedGallons: 0
            )
        }
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
                                Text(loc.name).font(.custom("DMSans-SemiBold", size: 15)).foregroundColor(Color.theme.text)
                                Text(startSubtitle(loc)).font(.custom("DMSans-Regular", size: 12)).foregroundColor(Color.theme.textSecondary)
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
                        .foregroundColor(selectedId == option.id ? .white : Color.theme.text)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(selectedId == option.id ? Color(hex: "c8893a") : Color.theme.surface)
                        .cornerRadius(50)
                        .overlay(RoundedRectangle(cornerRadius: 50).stroke(selectedId == option.id ? Color.clear : Color.theme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .background(Color.theme.background)
        .overlay(Rectangle().fill(Color.theme.border).frame(height: 1), alignment: .bottom)
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
    var showFillData: Bool = true
    var isEditable: Bool = true
    var onReset: (() -> Void)? = nil
    @State private var selectedStop: RouteStop?
    @State private var highlightedStopId: Int?
    @State private var showStartDetail = false
    @State private var selectedBusinessId: Int?
    @State private var showMapSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Stats bar with map toggle
            HStack {
                Label("\(route.count) stops", systemImage: "mappin.circle.fill")
                    .font(.custom("DMSans-SemiBold", size: 12))
                    .foregroundColor(Color(hex: "2d6a4f"))
                if isDirty {
                    Text("·").foregroundColor(Color.theme.border)
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
                if showFillData {
                    let totalGal = route.reduce(0) { $0 + $1.fillLevel }
                    Label("~\(Int(totalGal))g", systemImage: "drop.fill")
                        .font(.custom("DMSans-SemiBold", size: 12))
                        .foregroundColor(Color(hex: "c8893a"))
                    Text("·").foregroundColor(Color.theme.border)
                }
                let totalMiles = totalRouteMiles()
                Label(String(format: "%.0f mi", totalMiles), systemImage: "road.lanes")
                    .font(.custom("DMSans-SemiBold", size: 12))
                    .foregroundColor(Color.theme.textSecondary)
                Text("·").foregroundColor(Color.theme.border)
                Button(action: { showMapSheet = true }) {
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

            // Stop list with reorder + scroll-to support
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(route.enumerated()), id: \.element.id) { idx, stop in
                        let dist: Double = {
                            let from = idx == 0 ? startCoord : route[idx - 1].coordinate
                            return RouteEngine.haversine(from: from, to: stop.coordinate) / 1609.344
                        }()
                        StopRow(stop: stop, showFillData: showFillData, distanceMiles: dist, onBusinessTap: { bizId in
                            selectedBusinessId = bizId
                        })
                            .id(stop.id)
                            .listRowBackground(highlightedStopId == stop.id ? Color(hex: "fff3e0") : Color.theme.surface)
                    }
                    .onMove { from, to in
                        guard isEditable else { return }
                        route.move(fromOffsets: from, toOffset: to)
                        renumberStops()
                        cameraPosition = .automatic
                        isDirty = true
                    }
                }
                .listStyle(.plain)
                .environment(\.editMode, .constant(isEditable ? .active : .inactive))
                .onChange(of: highlightedStopId) { _, newId in
                    if let id = newId {
                        withAnimation { proxy.scrollTo(id, anchor: .center) }
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
        .sheet(isPresented: $showMapSheet) {
            RouteMapSheet(
                route: route,
                startCoord: startCoord,
                startName: startName,
                showFillData: showFillData,
                onStopTap: { stop in
                    showMapSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        selectedStop = stop
                    }
                }
            )
        }
    }

    private func renumberStops() {
        for i in 0..<route.count {
            route[i].stopNumber = i + 1
        }
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

// MARK: - Route Save & Assign Sheet

struct RouteSaveAssignSheet: View {
    let route: [RouteStop]
    let startName: String
    let startCoord: CLLocationCoordinate2D
    let isAdmin: Bool
    let currentUserId: Int
    let onSaved: (Int, String) -> Void

    @Environment(\.dismiss) var dismiss
    @State private var routeName = ""
    @State private var saveToCollection = true
    @State private var assignRoute = false
    @State private var assignDate = Date()
    @State private var assignToUserId: Int?
    @State private var employees: [NotificationUser] = []
    @State private var saving = false
    @State private var errorMsg = ""
    @State private var makeRecurring = false
    @State private var recurrenceStart = Date()
    @State private var recurrenceInterval = 1
    @State private var recurrenceUnit = "week"

    private var stopsData: [[String: Any]] {
        route.map { stop in
            [
                "name": stop.candidate.business_name ?? "Unknown",
                "address": stop.addressLine.isEmpty ? "No address" : stop.addressLine,
                "latitude": stop.coordinate.latitude,
                "longitude": stop.coordinate.longitude,
                "source_type": stop.candidate.business_id > 0 ? "business" : "manual",
                "business_id": stop.candidate.business_id,
                "location_id": stop.id
            ] as [String: Any]
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
                            .padding(12).frame(maxWidth: .infinity)
                            .background(Color.theme.red.opacity(0.08)).cornerRadius(8)
                    }

                    // Route name
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ROUTE NAME")
                            .font(.custom("DMSans-SemiBold", size: 9))
                            .foregroundColor(Color.theme.textSecondary).tracking(0.4)
                        TextField("e.g. Monday Roanoke Run", text: $routeName)
                            .font(.custom("DMSans-Regular", size: 14))
                            .padding(12).background(Color.theme.surface).cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.theme.border, lineWidth: 1))
                    }

                    // Save to collection toggle
                    Toggle(isOn: $saveToCollection) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Save to my collection")
                                .font(.custom("DMSans-SemiBold", size: 14))
                                .foregroundColor(Color.theme.text)
                            Text("Access this route from Saved tab later")
                                .font(.custom("DMSans-Regular", size: 12))
                                .foregroundColor(Color.theme.textSecondary)
                        }
                    }
                    .tint(Color(hex: "2d6a4f"))

                    // Assign toggle
                    Toggle(isOn: $assignRoute) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Assign route")
                                .font(.custom("DMSans-SemiBold", size: 14))
                                .foregroundColor(Color.theme.text)
                            Text(isAdmin ? "Assign to yourself or another employee" : "Assign to yourself for a date")
                                .font(.custom("DMSans-Regular", size: 12))
                                .foregroundColor(Color.theme.textSecondary)
                        }
                    }
                    .tint(Color(hex: "c8893a"))

                    if assignRoute {
                        VStack(alignment: .leading, spacing: 12) {
                            // Date picker
                            DatePicker("Route Date", selection: $assignDate, displayedComponents: .date)
                                .font(.custom("DMSans-Medium", size: 14))
                                .tint(Color(hex: "c8893a"))

                            // User picker (admin only)
                            if isAdmin {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("ASSIGN TO")
                                        .font(.custom("DMSans-SemiBold", size: 9))
                                        .foregroundColor(Color.theme.textSecondary).tracking(0.4)
                                    Picker("Employee", selection: Binding(
                                        get: { assignToUserId ?? currentUserId },
                                        set: { assignToUserId = $0 }
                                    )) {
                                        ForEach(employees) { emp in
                                            Text("\(emp.name) (\(emp.role ?? ""))").tag(emp.id)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .tint(Color(hex: "c8893a"))
                                }
                            }
                        }
                        .padding(14).background(Color.theme.surface).cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.theme.border, lineWidth: 1))
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

                    // Submit
                    Button(action: save) {
                        HStack {
                            if saving { ProgressView().scaleEffect(0.8).tint(.white) }
                            else { Image(systemName: "square.and.arrow.down").font(.system(size: 14)) }
                            Text(assignRoute ? "Save & Assign" : "Save Route")
                                .font(.custom("DMSans-SemiBold", size: 15))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(hex: "2d6a4f"))
                        .cornerRadius(12)
                    }
                    .disabled(saving)

                    // Route summary
                    routeSummary
                }
                .padding(20)
            }
            .background(Color.theme.background)
            .navigationTitle("Save Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.custom("DMSans-Regular", size: 14))
                        .foregroundColor(Color.theme.textSecondary)
                }
            }
            .task { if isAdmin { await loadEmployees() } }
        }
    }

    private var routeSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ROUTE SUMMARY")
                .font(.custom("DMSans-SemiBold", size: 9))
                .foregroundColor(Color.theme.textSecondary).tracking(0.4)
            HStack(spacing: 16) {
                Label("\(route.count) stops", systemImage: "mappin.circle.fill")
                    .font(.custom("DMSans-Medium", size: 13))
                    .foregroundColor(Color(hex: "2d6a4f"))
                Label("from \(startName)", systemImage: "house.fill")
                    .font(.custom("DMSans-Medium", size: 13))
                    .foregroundColor(Color.theme.textSecondary)
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
                            .foregroundColor(Color.theme.text).lineLimit(1)
                        Text(stop.addressLine)
                            .font(.custom("DMSans-Regular", size: 11))
                            .foregroundColor(Color.theme.textSecondary).lineLimit(1)
                    }
                }
            }
        }
        .padding(16).background(Color.theme.background).cornerRadius(10)
    }

    private func loadEmployees() async {
        do { employees = try await APIClient.shared.getNotificationUsers() } catch { }
        assignToUserId = currentUserId
    }

    private func save() {
        let trimmed = routeName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            errorMsg = "Please enter a name for this route."; return
        }
        saving = true; errorMsg = ""
        let rStart = makeRecurring ? recurrenceStart.formatted(.iso8601).prefix(10).description : nil
        let rInterval = makeRecurring ? recurrenceInterval : nil
        let rUnit = makeRecurring ? recurrenceUnit : nil
        Task {
            do {
                var savedId = 0
                var savedName = trimmed
                if assignRoute {
                    let dateStr = assignDate.formatted(.iso8601).prefix(10)
                    let targetUserId = assignToUserId ?? currentUserId
                    let result = try await APIClient.shared.createAndAssignRoute(
                        name: trimmed, startName: startName,
                        startLat: startCoord.latitude, startLng: startCoord.longitude,
                        stops: stopsData, employeeId: targetUserId,
                        routeDate: String(dateStr), saveRoute: saveToCollection,
                        recurrenceStart: rStart, recurrenceInterval: rInterval, recurrenceUnit: rUnit
                    )
                    savedId = result.id; savedName = result.name
                } else {
                    let created = try await APIClient.shared.createRoute(
                        name: trimmed, startName: startName,
                        startLat: startCoord.latitude, startLng: startCoord.longitude,
                        stops: stopsData,
                        recurrenceStart: rStart, recurrenceInterval: rInterval, recurrenceUnit: rUnit
                    )
                    if saveToCollection {
                        try await APIClient.shared.saveRouteToCollection(routeId: created.id)
                    }
                    savedId = created.id; savedName = created.name
                }
                onSaved(savedId, savedName); dismiss()
            } catch { errorMsg = error.localizedDescription }
            saving = false
        }
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
                    NavigateAndVisitButton(
                        coordinate: stop.coordinate,
                        name: stop.candidate.business_name ?? "Collection Stop",
                        stopIndex: stop.stopNumber - 1
                    )
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(Color(hex: "c8893a")).frame(width: 40, height: 40)
                            Text("\(stop.stopNumber)").font(.custom("Syne-Bold", size: 16)).foregroundColor(.white)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stop.candidate.business_name ?? "Unknown")
                                .font(.custom("Syne-Bold", size: 18)).foregroundColor(Color.theme.text)
                            Text("Stop \(stop.stopNumber) of route")
                                .font(.custom("DMSans-Regular", size: 13)).foregroundColor(Color.theme.textSecondary)
                        }
                    }
                    Divider()
                    if !stop.addressLine.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "mappin.circle.fill").font(.system(size: 16)).foregroundColor(Color(hex: "2d6a4f")).frame(width: 20)
                            Text(stop.addressLine).font(.custom("DMSans-Regular", size: 14)).foregroundColor(Color.theme.text)
                        }
                    }
                    HStack(spacing: 10) {
                        Image(systemName: "road.lanes").font(.system(size: 14)).foregroundColor(Color.theme.textSecondary).frame(width: 20)
                        Text(String(format: "%.0f miles from start", distanceMiles))
                            .font(.custom("DMSans-Regular", size: 13)).foregroundColor(Color.theme.textSecondary)
                    }
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("COORDINATES").font(.custom("DMSans-SemiBold", size: 9)).foregroundColor(Color.theme.textSecondary).tracking(0.5)
                            Text(coordString).font(.system(.caption, design: .monospaced)).foregroundColor(Color.theme.text).textSelection(.enabled)
                        }
                        Spacer()
                        Button(action: copyCoordinates) {
                            HStack(spacing: 4) {
                                Image(systemName: copiedFeedback ? "checkmark" : "doc.on.doc").font(.system(size: 11))
                                Text(copiedFeedback ? "Copied" : "Copy").font(.custom("DMSans-SemiBold", size: 11))
                            }
                            .foregroundColor(copiedFeedback ? Color(hex: "2d6a4f") : Color.theme.text)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color.theme.background).cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.theme.border, lineWidth: 1))
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Stop Details").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.font(.custom("DMSans-Medium", size: 14)).foregroundColor(Color(hex: "c8893a"))
                }
            }
        }
    }

    private var coordString: String { String(format: "%.6f, %.6f", stop.coordinate.latitude, stop.coordinate.longitude) }
    private func copyCoordinates() {
        UIPasteboard.general.string = coordString
        copiedFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedFeedback = false }
    }
}

// MARK: - Start Location Detail Sheet

struct StartLocationDetailSheet: View {
    let name: String
    let coordinate: CLLocationCoordinate2D
    @Environment(\.dismiss) var dismiss
    @State private var copiedFeedback = false
    @State private var showNavigation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Button(action: { showNavigation = true }) {
                        HStack {
                            Image(systemName: "map.fill").font(.system(size: 14))
                            Text("Navigate").font(.custom("DMSans-SemiBold", size: 15))
                        }
                        .foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Color.theme.text).cornerRadius(12)
                    }
                    .fullScreenCover(isPresented: $showNavigation) {
                        InAppNavigationSheet(destination: coordinate, destinationName: name)
                    }
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(Color.theme.text).frame(width: 40, height: 40)
                            Image(systemName: "house.fill").font(.system(size: 14)).foregroundColor(.white)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name).font(.custom("Syne-Bold", size: 18)).foregroundColor(Color.theme.text)
                            Text("Starting Location").font(.custom("DMSans-Regular", size: 13)).foregroundColor(Color.theme.textSecondary)
                        }
                    }
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("COORDINATES").font(.custom("DMSans-SemiBold", size: 9)).foregroundColor(Color.theme.textSecondary).tracking(0.5)
                            Text(coordString).font(.system(.caption, design: .monospaced)).foregroundColor(Color.theme.text).textSelection(.enabled)
                        }
                        Spacer()
                        Button(action: copyCoordinates) {
                            HStack(spacing: 4) {
                                Image(systemName: copiedFeedback ? "checkmark" : "doc.on.doc").font(.system(size: 11))
                                Text(copiedFeedback ? "Copied" : "Copy").font(.custom("DMSans-SemiBold", size: 11))
                            }
                            .foregroundColor(copiedFeedback ? Color(hex: "2d6a4f") : Color.theme.text)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color.theme.background).cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.theme.border, lineWidth: 1))
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Start Location").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.font(.custom("DMSans-Medium", size: 14)).foregroundColor(Color(hex: "c8893a"))
                }
            }
        }
    }

    private var coordString: String { String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude) }
    private func copyCoordinates() {
        UIPasteboard.general.string = coordString
        copiedFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedFeedback = false }
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
            Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundColor(Color(hex: "2d6a4f"))
            Text("All caught up!")
                .font(.custom("Syne-ExtraBold", size: 24)).foregroundColor(Color.theme.text)
            Text("No locations have reached container capacity.\nAll containers are below 50 gallons.")
                .font(.custom("DMSans-Regular", size: 14)).foregroundColor(Color.theme.textSecondary)
                .multilineTextAlignment(.center).lineSpacing(4)
            Spacer()
        }
        .padding()
    }
}

// MARK: - Stop Row

struct StopRow: View {
    let stop: RouteStop
    var showFillData: Bool = true
    var distanceMiles: Double? = nil
    var onBusinessTap: ((Int) -> Void)? = nil
    @ObservedObject private var travelManager = RouteTravelManager.shared

    private var isVisited: Bool { travelManager.isTraveling && travelManager.isStopVisited(stop.stopNumber - 1) }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(isVisited ? Color(hex: "2d6a4f") : (showFillData ? badgeColor : Color(hex: "2d6a4f"))).frame(width: 32, height: 32)
                if isVisited {
                    Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                } else {
                    Text("\(stop.stopNumber)").font(.custom("Syne-Bold", size: 14)).foregroundColor(.white)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Button(action: { onBusinessTap?(stop.candidate.business_id) }) {
                    Text(stop.candidate.business_name ?? "Unknown")
                        .font(.custom("DMSans-SemiBold", size: 15)).foregroundColor(Color(hex: "c8893a")).lineLimit(1).underline()
                }
                .buttonStyle(.plain)
                if !stop.addressLine.isEmpty {
                    Text(stop.addressLine).font(.custom("DMSans-Regular", size: 12)).foregroundColor(Color.theme.textSecondary).lineLimit(1)
                }
                HStack(spacing: 12) {
                    if let dist = distanceMiles, dist > 0 {
                        Label(String(format: "%.0f mi", dist), systemImage: "arrow.forward")
                            .font(.custom("DMSans-Regular", size: 11)).foregroundColor(Color.theme.textSecondary)
                    }
                    if showFillData {
                        HStack(spacing: 4) {
                            fillGauge
                            Text("\(Int(stop.fillLevel))/\(Int(routeContainerCapacity))g")
                                .font(.custom("DMSans-SemiBold", size: 11)).foregroundColor(fillColor)
                        }
                        Label("\(stop.daysSincePickup)d ago", systemImage: "clock")
                            .font(.custom("DMSans-Regular", size: 11)).foregroundColor(Color.theme.textSecondary)
                        Label("\(stop.estimatedGallons)g/wk", systemImage: "arrow.up.right")
                            .font(.custom("DMSans-Regular", size: 11)).foregroundColor(Color.theme.textSecondary)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }

    private var fillGauge: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3).fill(Color.theme.border).frame(width: 32, height: 6)
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
                VStack { Spacer(); ProgressView("Loading business…").font(.custom("DMSans-Regular", size: 14)); Spacer() }
            } else if let business = business {
                BusinessDetailView(business: business, regions: regions, canManageRegions: false, onUpdate: { Task { await loadData() } })
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 36)).foregroundColor(Color(hex: "c1121f"))
                    Text(errorMsg.isEmpty ? "Business not found" : errorMsg)
                        .font(.custom("DMSans-Regular", size: 14)).foregroundColor(Color.theme.text)
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
            business = try await bizReq; regions = try await regReq
        } catch { errorMsg = error.localizedDescription }
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
        lastLocation = locations.last; manager.stopUpdatingLocation()
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { }
}

#Preview {
    NavigationStack { RoutePlannerView() }.environmentObject(AuthManager())
}

// MARK: - Route Map Sheet

struct RouteMapSheet: View {
    let route: [RouteStop]
    let startCoord: CLLocationCoordinate2D
    let startName: String
    var showFillData: Bool = true
    var onStopTap: ((RouteStop) -> Void)? = nil
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
                ForEach(route) { stop in
                    Annotation(stop.candidate.business_name ?? "", coordinate: stop.coordinate) {
                        Button(action: { onStopTap?(stop) }) {
                            ZStack {
                                Circle().fill(Color(hex: "2d6a4f")).frame(width: 30, height: 30)
                                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                                Text("\(stop.stopNumber)").font(.custom("Syne-Bold", size: 13)).foregroundColor(.white)
                            }
                        }
                    }
                }
                if route.count >= 1 {
                    let coords = [startCoord] + route.map { $0.coordinate } + [startCoord]
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
                    Label("\(route.count) stops", systemImage: "mappin.circle.fill")
                        .font(.custom("DMSans-SemiBold", size: 12)).foregroundColor(Color(hex: "2d6a4f"))
                    Text("·").foregroundColor(.white.opacity(0.4))
                    let totalMiles = totalRouteMiles()
                    Label(String(format: "%.0f mi", totalMiles), systemImage: "road.lanes")
                        .font(.custom("DMSans-SemiBold", size: 12)).foregroundColor(.white)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.ultraThinMaterial).cornerRadius(12)
                .padding(.bottom, 12)
            }
            .navigationTitle("Route Map").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.font(.custom("DMSans-Medium", size: 14)).foregroundColor(Color(hex: "c8893a"))
                }
            }
        }
    }

    private func totalRouteMiles() -> Double {
        guard !route.isEmpty else { return 0 }
        let allCoords = [startCoord] + route.map { $0.coordinate } + [startCoord]
        var total = 0.0
        for i in 0..<(allCoords.count - 1) {
            total += RouteEngine.haversine(from: allCoords[i], to: allCoords[i + 1])
        }
        return total / 1609.344
    }
}
