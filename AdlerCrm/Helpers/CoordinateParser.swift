// /AdlerCRM/Helpers/CoordinateParser.swift  10/04/2026 23:14:00 EDT
import SwiftUI

enum CoordinateParser {
    /// Attempts to parse a pasted coordinate string and return (latitude, longitude).
    /// Supports formats:
    ///   "37.27100° N, -79.94140° W"
    ///   "37.27100°N, 79.94140°W"
    ///   "37.27100 N, 79.94140 W"
    ///   "37.27100, -79.94140"
    /// Returns nil if the string doesn't match a coordinate pair pattern.
    static func parse(_ input: String) -> (lat: String, lng: String)? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if it looks like a coordinate pair (contains comma separating two parts)
        let parts = trimmed.components(separatedBy: ",")
        guard parts.count == 2 else { return nil }

        let rawLat = parts[0].trimmingCharacters(in: .whitespaces)
        let rawLng = parts[1].trimmingCharacters(in: .whitespaces)

        guard let lat = parseComponent(rawLat, negativeSuffix: "S"),
              let lng = parseComponent(rawLng, negativeSuffix: "W") else {
            return nil
        }

        return (lat: lat, lng: lng)
    }

    /// Parse a single coordinate component, stripping degree symbols and direction letters.
    /// "37.27100° N" → "37.27100"
    /// "-79.94140° W" → "-79.94140"
    /// "79.94140° W" → "-79.94140" (W means negative)
    /// "37.27100" → "37.27100"
    private static func parseComponent(_ raw: String, negativeSuffix: String) -> String? {
        var cleaned = raw

        // Detect direction suffix (N/S/E/W)
        let upper = cleaned.uppercased()
        let hasNegativeSuffix = upper.hasSuffix(negativeSuffix) || upper.hasSuffix("S") && negativeSuffix == "S"

        // Remove direction letters
        cleaned = cleaned.replacingOccurrences(of: "N", with: "", options: .caseInsensitive)
        cleaned = cleaned.replacingOccurrences(of: "S", with: "", options: .caseInsensitive)
        cleaned = cleaned.replacingOccurrences(of: "E", with: "", options: .caseInsensitive)
        cleaned = cleaned.replacingOccurrences(of: "W", with: "", options: .caseInsensitive)

        // Remove degree symbol and any extra whitespace
        cleaned = cleaned.replacingOccurrences(of: "°", with: "")
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)

        // Validate it's a number
        guard let value = Double(cleaned) else { return nil }

        // Apply negative for W or S direction
        if hasNegativeSuffix && value > 0 {
            return String(format: "%.6f", -value)
        }

        return String(format: "%.6f", value)
    }
}

// MARK: - View Modifier for Coordinate Paste Detection

struct CoordinatePasteModifier: ViewModifier {
    @Binding var latitude: String
    @Binding var longitude: String

    func body(content: Content) -> some View {
        content
            .onChange(of: latitude) { _, newValue in
                tryParse(newValue, isLat: true)
            }
            .onChange(of: longitude) { _, newValue in
                tryParse(newValue, isLat: false)
            }
    }

    private func tryParse(_ value: String, isLat: Bool) {
        // Only try parsing if the value looks like it contains a comma (pasted pair)
        guard value.contains(",") else { return }
        guard let parsed = CoordinateParser.parse(value) else { return }
        latitude = parsed.lat
        longitude = parsed.lng
    }
}

extension View {
    /// Attach to a container holding lat/lng fields. Detects pasted coordinate
    /// pairs in either field and auto-splits into both bindings.
    func coordinatePaste(latitude: Binding<String>, longitude: Binding<String>) -> some View {
        modifier(CoordinatePasteModifier(latitude: latitude, longitude: longitude))
    }
}
