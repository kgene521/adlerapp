// /AdlerCRM/Views/RouteRenameSheet.swift  11/04/2026 00:44:00 EDT
import SwiftUI

struct RouteRenameSheet: View {
    let currentName: String
    let onRename: (String) -> Void

    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var saving = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ROUTE NAME")
                        .font(.custom("DMSans-SemiBold", size: 9))
                        .foregroundColor(Color.theme.textSecondary)
                        .tracking(0.4)
                    TextField("Route name", text: $name)
                        .font(.custom("DMSans-Regular", size: 14))
                        .foregroundColor(Color.theme.text)
                        .padding(12)
                        .background(Color.theme.inputBackground)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.theme.border, lineWidth: 1))
                }

                Spacer()
            }
            .padding(20)
            .background(Color.theme.background)
            .navigationTitle("Rename Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.custom("DMSans-Regular", size: 14))
                        .foregroundColor(Color.theme.textSecondary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty, trimmed != currentName else {
                            dismiss(); return
                        }
                        saving = true
                        onRename(trimmed)
                        dismiss()
                    }
                    .font(.custom("DMSans-SemiBold", size: 14))
                    .foregroundColor(Color(hex: "2d6a4f"))
                    .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { name = currentName }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
