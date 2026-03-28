import Combine
import Foundation

@MainActor
final class ProjectsViewModel: ObservableObject {
    @Published var projects: [Project] = []
    @Published var tasks: [Task] = []
    @Published var projectTimeById: [UUID: Int] = [:]
    @Published var errorMessage: String?

    private let projectRepository: ProjectRepository
    private let taskRepository: TaskRepository
    private let timerRepository: TimerRepository

    init(projectRepository: ProjectRepository, taskRepository: TaskRepository, timerRepository: TimerRepository) {
        self.projectRepository = projectRepository
        self.taskRepository = taskRepository
        self.timerRepository = timerRepository
    }

    func load() {
        do {
            projects = try projectRepository.fetchAll(includeDeleted: false)
            tasks = try taskRepository.fetchAll(includeDeleted: false)
            projectTimeById = try calculateProjectTimeById(projects: projects, tasks: tasks)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createProject(name: String, color: String?) {
        do {
            _ = try projectRepository.create(name: name, color: color)
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteProjects(at offsets: IndexSet) {
        do {
            for index in offsets {
                let project = projects[index]
                try projectRepository.softDelete(projectId: project.id)
            }
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateProject(project: Project, name: String, color: String?, isArchived: Bool = false) {
        do {
            try projectRepository.update(project: project, name: name, color: color, isArchived: isArchived)
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteProject(_ project: Project) {
        do {
            try projectRepository.softDelete(projectId: project.id)
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func tasks(for project: Project) -> [Task] {
        tasks.filter { $0.projectId == project.id }
    }

    func projectSpentTime(for project: Project) -> Int {
        projectTimeById[project.id] ?? 0
    }

    func formattedProjectSpentTime(for project: Project) -> String {
        formatDuration(seconds: projectSpentTime(for: project))
    }

    private func calculateProjectTimeById(projects: [Project], tasks: [Task]) throws -> [UUID: Int] {
        var result: [UUID: Int] = [:]
        let taskIdsByProject = Dictionary(grouping: tasks.compactMap { task -> (UUID, UUID)? in
            guard let projectId = task.projectId else { return nil }
            return (projectId, task.id)
        }, by: { $0.0 }).mapValues { pairs in pairs.map { $0.1 } }

        for project in projects {
            guard let taskIds = taskIdsByProject[project.id], !taskIds.isEmpty else {
                result[project.id] = 0
                continue
            }

            let sessions = try timerRepository.sessions(taskIds: taskIds)
            let total = sessions
                .filter { $0.mode == .work }
                .reduce(into: 0) { partial, session in
                    guard let endedAt = session.endedAt else { return }
                    partial += max(0, Int(endedAt.timeIntervalSince(session.startedAt)))
                }

            result[project.id] = total
        }

        return result
    }

    private func formatDuration(seconds: Int) -> String {
        let totalSeconds = max(0, seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60

        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        }
        return String(format: "%dm", minutes)
    }
}
