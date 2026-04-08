// AdlerCRM/Views/TodoView.swift  07/04/2026 20:28:49
import SwiftUI

struct TodoView: View {
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

    var body: some View {
        VStack(spacing: 0) {
            dateBar
            if showCalendar {
                TodoCalendarGrid(selectedDate: $selectedDate, calendarMonth: $calendarMonth, todoDates: todoDates)
                    .padding(.horizontal, 12).padding(.bottom, 8)
                    .background(Color.white)
                    .overlay(Rectangle().fill(Color(hex: "e2dfd6")).frame(height: 1), alignment: .bottom)
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
        .background(Color(hex: "f5f4f0"))
        .navigationTitle("To-Do")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 14) {
                    Button(action: { showAddSheet = true }) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 18)).foregroundColor(Color(hex: "c8893a"))
                    }
                    Button(action: { Task { await loadTodos() } }) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 14)).foregroundColor(Color(hex: "7a7f94"))
                    }
                }
            }
        }
        .task { await loadTodos(); await loadDateMarkers() }
        .onChange(of: selectedDate) { _, _ in Task { await loadTodos() } }
        .onChange(of: calendarMonth) { _, _ in Task { await loadDateMarkers() } }
        .sheet(isPresented: $showAddSheet) {
            AddTodoSheet(deadlineDate: selectedDate, onSave: { Task { await loadTodos(); await loadDateMarkers() } })
        }
        .sheet(item: $editingTodo) { todo in
            EditTodoSheet(todo: todo, onSave: { Task { await loadTodos(); await loadDateMarkers() } })
        }
        .confirmationDialog("Delete this task?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let todo = todoToDelete { deleteTodo(todo) } }
            Button("Cancel", role: .cancel) { todoToDelete = nil }
        } message: { Text("This task will be permanently removed.") }
    }

    private var dateBar: some View {
        HStack(spacing: 12) {
            Button(action: { selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate }) {
                Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold)).foregroundColor(Color(hex: "7a7f94"))
            }
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showCalendar.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar").font(.system(size: 12)).foregroundColor(Color(hex: "c8893a"))
                    Text(formattedDate(selectedDate)).font(.custom("DMSans-SemiBold", size: 14)).foregroundColor(Color(hex: "0f1117"))
                    if isToday {
                        Text("Today").font(.custom("DMSans-SemiBold", size: 10)).foregroundColor(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2).background(Color(hex: "2d6a4f")).cornerRadius(50)
                    }
                    Image(systemName: showCalendar ? "chevron.up" : "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundColor(Color(hex: "7a7f94"))
                }
            }.buttonStyle(.plain)
            Button(action: { selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate }) {
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundColor(Color(hex: "7a7f94"))
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
        .background(Color.white)
        .overlay(Rectangle().fill(Color(hex: "e2dfd6")).frame(height: 1), alignment: .bottom)
    }

    private var taskList: some View {
        List {
            let pending = todos.filter { $0.is_done != true }
            if !pending.isEmpty {
                Section {
                    ForEach(pending) { todo in todoRow(todo) }
                } header: {
                    Text("PENDING (\(pending.count))").font(.custom("DMSans-SemiBold", size: 10)).foregroundColor(Color(hex: "7a7f94")).tracking(0.4)
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

    private func todoRow(_ todo: TodoItem) -> some View {
        HStack(spacing: 12) {
            Button(action: { toggleDone(todo) }) {
                Image(systemName: todo.is_done == true ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(todo.is_done == true ? Color(hex: "2d6a4f") : Color(hex: "e2dfd6"))
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 3) {
                Text(todo.title).font(.custom("DMSans-SemiBold", size: 14))
                    .foregroundColor(todo.is_done == true ? Color(hex: "7a7f94") : Color(hex: "0f1117"))
                    .strikethrough(todo.is_done == true).lineLimit(2)
                if let desc = todo.description, !desc.isEmpty {
                    Text(desc).font(.custom("DMSans-Regular", size: 12)).foregroundColor(Color(hex: "7a7f94")).lineLimit(1)
                }
                HStack(spacing: 8) {
                    Label("ID: \(todo.id)", systemImage: "number").font(.custom("DMSans-Regular", size: 10)).foregroundColor(Color(hex: "7a7f94"))
                    if let name = todo.user_name {
                        Text("\u{00B7}").foregroundColor(Color(hex: "e2dfd6"))
                        Text(name).font(.custom("DMSans-Medium", size: 10)).foregroundColor(Color(hex: "c8893a"))
                    }
                    if todo.is_done == true, let doneDate = todo.date_done {
                        Text("\u{00B7}").foregroundColor(Color(hex: "e2dfd6"))
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
                Image(systemName: "ellipsis").font(.system(size: 14)).foregroundColor(Color(hex: "7a7f94")).frame(width: 28, height: 28)
            }
        }.padding(.vertical, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "checklist").font(.system(size: 40)).foregroundColor(Color(hex: "e2dfd6"))
            Text("No tasks for \(isToday ? "today" : formattedDate(selectedDate))")
                .font(.custom("DMSans-Regular", size: 14)).foregroundColor(Color(hex: "7a7f94"))
            Button(action: { showAddSheet = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill").font(.system(size: 13))
                    Text("Add Task").font(.custom("DMSans-SemiBold", size: 13))
                }.foregroundColor(.white).padding(.horizontal, 16).padding(.vertical, 10).background(Color(hex: "c8893a")).cornerRadius(8)
            }
            Spacer()
        }
    }

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

// MARK: - Custom Calendar Grid with Todo Markers

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
        let firstWeekday = cal.component(.weekday, from: monthStart) - 1
        var days: [Date?] = Array(repeating: nil, count: firstWeekday)
        for day in range { if let date = cal.date(byAdding: .day, value: day - 1, to: monthStart) { days.append(date) } }
        while days.count % 7 != 0 { days.append(nil) }
        return days
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button(action: { calendarMonth = cal.date(byAdding: .month, value: -1, to: calendarMonth) ?? calendarMonth }) {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold)).foregroundColor(Color(hex: "7a7f94"))
                }
                Spacer()
                Text(monthLabel).font(.custom("DMSans-SemiBold", size: 15)).foregroundColor(Color(hex: "0f1117"))
                Spacer()
                Button(action: { calendarMonth = cal.date(byAdding: .month, value: 1, to: calendarMonth) ?? calendarMonth }) {
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundColor(Color(hex: "7a7f94"))
                }
            }.padding(.horizontal, 4)

            HStack(spacing: 0) {
                ForEach(dayNames, id: \.self) { name in
                    Text(name).font(.custom("DMSans-SemiBold", size: 11)).foregroundColor(Color(hex: "7a7f94")).frame(maxWidth: .infinity)
                }
            }

            let days = monthDays
            let rows = days.count / 7
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { col in
                        let idx = row * 7 + col
                        if idx < days.count, let date = days[idx] { dateCell(date) }
                        else { Color.clear.frame(maxWidth: .infinity, minHeight: 36) }
                    }
                }
            }
        }.padding(.vertical, 8)
    }

    private func dateCell(_ date: Date) -> some View {
        let dayNum = cal.component(.day, from: date)
        let isSelected = cal.isDate(date, inSameDayAs: selectedDate)
        let isCurrentDay = cal.isDateInToday(date)
        let hasTodos = todoDates.contains(dateFmt.string(from: date))
        return Button(action: { selectedDate = date }) {
            VStack(spacing: 2) {
                Text("\(dayNum)")
                    .font(.custom(isSelected ? "DMSans-SemiBold" : "DMSans-Regular", size: 14))
                    .foregroundColor(isSelected ? .white : (isCurrentDay ? Color(hex: "c8893a") : Color(hex: "0f1117")))
                    .frame(width: 30, height: 30)
                    .background(isSelected ? Color(hex: "c8893a") : Color.clear)
                    .cornerRadius(15)
                Circle().fill(hasTodos ? Color(hex: "2d6a4f") : Color.clear).frame(width: 5, height: 5)
            }
        }.buttonStyle(.plain).frame(maxWidth: .infinity, minHeight: 36)
    }
}

// MARK: - Today's Tasks Sheet (for RoutePlannerView)

struct TodayTasksSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var todos: [TodoItem] = []
    @State private var loading = true
    @State private var showAddSheet = false
    @State private var editingTodo: TodoItem?
    private let todayStr: String = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date()) }()

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    VStack { Spacer(); ProgressView("Loading tasks\u{2026}").font(.custom("DMSans-Regular", size: 14)); Spacer() }
                } else if todos.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "checklist").font(.system(size: 40)).foregroundColor(Color(hex: "e2dfd6"))
                        Text("No tasks for today").font(.custom("DMSans-Regular", size: 14)).foregroundColor(Color(hex: "7a7f94"))
                        Button(action: { showAddSheet = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill").font(.system(size: 13))
                                Text("Add Task").font(.custom("DMSans-SemiBold", size: 13))
                            }.foregroundColor(.white).padding(.horizontal, 16).padding(.vertical, 10).background(Color(hex: "c8893a")).cornerRadius(8)
                        }
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(todos) { todo in
                            HStack(spacing: 12) {
                                Button(action: { toggleTodo(todo) }) {
                                    Image(systemName: todo.is_done == true ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 22))
                                        .foregroundColor(todo.is_done == true ? Color(hex: "2d6a4f") : Color(hex: "e2dfd6"))
                                }.buttonStyle(.plain)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(todo.title).font(.custom("DMSans-SemiBold", size: 14))
                                        .foregroundColor(todo.is_done == true ? Color(hex: "7a7f94") : Color(hex: "0f1117"))
                                        .strikethrough(todo.is_done == true).lineLimit(2)
                                    if let desc = todo.description, !desc.isEmpty {
                                        Text(desc).font(.custom("DMSans-Regular", size: 12)).foregroundColor(Color(hex: "7a7f94")).lineLimit(1)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { editingTodo = todo }
                                Spacer()
                            }.padding(.vertical, 4)
                        }
                    }.listStyle(.plain)
                }
            }
            .navigationTitle("Today's Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showAddSheet = true }) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 18)).foregroundColor(Color(hex: "c8893a"))
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.font(.custom("DMSans-Medium", size: 14)).foregroundColor(Color(hex: "c8893a"))
                }
            }
            .task { await loadTodos() }
            .sheet(isPresented: $showAddSheet) { AddTodoSheet(deadlineDate: Date(), onSave: { Task { await loadTodos() } }) }
            .sheet(item: $editingTodo) { todo in EditTodoSheet(todo: todo, onSave: { Task { await loadTodos() } }) }
        }
    }

    private func loadTodos() async { loading = true; do { todos = try await APIClient.shared.getTodos(date: todayStr) } catch { }; loading = false }
    private func toggleTodo(_ todo: TodoItem) { Task { do { _ = try await APIClient.shared.toggleTodo(id: todo.id); await loadTodos() } catch { } } }
}

// MARK: - Add Todo Sheet

struct AddTodoSheet: View {
    let deadlineDate: Date; let onSave: () -> Void
    @Environment(\.dismiss) var dismiss
    @State private var title = ""; @State private var desc = ""; @State private var deadline: Date
    @State private var saving = false; @State private var errorMsg = ""
    init(deadlineDate: Date, onSave: @escaping () -> Void) { self.deadlineDate = deadlineDate; self.onSave = onSave; _deadline = State(initialValue: deadlineDate) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if !errorMsg.isEmpty {
                        Text(errorMsg).font(.custom("DMSans-Regular", size: 13)).foregroundColor(Color(hex: "c1121f"))
                            .padding(12).frame(maxWidth: .infinity).background(Color(hex: "ffe5e7")).cornerRadius(8)
                    }
                    todoField(label: "Task Title", text: $title, placeholder: "What needs to be done?")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DESCRIPTION (OPTIONAL)").font(.custom("DMSans-SemiBold", size: 9)).foregroundColor(Color(hex: "7a7f94")).tracking(0.4)
                        TextEditor(text: $desc)
                            .font(.custom("DMSans-Regular", size: 14))
                            .frame(minHeight: 80)
                            .padding(8)
                            .scrollContentBackground(.hidden)
                            .background(Color.white)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "e2dfd6"), lineWidth: 1))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DEADLINE").font(.custom("DMSans-SemiBold", size: 9)).foregroundColor(Color(hex: "7a7f94")).tracking(0.4)
                        DatePicker("", selection: $deadline, displayedComponents: .date).labelsHidden().tint(Color(hex: "c8893a"))
                    }
                }.padding(20)
            }.background(Color(hex: "f5f4f0"))
            .navigationTitle("New Task").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() }.font(.custom("DMSans-Regular", size: 14)).foregroundColor(Color(hex: "7a7f94")) }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: save) { if saving { ProgressView().scaleEffect(0.8) } else { Text("Save").font(.custom("DMSans-SemiBold", size: 14)) } }
                        .foregroundColor(Color(hex: "2d6a4f")).disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
        }
    }

    private func save() {
        saving = true; errorMsg = ""; let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        Task {
            do { _ = try await APIClient.shared.createTodo(title: title.trimmingCharacters(in: .whitespaces), description: desc.trimmingCharacters(in: .whitespaces).isEmpty ? nil : desc.trimmingCharacters(in: .whitespaces), deadlineDate: fmt.string(from: deadline)); onSave(); dismiss() } catch { errorMsg = error.localizedDescription }
            saving = false
        }
    }

    private func todoField(label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.custom("DMSans-SemiBold", size: 9)).foregroundColor(Color(hex: "7a7f94")).tracking(0.4)
            TextField(placeholder, text: text).font(.custom("DMSans-Regular", size: 14)).padding(12).background(Color.white).cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "e2dfd6"), lineWidth: 1))
        }
    }
}

// MARK: - Edit Todo Sheet

struct EditTodoSheet: View {
    let todo: TodoItem; let onSave: () -> Void
    @Environment(\.dismiss) var dismiss
    @State private var title: String; @State private var desc: String; @State private var deadline: Date
    @State private var saving = false; @State private var errorMsg = ""

    init(todo: TodoItem, onSave: @escaping () -> Void) {
        self.todo = todo; self.onSave = onSave
        _title = State(initialValue: todo.title); _desc = State(initialValue: todo.description ?? "")
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        _deadline = State(initialValue: (todo.deadline_date.flatMap { fmt.date(from: String($0.prefix(10))) }) ?? Date())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if !errorMsg.isEmpty {
                        Text(errorMsg).font(.custom("DMSans-Regular", size: 13)).foregroundColor(Color(hex: "c1121f"))
                            .padding(12).frame(maxWidth: .infinity).background(Color(hex: "ffe5e7")).cornerRadius(8)
                    }
                    editField(label: "Task Title", text: $title, placeholder: "What needs to be done?")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DESCRIPTION (OPTIONAL)").font(.custom("DMSans-SemiBold", size: 9)).foregroundColor(Color(hex: "7a7f94")).tracking(0.4)
                        TextEditor(text: $desc)
                            .font(.custom("DMSans-Regular", size: 14))
                            .frame(minHeight: 80)
                            .padding(8)
                            .scrollContentBackground(.hidden)
                            .background(Color.white)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "e2dfd6"), lineWidth: 1))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DEADLINE").font(.custom("DMSans-SemiBold", size: 9)).foregroundColor(Color(hex: "7a7f94")).tracking(0.4)
                        DatePicker("", selection: $deadline, displayedComponents: .date).labelsHidden().tint(Color(hex: "c8893a"))
                    }
                    HStack(spacing: 8) {
                        Label("ID: \(todo.id)", systemImage: "number")
                        if let entered = todo.date_entered { Text("\u{00B7}").foregroundColor(Color(hex: "e2dfd6")); Text("Added \(String(entered.prefix(10)))") }
                    }.font(.custom("DMSans-Regular", size: 11)).foregroundColor(Color(hex: "7a7f94"))
                }.padding(20)
            }.background(Color(hex: "f5f4f0"))
            .navigationTitle("Edit Task").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() }.font(.custom("DMSans-Regular", size: 14)).foregroundColor(Color(hex: "7a7f94")) }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: save) { if saving { ProgressView().scaleEffect(0.8) } else { Text("Save").font(.custom("DMSans-SemiBold", size: 14)) } }
                        .foregroundColor(Color(hex: "2d6a4f")).disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
        }
    }

    private func save() {
        saving = true; errorMsg = ""; let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        Task {
            do { _ = try await APIClient.shared.updateTodo(id: todo.id, title: title.trimmingCharacters(in: .whitespaces), description: desc.trimmingCharacters(in: .whitespaces).isEmpty ? nil : desc.trimmingCharacters(in: .whitespaces), deadlineDate: fmt.string(from: deadline)); onSave(); dismiss() } catch { errorMsg = error.localizedDescription }
            saving = false
        }
    }

    private func editField(label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.custom("DMSans-SemiBold", size: 9)).foregroundColor(Color(hex: "7a7f94")).tracking(0.4)
            TextField(placeholder, text: text).font(.custom("DMSans-Regular", size: 14)).padding(12).background(Color.white).cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "e2dfd6"), lineWidth: 1))
        }
    }
}
