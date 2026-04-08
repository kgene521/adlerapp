// /AdlerCRM/Services/RouteEngine.swift  08/04/2026 00:51:00 EDT
import Foundation
import CoreLocation

// MARK: - Constants

let routeContainerCapacity: Double = 50.0  // gallons

// MARK: - Route Stop Model

struct RouteStop: Identifiable {
    let id: Int
    var stopNumber: Int
    let candidate: RouteCandidate
    let coordinate: CLLocationCoordinate2D
    let fillLevel: Double
    let fillPercent: Double
    let daysSincePickup: Int
    let estimatedGallons: Int

    var addressLine: String {
        [candidate.address, candidate.city, candidate.state]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

// MARK: - Route Result

struct RouteResult {
    let stops: [RouteStop]
    let nextReadyDate: Date?
    let nextReadyCount: Int
}

// MARK: - Region Info (for picker)

struct RegionInfo: Identifiable, Hashable {
    let id: Int        // -1 = all
    let name: String
    let centerLat: Double?
    let centerLng: Double?
}

let allRegionsInfo = RegionInfo(id: -1, name: "All Regions", centerLat: nil, centerLng: nil)

// MARK: - Route Engine

enum RouteEngine {

    /// Build region options from candidates
    static func buildRegions(from candidates: [RouteCandidate]) -> [RegionInfo] {
        var seen = Set<Int>()
        var options: [RegionInfo] = []

        for c in candidates {
            if let rid = c.region_id, !seen.contains(rid) {
                let locs = candidates.filter { $0.region_id == rid }
                let lats = locs.compactMap { $0.latitude }
                let lngs = locs.compactMap { $0.longitude }
                let avgLat = lats.isEmpty ? nil : lats.reduce(0, +) / Double(lats.count)
                let avgLng = lngs.isEmpty ? nil : lngs.reduce(0, +) / Double(lngs.count)
                options.append(RegionInfo(id: rid, name: c.region_name ?? "Region \(rid)", centerLat: avgLat, centerLng: avgLng))
                seen.insert(rid)
            }
        }

        options.sort { $0.name < $1.name }
        if options.count > 1 {
            options.insert(allRegionsInfo, at: 0)
        }
        return options
    }

    /// Find the region closest to a given coordinate
    static func closestRegionId(to coord: CLLocationCoordinate2D, from regions: [RegionInfo]) -> Int {
        let regionsOnly = regions.filter { $0.id >= 0 }
        guard !regionsOnly.isEmpty else { return -1 }

        var closestId = regionsOnly.first!.id
        var closestDist = Double.infinity

        for opt in regionsOnly {
            guard let lat = opt.centerLat, let lng = opt.centerLng else { continue }
            let dist = haversine(from: coord, to: CLLocationCoordinate2D(latitude: lat, longitude: lng))
            if dist < closestDist {
                closestDist = dist
                closestId = opt.id
            }
        }
        return closestId
    }

    /// Compute route for a given date, region, start coordinate, and candidates.
    static func computeRoute(
        candidates: [RouteCandidate],
        targetDate: Date,
        regionId: Int,
        startCoord: CLLocationCoordinate2D,
        maxStops: Int = 10
    ) -> RouteResult {
        let calendar = Calendar.current
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"

        // Filter by region
        let filtered: [RouteCandidate]
        if regionId == -1 {
            filtered = candidates
        } else {
            filtered = candidates.filter { $0.region_id == regionId }
        }

        struct Scored {
            let candidate: RouteCandidate
            let coord: CLLocationCoordinate2D
            let fillLevel: Double
            let fillPercent: Double
            let daysSince: Int
            let estGal: Int
            let daysUntilFull: Double
        }

        var scored: [Scored] = []

        for c in filtered {
            guard let lat = c.latitude, let lng = c.longitude else { continue }
            let estGal = c.estimated_gallons ?? 0
            guard estGal > 0 else { continue }

            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            let dailyRate = Double(estGal) / 7.0

            let daysSince: Int
            if let dateStr = c.last_pickup_date,
               let pickupDate = dateFmt.date(from: String(dateStr.prefix(10))) {
                daysSince = max(0, calendar.dateComponents([.day], from: pickupDate, to: targetDate).day ?? 0)
            } else {
                daysSince = 365
            }

            let fillLevel = min(Double(daysSince) * dailyRate, routeContainerCapacity * 2)
            let fillPercent = fillLevel / routeContainerCapacity

            let daysUntilFull: Double
            if fillLevel >= routeContainerCapacity {
                daysUntilFull = 0
            } else {
                daysUntilFull = (routeContainerCapacity - fillLevel) / dailyRate
            }

            scored.append(Scored(
                candidate: c, coord: coord, fillLevel: fillLevel,
                fillPercent: fillPercent, daysSince: daysSince,
                estGal: estGal, daysUntilFull: daysUntilFull
            ))
        }

        let ready = scored.filter { $0.fillLevel >= routeContainerCapacity }

        if ready.isEmpty {
            let notReady = scored.filter { $0.daysUntilFull > 0 }.sorted { $0.daysUntilFull < $1.daysUntilFull }
            if let soonest = notReady.first {
                let nextDate = calendar.date(byAdding: .day, value: Int(ceil(soonest.daysUntilFull)), to: targetDate) ?? targetDate
                let count = notReady.filter { $0.daysUntilFull <= ceil(soonest.daysUntilFull) + 1 }.count
                return RouteResult(stops: [], nextReadyDate: nextDate, nextReadyCount: count)
            }
            return RouteResult(stops: [], nextReadyDate: nil, nextReadyCount: 0)
        }

        let prioritized = ready
            .sorted { $0.fillLevel - routeContainerCapacity > $1.fillLevel - routeContainerCapacity }
            .prefix(maxStops)

        // Nearest-neighbor optimization
        var remaining = Array(prioritized)
        var ordered: [Scored] = []
        var currentPos = startCoord

        while !remaining.isEmpty {
            var nearestIdx = 0
            var nearestDist = Double.infinity
            for (i, s) in remaining.enumerated() {
                let dist = haversine(from: currentPos, to: s.coord)
                if dist < nearestDist {
                    nearestDist = dist
                    nearestIdx = i
                }
            }
            let next = remaining.remove(at: nearestIdx)
            ordered.append(next)
            currentPos = next.coord
        }

        let stops = ordered.enumerated().map { (idx, s) in
            RouteStop(
                id: s.candidate.id, stopNumber: idx + 1,
                candidate: s.candidate, coordinate: s.coord,
                fillLevel: s.fillLevel, fillPercent: s.fillPercent,
                daysSincePickup: s.daysSince, estimatedGallons: s.estGal
            )
        }

        return RouteResult(stops: stops, nextReadyDate: nil, nextReadyCount: 0)
    }

    // MARK: - Haversine

    static func haversine(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let R = 6371000.0
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return R * 2 * atan2(sqrt(h), sqrt(1 - h))
    }
}
