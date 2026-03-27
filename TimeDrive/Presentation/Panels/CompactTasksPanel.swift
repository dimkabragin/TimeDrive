import SwiftUI

struct CompactTasksPanel: View {
    @ObservedObject var viewModel: TasksViewModel
    @State private var showCreateTask = false
    @State private var newTitle = ""
    @State private var newNotes = ""
    @State private var newProjectId: UUID?
    @State private var newStatus: TaskStatus = .todo

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Tasks")
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
                    showCreateTask = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            if viewModel.filteredTasks.isEmpty {
                CompactEmptyState(text: "No tasks yet")
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
                        }
                    }
                }
            }

            if let error = viewModel.errorMessage {
                InlineErrorView(message: error)
            }
        }
        .sheet(isPresented: $showCreateTask) {
            TaskEditorSheet(
                title: $newTitle,
                notes: $newNotes,
                projectId: $newProjectId,
                status: $newStatus,
                projects: viewModel.projects,
                onCancel: {
                    showCreateTask = false
                    resetCreateTaskForm()
                },
                onSave: {
                    let previousError = viewModel.errorMessage
                    viewModel.createTask(
                        title: newTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                        notes: newNotes.isEmpty ? nil : newNotes,
                        projectId: newProjectId,
                        status: newStatus
                    )
                    if viewModel.errorMessage == previousError || viewModel.errorMessage == nil {
                        showCreateTask = false
                        resetCreateTaskForm()
                    }
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
