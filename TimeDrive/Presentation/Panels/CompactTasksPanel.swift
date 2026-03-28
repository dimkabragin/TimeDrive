import SwiftUI

struct CompactTasksPanel: View {
    @ObservedObject var viewModel: TasksViewModel
    @State private var showTaskEditor = false
    @State private var newTitle = ""
    @State private var newNotes = ""
    @State private var newProjectId: UUID?
    @State private var newStatus: TaskStatus = .todo
    @State private var editingTask: Task?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(String(localized: "tasks.title"))
                    .font(.headline)

                Spacer()

                Menu {
                    ForEach(TaskFilter.allCases) { filter in
                        Button(filter.title) {
                            viewModel.filter = filter
                        }
                    }
                } label: {
                    Label(viewModel.filter.title, systemImage: "line.3.horizontal.decrease.circle")
                }
                .menuStyle(.borderlessButton)

                Button {
                    openCreateTask()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            if viewModel.filteredTasks.isEmpty {
                CompactEmptyState(text: String(localized: "tasks.empty"))
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.filteredTasks, id: \.id) { task in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .top, spacing: 8) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(task.title)
                                            .font(.subheadline.weight(.semibold))
                                            .lineLimit(2)
                                        Text(viewModel.projectName(for: task.projectId))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }

                                    Spacer(minLength: 0)

                                    Button {
                                        viewModel.quickStart(task: task)
                                    } label: {
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 12, weight: .bold))
                                            .frame(width: 30, height: 30)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                    .disabled(task.status == .done)
                                    .accessibilityLabel(String(localized: "task.start"))
                                    .accessibilityHint(task.status == .done ? String(localized: "task.startHint.completed") : String(localized: "task.startHint.active"))
                                }

                                HStack {
                                    Menu(task.status.rawValue) {
                                        ForEach(TaskStatus.allCases, id: \.rawValue) { status in
                                            Button(status.rawValue) {
                                                viewModel.updateStatus(for: task, status: status)
                                            }
                                        }
                                    }
                                    .menuStyle(.borderlessButton)

                                    Spacer()
                                }
                            }
                            .padding(12)
                            .background(Color.primary.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .contextMenu {
                                Button(String(localized: "action.edit")) {
                                    openEditTask(task)
                                }
                                Button(String(localized: "action.delete"), role: .destructive) {
                                    viewModel.deleteTask(task)
                                }
                            }
                        }
                    }
                }
            }

            if let error = viewModel.errorMessage {
                InlineErrorView(message: error)
            }
        }
        .sheet(isPresented: $showTaskEditor) {
            TaskEditorSheet(
                title: $newTitle,
                notes: $newNotes,
                projectId: $newProjectId,
                status: $newStatus,
                titleKey: editingTask == nil ? "editor.task.title.create" : "editor.task.title.edit",
                projects: viewModel.projects,
                onCancel: {
                    closeTaskEditor()
                },
                onSave: {
                    let previousError = viewModel.errorMessage
                    let trimmedTitle = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    let normalizedNotes = newNotes.isEmpty ? nil : newNotes

                    if let editingTask {
                        viewModel.updateTask(
                            task: editingTask,
                            title: trimmedTitle,
                            notes: normalizedNotes,
                            status: newStatus,
                            projectId: newProjectId
                        )
                    } else {
                        viewModel.createTask(
                            title: trimmedTitle,
                            notes: normalizedNotes,
                            projectId: newProjectId,
                            status: newStatus
                        )
                    }

                    if viewModel.errorMessage == previousError || viewModel.errorMessage == nil {
                        closeTaskEditor()
                    }
                }
            )
        }
    }

    private func openCreateTask() {
        editingTask = nil
        resetCreateTaskForm()
        showTaskEditor = true
    }

    private func openEditTask(_ task: Task) {
        editingTask = task
        newTitle = task.title
        newNotes = task.notes ?? ""
        newProjectId = task.projectId
        newStatus = task.status
        showTaskEditor = true
    }

    private func closeTaskEditor() {
        showTaskEditor = false
        editingTask = nil
        resetCreateTaskForm()
    }

    private func resetCreateTaskForm() {
        newTitle = ""
        newNotes = ""
        newProjectId = nil
        newStatus = .todo
    }
}
