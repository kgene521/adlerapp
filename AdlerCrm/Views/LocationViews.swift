// AdlerCRM/Views/LocationViews.swift  07/04/2026 20:18:54
import SwiftUI
import MapKit
import Combine

// MARK: - Location Row (used in Business Detail)

struct LocationRow: View {
    let location: Location

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 22))
                .foregroundColor(isInactive ? Color(hex: "e2dfd6") : (location.latitude != nil ? Color(hex: "2d6a4f") : Color(hex: "e2dfd6")))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(addressLine)
                        .font(.custom("DMSans-SemiBold", size: 14))
                        .foregroundColor(Color(hex: "0f1117"))
                        .lineLimit(1)
                    if isInactive {
                        Text("Inactive")
                            .font(.custom("DMSans-SemiBold", size: 9))
                            .foregroundColor(Color(hex: "7a7f94"))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(hex: "e2dfd6"))
                            .cornerRadius(50)
                    }
                }

                HStack(spacing: 12) {
                    if let gal = location.estimated_gallons, gal > 0 {
                        Label("\(gal) gal/wk", systemImage: "drop.fill")
                            .font(.custom("DMSans-Regular", size: 11))
                            .foregroundColor(Color(hex: "2d6a4f"))
                    }
                    Label(freqLabel, systemImage: "clock")
                        .font(.custom("DMSans-Regular", size: 11))
                        .foregroundColor(Color(hex: "7a7f94"))
                    if let ph = location.phone, !ph.isEmpty {
                        Label(PhoneFormatter.format(ph), systemImage: "phone")
                            .font(.custom("DMSans-Regular", size: 11))
                            .foregroundColor(Color(hex: "7a7f94"))
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            if let total = location.total_collected, total > 0 {
                Text("\(Int(total))g")
                    .font(.custom("DMSans-SemiBold", size: 12))
                    .foregroundColor(Color(hex: "2d6a4f"))
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(hex: "e2dfd6"))
        }
        .padding(.vertical, 8)
        .opacity(isInactive ? 0.5 : 1)
    }

    private var isInactive: Bool { location.is_deleted == true }

    private var addressLine: String {
        let parts = [location.address, location.city, location.state]
            .compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? "No address" : parts.joined(separator: ", ")
    }

    private var freqLabel: String {
        switch location.pickup_freq {
        case "weekly": return "Weekly"
        case "biweekly": return "Biweekly"
        case "monthly": return "Monthly"
        default: return location.pickup_freq?.capitalized ?? "Weekly"
        }
    }
}

// MARK: - Location Detail View

struct LocationDetailView: View {
    let location: Location
    let businessName: String
    var onUpdate: (() -> Void)? = nil

    @Environment(\.dismiss) var dismiss
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var copiedFeedback = false

    // Edit mode
    @State private var editing = false
    @State private var saving = false
    @State private var saveError = ""
    @State private var saveSuccess = false
    @State private var showDeactivateConfirm = false
    @State private var showReactivateConfirm = false

    private var isInactive: Bool { location.is_deleted == true }

    // Editable fields — Address
    @State private var editAddress = ""
    @State private var editCity = ""
    @State private var editState = ""
    @State private var editZip = ""
    @State private var editPhone = ""

    // Editable fields — Collection
    @State private var editGallons = ""
    @State private var editFreq = "weekly"
    @State private var editLatitude = ""
    @State private var editLongitude = ""

    private var hasCoordinates: Bool {
        location.latitude != nil && location.longitude != nil
    }

    private var coordinate: CLLocationCoordinate2D? {
        guard let lat = location.latitude, let lng = location.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Map card (always read-only)
                if let coord = coordinate {
                    VStack(spacing: 0) {
                        Map(position: $cameraPosition) {
                            Marker(businessName, coordinate: coord)
                                .tint(Color(hex: "2d6a4f"))
                        }
                        .mapStyle(.standard(elevation: .flat))
                        .mapControls {
                            MapCompass()
                            MapScaleView()
                        }
                        .frame(height: 220)
                        .cornerRadius(16, corners: [.topLeft, .topRight])
                        .onAppear {
                            cameraPosition = .region(MKCoordinateRegion(
                                center: coord,
                                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                            ))
                        }

                        Button(action: openInMaps) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                                    .font(.system(size: 14))
                                Text("Navigate")
                                    .font(.custom("DMSans-SemiBold", size: 15))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Color(hex: "0f1117"))
                        }
                        .cornerRadius(16, corners: [.bottomLeft, .bottomRight])
                    }
                    .shadow(color: Color.black.opacity(0.06), radius: 8, y: 2)
                }

                // Address card
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader("Address & Phone")

                    if editing {
                        editField(label: "Street Address", text: $editAddress, placeholder: "123 Main St")
                        HStack(spacing: 10) {
                            editField(label: "City", text: $editCity, placeholder: "City")
                            editField(label: "State", text: $editState, placeholder: "VA")
                                .frame(width: 60)
                            editField(label: "ZIP", text: $editZip, placeholder: "24065")
                                .frame(width: 80)
                        }
                        editField(label: "Phone", text: $editPhone, placeholder: "(540) 555-1234", keyboard: .phonePad)
                            .onChange(of: editPhone) { _, new in
                                let formatted = PhoneFormatter.autoFormat(new)
                                if formatted != new { editPhone = formatted }
                            }
                    } else {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 16))
                                .foregroundColor(Color(hex: "c8893a"))
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 4) {
                                if let addr = location.address, !addr.isEmpty {
                                    Text(addr)
                                        .font(.custom("DMSans-Medium", size: 15))
                                        .foregroundColor(Color(hex: "0f1117"))
                                }
                                let cityState = [location.city, location.state, location.zip]
                                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
                                if !cityState.isEmpty {
                                    Text(cityState)
                                        .font(.custom("DMSans-Regular", size: 14))
                                        .foregroundColor(Color(hex: "7a7f94"))
                                }
                                if (location.address ?? "").isEmpty && cityState.isEmpty {
                                    Text("No address provided")
                                        .font(.custom("DMSans-Regular", size: 14))
                                        .foregroundColor(Color(hex: "7a7f94"))
                                        .italic()
                                }
                            }
                        }

                        if let ph = location.phone, !ph.isEmpty {
                            HStack(spacing: 12) {
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(Color(hex: "1d4e89"))
                                    .frame(width: 24)
                                Text(PhoneFormatter.format(ph))
                                    .font(.custom("DMSans-Medium", size: 14))
                                    .foregroundColor(Color(hex: "0f1117"))
                            }
                        }
                    }
                }
                .cardStyle()

                // Collection card
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader("Collection")

                    if editing {
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("EST. CAPACITY (GAL/WK)")
                                    .font(.custom("DMSans-SemiBold", size: 9))
                                    .foregroundColor(Color(hex: "7a7f94"))
                                    .tracking(0.4)
                                TextField("0", text: $editGallons)
                                    .keyboardType(.numberPad)
                                    .font(.custom("DMSans-Regular", size: 14))
                                    .padding(10)
                                    .background(Color(hex: "f5f4f0"))
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "e2dfd6"), lineWidth: 1))
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("FREQUENCY")
                                    .font(.custom("DMSans-SemiBold", size: 9))
                                    .foregroundColor(Color(hex: "7a7f94"))
                                    .tracking(0.4)
                                Picker("Frequency", selection: $editFreq) {
                                    Text("Weekly").tag("weekly")
                                    Text("Biweekly").tag("biweekly")
                                    Text("Monthly").tag("monthly")
                                }
                                .pickerStyle(.menu)
                                .tint(Color(hex: "0f1117"))
                                .font(.custom("DMSans-Regular", size: 14))
                                .padding(.vertical, 4)
                                .padding(.horizontal, 6)
                                .background(Color(hex: "f5f4f0"))
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "e2dfd6"), lineWidth: 1))
                            }
                        }

                        Divider()
                    }

                    // Always-visible stats (read-only)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        if !editing {
                            statItem(icon: "drop.fill", label: "Est. Capacity",
                                     value: "\(location.estimated_gallons ?? 0) gal/wk",
                                     color: Color(hex: "2d6a4f"))
                            statItem(icon: "clock.fill", label: "Frequency",
                                     value: freqLabel,
                                     color: Color(hex: "1d4e89"))
                        }
                        statItem(icon: "truck.box.fill", label: "Total Pickups",
                                 value: "\(location.collection_count ?? 0)",
                                 color: Color(hex: "c8893a"))
                        statItem(icon: "chart.bar.fill", label: "Total Collected",
                                 value: "\(Int(location.total_collected ?? 0)) gal",
                                 color: Color(hex: "2d6a4f"))
                    }
                }
                .cardStyle()

                // Coordinates card
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader("Coordinates")

                    if editing {
                        HStack(spacing: 10) {
                            editField(label: "Latitude", text: $editLatitude, placeholder: "e.g. 37.2710", keyboard: .numbersAndPunctuation)
                            editField(label: "Longitude", text: $editLongitude, placeholder: "e.g. -79.9414", keyboard: .numbersAndPunctuation)
                        }
                    } else if hasCoordinates {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                coordRow(label: "LAT", value: String(format: "%.6f", location.latitude!))
                                coordRow(label: "LNG", value: String(format: "%.6f", location.longitude!))
                            }
                            Spacer()
                            Button(action: copyCoordinates) {
                                HStack(spacing: 4) {
                                    Image(systemName: copiedFeedback ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 12))
                                    Text(copiedFeedback ? "Copied" : "Copy")
                                        .font(.custom("DMSans-SemiBold", size: 12))
                                }
                                .foregroundColor(copiedFeedback ? Color(hex: "2d6a4f") : Color(hex: "3a3d4a"))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(hex: "f5f4f0"))
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "e2dfd6"), lineWidth: 1))
                            }
                        }
                    } else {
                        Text("No coordinates set")
                            .font(.custom("DMSans-Regular", size: 13))
                            .foregroundColor(Color(hex: "7a7f94"))
                            .italic()
                    }
                }
                .cardStyle()

                // Details card (read-only)
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader("Details")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        infoItem(label: "Business", value: businessName)
                        infoItem(label: "Added By", value: location.created_by_name ?? "—")
                        infoItem(label: "Created", value: formatDate(location.created_at))
                    }
                }
                .cardStyle()

                // Save error
                if !saveError.isEmpty {
                    Text(saveError)
                        .font(.custom("DMSans-Regular", size: 13))
                        .foregroundColor(Color(hex: "c1121f"))
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(Color(hex: "ffe5e7"))
                        .cornerRadius(8)
                }
            }
            .padding(16)
        }
        .background(Color(hex: "f5f4f0"))
        .navigationTitle(addressShort)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isInactive {
                    Button(action: { showReactivateConfirm = true }) {
                        Text("Reactivate")
                            .font(.custom("DMSans-Medium", size: 14))
                            .foregroundColor(Color(hex: "2d6a4f"))
                    }
                } else if editing {
                    HStack(spacing: 12) {
                        Button("Cancel") {
                            editing = false
                            saveError = ""
                            populateEditFields()
                        }
                        .font(.custom("DMSans-Regular", size: 14))
                        .foregroundColor(Color(hex: "7a7f94"))

                        Button(action: save) {
                            if saving {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Text("Save")
                                    .font(.custom("DMSans-SemiBold", size: 14))
                            }
                        }
                        .foregroundColor(Color(hex: "2d6a4f"))
                        .disabled(saving)
                    }
                } else {
                    HStack(spacing: 14) {
                        Button(action: {
                            populateEditFields()
                            editing = true
                        }) {
                            Text("Edit")
                                .font(.custom("DMSans-Medium", size: 14))
                                .foregroundColor(Color(hex: "c8893a"))
                        }
                        Button(action: { showDeactivateConfirm = true }) {
                            Text("Deactivate")
                                .font(.custom("DMSans-Medium", size: 14))
                                .foregroundColor(Color(hex: "c1121f"))
                        }
                    }
                }
            }
        }
        .onAppear { populateEditFields() }
        .confirmationDialog(
            "Deactivate this location?",
            isPresented: $showDeactivateConfirm,
            titleVisibility: .visible
        ) {
            Button("Deactivate", role: .destructive) { deactivateLocation() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This location will be removed from active lists and route planning. If no active locations remain, the business will also be deactivated.")
        }
        .confirmationDialog(
            "Reactivate this location?",
            isPresented: $showReactivateConfirm,
            titleVisibility: .visible
        ) {
            Button("Reactivate") { reactivateLocation() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This location will appear in active lists and route planning again.")
        }
    }

    // MARK: - Edit Field Component

    private func editField(label: String, text: Binding<String>, placeholder: String, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.custom("DMSans-SemiBold", size: 9))
                .foregroundColor(Color(hex: "7a7f94"))
                .tracking(0.4)
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .font(.custom("DMSans-Regular", size: 14))
                .padding(10)
                .background(Color(hex: "f5f4f0"))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "e2dfd6"), lineWidth: 1))
        }
    }

    // MARK: - Shared Components

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.custom("Syne-Bold", size: 16))
            .foregroundColor(Color(hex: "0f1117"))
    }

    private func statItem(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.custom("DMSans-SemiBold", size: 8))
                    .foregroundColor(Color(hex: "7a7f94"))
                    .tracking(0.4)
                Text(value)
                    .font(.custom("DMSans-SemiBold", size: 14))
                    .foregroundColor(Color(hex: "0f1117"))
            }
        }
    }

    private func coordRow(label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.custom("DMSans-SemiBold", size: 9))
                .foregroundColor(Color(hex: "7a7f94"))
                .tracking(0.5)
                .frame(width: 28, alignment: .trailing)
            Text(value)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundColor(Color(hex: "0f1117"))
                .textSelection(.enabled)
        }
    }

    private func infoItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.custom("DMSans-SemiBold", size: 9))
                .foregroundColor(Color(hex: "7a7f94"))
                .tracking(0.5)
            Text(value)
                .font(.custom("DMSans-Medium", size: 14))
                .foregroundColor(Color(hex: "0f1117"))
        }
    }

    // MARK: - Actions

    private func populateEditFields() {
        editAddress = location.address ?? ""
        editCity = location.city ?? ""
        editState = location.state ?? ""
        editZip = location.zip ?? ""
        editPhone = PhoneFormatter.format(location.phone)
        editGallons = "\(location.estimated_gallons ?? 0)"
        editFreq = location.pickup_freq ?? "weekly"
        editLatitude = location.latitude != nil ? String(format: "%.6f", location.latitude!) : ""
        editLongitude = location.longitude != nil ? String(format: "%.6f", location.longitude!) : ""
    }

    private func save() {
        saving = true
        saveError = ""
        Task {
            do {
                _ = try await APIClient.shared.updateLocation(
                    id: location.id,
                    address: editAddress.isEmpty ? nil : editAddress,
                    city: editCity.isEmpty ? nil : editCity,
                    state: editState.isEmpty ? nil : editState,
                    zip: editZip.isEmpty ? nil : editZip,
                    phone: editPhone.isEmpty ? nil : editPhone,
                    estimatedGallons: Int(editGallons) ?? 0,
                    pickupFreq: editFreq,
                    latitude: Double(editLatitude),
                    longitude: Double(editLongitude)
                )
                editing = false
                saveSuccess = true
                onUpdate?()
            } catch {
                saveError = error.localizedDescription
            }
            saving = false
        }
    }

    private func deactivateLocation() {
        Task {
            do {
                _ = try await APIClient.shared.deleteLocation(id: location.id)
                onUpdate?()
                dismiss()
            } catch {
                saveError = error.localizedDescription
            }
        }
    }

    private func reactivateLocation() {
        Task {
            do {
                _ = try await APIClient.shared.reactivateLocation(id: location.id)
                onUpdate?()
                dismiss()
            } catch {
                saveError = error.localizedDescription
            }
        }
    }

    private func openInMaps() {
        guard let coord = coordinate else { return }
        MapHelpers.openDirections(to: coord, name: businessName)
    }

    private func copyCoordinates() {
        guard let lat = location.latitude, let lng = location.longitude else { return }
        UIPasteboard.general.string = String(format: "%.6f, %.6f", lat, lng)
        copiedFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedFeedback = false }
    }

    // MARK: - Helpers

    private var addressShort: String {
        location.address ?? location.city ?? "Location"
    }

    private var freqLabel: String {
        switch location.pickup_freq {
        case "weekly": return "Weekly"
        case "biweekly": return "Biweekly"
        case "monthly": return "Monthly"
        default: return location.pickup_freq?.capitalized ?? "Weekly"
        }
    }

    private func formatDate(_ dateStr: String?) -> String {
        guard let dateStr = dateStr else { return "—" }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: dateStr) {
            let fmt = DateFormatter()
            fmt.dateFormat = "MMM d, yyyy"
            return fmt.string(from: date)
        }
        let prefix = String(dateStr.prefix(10))
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        if let date = fmt.date(from: prefix) {
            fmt.dateFormat = "MMM d, yyyy"
            return fmt.string(from: date)
        }
        return "—"
    }
}

// MARK: - Card Style Modifier

struct CardStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(Color.white)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.06), radius: 8, y: 2)
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyleModifier())
    }
}

// MARK: - Rounded Corner Helper

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

#Preview {
    NavigationStack {
        LocationDetailView(
            location: Location(
                id: 1, business_id: 1,
                address: "123 Main St", city: "Roanoke", state: "VA", zip: "24011",
                phone: "540-555-1234",
                estimated_gallons: 45, pickup_freq: "weekly",
                latitude: 37.2710, longitude: -79.9414,
                business_name: "Golden Wok", created_by_name: "Admin",
                total_collected: 1250, collection_count: 28,
                is_deleted: false, created_at: "2024-01-15"
            ),
            businessName: "The Golden Wok"
        )
    }
}
