//
//  ContentView.swift
//  TimeDrive
//
//  Created by Дмитрий Брагин on 27.03.2026.
//

import SwiftUI
import SwiftData
import Combine

struct ContentView: View {
    private let appContainer: AppContainer

    init(appContainer: AppContainer) {
        self.appContainer = appContainer
    }

    var body: some View {
        TabView {
            NavigationStack {
                TimerView(viewModel: TimerScreenViewModel(useCases: appContainer.timerUseCases, taskRepository: appContainer.taskRepository))
            }
            .tabItem {
                Label("Timer", systemImage: "timer")
            }

            NavigationStack {
                TasksView(viewModel: TasksViewModel(taskRepository: appContainer.taskRepository, projectRepository: appContainer.projectRepository, timerUseCases: appContainer.timerUseCases))
            }
            .tabItem {
                Label("Tasks", systemImage: "checklist")
            }

            NavigationStack {
                ProjectsView(viewModel: ProjectsViewModel(projectRepository: appContainer.projectRepository, taskRepository: appContainer.taskRepository))
            }
            .tabItem {
                Label("Projects", systemImage: "folder")
            }

            NavigationStack {
                SettingsView(
                    viewModel: SettingsViewModel(
                        settingsRepository: appContainer.settingsRepository,
                        syncRepository: appContainer.syncRepository,
                        timerUseCases: appContainer.timerUseCases,
                        syncEngine: appContainer.syncEngine
                    )
                )
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }
}

@MainActor
final class TimerScreenViewModel: ObservableObject {
    @Published var snapshot: ActiveTimerSnapshot?
    @Published var currentTask: Task?
    @Published var switchableTasks: [Task] = []
    @Published var errorMessage: String?

    private let useCases: TimerUseCases
    private let taskRepository: TaskRepository

    init(useCases: TimerUseCases, taskRepository: TaskRepository) {
        self.useCases = useCases
        self.taskRepository = taskRepository
    }

    func restore() {
        do {
            try useCases.recoverTimerStateOnLaunch()
            try refresh()
            try reloadTasks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh(now: Date = .now) throws {
        snapshot = try useCases.activeSnapshot(now: now)
        if let taskId = snapshot?.taskId {
            currentTask = try taskRepository.task(by: taskId)
        } else {
            currentTask = nil
        }
    }

    func safeRefresh(now: Date = .now) {
        do {
            try refresh(now: now)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reloadTasks() throws {
        switchableTasks = try taskRepository.fetchAll(includeDeleted: false)
            .filter { $0.status != .done }
    }

    func startWorkWithoutTask() {
        do {
            _ = try useCases.startWork(taskId: nil)
            try refresh()
            try reloadTasks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopTimer() {
        do {
            try useCases.stopActiveSession()
            try refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func skipToBreak() {
        do {
            _ = try useCases.skipToBreak()
            try refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func switchTask(to taskId: UUID) {
        do {
            _ = try useCases.switchTask(to: taskId)
            try refresh()
            try reloadTasks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum TaskFilter: String, CaseIterable, Identifiable {
    case all
    case todo
    case inProgress
    case done

    var id: Self { self }

    var title: String {
        switch self {
        case .all: return "All"
        case .todo: return "To Do"
        case .inProgress: return "In Progress"
        case .done: return "Done"
        }
    }
}

@MainActor
final class TasksViewModel: ObservableObject {
    @Published var tasks: [Task] = []
    @Published var projects: [Project] = []
    @Published var filter: TaskFilter = .all
    @Published var errorMessage: String?

    private let taskRepository: TaskRepository
    private let projectRepository: ProjectRepository
    private let timerUseCases: TimerUseCases

    init(taskRepository: TaskRepository, projectRepository: ProjectRepository, timerUseCases: TimerUseCases) {
        self.taskRepository = taskRepository
        self.projectRepository = projectRepository
        self.timerUseCases = timerUseCases
    }

    var filteredTasks: [Task] {
        switch filter {
        case .all:
            return tasks
        case .todo:
            return tasks.filter { $0.status == .todo }
        case .inProgress:
            return tasks.filter { $0.status == .inProgress }
        case .done:
            return tasks.filter { $0.status == .done }
        }
    }

    func projectName(for projectId: UUID?) -> String {
        guard let projectId,
              let project = projects.first(where: { $0.id == projectId })
        else {
            return "No Project"
        }
        return project.name
    }

    func load() {
        do {
            tasks = try taskRepository.fetchAll(includeDeleted: false)
            projects = try projectRepository.fetchAll(includeDeleted: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createTask(title: String, notes: String?, projectId: UUID?, status: TaskStatus) {
        do {
            let task = try taskRepository.create(title: title, notes: notes, projectId: projectId, estimateMinutes: nil)
            if status != .todo {
                try taskRepository.update(task: task, title: title, notes: notes, status: status, projectId: projectId)
            }
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateStatus(for task: Task, status: TaskStatus) {
        do {
            try taskRepository.update(task: task, title: task.title, notes: task.notes, status: status, projectId: task.projectId)
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func quickStart(task: Task) {
        do {
            _ = try timerUseCases.startWork(taskId: task.id)
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

@MainActor
final class ProjectsViewModel: ObservableObject {
    @Published var projects: [Project] = []
    @Published var tasks: [Task] = []
    @Published var errorMessage: String?

    private let projectRepository: ProjectRepository
    private let taskRepository: TaskRepository

    init(projectRepository: ProjectRepository, taskRepository: TaskRepository) {
        self.projectRepository = projectRepository
        self.taskRepository = taskRepository
    }

    func load() {
        do {
            projects = try projectRepository.fetchAll(includeDeleted: false)
            tasks = try taskRepository.fetchAll(includeDeleted: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createProject(name: String, color: String?) {
        do {
            _ = try projectRepository.create(name: name, color: color)
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteProjects(at offsets: IndexSet) {
        do {
            for index in offsets {
                let project = projects[index]
                try projectRepository.softDelete(projectId: project.id)
            }
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func tasks(for project: Project) -> [Task] {
        tasks.filter { $0.projectId == project.id }
    }
}

struct SyncStatusSnapshot {
    let isOnlinePlaceholder: Bool
    let pendingOperations: Int
    let lastSyncText: String
}

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var workDurationMinutes: Int = 25
    @Published var breakDurationMinutes: Int = 5
    @Published var autoStartNext: Bool = false
    @Published var syncStatus = SyncStatusSnapshot(isOnlinePlaceholder: false, pendingOperations: 0, lastSyncText: "Not available")
    @Published var isSyncingNow: Bool = false
    @Published var errorMessage: String?

    private let settingsRepository: SettingsRepository
    private let syncRepository: SyncRepository
    private let timerUseCases: TimerUseCases
    private let syncEngine: SyncEngine

    init(
        settingsRepository: SettingsRepository,
        syncRepository: SyncRepository,
        timerUseCases: TimerUseCases,
        syncEngine: SyncEngine
    ) {
        self.settingsRepository = settingsRepository
        self.syncRepository = syncRepository
        self.timerUseCases = timerUseCases
        self.syncEngine = syncEngine
    }

    func load() {
        do {
            let settings = try settingsRepository.getOrCreate()
            workDurationMinutes = max(1, settings.workDurationSec / 60)
            breakDurationMinutes = max(1, settings.breakDurationSec / 60)
            autoStartNext = settings.autoStartNext

            let pending = try syncRepository.pendingOperations().count
            let lastSyncText = formatLastSync(syncEngine.lastSyncAt())
            syncStatus = SyncStatusSnapshot(
                isOnlinePlaceholder: false,
                pendingOperations: pending,
                lastSyncText: lastSyncText
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveDurations() {
        do {
            _ = try timerUseCases.updateDurations(
                workDurationSec: max(1, workDurationMinutes) * 60,
                breakDurationSec: max(1, breakDurationMinutes) * 60
            )
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveAutoStartNext() {
        do {
            _ = try timerUseCases.updateAutoStartNext(autoStartNext)
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func syncNow() {
        guard !isSyncingNow else { return }
        isSyncingNow = true
        errorMessage = nil

        Swift.Task { @MainActor in
            defer {
                isSyncingNow = false
            }
            do {
                try await syncEngine.syncNow()
                load()
            } catch {
                load()
                errorMessage = error.localizedDescription
            }
        }
    }

    private func formatLastSync(_ date: Date?) -> String {
        guard let date else { return "Not synced yet" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

struct TimerView: View {
    @StateObject private var viewModel: TimerScreenViewModel
    @State private var showTaskSwitcher = false
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(viewModel: TimerScreenViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 20) {
            if let snapshot = viewModel.snapshot {
                Text(snapshot.mode == .work ? "Work" : "Break")
                    .font(.headline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(snapshot.mode == .work ? Color.blue.opacity(0.2) : Color.green.opacity(0.2))
                    .clipShape(Capsule())

                Text(formatMainTimer(snapshot: snapshot))
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit()

                if snapshot.isInExtraTime {
                    Text("+\(formatClock(snapshot.extraSec))")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.orange)
                        .monospacedDigit()
                }

                VStack(spacing: 4) {
                    Text("Current task")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(viewModel.currentTask?.title ?? "No task selected")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                }
            } else {
                Text("No active session")
                    .font(.headline)
            }

            HStack {
                Button("Start") {
                    viewModel.startWorkWithoutTask()
                }
                .buttonStyle(.borderedProminent)

                Button("Stop") {
                    viewModel.stopTimer()
                }
                .buttonStyle(.bordered)
            }

            HStack {
                Button("Break Now") {
                    viewModel.skipToBreak()
                }
                .buttonStyle(.bordered)

                Button("Switch Task") {
                    showTaskSwitcher = true
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.switchableTasks.isEmpty)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Timer")
        .onAppear {
            viewModel.restore()
        }
        .onReceive(ticker) { now in
            viewModel.safeRefresh(now: now)
        }
        .sheet(isPresented: $showTaskSwitcher) {
            NavigationStack {
                List(viewModel.switchableTasks, id: \.id) { task in
                    Button(task.title) {
                        viewModel.switchTask(to: task.id)
                        showTaskSwitcher = false
                    }
                }
                .navigationTitle("Switch Task")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            showTaskSwitcher = false
                        }
                    }
                }
            }
        }
    }

    private func formatMainTimer(snapshot: ActiveTimerSnapshot) -> String {
        if snapshot.isInExtraTime {
            return "00:00"
        }
        return formatClock(max(0, snapshot.remainingSec))
    }

    private func formatClock(_ totalSeconds: Int) -> String {
        let seconds = max(0, totalSeconds)
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}

struct TasksView: View {
    @StateObject private var viewModel: TasksViewModel
    @State private var showCreateTask = false
    @State private var newTitle = ""
    @State private var newNotes = ""
    @State private var newProjectId: UUID?
    @State private var newStatus: TaskStatus = .todo

    init(viewModel: TasksViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        VStack {
            Picker("Filter", selection: $viewModel.filter) {
                ForEach(TaskFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            List(viewModel.filteredTasks, id: \.id) { task in
                VStack(alignment: .leading, spacing: 8) {
                    Text(task.title)
                        .font(.headline)
                    Text(viewModel.projectName(for: task.projectId))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Menu(task.status.rawValue) {
                            ForEach(TaskStatus.allCases, id: \.rawValue) { status in
                                Button(status.rawValue) {
                                    viewModel.updateStatus(for: task, status: status)
                                }
                            }
                        }

                        Spacer()

                        Button("Start") {
                            viewModel.quickStart(task: task)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(task.status == .done)
                    }
                }
                .padding(.vertical, 4)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.footnote)
                    .padding(.bottom)
            }
        }
        .navigationTitle("Tasks")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreateTask = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .onAppear {
            viewModel.load()
        }
        .sheet(isPresented: $showCreateTask) {
            NavigationStack {
                Form {
                    TextField("Title", text: $newTitle)
                    TextField("Notes", text: $newNotes)

                    Picker("Project", selection: $newProjectId) {
                        Text("No Project").tag(UUID?.none)
                        ForEach(viewModel.projects, id: \.id) { project in
                            Text(project.name).tag(Optional(project.id))
                        }
                    }

                    Picker("Status", selection: $newStatus) {
                        ForEach(TaskStatus.allCases, id: \.rawValue) { status in
                            Text(status.rawValue).tag(status)
                        }
                    }
                }
                .navigationTitle("New Task")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showCreateTask = false
                            resetCreateTaskForm()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            viewModel.createTask(
                                title: newTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                                notes: newNotes.isEmpty ? nil : newNotes,
                                projectId: newProjectId,
                                status: newStatus
                            )
                            showCreateTask = false
                            resetCreateTaskForm()
                        }
                        .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    private func resetCreateTaskForm() {
        newTitle = ""
        newNotes = ""
        newProjectId = nil
        newStatus = .todo
    }
}

struct ProjectsView: View {
    @StateObject private var viewModel: ProjectsViewModel
    @State private var showCreateProject = false
    @State private var projectName = ""
    @State private var projectColor = ""

    init(viewModel: ProjectsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        List {
            ForEach(viewModel.projects, id: \.id) { project in
                NavigationLink(project.name) {
                    ProjectTasksView(project: project, tasks: viewModel.tasks(for: project))
                }
            }
            .onDelete(perform: viewModel.deleteProjects)
        }
        .navigationTitle("Projects")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreateProject = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .onAppear {
            viewModel.load()
        }
        .sheet(isPresented: $showCreateProject) {
            NavigationStack {
                Form {
                    TextField("Name", text: $projectName)
                    TextField("Color (optional)", text: $projectColor)
                }
                .navigationTitle("New Project")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showCreateProject = false
                            resetCreateProjectForm()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            viewModel.createProject(
                                name: projectName.trimmingCharacters(in: .whitespacesAndNewlines),
                                color: projectColor.isEmpty ? nil : projectColor
                            )
                            showCreateProject = false
                            resetCreateProjectForm()
                        }
                        .disabled(projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.bottom, 8)
            }
        }
    }

    private func resetCreateProjectForm() {
        projectName = ""
        projectColor = ""
    }
}

struct ProjectTasksView: View {
    let project: Project
    let tasks: [Task]

    var body: some View {
        List(tasks, id: \.id) { task in
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                Text(task.status.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(project.name)
    }
}

struct SettingsView: View {
    @StateObject private var viewModel: SettingsViewModel

    init(viewModel: SettingsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        Form {
            Section("Timer") {
                Stepper(value: $viewModel.workDurationMinutes, in: 1...180) {
                    Text("Work: \(viewModel.workDurationMinutes) min")
                }

                Stepper(value: $viewModel.breakDurationMinutes, in: 1...60) {
                    Text("Break: \(viewModel.breakDurationMinutes) min")
                }

                Button("Save Durations") {
                    viewModel.saveDurations()
                }
            }

            Section("Behavior") {
                Toggle("Auto-start next session", isOn: $viewModel.autoStartNext)
                Button("Apply") {
                    viewModel.saveAutoStartNext()
                }
            }

            SyncStatusView(
                snapshot: viewModel.syncStatus,
                isSyncingNow: viewModel.isSyncingNow,
                onSyncNowTapped: {
                    viewModel.syncNow()
                }
            )

            if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            viewModel.load()
        }
    }
}

struct SyncStatusView: View {
    let snapshot: SyncStatusSnapshot
    let isSyncingNow: Bool
    let onSyncNowTapped: () -> Void

    var body: some View {
        Section("Sync Status") {
            HStack {
                Text("Connectivity")
                Spacer()
                Text(snapshot.isOnlinePlaceholder ? "Online" : "Offline")
                    .foregroundStyle(snapshot.isOnlinePlaceholder ? .green : .orange)
            }

            HStack {
                Text("Pending operations")
                Spacer()
                Text("\(snapshot.pendingOperations)")
            }

            HStack {
                Text("Last sync")
                Spacer()
                Text(snapshot.lastSyncText)
                    .foregroundStyle(.secondary)
            }

            Button(isSyncingNow ? "Syncing..." : "Sync now") {
                onSyncNowTapped()
            }
            .disabled(isSyncingNow)
        }
    }
}

#Preview {
    let previewContainer = try! ModelContainer(
        for: Project.self,
        Task.self,
        TimerSettings.self,
        TimerSession.self,
        TimerState.self,
        TimeEvent.self,
        SyncOperation.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let appContainer = AppContainer(modelContext: previewContainer.mainContext)
    return ContentView(appContainer: appContainer)
}
