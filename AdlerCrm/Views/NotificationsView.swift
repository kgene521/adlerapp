// AdlerCRM/Views/NotificationsView.swift  03/04/2026 01:16:20
import SwiftUI

// MARK: - Notifications List Sheet

struct NotificationsSheet: View {
    @ObservedObject var notifManager = NotificationManager.shared
    @Environment(\.dismiss) var dismiss
    @State private var notifications: [AppNotification] = []
    @State private var loading = true
    @State private var showComposeSheet = false
    @State private var showDeleteConfirm = false
    @State private var notifToDelete: AppNotification?

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    VStack { Spacer(); ProgressView("Loading…").font(.custom("DMSans-Regular", size: 14)); Spacer() }
                } else if notifications.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "bell.slash")
                            .font(.system(size: 40)).foregroundColor(Color(hex: "e2dfd6"))
                        Text("No notifications")
                            .font(.custom("DMSans-Regular", size: 14)).foregroundColor(Color(hex: "7a7f94"))
                        Spacer()
                    }
                } else {
                    List {
                        let unread = notifications.filter { $0.is_read != true }
                        if !unread.isEmpty {
                            Section {
                                ForEach(unread) { n in notificationRow(n) }
                            } header: {
                                HStack {
                                    Text("UNREAD (\(unread.count))")
                                        .font(.custom("DMSans-SemiBold", size: 10)).foregroundColor(Color(hex: "c1121f")).tracking(0.4)
                                    Spacer()
                                    Button("Mark All Read") { markAllRead() }
                                        .font(.custom("DMSans-Medium", size: 11)).foregroundColor(Color(hex: "c8893a"))
                                }
                            }
                        }

                        let read = notifications.filter { $0.is_read == true }
                        if !read.isEmpty {
                            Section {
                                ForEach(read) { n in notificationRow(n) }
                            } header: {
                                Text("READ").font(.custom("DMSans-SemiBold", size: 10)).foregroundColor(Color(hex: "7a7f94")).tracking(0.4)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showComposeSheet = true }) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 14)).foregroundColor(Color(hex: "c8893a"))
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.custom("DMSans-Medium", size: 14)).foregroundColor(Color(hex: "c8893a"))
                }
            }
            .task { await loadNotifications() }
            .sheet(isPresented: $showComposeSheet) {
                ComposeNotificationSheet(onSent: { Task { await loadNotifications() } })
            }
            .confirmationDialog("Delete this notification?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let n = notifToDelete { deleteNotif(n) }
                }
                Button("Cancel", role: .cancel) { notifToDelete = nil }
            }
        }
    }

    private func notificationRow(_ n: AppNotification) -> some View {
        HStack(spacing: 12) {
            // Priority indicator
            Circle()
                .fill(priorityColor(n.priority))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(n.message)
                    .font(.custom(n.is_read == true ? "DMSans-Regular" : "DMSans-SemiBold", size: 14))
                    .foregroundColor(n.is_read == true ? Color(hex: "7a7f94") : Color(hex: "0f1117"))
                    .lineLimit(3)

                HStack(spacing: 8) {
                    if let from = n.from_user_name {
                        Label(from, systemImage: "person.fill")
                            .font(.custom("DMSans-Medium", size: 10)).foregroundColor(Color(hex: "c8893a"))
                    }
                    Text(formatTime(n.created_at))
                        .font(.custom("DMSans-Regular", size: 10)).foregroundColor(Color(hex: "7a7f94"))
                    if let p = n.priority, p != "normal" {
                        Text(p.uppercased())
                            .font(.custom("DMSans-SemiBold", size: 8))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(priorityColor(n.priority))
                            .cornerRadius(50)
                    }
                }
            }

            Spacer()

            Menu {
                if n.is_read != true {
                    Button(action: { markRead(n) }) { Label("Mark Read", systemImage: "envelope.open") }
                }
                Button(role: .destructive, action: { notifToDelete = n; showDeleteConfirm = true }) {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 14)).foregroundColor(Color(hex: "7a7f94")).frame(width: 28, height: 28)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if n.is_read != true { markRead(n) }
        }
    }

    private func loadNotifications() async {
        loading = true
        do { notifications = try await APIClient.shared.getNotifications() } catch { }
        loading = false
        notifManager.poll()
    }

    private func markRead(_ n: AppNotification) {
        Task {
            do { try await APIClient.shared.markNotificationRead(id: n.id); await loadNotifications() } catch { }
        }
    }

    private func markAllRead() {
        Task {
            do { try await APIClient.shared.markAllNotificationsRead(); await loadNotifications() } catch { }
        }
    }

    private func deleteNotif(_ n: AppNotification) {
        Task {
            do { try await APIClient.shared.deleteNotification(id: n.id); await loadNotifications() } catch { }
            notifToDelete = nil
        }
    }

    private func priorityColor(_ p: String?) -> Color {
        switch p {
        case "urgent": return Color(hex: "c1121f")
        case "high": return Color(hex: "c8893a")
        case "low": return Color(hex: "7a7f94")
        default: return Color(hex: "2d6a4f")
        }
    }

    private func formatTime(_ str: String?) -> String {
        guard let s = str else { return "" }
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = iso.date(from: s) ?? ISO8601DateFormatter().date(from: s) else { return String(s.prefix(10)) }
        let fmt = DateFormatter(); fmt.dateFormat = "MMM d, h:mm a"; return fmt.string(from: date)
    }
}

// MARK: - Compose Notification Sheet

struct ComposeNotificationSheet: View {
    let onSent: () -> Void
    @Environment(\.dismiss) var dismiss
    @State private var users: [NotificationUser] = []
    @State private var selectedUserId: Int?
    @State private var message = ""
    @State private var priority = "normal"
    @State private var sending = false
    @State private var errorMsg = ""
    @State private var loading = true

    let priorities = ["low", "normal", "high", "urgent"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if !errorMsg.isEmpty {
                        Text(errorMsg).font(.custom("DMSans-Regular", size: 13)).foregroundColor(Color(hex: "c1121f"))
                            .padding(12).frame(maxWidth: .infinity).background(Color(hex: "ffe5e7")).cornerRadius(8)
                    }

                    // Recipient picker
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TO").font(.custom("DMSans-SemiBold", size: 9)).foregroundColor(Color(hex: "7a7f94")).tracking(0.4)
                        if loading {
                            ProgressView().padding(.vertical, 8)
                        } else {
                            Picker("Recipient", selection: Binding(
                                get: { selectedUserId ?? -1 },
                                set: { selectedUserId = $0 == -1 ? nil : $0 }
                            )) {
                                Text("Select a user…").tag(-1)
                                ForEach(users) { user in
                                    Text("\(user.name) (\(user.role ?? ""))").tag(user.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(Color(hex: "c8893a"))
                        }
                    }

                    // Message
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MESSAGE").font(.custom("DMSans-SemiBold", size: 9)).foregroundColor(Color(hex: "7a7f94")).tracking(0.4)
                        TextEditor(text: $message)
                            .font(.custom("DMSans-Regular", size: 14))
                            .frame(minHeight: 100)
                            .padding(8)
                            .background(Color.white)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "e2dfd6"), lineWidth: 1))
                    }

                    // Priority
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PRIORITY").font(.custom("DMSans-SemiBold", size: 9)).foregroundColor(Color(hex: "7a7f94")).tracking(0.4)
                        Picker("Priority", selection: $priority) {
                            ForEach(priorities, id: \.self) { p in
                                Text(p.capitalized).tag(p)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .padding(20)
            }
            .background(Color(hex: "f5f4f0"))
            .navigationTitle("Send Notification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.custom("DMSans-Regular", size: 14)).foregroundColor(Color(hex: "7a7f94"))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: send) {
                        if sending { ProgressView().scaleEffect(0.8) }
                        else { Text("Send").font(.custom("DMSans-SemiBold", size: 14)) }
                    }
                    .foregroundColor(Color(hex: "2d6a4f"))
                    .disabled(selectedUserId == nil || message.trimmingCharacters(in: .whitespaces).isEmpty || sending)
                }
            }
            .task { await loadUsers() }
        }
    }

    private func loadUsers() async {
        loading = true
        do { users = try await APIClient.shared.getNotificationUsers() } catch { }
        loading = false
    }

    private func send() {
        guard let uid = selectedUserId else { return }
        sending = true; errorMsg = ""
        Task {
            do {
                _ = try await APIClient.shared.sendNotification(toUserId: uid, message: message.trimmingCharacters(in: .whitespaces), priority: priority)
                onSent(); dismiss()
            } catch { errorMsg = error.localizedDescription }
            sending = false
        }
    }
}

// MARK: - Notification Banner Overlay

struct NotificationBanner: View {
    @ObservedObject var notifManager = NotificationManager.shared
    @Binding var showNotifications: Bool

    var body: some View {
        if notifManager.unreadCount > 0 {
            VStack {
                Button(action: { showNotifications = true }) {
                    HStack(spacing: 10) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                        Text("You have \(notifManager.unreadCount) unread notification\(notifManager.unreadCount == 1 ? "" : "s")")
                            .font(.custom("DMSans-SemiBold", size: 13))
                            .foregroundColor(.white)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(hex: "c8893a"))
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                Spacer()
            }
        }
    }
}
