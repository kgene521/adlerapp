// /AdlerCRM/Views/TodoView.swift  15/04/2026 01:00:00 EDT
import SwiftUI

struct TodoView: View {
    @EnvironmentObject var auth: AuthManager
    @State private var selectedDate = Date()
    @State private var todos: [TodoItem] = []
    @State private var loading = true
    @State private var showAddSheet = false
    @State private var editingTodo: TodoItem?
    @State private var showDeleteConfirm = false
    @State private var todoToDelete: TodoItem?
    @State private var todoDates: Set<String> = []
    @State private var showCalendar = false
    @State private var calendarMonth = Date()

    private let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    private var selectedDateStr: String { dateFmt.string(from: selectedDate) }
    private var isToday: Bool { Calendar.current.isDateInToday(selectedDate) }
    private var pendingCount: Int { todos.filter { $0.is_done != true }.count }
    private var doneCount: Int { todos.filter { $0.is_done == true }.count }
    private var currentUserId: Int { auth.currentUser?.id ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            dateBar
            if showCalendar {
                TodoCalendarGrid(selectedDate: $selectedDate, calendarMonth: $calendarMonth, todoDates: todoDates)
                    .padding(.horizontal, 12).padding(.bottom, 8)
                    .background(Color.theme.surface)
                    .overlay(Rectangle().fill(Color.theme.border).frame(height: 1), alignment: .bottom)
            }
            if loading {
                Spacer()
                ProgressView("Loading tasks\u{2026}").font(.custom("DMSans-Regular", size: 14))
                Spacer()
            } else if todos.isEmpty {
                emptyState
            } else {
                taskList
            }
        }
        .background(Color.theme.background)
        .navigationTitle("To-Do")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 14) {
                    Button(action: { showAddSheet = true }) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 18)).foregroundColor(Color(hex: "c8893a"))
                    }
                    Button(action: { Task { await loadTodos() } }) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 14)).foregroundColor(Color.theme.textSecondary)
                    }
                }
            }
        }
        .task { await loadTodos(); await loadDateMarkers() }
        .onChange(of: selectedDate) { _, _ in Task { await loadTodos() } }
        .onChange(of: calendarMonth) { _, _ in Task { await loadDateMarkers() } }
        .sheet(isPresented: $showAddSheet) {
            AddTodoSheet(deadlineDate: selectedDate, currentUserId: currentUserId, onSave: { Task { await loadTodos(); await loadDateMarkers() } })
        }
        .sheet(item: $editingTodo) { todo in
            EditTodoSheet(todo: todo, currentUserId: currentUserId, onSave: { Task { await loadTodos(); await loadDateMarkers() } })
        }
        .confirmationDialog("Delete this task?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let todo = todoToDelete { deleteTodo(todo) } }
            Button("Cancel", role: .cancel) { todoToDelete = nil }
        } message: { Text("This task will be permanently removed.") }
    }

    // MARK: - Date Bar

    private var dateBar: some View {
        HStack(spacing: 12) {
            Button(action: { selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate }) {
                Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold)).foregroundColor(Color.theme.textSecondary)
            }
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showCalendar.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar").font(.system(size: 12)).foregroundColor(Color(hex: "c8893a"))
                    Text(formattedDate(selectedDate)).font(.custom("DMSans-SemiBold", size: 14)).foregroundColor(Color.theme.text)
                    if isToday {
                        Text("Today").font(.custom("DMSans-SemiBold", size: 10)).foregroundColor(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2).background(Color(hex: "2d6a4f")).cornerRadius(50)
                    }
                    Image(systemName: showCalendar ? "chevron.up" : "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundColor(Color.theme.textSecondary)
                }
            }.buttonStyle(.plain)
            Button(action: { selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate }) {
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundColor(Color.theme.textSecondary)
            }
            Spacer()
            if !isToday {
                Button(action: { selectedDate = Date() }) {
                    Text("Today").font(.custom("DMSans-SemiBold", size: 12)).foregroundColor(Color(hex: "c8893a"))
                }
            }
            if !todos.isEmpty {
                HStack(spacing: 4) {
                    Text("\(doneCount)/\(todos.count)").font(.custom("DMSans-SemiBold", size: 12))
                        .foregroundColor(pendingCount == 0 ? Color(hex: "2d6a4f") : Color(hex: "c8893a"))
                    Image(systemName: pendingCount == 0 ? "checkmark.circle.fill" : "circle.dotted").font(.system(size: 12))
                        .foregroundColor(pendingCount == 0 ? Color(hex: "2d6a4f") : Color(hex: "c8893a"))
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color.theme.surface)
        .overlay(Rectangle().fill(Color.theme.border).frame(height: 1), alignment: .bottom)
    }

    // MARK: - Task List

    private var taskList: some View {
        List {
            let pending = todos.filter { $0.is_done != true }
            if !pending.isEmpty {
                Section {
                    ForEach(pending) { todo in todoRow(todo) }
                } header: {
                    Text("PENDING (\(pending.count))").font(.custom("DMSans-SemiBold", size: 10)).foregroundColor(Color.theme.textSecondary).tracking(0.4)
                }
            }
            let done = todos.filter { $0.is_done == true }
            if !done.isEmpty {
                Section {
                    ForEach(done) { todo in todoRow(todo) }
                } header: {
                    Text("COMPLETED (\(done.count))").font(.custom("DMSans-SemiBold", size: 10)).foregroundColor(Color(hex: "2d6a4f")).tracking(0.4)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Expiration

    private enum ExpirationStatus { case none, warning, expired }

    private func expirationStatus(_ todo: TodoItem) -> ExpirationStatus {
        guard todo.is_done != true,
              let deadlineStr = todo.deadline_date,
              let _ = dateFmt.date(from: String(deadlineStr.prefix(10))) else { return .none }
        let today = dateFmt.string(from: Date())
        let deadlineKey = String(deadlineStr.prefix(10))
        if deadlineKey < today { return .expired }
        if deadlineKey == today { return .warning }
        return .none
    }

    // MARK: - Todo Row

    private func todoRow(_ todo: TodoItem) -> some View {
        let expStatus = expirationStatus(todo)
        return HStack(spacing: 12) {
            Button(action: { toggleDone(todo) }) {
                Image(systemName: todo.is_done == true ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(
                        todo.is_done == true ? Color(hex: "2d6a4f") :
                        expStatus == .expired ? Color(hex: "c1121f") :
                        expStatus == .warning ? Color(hex: "c8893a") :
                        Color.theme.border
                    )
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 3) {
                Text(todo.title).font(.custom("DMSans-SemiBold", size: 14))
                    .foregroundColor(
                        todo.is_done == true ? Color.theme.textSecondary :
                        expStatus == .expired ? Color(hex: "c1121f") :
                        Color.theme.text
                    )
                    .strikethrough(todo.is_done == true).lineLimit(2)
                if let desc = todo.description, !desc.isEmpty {
                    Text(desc).font(.custom("DMSans-Regular", size: 12)).foregroundColor(Color.theme.textSecondary).lineLimit(1)
                }
                if expStatus == .expired {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9))
                        Text("Expired").font(.custom("DMSans-SemiBold", size: 10))
                    }.foregroundColor(Color(hex: "c1121f"))
                } else if expStatus == .warning {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.badge.exclamationmark.fill").font(.system(size: 9))
                        Text("Due today").font(.custom("DMSans-SemiBold", size: 10))
                    }.foregroundColor(Color(hex: "c8893a"))
                }
                HStack(spacing: 8) {
                    if let assignedName = todo.assigned_to_name {
                        if todo.assigned_to == currentUserId {
                            Label("You", systemImage: "person.fill")
                                .font(.custom("DMSans-Medium", size: 10)).foregroundColor(Color(hex: "2d6a4f"))
                        } else {
                            Label(assignedName, systemImage: "person.fill")
                                .font(.custom("DMSans-Medium", size: 10)).foregroundColor(Color(hex: "c8893a"))
                        }
                    }
                    if let byName = todo.assigned_by_name, todo.assigned_by != currentUserId, todo.assigned_by != todo.assigned_to {
                        Text("\u{00B7}").foregroundColor(Color.theme.border)
                        Text("from \(byName)").font(.custom("DMSans-Regular", size: 10)).foregroundColor(Color.theme.textSecondary)
                    }
                    if todo.is_done == true, let doneDate = todo.date_done {
                        Text("\u{00B7}").foregroundColor(Color.theme.border)
                        Text("Done \(formatShortDate(doneDate))").font(.custom("DMSans-Regular", size: 10)).foregroundColor(Color(hex: "2d6a4f"))
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { editingTodo = todo }
            Spacer()
            Menu {
                Button(action: { editingTodo = todo }) { Label("Edit", systemImage: "pencil") }
                Button(role: .destructive, action: { todoToDelete = todo; showDeleteConfirm = true }) { Label("Delete", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 14)).foregroundColor(Color.theme.textSecondary).frame(width: 28, height: 28)
            }
        }.padding(.vertical, 4)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "checklist").font(.system(size: 40)).foregroundColor(Color.theme.border)
            Text("No tasks for \(isToday ? "today" : formattedDate(selectedDate))")
                .font(.custom("DMSans-Regular", size: 14)).foregroundColor(Color.theme.textSecondary)
            Button(action: { showAddSheet = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill").font(.system(size: 13))
                    Text("Add Task").font(.custom("DMSans-SemiBold", size: 13))
                }.foregroundColor(.white).padding(.horizontal, 16).padding(.vertical, 10).background(Color(hex: "c8893a")).cornerRadius(8)
            }
            Spacer()
        }
    }

    // MARK: - Actions

    private func loadTodos() async {
        loading = true
        do { todos = try await APIClient.shared.getTodos(date: selectedDateStr) } catch { }
        loading = false
    }

    private func loadDateMarkers() async {
        let cal = Calendar.current
        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: calendarMonth)),
              let monthEnd = cal.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart) else { return }
        do {
            let counts = try await APIClient.shared.getTodoDateCounts(from: dateFmt.string(from: monthStart), to: dateFmt.string(from: monthEnd))
            var dates = Set<String>()
            for c in counts { if let d = c.deadline_date { dates.insert(String(d.prefix(10))) } }
            todoDates = dates
        } catch { }
    }

    private func toggleDone(_ todo: TodoItem) {
        Task { do { _ = try await APIClient.shared.toggleTodo(id: todo.id); await loadTodos(); await loadDateMarkers() } catch { } }
    }

    private func deleteTodo(_ todo: TodoItem) {
        Task { do { try await APIClient.shared.deleteTodo(id: todo.id); await loadTodos(); await loadDateMarkers() } catch { }; todoToDelete = nil }
    }

    private func formattedDate(_ date: Date) -> String {
        let fmt = DateFormatter(); fmt.dateFormat = "EEE, MMM d, yyyy"; return fmt.string(from: date)
    }

    private func formatShortDate(_ str: String) -> String {
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = iso.date(from: str) ?? ISO8601DateFormatter().date(from: str) else { return String(str.prefix(10)) }
        let fmt = DateFormatter(); fmt.dateFormat = "MMM d, h:mm a"; return fmt.string(from: date)
    }
}

// MARK: - Calendar Grid

struct TodoCalendarGrid: View {
    @Binding var selectedDate: Date
    @Binding var calendarMonth: Date
    let todoDates: Set<String>
    private let cal = Calendar.current
    private let dayNames = ["S", "M", "T", "W", "T", "F", "S"]
    private let dateFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f }()
    private var monthLabel: String { let fmt = DateFormatter(); fmt.dateFormat = "MMMM yyyy"; return fmt.string(from: calendarMonth) }

    private var monthDays: [Date?] {
        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: calendarMonth)),
              let range = cal.range(of: .day, in: .month, for: monthStart) else { return [] }
        let weekday = cal.component(.weekday, from: monthStart) - 1
        var days: [Date?] = Array(repeating: nil, count: weekday)
        for day in range { if let d = cal.date(bySetting: .day, value: day, of: monthStart) { days.append(d) } }
        return days
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button(action: { calendarMonth = cal.date(byAdding: .month, value: -1, to: calendarMonth) ?? calendarMonth }) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold)).foregroundColor(Color.theme.textSecondary)
                }
                Spacer()
                Text(monthLabel).font(.custom("DMSans-SemiBold", size: 14)).foregroundColor(Color.theme.text)
                Spacer()
                Button(action: { calendarMonth = cal.date(byAdding: .month, value: 1, to: calendarMonth) ?? calendarMonth }) {
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundColor(Color.theme.textSecondary)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
                ForEach(dayNames, id: \.self) { name in
                    Text(name).font(.custom("DMSans-SemiBold", size: 10)).foregroundColor(Color.theme.textSecondary)
                }
                ForEach(Array(monthDays.enumerated()), id: \.offset) { _, date in
                    if let date = date {
                        let dateStr = dateFmt.string(from: date)
                        let isSelected = cal.isDate(date, inSameDayAs: selectedDate)
                        let hasTodo = todoDates.contains(dateStr)
                        Button(action: { selectedDate = date }) {
                            VStack(spacing: 2) {
                                Text("\(cal.component(.day, from: date))")
                                    .font(.custom("DMSans-Medium", size: 13))
                                    .foregroundColor(isSelected ? .white : cal.isDateInToday(date) ? Color(hex: "c8893a") : Color.theme.text)
                                Circle().fill(hasTodo ? Color(hex: "c8893a") : .clear).frame(width: 4, height: 4)
                            }
                            .frame(width: 32, height: 36)
                            .background(isSelected ? Color(hex: "2d6a4f") : .clear)
                            .cornerRadius(6)
                        }.buttonStyle(.plain)
                    } else {
                        Text("").frame(width: 32, height: 36)
                    }
                }
            }
        }
    }
}

// MARK: - Add Todo Sheet

struct AddTodoSheet: View {
    let deadlineDate: Date; let currentUserId: Int; let onSave: () -> Void
    @Environment(\.dismiss) var dismiss
    @State private var title = ""; @State private var desc = ""; @State private var deadline: Date
    @State private var assignToUserId: Int?
    @State private var employees: [NotificationUser] = []
    @State private var saving = false; @State private var errorMsg = ""

    init(deadlineDate: Date, currentUserId: Int, onSave: @escaping () -> Void) {
        self.deadlineDate = deadlineDate; self.currentUserId = currentUserId; self.onSave = onSave
        _deadline = State(initialValue: deadlineDate)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if !errorMsg.isEmpty {
                        Text(errorMsg).font(.custom("DMSans-Regular", size: 13)).foregroundColor(Color(hex: "c1121f"))
                            .padding(12).frame(maxWidth: .infinity).background(Color.theme.red.opacity(0.08)).cornerRadius(8)
                    }
                    todoField(label: "Task Title", text: $title, placeholder: "What needs to be done?")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DESCRIPTION (OPTIONAL)").font(.custom("DMSans-SemiBold", size: 9)).foregroundColor(Color.theme.textSecondary).tracking(0.4)
                        TextEditor(text: $desc).font(.custom("DMSans-Regular", size: 14)).frame(minHeight: 80).padding(8)
                            .scrollContentBackground(.hidden).background(Color.theme.surface).cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.theme.border, lineWidth: 1))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DEADLINE").font(.custom("DMSans-SemiBold", size: 9)).foregroundColor(Color.theme.textSecondary).tracking(0.4)
                        DatePicker("", selection: $deadline, displayedComponents: .date).labelsHidden().tint(Color(hex: "c8893a"))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ASSIGN TO").font(.custom("DMSans-SemiBold", size: 9)).foregroundColor(Color.theme.textSecondary).tracking(0.4)
                        Picker("Assign to", selection: Binding(
                            get: { assignToUserId ?? currentUserId },
                            set: { assignToUserId = $0 }
                        )) {
                            ForEach(employees) { emp in
                                Text("\(emp.name)\(emp.id == currentUserId ? " (Me)" : "")").tag(emp.id)
                            }
                        }.pickerStyle(.menu).tint(Color(hex: "c8893a"))
                    }
                }.padding(20)
            }.background(Color.theme.background)
            .navigationTitle("New Task").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() }.font(.custom("DMSans-Regular", size: 14)).foregroundColor(Color.theme.textSecondary) }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: save) { if saving { ProgressView().scaleEffect(0.8) } else { Text("Save").font(.custom("DMSans-SemiBold", size: 14)) } }
                        .foregroundColor(Color(hex: "2d6a4f")).disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
            .task { await loadEmployees() }
        }
    }

    private func loadEmployees() async {
        do {
            let users: [NotificationUser] = try await APIClient.shared.request(path: "/notifications/users")
            employees = users
            if assignToUserId == nil { assignToUserId = currentUserId }
        } catch { }
    }

    private func save() {
        saving = true; errorMsg = ""; let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        Task {
            do {
                _ = try await APIClient.shared.createTodo(
                    title: title.trimmingCharacters(in: .whitespaces),
                    description: desc.trimmingCharacters(in: .whitespaces).isEmpty ? nil : desc.trimmingCharacters(in: .whitespaces),
                    deadlineDate: fmt.string(from: deadline),
                    assignedTo: assignToUserId ?? currentUserId
                ); onSave(); dismiss()
            } catch { errorMsg = error.localizedDescription }
            saving = false
        }
    }

    private func todoField(label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.custom("DMSans-SemiBold", size: 9)).foregroundColor(Color.theme.textSecondary).tracking(0.4)
            TextField(placeholder, text: text).font(.custom("DMSans-Regular", size: 14)).padding(12).background(Color.theme.surface).cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.theme.border, lineWidth: 1))
        }
    }
}

// MARK: - Edit Todo Sheet

struct EditTodoSheet: View {
    let todo: TodoItem; let currentUserId: Int; let onSave: () -> Void
    @Environment(\.dismiss) var dismiss
    @State private var title: String; @State private var desc: String; @State private var deadline: Date
    @State private var assignToUserId: Int?
    @State private var employees: [NotificationUser] = []
    @State private var saving = false; @State private var errorMsg = ""

    init(todo: TodoItem, currentUserId: Int, onSave: @escaping () -> Void) {
        self.todo = todo; self.currentUserId = currentUserId; self.onSave = onSave
        _title = State(initialValue: todo.title); _desc = State(initialValue: todo.description ?? "")
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        _deadline = State(initialValue: (todo.deadline_date.flatMap { fmt.date(from: String($0.prefix(10))) }) ?? Date())
        _assignToUserId = State(initialValue: todo.assigned_to ?? todo.user_id)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if !errorMsg.isEmpty {
                        Text(errorMsg).font(.custom("DMSans-Regular", size: 13)).foregroundColor(Color(hex: "c1121f"))
                            .padding(12).frame(maxWidth: .infinity).background(Color.theme.red.opacity(0.08)).cornerRadius(8)
                    }
                    editField(label: "Task Title", text: $title, placeholder: "What needs to be done?")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DESCRIPTION (OPTIONAL)").font(.custom("DMSans-SemiBold", size: 9)).foregroundColor(Color.theme.textSecondary).tracking(0.4)
                        TextEditor(text: $desc).font(.custom("DMSans-Regular", size: 14)).frame(minHeight: 80).padding(8)
                            .scrollContentBackground(.hidden).background(Color.theme.surface).cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.theme.border, lineWidth: 1))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DEADLINE").font(.custom("DMSans-SemiBold", size: 9)).foregroundColor(Color.theme.textSecondary).tracking(0.4)
                        DatePicker("", selection: $deadline, displayedComponents: .date).labelsHidden().tint(Color(hex: "c8893a"))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ASSIGN TO").font(.custom("DMSans-SemiBold", size: 9)).foregroundColor(Color.theme.textSecondary).tracking(0.4)
                        Picker("Assign to", selection: Binding(
                            get: { assignToUserId ?? currentUserId },
                            set: { assignToUserId = $0 }
                        )) {
                            ForEach(employees) { emp in
                                Text("\(emp.name)\(emp.id == currentUserId ? " (Me)" : "")").tag(emp.id)
                            }
                        }.pickerStyle(.menu).tint(Color(hex: "c8893a"))
                    }
                    HStack(spacing: 8) {
                        Label("ID: \(todo.id)", systemImage: "number")
                        if let entered = todo.date_entered { Text("\u{00B7}").foregroundColor(Color.theme.border); Text("Added \(String(entered.prefix(10)))") }
                    }.font(.custom("DMSans-Regular", size: 11)).foregroundColor(Color.theme.textSecondary)
                }.padding(20)
            }.background(Color.theme.background)
            .navigationTitle("Edit Task").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() }.font(.custom("DMSans-Regular", size: 14)).foregroundColor(Color.theme.textSecondary) }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: save) { if saving { ProgressView().scaleEffect(0.8) } else { Text("Save").font(.custom("DMSans-SemiBold", size: 14)) } }
                        .foregroundColor(Color(hex: "2d6a4f")).disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
            .task { await loadEmployees() }
        }
    }

    private func loadEmployees() async {
        do {
            let users: [NotificationUser] = try await APIClient.shared.request(path: "/notifications/users")
            employees = users
        } catch { }
    }

    private func save() {
        saving = true; errorMsg = ""; let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        Task {
            do {
                _ = try await APIClient.shared.updateTodo(
                    id: todo.id, title: title.trimmingCharacters(in: .whitespaces),
                    description: desc.trimmingCharacters(in: .whitespaces).isEmpty ? nil : desc.trimmingCharacters(in: .whitespaces),
                    deadlineDate: fmt.string(from: deadline),
                    assignedTo: assignToUserId
                ); onSave(); dismiss()
            } catch { errorMsg = error.localizedDescription }
            saving = false
        }
    }

    private func editField(label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.custom("DMSans-SemiBold", size: 9)).foregroundColor(Color.theme.textSecondary).tracking(0.4)
            TextField(placeholder, text: text).font(.custom("DMSans-Regular", size: 14)).padding(12).background(Color.theme.surface).cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.theme.border, lineWidth: 1))
        }
    }
}

// MARK: - Today Tasks Sheet (used from RoutePlannerView)

struct TodayTasksSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var todos: [TodoItem] = []
    @State private var loading = true

    private var today: String {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"; return fmt.string(from: Date())
    }

    private var pending: [TodoItem] { todos.filter { $0.is_done != true } }
    private var done: [TodoItem] { todos.filter { $0.is_done == true } }

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    VStack { Spacer(); ProgressView("Loading tasks…"); Spacer() }
                } else if todos.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 40)).foregroundColor(Color(hex: "2d6a4f"))
                        Text("No tasks for today").font(.custom("DMSans-Regular", size: 14)).foregroundColor(Color.theme.textSecondary)
                        Spacer()
                    }
                } else {
                    List {
                        if !pending.isEmpty {
                            Section {
                                ForEach(pending) { todo in taskRow(todo) }
                            } header: {
                                Text("PENDING (\(pending.count))").font(.custom("DMSans-SemiBold", size: 10)).foregroundColor(Color.theme.textSecondary).tracking(0.4)
                            }
                        }
                        if !done.isEmpty {
                            Section {
                                ForEach(done) { todo in taskRow(todo) }
                            } header: {
                                Text("DONE (\(done.count))").font(.custom("DMSans-SemiBold", size: 10)).foregroundColor(Color(hex: "2d6a4f")).tracking(0.4)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Color.theme.background)
            .navigationTitle("Today's Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.font(.custom("DMSans-Medium", size: 14)).foregroundColor(Color(hex: "c8893a"))
                }
            }
            .task { await loadTodos() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func taskRow(_ todo: TodoItem) -> some View {
        HStack(spacing: 12) {
            Button(action: { toggleDone(todo) }) {
                Image(systemName: todo.is_done == true ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(todo.is_done == true ? Color(hex: "2d6a4f") : Color.theme.border)
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(todo.title).font(.custom("DMSans-SemiBold", size: 14))
                    .foregroundColor(todo.is_done == true ? Color.theme.textSecondary : Color.theme.text)
                    .strikethrough(todo.is_done == true).lineLimit(1)
                if let name = todo.assigned_to_name {
                    Text(name).font(.custom("DMSans-Regular", size: 11)).foregroundColor(Color(hex: "c8893a"))
                }
            }
            Spacer()
        }.padding(.vertical, 2)
    }

    private func loadTodos() async {
        loading = true
        do { todos = try await APIClient.shared.getTodos(date: today) } catch { }
        loading = false
    }

    private func toggleDone(_ todo: TodoItem) {
        Task {
            do { _ = try await APIClient.shared.toggleTodo(id: todo.id); await loadTodos() } catch { }
        }
    }
}
