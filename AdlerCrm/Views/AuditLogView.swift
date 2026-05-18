// /AdlerCRM/Views/AuditLogView.swift  15/04/2026 21:51:00 EDT
import SwiftUI

struct AuditLogView: View {
    @State private var logs: [AuditLogEntry] = []
    @State private var total = 0
    @State private var loading = true
    @State private var offset = 0
    @State private var hasMore = false

    // Filters
    @State private var filterAction = ""
    @State private var filterEntityType = ""
    @State private var filterUsername = ""
    @State private var availableActions: [String] = []
    @State private var availableEntityTypes: [String] = []
    @State private var showFilters = false

    // Detail
    @State private var selectedEntry: AuditLogEntry?

    // Stats
    @State private var stats: AuditLogStatsResponse?
    @State private var showStats = false

    // Purge
    @State private var showPurgeConfirm = false
    @State private var purgeResult: String?

    private let pageSize = 50

    var body: some View {
        VStack(spacing: 0) {
            // Active filters bar
            if hasActiveFilters {
                activeFiltersBar
            }

            if loading && logs.isEmpty {
                Spacer()
                ProgressView("Loading audit logs…")
                    .font(.custom("DMSans-Regular", size: 14))
                Spacer()
            } else if logs.isEmpty {
                emptyState
            } else {
                logList
            }
        }
        .background(Color.theme.background)
        .navigationTitle("Audit Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    Button(action: { showStats.toggle() }) {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "c8893a"))
                    }
                    Button(action: { showFilters.toggle() }) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.system(size: 16))
                                .foregroundColor(hasActiveFilters ? Color(hex: "c8893a") : Color.theme.textSecondary)
                            if hasActiveFilters {
                                Circle().fill(Color(hex: "c8893a")).frame(width: 7, height: 7).offset(x: 2, y: -2)
                            }
                        }
                    }
                    Button(action: { Task { await refresh() } }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14))
                            .foregroundColor(Color.theme.textSecondary)
                    }
                }
            }
        }
        .task {
            await loadFilterOptions()
            await loadLogs(reset: true)
        }
        .sheet(isPresented: $showFilters) {
            AuditLogFilterSheet(
                filterAction: $filterAction,
                filterEntityType: $filterEntityType,
                filterUsername: $filterUsername,
                availableActions: availableActions,
                availableEntityTypes: availableEntityTypes,
                onApply: { Task { await loadLogs(reset: true) } },
                onClear: {
                    filterAction = ""
                    filterEntityType = ""
                    filterUsername = ""
                    Task { await loadLogs(reset: true) }
                }
            )
        }
        .sheet(item: $selectedEntry) { entry in
            AuditLogDetailSheet(entry: entry)
        }
        .sheet(isPresented: $showStats) {
            AuditLogStatsSheet(stats: stats, onPurge: { showPurgeConfirm = true })
                .task { await loadStats() }
        }
        .confirmationDialog("Purge logs older than 30 days?", isPresented: $showPurgeConfirm, titleVisibility: .visible) {
            Button("Purge", role: .destructive) { Task { await purgeOldLogs() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all audit log entries older than 30 days.")
        }
        .overlay {
            if let result = purgeResult {
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(Color(hex: "2d6a4f"))
                        Text(result).font(.custom("DMSans-Medium", size: 13)).foregroundColor(.white)
                        Spacer()
                    }
                    .padding(14)
                    .background(Color(hex: "2d6a4f"))
                    .cornerRadius(10)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation { purgeResult = nil }
                    }
                }
            }
        }
    }

    // MARK: - Active Filters Bar

    private var hasActiveFilters: Bool {
        !filterAction.isEmpty || !filterEntityType.isEmpty || !filterUsername.isEmpty
    }

    private var activeFiltersBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if !filterAction.isEmpty {
                    filterChip("Action: \(filterAction)") { filterAction = ""; Task { await loadLogs(reset: true) } }
                }
                if !filterEntityType.isEmpty {
                    filterChip("Entity: \(filterEntityType)") { filterEntityType = ""; Task { await loadLogs(reset: true) } }
                }
                if !filterUsername.isEmpty {
                    filterChip("User: \(filterUsername)") { filterUsername = ""; Task { await loadLogs(reset: true) } }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color.theme.surface)
        .overlay(Rectangle().fill(Color.theme.border).frame(height: 1), alignment: .bottom)
    }

    private func filterChip(_ label: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.custom("DMSans-Medium", size: 11))
                .foregroundColor(Color(hex: "c8893a"))
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "c8893a").opacity(0.6))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(hex: "c8893a").opacity(0.1))
        .cornerRadius(50)
    }

    // MARK: - Log List

    private var logList: some View {
        VStack(spacing: 0) {
            // Count bar
            HStack {
                Text("\(total) entries")
                    .font(.custom("DMSans-Medium", size: 12))
                    .foregroundColor(Color.theme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color.theme.background)

            List {
                ForEach(logs) { entry in
                    Button(action: { selectedEntry = entry }) {
                        logRow(entry)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }

                if hasMore {
                    HStack {
                        Spacer()
                        if loading {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Button("Load More") { Task { await loadLogs(reset: false) } }
                                .font(.custom("DMSans-Medium", size: 13))
                                .foregroundColor(Color(hex: "c8893a"))
                        }
                        Spacer()
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }
            .listStyle(.plain)
        }
    }

    // MARK: - Log Row

    private func logRow(_ entry: AuditLogEntry) -> some View {
        HStack(spacing: 10) {
            // Action badge
            Text(entry.action?.uppercased() ?? entry.method ?? "?")
                .font(.custom("DMSans-Bold", size: 8))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(actionColor(entry.action))
                .cornerRadius(4)
                .frame(minWidth: 52)

            VStack(alignment: .leading, spacing: 3) {
                // Entity info
                HStack(spacing: 4) {
                    if let et = entry.entity_type {
                        Text(et)
                            .font(.custom("DMSans-SemiBold", size: 13))
                            .foregroundColor(Color.theme.text)
                    }
                    if let eid = entry.entity_id {
                        Text("#\(eid)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Color.theme.textSecondary)
                    }
                }

                // User + time
                HStack(spacing: 6) {
                    if let user = entry.username {
                        Text(user)
                            .font(.custom("DMSans-Medium", size: 11))
                            .foregroundColor(Color(hex: "c8893a"))
                    }
                    Text(formatTime(entry.timestamp))
                        .font(.custom("DMSans-Regular", size: 10))
                        .foregroundColor(Color.theme.textSecondary)
                }
            }

            Spacer()

            // Status code
            if let sc = entry.status_code {
                Text("\(sc)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(sc < 400 ? Color(hex: "2d6a4f") : Color(hex: "c1121f"))
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 10))
                .foregroundColor(Color.theme.border)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(Color.theme.border)
            Text("No audit log entries")
                .font(.custom("DMSans-Regular", size: 14))
                .foregroundColor(Color.theme.textSecondary)
            if hasActiveFilters {
                Button("Clear Filters") {
                    filterAction = ""; filterEntityType = ""; filterUsername = ""
                    Task { await loadLogs(reset: true) }
                }
                .font(.custom("DMSans-Medium", size: 13))
                .foregroundColor(Color(hex: "c8893a"))
            }
            Spacer()
        }
    }

    // MARK: - Data Loading

    private func loadFilterOptions() async {
        do {
            availableActions = try await APIClient.shared.getAuditLogActions()
            availableEntityTypes = try await APIClient.shared.getAuditLogEntityTypes()
        } catch {}
    }

    private func loadLogs(reset: Bool) async {
        if reset { offset = 0 }
        loading = true
        do {
            let response = try await APIClient.shared.getAuditLogs(
                limit: pageSize, offset: offset,
                action: filterAction.isEmpty ? nil : filterAction,
                entityType: filterEntityType.isEmpty ? nil : filterEntityType,
                username: filterUsername.isEmpty ? nil : filterUsername
            )
            if reset {
                logs = response.logs
            } else {
                logs.append(contentsOf: response.logs)
            }
            total = response.total
            offset = logs.count
            hasMore = logs.count < total
        } catch {}
        loading = false
    }

    private func loadStats() async {
        do { stats = try await APIClient.shared.getAuditLogStats() } catch {}
    }

    private func refresh() async {
        await loadFilterOptions()
        await loadLogs(reset: true)
    }

    private func purgeOldLogs() async {
        do {
            let deleted = try await APIClient.shared.purgeAuditLogs(mode: "retention", days: 30)
            withAnimation { purgeResult = "Purged \(deleted) entries" }
            await refresh()
            await loadStats()
        } catch {
            withAnimation { purgeResult = "Purge failed: \(error.localizedDescription)" }
        }
    }

    // MARK: - Helpers

    private func actionColor(_ action: String?) -> Color {
        switch action {
        case "create", "upload":          return Color(hex: "2d6a4f")
        case "update":                    return Color(hex: "1d4e89")
        case "delete":                    return Color(hex: "c1121f")
        case "login":                     return Color(hex: "6c5ce7")
        case "toggle":                    return Color(hex: "e17055")
        case "assign", "create-and-assign": return Color(hex: "00b894")
        case "unassign", "unsave":        return Color(hex: "d63031")
        case "save":                      return Color(hex: "0984e3")
        case "purge":                     return Color(hex: "636e72")
        case "impersonate":               return Color(hex: "e84393")
        case "totp-setup", "totp-verify", "totp-reset", "change-password":
                                          return Color(hex: "fdcb6e")
        case "mark-read", "mark-read-all": return Color(hex: "74b9ff")
        case "reactivate":                return Color(hex: "55efc4")
        case "bulk-import":               return Color(hex: "a29bfe")
        default:                          return Color(hex: "636e72")
        }
    }

    private func formatTime(_ str: String?) -> String {
        guard let s = str else { return "" }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = iso.date(from: s) ?? ISO8601DateFormatter().date(from: s) else {
            return String(s.prefix(16))
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, h:mm a"
        return fmt.string(from: date)
    }
}

// MARK: - Filter Sheet

struct AuditLogFilterSheet: View {
    @Binding var filterAction: String
    @Binding var filterEntityType: String
    @Binding var filterUsername: String
    let availableActions: [String]
    let availableEntityTypes: [String]
    let onApply: () -> Void
    let onClear: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Action filter
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ACTION")
                            .font(.custom("DMSans-SemiBold", size: 9))
                            .foregroundColor(Color.theme.textSecondary)
                            .tracking(0.4)
                        FlowLayout(spacing: 6) {
                            filterPill("All", isSelected: filterAction.isEmpty) { filterAction = "" }
                            ForEach(availableActions, id: \.self) { action in
                                filterPill(action, isSelected: filterAction == action) { filterAction = action }
                            }
                        }
                    }

                    // Entity type filter
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ENTITY TYPE")
                            .font(.custom("DMSans-SemiBold", size: 9))
                            .foregroundColor(Color.theme.textSecondary)
                            .tracking(0.4)
                        FlowLayout(spacing: 6) {
                            filterPill("All", isSelected: filterEntityType.isEmpty) { filterEntityType = "" }
                            ForEach(availableEntityTypes, id: \.self) { et in
                                filterPill(et, isSelected: filterEntityType == et) { filterEntityType = et }
                            }
                        }
                    }

                    // Username filter
                    VStack(alignment: .leading, spacing: 6) {
                        Text("USERNAME")
                            .font(.custom("DMSans-SemiBold", size: 9))
                            .foregroundColor(Color.theme.textSecondary)
                            .tracking(0.4)
                        TextField("Search by username…", text: $filterUsername)
                            .font(.custom("DMSans-Regular", size: 14))
                            .foregroundColor(Color.theme.text)
                            .padding(12)
                            .background(Color.theme.inputBackground)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.theme.border, lineWidth: 1))
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }

                    Spacer()
                }
                .padding(20)
            }
            .background(Color.theme.background)
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Clear") { onClear(); dismiss() }
                        .font(.custom("DMSans-Regular", size: 14))
                        .foregroundColor(Color.theme.textSecondary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Apply") { onApply(); dismiss() }
                        .font(.custom("DMSans-SemiBold", size: 14))
                        .foregroundColor(Color(hex: "2d6a4f"))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func filterPill(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.custom("DMSans-SemiBold", size: 11))
                .foregroundColor(isSelected ? .white : Color.theme.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color(hex: "c8893a") : Color.theme.surface)
                .cornerRadius(50)
                .overlay(RoundedRectangle(cornerRadius: 50).stroke(isSelected ? Color.clear : Color.theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Detail Sheet

struct AuditLogDetailSheet: View {
    let entry: AuditLogEntry
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header card
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text(entry.action?.uppercased() ?? "—")
                                .font(.custom("DMSans-Bold", size: 11))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(actionColor(entry.action))
                                .cornerRadius(4)

                            if let sc = entry.status_code {
                                Text("\(sc)")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(sc < 400 ? Color(hex: "2d6a4f") : Color(hex: "c1121f"))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(sc < 400 ? Color(hex: "2d6a4f").opacity(0.1) : Color(hex: "c1121f").opacity(0.1))
                                    .cornerRadius(4)
                            }

                            Spacer()

                            if let ms = entry.duration_ms {
                                Text("\(ms)ms")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(Color.theme.textSecondary)
                            }
                        }

                        if let path = entry.path {
                            HStack(spacing: 4) {
                                Text(entry.method ?? "")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color.theme.text)
                                Text(path)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(Color.theme.textSecondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .padding(14)
                    .background(Color.theme.surface)
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.theme.border, lineWidth: 1))

                    // Details grid
                    detailCard("Details") {
                        detailRow("Timestamp", formatTimeFull(entry.timestamp))
                        detailRow("User", entry.username ?? "—")
                        detailRow("User ID", entry.user_id != nil ? "\(entry.user_id!)" : "—")
                        detailRow("Entity Type", entry.entity_type ?? "—")
                        detailRow("Entity ID", entry.entity_id != nil ? "#\(entry.entity_id!)" : "—")
                        detailRow("Log ID", "#\(entry.id)")
                    }

                    // Network info
                    detailCard("Network") {
                        detailRow("IP Address", entry.ip_address ?? "—")
                        if let ua = entry.user_agent {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("User Agent")
                                    .font(.custom("DMSans-SemiBold", size: 10))
                                    .foregroundColor(Color.theme.textSecondary)
                                Text(ua)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(Color.theme.text)
                                    .textSelection(.enabled)
                            }
                            .padding(.top, 4)
                        }
                    }

                    // Request body
                    if let body = entry.body, !body.displayPairs.isEmpty {
                        detailCard("Request Body") {
                            ForEach(body.displayPairs, id: \.key) { pair in
                                detailRow(pair.key, pair.value)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.theme.background)
            .navigationTitle("Log Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.custom("DMSans-Medium", size: 14))
                        .foregroundColor(Color(hex: "c8893a"))
                }
            }
        }
    }

    private func detailCard(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.custom("DMSans-SemiBold", size: 9))
                .foregroundColor(Color.theme.textSecondary)
                .tracking(0.4)
            VStack(alignment: .leading, spacing: 6) {
                content()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.theme.surface)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.theme.border, lineWidth: 1))
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.custom("DMSans-SemiBold", size: 11))
                .foregroundColor(Color.theme.textSecondary)
                .frame(width: 80, alignment: .trailing)
            Text(value)
                .font(.custom("DMSans-Regular", size: 12))
                .foregroundColor(Color.theme.text)
                .textSelection(.enabled)
            Spacer()
        }
    }

    private func actionColor(_ action: String?) -> Color {
        switch action {
        case "create", "upload":          return Color(hex: "2d6a4f")
        case "update":                    return Color(hex: "1d4e89")
        case "delete":                    return Color(hex: "c1121f")
        case "login":                     return Color(hex: "6c5ce7")
        case "toggle":                    return Color(hex: "e17055")
        case "assign", "create-and-assign": return Color(hex: "00b894")
        case "unassign", "unsave":        return Color(hex: "d63031")
        case "save":                      return Color(hex: "0984e3")
        case "purge":                     return Color(hex: "636e72")
        case "impersonate":               return Color(hex: "e84393")
        default:                          return Color(hex: "636e72")
        }
    }

    private func formatTimeFull(_ str: String?) -> String {
        guard let s = str else { return "—" }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = iso.date(from: s) ?? ISO8601DateFormatter().date(from: s) else {
            return String(s.prefix(19))
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, yyyy 'at' h:mm:ss a"
        return fmt.string(from: date)
    }
}

// MARK: - Stats Sheet

struct AuditLogStatsSheet: View {
    let stats: AuditLogStatsResponse?
    let onPurge: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                if let stats = stats {
                    VStack(spacing: 16) {
                        // Total
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Total Records")
                                    .font(.custom("DMSans-SemiBold", size: 13))
                                    .foregroundColor(Color.theme.text)
                                Text("\(stats.total_records)")
                                    .font(.custom("Syne-Bold", size: 28))
                                    .foregroundColor(Color(hex: "c8893a"))
                            }
                            Spacer()
                            Button(action: { onPurge(); dismiss() }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "trash").font(.system(size: 11))
                                    Text("Purge 30d+")
                                        .font(.custom("DMSans-Medium", size: 12))
                                }
                                .foregroundColor(Color(hex: "c1121f"))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color(hex: "c1121f").opacity(0.08))
                                .cornerRadius(50)
                            }
                        }
                        .padding(14)
                        .background(Color.theme.surface)
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.theme.border, lineWidth: 1))

                        // Last 24h section label
                        HStack {
                            Text("Last 24 Hours")
                                .font(.custom("DMSans-SemiBold", size: 14))
                                .foregroundColor(Color.theme.text)
                            Spacer()
                        }

                        // Actions breakdown
                        if !stats.last_24h.actions.isEmpty {
                            statsCard("By Action", items: stats.last_24h.actions.map { ($0.label, $0.count) })
                        }

                        // Entity breakdown
                        if !stats.last_24h.entities.isEmpty {
                            statsCard("By Entity", items: stats.last_24h.entities.map { ($0.label, $0.count) })
                        }

                        // Users breakdown
                        if !stats.last_24h.users.isEmpty {
                            statsCard("By User", items: stats.last_24h.users.map { ($0.username, $0.count) })
                        }
                    }
                    .padding(16)
                } else {
                    VStack { Spacer(); ProgressView("Loading stats…"); Spacer() }
                }
            }
            .background(Color.theme.background)
            .navigationTitle("Audit Stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.custom("DMSans-Medium", size: 14))
                        .foregroundColor(Color(hex: "c8893a"))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func statsCard(_ title: String, items: [(String, Int)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.custom("DMSans-SemiBold", size: 9))
                .foregroundColor(Color.theme.textSecondary)
                .tracking(0.4)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.0) { idx, item in
                    HStack {
                        Text(item.0)
                            .font(.custom("DMSans-Medium", size: 13))
                            .foregroundColor(Color.theme.text)
                        Spacer()
                        Text("\(item.1)")
                            .font(.custom("DMSans-Bold", size: 13))
                            .foregroundColor(Color(hex: "c8893a"))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    if idx < items.count - 1 {
                        Divider()
                    }
                }
            }
            .background(Color.theme.surface)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.theme.border, lineWidth: 1))
        }
    }
}
