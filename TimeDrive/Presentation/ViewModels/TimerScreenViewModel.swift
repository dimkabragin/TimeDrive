import Combine
import Foundation

@MainActor
final class TimerScreenViewModel: ObservableObject {
    @Published var snapshot: ActiveTimerSnapshot?
    @Published var currentTask: Task?
    @Published var switchableTasks: [Task] = []
    @Published var errorMessage: String?

    private let useCases: TimerUseCases
    private let taskRepository: TaskRepository

    init(useCases: TimerUseCases, taskRepository: TaskRepository) {
        self.useCases = useCases
        self.taskRepository = taskRepository
    }

    func restore() {
        do {
            try useCases.recoverTimerStateOnLaunch()
            try refresh()
            try reloadTasks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh(now: Date = .now) throws {
        snapshot = try useCases.activeSnapshot(now: now)
        if let taskId = snapshot?.taskId {
            currentTask = try taskRepository.task(by: taskId)
        } else {
            currentTask = nil
        }
    }

    func safeRefresh(now: Date = .now) {
        do {
            try refresh(now: now)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reloadTasks() throws {
        switchableTasks = try taskRepository.fetchAll(includeDeleted: false)
            .filter { $0.status != .done }
    }

    func startWorkWithoutTask() {
        do {
            _ = try useCases.startWork(taskId: nil)
            try refresh()
            try reloadTasks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopTimer() {
        do {
            try useCases.stopActiveSession()
            try refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func skipToBreak() {
        do {
            _ = try useCases.skipToBreak()
            try refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func switchTask(to taskId: UUID) {
        do {
            _ = try useCases.switchTask(to: taskId)
            try refresh()
            try reloadTasks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
