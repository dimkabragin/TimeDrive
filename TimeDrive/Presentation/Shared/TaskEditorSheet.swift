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
                TextField(String(localized: "field.title"), text: $title)
                TextField(String(localized: "field.notes"), text: $notes)

                Picker(String(localized: "field.project"), selection: $projectId) {
                    Text(String(localized: "tasks.noProject")).tag(UUID?.none)
                    ForEach(projects, id: \.id) { project in
                        Text(project.name).tag(Optional(project.id))
                    }
                }

                Picker(String(localized: "field.status"), selection: $status) {
                    ForEach(TaskStatus.allCases, id: \.rawValue) { taskStatus in
                        Text(taskStatus.rawValue).tag(taskStatus)
                    }
                }
            }
            .navigationTitle(String(localized: "editor.task.title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "action.cancel"), action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "action.save"), action: onSave)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
