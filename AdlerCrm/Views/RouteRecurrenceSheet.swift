// /AdlerCRM/Views/RouteRecurrenceSheet.swift  12/04/2026 22:39:00 EDT
import SwiftUI

struct RouteRecurrenceSheet: View {
    let routeId: Int?
    let routeName: String
    let currentStart: String?
    let currentInterval: Int?
    let currentUnit: String?
    let onSave: (String?, Int?, String?) -> Void

    @Environment(\.dismiss) var dismiss
    @State private var enabled = false
    @State private var startDate = Date()
    @State private var interval = 1
    @State private var unit = "week"
    @State private var saving = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Route name
                HStack(spacing: 8) {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "c8893a"))
                    Text(routeName)
                        .font(.custom("DMSans-SemiBold", size: 14))
                        .foregroundColor(Color.theme.text)
                        .lineLimit(1)
                    Spacer()
                }

                // Enable toggle
                Toggle(isOn: $enabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recurring route")
                            .font(.custom("DMSans-SemiBold", size: 14))
                            .foregroundColor(Color.theme.text)
                        Text("Automatically appears in Calendar on matching dates")
                            .font(.custom("DMSans-Regular", size: 12))
                            .foregroundColor(Color.theme.textSecondary)
                    }
                }
                .tint(Color(hex: "c8893a"))

                if enabled {
                    VStack(alignment: .leading, spacing: 14) {
                        DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                            .font(.custom("DMSans-Medium", size: 14))
                            .tint(Color(hex: "c8893a"))

                        HStack(spacing: 12) {
                            Text("Repeat every")
                                .font(.custom("DMSans-Medium", size: 14))
                                .foregroundColor(Color.theme.text)
                            Picker("Interval", selection: $interval) {
                                ForEach(1..<31) { n in Text("\(n)").tag(n) }
                            }
                            .pickerStyle(.menu)
                            .tint(Color(hex: "c8893a"))
                            Picker("Unit", selection: $unit) {
                                Text("Days").tag("day")
                                Text("Weeks").tag("week")
                                Text("Months").tag("month")
                            }
                            .pickerStyle(.menu)
                            .tint(Color(hex: "c8893a"))
                        }

                        // Summary
                        HStack(spacing: 6) {
                            Image(systemName: "repeat")
                                .font(.system(size: 12))
                            Text(recurrenceSummary)
                                .font(.custom("DMSans-Regular", size: 13))
                        }
                        .foregroundColor(Color(hex: "2d6a4f"))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.theme.green.opacity(0.08))
                        .cornerRadius(8)
                    }
                    .padding(14)
                    .background(Color.theme.surface)
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.theme.border, lineWidth: 1))
                }

                Spacer()
            }
            .padding(20)
            .background(Color.theme.background)
            .navigationTitle("Recurrence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.custom("DMSans-Regular", size: 14))
                        .foregroundColor(Color.theme.textSecondary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Apply") {
                        if enabled {
                            let dateStr = startDate.formatted(.iso8601).prefix(10).description
                            onSave(dateStr, interval, unit)
                        } else {
                            onSave(nil, nil, nil)
                        }
                        dismiss()
                    }
                    .font(.custom("DMSans-SemiBold", size: 14))
                    .foregroundColor(Color(hex: "2d6a4f"))
                }
            }
            .onAppear {
                if let cs = currentStart, let ci = currentInterval, let cu = currentUnit {
                    enabled = true
                    interval = ci
                    unit = cu
                    let fmt = DateFormatter()
                    fmt.dateFormat = "yyyy-MM-dd"
                    if let d = fmt.date(from: cs) { startDate = d }
                } else {
                    enabled = false
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var recurrenceSummary: String {
        let unitLabel: String
        switch unit {
        case "day": unitLabel = interval == 1 ? "day" : "days"
        case "week": unitLabel = interval == 1 ? "week" : "weeks"
        case "month": unitLabel = interval == 1 ? "month" : "months"
        default: unitLabel = unit
        }
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        let dateStr = fmt.string(from: startDate)
        if interval == 1 {
            return "Every \(unitLabel) starting \(dateStr)"
        }
        return "Every \(interval) \(unitLabel) starting \(dateStr)"
    }
}
