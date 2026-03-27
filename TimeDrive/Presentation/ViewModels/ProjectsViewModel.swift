import Combine
import Foundation

@MainActor
final class ProjectsViewModel: ObservableObject {
    @Published var projects: [Project] = []
    @Published var tasks: [Task] = []
    @Published var errorMessage: String?

    private let projectRepository: ProjectRepository
    private let taskRepository: TaskRepository

    init(projectRepository: ProjectRepository, taskRepository: TaskRepository) {
        self.projectRepository = projectRepository
        self.taskRepository = taskRepository
    }

    func load() {
        do {
            projects = try projectRepository.fetchAll(includeDeleted: false)
            tasks = try taskRepository.fetchAll(includeDeleted: false)
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

    func tasks(for project: Project) -> [Task] {
        tasks.filter { $0.projectId == project.id }
    }
}
