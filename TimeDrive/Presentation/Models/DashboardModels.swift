import Foundation

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

enum DashboardPanel: String, Identifiable, CaseIterable {
    case tasks
    case projects
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .tasks:
            return "Tasks"
        case .projects:
            return "Projects"
        case .settings:
            return "Settings"
        }
    }
}

struct SyncStatusSnapshot {
    let isOnlinePlaceholder: Bool
    let pendingOperations: Int
    let lastSyncText: String
}
