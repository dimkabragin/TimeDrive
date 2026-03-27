import Combine
import Foundation

@MainActor
final class TasksViewModel: ObservableObject {
    @Published var tasks: [Task] = []
    @Published var projects: [Project] = []
    @Published var filter: TaskFilter = .all
    @Published var errorMessage: String?

    private let taskRepository: TaskRepository
    private let projectRepository: ProjectRepository
    private let timerUseCases: TimerUseCases

    init(taskRepository: TaskRepository, projectRepository: ProjectRepository, timerUseCases: TimerUseCases) {
        self.taskRepository = taskRepository
        self.projectRepository = projectRepository
        self.timerUseCases = timerUseCases
    }

    var filteredTasks: [Task] {
        switch filter {
        case .all:
            return tasks
        case .todo:
            return tasks.filter { $0.status == .todo }
        case .inProgress:
            return tasks.filter { $0.status == .inProgress }
        case .done:
            return tasks.filter { $0.status == .done }
        }
    }

    func projectName(for projectId: UUID?) -> String {
        guard let projectId,
              let project = projects.first(where: { $0.id == projectId })
        else {
            return "No Project"
        }
        return project.name
    }

    func load() {
        do {
            tasks = try taskRepository.fetchAll(includeDeleted: false)
            projects = try projectRepository.fetchAll(includeDeleted: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createTask(title: String, notes: String?, projectId: UUID?, status: TaskStatus) {
        do {
            let task = try taskRepository.create(title: title, notes: notes, projectId: projectId, estimateMinutes: nil)
            if status != .todo {
                try taskRepository.update(task: task, title: title, notes: notes, status: status, projectId: projectId)
            }
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateStatus(for task: Task, status: TaskStatus) {
        do {
            try taskRepository.update(task: task, title: task.title, notes: task.notes, status: status, projectId: task.projectId)
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func quickStart(task: Task) {
        do {
            _ = try timerUseCases.startWork(taskId: task.id)
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
