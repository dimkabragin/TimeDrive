import Foundation

enum TaskFilter: String, CaseIterable, Identifiable {
    case all
    case todo
    case inProgress
    case done

    var id: Self { self }

    var title: String {
        switch self {
        case .all: return String(localized: "tasks.filter.all")
        case .todo: return String(localized: "tasks.filter.todo")
        case .inProgress: return String(localized: "tasks.filter.inProgress")
        case .done: return String(localized: "tasks.filter.done")
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
            return String(localized: "tasks.title")
        case .projects:
            return String(localized: "projects.title")
        case .settings:
            return String(localized: "settings.title")
        }
    }
}

struct SyncStatusSnapshot {
    let isOnlinePlaceholder: Bool
    let pendingOperations: Int
    let lastSyncText: String
}
