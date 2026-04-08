// AdlerCRM/Models/Models.swift  03/04/2026 02:16:32
import Foundation

// MARK: - Flexible Decoding Helpers
// PostgreSQL's NUMERIC type is returned as a string by the Node.js pg driver.
// These helpers let Swift decode a JSON value that might be either a number or a string.

extension KeyedDecodingContainer {
    func flexibleDouble(forKey key: Key) throws -> Double? {
        if let val = try? decode(Double.self, forKey: key) { return val }
        if let str = try? decode(String.self, forKey: key) { return Double(str) }
        return nil
    }

    func flexibleInt(forKey key: Key) throws -> Int? {
        if let val = try? decode(Int.self, forKey: key) { return val }
        if let str = try? decode(String.self, forKey: key) { return Int(str) }
        if let dbl = try? decode(Double.self, forKey: key) { return Int(dbl) }
        return nil
    }
}

// MARK: - Auth Models

struct LoginResponse: Codable {
    let totp_required: Bool?
    let totp_setup_needed: Bool?
    let temp_token: String?
    let token: String?
    let user: UserInfo?
    let error: String?
    // Lockout fields
    let locked: Bool?
    let locked_until: String?
    let retry_after_minutes: Int?
    let consecutive_failures: Int?
}

struct TOTPSetupResponse: Codable {
    let qr: String       // Base64 data URL for QR code image
    let secret: String   // Manual entry key
    let uri: String
}

struct TOTPVerifyResponse: Codable {
    let token: String
    let user: UserInfo
    let password_expired: Bool?
}

struct UserInfo: Codable, Identifiable {
    let id: Int
    let name: String
    let role: String?
}

struct APIError: Codable {
    let error: String
}

// MARK: - Business Model

struct Business: Identifiable {
    let id: Int
    let name: String
    let type: String?
    let status: String?
    let notes: String?
    let region_id: Int?
    let region_name: String?
    let created_by: Int?
    let created_by_name: String?
    let created_by_username: String?
    let location_count: Int?
    let total_est_gallons: Int?
    let first_lat: Double?
    let first_lng: Double?
    let first_pickup_freq: String?
    let first_loc_id: Int?
    let first_address: String?
    let first_city: String?
    let is_deleted: Bool?
    let created_at: String?
}

extension Business: Codable {
    enum CodingKeys: String, CodingKey {
        case id, name, type, status, notes
        case region_id, region_name
        case created_by, created_by_name, created_by_username
        case location_count, total_est_gallons
        case first_lat, first_lng
        case first_pickup_freq, first_loc_id
        case first_address, first_city
        case is_deleted, created_at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        type = try? c.decode(String.self, forKey: .type)
        status = try? c.decode(String.self, forKey: .status)
        notes = try? c.decode(String.self, forKey: .notes)
        region_id = try c.flexibleInt(forKey: .region_id)
        region_name = try? c.decode(String.self, forKey: .region_name)
        created_by = try c.flexibleInt(forKey: .created_by)
        created_by_name = try? c.decode(String.self, forKey: .created_by_name)
        created_by_username = try? c.decode(String.self, forKey: .created_by_username)
        location_count = try c.flexibleInt(forKey: .location_count)
        total_est_gallons = try c.flexibleInt(forKey: .total_est_gallons)
        first_lat = try c.flexibleDouble(forKey: .first_lat)
        first_lng = try c.flexibleDouble(forKey: .first_lng)
        first_pickup_freq = try? c.decode(String.self, forKey: .first_pickup_freq)
        first_loc_id = try c.flexibleInt(forKey: .first_loc_id)
        first_address = try? c.decode(String.self, forKey: .first_address)
        first_city = try? c.decode(String.self, forKey: .first_city)
        is_deleted = try? c.decode(Bool.self, forKey: .is_deleted)
        created_at = try? c.decode(String.self, forKey: .created_at)
    }
}

// MARK: - Region

struct Region: Codable, Identifiable {
    let id: Int
    let name: String
    let notes: String?
    let is_deleted: Bool?
    let created_at: String?
    var members: [RegionMember]?
}

struct RegionMember: Codable, Identifiable {
    var id: Int { user_id }
    let membership_id: Int?
    let user_id: Int
    let name: String
    let username: String
    let role: String
}

// MARK: - Location

struct Location: Identifiable {
    let id: Int
    let business_id: Int
    let address: String?
    let city: String?
    let state: String?
    let zip: String?
    let phone: String?
    let estimated_gallons: Int?
    let pickup_freq: String?
    let latitude: Double?
    let longitude: Double?
    let business_name: String?
    let created_by_name: String?
    let total_collected: Double?
    let collection_count: Int?
    let is_deleted: Bool?
    let created_at: String?
}

extension Location: Codable {
    enum CodingKeys: String, CodingKey {
        case id, business_id, address, city, state, zip, phone
        case estimated_gallons, pickup_freq, latitude, longitude
        case business_name, created_by_name
        case total_collected, collection_count
        case is_deleted, created_at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        business_id = try c.decode(Int.self, forKey: .business_id)
        address = try? c.decode(String.self, forKey: .address)
        city = try? c.decode(String.self, forKey: .city)
        state = try? c.decode(String.self, forKey: .state)
        zip = try? c.decode(String.self, forKey: .zip)
        phone = try? c.decode(String.self, forKey: .phone)
        estimated_gallons = try c.flexibleInt(forKey: .estimated_gallons)
        pickup_freq = try? c.decode(String.self, forKey: .pickup_freq)
        latitude = try c.flexibleDouble(forKey: .latitude)
        longitude = try c.flexibleDouble(forKey: .longitude)
        business_name = try? c.decode(String.self, forKey: .business_name)
        created_by_name = try? c.decode(String.self, forKey: .created_by_name)
        total_collected = try c.flexibleDouble(forKey: .total_collected)
        collection_count = try c.flexibleInt(forKey: .collection_count)
        is_deleted = try? c.decode(Bool.self, forKey: .is_deleted)
        created_at = try? c.decode(String.self, forKey: .created_at)
    }
}

// MARK: - Collection

struct Collection: Identifiable {
    let id: Int
    let location_id: Int
    let user_id: Int?
    let pickup_date: String?
    let gallons: Double?
    let notes: String?
    let location_address: String?
    let location_city: String?
    let business_id: Int?
    let business_name: String?
    let employee_name: String?
    let is_deleted: Bool?
    let created_at: String?
}

extension Collection: Codable {
    enum CodingKeys: String, CodingKey {
        case id, location_id, user_id, pickup_date, gallons, notes
        case location_address, location_city
        case business_id, business_name, employee_name
        case is_deleted, created_at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        location_id = try c.decode(Int.self, forKey: .location_id)
        user_id = try c.flexibleInt(forKey: .user_id)
        pickup_date = try? c.decode(String.self, forKey: .pickup_date)
        gallons = try c.flexibleDouble(forKey: .gallons)
        notes = try? c.decode(String.self, forKey: .notes)
        location_address = try? c.decode(String.self, forKey: .location_address)
        location_city = try? c.decode(String.self, forKey: .location_city)
        business_id = try c.flexibleInt(forKey: .business_id)
        business_name = try? c.decode(String.self, forKey: .business_name)
        employee_name = try? c.decode(String.self, forKey: .employee_name)
        is_deleted = try? c.decode(Bool.self, forKey: .is_deleted)
        created_at = try? c.decode(String.self, forKey: .created_at)
    }
}

// MARK: - Business Contact

struct BusinessContact: Codable, Identifiable {
    let id: Int
    let business_id: Int
    let location_id: Int?
    let name: String
    let title: String?
    let phone: String?
    let email: String?
    let is_primary: Bool?
    let created_by_name: String?
    let is_deleted: Bool?
    let created_at: String?
}

// MARK: - Contact Event

struct ContactEvent: Codable, Identifiable {
    let id: Int
    let business_id: Int
    let location_id: Int?
    let user_id: Int?
    let business_contact_id: Int?
    let event_date: String?
    let method: String?
    let subject: String?
    let notes: String?
    let follow_up_required: Bool?
    let follow_up_date: String?
    let business_name: String?
    let location_address: String?
    let employee_name: String?
    let contact_name: String?
    let is_deleted: Bool?
    let created_at: String?
}

// MARK: - Business Note

struct BusinessNote: Codable, Identifiable {
    let id: Int
    let business_id: Int
    let note_text: String
    let created_by: Int?
    let created_by_name: String?
    let is_deleted: Bool?
    let created_at: String?
}

// MARK: - Employee

struct Employee: Codable, Identifiable {
    let id: Int
    let username: String
    let name: String
    let role: String?
    let email: String?
    let phone: String?
    let is_active: Bool?
    let totp_enabled: Bool?
    let created_at: String?
}

// MARK: - Business Document

struct BusinessDocument: Codable, Identifiable {
    let id: Int
    let business_id: Int
    let doc_type: String   // "agreement" or "photo"
    let file_name: String?
    let original_name: String?
    let file_path: String?
    let notes: String?
    let uploaded_by: Int?
    let uploaded_by_name: String?
    let is_deleted: Bool?
    let created_at: String?
}

// MARK: - Route Candidate

struct RouteCandidate: Identifiable {
    let id: Int
    let business_id: Int
    let address: String?
    let city: String?
    let state: String?
    let zip: String?
    let phone: String?
    let estimated_gallons: Int?
    let pickup_freq: String?
    let latitude: Double?
    let longitude: Double?
    let business_name: String?
    let business_status: String?
    let region_id: Int?
    let region_name: String?
    let last_pickup_date: String?
    let collection_count: Int?
    let total_collected: Double?
}

extension RouteCandidate: Codable {
    enum CodingKeys: String, CodingKey {
        case id, business_id, address, city, state, zip, phone
        case estimated_gallons, pickup_freq, latitude, longitude
        case business_name, business_status
        case region_id, region_name
        case last_pickup_date, collection_count, total_collected
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        business_id = try c.decode(Int.self, forKey: .business_id)
        address = try? c.decode(String.self, forKey: .address)
        city = try? c.decode(String.self, forKey: .city)
        state = try? c.decode(String.self, forKey: .state)
        zip = try? c.decode(String.self, forKey: .zip)
        phone = try? c.decode(String.self, forKey: .phone)
        estimated_gallons = try c.flexibleInt(forKey: .estimated_gallons)
        pickup_freq = try? c.decode(String.self, forKey: .pickup_freq)
        latitude = try c.flexibleDouble(forKey: .latitude)
        longitude = try c.flexibleDouble(forKey: .longitude)
        business_name = try? c.decode(String.self, forKey: .business_name)
        business_status = try? c.decode(String.self, forKey: .business_status)
        region_id = try c.flexibleInt(forKey: .region_id)
        region_name = try? c.decode(String.self, forKey: .region_name)
        last_pickup_date = try? c.decode(String.self, forKey: .last_pickup_date)
        collection_count = try c.flexibleInt(forKey: .collection_count)
        total_collected = try c.flexibleDouble(forKey: .total_collected)
    }
}

// MARK: - Saved Route

struct SavedRouteStop: Codable {
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let source_type: String  // "business" or "manual"
    let business_id: Int?
    let location_id: Int?
}

struct SavedRoute: Codable, Identifiable {
    let id: Int
    let name: String
    let user_id: Int
    let start_name: String?
    let start_lat: Double?
    let start_lng: Double?
    let stops: [SavedRouteStop]?
    let user_name: String?
    let username: String?
    let is_deleted: Bool?
    let created_at: String?

    // Decode stops from JSONB string or array
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        user_id = try c.decode(Int.self, forKey: .user_id)
        start_name = try? c.decode(String.self, forKey: .start_name)
        start_lat = try? c.decode(Double.self, forKey: .start_lat)
        start_lng = try? c.decode(Double.self, forKey: .start_lng)
        user_name = try? c.decode(String.self, forKey: .user_name)
        username = try? c.decode(String.self, forKey: .username)
        is_deleted = try? c.decode(Bool.self, forKey: .is_deleted)
        created_at = try? c.decode(String.self, forKey: .created_at)

        // stops can come as a JSON array or a JSON string
        if let arr = try? c.decode([SavedRouteStop].self, forKey: .stops) {
            stops = arr
        } else if let str = try? c.decode(String.self, forKey: .stops),
                  let data = str.data(using: .utf8),
                  let arr = try? JSONDecoder().decode([SavedRouteStop].self, from: data) {
            stops = arr
        } else {
            stops = nil
        }
    }
}

// MARK: - Report Models

struct CollectionSummary: Codable {
    let total_gallons: Double?
    let total_pickups: Int?
    let avg_gallons_per_pickup: Double?
    let first_pickup: String?
    let last_pickup: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        total_gallons = try c.flexibleDouble(forKey: .total_gallons)
        total_pickups = try c.flexibleInt(forKey: .total_pickups)
        avg_gallons_per_pickup = try c.flexibleDouble(forKey: .avg_gallons_per_pickup)
        first_pickup = try? c.decode(String.self, forKey: .first_pickup)
        last_pickup = try? c.decode(String.self, forKey: .last_pickup)
    }
}

struct MonthlyBreakdown: Codable, Identifiable {
    var id: String { month }
    let month: String
    let gallons: Double?
    let pickups: Int?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        month = try c.decode(String.self, forKey: .month)
        gallons = try c.flexibleDouble(forKey: .gallons)
        pickups = try c.flexibleInt(forKey: .pickups)
    }
}

struct LocationBreakdown: Codable, Identifiable {
    let location_id: Int
    let location_label: String?
    let gallons: Double?
    let pickups: Int?
    var id: Int { location_id }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        location_id = try c.decode(Int.self, forKey: .location_id)
        location_label = try? c.decode(String.self, forKey: .location_label)
        gallons = try c.flexibleDouble(forKey: .gallons)
        pickups = try c.flexibleInt(forKey: .pickups)
    }
}

struct CollectionSummaryReport: Codable {
    let summary: CollectionSummary
    let monthly: [MonthlyBreakdown]
    let by_location: [LocationBreakdown]
}

struct PickupLogEntry: Codable, Identifiable {
    let id: Int
    let pickup_date: String?
    let gallons: Double?
    let notes: String?
    let location_address: String?
    let location_city: String?
    let employee_name: String?
    let created_at: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        pickup_date = try? c.decode(String.self, forKey: .pickup_date)
        gallons = try c.flexibleDouble(forKey: .gallons)
        notes = try? c.decode(String.self, forKey: .notes)
        location_address = try? c.decode(String.self, forKey: .location_address)
        location_city = try? c.decode(String.self, forKey: .location_city)
        employee_name = try? c.decode(String.self, forKey: .employee_name)
        created_at = try? c.decode(String.self, forKey: .created_at)
    }
}

// MARK: - Report History Models

struct ReportHistoryEntry: Codable, Identifiable {
    let id: Int
    let report_name: String?
    let business_id: Int?
    let business_name: String?
    let file_path: String?
    let period_from: String?
    let period_to: String?
    let total_gallons: Double?
    let generated_by: Int?
    let generated_by_name: String?
    let created_at: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        report_name = try? c.decode(String.self, forKey: .report_name)
        business_id = try c.flexibleInt(forKey: .business_id)
        business_name = try? c.decode(String.self, forKey: .business_name)
        file_path = try? c.decode(String.self, forKey: .file_path)
        period_from = try? c.decode(String.self, forKey: .period_from)
        period_to = try? c.decode(String.self, forKey: .period_to)
        total_gallons = try c.flexibleDouble(forKey: .total_gallons)
        generated_by = try c.flexibleInt(forKey: .generated_by)
        generated_by_name = try? c.decode(String.self, forKey: .generated_by_name)
        created_at = try? c.decode(String.self, forKey: .created_at)
    }
}

struct GenerateReportResponse: Codable {
    let ok: Bool?
    let report: GeneratedReportInfo?
}

struct GeneratedReportInfo: Codable {
    let id: Int?
    let report_name: String?
    let business_name: String?
    let total_gallons: Double?
    let collection_count: Int?
    let period: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.flexibleInt(forKey: .id)
        report_name = try? c.decode(String.self, forKey: .report_name)
        business_name = try? c.decode(String.self, forKey: .business_name)
        total_gallons = try c.flexibleDouble(forKey: .total_gallons)
        collection_count = try c.flexibleInt(forKey: .collection_count)
        period = try? c.decode(String.self, forKey: .period)
    }
}

// MARK: - Todo Model

struct TodoItem: Codable, Identifiable {
    let id: Int
    let title: String
    let description: String?
    let deadline_date: String?
    let date_entered: String?
    let date_done: String?
    let is_done: Bool?
    let user_id: Int?
    let user_name: String?
    let is_deleted: Bool?
    let created_at: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        description = try? c.decode(String.self, forKey: .description)
        deadline_date = try? c.decode(String.self, forKey: .deadline_date)
        date_entered = try? c.decode(String.self, forKey: .date_entered)
        date_done = try? c.decode(String.self, forKey: .date_done)
        is_done = try? c.decode(Bool.self, forKey: .is_done)
        user_id = try c.flexibleInt(forKey: .user_id)
        user_name = try? c.decode(String.self, forKey: .user_name)
        is_deleted = try? c.decode(Bool.self, forKey: .is_deleted)
        created_at = try? c.decode(String.self, forKey: .created_at)
    }
}

struct TodoDateCount: Codable {
    let id: Int
    let deadline_date: String?
    let is_done: Bool?
}

// MARK: - Notification Models

struct AppNotification: Codable, Identifiable {
    let id: Int
    let from_user_id: Int?
    let to_user_id: Int?
    let message: String
    let priority: String?
    let is_read: Bool?
    let read_at: String?
    let from_user_name: String?
    let is_deleted: Bool?
    let created_at: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        from_user_id = try c.flexibleInt(forKey: .from_user_id)
        to_user_id = try c.flexibleInt(forKey: .to_user_id)
        message = try c.decode(String.self, forKey: .message)
        priority = try? c.decode(String.self, forKey: .priority)
        is_read = try? c.decode(Bool.self, forKey: .is_read)
        read_at = try? c.decode(String.self, forKey: .read_at)
        from_user_name = try? c.decode(String.self, forKey: .from_user_name)
        is_deleted = try? c.decode(Bool.self, forKey: .is_deleted)
        created_at = try? c.decode(String.self, forKey: .created_at)
    }
}

struct NotificationUser: Codable, Identifiable {
    let id: Int
    let name: String
    let username: String?
    let role: String?
}

// MARK: - Corporate Models

struct CorporateDocument: Codable, Identifiable {
    let id: Int
    let file_name: String?
    let original_name: String?
    let mime_type: String?
    let file_size: Int?
    let doc_type: String?
    let notes: String?
    let uploaded_by: Int?
    let uploaded_by_name: String?
    let is_deleted: Bool?
    let created_at: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        file_name = try? c.decode(String.self, forKey: .file_name)
        original_name = try? c.decode(String.self, forKey: .original_name)
        mime_type = try? c.decode(String.self, forKey: .mime_type)
        file_size = try c.flexibleInt(forKey: .file_size)
        doc_type = try? c.decode(String.self, forKey: .doc_type)
        notes = try? c.decode(String.self, forKey: .notes)
        uploaded_by = try c.flexibleInt(forKey: .uploaded_by)
        uploaded_by_name = try? c.decode(String.self, forKey: .uploaded_by_name)
        is_deleted = try? c.decode(Bool.self, forKey: .is_deleted)
        created_at = try? c.decode(String.self, forKey: .created_at)
    }
}

struct CorporateNote: Codable, Identifiable {
    let id: Int
    let note_text: String
    let created_by: Int?
    let created_by_name: String?
    let is_deleted: Bool?
    let created_at: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        note_text = try c.decode(String.self, forKey: .note_text)
        created_by = try c.flexibleInt(forKey: .created_by)
        created_by_name = try? c.decode(String.self, forKey: .created_by_name)
        is_deleted = try? c.decode(Bool.self, forKey: .is_deleted)
        created_at = try? c.decode(String.self, forKey: .created_at)
    }
}
