// AdlerCRM/Views/CorporateView.swift  07/04/2026 20:28:49
import SwiftUI
import PhotosUI

struct CorporateView: View {
    @EnvironmentObject var auth: AuthManager
    @State private var documents: [CorporateDocument] = []
    @State private var notes: [CorporateNote] = []
    @State private var loading = true
    @State private var showUploadSheet = false
    @State private var showAddNote = false
    @State private var editingNote: CorporateNote?
    @State private var showDeleteDocConfirm = false
    @State private var docToDelete: CorporateDocument?
    @State private var showDeleteNoteConfirm = false
    @State private var noteToDelete: CorporateNote?
    @State private var previewDoc: CorporateDocument?
    @State private var showDocPreview = false
    @State private var previewData: Data?

    private var isAdmin: Bool { auth.currentUser?.role == "Administrator" }
    private var docFiles: [CorporateDocument] { documents.filter { $0.doc_type == "document" } }
    private var photos: [CorporateDocument] { documents.filter { $0.doc_type == "photo" } }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Notes card
                notesCard

                // Documents card
                documentsCard("Documents", icon: "doc.text.fill", color: Color(hex: "1d4e89"), items: docFiles, docType: "document")

                // Photos card
                documentsCard("Photos", icon: "photo.fill", color: Color(hex: "2d6a4f"), items: photos, docType: "photo")
            }
            .padding(12)
        }
        .background(Color(hex: "f5f4f0"))
        .navigationTitle("Corporate")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadAll() }
        .sheet(isPresented: $showUploadSheet) {
            CorporateUploadSheet(onSave: { Task { await loadAll() } })
        }
        .sheet(isPresented: $showAddNote) {
            CorporateNoteSheet(note: nil, onSave: { Task { await loadAll() } })
        }
        .sheet(item: $editingNote) { note in
            CorporateNoteSheet(note: note, onSave: { Task { await loadAll() } })
        }
        .sheet(isPresented: $showDocPreview) {
            if let doc = previewDoc, let data = previewData {
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(doc.original_name ?? doc.file_name ?? "file")
                CorporateFilePreview(url: { try! data.write(to: tempURL); return tempURL }(), fileName: doc.original_name ?? "File")
            }
        }
        .confirmationDialog("Delete this document?", isPresented: $showDeleteDocConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let d = docToDelete { deleteDoc(d) } }
            Button("Cancel", role: .cancel) { docToDelete = nil }
        }
        .confirmationDialog("Delete this note?", isPresented: $showDeleteNoteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let n = noteToDelete { deleteNote(n) } }
            Button("Cancel", role: .cancel) { noteToDelete = nil }
        }
    }

    // MARK: - Notes Card

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Notes", systemImage: "note.text")
                    .font(.custom("Syne-Bold", size: 16))
                    .foregroundColor(Color(hex: "0f1117"))
                Spacer()
                Text("\(notes.count)")
                    .font(.custom("DMSans-SemiBold", size: 11))
                    .foregroundColor(Color(hex: "7a7f94"))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color(hex: "e2dfd6"))
                    .cornerRadius(50)
                if isAdmin {
                    Button(action: { showAddNote = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(Color(hex: "c8893a"))
                    }
                }
            }

            if loading {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12)
            } else if notes.isEmpty {
                Text("No corporate notes yet.")
                    .font(.custom("DMSans-Regular", size: 13))
                    .foregroundColor(Color(hex: "7a7f94"))
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(notes) { note in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.note_text)
                                .font(.custom("DMSans-Regular", size: 13))
                                .foregroundColor(Color(hex: "0f1117"))

                            HStack(spacing: 8) {
                                Text(formatDate(note.created_at))
                                    .font(.custom("DMSans-Regular", size: 10))
                                    .foregroundColor(Color(hex: "7a7f94"))
                                if let by = note.created_by_name {
                                    Text("·").foregroundColor(Color(hex: "e2dfd6"))
                                    Text(by)
                                        .font(.custom("DMSans-Medium", size: 10))
                                        .foregroundColor(Color(hex: "c8893a"))
                                }
                                Spacer()
                                if isAdmin {
                                    Menu {
                                        Button(action: { editingNote = note }) { Label("Edit", systemImage: "pencil") }
                                        Button(role: .destructive, action: { noteToDelete = note; showDeleteNoteConfirm = true }) { Label("Delete", systemImage: "trash") }
                                    } label: {
                                        Image(systemName: "ellipsis")
                                            .font(.system(size: 12)).foregroundColor(Color(hex: "7a7f94"))
                                            .frame(width: 24, height: 24)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 8)
                        if note.id != notes.last?.id { Divider() }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 8, y: 2)
    }

    // MARK: - Documents/Photos Card

    private func documentsCard(_ title: String, icon: String, color: Color, items: [CorporateDocument], docType: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.custom("Syne-Bold", size: 16))
                    .foregroundColor(Color(hex: "0f1117"))
                Spacer()
                Text("\(items.count)")
                    .font(.custom("DMSans-SemiBold", size: 11))
                    .foregroundColor(color)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(color.opacity(0.15))
                    .cornerRadius(50)
                if isAdmin {
                    Button(action: { showUploadSheet = true }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(Color(hex: "c8893a"))
                    }
                }
            }

            if loading {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12)
            } else if items.isEmpty {
                Text("No \(title.lowercased()) uploaded yet.")
                    .font(.custom("DMSans-Regular", size: 13))
                    .foregroundColor(Color(hex: "7a7f94"))
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(items) { doc in
                        HStack(spacing: 12) {
                            Image(systemName: docType == "photo" ? "photo" : "doc.fill")
                                .font(.system(size: 18))
                                .foregroundColor(color)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(doc.original_name ?? doc.file_name ?? "File")
                                    .font(.custom("DMSans-SemiBold", size: 13))
                                    .foregroundColor(Color(hex: "0f1117"))
                                    .lineLimit(1)
                                HStack(spacing: 8) {
                                    Text(formatDate(doc.created_at))
                                        .font(.custom("DMSans-Regular", size: 10))
                                        .foregroundColor(Color(hex: "7a7f94"))
                                    if let by = doc.uploaded_by_name {
                                        Text("·").foregroundColor(Color(hex: "e2dfd6"))
                                        Text(by).font(.custom("DMSans-Medium", size: 10)).foregroundColor(Color(hex: "c8893a"))
                                    }
                                    if let size = doc.file_size {
                                        Text("·").foregroundColor(Color(hex: "e2dfd6"))
                                        Text(formatSize(size)).font(.custom("DMSans-Regular", size: 10)).foregroundColor(Color(hex: "7a7f94"))
                                    }
                                }
                            }
                            Spacer()
                            if isAdmin {
                                Button(action: { docToDelete = doc; showDeleteDocConfirm = true }) {
                                    Image(systemName: "trash").font(.system(size: 12)).foregroundColor(Color(hex: "c1121f").opacity(0.4))
                                }.buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .onTapGesture { openDoc(doc) }
                        if doc.id != items.last?.id { Divider().padding(.leading, 36) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 8, y: 2)
    }

    // MARK: - Logic

    private func loadAll() async {
        loading = true
        do {
            documents = try await APIClient.shared.getCorporateDocuments()
            notes = try await APIClient.shared.getCorporateNotes()
        } catch { }
        loading = false
    }

    private func deleteDoc(_ doc: CorporateDocument) {
        Task { do { try await APIClient.shared.deleteCorporateDocument(id: doc.id); await loadAll() } catch { }; docToDelete = nil }
    }

    private func deleteNote(_ note: CorporateNote) {
        Task { do { try await APIClient.shared.deleteCorporateNote(id: note.id); await loadAll() } catch { }; noteToDelete = nil }
    }

    private func openDoc(_ doc: CorporateDocument) {
        previewDoc = doc
        Task {
            do {
                let data = try await APIClient.shared.downloadCorporateFile(id: doc.id)
                previewData = data
                showDocPreview = true
            } catch { }
        }
    }

    private func formatDate(_ str: String?) -> String {
        guard let s = str else { return "" }
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = iso.date(from: s) ?? ISO8601DateFormatter().date(from: s) else { return String(s.prefix(10)) }
        let fmt = DateFormatter(); fmt.dateFormat = "MMM d, yyyy"; return fmt.string(from: date)
    }

    private func formatSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
    }
}

// MARK: - File Preview

struct CorporateFilePreview: View {
    let url: URL
    let fileName: String
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            if url.pathExtension.lowercased() == "pdf" {
                PDFKitView(url: url)
            } else if ["jpg","jpeg","png","gif","heic","webp"].contains(url.pathExtension.lowercased()) {
                if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                    ScrollView { Image(uiImage: img).resizable().scaledToFit().padding() }
                } else { Text("Cannot preview this file").foregroundColor(Color(hex: "7a7f94")) }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.fill").font(.system(size: 48)).foregroundColor(Color(hex: "e2dfd6"))
                    Text(fileName).font(.custom("DMSans-SemiBold", size: 14)).foregroundColor(Color(hex: "0f1117"))
                    ShareLink(item: url) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up").font(.system(size: 13))
                            Text("Share / Open In…").font(.custom("DMSans-SemiBold", size: 13))
                        }.foregroundColor(.white).padding(.horizontal, 16).padding(.vertical, 10).background(Color(hex: "c8893a")).cornerRadius(8)
                    }
                }
            }
        }
        .navigationTitle(fileName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Done") { dismiss() }.font(.custom("DMSans-Medium", size: 14)).foregroundColor(Color(hex: "c8893a"))
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 14)).foregroundColor(Color(hex: "c8893a"))
                }
            }
        }
    }
}

// MARK: - Upload Sheet

struct CorporateUploadSheet: View {
    let onSave: () -> Void
    @Environment(\.dismiss) var dismiss
    @State private var docType = "document"
    @State private var notes = ""
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedData: Data?
    @State private var selectedFileName = "file"
    @State private var selectedMimeType = "application/octet-stream"
    @State private var saving = false
    @State private var errorMsg = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if !errorMsg.isEmpty {
                        Text(errorMsg).font(.custom("DMSans-Regular", size: 13)).foregroundColor(Color(hex: "c1121f"))
                            .padding(12).frame(maxWidth: .infinity).background(Color(hex: "ffe5e7")).cornerRadius(8)
                    }

                    Picker("Type", selection: $docType) {
                        Text("Document").tag("document")
                        Text("Photo").tag("photo")
                    }.pickerStyle(.segmented)

                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        HStack {
                            Image(systemName: "paperclip").font(.system(size: 14))
                            Text(selectedData != nil ? selectedFileName : "Select File")
                                .font(.custom("DMSans-Medium", size: 14))
                        }
                        .foregroundColor(Color(hex: "c8893a"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "e2dfd6"), lineWidth: 1))
                    }
                    .onChange(of: selectedItem) { _, item in
                        guard let item = item else { return }
                        Task {
                            if let data = try? await item.loadTransferable(type: Data.self) {
                                selectedData = data
                                if let ct = item.supportedContentTypes.first {
                                    selectedMimeType = ct.preferredMIMEType ?? "application/octet-stream"
                                    selectedFileName = "upload.\(ct.preferredFilenameExtension ?? "bin")"
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("NOTES (OPTIONAL)").font(.custom("DMSans-SemiBold", size: 9)).foregroundColor(Color(hex: "7a7f94")).tracking(0.4)
                        TextEditor(text: $notes)
                            .font(.custom("DMSans-Regular", size: 14))
                            .frame(minHeight: 80)
                            .padding(8)
                            .scrollContentBackground(.hidden)
                            .background(Color.white)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "e2dfd6"), lineWidth: 1))
                    }
                }.padding(20)
            }
            .background(Color(hex: "f5f4f0"))
            .navigationTitle("Upload to Corporate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }.font(.custom("DMSans-Regular", size: 14)).foregroundColor(Color(hex: "7a7f94"))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: upload) {
                        if saving { ProgressView().scaleEffect(0.8) }
                        else { Text("Upload").font(.custom("DMSans-SemiBold", size: 14)) }
                    }.foregroundColor(Color(hex: "2d6a4f")).disabled(selectedData == nil || saving)
                }
            }
        }
    }

    private func upload() {
        guard let data = selectedData else { return }
        saving = true; errorMsg = ""
        Task {
            do {
                _ = try await APIClient.shared.uploadCorporateDocument(
                    fileData: data, fileName: selectedFileName, mimeType: selectedMimeType,
                    docType: docType, notes: notes.isEmpty ? nil : notes
                )
                onSave(); dismiss()
            } catch { errorMsg = error.localizedDescription }
            saving = false
        }
    }
}

// MARK: - Note Sheet (Add/Edit)

struct CorporateNoteSheet: View {
    let note: CorporateNote?
    let onSave: () -> Void
    @Environment(\.dismiss) var dismiss
    @State private var text: String
    @State private var saving = false
    @State private var errorMsg = ""

    init(note: CorporateNote?, onSave: @escaping () -> Void) {
        self.note = note; self.onSave = onSave
        _text = State(initialValue: note?.note_text ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if !errorMsg.isEmpty {
                    Text(errorMsg).font(.custom("DMSans-Regular", size: 13)).foregroundColor(Color(hex: "c1121f"))
                        .padding(12).frame(maxWidth: .infinity).background(Color(hex: "ffe5e7")).cornerRadius(8)
                }
                TextEditor(text: $text)
                    .font(.custom("DMSans-Regular", size: 14))
                    .frame(minHeight: 120)
                    .padding(8).background(Color.white).cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "e2dfd6"), lineWidth: 1))
                Spacer()
            }
            .padding(20)
            .background(Color(hex: "f5f4f0"))
            .navigationTitle(note == nil ? "Add Note" : "Edit Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }.font(.custom("DMSans-Regular", size: 14)).foregroundColor(Color(hex: "7a7f94"))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: save) {
                        if saving { ProgressView().scaleEffect(0.8) }
                        else { Text("Save").font(.custom("DMSans-SemiBold", size: 14)) }
                    }.foregroundColor(Color(hex: "2d6a4f")).disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
        }
    }

    private func save() {
        saving = true; errorMsg = ""
        Task {
            do {
                if let note = note {
                    _ = try await APIClient.shared.updateCorporateNote(id: note.id, text: text.trimmingCharacters(in: .whitespaces))
                } else {
                    _ = try await APIClient.shared.createCorporateNote(text: text.trimmingCharacters(in: .whitespaces))
                }
                onSave(); dismiss()
            } catch { errorMsg = error.localizedDescription }
            saving = false
        }
    }
}
