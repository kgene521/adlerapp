// /AdlerCRM/Views/CollectionDocumentViews.swift  17/05/2026 23:22:00 EDT
import SwiftUI
import PhotosUI
import Combine
import PDFKit

// MARK: - Collections Section

struct CollectionsSection: View {
    let collections: [Collection]
    let loading: Bool
    let locations: [Location]
    let onReload: () -> Void

    @State private var showLogSheet = false

    private var totalGallons: Double {
        collections.reduce(0) { $0 + ($1.gallons ?? 0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Oil Collections")
                    .font(.custom("Syne-Bold", size: 16))
                    .foregroundColor(Color.theme.text)
                Spacer()

                if !collections.isEmpty {
                    Text("\(Int(totalGallons)) gal total")
                        .font(.custom("DMSans-SemiBold", size: 11))
                        .foregroundColor(Color(hex: "2d6a4f"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.theme.green.opacity(0.12))
                        .cornerRadius(50)
                }

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
                    .background(Color(hex: "2d6a4f"))
                    .cornerRadius(50)
                }
            }

            if loading {
                HStack { Spacer(); ProgressView().padding(.vertical, 20); Spacer() }
            } else if collections.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "drop")
                        .font(.system(size: 28))
                        .foregroundColor(Color.theme.border)
                    Text("No collections yet")
                        .font(.custom("DMSans-Regular", size: 13))
                        .foregroundColor(Color.theme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(collections) { col in
                        CollectionRow(collection: col, onDelete: {
                            deleteCollection(col)
                        })
                        if col.id != collections.last?.id {
                            Divider().padding(.leading, 36)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.theme.surface)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 8, y: 2)
        .sheet(isPresented: $showLogSheet) {
            LogCollectionSheet(locations: locations, onSave: onReload)
        }
    }

    private func deleteCollection(_ col: Collection) {
        Task {
            do {
                _ = try await APIClient.shared.deleteCollection(id: col.id)
                onReload()
            } catch { }
        }
    }
}

// MARK: - Collection Row

struct CollectionRow: View {
    let collection: Collection
    let onDelete: () -> Void

    @State private var showDeleteConfirm = false

    var body: some View {
        HStack(spacing: 12) {
            // Drop icon
            Image(systemName: "drop.fill")
                .font(.system(size: 16))
                .foregroundColor(Color(hex: "2d6a4f"))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("\(Int(collection.gallons ?? 0)) gallons")
                        .font(.custom("DMSans-SemiBold", size: 14))
                        .foregroundColor(Color.theme.text)

                    Text(shortDate(collection.pickup_date))
                        .font(.custom("DMSans-Regular", size: 12))
                        .foregroundColor(Color.theme.textSecondary)
                }

                HStack(spacing: 8) {
                    if let addr = collection.location_address, !addr.isEmpty {
                        Label(addr, systemImage: "mappin")
                            .font(.custom("DMSans-Regular", size: 11))
                            .foregroundColor(Color.theme.textSecondary)
                            .lineLimit(1)
                    }
                    if let emp = collection.employee_name, !emp.isEmpty {
                        Label(emp, systemImage: "person")
                            .font(.custom("DMSans-Regular", size: 11))
                            .foregroundColor(Color.theme.textSecondary)
                            .lineLimit(1)
                    }
                }

                if let notes = collection.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.custom("DMSans-Italic", size: 11))
                        .foregroundColor(Color.theme.textSecondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Button(action: { showDeleteConfirm = true }) {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: "c1121f").opacity(0.6))
            }
            .buttonStyle(.plain)
            .confirmationDialog(
                "Delete this collection?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { onDelete() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("\(Int(collection.gallons ?? 0)) gal on \(shortDate(collection.pickup_date))")
            }
        }
        .padding(.vertical, 8)
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

// MARK: - Log Collection Sheet

struct LogCollectionSheet: View {
    let locations: [Location]
    let onSave: () -> Void

    @Environment(\.dismiss) var dismiss
    @State private var selectedLocationId: Int?
    @State private var pickupDate = Date()
    @State private var gallons = ""
    @State private var notes = ""
    @State private var saving = false
    @State private var errorMsg = ""
    @State private var scannedDrum: Drum?
    @State private var scannedDrumId: Int?

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

                    // Location picker
                    VStack(alignment: .leading, spacing: 4) {
                        fieldLabel("Location *")
                        Picker("Location", selection: $selectedLocationId) {
                            Text("Select location…").tag(nil as Int?)
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

                    // Date
                    VStack(alignment: .leading, spacing: 4) {
                        fieldLabel("Pickup Date *")
                        DatePicker("", selection: $pickupDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                    }

                    // Gallons
                    VStack(alignment: .leading, spacing: 4) {
                        fieldLabel("Gallons Collected *")
                        TextField("e.g. 45", text: $gallons)
                            .keyboardType(.decimalPad)
                            .font(.custom("DMSans-Regular", size: 14))
                            .padding(12)
                            .background(Color.theme.surface)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.theme.border, lineWidth: 1))
                    }

                    // Notes
                    VStack(alignment: .leading, spacing: 4) {
                        fieldLabel("Notes")
                        TextEditor(text: $notes)
                            .font(.custom("DMSans-Regular", size: 14))
                            .frame(minHeight: 80)
                            .padding(8)
                            .background(Color.theme.surface)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.theme.border, lineWidth: 1))
                    }

                    // NFC Drum Scan
                    VStack(alignment: .leading, spacing: 4) {
                        fieldLabel("Drum (Optional)")
                        DrumScanButton(scannedDrum: $scannedDrum, scannedDrumId: $scannedDrumId)
                    }
                }
                .padding(20)
            }
            .background(Color.theme.background)
            .navigationTitle("Log Oil Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.custom("DMSans-Regular", size: 14))
                        .foregroundColor(Color.theme.textSecondary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: save) {
                        if saving { ProgressView().scaleEffect(0.8) }
                        else { Text("Save").font(.custom("DMSans-SemiBold", size: 14)) }
                    }
                    .foregroundColor(Color(hex: "2d6a4f"))
                    .disabled(saving || gallons.isEmpty || selectedLocationId == nil)
                }
            }
            .onAppear {
                if locations.count == 1 { selectedLocationId = locations.first?.id }
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
        guard let locId = selectedLocationId, let gal = Double(gallons), gal > 0 else {
            errorMsg = "Please select a location and enter gallons."
            return
        }
        saving = true
        errorMsg = ""
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"

        Task {
            do {
                _ = try await APIClient.shared.createCollection(
                    locationId: locId,
                    pickupDate: fmt.string(from: pickupDate),
                    gallons: gal,
                    notes: notes.isEmpty ? nil : notes,
                    drumId: scannedDrumId
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

// MARK: - Documents Section

struct DocumentsSection: View {
    let documents: [BusinessDocument]
    let loading: Bool
    let businessId: Int
    let onReload: () -> Void

    @State private var showUploadSheet = false
    @State private var previewDoc: BusinessDocument?
    @State private var showCollectionSummary = false
    @State private var showPickupLog = false

    private var agreements: [BusinessDocument] {
        documents.filter { $0.doc_type == "agreement" }
    }
    private var photos: [BusinessDocument] {
        documents.filter { $0.doc_type == "photo" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Documents & Reports")
                    .font(.custom("Syne-Bold", size: 16))
                    .foregroundColor(Color.theme.text)
                Spacer()
                if !documents.isEmpty {
                    Text("\(documents.count)")
                        .font(.custom("DMSans-SemiBold", size: 12))
                        .foregroundColor(Color.theme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.theme.border)
                        .cornerRadius(50)
                }

                Button(action: { showUploadSheet = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.doc")
                            .font(.system(size: 11, weight: .bold))
                        Text("Upload")
                            .font(.custom("DMSans-SemiBold", size: 12))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.theme.text)
                    .cornerRadius(50)
                }
            }

            // Reports subsection
            reportsSubsection

            if loading {
                HStack { Spacer(); ProgressView().padding(.vertical, 20); Spacer() }
            } else if !documents.isEmpty {
                // Agreements subsection
                if !agreements.isEmpty {
                    docSubsection(title: "Agreements", icon: "doc.text.fill", color: Color(hex: "1d4e89"), docs: agreements)
                }

                // Photos subsection
                if !photos.isEmpty {
                    if !agreements.isEmpty { Divider() }
                    docSubsection(title: "Photos", icon: "photo.fill", color: Color(hex: "2d6a4f"), docs: photos)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.theme.surface)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 8, y: 2)
        .sheet(isPresented: $showUploadSheet) {
            UploadDocumentSheet(businessId: businessId, onSave: onReload)
        }
        .sheet(item: $previewDoc) { doc in
            DocumentPreviewSheet(document: doc, onDelete: {
                deleteDocument(doc)
            })
        }
        .sheet(isPresented: $showCollectionSummary) {
            CollectionSummaryReportView(businessId: businessId)
        }
        .sheet(isPresented: $showPickupLog) {
            PickupLogReportView(businessId: businessId)
        }
    }

    // MARK: - Reports Subsection

    private var reportsSubsection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: "c8893a"))
                Text("REPORTS")
                    .font(.custom("DMSans-SemiBold", size: 10))
                    .foregroundColor(Color.theme.textSecondary)
                    .tracking(0.5)
            }

            Button(action: { showCollectionSummary = true }) {
                HStack(spacing: 10) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "2d6a4f"))
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Collection Summary")
                            .font(.custom("DMSans-SemiBold", size: 13))
                            .foregroundColor(Color.theme.text)
                        Text("Gallons collected over time")
                            .font(.custom("DMSans-Regular", size: 11))
                            .foregroundColor(Color.theme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color.theme.border)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            Divider()

            Button(action: { showPickupLog = true }) {
                HStack(spacing: 10) {
                    Image(systemName: "list.clipboard.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "1d4e89"))
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Pickup Log")
                            .font(.custom("DMSans-SemiBold", size: 13))
                            .foregroundColor(Color.theme.text)
                        Text("Detailed pickup history")
                            .font(.custom("DMSans-Regular", size: 11))
                            .foregroundColor(Color.theme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color.theme.border)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            Divider()
        }
    }

    private func docSubsection(title: String, icon: String, color: Color, docs: [BusinessDocument]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(color)
                Text(title.uppercased())
                    .font(.custom("DMSans-SemiBold", size: 10))
                    .foregroundColor(Color.theme.textSecondary)
                    .tracking(0.5)
                Text("(\(docs.count))")
                    .font(.custom("DMSans-Regular", size: 10))
                    .foregroundColor(Color.theme.textSecondary)
            }

            ForEach(docs) { doc in
                Button(action: { previewDoc = doc }) {
                    DocumentRow(document: doc)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func deleteDocument(_ doc: BusinessDocument) {
        Task {
            do {
                _ = try await APIClient.shared.deleteDocument(id: doc.id)
                onReload()
            } catch { }
        }
    }
}

// MARK: - Document Row

struct DocumentRow: View {
    let document: BusinessDocument

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: fileIcon)
                .font(.system(size: 18))
                .foregroundColor(fileColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(document.original_name ?? document.file_name ?? "Document")
                    .font(.custom("DMSans-Medium", size: 13))
                    .foregroundColor(Color.theme.text)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let name = document.uploaded_by_name {
                        Text(name)
                            .font(.custom("DMSans-Regular", size: 11))
                            .foregroundColor(Color.theme.textSecondary)
                    }
                    Text(shortDate(document.created_at))
                        .font(.custom("DMSans-Regular", size: 11))
                        .foregroundColor(Color.theme.textSecondary)
                }

                if let notes = document.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.custom("DMSans-Italic", size: 11))
                        .foregroundColor(Color.theme.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color.theme.border)
        }
        .padding(.vertical, 6)
    }

    private var fileIcon: String {
        let ext = (document.original_name ?? "").lowercased()
        if ext.hasSuffix(".pdf") { return "doc.text.fill" }
        if ext.hasSuffix(".jpg") || ext.hasSuffix(".jpeg") || ext.hasSuffix(".png") || ext.hasSuffix(".heic") {
            return "photo.fill"
        }
        return "doc.fill"
    }

    private var fileColor: Color {
        document.doc_type == "agreement" ? Color(hex: "1d4e89") : Color(hex: "2d6a4f")
    }

    private func shortDate(_ dateStr: String?) -> String {
        guard let dateStr = dateStr else { return "" }
        let prefix = String(dateStr.prefix(10))
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        if let date = fmt.date(from: prefix) {
            fmt.dateFormat = "M/d/yy"
            return fmt.string(from: date)
        }
        return ""
    }
}

// MARK: - Document Preview Sheet

struct DocumentPreviewSheet: View {
    let document: BusinessDocument
    let onDelete: () -> Void

    @Environment(\.dismiss) var dismiss
    @State private var imageData: Data?
    @State private var loading = true
    @State private var errorMsg = ""
    @State private var showDeleteConfirm = false

    private var isImage: Bool {
        let name = (document.original_name ?? "").lowercased()
        return name.hasSuffix(".jpg") || name.hasSuffix(".jpeg") || name.hasSuffix(".png") ||
               name.hasSuffix(".gif") || name.hasSuffix(".webp") || name.hasSuffix(".heic")
    }

    var body: some View {
        NavigationStack {
            VStack {
                if loading {
                    Spacer()
                    ProgressView("Loading document…")
                        .font(.custom("DMSans-Regular", size: 14))
                    Spacer()
                } else if !errorMsg.isEmpty {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(Color(hex: "c1121f"))
                    Text(errorMsg)
                        .font(.custom("DMSans-Regular", size: 14))
                        .foregroundColor(Color.theme.text)
                    Spacer()
                } else if isImage, let data = imageData, let uiImage = UIImage(data: data) {
                    ScrollView {
                        VStack(spacing: 16) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .cornerRadius(12)
                                .padding(.horizontal, 16)

                            docMeta
                        }
                        .padding(.vertical, 16)
                    }
                } else {
                    // Non-image file (PDF etc)
                    ScrollView {
                        VStack(spacing: 16) {
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 60))
                                .foregroundColor(Color(hex: "1d4e89"))
                                .padding(.top, 40)

                            Text(document.original_name ?? "Document")
                                .font(.custom("DMSans-SemiBold", size: 16))
                                .foregroundColor(Color.theme.text)

                            Text("PDF preview is not available in-app.\nThe file is stored on the server.")
                                .font(.custom("DMSans-Regular", size: 13))
                                .foregroundColor(Color.theme.textSecondary)
                                .multilineTextAlignment(.center)

                            docMeta
                        }
                        .padding(16)
                    }
                }
            }
            .background(Color.theme.background)
            .navigationTitle(document.original_name ?? "Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showDeleteConfirm = true }) {
                        Image(systemName: "trash")
                            .foregroundColor(Color(hex: "c1121f"))
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.custom("DMSans-Medium", size: 14))
                        .foregroundColor(Color(hex: "c8893a"))
                }
            }
            .confirmationDialog("Delete this document?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            }
            .task { await loadFile() }
        }
    }

    private var docMeta: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                metaItem(label: "Type", value: document.doc_type == "agreement" ? "Agreement" : "Photo")
                metaItem(label: "Uploaded By", value: document.uploaded_by_name ?? "—")
            }
            if let notes = document.notes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NOTES")
                        .font(.custom("DMSans-SemiBold", size: 9))
                        .foregroundColor(Color.theme.textSecondary)
                        .tracking(0.4)
                    Text(notes)
                        .font(.custom("DMSans-Regular", size: 13))
                        .foregroundColor(Color.theme.text)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.theme.surface)
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }

    private func metaItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.custom("DMSans-SemiBold", size: 8))
                .foregroundColor(Color.theme.textSecondary)
                .tracking(0.4)
            Text(value)
                .font(.custom("DMSans-Medium", size: 13))
                .foregroundColor(Color.theme.text)
        }
    }

    private func loadFile() async {
        guard isImage else { loading = false; return }
        do {
            imageData = try await APIClient.shared.requestData(path: "/documents/file/\(document.id)")
        } catch {
            errorMsg = error.localizedDescription
        }
        loading = false
    }
}

// MARK: - Upload Document Sheet

struct UploadDocumentSheet: View {
    let businessId: Int
    let onSave: () -> Void

    @Environment(\.dismiss) var dismiss
    @State private var docType = "photo"
    @State private var notes = ""
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var selectedFileName = ""
    @State private var selectedMimeType = ""
    @State private var previewImage: UIImage?
    @State private var saving = false
    @State private var errorMsg = ""

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

                    // Type picker
                    VStack(alignment: .leading, spacing: 4) {
                        fieldLabel("Document Type")
                        Picker("Type", selection: $docType) {
                            Text("Photo").tag("photo")
                            Text("Agreement").tag("agreement")
                        }
                        .pickerStyle(.segmented)
                    }

                    // Photo picker
                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel("File")
                        PhotosPicker(
                            selection: $selectedItem,
                            matching: .any(of: [.images]),
                            photoLibrary: .shared()
                        ) {
                            HStack {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.system(size: 16))
                                Text(selectedFileName.isEmpty ? "Choose Photo…" : selectedFileName)
                                    .font(.custom("DMSans-Medium", size: 14))
                                    .lineLimit(1)
                            }
                            .foregroundColor(Color.theme.text)
                            .frame(maxWidth: .infinity)
                            .padding(14)
                            .background(Color.theme.surface)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                                    .foregroundColor(Color.theme.border)
                            )
                        }
                        .onChange(of: selectedItem) { _, newItem in
                            Task { await loadImage(newItem) }
                        }
                    }

                    // Preview
                    if let img = previewImage {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 200)
                            .cornerRadius(10)
                    }

                    // Notes
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
                .padding(20)
            }
            .background(Color.theme.background)
            .navigationTitle("Upload Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.custom("DMSans-Regular", size: 14))
                        .foregroundColor(Color.theme.textSecondary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: upload) {
                        if saving { ProgressView().scaleEffect(0.8) }
                        else { Text("Upload").font(.custom("DMSans-SemiBold", size: 14)) }
                    }
                    .foregroundColor(Color(hex: "2d6a4f"))
                    .disabled(saving || selectedImageData == nil)
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

    private func loadImage(_ item: PhotosPickerItem?) async {
        guard let item = item else { return }
        if let data = try? await item.loadTransferable(type: Data.self) {
            selectedImageData = data
            previewImage = UIImage(data: data)
            // Determine filename and mimetype
            if let type = item.supportedContentTypes.first {
                let ext = type.preferredFilenameExtension ?? "jpg"
                selectedFileName = "photo_\(Int(Date().timeIntervalSince1970)).\(ext)"
                selectedMimeType = type.preferredMIMEType ?? "image/jpeg"
            } else {
                selectedFileName = "photo_\(Int(Date().timeIntervalSince1970)).jpg"
                selectedMimeType = "image/jpeg"
            }
        }
    }

    private func upload() {
        guard let data = selectedImageData else {
            errorMsg = "Please select a file."
            return
        }
        saving = true
        errorMsg = ""

        Task {
            do {
                _ = try await APIClient.shared.uploadDocument(
                    fileData: data,
                    fileName: selectedFileName,
                    mimeType: selectedMimeType,
                    businessId: businessId,
                    docType: docType,
                    notes: notes.isEmpty ? nil : notes
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

// MARK: - Collection Summary Report View

struct CollectionSummaryReportView: View {
    let businessId: Int

    @Environment(\.dismiss) var dismiss
    @State private var report: CollectionSummaryReport?
    @State private var loading = true
    @State private var errorMsg = ""
    @State private var period = "all"

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        periodButton("All Time", value: "all")
                        periodButton("This Week", value: "week")
                        periodButton("This Month", value: "month")
                        periodButton("This Year", value: "year")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .background(Color.theme.background)
                .overlay(Rectangle().fill(Color.theme.border).frame(height: 1), alignment: .bottom)

                if loading {
                    Spacer()
                    ProgressView("Generating report\u{2026}")
                        .font(.custom("DMSans-Regular", size: 14))
                    Spacer()
                } else if let report = report {
                    ScrollView {
                        VStack(spacing: 16) {
                            summaryCards(report.summary)
                            if !report.monthly.isEmpty { monthlySection(report.monthly) }
                            if !report.by_location.isEmpty { locationSection(report.by_location) }
                        }
                        .padding(16)
                    }
                } else {
                    Spacer()
                    Text(errorMsg.isEmpty ? "No data" : errorMsg)
                        .font(.custom("DMSans-Regular", size: 14))
                        .foregroundColor(Color.theme.textSecondary)
                    Spacer()
                }
            }
            .navigationTitle("Collection Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.custom("DMSans-Medium", size: 14))
                        .foregroundColor(Color(hex: "c8893a"))
                }
            }
            .task { await loadReport() }
            .onChange(of: period) { _, _ in Task { await loadReport() } }
        }
    }

    private func summaryCards(_ s: CollectionSummary) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                statCard(label: "Total Gallons", value: String(format: "%.0f", s.total_gallons ?? 0), icon: "drop.fill", color: Color(hex: "2d6a4f"))
                statCard(label: "Total Pickups", value: "\(s.total_pickups ?? 0)", icon: "truck.box.fill", color: Color(hex: "c8893a"))
            }
            HStack(spacing: 12) {
                statCard(label: "Avg/Pickup", value: String(format: "%.1f gal", s.avg_gallons_per_pickup ?? 0), icon: "chart.bar.fill", color: Color(hex: "1d4e89"))
                statCard(label: "Date Range", value: dateRange(s.first_pickup, s.last_pickup), icon: "calendar", color: Color.theme.textSecondary)
            }
        }
    }

    private func statCard(label: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12)).foregroundColor(color)
                Text(label.uppercased())
                    .font(.custom("DMSans-SemiBold", size: 9))
                    .foregroundColor(Color.theme.textSecondary)
                    .tracking(0.4)
            }
            Text(value)
                .font(.custom("DMSans-SemiBold", size: 16))
                .foregroundColor(Color.theme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.theme.surface)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.04), radius: 4, y: 2)
    }

    private func monthlySection(_ monthly: [MonthlyBreakdown]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Monthly Breakdown", systemImage: "calendar")
                .font(.custom("Syne-Bold", size: 15))
                .foregroundColor(Color.theme.text)
            ForEach(monthly) { m in
                HStack {
                    Text(formatMonth(m.month))
                        .font(.custom("DMSans-Medium", size: 13))
                        .foregroundColor(Color.theme.text)
                        .frame(width: 80, alignment: .leading)
                    let maxGal = monthly.compactMap { $0.gallons }.max() ?? 1
                    let pct = (m.gallons ?? 0) / maxGal
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(hex: "2d6a4f"))
                            .frame(width: max(4, geo.size.width * pct), height: 16)
                    }
                    .frame(height: 16)
                    Text(String(format: "%.0f gal", m.gallons ?? 0))
                        .font(.custom("DMSans-SemiBold", size: 11))
                        .foregroundColor(Color(hex: "2d6a4f"))
                        .frame(width: 55, alignment: .trailing)
                    Text("\(m.pickups ?? 0)x")
                        .font(.custom("DMSans-Regular", size: 11))
                        .foregroundColor(Color.theme.textSecondary)
                        .frame(width: 24, alignment: .trailing)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(16)
        .background(Color.theme.surface)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.04), radius: 4, y: 2)
    }

    private func locationSection(_ locs: [LocationBreakdown]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("By Location", systemImage: "mappin.circle.fill")
                .font(.custom("Syne-Bold", size: 15))
                .foregroundColor(Color.theme.text)
            ForEach(locs) { loc in
                HStack {
                    Text(loc.location_label ?? "Unknown")
                        .font(.custom("DMSans-Regular", size: 13))
                        .foregroundColor(Color.theme.text)
                        .lineLimit(1)
                    Spacer()
                    Text(String(format: "%.0f gal", loc.gallons ?? 0))
                        .font(.custom("DMSans-SemiBold", size: 12))
                        .foregroundColor(Color(hex: "2d6a4f"))
                    Text("·").foregroundColor(Color.theme.border)
                    Text("\(loc.pickups ?? 0) pickups")
                        .font(.custom("DMSans-Regular", size: 11))
                        .foregroundColor(Color.theme.textSecondary)
                }
                .padding(.vertical, 2)
                if loc.id != locs.last?.id { Divider() }
            }
        }
        .padding(16)
        .background(Color.theme.surface)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.04), radius: 4, y: 2)
    }

    private func periodButton(_ label: String, value: String) -> some View {
        Button(action: { period = value }) {
            Text(label)
                .font(.custom("DMSans-SemiBold", size: 11))
                .foregroundColor(period == value ? .white : Color.theme.text)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(period == value ? Color(hex: "c8893a") : Color.theme.surface)
                .cornerRadius(50)
                .overlay(RoundedRectangle(cornerRadius: 50).stroke(period == value ? Color.clear : Color.theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func loadReport() async {
        loading = true; errorMsg = ""
        do { report = try await APIClient.shared.getCollectionSummary(bizId: businessId, period: period) }
        catch { errorMsg = error.localizedDescription }
        loading = false
    }

    private func formatMonth(_ str: String) -> String {
        let parts = str.split(separator: "-")
        guard parts.count == 2, let month = Int(parts[1]) else { return str }
        let months = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return month >= 1 && month <= 12 ? "\(months[month]) \(parts[0].suffix(2))" : str
    }

    private func dateRange(_ first: String?, _ last: String?) -> String {
        guard let f = first, let l = last else { return "—" }
        return "\(String(f.prefix(10)))\n\(String(l.prefix(10)))"
    }
}

// MARK: - Pickup Log Report View

struct PickupLogReportView: View {
    let businessId: Int

    @Environment(\.dismiss) var dismiss
    @State private var entries: [PickupLogEntry] = []
    @State private var loading = true
    @State private var errorMsg = ""
    @State private var period = "all"

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        periodButton("All Time", value: "all")
                        periodButton("This Week", value: "week")
                        periodButton("This Month", value: "month")
                        periodButton("This Year", value: "year")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .background(Color.theme.background)
                .overlay(Rectangle().fill(Color.theme.border).frame(height: 1), alignment: .bottom)

                if !entries.isEmpty {
                    HStack {
                        let totalGal = entries.compactMap { $0.gallons }.reduce(0, +)
                        Label(String(format: "%.0f gal total", totalGal), systemImage: "drop.fill")
                            .font(.custom("DMSans-SemiBold", size: 12))
                            .foregroundColor(Color(hex: "2d6a4f"))
                        Text("·").foregroundColor(Color.theme.border)
                        Text("\(entries.count) pickups")
                            .font(.custom("DMSans-SemiBold", size: 12))
                            .foregroundColor(Color.theme.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color.theme.background)
                }

                if loading {
                    Spacer()
                    ProgressView("Loading pickup log…")
                        .font(.custom("DMSans-Regular", size: 14))
                    Spacer()
                } else if entries.isEmpty {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "list.clipboard")
                            .font(.system(size: 32))
                            .foregroundColor(Color.theme.border)
                        Text("No pickups recorded")
                            .font(.custom("DMSans-Regular", size: 14))
                            .foregroundColor(Color.theme.textSecondary)
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(entries) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(formatDate(entry.pickup_date))
                                        .font(.custom("DMSans-SemiBold", size: 13))
                                        .foregroundColor(Color.theme.text)
                                    Spacer()
                                    Text(String(format: "%.1f gal", entry.gallons ?? 0))
                                        .font(.custom("DMSans-SemiBold", size: 13))
                                        .foregroundColor(Color(hex: "2d6a4f"))
                                }
                                HStack(spacing: 8) {
                                    let addr = [entry.location_address, entry.location_city]
                                        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
                                    if !addr.isEmpty {
                                        Text(addr)
                                            .font(.custom("DMSans-Regular", size: 11))
                                            .foregroundColor(Color.theme.textSecondary)
                                            .lineLimit(1)
                                    }
                                    if let emp = entry.employee_name {
                                        Text("·").font(.system(size: 8)).foregroundColor(Color.theme.border)
                                        Text(emp)
                                            .font(.custom("DMSans-Medium", size: 11))
                                            .foregroundColor(Color(hex: "c8893a"))
                                    }
                                }
                                if let notes = entry.notes, !notes.isEmpty {
                                    Text(notes)
                                        .font(.custom("DMSans-Regular", size: 11))
                                        .foregroundColor(Color.theme.textSecondary)
                                        .lineLimit(1)
                                        .italic()
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Pickup Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.custom("DMSans-Medium", size: 14))
                        .foregroundColor(Color(hex: "c8893a"))
                }
            }
            .task { await loadLog() }
            .onChange(of: period) { _, _ in Task { await loadLog() } }
        }
    }

    private func periodButton(_ label: String, value: String) -> some View {
        Button(action: { period = value }) {
            Text(label)
                .font(.custom("DMSans-SemiBold", size: 11))
                .foregroundColor(period == value ? .white : Color.theme.text)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(period == value ? Color(hex: "c8893a") : Color.theme.surface)
                .cornerRadius(50)
                .overlay(RoundedRectangle(cornerRadius: 50).stroke(period == value ? Color.clear : Color.theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func loadLog() async {
        loading = true; errorMsg = ""
        do { entries = try await APIClient.shared.getPickupLog(bizId: businessId, period: period) }
        catch { errorMsg = error.localizedDescription }
        loading = false
    }

    private func formatDate(_ str: String?) -> String {
        guard let s = str else { return "—" }
        return String(s.prefix(10))
    }
}

// MARK: - Collection Reports Section (Separate Card)

struct CollectionReportsSection: View {
    let businessId: Int

    @State private var reports: [ReportHistoryEntry] = []
    @State private var loading = true
    @State private var showGenerateSheet = false
    @State private var previewingPDF: URL?
    @State private var showPDFPreview = false
    @State private var downloadingId: Int?
    @State private var sharingId: Int?
    @State private var shareURL: URL?
    @State private var showShareSheet = false
    @State private var showDeleteConfirm = false
    @State private var reportToDelete: ReportHistoryEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Collection Reports", systemImage: "doc.text.fill")
                    .font(.custom("Syne-Bold", size: 16))
                    .foregroundColor(Color.theme.text)
                Spacer()

                if !reports.isEmpty {
                    Text("\(reports.count)")
                        .font(.custom("DMSans-SemiBold", size: 12))
                        .foregroundColor(Color.theme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.theme.border)
                        .cornerRadius(50)
                }

                Button(action: { showGenerateSheet = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("Generate")
                            .font(.custom("DMSans-SemiBold", size: 12))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(hex: "2d6a4f"))
                    .cornerRadius(50)
                }
            }

            if loading {
                HStack { Spacer(); ProgressView().padding(.vertical, 20); Spacer() }
            } else if reports.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 28))
                        .foregroundColor(Color.theme.border)
                    Text("No reports generated yet")
                        .font(.custom("DMSans-Regular", size: 13))
                        .foregroundColor(Color.theme.textSecondary)
                    Text("Tap Generate to create a collection report.")
                        .font(.custom("DMSans-Regular", size: 11))
                        .foregroundColor(Color.theme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(reports) { report in
                        reportRow(report)
                        if report.id != reports.last?.id {
                            Divider().padding(.leading, 36)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.theme.surface)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 8, y: 2)
        .task { await loadReports() }
        .sheet(isPresented: $showGenerateSheet) {
            GenerateReportSheet(businessId: businessId, onGenerated: {
                Task { await loadReports() }
            })
        }
        .sheet(isPresented: $showPDFPreview) {
            if let url = previewingPDF {
                PDFPreviewSheet(url: url)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = shareURL {
                ActivitySheet(items: [url])
            }
        }
        .confirmationDialog("Delete this report?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let report = reportToDelete { deleteReport(report) }
            }
            Button("Cancel", role: .cancel) { reportToDelete = nil }
        } message: {
            Text("The report PDF will be permanently deleted.")
        }
    }

    private func reportRow(_ report: ReportHistoryEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 22))
                .foregroundColor(Color(hex: "c1121f"))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(report.report_name ?? "Report")
                    .font(.custom("DMSans-SemiBold", size: 13))
                    .foregroundColor(Color.theme.text)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    let periodStr = formatPeriod(from: report.period_from, to: report.period_to)
                    Text(periodStr)
                        .font(.custom("DMSans-Regular", size: 11))
                        .foregroundColor(Color.theme.textSecondary)

                    if let gal = report.total_gallons, gal > 0 {
                        Text("·").foregroundColor(Color.theme.border)
                        Text(String(format: "%.0f gal", gal))
                            .font(.custom("DMSans-SemiBold", size: 11))
                            .foregroundColor(Color(hex: "2d6a4f"))
                    }
                }

                HStack(spacing: 8) {
                    Text(formatDate(report.created_at))
                        .font(.custom("DMSans-Regular", size: 10))
                        .foregroundColor(Color.theme.textSecondary)

                    if let byName = report.generated_by_name {
                        Text("·").foregroundColor(Color.theme.border)
                        Text(byName)
                            .font(.custom("DMSans-Medium", size: 10))
                            .foregroundColor(Color(hex: "c8893a"))
                    }
                }
            }

            Spacer()

            if downloadingId == report.id {
                ProgressView()
                    .frame(width: 24, height: 24)
            } else if sharingId == report.id {
                ProgressView()
                    .frame(width: 24, height: 24)
            } else {
                HStack(spacing: 14) {
                    Button(action: { downloadForShare(report) }) {
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "1d4e89"))
                    }
                    .buttonStyle(.plain)

                    Button(action: { reportToDelete = report; showDeleteConfirm = true }) {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: "c1121f").opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { openReport(report) }
    }

    private func loadReports() async {
        loading = true
        do { reports = try await APIClient.shared.getReportHistory(bizId: businessId) } catch { }
        loading = false
    }

    private func openReport(_ report: ReportHistoryEntry) {
        guard let name = report.report_name, downloadingId == nil else { return }
        downloadingId = report.id
        Task {
            do {
                let data = try await APIClient.shared.downloadReportPDF(reportName: name)
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                try data.write(to: tempURL)
                await MainActor.run {
                    previewingPDF = tempURL
                    showPDFPreview = true
                    downloadingId = nil
                }
            } catch {
                await MainActor.run { downloadingId = nil }
            }
        }
    }

    private func deleteReport(_ report: ReportHistoryEntry) {
        Task {
            do {
                try await APIClient.shared.deleteReports(ids: [report.id])
                await loadReports()
            } catch { }
            reportToDelete = nil
        }
    }

    private func downloadForShare(_ report: ReportHistoryEntry) {
        guard let name = report.report_name, sharingId == nil else { return }
        sharingId = report.id
        Task {
            do {
                let data = try await APIClient.shared.downloadReportPDF(reportName: name)
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                try data.write(to: tempURL)
                await MainActor.run {
                    shareURL = tempURL
                    showShareSheet = true
                    sharingId = nil
                }
            } catch {
                await MainActor.run { sharingId = nil }
            }
        }
    }

    private func formatPeriod(from: String?, to: String?) -> String {
        if let f = from, let t = to {
            return "\(String(f.prefix(10))) – \(String(t.prefix(10)))"
        } else if let f = from {
            return "From \(String(f.prefix(10)))"
        } else if let t = to {
            return "Up to \(String(t.prefix(10)))"
        }
        return "All time"
    }

    private func formatDate(_ str: String?) -> String {
        guard let s = str else { return "—" }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = iso.date(from: s) ?? ISO8601DateFormatter().date(from: s) else {
            return String(s.prefix(10))
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, yyyy h:mm a"
        return fmt.string(from: date)
    }
}

// MARK: - Generate Report Sheet

struct GenerateReportSheet: View {
    let businessId: Int
    let onGenerated: () -> Void

    @Environment(\.dismiss) var dismiss
    @State private var useCustomDates = false
    @State private var fromDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var toDate = Date()
    @State private var generating = false
    @State private var errorMsg = ""
    @State private var successInfo: GeneratedReportInfo?
    @State private var previewURL: URL?
    @State private var showPDFPreview = false
    @State private var loadingPreview = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header info
                        VStack(alignment: .leading, spacing: 6) {
                            Text("REPORT DETAILS")
                                .font(.custom("DMSans-SemiBold", size: 10))
                                .foregroundColor(Color.theme.textSecondary)
                                .tracking(0.5)
                            Text("Generate a Used Cooking Oil Collection Report PDF with pickup history, gallons collected, and location breakdown.")
                                .font(.custom("DMSans-Regular", size: 13))
                                .foregroundColor(Color.theme.text)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.theme.background)
                        .cornerRadius(12)

                        // Date range toggle
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle(isOn: $useCustomDates) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Custom Date Range")
                                        .font(.custom("DMSans-SemiBold", size: 14))
                                        .foregroundColor(Color.theme.text)
                                    Text(useCustomDates ? "Report covers selected dates" : "Report covers all time")
                                        .font(.custom("DMSans-Regular", size: 11))
                                        .foregroundColor(Color.theme.textSecondary)
                                }
                            }
                            .tint(Color(hex: "c8893a"))

                            if useCustomDates {
                                VStack(spacing: 12) {
                                    DatePicker("From", selection: $fromDate, displayedComponents: .date)
                                        .font(.custom("DMSans-Medium", size: 14))
                                        .foregroundColor(Color.theme.text)
                                    DatePicker("To", selection: $toDate, displayedComponents: .date)
                                        .font(.custom("DMSans-Medium", size: 14))
                                        .foregroundColor(Color.theme.text)
                                }
                                .padding(.leading, 4)
                            }
                        }
                        .padding(16)
                        .background(Color.theme.surface)
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.04), radius: 4, y: 2)

                        // Success message
                        if let info = successInfo {
                            Button(action: { openGeneratedReport(info) }) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Label("Report generated successfully!", systemImage: "checkmark.circle.fill")
                                        .font(.custom("DMSans-SemiBold", size: 14))
                                        .foregroundColor(Color(hex: "2d6a4f"))
                                    Text(info.report_name ?? "")
                                        .font(.custom("DMSans-Regular", size: 12))
                                        .foregroundColor(Color.theme.text)
                                    HStack(spacing: 12) {
                                        if let gal = info.total_gallons {
                                            Label(String(format: "%.0f gal", gal), systemImage: "drop.fill")
                                                .font(.custom("DMSans-Regular", size: 11))
                                                .foregroundColor(Color(hex: "2d6a4f"))
                                        }
                                        if let cnt = info.collection_count {
                                            Label("\(cnt) pickups", systemImage: "truck.box.fill")
                                                .font(.custom("DMSans-Regular", size: 11))
                                                .foregroundColor(Color(hex: "c8893a"))
                                        }
                                        if let period = info.period {
                                            Label(period, systemImage: "calendar")
                                                .font(.custom("DMSans-Regular", size: 11))
                                                .foregroundColor(Color.theme.textSecondary)
                                        }
                                    }
                                    HStack(spacing: 4) {
                                        if loadingPreview {
                                            ProgressView().controlSize(.small)
                                            Text("Opening report…")
                                                .font(.custom("DMSans-Medium", size: 11))
                                                .foregroundColor(Color(hex: "2d6a4f"))
                                        } else {
                                            Image(systemName: "eye.fill")
                                                .font(.system(size: 10))
                                            Text("Tap to view report")
                                                .font(.custom("DMSans-Medium", size: 11))
                                        }
                                    }
                                    .foregroundColor(Color(hex: "1d4e89"))
                                    .padding(.top, 2)
                                }
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.theme.green.opacity(0.12))
                                .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                        }

                        // Error message
                        if !errorMsg.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(Color(hex: "c1121f"))
                                Text(errorMsg)
                                    .font(.custom("DMSans-Regular", size: 12))
                                    .foregroundColor(Color(hex: "c1121f"))
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.theme.red.opacity(0.08))
                            .cornerRadius(8)
                        }
                    }
                    .padding(16)
                }

                // Generate button
                VStack(spacing: 0) {
                    Divider()
                    Button(action: generate) {
                        HStack {
                            if generating {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "doc.badge.plus")
                                Text("Generate Report")
                                    .font(.custom("DMSans-SemiBold", size: 15))
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(generating ? Color.theme.textSecondary : Color(hex: "2d6a4f"))
                        .cornerRadius(12)
                    }
                    .disabled(generating)
                    .padding(16)
                }
            }
            .navigationTitle("Generate Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.custom("DMSans-Medium", size: 14))
                        .foregroundColor(Color(hex: "c8893a"))
                }
            }
            .sheet(isPresented: $showPDFPreview) {
                if let url = previewURL {
                    PDFPreviewSheet(url: url)
                }
            }
        }
    }

    private func generate() {
        generating = true
        errorMsg = ""
        successInfo = nil

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"

        let fromStr: String? = useCustomDates ? fmt.string(from: fromDate) : nil
        let toStr: String? = useCustomDates ? fmt.string(from: toDate) : nil

        Task {
            do {
                let response = try await APIClient.shared.generateCollectionReport(
                    bizId: businessId, from: fromStr, to: toStr
                )
                successInfo = response.report
                onGenerated()
            } catch {
                errorMsg = error.localizedDescription
            }
            generating = false
        }
    }

    private func openGeneratedReport(_ info: GeneratedReportInfo) {
        guard let name = info.report_name, !loadingPreview else { return }
        loadingPreview = true
        Task {
            do {
                let data = try await APIClient.shared.downloadReportPDF(reportName: name)
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                try data.write(to: tempURL)
                await MainActor.run {
                    previewURL = tempURL
                    showPDFPreview = true
                    loadingPreview = false
                }
            } catch {
                await MainActor.run { loadingPreview = false }
            }
        }
    }
}

// MARK: - PDF Preview Sheet

struct PDFPreviewSheet: View {
    let url: URL
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            PDFKitView(url: url)
                .navigationTitle(url.lastPathComponent)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Done") { dismiss() }
                            .font(.custom("DMSans-Medium", size: 14))
                            .foregroundColor(Color(hex: "c8893a"))
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14))
                                .foregroundColor(Color(hex: "c8893a"))
                        }
                    }
                }
        }
    }
}

struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.document = PDFDocument(url: url)
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        if pdfView.document?.documentURL != url {
            pdfView.document = PDFDocument(url: url)
        }
    }
}

// MARK: - Share Sheet (UIActivityViewController)

struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
