import SwiftUI

struct DashboardBodyView: View {
    let activePanel: DashboardPanel
    @ObservedObject var tasksViewModel: TasksViewModel
    @ObservedObject var projectsViewModel: ProjectsViewModel
    @ObservedObject var settingsViewModel: SettingsViewModel

    var body: some View {
        Group {
            switch activePanel {
            case .tasks:
                CompactTasksPanel(viewModel: tasksViewModel)
            case .projects:
                CompactProjectsPanel(viewModel: projectsViewModel)
            case .settings:
                CompactSettingsPanel(viewModel: settingsViewModel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

