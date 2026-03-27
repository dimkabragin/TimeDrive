import SwiftUI

struct CompactProjectsPanel: View {
    @ObservedObject var viewModel: ProjectsViewModel
    @State private var showCreateProject = false
    @State private var projectName = ""
    @State private var projectColor = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Projects")
                    .font(.headline)

                Spacer()

                Button {
                    showCreateProject = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            if viewModel.projects.isEmpty {
                CompactEmptyState(text: "No projects yet")
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.projects, id: \.id) { project in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(project.name)
                                    .font(.subheadline.weight(.semibold))
                                Text("\(viewModel.tasks(for: project).count) tasks")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
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
        .sheet(isPresented: $showCreateProject) {
            ProjectEditorSheet(
                name: $projectName,
                color: $projectColor,
                onCancel: {
                    showCreateProject = false
                    resetCreateProjectForm()
                },
                onSave: {
                    let previousError = viewModel.errorMessage
                    viewModel.createProject(
                        name: projectName.trimmingCharacters(in: .whitespacesAndNewlines),
                        color: projectColor.isEmpty ? nil : projectColor
                    )
                    if viewModel.errorMessage == previousError || viewModel.errorMessage == nil {
                        showCreateProject = false
                        resetCreateProjectForm()
                    }
                }
            )
        }
    }

    private func resetCreateProjectForm() {
        projectName = ""
        projectColor = ""
    }
}
