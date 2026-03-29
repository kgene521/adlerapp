// AdlerCRM/Views/ContactEventViews.swift  27/03/2026 23:52:35
import SwiftUI
import Combine

// MARK: - Contacts Section (used in BusinessDetailView)

struct ContactsSection: View {
    let contacts: [BusinessContact]
    let loading: Bool
    let businessId: Int
    let locations: [Location]
    let onReload: () -> Void

    @State private var showAddSheet = false
    @State private var editingContact: BusinessContact?

    private var primaryContacts: [BusinessContact] {
        contacts.filter { $0.is_primary == true }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Contacts")
                    .font(.custom("Syne-Bold", size: 16))
                    .foregroundColor(Color(hex: "0f1117"))
                Spacer()
                Text("\(contacts.count)")
                    .font(.custom("DMSans-SemiBold", size: 12))
                    .foregroundColor(Color(hex: "1d4e89"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color(hex: "dbeafe"))
                    .cornerRadius(50)

                Button(action: { showAddSheet = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(Color(hex: "c8893a"))
                }
            }

            if loading {
                HStack { Spacer(); ProgressView().padding(.vertical, 20); Spacer() }
            } else if contacts.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 28))
                        .foregroundColor(Color(hex: "e2dfd6"))
                    Text("No contacts yet")
                        .font(.custom("DMSans-Regular", size: 13))
                        .foregroundColor(Color(hex: "7a7f94"))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(contacts) { contact in
                        Button(action: { editingContact = contact }) {
                            ContactRow(contact: contact)
                        }
                        .buttonStyle(.plain)
                        if contact.id != contacts.last?.id {
                            Divider().padding(.leading, 36)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 8, y: 2)
        .sheet(isPresented: $showAddSheet) {
            ContactFormSheet(
                businessId: businessId,
                contact: nil,
                onSave: onReload
            )
        }
        .sheet(item: $editingContact) { contact in
            ContactFormSheet(
                businessId: businessId,
                contact: contact,
                onSave: onReload
            )
        }
    }
}

// MARK: - Contact Row

struct ContactRow: View {
    let contact: BusinessContact

    var body: some View {
        HStack(spacing: 12) {
            // Avatar circle
            ZStack {
                Circle()
                    .fill(contact.is_primary == true ? Color(hex: "c8893a") : Color(hex: "e2dfd6"))
                    .frame(width: 32, height: 32)
                Text(initials)
                    .font(.custom("DMSans-SemiBold", size: 12))
                    .foregroundColor(contact.is_primary == true ? .white : Color(hex: "7a7f94"))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(contact.name)
                        .font(.custom("DMSans-SemiBold", size: 14))
                        .foregroundColor(Color(hex: "0f1117"))
                    if contact.is_primary == true {
                        Text("Primary")
                            .font(.custom("DMSans-SemiBold", size: 9))
                            .foregroundColor(Color(hex: "c8893a"))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color(hex: "fef3c7"))
                            .cornerRadius(50)
                    }
                }
                if let title = contact.title, !title.isEmpty {
                    Text(title)
                        .font(.custom("DMSans-Regular", size: 12))
                        .foregroundColor(Color(hex: "7a7f94"))
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if let phone = contact.phone, !phone.isEmpty {
                    Label(phone, systemImage: "phone")
                        .font(.custom("DMSans-Regular", size: 11))
                        .foregroundColor(Color(hex: "7a7f94"))
                        .lineLimit(1)
                }
                if let email = contact.email, !email.isEmpty {
                    Label(email, systemImage: "envelope")
                        .font(.custom("DMSans-Regular", size: 10))
                        .foregroundColor(Color(hex: "7a7f94"))
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var initials: String {
        contact.name.split(separator: " ").prefix(2).map { String($0.prefix(1)) }.joined().uppercased()
    }
}

// MARK: - Contact Form Sheet (Add / Edit)

struct ContactFormSheet: View {
    let businessId: Int
    let contact: BusinessContact?
    let onSave: () -> Void

    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var title = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var isPrimary = false
    @State private var saving = false
    @State private var errorMsg = ""

    private var isEditing: Bool { contact != nil }

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

                    formField(label: "Name *", text: $name, placeholder: "Full name")
                    formField(label: "Title", text: $title, placeholder: "e.g. Manager, Owner")
                    formField(label: "Phone", text: $phone, placeholder: "540-555-1234", keyboard: .phonePad)
                    formField(label: "Email", text: $email, placeholder: "name@example.com", keyboard: .emailAddress)

                    Toggle(isOn: $isPrimary) {
                        Text("Primary Contact")
                            .font(.custom("DMSans-Medium", size: 14))
                            .foregroundColor(Color(hex: "0f1117"))
                    }
                    .tint(Color(hex: "c8893a"))

                    if isEditing {
                        Button(action: deleteContact) {
                            Label("Delete Contact", systemImage: "trash")
                                .font(.custom("DMSans-Medium", size: 14))
                                .foregroundColor(Color(hex: "c1121f"))
                        }
                        .padding(.top, 12)
                    }
                }
                .padding(20)
            }
            .background(Color(hex: "f5f4f0"))
            .navigationTitle(isEditing ? "Edit Contact" : "Add Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.custom("DMSans-Regular", size: 14))
                        .foregroundColor(Color(hex: "7a7f94"))
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
                    .disabled(saving || name.isEmpty)
                }
            }
            .onAppear {
                if let c = contact {
                    name = c.name
                    title = c.title ?? ""
                    phone = c.phone ?? ""
                    email = c.email ?? ""
                    isPrimary = c.is_primary ?? false
                }
            }
        }
    }

    private func formField(label: String, text: Binding<String>, placeholder: String, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.custom("DMSans-SemiBold", size: 9))
                .foregroundColor(Color(hex: "7a7f94"))
                .tracking(0.4)
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .autocapitalization(keyboard == .emailAddress ? .none : .words)
                .font(.custom("DMSans-Regular", size: 14))
                .padding(12)
                .background(Color.white)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "e2dfd6"), lineWidth: 1))
        }
    }

    private func save() {
        saving = true
        errorMsg = ""
        Task {
            do {
                if let c = contact {
                    _ = try await APIClient.shared.updateContact(
                        id: c.id, name: name, title: title.isEmpty ? nil : title,
                        phone: phone.isEmpty ? nil : phone, email: email.isEmpty ? nil : email,
                        isPrimary: isPrimary
                    )
                } else {
                    _ = try await APIClient.shared.createContact(
                        bizId: businessId, name: name, title: title.isEmpty ? nil : title,
                        phone: phone.isEmpty ? nil : phone, email: email.isEmpty ? nil : email,
                        isPrimary: isPrimary
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

    private func deleteContact() {
        guard let c = contact else { return }
        saving = true
        Task {
            do {
                _ = try await APIClient.shared.deleteContact(id: c.id)
                onSave()
                dismiss()
            } catch {
                errorMsg = error.localizedDescription
            }
            saving = false
        }
    }
}

// MARK: - Events Section (used in BusinessDetailView)

struct EventsSection: View {
    let events: [ContactEvent]
    let loading: Bool
    let businessId: Int
    let contacts: [BusinessContact]
    let locations: [Location]
    let onReload: () -> Void

    @State private var showLogSheet = false
    @State private var selectedEvent: ContactEvent?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Contact Events")
                    .font(.custom("Syne-Bold", size: 16))
                    .foregroundColor(Color(hex: "0f1117"))
                Spacer()
                Text("\(events.count)")
                    .font(.custom("DMSans-SemiBold", size: 12))
                    .foregroundColor(Color(hex: "c8893a"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color(hex: "fef3c7"))
                    .cornerRadius(50)

                Button(action: { showLogSheet = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("Log")
                            .font(.custom("DMSans-SemiBold", size: 12))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(hex: "c8893a"))
                    .cornerRadius(50)
                }
            }

            if loading {
                HStack { Spacer(); ProgressView().padding(.vertical, 20); Spacer() }
            } else if events.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 28))
                        .foregroundColor(Color(hex: "e2dfd6"))
                    Text("No events logged yet")
                        .font(.custom("DMSans-Regular", size: 13))
                        .foregroundColor(Color(hex: "7a7f94"))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(events) { event in
                        Button(action: { selectedEvent = event }) {
                            EventRow(event: event)
                        }
                        .buttonStyle(.plain)
                        if event.id != events.last?.id {
                            Divider().padding(.leading, 36)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 8, y: 2)
        .sheet(isPresented: $showLogSheet) {
            LogEventSheet(
                businessId: businessId,
                contacts: contacts,
                locations: locations,
                onSave: onReload
            )
        }
        .sheet(item: $selectedEvent) { event in
            EventDetailSheet(event: event)
        }
    }
}

// MARK: - Event Row

struct EventRow: View {
    let event: ContactEvent

    var body: some View {
        HStack(spacing: 12) {
            // Method icon
            Image(systemName: methodIcon)
                .font(.system(size: 16))
                .foregroundColor(methodColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.subject ?? "No subject")
                    .font(.custom("DMSans-SemiBold", size: 14))
                    .foregroundColor(Color(hex: "0f1117"))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(event.method ?? "Phone Call")
                        .font(.custom("DMSans-Medium", size: 11))
                        .foregroundColor(methodColor)

                    if let contact = event.contact_name, !contact.isEmpty {
                        Text("· \(contact)")
                            .font(.custom("DMSans-Regular", size: 11))
                            .foregroundColor(Color(hex: "7a7f94"))
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(shortDate(event.event_date))
                    .font(.custom("DMSans-Medium", size: 11))
                    .foregroundColor(Color(hex: "0f1117"))

                if event.follow_up_required == true {
                    HStack(spacing: 3) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 8))
                        Text(shortDate(event.follow_up_date))
                            .font(.custom("DMSans-Regular", size: 10))
                    }
                    .foregroundColor(Color(hex: "c1121f"))
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var methodIcon: String {
        switch event.method {
        case "Phone Call": return "phone.fill"
        case "Email": return "envelope.fill"
        case "In-Person": return "person.fill"
        case "Text": return "message.fill"
        default: return "phone.fill"
        }
    }

    private var methodColor: Color {
        switch event.method {
        case "Phone Call": return Color(hex: "1d4e89")
        case "Email": return Color(hex: "2d6a4f")
        case "In-Person": return Color(hex: "c8893a")
        case "Text": return Color(hex: "911eb4")
        default: return Color(hex: "1d4e89")
        }
    }

    private func shortDate(_ dateStr: String?) -> String {
        guard let dateStr = dateStr else { return "—" }
        let prefix = String(dateStr.prefix(10))
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        if let date = fmt.date(from: prefix) {
            fmt.dateFormat = "M/d/yy"
            return fmt.string(from: date)
        }
        return String(prefix.suffix(5))
    }
}

// MARK: - Event Detail Sheet

struct EventDetailSheet: View {
    let event: ContactEvent
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Subject
                    Text(event.subject ?? "No subject")
                        .font(.custom("Syne-Bold", size: 20))
                        .foregroundColor(Color(hex: "0f1117"))

                    // Meta grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        detailItem(icon: methodIcon, label: "Method", value: event.method ?? "Phone Call", color: methodColor)
                        detailItem(icon: "calendar", label: "Date", value: formatDate(event.event_date), color: Color(hex: "0f1117"))
                        detailItem(icon: "person.fill", label: "Logged By", value: event.employee_name ?? "—", color: Color(hex: "7a7f94"))

                        if let contact = event.contact_name, !contact.isEmpty {
                            detailItem(icon: "person.crop.circle", label: "Contact", value: contact, color: Color(hex: "c8893a"))
                        }

                        if let loc = event.location_address, !loc.isEmpty {
                            detailItem(icon: "mappin", label: "Location", value: loc, color: Color(hex: "2d6a4f"))
                        }
                    }

                    // Follow-up
                    if event.follow_up_required == true {
                        HStack(spacing: 10) {
                            Image(systemName: "bell.fill")
                                .font(.system(size: 14))
                                .foregroundColor(Color(hex: "c1121f"))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("FOLLOW-UP REQUIRED")
                                    .font(.custom("DMSans-SemiBold", size: 9))
                                    .foregroundColor(Color(hex: "c1121f"))
                                    .tracking(0.4)
                                Text(formatDate(event.follow_up_date))
                                    .font(.custom("DMSans-SemiBold", size: 14))
                                    .foregroundColor(Color(hex: "0f1117"))
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(hex: "ffe5e7"))
                        .cornerRadius(10)
                    }

                    // Notes
                    if let notes = event.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("NOTES")
                                .font(.custom("DMSans-SemiBold", size: 9))
                                .foregroundColor(Color(hex: "7a7f94"))
                                .tracking(0.4)
                            Text(notes)
                                .font(.custom("DMSans-Regular", size: 14))
                                .foregroundColor(Color(hex: "0f1117"))
                                .lineSpacing(4)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(hex: "f5f4f0"))
                        .cornerRadius(10)
                    }
                }
                .padding(20)
            }
            .background(Color(hex: "f5f4f0"))
            .navigationTitle("Event Details")
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

    private func detailItem(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.custom("DMSans-SemiBold", size: 8))
                    .foregroundColor(Color(hex: "7a7f94"))
                    .tracking(0.4)
                Text(value)
                    .font(.custom("DMSans-Medium", size: 13))
                    .foregroundColor(Color(hex: "0f1117"))
                    .lineLimit(2)
            }
        }
    }

    private var methodIcon: String {
        switch event.method {
        case "Phone Call": return "phone.fill"
        case "Email": return "envelope.fill"
        case "In-Person": return "person.fill"
        case "Text": return "message.fill"
        default: return "phone.fill"
        }
    }

    private var methodColor: Color {
        switch event.method {
        case "Phone Call": return Color(hex: "1d4e89")
        case "Email": return Color(hex: "2d6a4f")
        case "In-Person": return Color(hex: "c8893a")
        case "Text": return Color(hex: "911eb4")
        default: return Color(hex: "1d4e89")
        }
    }

    private func formatDate(_ dateStr: String?) -> String {
        guard let dateStr = dateStr else { return "—" }
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

// MARK: - Log Event Sheet

struct LogEventSheet: View {
    let businessId: Int
    let contacts: [BusinessContact]
    let locations: [Location]
    let onSave: () -> Void

    @Environment(\.dismiss) var dismiss
    @State private var eventDate = Date()
    @State private var method = "Phone Call"
    @State private var subject = ""
    @State private var notes = ""
    @State private var selectedContactId: Int?
    @State private var selectedLocationId: Int?
    @State private var followUpRequired = false
    @State private var followUpDate = Date().addingTimeInterval(7 * 86400)
    @State private var saving = false
    @State private var errorMsg = ""

    private let methods = ["Phone Call", "Email", "In-Person", "Text"]

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

                    // Date
                    VStack(alignment: .leading, spacing: 4) {
                        fieldLabel("Date *")
                        DatePicker("", selection: $eventDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                    }

                    // Method
                    VStack(alignment: .leading, spacing: 4) {
                        fieldLabel("Method")
                        Picker("Method", selection: $method) {
                            ForEach(methods, id: \.self) { m in
                                Text(m).tag(m)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    // Subject
                    VStack(alignment: .leading, spacing: 4) {
                        fieldLabel("Subject *")
                        TextField("Brief description of the interaction", text: $subject)
                            .font(.custom("DMSans-Regular", size: 14))
                            .padding(12)
                            .background(Color.white)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "e2dfd6"), lineWidth: 1))
                    }

                    // Contact picker
                    if !contacts.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            fieldLabel("Contact")
                            Picker("Contact", selection: $selectedContactId) {
                                Text("None").tag(nil as Int?)
                                ForEach(contacts) { c in
                                    Text("\(c.name)\(c.title != nil ? " (\(c.title!))" : "")")
                                        .tag(c.id as Int?)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(Color(hex: "0f1117"))
                            .font(.custom("DMSans-Regular", size: 14))
                            .padding(8)
                            .background(Color.white)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "e2dfd6"), lineWidth: 1))
                        }
                    }

                    // Location picker
                    if !locations.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            fieldLabel("Location")
                            Picker("Location", selection: $selectedLocationId) {
                                Text("None").tag(nil as Int?)
                                ForEach(locations) { loc in
                                    Text(loc.address ?? loc.city ?? "Location #\(loc.id)")
                                        .tag(loc.id as Int?)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(Color(hex: "0f1117"))
                            .font(.custom("DMSans-Regular", size: 14))
                            .padding(8)
                            .background(Color.white)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "e2dfd6"), lineWidth: 1))
                        }
                    }

                    // Notes
                    VStack(alignment: .leading, spacing: 4) {
                        fieldLabel("Notes")
                        TextEditor(text: $notes)
                            .font(.custom("DMSans-Regular", size: 14))
                            .frame(minHeight: 80)
                            .padding(8)
                            .background(Color.white)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "e2dfd6"), lineWidth: 1))
                    }

                    // Follow-up
                    Toggle(isOn: $followUpRequired) {
                        Text("Follow-up Required")
                            .font(.custom("DMSans-Medium", size: 14))
                            .foregroundColor(Color(hex: "0f1117"))
                    }
                    .tint(Color(hex: "c1121f"))

                    if followUpRequired {
                        VStack(alignment: .leading, spacing: 4) {
                            fieldLabel("Follow-up Date")
                            DatePicker("", selection: $followUpDate, displayedComponents: .date)
                                .datePickerStyle(.compact)
                                .labelsHidden()
                        }
                    }
                }
                .padding(20)
            }
            .background(Color(hex: "f5f4f0"))
            .navigationTitle("Log Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.custom("DMSans-Regular", size: 14))
                        .foregroundColor(Color(hex: "7a7f94"))
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
                    .disabled(saving || subject.isEmpty)
                }
            }
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.custom("DMSans-SemiBold", size: 9))
            .foregroundColor(Color(hex: "7a7f94"))
            .tracking(0.4)
    }

    private func save() {
        saving = true
        errorMsg = ""
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let dateStr = fmt.string(from: eventDate)
        let fuDateStr = followUpRequired ? fmt.string(from: followUpDate) : nil

        Task {
            do {
                _ = try await APIClient.shared.createEvent(
                    bizId: businessId,
                    locationId: selectedLocationId,
                    contactId: selectedContactId,
                    eventDate: dateStr,
                    method: method,
                    subject: subject,
                    notes: notes.isEmpty ? nil : notes,
                    followUpRequired: followUpRequired,
                    followUpDate: fuDateStr
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
