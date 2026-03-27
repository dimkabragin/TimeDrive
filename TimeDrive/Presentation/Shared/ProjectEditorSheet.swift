import SwiftUI

struct ProjectEditorSheet: View {
    @Binding var name: String
    @Binding var color: String

    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField(String(localized: "field.name"), text: $name)
                TextField(String(localized: "field.colorOptional"), text: $color)
            }
            .navigationTitle(String(localized: "editor.project.title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "action.cancel"), action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "action.save"), action: onSave)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
