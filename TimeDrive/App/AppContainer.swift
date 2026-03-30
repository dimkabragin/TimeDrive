import Foundation
import Combine
import SwiftData

enum UpdateCheckResult: Equatable {
    case checking
    case upToDate
    case updateAvailable(version: String)
    case unavailable
    case failed(message: String)
}

protocol UpdateService {
    var isAutoUpdateSupported: Bool { get }
    var checkForUpdatesEvents: AnyPublisher<UpdateCheckResult, Never> { get }
    func setAutomaticChecksEnabled(_ isEnabled: Bool)
    func checkForUpdates() async -> UpdateCheckResult
}

final class NoOpUpdateService: UpdateService {
    var isAutoUpdateSupported: Bool { false }
    var checkForUpdatesEvents: AnyPublisher<UpdateCheckResult, Never> { Empty().eraseToAnyPublisher() }

    func setAutomaticChecksEnabled(_ isEnabled: Bool) {}

    func checkForUpdates() async -> UpdateCheckResult {
        .unavailable
    }
}

@MainActor
final class AppContainer {
    let projectRepository: ProjectRepository
    let taskRepository: TaskRepository
    let timerRepository: TimerRepository
    let settingsRepository: SettingsRepository
    let syncRepository: SyncRepository
    let syncEngine: SyncEngine
    let timerUseCases: TimerUseCases
    let updateService: UpdateService

    init(modelContext: ModelContext) {
        let syncRepository = SwiftDataSyncRepository(modelContext: modelContext)
        self.syncRepository = syncRepository
        self.projectRepository = SwiftDataProjectRepository(modelContext: modelContext, syncRepository: syncRepository)
        self.taskRepository = SwiftDataTaskRepository(modelContext: modelContext, syncRepository: syncRepository)
        self.timerRepository = SwiftDataTimerRepository(modelContext: modelContext, syncRepository: syncRepository)
        self.settingsRepository = SwiftDataSettingsRepository(modelContext: modelContext, syncRepository: syncRepository)
        let syncTokenStore = UserDefaultsSyncTokenStore()
        let syncAPIClient = OfflineStubSyncAPIClient()
        self.syncEngine = SyncEngine(
            syncRepository: syncRepository,
            apiClient: syncAPIClient,
            tokenStore: syncTokenStore,
            modelContext: modelContext
        )
        self.timerUseCases = TimerUseCases(taskRepository: taskRepository, timerRepository: timerRepository, settingsRepository: settingsRepository)
        self.updateService = SparkleUpdateService()
        let isAutoUpdatesEnabled = (try? settingsRepository.getOrCreate().autoUpdatesEnabled ?? false) ?? false
        self.updateService.setAutomaticChecksEnabled(isAutoUpdatesEnabled)
    }
}
