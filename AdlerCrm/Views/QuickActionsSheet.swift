// /AdlerCRM/Views/QuickActionsSheet.swift  15/04/2026 01:32:00 EDT

import SwiftUI

struct QuickAction: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: QuickActionType
}

enum QuickActionType {
    case switchTab(String)
    case openSheet(SheetType)
}

enum SheetType {
    case notifications
    case tests
    case employees
}

struct QuickActionsSheet: View {
    @EnvironmentObject var auth: AuthManager
    let onAction: (QuickActionType) -> Void
    @Environment(\.dismiss) var dismiss

    private var actions: [QuickAction] {
        let items: [QuickAction] = [
            QuickAction(
                icon: "building.2.fill",
                title: "Businesses",
                subtitle: "Browse and manage accounts",
                color: Color.theme.text,
                action: .switchTab("businesses")
            ),
            QuickAction(
                icon: "point.topleft.down.to.point.bottomright.curvepath.fill",
                title: "Today's Route",
                subtitle: "View your assigned route",
                color: Color.theme.gold,
                action: .switchTab("routes")
            ),
            QuickAction(
                icon: "bell.fill",
                title: "Send Notification",
                subtitle: "Message a team member",
                color: Color.theme.gold,
                action: .openSheet(.notifications)
            ),
            QuickAction(
                icon: "checklist",
                title: "My To-Dos",
                subtitle: "View and manage your tasks",
                color: Color.theme.green,
                action: .switchTab("todo")
            ),
            QuickAction(
                icon: "calendar",
                title: "Calendar",
                subtitle: "View scheduled routes by date",
                color: Color.theme.text,
                action: .switchTab("calendar")
            ),
            QuickAction(
                icon: "map.fill",
                title: "Full Map",
                subtitle: "See all locations on the map",
                color: Color.theme.green,
                action: .switchTab("map")
            )
        ]

        return items
    }

    @State private var showMore = false
    @State private var showNotifications = false
    @State private var appReady = false
    @ObservedObject private var notifManager = NotificationManager.shared

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Greeting
                        Text(greeting)
                            .font(.custom("Syne-Bold", size: 26))
                            .foregroundColor(Color.theme.text)

                        // Action grid
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ], spacing: 12) {
                            ForEach(actions) { action in
                                Button {
                                    dismiss()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        onAction(action.action)
                                    }
                                } label: {
                                    actionCard(action)
                                }
                                .buttonStyle(.plain)
                                .disabled(!appReady)
                            }
                        }
                        .opacity(appReady ? 1 : 0.4)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    .padding(.top, 4)
                }
                .background(Color.theme.background)

                // Loading overlay
                if !appReady {
                    VStack(spacing: 16) {
                        Spacer()
                        Image("adler-logo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 80, height: 80)
                            .cornerRadius(16)
                        ProgressView()
                            .scaleEffect(1.1)
                            .tint(Color(hex: "c8893a"))
                        Text("Loading…")
                            .font(.custom("DMSans-Medium", size: 14))
                            .foregroundColor(Color.theme.textSecondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.theme.background.opacity(0.95))
                    .transition(.opacity)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 14) {
                        Button(action: { showMore = true }) {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(Color.theme.text)
                        }
                        Button(action: { showNotifications = true }) {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "bell.fill")
                                    .font(.system(size: 15))
                                    .foregroundColor(notifManager.unreadCount > 0 ? Color(hex: "c8893a") : Color.theme.textSecondary)
                                if notifManager.unreadCount > 0 {
                                    Text("\(min(notifManager.unreadCount, 99))")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(minWidth: 16, minHeight: 16)
                                        .background(Color(hex: "c1121f"))
                                        .cornerRadius(8)
                                        .offset(x: 8, y: -6)
                                }
                            }
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color.theme.textSecondary)
                    }
                }
            }
        }
        .sheet(isPresented: $showMore) {
            NavigationStack {
                MoreMenuView()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { showMore = false }
                                .font(.custom("DMSans-Medium", size: 14))
                                .foregroundColor(Color(hex: "c8893a"))
                        }
                    }
            }
        }
        .sheet(isPresented: $showNotifications) {
            NotificationsSheet()
        }
        .task {
            do {
                _ = try await APIClient.shared.getBusinesses()
            } catch { }
            withAnimation(.easeOut(duration: 0.3)) {
                appReady = true
            }
        }
    }

    // MARK: - Action Card

    private func actionCard(_ action: QuickAction) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: action.icon)
                .font(.system(size: 22))
                .foregroundColor(action.color)

            Text(action.title)
                .font(.custom("DMSans-SemiBold", size: 14))
                .foregroundColor(Color.theme.text)
                .lineLimit(1)

            Text(action.subtitle)
                .font(.custom("DMSans-Regular", size: 11))
                .foregroundColor(Color.theme.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.theme.surface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.theme.border, lineWidth: 1)
        )
    }

    // MARK: - Greeting

    private var greeting: String {
        let name = auth.currentUser?.name.components(separatedBy: " ").first ?? "there"
        let hour = Calendar.current.component(.hour, from: Date())
        let timeOfDay: String
        switch hour {
        case 0..<12: timeOfDay = "Good morning"
        case 12..<17: timeOfDay = "Good afternoon"
        default: timeOfDay = "Good evening"
        }
        return "\(timeOfDay), \(name)"
    }
}
