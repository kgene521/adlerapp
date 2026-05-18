// /AdlerCRM/Views/InAppNavigationSheet.swift  17/04/2026 02:30:00 EDT
import SwiftUI
import MapKit
import CoreLocation
import Combine

// MARK: - In-App Navigation Sheet

struct InAppNavigationSheet: View {
    let destination: CLLocationCoordinate2D
    let destinationName: String
    @Environment(\.dismiss) var dismiss
    @StateObject private var navState = NavigationState()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Map
                mapView

                // Bottom card
                bottomCard
            }
            .ignoresSafeArea(edges: .top)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                            Text("Back").font(.custom("DMSans-Medium", size: 14))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .cornerRadius(50)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: openInExternalMaps) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right.square").font(.system(size: 11))
                            Text("Maps").font(.custom("DMSans-Medium", size: 12))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .cornerRadius(50)
                    }
                }
            }
            .task { await navState.calculateRoute(to: destination, name: destinationName) }
        }
    }

    // MARK: - Map View

    private var mapView: some View {
        Map(position: $navState.cameraPosition) {
            // User location
            UserAnnotation()

            // Destination pin
            Annotation(destinationName, coordinate: destination) {
                ZStack {
                    Circle().fill(Color(hex: "c1121f")).frame(width: 32, height: 32)
                    Image(systemName: "mappin").font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                }
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
            }

            // Route polyline
            if let route = navState.route {
                MapPolyline(route.polyline)
                    .stroke(Color(hex: "2d6a4f"), lineWidth: 5)
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
    }

    // MARK: - Bottom Card

    private var bottomCard: some View {
        VStack(spacing: 0) {
            // Drag indicator
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.theme.border)
                .frame(width: 36, height: 4)
                .padding(.top, 8)
                .padding(.bottom, 6)

            // ETA bar
            if navState.isLoading {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("Calculating route…")
                        .font(.custom("DMSans-Regular", size: 13))
                        .foregroundColor(Color.theme.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            } else if let error = navState.error {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Color(hex: "c1121f"))
                    Text(error)
                        .font(.custom("DMSans-Regular", size: 13))
                        .foregroundColor(Color(hex: "c1121f"))
                    Spacer()
                    Button("Open Maps") { openInExternalMaps() }
                        .font(.custom("DMSans-SemiBold", size: 12))
                        .foregroundColor(Color(hex: "c8893a"))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            } else if let route = navState.route {
                // ETA header
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(destinationName)
                            .font(.custom("DMSans-SemiBold", size: 15))
                            .foregroundColor(Color.theme.text)
                            .lineLimit(1)
                        HStack(spacing: 12) {
                            Label(navState.formattedDuration(route.expectedTravelTime), systemImage: "clock")
                                .font(.custom("DMSans-Medium", size: 13))
                                .foregroundColor(Color(hex: "2d6a4f"))
                            Label(navState.formattedDistance(route.distance), systemImage: "road.lanes")
                                .font(.custom("DMSans-Medium", size: 13))
                                .foregroundColor(Color.theme.textSecondary)
                        }
                    }
                    Spacer()
                    // Arrival time
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("ARRIVE")
                            .font(.custom("DMSans-SemiBold", size: 8))
                            .foregroundColor(Color.theme.textSecondary)
                            .tracking(0.5)
                        Text(navState.arrivalTime(route.expectedTravelTime))
                            .font(.custom("Syne-Bold", size: 18))
                            .foregroundColor(Color(hex: "2d6a4f"))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider().padding(.horizontal, 16)

                // Step-by-step directions
                if !route.steps.isEmpty {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(route.steps.enumerated()), id: \.offset) { idx, step in
                                if !step.instructions.isEmpty {
                                    stepRow(step, index: idx, isLast: idx == route.steps.count - 1)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .frame(maxHeight: 250)
                }
            }
        }
        .background(.regularMaterial)
        .cornerRadius(16, corners: [.topLeft, .topRight])
        .shadow(color: .black.opacity(0.15), radius: 8, y: -4)
    }

    // MARK: - Step Row

    private func stepRow(_ step: MKRoute.Step, index: Int, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(isLast ? Color(hex: "c1121f").opacity(0.12) : Color(hex: "2d6a4f").opacity(0.12))
                    .frame(width: 28, height: 28)
                Image(systemName: stepIcon(step, isLast: isLast))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isLast ? Color(hex: "c1121f") : Color(hex: "2d6a4f"))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(step.instructions)
                    .font(.custom("DMSans-Regular", size: 13))
                    .foregroundColor(Color.theme.text)
                if step.distance > 0 {
                    Text(navState.formattedDistance(step.distance))
                        .font(.custom("DMSans-Regular", size: 11))
                        .foregroundColor(Color.theme.textSecondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .overlay(
            Group {
                if !isLast { Divider().padding(.leading, 40) }
            }, alignment: .bottom
        )
    }

    private func stepIcon(_ step: MKRoute.Step, isLast: Bool) -> String {
        if isLast { return "flag.fill" }
        let instr = step.instructions.lowercased()
        if instr.contains("left") { return "arrow.turn.up.left" }
        if instr.contains("right") { return "arrow.turn.up.right" }
        if instr.contains("u-turn") { return "arrow.uturn.left" }
        if instr.contains("merge") { return "arrow.merge" }
        if instr.contains("ramp") || instr.contains("exit") { return "arrow.up.right" }
        if instr.contains("straight") || instr.contains("continue") { return "arrow.up" }
        return "arrow.up"
    }

    // MARK: - External Maps Fallback

    private func openInExternalMaps() {
        MapHelpers.openDirectionsExternal(to: destination, name: destinationName)
    }
}

// MARK: - Navigation State

@MainActor
class NavigationState: ObservableObject {
    @Published var route: MKRoute?
    @Published var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @Published var isLoading = false
    @Published var error: String?

    func calculateRoute(to destination: CLLocationCoordinate2D, name: String) async {
        isLoading = true
        error = nil

        let request = MKDirections.Request()
        request.source = MKMapItem.forCurrentLocation()
        request.destination = MapHelpers.makeMapItem(coordinate: destination, name: name)
        request.transportType = .automobile

        let directions = MKDirections(request: request)

        do {
            let response = try await directions.calculate()
            if let bestRoute = response.routes.first {
                route = bestRoute
                // Zoom to show entire route
                let rect = bestRoute.polyline.boundingMapRect
                let padded = rect.insetBy(dx: -rect.width * 0.15, dy: -rect.height * 0.15)
                cameraPosition = .rect(MKMapRect(
                    origin: padded.origin,
                    size: padded.size
                ))
            } else {
                error = "No route found"
            }
        } catch {
            self.error = "Could not calculate route"
        }
        isLoading = false
    }

    func formattedDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds / 60)
        if mins < 60 { return "\(mins) min" }
        let hrs = mins / 60
        let remainMins = mins % 60
        if remainMins == 0 { return "\(hrs) hr" }
        return "\(hrs) hr \(remainMins) min"
    }

    func formattedDistance(_ meters: CLLocationDistance) -> String {
        let miles = meters / 1609.344
        if miles < 0.1 { return "\(Int(meters * 3.281)) ft" }
        return String(format: "%.1f mi", miles)
    }

    func arrivalTime(_ seconds: TimeInterval) -> String {
        let arrival = Date().addingTimeInterval(seconds)
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm a"
        return fmt.string(from: arrival)
    }
}
