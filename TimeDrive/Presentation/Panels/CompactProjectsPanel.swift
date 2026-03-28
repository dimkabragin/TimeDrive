import SwiftUI

struct CompactProjectsPanel: View {
    @ObservedObject var viewModel: ProjectsViewModel
    @State private var showProjectEditor = false
    @State private var projectName = ""
    @State private var projectColor = ""
    @State private var editingProject: Project?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(String(localized: "projects.title"))
                    .font(.headline)

                Spacer()

                Button {
                    openCreateProject()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            if viewModel.projects.isEmpty {
                CompactEmptyState(text: String(localized: "projects.empty"))
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.projects, id: \.id) { project in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(project.name)
                                    .font(.subheadline.weight(.semibold))

                                let tasksCount = viewModel.tasks(for: project).count
                                let spentTime = viewModel.formattedProjectSpentTime(for: project)
                                Text(String(
                                    format: String(localized: "projects.statsFormat"),
                                    tasksCount,
                                    spentTime
                                ))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color.primary.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .contextMenu {
                                Button(String(localized: "action.edit")) {
                                    openEditProject(project)
                                }
                                Button(String(localized: "action.delete"), role: .destructive) {
                                    viewModel.deleteProject(project)
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
        .sheet(isPresented: $showProjectEditor) {
            ProjectEditorSheet(
                name: $projectName,
                color: $projectColor,
                titleKey: editingProject == nil ? "editor.project.title.create" : "editor.project.title.edit",
                onCancel: {
                    closeProjectEditor()
                },
                onSave: {
                    let previousError = viewModel.errorMessage
                    let trimmedName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)

                    if let editingProject {
                        viewModel.updateProject(
                            project: editingProject,
                            name: trimmedName,
                            color: projectColor.isEmpty ? nil : projectColor,
                            isArchived: editingProject.isArchived
                        )
                    } else {
                        viewModel.createProject(
                            name: trimmedName,
                            color: projectColor.isEmpty ? nil : projectColor
                        )
                    }

                    if viewModel.errorMessage == previousError || viewModel.errorMessage == nil {
                        closeProjectEditor()
                    }
                }
            )
        }
    }

    private func openCreateProject() {
        editingProject = nil
        projectName = ""
        projectColor = ""
        showProjectEditor = true
    }

    private func openEditProject(_ project: Project) {
        editingProject = project
        projectName = project.name
        projectColor = project.color ?? ""
        showProjectEditor = true
    }

    private func closeProjectEditor() {
        showProjectEditor = false
        resetCreateProjectForm()
    }

    private func resetCreateProjectForm() {
        editingProject = nil
        projectName = ""
        projectColor = ""
    }
}
