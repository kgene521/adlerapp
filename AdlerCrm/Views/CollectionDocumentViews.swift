//
//  CollectionDocumentViews.swift
//  AdlerCrm
//
//  Created by E. K. Khanine on 3/27/26.
//
// AdlerCRM/Views/CollectionDocumentViews.swift  27/03/2026 00:50:21
import SwiftUI
import PhotosUI
import Combine

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
                    .foregroundColor(Color(hex: "0f1117"))
                Spacer()

                if !collections.isEmpty {
                    Text("\(Int(totalGallons)) gal total")
                        .font(.custom("DMSans-SemiBold", size: 11))
                        .foregroundColor(Color(hex: "2d6a4f"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color(hex: "d8f3dc"))
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
                        .foregroundColor(Color(hex: "e2dfd6"))
                    Text("No collections yet")
                        .font(.custom("DMSans-Regular", size: 13))
                        .foregroundColor(Color(hex: "7a7f94"))
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
        .background(Color.white)
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
                        .foregroundColor(Color(hex: "0f1117"))

                    Text(shortDate(collection.pickup_date))
                        .font(.custom("DMSans-Regular", size: 12))
                        .foregroundColor(Color(hex: "7a7f94"))
                }

                HStack(spacing: 8) {
                    if let addr = collection.location_address, !addr.isEmpty {
                        Label(addr, systemImage: "mappin")
                            .font(.custom("DMSans-Regular", size: 11))
                            .foregroundColor(Color(hex: "7a7f94"))
                            .lineLimit(1)
                    }
                    if let emp = collection.employee_name, !emp.isEmpty {
                        Label(emp, systemImage: "person")
                            .font(.custom("DMSans-Regular", size: 11))
                            .foregroundColor(Color(hex: "7a7f94"))
                            .lineLimit(1)
                    }
                }

                if let notes = collection.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.custom("DMSans-Italic", size: 11))
                        .foregroundColor(Color(hex: "7a7f94"))
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
                        .tint(Color(hex: "0f1117"))
                        .font(.custom("DMSans-Regular", size: 14))
                        .padding(8)
                        .background(Color.white)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "e2dfd6"), lineWidth: 1))
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
                            .background(Color.white)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "e2dfd6"), lineWidth: 1))
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
                }
                .padding(20)
            }
            .background(Color(hex: "f5f4f0"))
            .navigationTitle("Log Oil Collection")
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
            .foregroundColor(Color(hex: "7a7f94"))
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

// MARK: - Documents Section

struct DocumentsSection: View {
    let documents: [BusinessDocument]
    let loading: Bool
    let businessId: Int
    let onReload: () -> Void

    @State private var showUploadSheet = false
    @State private var previewDoc: BusinessDocument?

    private var agreements: [BusinessDocument] {
        documents.filter { $0.doc_type == "agreement" }
    }
    private var photos: [BusinessDocument] {
        documents.filter { $0.doc_type == "photo" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Documents")
                    .font(.custom("Syne-Bold", size: 16))
                    .foregroundColor(Color(hex: "0f1117"))
                Spacer()
                Text("\(documents.count)")
                    .font(.custom("DMSans-SemiBold", size: 12))
                    .foregroundColor(Color(hex: "7a7f94"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color(hex: "e2dfd6"))
                    .cornerRadius(50)

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
                    .background(Color(hex: "0f1117"))
                    .cornerRadius(50)
                }
            }

            if loading {
                HStack { Spacer(); ProgressView().padding(.vertical, 20); Spacer() }
            } else if documents.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "doc")
                        .font(.system(size: 28))
                        .foregroundColor(Color(hex: "e2dfd6"))
                    Text("No documents uploaded yet")
                        .font(.custom("DMSans-Regular", size: 13))
                        .foregroundColor(Color(hex: "7a7f94"))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
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
        .background(Color.white)
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
    }

    private func docSubsection(title: String, icon: String, color: Color, docs: [BusinessDocument]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(color)
                Text(title.uppercased())
                    .font(.custom("DMSans-SemiBold", size: 10))
                    .foregroundColor(Color(hex: "7a7f94"))
                    .tracking(0.5)
                Text("(\(docs.count))")
                    .font(.custom("DMSans-Regular", size: 10))
                    .foregroundColor(Color(hex: "7a7f94"))
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
                    .foregroundColor(Color(hex: "0f1117"))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let name = document.uploaded_by_name {
                        Text(name)
                            .font(.custom("DMSans-Regular", size: 11))
                            .foregroundColor(Color(hex: "7a7f94"))
                    }
                    Text(shortDate(document.created_at))
                        .font(.custom("DMSans-Regular", size: 11))
                        .foregroundColor(Color(hex: "7a7f94"))
                }

                if let notes = document.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.custom("DMSans-Italic", size: 11))
                        .foregroundColor(Color(hex: "7a7f94"))
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(hex: "e2dfd6"))
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
                        .foregroundColor(Color(hex: "3a3d4a"))
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
                                .foregroundColor(Color(hex: "0f1117"))

                            Text("PDF preview is not available in-app.\nThe file is stored on the server.")
                                .font(.custom("DMSans-Regular", size: 13))
                                .foregroundColor(Color(hex: "7a7f94"))
                                .multilineTextAlignment(.center)

                            docMeta
                        }
                        .padding(16)
                    }
                }
            }
            .background(Color(hex: "f5f4f0"))
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
                        .foregroundColor(Color(hex: "7a7f94"))
                        .tracking(0.4)
                    Text(notes)
                        .font(.custom("DMSans-Regular", size: 13))
                        .foregroundColor(Color(hex: "0f1117"))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white)
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }

    private func metaItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.custom("DMSans-SemiBold", size: 8))
                .foregroundColor(Color(hex: "7a7f94"))
                .tracking(0.4)
            Text(value)
                .font(.custom("DMSans-Medium", size: 13))
                .foregroundColor(Color(hex: "0f1117"))
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
                            .background(Color(hex: "ffe5e7"))
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
                            .foregroundColor(Color(hex: "0f1117"))
                            .frame(maxWidth: .infinity)
                            .padding(14)
                            .background(Color.white)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                                    .foregroundColor(Color(hex: "e2dfd6"))
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
                        TextField("Optional description", text: $notes)
                            .font(.custom("DMSans-Regular", size: 14))
                            .padding(12)
                            .background(Color.white)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "e2dfd6"), lineWidth: 1))
                    }
                }
                .padding(20)
            }
            .background(Color(hex: "f5f4f0"))
            .navigationTitle("Upload Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.custom("DMSans-Regular", size: 14))
                        .foregroundColor(Color(hex: "7a7f94"))
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
            .foregroundColor(Color(hex: "7a7f94"))
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
