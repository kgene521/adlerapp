// /AdlerCRM/Services/RouteTravelManager.swift  16/04/2026 02:22:00 EDT
import Foundation
import Combine
import CoreLocation
import SwiftUI

@MainActor
class RouteTravelManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = RouteTravelManager()

    // MARK: - Published State

    @Published var activeSession: TravelSession?
    @Published var visitedStopIndices: Set<Int> = []
    @Published var isLoading = false
    @Published var error: String?

    var isActive: Bool { activeSession?.status == "active" }
    var isPaused: Bool { activeSession?.status == "paused" }
    var isTraveling: Bool { isActive || isPaused }
    var sessionId: Int? { activeSession?.id }

    // MARK: - Location

    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocationCoordinate2D?
    private var locationContinuation: CheckedContinuation<CLLocationCoordinate2D, Error>?

    // MARK: - Persistence Keys

    private let kSessionId = "travel_session_id"
    private let kRouteName = "travel_route_name"
    private let kRouteId = "travel_route_id"
    private let kStatus = "travel_status"
    private let kVisitedStops = "travel_visited_stops"
    private let kTotalStops = "travel_total_stops"
    private let kStartedAt = "travel_started_at"

    // MARK: - Init

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        loadFromDisk()
    }

    // MARK: - Location Delegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            currentLocation = loc.coordinate
            if let cont = locationContinuation {
                locationContinuation = nil
                cont.resume(returning: loc.coordinate)
            }
            locationManager.stopUpdatingLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            if let cont = locationContinuation {
                locationContinuation = nil
                cont.resume(throwing: error)
            }
        }
    }

    private func getLocation() async throws -> CLLocationCoordinate2D {
        // If we have a recent location, use it
        if let loc = currentLocation { return loc }

        locationManager.startUpdatingLocation()
        return try await withCheckedThrowingContinuation { cont in
            locationContinuation = cont
            // Timeout after 10 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                guard let self = self else { return }
                if let c = self.locationContinuation {
                    self.locationContinuation = nil
                    // Fall back to a default if we can't get location
                    if let loc = self.currentLocation {
                        c.resume(returning: loc)
                    } else {
                        c.resume(throwing: TravelError.locationUnavailable)
                    }
                }
            }
        }
    }

    // MARK: - Persistence

    private func saveToDisk() {
        let ud = UserDefaults.standard
        if let session = activeSession {
            ud.set(session.id, forKey: kSessionId)
            ud.set(session.route_name, forKey: kRouteName)
            ud.set(session.route_id, forKey: kRouteId)
            ud.set(session.status, forKey: kStatus)
            ud.set(session.total_stops, forKey: kTotalStops)
            ud.set(session.started_at, forKey: kStartedAt)
            ud.set(Array(visitedStopIndices), forKey: kVisitedStops)
        } else {
            clearDisk()
        }
    }

    private func loadFromDisk() {
        let ud = UserDefaults.standard
        guard ud.integer(forKey: kSessionId) != 0 else { return }
        let status = ud.string(forKey: kStatus) ?? "active"
        if status == "completed" { clearDisk(); return }

        // Restore visited stops from disk
        let visited = ud.array(forKey: kVisitedStops) as? [Int] ?? []
        visitedStopIndices = Set(visited)

        // We'll sync with server on next syncWithServer() call
        // For now, mark that we have a pending session
    }

    private func clearDisk() {
        let ud = UserDefaults.standard
        for key in [kSessionId, kRouteName, kRouteId, kStatus, kVisitedStops, kTotalStops, kStartedAt] {
            ud.removeObject(forKey: key)
        }
    }

    // MARK: - Server Sync

    func syncWithServer() async {
        do {
            let session = try await APIClient.shared.getActiveTravel()
            if let session = session {
                activeSession = session
                // Rebuild visited stops from events
                if let events = session.events {
                    visitedStopIndices = Set(events.filter { $0.action == "visit-stop" }.compactMap { $0.stop_index })
                }
                saveToDisk()
            } else {
                // No active session on server
                activeSession = nil
                visitedStopIndices = []
                clearDisk()
            }
        } catch {
            // If server is unreachable, keep local state
            let ud = UserDefaults.standard
            let savedId = ud.integer(forKey: kSessionId)
            if savedId != 0 && activeSession == nil {
                // We have a local session but couldn't reach server — keep the local state
                // The user can still see that a session was active
            }
        }
    }

    // MARK: - Actions

    func startTravel(routeName: String, routeId: Int?, totalStops: Int) async {
        isLoading = true
        error = nil
        do {
            let coord = try await getLocation()
            let session = try await APIClient.shared.startTravel(
                routeName: routeName, routeId: routeId,
                latitude: coord.latitude, longitude: coord.longitude,
                totalStops: totalStops
            )
            activeSession = session
            visitedStopIndices = []
            saveToDisk()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func pauseTravel() async {
        guard let sid = sessionId else { return }
        isLoading = true
        error = nil
        do {
            let coord = try await getLocation()
            let session = try await APIClient.shared.pauseTravel(sessionId: sid, latitude: coord.latitude, longitude: coord.longitude)
            activeSession = session
            saveToDisk()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func resumeTravel() async {
        guard let sid = sessionId else { return }
        isLoading = true
        error = nil
        do {
            let coord = try await getLocation()
            let session = try await APIClient.shared.resumeTravel(sessionId: sid, latitude: coord.latitude, longitude: coord.longitude)
            activeSession = session
            saveToDisk()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func endTravel() async {
        guard let sid = sessionId else { return }
        isLoading = true
        error = nil
        do {
            let coord = try await getLocation()
            let _ = try await APIClient.shared.endTravel(sessionId: sid, latitude: coord.latitude, longitude: coord.longitude)
            activeSession = nil
            visitedStopIndices = []
            clearDisk()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func visitStop(index: Int, name: String?) async {
        guard let sid = sessionId, isActive else { return }
        do {
            let coord = try await getLocation()
            let _ = try await APIClient.shared.visitStop(
                sessionId: sid,
                latitude: coord.latitude, longitude: coord.longitude,
                stopIndex: index, stopName: name
            )
            visitedStopIndices.insert(index)
            saveToDisk()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func isStopVisited(_ index: Int) -> Bool {
        visitedStopIndices.contains(index)
    }

    /// Check if the current active session matches a given route
    func isSessionForRoute(name: String?, routeId: Int?) -> Bool {
        guard let session = activeSession else { return false }
        if let routeId = routeId, session.route_id == routeId { return true }
        if let name = name, session.route_name == name { return true }
        return false
    }
}

// MARK: - Error

enum TravelError: LocalizedError {
    case locationUnavailable

    var errorDescription: String? {
        switch self {
        case .locationUnavailable: return "Unable to get your current location. Please check location permissions."
        }
    }
}
