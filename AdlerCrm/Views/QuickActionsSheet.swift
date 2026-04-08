// /AdlerCRM/Views/QuickActionsSheet.swift  08/04/2026 01:05:00 EDT

import SwiftUI

struct QuickAction: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let subtitle: String
    let color: String
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

    private var isAdmin: Bool {
        auth.currentUser?.role == "Administrator"
    }

    private var actions: [QuickAction] {
        var items: [QuickAction] = [
            QuickAction(
                icon: "map.fill",
                title: "Full Map",
                subtitle: "See all business locations",
                color: "2d6a4f",
                action: .switchTab("map")
            ),
            QuickAction(
                icon: "building.2.fill",
                title: "Businesses",
                subtitle: "Browse and manage accounts",
                color: "0f1117",
                action: .switchTab("businesses")
            ),
            QuickAction(
                icon: "point.topleft.down.to.point.bottomright.curvepath.fill",
                title: "Today's Route",
                subtitle: "Calculate your pickup route",
                color: "c8893a",
                action: .switchTab("routes")
            ),
            QuickAction(
                icon: "bell.fill",
                title: "Send Notification",
                subtitle: "Message a team member",
                color: "c8893a",
                action: .openSheet(.notifications)
            ),
            QuickAction(
                icon: "checklist",
                title: "Create a To-Do",
                subtitle: "Add a task for today",
                color: "2d6a4f",
                action: .switchTab("todo")
            ),
            QuickAction(
                icon: "pencil.and.list.clipboard",
                title: "Custom Route",
                subtitle: "Build a manual route",
                color: "0f1117",
                action: .switchTab("custom")
            )
        ]

        if isAdmin {
            items.append(QuickAction(
                icon: "testtube.2",
                title: "Run Tests",
                subtitle: "Execute API test suite",
                color: "c1121f",
                action: .openSheet(.tests)
            ))
            items.append(QuickAction(
                icon: "person.2.fill",
                title: "Employees",
                subtitle: "Manage team members",
                color: "7a7f94",
                action: .openSheet(.employees)
            ))
        }

        return items
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Greeting
                    VStack(alignment: .leading, spacing: 4) {
                        Text(greeting)
                            .font(.custom("Syne-Bold", size: 26))
                            .foregroundColor(Color(hex: "0f1117"))
                        Text("What would you like to do?")
                            .font(.custom("DMSans-Regular", size: 15))
                            .foregroundColor(Color(hex: "7a7f94"))
                    }
                    .padding(.top, 8)

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
                        }
                    }
                }
                .padding(20)
            }
            .background(Color(hex: "f5f4f0"))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Skip") { dismiss() }
                        .font(.custom("DMSans-Medium", size: 14))
                        .foregroundColor(Color(hex: "7a7f94"))
                }
            }
        }
    }

    // MARK: - Action Card

    private func actionCard(_ action: QuickAction) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: action.icon)
                .font(.system(size: 22))
                .foregroundColor(Color(hex: action.color))

            Text(action.title)
                .font(.custom("DMSans-SemiBold", size: 14))
                .foregroundColor(Color(hex: "0f1117"))
                .lineLimit(1)

            Text(action.subtitle)
                .font(.custom("DMSans-Regular", size: 11))
                .foregroundColor(Color(hex: "7a7f94"))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: "e2dfd6"), lineWidth: 1)
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
