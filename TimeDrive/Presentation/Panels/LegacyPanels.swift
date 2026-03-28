import SwiftUI

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
            Picker(String(localized: "field.status"), selection: $viewModel.filter) {
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

                        Button(String(localized: "task.start")) {
                            viewModel.quickStart(task: task)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(task.status == .done)
                    }
                }
                .padding(.vertical, 4)
            }

            if let error = viewModel.errorMessage {
                InlineErrorView(message: error)
                    .padding(.bottom)
            }
        }
        .navigationTitle(String(localized: "tasks.title"))
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
            TaskEditorSheet(
                title: $newTitle,
                notes: $newNotes,
                projectId: $newProjectId,
                status: $newStatus,
                titleKey: "editor.task.title.create",
                projects: viewModel.projects,
                onCancel: {
                    showCreateTask = false
                    resetCreateTaskForm()
                },
                onSave: {
                    viewModel.createTask(
                        title: newTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                        notes: newNotes.isEmpty ? nil : newNotes,
                        projectId: newProjectId,
                        status: newStatus
                    )
                    showCreateTask = false
                    resetCreateTaskForm()
                }
            )
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
        .navigationTitle(String(localized: "projects.title"))
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
            ProjectEditorSheet(
                name: $projectName,
                color: $projectColor,
                titleKey: "editor.project.title.create",
                onCancel: {
                    showCreateProject = false
                    resetCreateProjectForm()
                },
                onSave: {
                    viewModel.createProject(
                        name: projectName.trimmingCharacters(in: .whitespacesAndNewlines),
                        color: projectColor.isEmpty ? nil : projectColor
                    )
                    showCreateProject = false
                    resetCreateProjectForm()
                }
            )
        }
        .overlay(alignment: .bottom) {
            if let error = viewModel.errorMessage {
                InlineErrorView(message: error)
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
                    InlineErrorView(message: error)
                }
            }
        }
        .navigationTitle(String(localized: "settings.title"))
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
        Section(String(localized: "settings.sync.section")) {
            HStack {
                Text(String(localized: "sync.connectivity"))
                Spacer()
                Text(snapshot.isOnlinePlaceholder ? String(localized: "sync.online") : String(localized: "sync.offline"))
                    .foregroundStyle(snapshot.isOnlinePlaceholder ? .green : .orange)
            }

            HStack {
                Text(String(localized: "sync.pending"))
                Spacer()
                Text("\(snapshot.pendingOperations)")
            }

            HStack {
                Text(String(localized: "sync.lastSync"))
                Spacer()
                Text(snapshot.lastSyncText)
                    .foregroundStyle(.secondary)
            }

            Button(isSyncingNow ? String(localized: "sync.syncing") : String(localized: "sync.now")) {
                onSyncNowTapped()
            }
            .disabled(isSyncingNow)
        }
    }
}
