// /AdlerCRM/Views/BusinessListView.swift  16/04/2026 00:10:00 EDT
import SwiftUI
import Combine

private enum SortColumn: String {
    case name, estGal, nextCall, region
}

struct BusinessListView: View {
    @EnvironmentObject var auth: AuthManager
    @State private var businesses: [Business] = []
    @State private var regions: [Region] = []
    @State private var loading = true
    @State private var errorMsg = ""

    // Search & filters
    @State private var searchText = ""
    @State private var showFilters = false
    @State private var filterRegion = ""
    @State private var showInactive = false
    @State private var showAddSheet = false

    // Sort
    @State private var sortColumn: SortColumn = .name
    @State private var sortAscending = true

    private var isAdmin: Bool { auth.currentUser?.role == "Administrator" }
    private var canManageRegions: Bool { isAdmin || auth.currentUser?.role == "Operations Manager" }

    // Filtered + sorted businesses
    private var filtered: [Business] {
        var list = businesses.filter { b in
            if !showInactive && b.status == "inactive" { return false }

            if !searchText.isEmpty {
                let searchable = [b.name, b.first_address, b.first_city, b.region_name]
                    .compactMap { $0 }.joined(separator: " ")
                if !searchable.localizedCaseInsensitiveContains(searchText) { return false }
            }

            if filterRegion == "__none__" && b.region_id != nil { return false }
            if !filterRegion.isEmpty && filterRegion != "__none__" {
                if String(b.region_id ?? -1) != filterRegion { return false }
            }

            return true
        }

        list.sort { a, b in
            let result: Bool
            switch sortColumn {
            case .name:
                result = a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .estGal:
                result = (a.total_est_gallons ?? 0) < (b.total_est_gallons ?? 0)
            case .nextCall:
                let dateA = nextCallSortDate(a)
                let dateB = nextCallSortDate(b)
                result = dateA < dateB
            case .region:
                result = (a.region_name ?? "zzz").localizedCaseInsensitiveCompare(b.region_name ?? "zzz") == .orderedAscending
            }
            return sortAscending ? result : !result
        }

        return list
    }

    private var hasActiveFilters: Bool {
        !filterRegion.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if loading {
                Spacer()
                ProgressView("Loading businesses…")
                    .font(.custom("DMSans-Regular", size: 14))
                Spacer()
            } else if !errorMsg.isEmpty {
                errorView
            } else {
                listContent
            }
        }
        .navigationTitle("Businesses")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    Button(action: { showAddSheet = true }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(Color(hex: "c8893a"))
                    }
                    Button(action: { withAnimation { showFilters.toggle() } }) {
                        Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .foregroundColor(hasActiveFilters ? Color(hex: "c8893a") : Color.theme.textSecondary)
                    }
                    Button(action: loadData) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(Color.theme.textSecondary)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search by name, address, city, or region")
        .task { await loadDataAsync() }
        .sheet(isPresented: $showAddSheet) {
            AddBusinessSheet(regions: regions, onSave: loadData)
        }
    }

    // MARK: - List Content

    private var listContent: some View {
        VStack(spacing: 0) {
            // Filter bar
            if showFilters {
                filterBar
            }

            // Stats bar
            HStack {
                Text("\(filtered.count) of \(businesses.count) businesses")
                    .font(.custom("DMSans-Regular", size: 12))
                    .foregroundColor(Color.theme.textSecondary)

                Spacer()

                Toggle(isOn: $showInactive) {
                    Text("Inactive")
                        .font(.custom("DMSans-Regular", size: 12))
                        .foregroundColor(Color.theme.textSecondary)
                }
                .toggleStyle(.switch)
                .tint(Color(hex: "c8893a"))
                .fixedSize()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.theme.background)

            // Business list
            if filtered.isEmpty {
                emptyState
            } else {
                // Column header
                HStack(spacing: 0) {
                    Text("#")
                        .frame(width: 22, alignment: .trailing)

                    sortableHeader("Name", column: .name, alignment: .leading)
                        .padding(.leading, 6)
                    Spacer()

                    sortableHeader("Est\nGal", column: .estGal)
                        .frame(width: 36)

                    sortableHeader("Next\nCall", column: .nextCall)
                        .frame(width: 44)

                    sortableHeader("Reg.", column: .region)
                        .frame(width: 48)
                }
                .font(.custom("DMSans-SemiBold", size: 9))
                .foregroundColor(Color.theme.textSecondary)
                .tracking(0.3)
                .multilineTextAlignment(.center)
                .padding(.leading, 20)
                .padding(.trailing, 46)
                .padding(.vertical, 6)
                .background(Color.theme.background)
                .overlay(Rectangle().fill(Color.theme.border).frame(height: 1), alignment: .bottom)

                List {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, biz in
                        NavigationLink(destination: BusinessDetailView(
                            business: biz,
                            regions: regions,
                            canManageRegions: canManageRegions,
                            onUpdate: { loadData() }
                        )) {
                            BusinessRow(index: idx + 1, business: biz)
                        }
                        .listRowBackground(idx % 2 == 0 ? Color.theme.surface : Color.theme.background)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                // Region picker
                VStack(alignment: .leading, spacing: 3) {
                    Text("REGION")
                        .font(.custom("DMSans-SemiBold", size: 9))
                        .foregroundColor(Color.theme.textSecondary)
                        .tracking(0.5)
                    Picker("Region", selection: $filterRegion) {
                        Text("All").tag("")
                        Text("Unassigned").tag("__none__")
                        ForEach(regions) { t in
                            Text(t.name).tag(String(t.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Color.theme.text)
                    .font(.custom("DMSans-Regular", size: 13))
                }

                Spacer()

                if hasActiveFilters {
                    Button("Clear") {
                        filterRegion = ""
                    }
                    .font(.custom("DMSans-Medium", size: 13))
                    .foregroundColor(Color(hex: "c8893a"))
                }
            }
        }
        .padding(12)
        .background(Color.theme.background)
        .overlay(Rectangle().fill(Color.theme.border).frame(height: 1), alignment: .bottom)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Empty & Error States

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "building.2")
                .font(.system(size: 40))
                .foregroundColor(Color.theme.textSecondary.opacity(0.4))
            Text("No businesses found")
                .font(.custom("Syne-Bold", size: 17))
                .foregroundColor(Color.theme.text)
            Text("Try adjusting your filters or search.")
                .font(.custom("DMSans-Regular", size: 14))
                .foregroundColor(Color.theme.textSecondary)
            Spacer()
        }
    }

    private var errorView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundColor(Color(hex: "c1121f"))
            Text(errorMsg)
                .font(.custom("DMSans-Regular", size: 14))
                .foregroundColor(Color.theme.text)
                .multilineTextAlignment(.center)
            Button("Retry") { loadData() }
                .font(.custom("DMSans-SemiBold", size: 14))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(Color.theme.text)
                .cornerRadius(8)
            Spacer()
        }
        .padding()
    }

    // MARK: - Sortable Header

    private func sortableHeader(_ label: String, column: SortColumn, alignment: HorizontalAlignment = .center) -> some View {
        Button(action: {
            if sortColumn == column {
                sortAscending.toggle()
            } else {
                sortColumn = column
                sortAscending = true
            }
        }) {
            HStack(spacing: 2) {
                if label.contains("\n") {
                    let parts = label.split(separator: "\n")
                    VStack(spacing: 0) {
                        ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                            Text(part)
                        }
                    }
                } else {
                    Text(label)
                }

                if sortColumn == column {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 6, weight: .bold))
                }
            }
            .foregroundColor(sortColumn == column ? Color(hex: "c8893a") : Color.theme.textSecondary)
        }
        .buttonStyle(.plain)
    }

    private func nextCallSortDate(_ b: Business) -> Date {
        guard let freq = b.first_pickup_freq, let locId = b.first_loc_id else {
            return Date.distantFuture
        }
        let days = freq == "weekly" ? 7 : freq == "biweekly" ? 14 : 30
        let offset = ((locId) * 3) % days
        return Calendar.current.date(byAdding: .day, value: offset + 1, to: Date()) ?? Date.distantFuture
    }

    // MARK: - Data Loading

    private func loadData() {
        Task { await loadDataAsync() }
    }

    private func loadDataAsync() async {
        loading = true
        errorMsg = ""
        do {
            businesses = try await APIClient.shared.getBusinesses()
            // Territories may 403 for non-admin/non-ops-manager — that's fine
            if canManageRegions {
                regions = (try? await APIClient.shared.getRegions()) ?? []
            }
        } catch {
            errorMsg = error.localizedDescription
        }
        loading = false
    }
}

// MARK: - Business Row (compact, static)

struct BusinessRow: View {
    let index: Int
    let business: Business

    var body: some View {
        HStack(spacing: 0) {
            Text("\(index)")
                .font(.custom("DMSans-Regular", size: 11))
                .foregroundColor(Color.theme.textSecondary)
                .frame(width: 22, alignment: .trailing)

            Text(business.name)
                .font(.custom("DMSans-SemiBold", size: 14))
                .foregroundColor(Color.theme.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, 6)

            Spacer(minLength: 4)

            let gal = business.total_est_gallons ?? 0
            Text(gal > 0 ? "\(gal)" : "—")
                .font(.custom("DMSans-Medium", size: 11))
                .foregroundColor(gal > 0 ? Color(hex: "2d6a4f") : Color.theme.textSecondary)
                .frame(width: 36)

            Text(nextCallDate() ?? "—")
                .font(.custom("DMSans-Regular", size: 11))
                .foregroundColor(Color.theme.textSecondary)
                .frame(width: 44)

            Text(business.region_name ?? "—")
                .font(.custom("DMSans-Medium", size: 11))
                .foregroundColor(business.region_name != nil ? Color(hex: "c8893a") : Color.theme.textSecondary)
                .lineLimit(1)
                .frame(width: 48)

            if business.status == "inactive" {
                Circle()
                    .fill(Color.theme.border)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, 2)
        .opacity(business.status == "inactive" ? 0.5 : 1)
    }

    private func nextCallDate() -> String? {
        guard let freq = business.first_pickup_freq, let locId = business.first_loc_id else { return nil }
        let days = freq == "weekly" ? 7 : freq == "biweekly" ? 14 : 30
        let offset = ((locId) * 3) % days
        let next = Calendar.current.date(byAdding: .day, value: offset + 1, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: next)
    }
}

// MARK: - Business Detail View

struct BusinessDetailView: View {
    let business: Business
    let regions: [Region]
    let canManageRegions: Bool
    let onUpdate: () -> Void

    @State private var errorMsg = ""
    @State private var showEditSheet = false
    @State private var showAddLocation = false
    @State private var showDeactivateConfirm = false
    @State private var locations: [Location] = []
    @State private var locationsLoading = true
    @State private var showDeletedLocations = false
    @State private var contacts: [BusinessContact] = []
    @State private var contactsLoading = true
    @State private var notes: [BusinessNote] = []
    @State private var notesLoading = true
    @State private var collections: [Collection] = []
    @State private var collectionsLoading = true
    @State private var documents: [BusinessDocument] = []
    @State private var documentsLoading = true

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Compact header
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(business.name)
                            .font(.custom("Syne-ExtraBold", size: 20))
                            .foregroundColor(Color.theme.text)
                        HStack(spacing: 6) {
                            Image(systemName: "map.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: "c8893a"))
                            Text(business.region_name ?? "Unassigned")
                                .font(.custom("DMSans-Medium", size: 12))
                                .foregroundColor(Color.theme.textSecondary)
                        }
                    }
                    Spacer()
                    Text(business.status ?? "active")
                        .font(.custom("DMSans-SemiBold", size: 10))
                        .foregroundColor(business.status == "active" ? Color(hex: "2d6a4f") : Color.theme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(business.status == "active" ? Color.theme.green.opacity(0.12) : Color.theme.border)
                        .cornerRadius(50)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)

                // 1. Notes
                NotesSection(
                    notes: notes,
                    loading: notesLoading,
                    businessId: business.id,
                    onReload: loadNotes
                )

                // 2. Locations
                VStack(alignment: .leading, spacing: 8) {
                    let activeLocations = locations.filter { $0.is_deleted != true }
                    let deletedLocations = locations.filter { $0.is_deleted == true }

                    HStack {
                        Label("Locations", systemImage: "mappin.circle.fill")
                            .font(.custom("Syne-Bold", size: 15))
                            .foregroundColor(Color.theme.text)
                        Spacer()
                        Text("\(activeLocations.count)")
                            .font(.custom("DMSans-SemiBold", size: 11))
                            .foregroundColor(Color(hex: "2d6a4f"))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.theme.green.opacity(0.12))
                            .cornerRadius(50)
                        if !deletedLocations.isEmpty {
                            Button(action: { withAnimation { showDeletedLocations.toggle() } }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 10))
                                    Text("\(deletedLocations.count)")
                                        .font(.custom("DMSans-SemiBold", size: 10))
                                }
                                .foregroundColor(showDeletedLocations ? .white : Color.theme.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(showDeletedLocations ? Color(hex: "c1121f").opacity(0.7) : Color.theme.border)
                                .cornerRadius(50)
                            }
                        }
                        Button(action: { showAddLocation = true }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(Color(hex: "c8893a"))
                        }
                    }

                    if locationsLoading {
                        ProgressView().frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 8)
                    } else if activeLocations.isEmpty && !showDeletedLocations {
                        Text("No active locations.")
                            .font(.custom("DMSans-Regular", size: 13))
                            .foregroundColor(Color.theme.textSecondary)
                            .padding(.vertical, 4)
                    } else {
                        // Active locations
                        if !activeLocations.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(activeLocations) { loc in
                                    NavigationLink(destination: LocationDetailView(location: loc, businessName: business.name, onUpdate: reloadLocations)) {
                                        LocationRow(location: loc)
                                    }
                                    if loc.id != activeLocations.last?.id {
                                        Divider().padding(.leading, 36)
                                    }
                                }
                            }
                        }

                        // Deleted locations (collapsible)
                        if showDeletedLocations && !deletedLocations.isEmpty {
                            Divider().padding(.vertical, 4)
                            HStack(spacing: 6) {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(hex: "c1121f"))
                                Text("DELETED (\(deletedLocations.count))")
                                    .font(.custom("DMSans-SemiBold", size: 10))
                                    .foregroundColor(Color(hex: "c1121f"))
                                    .tracking(0.4)
                                Spacer()
                            }
                            .padding(.top, 4)

                            VStack(spacing: 0) {
                                ForEach(deletedLocations) { loc in
                                    NavigationLink(destination: LocationDetailView(location: loc, businessName: business.name, onUpdate: reloadLocations)) {
                                        LocationRow(location: loc)
                                    }
                                    if loc.id != deletedLocations.last?.id {
                                        Divider().padding(.leading, 36)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color.theme.surface)
                .cornerRadius(14)
                .shadow(color: Color.black.opacity(0.04), radius: 6, y: 2)
                .sheet(isPresented: $showAddLocation) {
                    AddLocationSheet(businessId: business.id, onSave: reloadLocations)
                }

                // 3. Collections
                CollectionsSection(
                    collections: collections,
                    loading: collectionsLoading,
                    locations: locations,
                    onReload: loadCollectionsAndDocs
                )

                // 4. Contacts
                ContactsSection(
                    contacts: contacts,
                    loading: contactsLoading,
                    businessId: business.id,
                    locations: locations,
                    onReload: loadContacts
                )

                // 5. Business properties
                VStack(alignment: .leading, spacing: 8) {
                    Label("Details", systemImage: "info.circle.fill")
                        .font(.custom("Syne-Bold", size: 15))
                        .foregroundColor(Color.theme.text)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        infoItem(label: "Est. Gallons/wk", value: "\(business.total_est_gallons ?? 0)")
                        infoItem(label: "Locations", value: "\(business.location_count ?? 0)")
                        infoItem(label: "Added By", value: business.created_by_name ?? "—")
                        infoItem(label: "Since", value: formatDate(business.created_at))
                        infoItem(label: "Next Call", value: nextCallDate() ?? "—")
                        infoItem(label: "Pickup Freq", value: business.first_pickup_freq ?? "—")
                    }

                    if business.first_lat != nil || business.first_lng != nil {
                        Divider()
                        HStack(spacing: 16) {
                            infoItem(label: "Latitude", value: business.first_lat != nil ? String(format: "%.5f", business.first_lat!) : "—")
                            infoItem(label: "Longitude", value: business.first_lng != nil ? String(format: "%.5f", business.first_lng!) : "—")
                            Spacer()
                        }
                    }
                }
                .padding(16)
                .background(Color.theme.surface)
                .cornerRadius(14)
                .shadow(color: Color.black.opacity(0.04), radius: 6, y: 2)

                // 6. Documents
                DocumentsSection(
                    documents: documents,
                    loading: documentsLoading,
                    businessId: business.id,
                    onReload: loadCollectionsAndDocs
                )

                // 7. Collection Reports
                CollectionReportsSection(businessId: business.id)
            }
            .padding(12)
        }
        .background(Color.theme.background)
        .navigationTitle(business.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 14) {
                    Button(action: { showEditSheet = true }) {
                        Text("Edit")
                            .font(.custom("DMSans-Medium", size: 14))
                            .foregroundColor(Color(hex: "c8893a"))
                    }
                    Button(action: { showDeactivateConfirm = true }) {
                        Text(business.status == "active" ? "Deactivate" : "Reactivate")
                            .font(.custom("DMSans-Medium", size: 14))
                            .foregroundColor(business.status == "active" ? Color(hex: "c1121f") : Color(hex: "2d6a4f"))
                    }
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            EditBusinessSheet(
                business: business,
                regions: regions,
                canManageRegions: canManageRegions,
                onSave: onUpdate
            )
        }
        .confirmationDialog(
            business.status == "active" ? "Deactivate \"\(business.name)\"?" : "Reactivate \"\(business.name)\"?",
            isPresented: $showDeactivateConfirm,
            titleVisibility: .visible
        ) {
            Button(business.status == "active" ? "Deactivate" : "Reactivate",
                   role: business.status == "active" ? .destructive : nil) {
                toggleStatus()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(business.status == "active"
                 ? "This business will be hidden from active lists and route planning."
                 : "This business will appear in active lists and route planning again.")
        }
        .task {
            do {
                locations = try await APIClient.shared.getLocations(bizId: business.id)
            } catch { }
            locationsLoading = false
            await loadContactsAsync()
            await loadNotesAsync()
            await loadCollectionsAndDocsAsync()
        }
    }

    // MARK: - Actions

    private func toggleStatus() {
        let newStatus = business.status == "active" ? "inactive" : "active"
        Task {
            do {
                _ = try await APIClient.shared.updateBusiness(
                    id: business.id,
                    name: business.name,
                    status: newStatus,
                    notes: business.notes,
                    regionId: business.region_id
                )
                onUpdate()
            } catch {
                errorMsg = error.localizedDescription
            }
        }
    }

    private func loadContactsAsync() async {
        do { contacts = try await APIClient.shared.getContacts(bizId: business.id) } catch { }
        contactsLoading = false
    }

    private func loadContacts() {
        Task { await loadContactsAsync() }
    }

    private func loadNotesAsync() async {
        do { notes = try await APIClient.shared.getBusinessNotes(bizId: business.id) } catch { }
        notesLoading = false
    }

    private func loadNotes() {
        Task { await loadNotesAsync() }
    }

    private func loadCollectionsAndDocsAsync() async {
        do { collections = try await APIClient.shared.getCollections(bizId: business.id) } catch { }
        collectionsLoading = false
        do { documents = try await APIClient.shared.getDocuments(bizId: business.id) } catch { }
        documentsLoading = false
    }

    private func loadCollectionsAndDocs() {
        Task { await loadCollectionsAndDocsAsync() }
    }

    private func reloadLocations() {
        Task {
            do { locations = try await APIClient.shared.getLocations(bizId: business.id) } catch { }
            onUpdate()
        }
    }

    // MARK: - Helpers

    private func infoItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.custom("DMSans-SemiBold", size: 9))
                .foregroundColor(Color.theme.textSecondary)
                .tracking(0.5)
            Text(value)
                .font(.custom("DMSans-Medium", size: 14))
                .foregroundColor(Color.theme.text)
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

    private func nextCallDate() -> String? {
        guard let freq = business.first_pickup_freq, let locId = business.first_loc_id else { return nil }
        let days = freq == "weekly" ? 7 : freq == "biweekly" ? 14 : 30
        let offset = ((locId) * 3) % days
        let next = Calendar.current.date(byAdding: .day, value: offset + 1, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: next)
    }
}

// MARK: - Add Business Sheet

struct AddBusinessSheet: View {
    let regions: [Region]
    let onSave: () -> Void

    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var status = "active"
    @State private var notes = ""
    @State private var selectedRegionId: Int?
    @State private var saving = false
    @State private var errorMsg = ""

    // Optional first location
    @State private var addLocation = false
    @State private var address = ""
    @State private var city = ""
    @State private var state = ""
    @State private var zip = ""
    @State private var phone = ""
    @State private var estGallons = ""
    @State private var pickupFreq = "weekly"
    @State private var latitude = ""
    @State private var longitude = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if !errorMsg.isEmpty {
                        Text(errorMsg)
                            .font(.custom("DMSans-Regular", size: 13))
                            .foregroundColor(Color(hex: "c1121f"))
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(Color.theme.red.opacity(0.08))
                            .cornerRadius(8)
                    }

                    // Business info
                    VStack(alignment: .leading, spacing: 14) {
                        sectionLabel("Business Info")

                        formField(label: "Business Name *", text: $name, placeholder: "e.g. The Golden Wok")

                        VStack(alignment: .leading, spacing: 4) {
                            fieldLabel("Status")
                            Picker("Status", selection: $status) {
                                Text("Active").tag("active")
                                Text("Inactive").tag("inactive")
                            }
                            .pickerStyle(.segmented)
                        }

                        if !regions.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                fieldLabel("Region")
                                Picker("Region", selection: $selectedRegionId) {
                                    Text("No region assigned").tag(nil as Int?)
                                    ForEach(regions) { r in
                                        Text(r.name).tag(r.id as Int?)
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

                        VStack(alignment: .leading, spacing: 4) {
                            fieldLabel("Notes")
                            TextEditor(text: $notes)
                                .font(.custom("DMSans-Regular", size: 14))
                                .frame(minHeight: 80)
                                .padding(8)
                                .scrollContentBackground(.hidden)
                                .background(Color.theme.surface)
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.theme.border, lineWidth: 1))
                        }
                    }

                    Divider()

                    // Optional first location
                    VStack(alignment: .leading, spacing: 14) {
                        Toggle(isOn: $addLocation) {
                            HStack(spacing: 8) {
                                Image(systemName: "mappin.circle.fill")
                                    .foregroundColor(Color(hex: "2d6a4f"))
                                Text("Add First Location")
                                    .font(.custom("DMSans-SemiBold", size: 14))
                                    .foregroundColor(Color.theme.text)
                            }
                        }
                        .tint(Color(hex: "c8893a"))

                        if addLocation {
                            formField(label: "Street Address", text: $address, placeholder: "123 Main St")

                            HStack(spacing: 10) {
                                formField(label: "City", text: $city, placeholder: "City")
                                formField(label: "State", text: $state, placeholder: "VA")
                                    .frame(width: 60)
                                formField(label: "ZIP", text: $zip, placeholder: "24065")
                                    .frame(width: 80)
                            }

                            formField(label: "Phone", text: $phone, placeholder: "(540) 555-1234", keyboard: .phonePad)
                                .onChange(of: phone) { _, new in
                                    let formatted = PhoneFormatter.autoFormat(new)
                                    if formatted != new { phone = formatted }
                                }

                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    fieldLabel("Est. Gallons/wk")
                                    TextField("e.g. 25", text: $estGallons)
                                        .keyboardType(.numberPad)
                                        .font(.custom("DMSans-Regular", size: 14))
                                        .padding(12)
                                        .background(Color.theme.surface)
                                        .cornerRadius(8)
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.theme.border, lineWidth: 1))
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    fieldLabel("Frequency")
                                    Picker("Frequency", selection: $pickupFreq) {
                                        Text("Weekly").tag("weekly")
                                        Text("Biweekly").tag("biweekly")
                                        Text("Monthly").tag("monthly")
                                    }
                                    .pickerStyle(.menu)
                                    .tint(Color.theme.text)
                                    .font(.custom("DMSans-Regular", size: 14))
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 6)
                                    .background(Color.theme.surface)
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.theme.border, lineWidth: 1))
                                }
                            }

                            HStack(spacing: 10) {
                                formField(label: "Latitude", text: $latitude, placeholder: "e.g. 37.2710", keyboard: .numbersAndPunctuation)
                                formField(label: "Longitude", text: $longitude, placeholder: "e.g. -79.9414", keyboard: .numbersAndPunctuation)
                            }
                            .coordinatePaste(latitude: $latitude, longitude: $longitude)
                        }
                    }
                }
                .padding(20)
            }
            .background(Color.theme.background)
            .navigationTitle("Add Business")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.custom("DMSans-Regular", size: 14))
                        .foregroundColor(Color.theme.textSecondary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: save) {
                        if saving {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Text("Save")
                                .font(.custom("DMSans-SemiBold", size: 14))
                        }
                    }
                    .foregroundColor(Color(hex: "2d6a4f"))
                    .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: - Components

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.custom("Syne-Bold", size: 16))
            .foregroundColor(Color.theme.text)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.custom("DMSans-SemiBold", size: 9))
            .foregroundColor(Color.theme.textSecondary)
            .tracking(0.4)
    }

    private func formField(label: String, text: Binding<String>, placeholder: String, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldLabel(label)
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .font(.custom("DMSans-Regular", size: 14))
                .padding(12)
                .background(Color.theme.surface)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.theme.border, lineWidth: 1))
        }
    }

    // MARK: - Save

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { errorMsg = "Business name is required."; return }

        saving = true
        errorMsg = ""

        Task {
            do {
                let biz = try await APIClient.shared.createBusiness(
                    name: trimmedName,
                    status: status,
                    notes: notes.isEmpty ? nil : notes,
                    regionId: selectedRegionId
                )

                // Create first location if toggled on
                if addLocation && !address.trimmingCharacters(in: .whitespaces).isEmpty {
                    var locBody: [String: Any] = [
                        "business_id": biz.id,
                        "pickup_freq": pickupFreq
                    ]
                    locBody["address"] = address.isEmpty ? NSNull() : address
                    locBody["city"] = city.isEmpty ? NSNull() : city
                    locBody["state"] = state.isEmpty ? NSNull() : state
                    locBody["zip"] = zip.isEmpty ? NSNull() : zip
                    locBody["phone"] = phone.isEmpty ? NSNull() : phone
                    locBody["estimated_gallons"] = Int(estGallons) ?? 0
                    if let lat = Double(latitude) { locBody["latitude"] = lat } else { locBody["latitude"] = NSNull() }
                    if let lng = Double(longitude) { locBody["longitude"] = lng } else { locBody["longitude"] = NSNull() }

                    let _: Location = try await APIClient.shared.request(
                        path: "/locations",
                        method: "POST",
                        body: locBody
                    )
                }

                onSave()
                dismiss()
            } catch {
                errorMsg = error.localizedDescription
            }
            saving = false
        }
    }
}

// MARK: - Add Location Sheet

struct AddLocationSheet: View {
    let businessId: Int
    let onSave: () -> Void

    @Environment(\.dismiss) var dismiss
    @State private var address = ""
    @State private var city = ""
    @State private var state = ""
    @State private var zip = ""
    @State private var phone = ""
    @State private var estGallons = ""
    @State private var pickupFreq = "weekly"
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var saving = false
    @State private var errorMsg = ""

    // For adding another location without dismissing
    @State private var savedCount = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if !errorMsg.isEmpty {
                        Text(errorMsg)
                            .font(.custom("DMSans-Regular", size: 13))
                            .foregroundColor(Color(hex: "c1121f"))
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(Color.theme.red.opacity(0.08))
                            .cornerRadius(8)
                    }

                    if savedCount > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Color(hex: "2d6a4f"))
                            Text("\(savedCount) location\(savedCount == 1 ? "" : "s") added")
                                .font(.custom("DMSans-SemiBold", size: 13))
                                .foregroundColor(Color(hex: "2d6a4f"))
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(Color.theme.green.opacity(0.12))
                        .cornerRadius(8)
                    }

                    formField(label: "Street Address *", text: $address, placeholder: "123 Main St")

                    HStack(spacing: 10) {
                        formField(label: "City", text: $city, placeholder: "City")
                        formField(label: "State", text: $state, placeholder: "VA")
                            .frame(width: 60)
                        formField(label: "ZIP", text: $zip, placeholder: "24065")
                            .frame(width: 80)
                    }

                    formField(label: "Phone", text: $phone, placeholder: "(540) 555-1234", keyboard: .phonePad)
                        .onChange(of: phone) { _, new in
                            let formatted = PhoneFormatter.autoFormat(new)
                            if formatted != new { phone = formatted }
                        }

                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            fieldLabel("Est. Gallons/wk")
                            TextField("e.g. 25", text: $estGallons)
                                .keyboardType(.numberPad)
                                .font(.custom("DMSans-Regular", size: 14))
                                .padding(12)
                                .background(Color.theme.surface)
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.theme.border, lineWidth: 1))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            fieldLabel("Frequency")
                            Picker("Frequency", selection: $pickupFreq) {
                                Text("Weekly").tag("weekly")
                                Text("Biweekly").tag("biweekly")
                                Text("Monthly").tag("monthly")
                            }
                            .pickerStyle(.menu)
                            .tint(Color.theme.text)
                            .font(.custom("DMSans-Regular", size: 14))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 6)
                            .background(Color.theme.surface)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.theme.border, lineWidth: 1))
                        }
                    }

                    HStack(spacing: 10) {
                        formField(label: "Latitude", text: $latitude, placeholder: "e.g. 37.2710", keyboard: .numbersAndPunctuation)
                        formField(label: "Longitude", text: $longitude, placeholder: "e.g. -79.9414", keyboard: .numbersAndPunctuation)
                    }
                    .coordinatePaste(latitude: $latitude, longitude: $longitude)
                }
                .padding(20)
            }
            .background(Color.theme.background)
            .navigationTitle("Add Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                        .font(.custom("DMSans-Regular", size: 14))
                        .foregroundColor(Color.theme.textSecondary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        Button(action: { saveAndAddAnother() }) {
                            Text("Save & Add")
                                .font(.custom("DMSans-Medium", size: 13))
                                .foregroundColor(Color(hex: "c8893a"))
                        }
                        .disabled(saving || address.trimmingCharacters(in: .whitespaces).isEmpty)

                        Button(action: { saveAndClose() }) {
                            if saving {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Text("Save")
                                    .font(.custom("DMSans-SemiBold", size: 14))
                            }
                        }
                        .foregroundColor(Color(hex: "2d6a4f"))
                        .disabled(saving || address.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.custom("DMSans-SemiBold", size: 9))
            .foregroundColor(Color.theme.textSecondary)
            .tracking(0.4)
    }

    private func formField(label: String, text: Binding<String>, placeholder: String, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldLabel(label)
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .font(.custom("DMSans-Regular", size: 14))
                .padding(12)
                .background(Color.theme.surface)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.theme.border, lineWidth: 1))
        }
    }

    private func saveLocation() async throws {
        _ = try await APIClient.shared.createLocation(
            bizId: businessId,
            address: address.isEmpty ? nil : address,
            city: city.isEmpty ? nil : city,
            state: state.isEmpty ? nil : state,
            zip: zip.isEmpty ? nil : zip,
            phone: phone.isEmpty ? nil : phone,
            estimatedGallons: Int(estGallons) ?? 0,
            pickupFreq: pickupFreq,
            latitude: Double(latitude),
            longitude: Double(longitude)
        )
    }

    private func clearForm() {
        address = ""; city = ""; state = ""; zip = ""; phone = ""
        estGallons = ""; pickupFreq = "weekly"; latitude = ""; longitude = ""
    }

    private func saveAndClose() {
        saving = true; errorMsg = ""
        Task {
            do {
                try await saveLocation()
                onSave()
                dismiss()
            } catch {
                errorMsg = error.localizedDescription
            }
            saving = false
        }
    }

    private func saveAndAddAnother() {
        saving = true; errorMsg = ""
        Task {
            do {
                try await saveLocation()
                savedCount += 1
                clearForm()
                onSave()
            } catch {
                errorMsg = error.localizedDescription
            }
            saving = false
        }
    }
}

// MARK: - Edit Business Sheet

struct EditBusinessSheet: View {
    let business: Business
    let regions: [Region]
    let canManageRegions: Bool
    let onSave: () -> Void

    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var status = "active"
    @State private var notes = ""
    @State private var selectedRegionId: Int?
    @State private var saving = false
    @State private var errorMsg = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if !errorMsg.isEmpty {
                        Text(errorMsg)
                            .font(.custom("DMSans-Regular", size: 13))
                            .foregroundColor(Color(hex: "c1121f"))
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(Color.theme.red.opacity(0.08))
                            .cornerRadius(8)
                    }

                    // Business Name
                    VStack(alignment: .leading, spacing: 4) {
                        fieldLabel("Business Name *")
                        TextField("Business name", text: $name)
                            .font(.custom("DMSans-Regular", size: 14))
                            .padding(12)
                            .background(Color.theme.surface)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.theme.border, lineWidth: 1))
                    }

                    // Status
                    VStack(alignment: .leading, spacing: 4) {
                        fieldLabel("Status")
                        Picker("Status", selection: $status) {
                            Text("Active").tag("active")
                            Text("Inactive").tag("inactive")
                        }
                        .pickerStyle(.segmented)
                    }

                    // Region
                    if canManageRegions && !regions.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            fieldLabel("Region")
                            Picker("Region", selection: $selectedRegionId) {
                                Text("No region assigned").tag(nil as Int?)
                                ForEach(regions) { r in
                                    Text(r.name).tag(r.id as Int?)
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

                    // Notes
                    VStack(alignment: .leading, spacing: 4) {
                        fieldLabel("Notes")
                        TextEditor(text: $notes)
                            .font(.custom("DMSans-Regular", size: 14))
                            .frame(minHeight: 100)
                            .padding(8)
                            .scrollContentBackground(.hidden)
                            .background(Color.theme.surface)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.theme.border, lineWidth: 1))
                    }
                }
                .padding(20)
            }
            .background(Color.theme.background)
            .navigationTitle("Edit Business")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.custom("DMSans-Regular", size: 14))
                        .foregroundColor(Color.theme.textSecondary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: save) {
                        if saving {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Text("Save")
                                .font(.custom("DMSans-SemiBold", size: 14))
                        }
                    }
                    .foregroundColor(Color(hex: "2d6a4f"))
                    .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                name = business.name
                status = business.status ?? "active"
                notes = business.notes ?? ""
                selectedRegionId = business.region_id
            }
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.custom("DMSans-SemiBold", size: 9))
            .foregroundColor(Color.theme.textSecondary)
            .tracking(0.4)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        saving = true; errorMsg = ""

        Task {
            do {
                _ = try await APIClient.shared.updateBusiness(
                    id: business.id,
                    name: trimmed,
                    status: status,
                    notes: notes.isEmpty ? nil : notes,
                    regionId: selectedRegionId
                )
                onSave()
                dismiss()
            } catch {
                errorMsg = error.localizedDescription
            }
            saving = false
        }
    }
}

#Preview {
    NavigationStack {
        BusinessListView()
    }
    .environmentObject(AuthManager())
}
