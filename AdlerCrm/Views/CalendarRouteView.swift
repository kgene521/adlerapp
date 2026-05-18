// /AdlerCRM/Views/CalendarRouteView.swift  16/04/2026 01:49:00 EDT
import SwiftUI
import MapKit
import CoreLocation
import Combine

struct CalendarRouteView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var locationManager = LocationHelper()
    @ObservedObject private var travelManager = RouteTravelManager.shared
    @State private var loading = true
    @State private var errorMsg = ""

    // Date selection
    @State private var selectedDate = Date()

    // Starting location
    @State private var selectedStartId: String = "current"
    @State private var startCoord: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 37.2710, longitude: -79.9414)

    // Assigned routes for selected date
    @State private var assignedRoutes: [SavedRoute] = []
    @State private var selectedRoute: SavedRoute?
    @State private var route: [RouteStop] = []
    @State private var originalRoute: [RouteStop] = []
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isDirty = false

    // Save
    @State private var showSaveSheet = false
    @State private var showRenameSheet = false
    @State private var showRecurrenceSheet = false
    @State private var savingDirect = false
    @State private var currentRouteId: Int?
    @State private var currentRouteName: String = ""
    @State private var currentRecurrenceStart: String?
    @State private var currentRecurrenceInterval: Int?
    @State private var currentRecurrenceUnit: String?

    // Unsaved changes
    @State private var showUnsavedAlert = false
    @State private var pendingAction: PendingAction?

    enum PendingAction {
        case back
        case dateChange(Date)
    }

    // Calendar dots
    @State private var assignedDates: Set<String> = []

    // Collapse
    @State private var showControls = false

    private var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    private var dateLabel: String {
        if isToday { return "Today" }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, yyyy"
        return fmt.string(from: selectedDate)
    }

    private var shortDateLabel: String {
        if isToday { return "Today" }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return fmt.string(from: selectedDate)
    }

    var body: some View {
        VStack(spacing: 0) {
            if loading {
                Spacer()
                ProgressView("Loading routes…")
                    .font(.custom("DMSans-Regular", size: 14))
                Spacer()
            } else if !errorMsg.isEmpty {
                errorView
            } else if let selected = selectedRoute, !route.isEmpty {
                // Viewing a specific route
                routeHeader(selected)
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
                // Travel controls
                RouteTravelBar(routeName: selected.name, routeId: selected.id, totalStops: route.count, onStopNavigate: nil)
            } else if assignedRoutes.isEmpty {
                compactBar
                if showControls { controlBar }
                inlineEmptyView
            } else {
                // Compact bar + route list
                compactBar
                if showControls { controlBar }
                routeList
            }
        }
        .background(Color.theme.background)
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: reload) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(Color.theme.textSecondary)
                }
            }
        }
        .task { await loadData(); await travelManager.syncWithServer() }
        .onChange(of: selectedDate) { oldDate, newDate in
            if isDirty {
                selectedDate = oldDate
                pendingAction = .dateChange(newDate)
                showUnsavedAlert = true
            } else {
                selectedRoute = nil; route = []; originalRoute = []; isDirty = false
                Task { await loadRoutesForDate() }
            }
        }
        .sheet(isPresented: $showSaveSheet) {
            RouteSaveAssignSheet(
                route: route,
                startName: currentStartName,
                startCoord: startCoord,
                isAdmin: auth.currentUser?.role == "Administrator",
                currentUserId: auth.currentUser?.id ?? 0,
                onSaved: { id, name in
                    currentRouteId = id
                    currentRouteName = name
                    originalRoute = route
                    isDirty = false
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
                            stops: routeStopsData
                        )
                        currentRouteId = saved.id
                        currentRouteName = saved.name
                        originalRoute = route
                        isDirty = false
                    } catch { }
                }
            }
        }
        .sheet(isPresented: $showRecurrenceSheet) {
            RouteRecurrenceSheet(
                routeId: currentRouteId,
                routeName: currentRouteName.isEmpty ? (selectedRoute?.name ?? "Route") : currentRouteName,
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

    private func goBack() {
        selectedRoute = nil; route = []; originalRoute = []; isDirty = false; cameraPosition = .automatic
        currentRouteId = nil; currentRouteName = ""
        currentRecurrenceStart = nil; currentRecurrenceInterval = nil; currentRecurrenceUnit = nil
    }

    private func executePendingAction() {
        switch pendingAction {
        case .back:
            goBack()
        case .dateChange(let newDate):
            selectedRoute = nil; route = []; originalRoute = []; isDirty = false
            selectedDate = newDate
            Task { await loadRoutesForDate() }
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
                    id: routeId, name: currentRouteName, startName: currentStartName,
                    startLat: startCoord.latitude, startLng: startCoord.longitude,
                    stops: routeStopsData,
                    recurrenceStart: currentRecurrenceStart, recurrenceInterval: currentRecurrenceInterval, recurrenceUnit: currentRecurrenceUnit
                )
                currentRouteId = saved.id
                currentRouteName = saved.name
                originalRoute = route
                isDirty = false
            } catch { }
            savingDirect = false
        }
    }

    // MARK: - Route Editability

    private var isRouteEditable: Bool {
        guard let ar = selectedRoute else { return true }
        let userId = auth.currentUser?.id ?? 0
        return ar.assigned_by == userId || ar.created_by == userId || auth.currentUser?.role == "Administrator"
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
                Text(currentRouteName.isEmpty ? (selectedRoute?.name ?? "Route") : currentRouteName)
                    .font(.custom("DMSans-SemiBold", size: 13))
                    .foregroundColor(Color.theme.text)
                    .lineLimit(1)
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

    // MARK: - Route Header (viewing single route)

    private func routeHeader(_ ar: SavedRoute) -> some View {
        HStack(spacing: 8) {
            Button(action: {
                if isDirty {
                    pendingAction = .back
                    showUnsavedAlert = true
                } else {
                    goBack()
                }
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "c8893a"))
            }
            Image(systemName: "calendar")
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "c8893a"))
            Text(shortDateLabel)
                .font(.custom("DMSans-SemiBold", size: 12))
                .foregroundColor(Color.theme.text)
            Text("·").foregroundColor(Color.theme.border)
            Text(ar.name)
                .font(.custom("DMSans-SemiBold", size: 12))
                .foregroundColor(Color(hex: "2d6a4f"))
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Color.theme.surface)
        .overlay(Rectangle().fill(Color.theme.border).frame(height: 1), alignment: .bottom)
    }

    // MARK: - Route List

    private var routeList: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(assignedRoutes) { ar in
                    Button(action: { selectRoute(ar) }) {
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
                                if ar.source == "recurring" {
                                    Label("Recurring", systemImage: "repeat")
                                        .font(.custom("DMSans-Medium", size: 11))
                                        .foregroundColor(Color(hex: "2d6a4f"))
                                } else if let by = ar.assigned_by_name {
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

    // MARK: - Compact Summary Bar

    private var compactBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar")
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "c8893a"))
            Text(shortDateLabel)
                .font(.custom("DMSans-SemiBold", size: 13))
                .foregroundColor(Color.theme.text)
            Text("·").foregroundColor(Color.theme.border)
            Text("\(assignedRoutes.count) route\(assignedRoutes.count == 1 ? "" : "s")")
                .font(.custom("DMSans-Medium", size: 12))
                .foregroundColor(Color(hex: "2d6a4f"))
            Spacer()
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 14))
                    Text(showControls ? "Hide" : "Pick Date")
                        .font(.custom("DMSans-SemiBold", size: 12))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color(hex: "c8893a"))
                .cornerRadius(8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.theme.surface)
        .overlay(Rectangle().fill(Color.theme.border).frame(height: 1), alignment: .bottom)
    }

    // MARK: - Control Bar (calendar)

    private var controlBar: some View {
        VStack(spacing: 0) {
            DatePicker(
                "Select Date",
                selection: $selectedDate,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .tint(Color(hex: "c8893a"))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .background(Color.theme.surface)
        .overlay(Rectangle().fill(Color.theme.border).frame(height: 1), alignment: .bottom)
    }

    // MARK: - Empty

    private var inlineEmptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 44))
                .foregroundColor(Color.theme.border)
            Text("No routes for \(dateLabel)")
                .font(.custom("Syne-Bold", size: 18))
                .foregroundColor(Color.theme.text)
            Text("No routes have been assigned for this date.")
                .font(.custom("DMSans-Regular", size: 13))
                .foregroundColor(Color.theme.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(32)
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
            Button("Retry") { reload() }
                .font(.custom("DMSans-SemiBold", size: 14))
                .foregroundColor(.white)
                .padding(.horizontal, 24).padding(.vertical, 10)
                .background(Color.theme.text).cornerRadius(8)
            Spacer()
        }
        .padding()
    }

    // MARK: - Logic

    private func reload() { Task { await loadData() } }

    private func loadData() async {
        loading = true; errorMsg = ""
        resolveStartCoord()
        do {
            await loadRoutesForDate()
            await loadAssignedDates()
        }
        loading = false
    }

    private func loadRoutesForDate() async {
        let dateStr = dateString(selectedDate)
        do {
            assignedRoutes = try await APIClient.shared.getAssignedRoutes(date: dateStr)
        } catch {
            if errorMsg.isEmpty { errorMsg = error.localizedDescription }
        }
    }

    private func loadAssignedDates() async {
        let cal = Calendar.current
        let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: selectedDate)) ?? selectedDate
        let endOfMonth = cal.date(byAdding: .month, value: 1, to: startOfMonth) ?? selectedDate
        let from = dateString(startOfMonth)
        let to = dateString(endOfMonth)
        do {
            let counts = try await APIClient.shared.getAssignedDates(from: from, to: to)
            assignedDates = Set(counts.map { String($0.route_date.prefix(10)) })
        } catch { }
    }

    private func selectRoute(_ ar: SavedRoute) {
        selectedRoute = ar
        currentRouteId = ar.id
        currentRouteName = ar.name
        if let sLat = ar.start_lat, let sLng = ar.start_lng {
            startCoord = CLLocationCoordinate2D(latitude: sLat, longitude: sLng)
        }
        guard let stops = ar.stops, !stops.isEmpty else {
            route = []; originalRoute = []; return
        }
        route = stops.enumerated().map { idx, stop in
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
        originalRoute = route
        isDirty = false
        cameraPosition = .automatic

        currentRecurrenceStart = ar.recurrence_start
        currentRecurrenceInterval = ar.recurrence_interval
        currentRecurrenceUnit = ar.recurrence_unit
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

    private func resolveStartCoord() {
        if selectedStartId == "current" {
            startCoord = locationManager.lastLocation?.coordinate ?? CLLocationCoordinate2D(latitude: 37.2710, longitude: -79.9414)
        }
    }

    private var currentStartName: String {
        if selectedStartId == "current" {
            return locationManager.lastLocation != nil ? "Current Location" : "Roanoke, VA (default)"
        }
        return startLocationPresets.first { $0.id == selectedStartId }?.name ?? "Unknown"
    }

    private func dateString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }
}

#Preview {
    NavigationStack { CalendarRouteView() }.environmentObject(AuthManager())
}
