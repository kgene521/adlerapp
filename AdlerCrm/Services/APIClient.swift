// /AdlerCRM/Services/APIClient.swift  17/05/2026 23:22:00 EDT
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

        HMACSigner.sign(&request)
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

        HMACSigner.sign(&request)
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
        guard let url = URL(string: "\(baseURL)/auth/login") else { throw APIClientError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["username": username, "password": password])
        HMACSigner.sign(&req)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let httpResp = response as? HTTPURLResponse else { throw APIClientError.invalidResponse }
        // Decode response for 200 and 401
        if [200, 401].contains(httpResp.statusCode) {
            return try JSONDecoder().decode(LoginResponse.self, from: data)
        }
        if let err = try? JSONDecoder().decode(APIError.self, from: data) { throw APIClientError.serverError(err.error) }
        throw APIClientError.serverError("HTTP \(httpResp.statusCode)")
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

    func createCollection(locationId: Int, pickupDate: String, gallons: Double, notes: String?, drumId: Int? = nil) async throws -> Collection {
        var body: [String: Any] = [
            "location_id": locationId,
            "pickup_date": pickupDate,
            "gallons": gallons
        ]
        body["notes"] = notes ?? NSNull()
        if let drumId = drumId { body["drum_id"] = drumId }
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

        HMACSigner.sign(&request)
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

    // MARK: - Routes

    func createRoute(name: String, startName: String?, startLat: Double?, startLng: Double?, stops: [[String: Any]], recurrenceStart: String? = nil, recurrenceInterval: Int? = nil, recurrenceUnit: String? = nil) async throws -> SavedRoute {
        var body: [String: Any] = ["name": name, "stops": stops]
        body["start_name"] = startName ?? NSNull()
        body["start_lat"] = startLat ?? NSNull()
        body["start_lng"] = startLng ?? NSNull()
        if let rs = recurrenceStart { body["recurrence_start"] = rs }
        if let ri = recurrenceInterval { body["recurrence_interval"] = ri }
        if let ru = recurrenceUnit { body["recurrence_unit"] = ru }
        return try await request(path: "/routes", method: "POST", body: body)
    }

    func createAndAssignRoute(name: String, startName: String?, startLat: Double?, startLng: Double?, stops: [[String: Any]], employeeId: Int, routeDate: String, saveRoute: Bool, recurrenceStart: String? = nil, recurrenceInterval: Int? = nil, recurrenceUnit: String? = nil) async throws -> SavedRoute {
        var body: [String: Any] = ["name": name, "stops": stops, "employee_id": employeeId, "route_date": routeDate, "save_route": saveRoute]
        body["start_name"] = startName ?? NSNull()
        body["start_lat"] = startLat ?? NSNull()
        body["start_lng"] = startLng ?? NSNull()
        if let rs = recurrenceStart { body["recurrence_start"] = rs }
        if let ri = recurrenceInterval { body["recurrence_interval"] = ri }
        if let ru = recurrenceUnit { body["recurrence_unit"] = ru }
        return try await request(path: "/routes/create-and-assign", method: "POST", body: body)
    }

    func getRoute(id: Int) async throws -> SavedRoute {
        return try await request(path: "/routes/\(id)")
    }

    func updateRoute(id: Int, name: String, startName: String?, startLat: Double?, startLng: Double?, stops: [[String: Any]], recurrenceStart: String? = nil, recurrenceInterval: Int? = nil, recurrenceUnit: String? = nil) async throws -> SavedRoute {
        var body: [String: Any] = ["name": name, "stops": stops]
        body["start_name"] = startName ?? NSNull()
        body["start_lat"] = startLat ?? NSNull()
        body["start_lng"] = startLng ?? NSNull()
        if let rs = recurrenceStart { body["recurrence_start"] = rs }
        if let ri = recurrenceInterval { body["recurrence_interval"] = ri }
        if let ru = recurrenceUnit { body["recurrence_unit"] = ru }
        return try await request(path: "/routes/\(id)", method: "PUT", body: body)
    }

    func deleteRoute(id: Int) async throws {
        struct R: Codable { let ok: Bool? }
        let _: R = try await request(path: "/routes/\(id)", method: "DELETE")
    }

    // MARK: - Route Assignment

    func assignRoute(routeId: Int, employeeId: Int, routeDate: String) async throws -> RouteAssignment {
        return try await request(path: "/routes/\(routeId)/assign", method: "POST", body: [
            "employee_id": employeeId, "route_date": routeDate
        ])
    }

    func getAssignedRoutes(date: String, userId: Int? = nil) async throws -> [SavedRoute] {
        var query = "?date=\(date)"
        if let uid = userId { query += "&user_id=\(uid)" }
        return try await request(path: "/routes/assigned/list\(query)")
    }

    func getAssignedDates(from: String, to: String, userId: Int? = nil) async throws -> [AssignedDateCount] {
        var query = "?from=\(from)&to=\(to)"
        if let uid = userId { query += "&user_id=\(uid)" }
        return try await request(path: "/routes/assigned/dates\(query)")
    }

    func unassignRoute(routeId: Int, employeeId: Int, routeDate: String) async throws {
        struct R: Codable { let ok: Bool? }
        let _: R = try await request(path: "/routes/\(routeId)/unassign", method: "DELETE", body: [
            "employee_id": employeeId, "route_date": routeDate
        ])
    }

    // MARK: - Saved Routes (personal collection)

    func getSavedRoutesList(search: String = "") async throws -> [SavedRoute] {
        var query = ""
        if !search.isEmpty {
            query = "?search=\(search.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? search)"
        }
        return try await request(path: "/routes/saved/list\(query)")
    }

    func saveRouteToCollection(routeId: Int) async throws {
        struct R: Codable { let employee_id: Int?; let route_id: Int? }
        let _: R = try await request(path: "/routes/\(routeId)/save", method: "POST")
    }

    func unsaveRoute(id: Int) async throws {
        struct R: Codable { let ok: Bool? }
        let _: R = try await request(path: "/routes/\(id)/unsave", method: "DELETE")
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

    // MARK: - Business Notes

    func getBusinessNotes(bizId: Int) async throws -> [BusinessNote] {
        return try await request(path: "/business-notes/\(bizId)")
    }

    func createBusinessNote(bizId: Int, text: String) async throws -> BusinessNote {
        return try await request(path: "/business-notes", method: "POST", body: [
            "business_id": bizId,
            "note_text": text
        ])
    }

    func updateBusinessNote(id: Int, text: String) async throws -> BusinessNote {
        return try await request(path: "/business-notes/\(id)", method: "PUT", body: [
            "note_text": text
        ])
    }

    func deleteBusinessNote(id: Int) async throws -> [String: Bool] {
        return try await request(path: "/business-notes/\(id)", method: "DELETE")
    }

    // MARK: - Reports

    func getCollectionSummary(bizId: Int, period: String = "all") async throws -> CollectionSummaryReport {
        return try await request(path: "/report-gen/collection-summary/\(bizId)?period=\(period)")
    }

    func getPickupLog(bizId: Int, period: String = "all") async throws -> [PickupLogEntry] {
        return try await request(path: "/report-gen/pickup-log/\(bizId)?period=\(period)")
    }

    func generateCollectionReport(bizId: Int, from: String?, to: String?) async throws -> GenerateReportResponse {
        var body: [String: Any] = ["business_id": bizId]
        if let from = from { body["from"] = from }
        if let to = to { body["to"] = to }
        return try await request(path: "/report-gen/collection", method: "POST", body: body)
    }

    func getReportHistory(bizId: Int) async throws -> [ReportHistoryEntry] {
        return try await request(path: "/report-gen/history/\(bizId)")
    }

    func downloadReportPDF(reportName: String) async throws -> Data {
        return try await requestData(path: "/report-gen/file/\(reportName)")
    }

    func deleteReports(ids: [Int]) async throws {
        struct DeleteResponse: Codable { let ok: Bool? }
        let body: [String: Any] = ["ids": ids]
        let _: DeleteResponse = try await request(path: "/report-gen/delete", method: "POST", body: body)
    }

    // MARK: - Todos

    func getTodos(date: String) async throws -> [TodoItem] {
        return try await request(path: "/todos?date=\(date)")
    }

    func getTodoDateCounts(from: String, to: String) async throws -> [TodoDateCount] {
        return try await request(path: "/todos/all?from=\(from)&to=\(to)")
    }

    func createTodo(title: String, description: String?, deadlineDate: String, assignedTo: Int? = nil) async throws -> TodoItem {
        var body: [String: Any] = ["title": title, "deadline_date": deadlineDate]
        if let desc = description { body["description"] = desc }
        if let at = assignedTo { body["assigned_to"] = at }
        return try await request(path: "/todos", method: "POST", body: body)
    }

    func updateTodo(id: Int, title: String, description: String?, deadlineDate: String, assignedTo: Int? = nil) async throws -> TodoItem {
        var body: [String: Any] = ["title": title, "deadline_date": deadlineDate]
        if let desc = description { body["description"] = desc }
        if let at = assignedTo { body["assigned_to"] = at }
        return try await request(path: "/todos/\(id)", method: "PUT", body: body)
    }

    func toggleTodo(id: Int) async throws -> TodoItem {
        return try await request(path: "/todos/\(id)/toggle", method: "PUT", body: [:])
    }

    func deleteTodo(id: Int) async throws {
        struct R: Codable { let ok: Bool? }
        let _: R = try await request(path: "/todos/\(id)", method: "DELETE")
    }

    // MARK: - Notifications

    func getNotifications() async throws -> [AppNotification] {
        return try await request(path: "/notifications")
    }

    func getUnreadCount() async throws -> Int {
        struct R: Codable { let count: Int }
        let r: R = try await request(path: "/notifications/unread-count")
        return r.count
    }

    func getNotificationUsers() async throws -> [NotificationUser] {
        return try await request(path: "/notifications/users")
    }

    func sendNotification(toUserId: Int, message: String, priority: String) async throws -> AppNotification {
        return try await request(path: "/notifications", method: "POST", body: [
            "to_user_id": toUserId, "message": message, "priority": priority
        ])
    }

    func markNotificationRead(id: Int) async throws {
        struct R: Codable { let id: Int? }
        let _: R = try await request(path: "/notifications/\(id)/read", method: "PUT", body: [:])
    }

    func markAllNotificationsRead() async throws {
        struct R: Codable { let ok: Bool? }
        let _: R = try await request(path: "/notifications/read-all", method: "PUT", body: [:])
    }

    func deleteNotification(id: Int) async throws {
        struct R: Codable { let ok: Bool? }
        let _: R = try await request(path: "/notifications/\(id)", method: "DELETE")
    }

    // MARK: - Corporate

    func getCorporateDocuments() async throws -> [CorporateDocument] {
        return try await request(path: "/corporate/documents")
    }

    func uploadCorporateDocument(fileData: Data, fileName: String, mimeType: String, docType: String, notes: String?) async throws -> CorporateDocument {
        guard let url = URL(string: "\(baseURL)/corporate/documents/upload") else { throw APIClientError.invalidURL }
        let boundary = UUID().uuidString
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = KeychainHelper.load(key: "adler_token") { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        var body = Data()
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"doc_type\"\r\n\r\n\(docType)\r\n")
        if let notes = notes, !notes.isEmpty { body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"notes\"\r\n\r\n\(notes)\r\n") }
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\nContent-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n")
        req.httpBody = body
        HMACSigner.sign(&req)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let httpResp = response as? HTTPURLResponse else { throw APIClientError.invalidResponse }
        if httpResp.statusCode == 401 { NotificationCenter.default.post(name: Notification.Name("adlerSessionExpired"), object: nil); throw APIClientError.unauthorized("Session expired") }
        if httpResp.statusCode >= 400 { if let err = try? JSONDecoder().decode(APIError.self, from: data) { throw APIClientError.serverError(err.error) }; throw APIClientError.serverError("HTTP \(httpResp.statusCode)") }
        return try JSONDecoder().decode(CorporateDocument.self, from: data)
    }

    func corporateFileURL(id: Int) -> URL? { URL(string: "\(baseURL)/corporate/documents/file/\(id)") }

    func downloadCorporateFile(id: Int) async throws -> Data {
        return try await requestData(path: "/corporate/documents/file/\(id)")
    }

    func deleteCorporateDocument(id: Int) async throws {
        struct R: Codable { let ok: Bool? }
        let _: R = try await request(path: "/corporate/documents/\(id)", method: "DELETE")
    }

    func getCorporateNotes() async throws -> [CorporateNote] {
        return try await request(path: "/corporate/notes")
    }

    func createCorporateNote(text: String) async throws -> CorporateNote {
        return try await request(path: "/corporate/notes", method: "POST", body: ["note_text": text])
    }

    func updateCorporateNote(id: Int, text: String) async throws -> CorporateNote {
        return try await request(path: "/corporate/notes/\(id)", method: "PUT", body: ["note_text": text])
    }

    func deleteCorporateNote(id: Int) async throws {
        struct R: Codable { let ok: Bool? }
        let _: R = try await request(path: "/corporate/notes/\(id)", method: "DELETE")
    }

    // MARK: - Employee Endpoints

    func getEmployees() async throws -> [Employee] {
        return try await request(path: "/employees")
    }

    // MARK: - Audit Log Endpoints

    func getAuditLogs(limit: Int = 100, offset: Int = 0, action: String? = nil, entityType: String? = nil, entityId: Int? = nil, username: String? = nil, userId: Int? = nil, from: String? = nil, to: String? = nil) async throws -> AuditLogResponse {
        var params: [String] = ["limit=\(limit)", "offset=\(offset)"]
        if let action = action, !action.isEmpty { params.append("action=\(action)") }
        if let entityType = entityType, !entityType.isEmpty { params.append("entity_type=\(entityType)") }
        if let entityId = entityId { params.append("entity_id=\(entityId)") }
        if let username = username, !username.isEmpty { params.append("username=\(username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? username)") }
        if let userId = userId { params.append("user_id=\(userId)") }
        if let from = from { params.append("from=\(from)") }
        if let to = to { params.append("to=\(to)") }
        let query = params.joined(separator: "&")
        return try await request(path: "/logs?\(query)")
    }

    func getAuditLogActions() async throws -> [String] {
        return try await request(path: "/logs/actions")
    }

    func getAuditLogEntityTypes() async throws -> [String] {
        return try await request(path: "/logs/entity-types")
    }

    func getAuditLogEntityHistory(entityType: String, entityId: Int) async throws -> [AuditLogEntry] {
        return try await request(path: "/logs/entity/\(entityType)/\(entityId)")
    }

    func getAuditLogStats() async throws -> AuditLogStatsResponse {
        return try await request(path: "/logs/stats")
    }

    func deleteAuditLog(id: Int) async throws {
        struct R: Codable { let ok: Bool? }
        let _: R = try await request(path: "/logs/\(id)", method: "DELETE")
    }

    func purgeAuditLogs(mode: String, from: String? = nil, to: String? = nil, username: String? = nil, days: Int? = nil) async throws -> Int {
        var body: [String: Any] = ["mode": mode]
        if let from = from { body["from"] = from }
        if let to = to { body["to"] = to }
        if let username = username { body["username"] = username }
        if let days = days { body["days"] = days }
        struct R: Codable { let ok: Bool?; let deleted: Int? }
        let r: R = try await request(path: "/logs/purge", method: "POST", body: body)
        return r.deleted ?? 0
    }

    // MARK: - Route Travel Endpoints

    func startTravel(routeName: String, routeId: Int?, latitude: Double, longitude: Double, totalStops: Int) async throws -> TravelSession {
        var body: [String: Any] = ["route_name": routeName, "latitude": latitude, "longitude": longitude, "total_stops": totalStops]
        if let routeId = routeId { body["route_id"] = routeId }
        return try await request(path: "/route-travel/start", method: "POST", body: body)
    }

    func pauseTravel(sessionId: Int, latitude: Double, longitude: Double) async throws -> TravelSession {
        return try await request(path: "/route-travel/\(sessionId)/pause", method: "POST", body: ["latitude": latitude, "longitude": longitude])
    }

    func resumeTravel(sessionId: Int, latitude: Double, longitude: Double) async throws -> TravelSession {
        return try await request(path: "/route-travel/\(sessionId)/resume", method: "POST", body: ["latitude": latitude, "longitude": longitude])
    }

    func endTravel(sessionId: Int, latitude: Double, longitude: Double) async throws -> TravelSession {
        return try await request(path: "/route-travel/\(sessionId)/end", method: "POST", body: ["latitude": latitude, "longitude": longitude])
    }

    func visitStop(sessionId: Int, latitude: Double, longitude: Double, stopIndex: Int, stopName: String?) async throws -> TravelEvent {
        var body: [String: Any] = ["latitude": latitude, "longitude": longitude, "stop_index": stopIndex]
        if let stopName = stopName { body["stop_name"] = stopName }
        return try await request(path: "/route-travel/\(sessionId)/visit-stop", method: "POST", body: body)
    }

    func getActiveTravel() async throws -> TravelSession? {
        // Server returns null if no active session — need custom handling
        let url = URL(string: "\(baseURL)/route-travel/active")!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = KeychainHelper.load(key: "adler_token") {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        HMACSigner.sign(&req)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let httpResp = response as? HTTPURLResponse else { throw APIClientError.invalidResponse }
        if httpResp.statusCode == 401 { NotificationCenter.default.post(name: Notification.Name("adlerSessionExpired"), object: nil); throw APIClientError.unauthorized("Session expired") }
        if httpResp.statusCode >= 400 { throw APIClientError.serverError("HTTP \(httpResp.statusCode)") }
        // Check for null response
        let text = String(data: data, encoding: .utf8) ?? ""
        if text.trimmingCharacters(in: .whitespaces) == "null" { return nil }
        return try JSONDecoder().decode(TravelSession.self, from: data)
    }

    func getTravelSession(id: Int) async throws -> TravelSession {
        return try await request(path: "/route-travel/\(id)")
    }

    func getTravelHistory(userId: Int? = nil, limit: Int = 50, offset: Int = 0) async throws -> TravelHistoryResponse {
        var params = "limit=\(limit)&offset=\(offset)"
        if let userId = userId { params += "&user_id=\(userId)" }
        return try await request(path: "/route-travel/history?\(params)")
    }

    func getTravelUserSummary(userId: Int) async throws -> TravelUserSummary {
        return try await request(path: "/route-travel/user/\(userId)/summary")
    }

    // MARK: - Drum Endpoints (NFC)

    func getDrums(businessId: Int? = nil, locationId: Int? = nil, search: String? = nil) async throws -> [Drum] {
        var params: [String] = []
        if let businessId = businessId { params.append("business_id=\(businessId)") }
        if let locationId = locationId { params.append("location_id=\(locationId)") }
        if let search = search, !search.isEmpty { params.append("search=\(search.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? search)") }
        let query = params.isEmpty ? "" : "?\(params.joined(separator: "&"))"
        return try await request(path: "/drums\(query)")
    }

    func getDrum(id: Int) async throws -> Drum {
        return try await request(path: "/drums/\(id)")
    }

    func lookupDrumByTag(tagId: String) async throws -> Drum {
        let encoded = tagId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? tagId
        return try await request(path: "/drums/tag/\(encoded)")
    }

    func registerDrum(nfcTagId: String, nickname: String?, locationId: Int?, businessId: Int?, latitude: Double?, longitude: Double?, capacityGallons: Int?, tagType: String?) async throws -> Drum {
        var body: [String: Any] = ["nfc_tag_id": nfcTagId]
        if let nickname = nickname { body["nickname"] = nickname }
        if let locationId = locationId { body["location_id"] = locationId }
        if let businessId = businessId { body["business_id"] = businessId }
        if let latitude = latitude { body["latitude"] = latitude }
        if let longitude = longitude { body["longitude"] = longitude }
        if let capacityGallons = capacityGallons { body["capacity_gallons"] = capacityGallons }
        if let tagType = tagType { body["tag_type"] = tagType }
        return try await request(path: "/drums", method: "POST", body: body)
    }

    func updateDrum(id: Int, nickname: String?, locationId: Int?, businessId: Int?, capacityGallons: Int?, status: String?) async throws -> Drum {
        var body: [String: Any] = [:]
        body["nickname"] = nickname ?? NSNull()
        body["location_id"] = locationId ?? NSNull()
        body["business_id"] = businessId ?? NSNull()
        body["capacity_gallons"] = capacityGallons ?? 55
        body["status"] = status ?? "active"
        return try await request(path: "/drums/\(id)", method: "PUT", body: body)
    }

    func scanDrum(id: Int, latitude: Double, longitude: Double) async throws -> DrumScan {
        return try await request(path: "/drums/\(id)/scan", method: "POST", body: ["latitude": latitude, "longitude": longitude])
    }

    func moveDrum(id: Int, locationId: Int?, businessId: Int?, latitude: Double?, longitude: Double?) async throws -> Drum {
        var body: [String: Any] = [:]
        body["location_id"] = locationId ?? NSNull()
        body["business_id"] = businessId ?? NSNull()
        if let latitude = latitude { body["latitude"] = latitude }
        if let longitude = longitude { body["longitude"] = longitude }
        return try await request(path: "/drums/\(id)/move", method: "POST", body: body)
    }

    func retireDrum(id: Int) async throws {
        struct R: Codable { let ok: Bool? }
        let _: R = try await request(path: "/drums/\(id)", method: "DELETE")
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
