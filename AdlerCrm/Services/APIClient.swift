// AdlerCRM/Services/APIClient.swift  28/03/2026 19:03:37
import Foundation

class APIClient {
    static let shared = APIClient()

    // IMPORTANT: Change this to your actual server URL
    private let baseURL = "http://184.94.215.203/api"

    private init() {}

    // MARK: - Generic Request

    func request<T: Decodable>(
        path: String,
        method: String = "GET",
        body: [String: Any]? = nil,
        token: String? = nil
    ) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw APIClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Use provided token or fall back to stored session token
        let authToken = token ?? KeychainHelper.load(key: "adler_token")
        if let authToken = authToken {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }

        // Handle 401 — token expired
        if httpResponse.statusCode == 401 {
            NotificationCenter.default.post(name: Notification.Name("adlerSessionExpired"), object: nil)
            throw APIClientError.unauthorized("Session expired")
        }

        // Handle other error status codes
        if httpResponse.statusCode >= 400 {
            if let errorResponse = try? JSONDecoder().decode(APIError.self, from: data) {
                throw APIClientError.serverError(errorResponse.error)
            }
            throw APIClientError.serverError("HTTP \(httpResponse.statusCode)")
        }

        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }

    // MARK: - Raw Data Request (for images, PDFs)

    func requestData(
        path: String,
        token: String? = nil
    ) async throws -> Data {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw APIClientError.invalidURL
        }

        var request = URLRequest(url: url)
        let authToken = token ?? KeychainHelper.load(key: "adler_token")
        if let authToken = authToken {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }
        if httpResponse.statusCode == 401 {
            NotificationCenter.default.post(name: Notification.Name("adlerSessionExpired"), object: nil)
            throw APIClientError.unauthorized("Session expired")
        }
        guard httpResponse.statusCode == 200 else {
            throw APIClientError.invalidResponse
        }

        return data
    }

    // MARK: - Auth Endpoints

    func login(username: String, password: String) async throws -> LoginResponse {
        return try await request(
            path: "/auth/login",
            method: "POST",
            body: ["username": username, "password": password]
        )
    }

    func totpSetup(tempToken: String) async throws -> TOTPSetupResponse {
        return try await request(
            path: "/auth/totp/setup",
            method: "POST",
            token: tempToken
        )
    }

    func totpVerify(tempToken: String, code: String) async throws -> TOTPVerifyResponse {
        return try await request(
            path: "/auth/totp/verify",
            method: "POST",
            body: ["code": code],
            token: tempToken
        )
    }

    // MARK: - Password

    func changePassword(oldPassword: String, newPassword: String, totpCode: String) async throws -> [String: Any] {
        let result: [String: String] = try await request(
            path: "/employees/change-password",
            method: "POST",
            body: [
                "old_password": oldPassword,
                "new_password": newPassword,
                "totp_code": totpCode
            ]
        )
        return result as [String: Any]
    }

    // MARK: - Business Endpoints

    func getBusinesses() async throws -> [Business] {
        return try await request(path: "/businesses")
    }

    func getBusiness(id: Int) async throws -> Business {
        return try await request(path: "/businesses/\(id)")
    }

    func createBusiness(name: String, status: String, notes: String?, regionId: Int?) async throws -> Business {
        var body: [String: Any] = ["name": name, "status": status]
        body["notes"] = notes ?? NSNull()
        body["region_id"] = regionId ?? NSNull()
        return try await request(path: "/businesses", method: "POST", body: body)
    }

    func updateBusiness(id: Int, name: String, status: String?, notes: String?, regionId: Int?) async throws -> Business {
        var body: [String: Any] = ["name": name]
        body["status"] = status ?? "active"
        body["notes"] = notes ?? NSNull()
        body["region_id"] = regionId ?? NSNull()
        return try await request(path: "/businesses/\(id)", method: "PUT", body: body)
    }

    // MARK: - Region Endpoints

    func getRegions() async throws -> [Region] {
        return try await request(path: "/regions")
    }

    func createRegion(name: String, notes: String?) async throws -> Region {
        var body: [String: Any] = ["name": name]
        body["notes"] = notes ?? NSNull()
        return try await request(path: "/regions", method: "POST", body: body)
    }

    func updateRegion(id: Int, name: String, notes: String?) async throws -> Region {
        var body: [String: Any] = ["name": name]
        body["notes"] = notes ?? NSNull()
        return try await request(path: "/regions/\(id)", method: "PUT", body: body)
    }

    func deleteRegion(id: Int) async throws -> [String: Bool] {
        return try await request(path: "/regions/\(id)", method: "DELETE")
    }

    func addRegionMember(regionId: Int, userId: Int) async throws -> [String: Bool] {
        return try await request(path: "/regions/\(regionId)/members", method: "POST", body: ["user_id": userId])
    }

    func removeRegionMember(regionId: Int, userId: Int) async throws -> [String: Bool] {
        return try await request(path: "/regions/\(regionId)/members/\(userId)", method: "DELETE")
    }

    // MARK: - Location Endpoints

    func getAllLocations() async throws -> [Location] {
        return try await request(path: "/locations")
    }

    func getAllLocationsIncludingInactive() async throws -> [Location] {
        return try await request(path: "/locations?include_inactive=true")
    }

    func getLocations(bizId: Int) async throws -> [Location] {
        return try await request(path: "/locations/business/\(bizId)")
    }

    func createLocation(bizId: Int, address: String?, city: String?, state: String?, zip: String?, phone: String?, estimatedGallons: Int, pickupFreq: String, latitude: Double?, longitude: Double?) async throws -> Location {
        var body: [String: Any] = [
            "business_id": bizId,
            "estimated_gallons": estimatedGallons,
            "pickup_freq": pickupFreq
        ]
        body["address"] = address ?? NSNull()
        body["city"] = city ?? NSNull()
        body["state"] = state ?? NSNull()
        body["zip"] = zip ?? NSNull()
        body["phone"] = phone ?? NSNull()
        if let lat = latitude { body["latitude"] = lat } else { body["latitude"] = NSNull() }
        if let lng = longitude { body["longitude"] = lng } else { body["longitude"] = NSNull() }
        return try await request(path: "/locations", method: "POST", body: body)
    }

    func updateLocation(id: Int, address: String?, city: String?, state: String?, zip: String?, phone: String?, estimatedGallons: Int, pickupFreq: String, latitude: Double?, longitude: Double?) async throws -> Location {
        var body: [String: Any] = [
            "estimated_gallons": estimatedGallons,
            "pickup_freq": pickupFreq
        ]
        body["address"] = address ?? NSNull()
        body["city"] = city ?? NSNull()
        body["state"] = state ?? NSNull()
        body["zip"] = zip ?? NSNull()
        body["phone"] = phone ?? NSNull()
        body["latitude"] = latitude ?? NSNull()
        body["longitude"] = longitude ?? NSNull()
        return try await request(path: "/locations/\(id)", method: "PUT", body: body)
    }

    func deleteLocation(id: Int) async throws -> [String: Bool] {
        return try await request(path: "/locations/\(id)", method: "DELETE")
    }

    func reactivateLocation(id: Int) async throws -> Location {
        return try await request(path: "/locations/\(id)/reactivate", method: "PATCH")
    }

    // MARK: - Collection Endpoints

    func getCollections() async throws -> [Collection] {
        return try await request(path: "/collections")
    }

    func getCollections(bizId: Int) async throws -> [Collection] {
        return try await request(path: "/collections/business/\(bizId)")
    }

    func createCollection(locationId: Int, pickupDate: String, gallons: Double, notes: String?) async throws -> Collection {
        var body: [String: Any] = [
            "location_id": locationId,
            "pickup_date": pickupDate,
            "gallons": gallons
        ]
        body["notes"] = notes ?? NSNull()
        return try await request(path: "/collections", method: "POST", body: body)
    }

    func deleteCollection(id: Int) async throws -> [String: Bool] {
        return try await request(path: "/collections/\(id)", method: "DELETE")
    }

    // MARK: - Document Endpoints

    func getDocuments(bizId: Int) async throws -> [BusinessDocument] {
        return try await request(path: "/documents/business/\(bizId)")
    }

    func deleteDocument(id: Int) async throws -> [String: Bool] {
        return try await request(path: "/documents/\(id)", method: "DELETE")
    }

    func uploadDocument(fileData: Data, fileName: String, mimeType: String, businessId: Int, docType: String, notes: String?) async throws -> BusinessDocument {
        guard let url = URL(string: "\(baseURL)/documents/upload") else {
            throw APIClientError.invalidURL
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        if let token = KeychainHelper.load(key: "adler_token") {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body = Data()
        // business_id field
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"business_id\"\r\n\r\n\(businessId)\r\n")
        // doc_type field
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"doc_type\"\r\n\r\n\(docType)\r\n")
        // notes field
        if let notes = notes, !notes.isEmpty {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"notes\"\r\n\r\n\(notes)\r\n")
        }
        // file field
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\nContent-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n")

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }
        if httpResponse.statusCode == 401 {
            NotificationCenter.default.post(name: Notification.Name("adlerSessionExpired"), object: nil)
            throw APIClientError.unauthorized("Session expired")
        }
        if httpResponse.statusCode >= 400 {
            if let err = try? JSONDecoder().decode(APIError.self, from: data) {
                throw APIClientError.serverError(err.error)
            }
            throw APIClientError.serverError("HTTP \(httpResponse.statusCode)")
        }
        return try JSONDecoder().decode(BusinessDocument.self, from: data)
    }

    func documentFileURL(id: Int) -> URL? {
        URL(string: "\(baseURL)/documents/file/\(id)")
    }

    // MARK: - Saved Routes

    func getSavedRoutes(scope: String = "mine", search: String = "", period: String = "") async throws -> [SavedRoute] {
        var query = "?scope=\(scope)"
        if !search.isEmpty { query += "&search=\(search.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? search)" }
        if !period.isEmpty { query += "&period=\(period)" }
        return try await request(path: "/saved-routes\(query)")
    }

    func saveRoute(name: String, startName: String?, startLat: Double?, startLng: Double?, stops: [[String: Any]]) async throws -> SavedRoute {
        var body: [String: Any] = ["name": name, "stops": stops]
        body["start_name"] = startName ?? NSNull()
        body["start_lat"] = startLat ?? NSNull()
        body["start_lng"] = startLng ?? NSNull()
        return try await request(path: "/saved-routes", method: "POST", body: body)
    }

    func deleteSavedRoute(id: Int) async throws -> [String: Bool] {
        return try await request(path: "/saved-routes/\(id)", method: "DELETE")
    }

    func updateSavedRoute(id: Int, name: String, startName: String?, startLat: Double?, startLng: Double?, stops: [[String: Any]]) async throws -> SavedRoute {
        var body: [String: Any] = ["name": name, "stops": stops]
        body["start_name"] = startName ?? NSNull()
        body["start_lat"] = startLat ?? NSNull()
        body["start_lng"] = startLng ?? NSNull()
        return try await request(path: "/saved-routes/\(id)", method: "PUT", body: body)
    }

    // MARK: - Contact Endpoints

    func getContacts(bizId: Int) async throws -> [BusinessContact] {
        return try await request(path: "/contacts/business/\(bizId)")
    }

    func createContact(bizId: Int, name: String, title: String?, phone: String?, email: String?, isPrimary: Bool) async throws -> BusinessContact {
        var body: [String: Any] = ["business_id": bizId, "name": name, "is_primary": isPrimary]
        body["title"] = title ?? NSNull()
        body["phone"] = phone ?? NSNull()
        body["email"] = email ?? NSNull()
        return try await request(path: "/contacts", method: "POST", body: body)
    }

    func updateContact(id: Int, name: String, title: String?, phone: String?, email: String?, isPrimary: Bool) async throws -> BusinessContact {
        var body: [String: Any] = ["name": name, "is_primary": isPrimary]
        body["title"] = title ?? NSNull()
        body["phone"] = phone ?? NSNull()
        body["email"] = email ?? NSNull()
        return try await request(path: "/contacts/\(id)", method: "PUT", body: body)
    }

    func deleteContact(id: Int) async throws -> [String: Bool] {
        return try await request(path: "/contacts/\(id)", method: "DELETE")
    }

    // MARK: - Event Endpoints

    func getEvents() async throws -> [ContactEvent] {
        return try await request(path: "/events")
    }

    func getEvents(bizId: Int) async throws -> [ContactEvent] {
        return try await request(path: "/events/business/\(bizId)")
    }

    func createEvent(bizId: Int, locationId: Int?, contactId: Int?, eventDate: String, method: String, subject: String, notes: String?, followUpRequired: Bool, followUpDate: String?) async throws -> ContactEvent {
        var body: [String: Any] = [
            "business_id": bizId,
            "event_date": eventDate,
            "method": method,
            "subject": subject,
            "follow_up_required": followUpRequired
        ]
        body["location_id"] = locationId ?? NSNull()
        body["business_contact_id"] = contactId ?? NSNull()
        body["notes"] = notes ?? NSNull()
        body["follow_up_date"] = followUpDate ?? NSNull()
        return try await request(path: "/events", method: "POST", body: body)
    }

    // MARK: - Route Planner Endpoints

    func getRouteCandidates() async throws -> [RouteCandidate] {
        return try await request(path: "/route-planner/candidates")
    }

    // MARK: - Employee Endpoints

    func getEmployees() async throws -> [Employee] {
        return try await request(path: "/employees")
    }
}

// MARK: - Error Types

enum APIClientError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized(String)
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .invalidResponse: return "Invalid server response"
        case .unauthorized(let msg): return msg
        case .serverError(let msg): return msg
        }
    }
}

// MARK: - Keychain Helper

class KeychainHelper {
    static func save(key: String, value: String) {
        let data = value.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Data Helper for Multipart

extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
