// AdlerCRM/Views/RegionsView.swift  27/03/2026 16:30:48
import SwiftUI
import Combine

struct RegionsView: View {
    @State private var regions: [Region] = []
    @State private var employees: [Employee] = []
    @State private var loading = true
    @State private var errorMsg = ""
    @State private var showAddSheet = false
    @State private var editingRegion: Region?

    var body: some View {
        VStack(spacing: 0) {
            if loading {
                Spacer()
                ProgressView("Loading regions…")
                    .font(.custom("DMSans-Regular", size: 14))
                Spacer()
            } else if !errorMsg.isEmpty {
                errorView
            } else if regions.isEmpty {
                emptyView
            } else {
                regionsList
            }
        }
        .navigationTitle("Regions")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    Button(action: { showAddSheet = true }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(Color(hex: "c8893a"))
                    }
                    Button(action: reload) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(Color(hex: "7a7f94"))
                    }
                }
            }
        }
        .task { await loadData() }
        .sheet(isPresented: $showAddSheet) {
            RegionFormSheet(region: nil, onSave: reload)
        }
        .sheet(item: $editingRegion) { region in
            RegionFormSheet(region: region, onSave: reload)
        }
    }

    // MARK: - List

    private var regionsList: some View {
        List {
            ForEach(regions) { region in
                RegionCard(
                    region: region,
                    employees: employees,
                    onEdit: { editingRegion = region },
                    onReload: reload
                )
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "map.circle")
                .font(.system(size: 44))
                .foregroundColor(Color(hex: "e2dfd6"))
            Text("No regions yet")
                .font(.custom("Syne-Bold", size: 20))
                .foregroundColor(Color(hex: "0f1117"))
            Text("Create regions to organize businesses and collection routes by area.")
                .font(.custom("DMSans-Regular", size: 14))
                .foregroundColor(Color(hex: "7a7f94"))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button(action: { showAddSheet = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Create Region")
                }
                .font(.custom("DMSans-SemiBold", size: 14))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(Color(hex: "c8893a"))
                .cornerRadius(8)
            }
            Spacer()
        }
    }

    // MARK: - Error

    private var errorView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundColor(Color(hex: "c1121f"))
            Text(errorMsg)
                .font(.custom("DMSans-Regular", size: 14))
                .foregroundColor(Color(hex: "3a3d4a"))
                .multilineTextAlignment(.center)
            Button("Retry") { reload() }
                .font(.custom("DMSans-SemiBold", size: 14))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(Color(hex: "0f1117"))
                .cornerRadius(8)
            Spacer()
        }
        .padding()
    }

    // MARK: - Data

    private func reload() { Task { await loadData() } }

    private func loadData() async {
        loading = true; errorMsg = ""
        do {
            async let r = APIClient.shared.getRegions()
            async let e = APIClient.shared.getEmployees()
            regions = try await r
            employees = try await e
        } catch {
            errorMsg = error.localizedDescription
        }
        loading = false
    }
}

// MARK: - Region Card

struct RegionCard: View {
    let region: Region
    let employees: [Employee]
    let onEdit: () -> Void
    let onReload: () -> Void

    @State private var showAddMember = false
    @State private var selectedUserId: Int?
    @State private var showDeleteConfirm = false

    private var members: [RegionMember] { region.members ?? [] }

    private var assignedUserIds: Set<Int> {
        Set(members.map { $0.user_id })
    }

    private var availableEmployees: [Employee] {
        employees.filter { !assignedUserIds.contains($0.id) && $0.is_active == true }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(region.name)
                        .font(.custom("Syne-Bold", size: 17))
                        .foregroundColor(Color(hex: "0f1117"))
                    if let notes = region.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.custom("DMSans-Regular", size: 12))
                            .foregroundColor(Color(hex: "7a7f94"))
                            .lineLimit(2)
                    }
                }
                Spacer()
                HStack(spacing: 8) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(Color(hex: "c8893a"))
                    }
                    .buttonStyle(.plain)

                    Button(action: { showDeleteConfirm = true }) {
                        Image(systemName: "trash.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(Color(hex: "c1121f").opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            // Members header
            HStack {
                Text("MEMBERS (\(members.count))")
                    .font(.custom("DMSans-SemiBold", size: 9))
                    .foregroundColor(Color(hex: "7a7f94"))
                    .tracking(0.5)
                Spacer()
                if !availableEmployees.isEmpty {
                    Button(action: { showAddMember.toggle() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .bold))
                            Text("Add")
                                .font(.custom("DMSans-SemiBold", size: 11))
                        }
                        .foregroundColor(Color(hex: "c8893a"))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Add member picker
            if showAddMember {
                HStack(spacing: 8) {
                    Picker("Employee", selection: $selectedUserId) {
                        Text("Select employee…").tag(nil as Int?)
                        ForEach(availableEmployees) { emp in
                            Text("\(emp.name) (\(emp.role ?? ""))").tag(emp.id as Int?)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Color(hex: "0f1117"))
                    .font(.custom("DMSans-Regular", size: 13))

                    Button("Add") { addMember() }
                        .font(.custom("DMSans-SemiBold", size: 12))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(hex: "2d6a4f"))
                        .cornerRadius(6)
                        .disabled(selectedUserId == nil)
                        .opacity(selectedUserId == nil ? 0.5 : 1)

                    Button("Cancel") {
                        showAddMember = false
                        selectedUserId = nil
                    }
                    .font(.custom("DMSans-Regular", size: 12))
                    .foregroundColor(Color(hex: "7a7f94"))
                }
                .padding(10)
                .background(Color(hex: "f5f4f0"))
                .cornerRadius(8)
            }

            // Member list
            if members.isEmpty {
                Text("No members assigned")
                    .font(.custom("DMSans-Regular", size: 13))
                    .foregroundColor(Color(hex: "7a7f94"))
                    .italic()
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(members) { member in
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(Color(hex: "c8893a"))
                                    .frame(width: 28, height: 28)
                                Text(initials(member.name))
                                    .font(.custom("DMSans-SemiBold", size: 10))
                                    .foregroundColor(.white)
                            }

                            VStack(alignment: .leading, spacing: 1) {
                                Text(member.name)
                                    .font(.custom("DMSans-SemiBold", size: 13))
                                    .foregroundColor(Color(hex: "0f1117"))
                                Text("\(member.username) · \(member.role)")
                                    .font(.custom("DMSans-Regular", size: 11))
                                    .foregroundColor(Color(hex: "7a7f94"))
                            }

                            Spacer()

                            Button(action: { removeMember(member.user_id) }) {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(Color(hex: "c1121f").opacity(0.5))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 6)

                        if member.user_id != members.last?.user_id {
                            Divider().padding(.leading, 38)
                        }
                    }
                }
            }
        }
        .padding(16)
        .confirmationDialog("Delete \"\(region.name)\"?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete Region", role: .destructive) { deleteRegion() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will unassign all businesses and remove all members from this region.")
        }
    }

    // MARK: - Actions

    private func addMember() {
        guard let userId = selectedUserId else { return }
        Task {
            do {
                _ = try await APIClient.shared.addRegionMember(regionId: region.id, userId: userId)
                selectedUserId = nil
                showAddMember = false
                onReload()
            } catch { }
        }
    }

    private func removeMember(_ userId: Int) {
        Task {
            do {
                _ = try await APIClient.shared.removeRegionMember(regionId: region.id, userId: userId)
                onReload()
            } catch { }
        }
    }

    private func deleteRegion() {
        Task {
            do {
                _ = try await APIClient.shared.deleteRegion(id: region.id)
                onReload()
            } catch { }
        }
    }

    private func initials(_ name: String) -> String {
        name.split(separator: " ").prefix(2).map { String($0.prefix(1)) }.joined().uppercased()
    }
}

// MARK: - Region Form Sheet (Add / Edit)

struct RegionFormSheet: View {
    let region: Region?
    let onSave: () -> Void

    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var notes = ""
    @State private var saving = false
    @State private var errorMsg = ""

    private var isEditing: Bool { region != nil }

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
                            .background(Color(hex: "ffe5e7"))
                            .cornerRadius(8)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("REGION NAME *")
                            .font(.custom("DMSans-SemiBold", size: 9))
                            .foregroundColor(Color(hex: "7a7f94"))
                            .tracking(0.4)
                        TextField("e.g. Southwest VA", text: $name)
                            .font(.custom("DMSans-Regular", size: 14))
                            .padding(12)
                            .background(Color.white)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "e2dfd6"), lineWidth: 1))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("NOTES")
                            .font(.custom("DMSans-SemiBold", size: 9))
                            .foregroundColor(Color(hex: "7a7f94"))
                            .tracking(0.4)
                        TextEditor(text: $notes)
                            .font(.custom("DMSans-Regular", size: 14))
                            .frame(minHeight: 100)
                            .padding(8)
                            .scrollContentBackground(.hidden)
                            .background(Color.white)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "e2dfd6"), lineWidth: 1))
                    }
                }
                .padding(20)
            }
            .background(Color(hex: "f5f4f0"))
            .navigationTitle(isEditing ? "Edit Region" : "Create Region")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.custom("DMSans-Regular", size: 14))
                        .foregroundColor(Color(hex: "7a7f94"))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: save) {
                        if saving { ProgressView().scaleEffect(0.8) }
                        else { Text("Save").font(.custom("DMSans-SemiBold", size: 14)) }
                    }
                    .foregroundColor(Color(hex: "2d6a4f"))
                    .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let r = region {
                    name = r.name
                    notes = r.notes ?? ""
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        saving = true; errorMsg = ""

        Task {
            do {
                if let r = region {
                    _ = try await APIClient.shared.updateRegion(id: r.id, name: trimmed, notes: notes.isEmpty ? nil : notes)
                } else {
                    _ = try await APIClient.shared.createRegion(name: trimmed, notes: notes.isEmpty ? nil : notes)
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

#Preview {
    NavigationStack { RegionsView() }.environmentObject(AuthManager())
}
