import SwiftUI

struct TaskEditorSheet: View {
    @Binding var title: String
    @Binding var notes: String
    @Binding var projectId: UUID?
    @Binding var status: TaskStatus

    let projects: [Project]
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                TextField("Notes", text: $notes)

                Picker("Project", selection: $projectId) {
                    Text("No Project").tag(UUID?.none)
                    ForEach(projects, id: \.id) { project in
                        Text(project.name).tag(Optional(project.id))
                    }
                }

                Picker("Status", selection: $status) {
                    ForEach(TaskStatus.allCases, id: \.rawValue) { taskStatus in
                        Text(taskStatus.rawValue).tag(taskStatus)
                    }
                }
            }
            .navigationTitle("New Task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: onSave)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
