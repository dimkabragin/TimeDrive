import Foundation
import SwiftData

@MainActor
final class AppContainer {
    let projectRepository: ProjectRepository
    let taskRepository: TaskRepository
    let timerRepository: TimerRepository
    let settingsRepository: SettingsRepository
    let syncRepository: SyncRepository
    let syncEngine: SyncEngine
    let timerUseCases: TimerUseCases

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
    }
}
