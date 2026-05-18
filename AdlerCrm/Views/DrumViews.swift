// /AdlerCRM/Views/DrumViews.swift  17/05/2026 23:40:00 EDT
import SwiftUI
import CoreLocation
import CoreNFC

// MARK: - Drum Scan Button (embed in collection flow)

struct DrumScanButton: View {
    @Binding var scannedDrum: Drum?
    @Binding var scannedDrumId: Int?
    @ObservedObject private var nfc = NFCManager.shared
    @State private var showRegister = false
    @State private var unknownTagId: String?
    @State private var unknownTagType: String?
    @State private var showDrumDetail = false
    @State private var scanError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Scan button
            Button(action: startScan) {
                HStack(spacing: 8) {
                    if nfc.isScanning {
                        ProgressView().tint(Color(hex: "c8893a")).scaleEffect(0.7)
                    } else {
                        Image(systemName: "wave.3.right.circle.fill")
                            .font(.system(size: 16))
                    }
                    Text(nfc.isScanning ? "Scanning…" : "Scan Drum NFC Tag")
                        .font(.custom("DMSans-SemiBold", size: 13))
                }
                .foregroundColor(Color(hex: "c8893a"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Color(hex: "c8893a").opacity(0.1))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "c8893a").opacity(0.3), lineWidth: 1))
            }
            .disabled(nfc.isScanning)

            // Scanned drum info
            if let drum = scannedDrum {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color(hex: "2d6a4f"))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(drum.nickname ?? "Drum #\(drum.id)")
                            .font(.custom("DMSans-SemiBold", size: 13))
                            .foregroundColor(Color.theme.text)
                        if let biz = drum.business_name {
                            Text(biz)
                                .font(.custom("DMSans-Regular", size: 11))
                                .foregroundColor(Color.theme.textSecondary)
                        }
                    }
                    Spacer()
                    Button(action: { scannedDrum = nil; scannedDrumId = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Color.theme.textSecondary)
                    }
                }
                .padding(10)
                .background(Color(hex: "2d6a4f").opacity(0.08))
                .cornerRadius(8)
            }

            // Error
            if let err = scanError {
                Text(err)
                    .font(.custom("DMSans-Regular", size: 11))
                    .foregroundColor(Color(hex: "c1121f"))
            }
        }
        .sheet(isPresented: $showRegister) {
            RegisterDrumSheet(
                tagId: unknownTagId ?? "",
                tagType: unknownTagType,
                onRegistered: { drum in
                    scannedDrum = drum
                    scannedDrumId = drum.id
                }
            )
        }
    }

    private func startScan() {
        scanError = nil
        nfc.scan { tagId, tagType in
            // Look up the tag
            Task {
                do {
                    let drum = try await APIClient.shared.lookupDrumByTag(tagId: tagId)
                    scannedDrum = drum
                    scannedDrumId = drum.id

                    // Log the scan
                    let locHelper = CLLocationManager()
                    if let loc = locHelper.location {
                        let _ = try? await APIClient.shared.scanDrum(id: drum.id, latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
                    }
                } catch {
                    // Tag not registered — offer to register
                    unknownTagId = tagId
                    unknownTagType = tagType
                    showRegister = true
                }
            }
        }
    }
}

// MARK: - Register Drum Sheet

struct RegisterDrumSheet: View {
    let tagId: String
    let tagType: String?
    let onRegistered: (Drum) -> Void

    @Environment(\.dismiss) var dismiss
    @State private var nickname = ""
    @State private var capacityGallons = "55"
    @State private var selectedBusinessId: Int?
    @State private var selectedLocationId: Int?
    @State private var businesses: [Business] = []
    @State private var locations: [Location] = []
    @State private var saving = false
    @State private var errorMsg = ""
    @State private var loadingData = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Tag info
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "wave.3.right.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(Color(hex: "c8893a"))
                            Text("New NFC Tag Detected")
                                .font(.custom("DMSans-SemiBold", size: 15))
                                .foregroundColor(Color.theme.text)
                        }
                        HStack(spacing: 8) {
                            tagPill("ID", tagId.prefix(20) + (tagId.count > 20 ? "…" : ""))
                            if let tt = tagType { tagPill("Type", tt) }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: "c8893a").opacity(0.08))
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "c8893a").opacity(0.2), lineWidth: 1))

                    if !errorMsg.isEmpty {
                        Text(errorMsg)
                            .font(.custom("DMSans-Regular", size: 13))
                            .foregroundColor(Color(hex: "c1121f"))
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(Color.theme.red.opacity(0.08))
                            .cornerRadius(8)
                    }

                    // Nickname
                    VStack(alignment: .leading, spacing: 4) {
                        fieldLabel("Drum Nickname")
                        TextField("e.g. Blue 55-gal, Drum #3", text: $nickname)
                            .font(.custom("DMSans-Regular", size: 14))
                            .padding(12)
                            .background(Color.theme.surface)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.theme.border, lineWidth: 1))
                    }

                    // Capacity
                    VStack(alignment: .leading, spacing: 4) {
                        fieldLabel("Capacity (gallons)")
                        TextField("55", text: $capacityGallons)
                            .keyboardType(.numberPad)
                            .font(.custom("DMSans-Regular", size: 14))
                            .padding(12)
                            .background(Color.theme.surface)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.theme.border, lineWidth: 1))
                    }

                    // Business picker
                    if loadingData {
                        ProgressView().padding(.vertical, 8)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            fieldLabel("Assign to Business")
                            Picker("Business", selection: $selectedBusinessId) {
                                Text("None").tag(nil as Int?)
                                ForEach(businesses) { biz in
                                    Text(biz.name).tag(biz.id as Int?)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(Color.theme.text)
                            .font(.custom("DMSans-Regular", size: 14))
                            .padding(8)
                            .background(Color.theme.surface)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.theme.border, lineWidth: 1))
                        }

                        // Location picker (filtered by business)
                        if selectedBusinessId != nil {
                            if !locations.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    fieldLabel("Assign to Location")
                                    Picker("Location", selection: $selectedLocationId) {
                                        Text("None").tag(nil as Int?)
                                        ForEach(locations) { loc in
                                            Text(loc.address ?? loc.city ?? "Location #\(loc.id)")
                                                .tag(loc.id as Int?)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .tint(Color.theme.text)
                                    .font(.custom("DMSans-Regular", size: 14))
                                    .padding(8)
                                    .background(Color.theme.surface)
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.theme.border, lineWidth: 1))
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Color.theme.background)
            .navigationTitle("Register Drum")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.custom("DMSans-Regular", size: 14))
                        .foregroundColor(Color.theme.textSecondary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: register) {
                        if saving { ProgressView().scaleEffect(0.8) }
                        else { Text("Register").font(.custom("DMSans-SemiBold", size: 14)) }
                    }
                    .foregroundColor(Color(hex: "2d6a4f"))
                    .disabled(saving)
                }
            }
            .task { await loadData() }
            .onChange(of: selectedBusinessId) { _, newVal in
                selectedLocationId = nil
                locations = []
                if let bizId = newVal {
                    Task { await loadLocations(bizId: bizId) }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.custom("DMSans-SemiBold", size: 9))
            .foregroundColor(Color.theme.textSecondary)
            .tracking(0.4)
    }

    private func tagPill(_ label: String, _ value: any StringProtocol) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.custom("DMSans-SemiBold", size: 9))
                .foregroundColor(Color(hex: "c8893a"))
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Color.theme.text)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.theme.surface)
        .cornerRadius(4)
    }

    private func loadData() async {
        loadingData = true
        do {
            businesses = try await APIClient.shared.getBusinesses()
        } catch {}
        loadingData = false
    }

    private func loadLocations(bizId: Int) async {
        do {
            locations = try await APIClient.shared.getLocations(bizId: bizId)
        } catch { locations = [] }
    }

    private func register() {
        saving = true
        errorMsg = ""
        let cap = Int(capacityGallons) ?? 55

        Task {
            do {
                // Get current location for coordinates
                let locManager = CLLocationManager()
                let lat = locManager.location?.coordinate.latitude
                let lng = locManager.location?.coordinate.longitude

                let drum = try await APIClient.shared.registerDrum(
                    nfcTagId: tagId,
                    nickname: nickname.isEmpty ? nil : nickname,
                    locationId: selectedLocationId,
                    businessId: selectedBusinessId,
                    latitude: lat,
                    longitude: lng,
                    capacityGallons: cap,
                    tagType: tagType
                )
                onRegistered(drum)
                dismiss()
            } catch {
                errorMsg = error.localizedDescription
            }
            saving = false
        }
    }
}

// MARK: - Drum Detail Sheet

struct DrumDetailSheet: View {
    let drumId: Int
    @Environment(\.dismiss) var dismiss
    @State private var drum: Drum?
    @State private var loading = true

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    VStack { Spacer(); ProgressView("Loading…"); Spacer() }
                } else if let drum = drum {
                    drumContent(drum)
                } else {
                    VStack { Spacer(); Text("Drum not found").foregroundColor(Color.theme.textSecondary); Spacer() }
                }
            }
            .background(Color.theme.background)
            .navigationTitle("Drum Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.custom("DMSans-Medium", size: 14))
                        .foregroundColor(Color(hex: "c8893a"))
                }
            }
            .task { await loadDrum() }
        }
    }

    private func drumContent(_ drum: Drum) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "wave.3.right.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(Color(hex: "c8893a"))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(drum.nickname ?? "Drum #\(drum.id)")
                                .font(.custom("Syne-Bold", size: 18))
                                .foregroundColor(Color.theme.text)
                            Text(drum.nfc_tag_id)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(Color.theme.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        statusBadge(drum.status ?? "active")
                    }
                }
                .padding(14)
                .background(Color.theme.surface)
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.theme.border, lineWidth: 1))

                // Info grid
                infoCard("Details") {
                    infoRow("Capacity", "\(drum.capacity_gallons ?? 55) gallons")
                    if let tt = drum.tag_type { infoRow("Tag Type", tt) }
                    if let biz = drum.business_name { infoRow("Business", biz) }
                    if let addr = drum.location_address { infoRow("Location", addr) }
                    if let reg = drum.registered_by_name { infoRow("Registered By", reg) }
                    infoRow("Scans", "\(drum.scan_count ?? 0)")
                    infoRow("Collections", "\(drum.collection_count ?? 0)")
                }

                // Recent scans
                if let scans = drum.recent_scans, !scans.isEmpty {
                    infoCard("Recent Scans") {
                        ForEach(scans.prefix(5)) { scan in
                            HStack {
                                Text(scan.user_name ?? "Unknown")
                                    .font(.custom("DMSans-Medium", size: 13))
                                    .foregroundColor(Color.theme.text)
                                Spacer()
                                Text(formatTime(scan.scanned_at))
                                    .font(.custom("DMSans-Regular", size: 11))
                                    .foregroundColor(Color.theme.textSecondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                // Recent collections
                if let collections = drum.recent_collections, !collections.isEmpty {
                    infoCard("Recent Collections") {
                        ForEach(collections.prefix(5)) { col in
                            HStack {
                                Text("\(Int(col.gallons ?? 0)) gal")
                                    .font(.custom("DMSans-SemiBold", size: 13))
                                    .foregroundColor(Color(hex: "2d6a4f"))
                                Text(col.employee_name ?? "")
                                    .font(.custom("DMSans-Regular", size: 12))
                                    .foregroundColor(Color.theme.textSecondary)
                                Spacer()
                                Text(shortDate(col.pickup_date))
                                    .font(.custom("DMSans-Regular", size: 11))
                                    .foregroundColor(Color.theme.textSecondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private func statusBadge(_ status: String) -> some View {
        Text(status.uppercased())
            .font(.custom("DMSans-Bold", size: 9))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status == "active" ? Color(hex: "2d6a4f").opacity(0.12) : Color.theme.textSecondary.opacity(0.12))
            .foregroundColor(status == "active" ? Color(hex: "2d6a4f") : Color.theme.textSecondary)
            .cornerRadius(4)
    }

    private func infoCard(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.custom("DMSans-SemiBold", size: 9))
                .foregroundColor(Color.theme.textSecondary)
                .tracking(0.4)
            VStack(alignment: .leading, spacing: 6) { content() }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.theme.surface)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.theme.border, lineWidth: 1))
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.custom("DMSans-Regular", size: 12))
                .foregroundColor(Color.theme.textSecondary)
            Spacer()
            Text(value)
                .font(.custom("DMSans-Medium", size: 13))
                .foregroundColor(Color.theme.text)
        }
    }

    private func formatTime(_ str: String?) -> String {
        guard let s = str else { return "" }
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = iso.date(from: s) ?? ISO8601DateFormatter().date(from: s) else { return String(s.prefix(10)) }
        let fmt = DateFormatter(); fmt.dateFormat = "MMM d, h:mm a"; return fmt.string(from: date)
    }

    private func shortDate(_ str: String?) -> String {
        guard let s = str else { return "" }
        return String(s.prefix(10))
    }

    private func loadDrum() async {
        loading = true
        do { drum = try await APIClient.shared.getDrum(id: drumId) } catch {}
        loading = false
    }
}

// MARK: - Write Tag Sheet

struct WriteTagSheet: View {
    let payload: String
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var nfc = NFCManager.shared
    @State private var writeSuccess = false
    @State private var writeError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: writeSuccess ? "checkmark.circle.fill" : "wave.3.right.circle.fill")
                    .font(.system(size: 56))
                    .foregroundColor(writeSuccess ? Color(hex: "2d6a4f") : Color(hex: "c8893a"))

                Text(writeSuccess ? "Tag Written!" : "Write NFC Tag")
                    .font(.custom("Syne-Bold", size: 22))
                    .foregroundColor(Color.theme.text)

                if writeSuccess {
                    Text("The tag has been programmed with the drum ID.")
                        .font(.custom("DMSans-Regular", size: 14))
                        .foregroundColor(Color.theme.textSecondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("This will write the following ID to the NFC tag:")
                        .font(.custom("DMSans-Regular", size: 14))
                        .foregroundColor(Color.theme.textSecondary)
                        .multilineTextAlignment(.center)

                    Text(payload)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Color.theme.text)
                        .padding(12)
                        .background(Color.theme.surface)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.theme.border, lineWidth: 1))
                }

                if let err = writeError {
                    Text(err)
                        .font(.custom("DMSans-Regular", size: 13))
                        .foregroundColor(Color(hex: "c1121f"))
                }

                if !writeSuccess {
                    Button(action: writeTag) {
                        HStack(spacing: 8) {
                            if nfc.isScanning {
                                ProgressView().tint(.white).scaleEffect(0.8)
                            } else {
                                Image(systemName: "pencil.line")
                            }
                            Text(nfc.isScanning ? "Hold near tag…" : "Write to Tag")
                                .font(.custom("DMSans-SemiBold", size: 15))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(hex: "c8893a"))
                        .cornerRadius(10)
                    }
                    .disabled(nfc.isScanning)
                    .padding(.horizontal, 40)
                }

                Spacer()
            }
            .padding(20)
            .background(Color.theme.background)
            .navigationTitle("Write Tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(writeSuccess ? "Done" : "Cancel") { dismiss() }
                        .font(.custom("DMSans-Medium", size: 14))
                        .foregroundColor(Color(hex: "c8893a"))
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func writeTag() {
        writeError = nil
        nfc.write(payload: payload) { success, error in
            if success {
                writeSuccess = true
            } else {
                writeError = error ?? "Failed to write tag."
            }
        }
    }
}
