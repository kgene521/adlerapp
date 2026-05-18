// /AdlerCRM/Views/RouteTravelBar.swift  17/04/2026 02:08:00 EDT
import SwiftUI
import MapKit

// MARK: - Travel Bar (embed in any route view)

struct RouteTravelBar: View {
    let routeName: String
    let routeId: Int?
    let totalStops: Int
    let onStopNavigate: ((Int) -> Void)?

    @ObservedObject private var manager = RouteTravelManager.shared
    @State private var showEndConfirm = false
    @State private var showActiveSessionAlert = false

    /// Whether this bar's route matches the active session
    private var isThisRoute: Bool {
        manager.isSessionForRoute(name: routeName, routeId: routeId)
    }

    /// Show controls only if no session is active OR this route is the active session
    private var showControls: Bool {
        !manager.isTraveling || isThisRoute
    }

    var body: some View {
        if !showControls {
            // Another route is active — show info bar
            otherRouteActiveBar
        } else if !manager.isTraveling {
            // No session — show Start button
            startBar
        } else {
            // This route is active — show controls
            activeBar
        }
    }

    // MARK: - Start Bar

    private var startBar: some View {
        Button(action: {
            Task { await manager.startTravel(routeName: routeName, routeId: routeId, totalStops: totalStops) }
        }) {
            HStack(spacing: 8) {
                if manager.isLoading {
                    ProgressView().tint(.white).scaleEffect(0.8)
                } else {
                    Image(systemName: "play.fill").font(.system(size: 12))
                }
                Text("Start Route").font(.custom("DMSans-SemiBold", size: 14))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(hex: "2d6a4f"))
            .cornerRadius(10)
        }
        .disabled(manager.isLoading || totalStops == 0)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.theme.surface)
        .overlay(Rectangle().fill(Color.theme.border).frame(height: 1), alignment: .top)
    }

    // MARK: - Active Bar

    private var activeBar: some View {
        VStack(spacing: 8) {
            // Progress
            HStack(spacing: 8) {
                Circle()
                    .fill(manager.isPaused ? Color(hex: "c8893a") : Color(hex: "2d6a4f"))
                    .frame(width: 8, height: 8)

                Text(manager.isPaused ? "PAUSED" : "IN PROGRESS")
                    .font(.custom("DMSans-Bold", size: 9))
                    .foregroundColor(manager.isPaused ? Color(hex: "c8893a") : Color(hex: "2d6a4f"))
                    .tracking(0.5)

                Spacer()

                Text("\(manager.visitedStopIndices.count)/\(totalStops) stops")
                    .font(.custom("DMSans-SemiBold", size: 12))
                    .foregroundColor(Color.theme.text)

                // Progress bar
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.theme.border).frame(width: 50, height: 6)
                    RoundedRectangle(cornerRadius: 3).fill(Color(hex: "2d6a4f"))
                        .frame(width: totalStops > 0 ? 50 * CGFloat(manager.visitedStopIndices.count) / CGFloat(totalStops) : 0, height: 6)
                }
            }

            // Buttons
            HStack(spacing: 10) {
                // Pause / Resume
                Button(action: {
                    Task {
                        if manager.isPaused { await manager.resumeTravel() }
                        else { await manager.pauseTravel() }
                    }
                }) {
                    HStack(spacing: 6) {
                        if manager.isLoading {
                            ProgressView().tint(manager.isPaused ? .white : Color(hex: "c8893a")).scaleEffect(0.7)
                        } else {
                            Image(systemName: manager.isPaused ? "play.fill" : "pause.fill").font(.system(size: 11))
                        }
                        Text(manager.isPaused ? "Resume" : "Pause").font(.custom("DMSans-SemiBold", size: 13))
                    }
                    .foregroundColor(manager.isPaused ? .white : Color(hex: "c8893a"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(manager.isPaused ? Color(hex: "c8893a") : Color(hex: "c8893a").opacity(0.12))
                    .cornerRadius(8)
                }
                .disabled(manager.isLoading)

                // End Route
                Button(action: { showEndConfirm = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.fill").font(.system(size: 11))
                        Text("End Route").font(.custom("DMSans-SemiBold", size: 13))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(hex: "c1121f"))
                    .cornerRadius(8)
                }
                .disabled(manager.isLoading)
            }

            // Error
            if let err = manager.error {
                Text(err)
                    .font(.custom("DMSans-Regular", size: 11))
                    .foregroundColor(Color(hex: "c1121f"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.theme.surface)
        .overlay(Rectangle().fill(manager.isPaused ? Color(hex: "c8893a") : Color(hex: "2d6a4f")).frame(height: 2), alignment: .top)
        .confirmationDialog("End this route?", isPresented: $showEndConfirm, titleVisibility: .visible) {
            Button("End Route", role: .destructive) { Task { await manager.endTravel() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will mark the route as completed. \(manager.visitedStopIndices.count)/\(totalStops) stops visited.")
        }
    }

    // MARK: - Other Route Active Bar

    private var otherRouteActiveBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "c8893a"))
            Text("Route \"\(manager.activeSession?.route_name ?? "Unknown")\" is \(manager.isPaused ? "paused" : "in progress")")
                .font(.custom("DMSans-Medium", size: 12))
                .foregroundColor(Color.theme.text)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(hex: "c8893a").opacity(0.08))
        .overlay(Rectangle().fill(Color(hex: "c8893a")).frame(height: 1), alignment: .top)
    }
}

// MARK: - Stop Visited Badge (overlay on stop number circles)

struct StopVisitedBadge: View {
    let index: Int
    @ObservedObject private var manager = RouteTravelManager.shared

    var body: some View {
        if manager.isTraveling && manager.isStopVisited(index) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(.white)
                .background(Circle().fill(Color(hex: "2d6a4f")).frame(width: 16, height: 16))
                .offset(x: 10, y: -10)
        }
    }
}

// MARK: - Navigate & Visit Button (replaces plain Navigate in stop sheets)

struct NavigateAndVisitButton: View {
    let coordinate: CLLocationCoordinate2D
    let name: String
    let stopIndex: Int
    @ObservedObject private var manager = RouteTravelManager.shared
    @Environment(\.dismiss) var dismiss
    @State private var showNavigation = false

    private var isVisited: Bool { manager.isStopVisited(stopIndex) }

    var body: some View {
        if manager.isActive && !isVisited {
            Button(action: {
                Task {
                    await manager.visitStop(index: stopIndex, name: name)
                    showNavigation = true
                }
            }) {
                HStack {
                    Image(systemName: "location.fill").font(.system(size: 14))
                    Text("Navigate & Mark Visited").font(.custom("DMSans-SemiBold", size: 15))
                }
                .foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(Color(hex: "2d6a4f")).cornerRadius(12)
            }
            .fullScreenCover(isPresented: $showNavigation) {
                InAppNavigationSheet(destination: coordinate, destinationName: name)
            }
        } else if manager.isActive && isVisited {
            HStack {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 16)).foregroundColor(Color(hex: "2d6a4f"))
                Text("Visited").font(.custom("DMSans-SemiBold", size: 15)).foregroundColor(Color(hex: "2d6a4f"))
                Spacer()
                Button(action: { showNavigation = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "map.fill").font(.system(size: 11))
                        Text("Navigate Again").font(.custom("DMSans-Medium", size: 12))
                    }
                    .foregroundColor(Color.theme.text)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.theme.background).cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.theme.border, lineWidth: 1))
                }
                .fullScreenCover(isPresented: $showNavigation) {
                    InAppNavigationSheet(destination: coordinate, destinationName: name)
                }
            }
            .padding(14).background(Color(hex: "2d6a4f").opacity(0.08)).cornerRadius(12)
        } else {
            // Not traveling — Navigate button
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
        }
    }
}
