// AdlerCRM/Views/CalendarRouteView.swift  02/04/2026 23:44:23
import SwiftUI
import MapKit
import CoreLocation
import Combine

struct CalendarRouteView: View {
    @StateObject private var locationManager = LocationHelper()
    @State private var candidates: [RouteCandidate] = []
    @State private var loading = true
    @State private var errorMsg = ""

    // Date selection
    @State private var selectedDate = Date()

    // Starting location
    @State private var selectedStartId: String = "current"
    @State private var startCoord: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 37.2710, longitude: -79.9414)
    @State private var showStartPicker = false

    // Region
    @State private var regionOptions: [RegionInfo] = []
    @State private var selectedRegionId: Int = -1
    @State private var regionAutoSelected = false

    // Route result
    @State private var route: [RouteStop] = []
    @State private var originalRoute: [RouteStop] = []
    @State private var nextReadyDate: Date?
    @State private var nextReadyCount = 0
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isDirty = false

    // Collapse
    @State private var showControls = false
    @State private var showSaveSheet = false

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
                ProgressView("Loading data…")
                    .font(.custom("DMSans-Regular", size: 14))
                Spacer()
            } else if !errorMsg.isEmpty {
                errorView
            } else if route.isEmpty {
                // Show full controls when no route
                controlBar
                inlineEmptyView
            } else {
                // Compact summary bar (always visible)
                compactBar

                // Expanded controls (collapsible)
                if showControls {
                    controlBar
                }

                // Route map + list (shared component)
                RouteMapListView(
                    route: $route,
                    startCoord: startCoord,
                    regionName: currentRegionName,
                    startName: currentStartName,
                    cameraPosition: $cameraPosition,
                    isDirty: $isDirty,
                    onReset: {
                        route = originalRoute
                        isDirty = false
                        cameraPosition = .automatic
                    }
                )
            }
        }
        .background(Color(hex: "f5f4f0"))
        .navigationTitle("Calendar")
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
        .task { await loadData() }
        .onChange(of: selectedDate) { _, _ in recompute() }
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
                Image(systemName: "calendar")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "c8893a"))
                Text(shortDateLabel)
                    .font(.custom("DMSans-SemiBold", size: 12))
                    .foregroundColor(Color(hex: "0f1117"))

                Text("·").foregroundColor(Color(hex: "e2dfd6"))

                Image(systemName: selectedStartId == "current" ? "location.fill" : "mappin.circle.fill")
                    .font(.system(size: 9))
                    .foregroundColor(Color(hex: "2d6a4f"))
                Text(currentStartName)
                    .font(.custom("DMSans-Medium", size: 12))
                    .foregroundColor(Color(hex: "7a7f94"))
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

    // MARK: - Control Bar (collapsible)

    private var controlBar: some View {
        VStack(spacing: 0) {
            // Calendar
            calendarCard

            // Start location
            startLocationBar

            // Region picker
            if regionOptions.count > 1 {
                RegionPickerBar(options: regionOptions, selectedId: $selectedRegionId)
            }
        }
    }

    // MARK: - Calendar Card

    private var calendarCard: some View {
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
        .background(Color.white)
        .overlay(Rectangle().fill(Color(hex: "e2dfd6")).frame(height: 1), alignment: .bottom)
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

    // MARK: - Inline Empty

    private var inlineEmptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundColor(Color(hex: "2d6a4f"))

            Text(isToday ? "All caught up!" : "No route needed")
                .font(.custom("Syne-Bold", size: 20))
                .foregroundColor(Color(hex: "0f1117"))

            if let name = currentRegionName, selectedRegionId >= 0 {
                Text("No locations in \(name) will have reached container capacity by \(dateLabel.lowercased()).")
                    .font(.custom("DMSans-Regular", size: 13))
                    .foregroundColor(Color(hex: "7a7f94"))
                    .multilineTextAlignment(.center)
            } else {
                Text("No containers will be full by \(dateLabel.lowercased()).")
                    .font(.custom("DMSans-Regular", size: 13))
                    .foregroundColor(Color(hex: "7a7f94"))
                    .multilineTextAlignment(.center)
            }

            if let date = nextReadyDate {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 16))
                        .foregroundColor(Color(hex: "c8893a"))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Next trip needed")
                            .font(.custom("DMSans-SemiBold", size: 12))
                            .foregroundColor(Color(hex: "0f1117"))
                        let fmt = DateFormatter()
                        let _ = fmt.dateFormat = "EEEE, MMM d"
                        Text("\(fmt.string(from: date)) — \(nextReadyCount) location\(nextReadyCount == 1 ? "" : "s")")
                            .font(.custom("DMSans-Regular", size: 12))
                            .foregroundColor(Color(hex: "7a7f94"))
                    }
                }
                .padding(14)
                .background(Color.white)
                .cornerRadius(10)
                .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
            }
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
                .foregroundColor(Color(hex: "3a3d4a"))
                .multilineTextAlignment(.center)
            Button("Retry") { reload() }
                .font(.custom("DMSans-SemiBold", size: 14))
                .foregroundColor(.white)
                .padding(.horizontal, 24).padding(.vertical, 10)
                .background(Color(hex: "0f1117")).cornerRadius(8)
            Spacer()
        }
        .padding()
    }

    // MARK: - Logic

    private func reload() { Task { await loadData() } }

    private func loadData() async {
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
            candidates: candidates, targetDate: selectedDate,
            regionId: selectedRegionId, startCoord: startCoord
        )
        route = result.stops
        originalRoute = result.stops
        nextReadyDate = result.nextReadyDate
        nextReadyCount = result.nextReadyCount
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

#Preview {
    NavigationStack { CalendarRouteView() }.environmentObject(AuthManager())
}
