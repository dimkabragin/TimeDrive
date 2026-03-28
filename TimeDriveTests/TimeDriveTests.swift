import Foundation
import SwiftData
import Testing
@testable import TimeDrive

struct TimeDriveTests {
    @Test
    func timerMetrics_whenInsidePlannedTime_calculatesElapsedRemainingWithoutExtra() {
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let now = Date(timeIntervalSince1970: 1_030)

        let metrics = TimerMetrics(startedAt: startedAt, plannedDurationSec: 60, now: now)

        #expect(metrics.elapsedSec == 30)
        #expect(metrics.remainingSec == 30)
        #expect(metrics.extraSec == 0)
        #expect(metrics.isInExtraTime == false)
    }

    @Test
    func timerMetrics_whenCrossingPlannedBoundary_entersExtraTime() {
        let startedAt = Date(timeIntervalSince1970: 2_000)
        let now = Date(timeIntervalSince1970: 2_130)

        let metrics = TimerMetrics(startedAt: startedAt, plannedDurationSec: 120, now: now)

        #expect(metrics.elapsedSec == 130)
        #expect(metrics.remainingSec == -10)
        #expect(metrics.extraSec == 10)
        #expect(metrics.isInExtraTime == true)
    }

    @Test
    func timerSession_metricsUsesSessionFields() {
        let startedAt = Date(timeIntervalSince1970: 3_000)
        let now = Date(timeIntervalSince1970: 3_061)
        let session = TimerSession(mode: .work, taskId: nil, plannedDurationSec: 60, startedAt: startedAt, createdAt: startedAt, updatedAt: startedAt)

        let metrics = session.metrics(at: now)

        #expect(metrics.elapsedSec == 61)
        #expect(metrics.remainingSec == -1)
        #expect(metrics.extraSec == 1)
        #expect(metrics.isInExtraTime == true)
    }

    @Test
    func startWork_whenNoActiveSession_startsWorkSessionAndActivatesTask() throws {
        let taskRepository = FakeTaskRepository()
        let timerRepository = FakeTimerRepository()
        let settingsRepository = FakeSettingsRepository(workDurationSec: 1500, breakDurationSec: 300)
        let useCases = TimerUseCases(taskRepository: taskRepository, timerRepository: timerRepository, settingsRepository: settingsRepository)

        let taskId = UUID()
        taskRepository.tasks[taskId] = Task(id: taskId, projectId: nil, title: "Task A", notes: nil, status: .todo)
        let now = Date(timeIntervalSince1970: 10_000)

        let started = try useCases.startWork(taskId: taskId, now: now)

        #expect(started.mode == .work)
        #expect(started.taskId == taskId)
        #expect(started.startedAt == now)
        #expect(started.plannedDurationSec == 1500)
        #expect((try timerRepository.activeSession())?.id == started.id)
        #expect(taskRepository.tasks[taskId]?.status == .inProgress)
        #expect(timerRepository.events.contains(where: { $0.sessionId == started.id && $0.type == .sessionStarted }))
    }

    @Test
    func startBreak_whenWorkIsActive_endsWorkAndStartsBreak() throws {
        let taskRepository = FakeTaskRepository()
        let timerRepository = FakeTimerRepository()
        let settingsRepository = FakeSettingsRepository(workDurationSec: 1500, breakDurationSec: 300)
        let useCases = TimerUseCases(taskRepository: taskRepository, timerRepository: timerRepository, settingsRepository: settingsRepository)

        let startWorkAt = Date(timeIntervalSince1970: 20_000)
        let breakAt = Date(timeIntervalSince1970: 20_120)
        let work = try useCases.startWork(taskId: nil, now: startWorkAt)

        let breakSession = try useCases.startBreak(now: breakAt)

        #expect(work.endedAt == breakAt)
        #expect(work.endedReason == .switchedMode)
        #expect(breakSession.mode == .break)
        #expect(breakSession.startedAt == breakAt)
        #expect((try timerRepository.activeSession())?.id == breakSession.id)
        #expect(timerRepository.events.contains(where: { $0.sessionId == work.id && $0.type == .modeSwitched }))
        #expect(timerRepository.events.contains(where: { $0.sessionId == work.id && $0.type == .sessionEnded }))
    }

    @Test
    func switchTask_whenWorkIsActive_stopsPreviousAndStartsNewTaskSession() throws {
        let taskRepository = FakeTaskRepository()
        let timerRepository = FakeTimerRepository()
        let settingsRepository = FakeSettingsRepository(workDurationSec: 1500, breakDurationSec: 300)
        let useCases = TimerUseCases(taskRepository: taskRepository, timerRepository: timerRepository, settingsRepository: settingsRepository)

        let oldTaskId = UUID()
        let newTaskId = UUID()
        taskRepository.tasks[oldTaskId] = Task(id: oldTaskId, projectId: nil, title: "Old", notes: nil, status: .inProgress)
        taskRepository.tasks[newTaskId] = Task(id: newTaskId, projectId: nil, title: "New", notes: nil, status: .todo)

        let workAt = Date(timeIntervalSince1970: 30_000)
        let switchAt = Date(timeIntervalSince1970: 30_400)
        let previous = try useCases.startWork(taskId: oldTaskId, now: workAt)

        let switched = try useCases.switchTask(to: newTaskId, now: switchAt)

        #expect(previous.endedAt == switchAt)
        #expect(previous.endedReason == .switchedTask)
        #expect(switched.mode == .work)
        #expect(switched.taskId == newTaskId)
        #expect(taskRepository.tasks[newTaskId]?.status == .inProgress)
        #expect(timerRepository.events.contains(where: { $0.sessionId == previous.id && $0.type == .taskSwitched }))
        #expect(timerRepository.events.contains(where: { $0.sessionId == previous.id && $0.type == .sessionEnded }))
    }

    @Test
    func skipToBreak_isAliasToStartBreak() throws {
        let taskRepository = FakeTaskRepository()
        let timerRepository = FakeTimerRepository()
        let settingsRepository = FakeSettingsRepository(workDurationSec: 1200, breakDurationSec: 600)
        let useCases = TimerUseCases(taskRepository: taskRepository, timerRepository: timerRepository, settingsRepository: settingsRepository)

        let now = Date(timeIntervalSince1970: 40_000)
        let session = try useCases.skipToBreak(now: now)

        #expect(session.mode == .break)
        #expect(session.plannedDurationSec == 600)
        #expect((try timerRepository.activeSession())?.id == session.id)
    }

    @Test
    func stopActiveSession_endsCurrentSessionAndClearsActiveState() throws {
        let taskRepository = FakeTaskRepository()
        let timerRepository = FakeTimerRepository()
        let settingsRepository = FakeSettingsRepository(workDurationSec: 1500, breakDurationSec: 300)
        let useCases = TimerUseCases(taskRepository: taskRepository, timerRepository: timerRepository, settingsRepository: settingsRepository)

        let startAt = Date(timeIntervalSince1970: 50_000)
        let stopAt = Date(timeIntervalSince1970: 50_050)
        let session = try useCases.startWork(taskId: nil, now: startAt)

        try useCases.stopActiveSession(now: stopAt)

        #expect(session.endedAt == stopAt)
        #expect(session.endedReason == .manualStop)
        #expect(try timerRepository.activeSession() == nil)
        #expect(timerRepository.events.contains(where: { $0.sessionId == session.id && $0.type == .sessionEnded }))
    }

    @MainActor
    @Test
    func timerScreenViewModel_stopAfterWork_selectsBreakWithoutAutoStart() throws {
        let taskRepository = FakeTaskRepository()
        let timerRepository = FakeTimerRepository()
        let settingsRepository = FakeSettingsRepository(workDurationSec: 1500, breakDurationSec: 300)
        let useCases = TimerUseCases(taskRepository: taskRepository, timerRepository: timerRepository, settingsRepository: settingsRepository)
        let viewModel = TimerScreenViewModel(useCases: useCases, taskRepository: taskRepository)

        viewModel.startWorkWithoutTask()
        #expect(viewModel.snapshot?.mode == .work)

        viewModel.stopTimer()

        #expect(viewModel.snapshot == nil)
        #expect(viewModel.selectedMode == .break)
        #expect(try timerRepository.activeSession() == nil)
    }

    @MainActor
    @Test
    func timerScreenViewModel_startSelectedMode_supportsManualBreakAndSwitchBackToWork() {
        let taskRepository = FakeTaskRepository()
        let timerRepository = FakeTimerRepository()
        let settingsRepository = FakeSettingsRepository(workDurationSec: 1500, breakDurationSec: 300)
        let useCases = TimerUseCases(taskRepository: taskRepository, timerRepository: timerRepository, settingsRepository: settingsRepository)
        let viewModel = TimerScreenViewModel(useCases: useCases, taskRepository: taskRepository)

        viewModel.selectMode(.break)
        viewModel.startSelectedMode()
        #expect(viewModel.snapshot?.mode == .break)

        viewModel.stopTimer()
        #expect(viewModel.snapshot == nil)

        viewModel.selectMode(.work)
        viewModel.startSelectedMode()
        #expect(viewModel.snapshot?.mode == .work)
    }

    @MainActor
    @Test
    func syncEngine_pushPendingOperations_marksAckedAndFailedByResponse() async throws {
        let op1 = SyncOperation(id: UUID(), entityType: .task, entityId: UUID(), opType: .create, payloadJson: "{}", clientTimestamp: Date(timeIntervalSince1970: 1), status: .pending, retryCount: 0)
        let op2 = SyncOperation(id: UUID(), entityType: .task, entityId: UUID(), opType: .update, payloadJson: "{}", clientTimestamp: Date(timeIntervalSince1970: 2), status: .pending, retryCount: 0)

        let syncRepository = FakeSyncRepository(operations: [op1, op2])
        let apiClient = FakeSyncAPIClient(pushResponse: SyncPushResponseDTO(ackedOperationIds: [op1.id], serverToken: "token-1"), pullResponse: SyncPullResponseDTO(nextToken: nil, deltas: []))
        let engine = SyncEngine(syncRepository: syncRepository, apiClient: apiClient, tokenStore: FakeSyncTokenStore(), modelContext: makeInMemoryModelContext())

        let response = try await engine.pushPendingOperations(limit: 100)

        #expect(response.ackedOperationIds == [op1.id])
        #expect(syncRepository.operationsById[op1.id]?.status == .acked)
        #expect(syncRepository.operationsById[op2.id]?.status == .failed)
        #expect(syncRepository.operationsById[op2.id]?.retryCount == 1)
    }

    @MainActor
    @Test
    func syncEngine_pushPendingOperations_onPushError_marksAllAsFailed() async {
        struct NetworkError: Error {}

        let op1 = SyncOperation(id: UUID(), entityType: .task, entityId: UUID(), opType: .create, payloadJson: "{}", clientTimestamp: Date(timeIntervalSince1970: 11), status: .pending, retryCount: 0)
        let op2 = SyncOperation(id: UUID(), entityType: .project, entityId: UUID(), opType: .update, payloadJson: "{}", clientTimestamp: Date(timeIntervalSince1970: 12), status: .pending, retryCount: 0)

        let syncRepository = FakeSyncRepository(operations: [op1, op2])
        let apiClient = FakeSyncAPIClient(pushError: NetworkError(), pullResponse: SyncPullResponseDTO(nextToken: nil, deltas: []))
        let engine = SyncEngine(syncRepository: syncRepository, apiClient: apiClient, tokenStore: FakeSyncTokenStore(), modelContext: makeInMemoryModelContext())

        await #expect(throws: NetworkError.self) {
            _ = try await engine.pushPendingOperations(limit: 100)
        }

        #expect(syncRepository.operationsById[op1.id]?.status == .failed)
        #expect(syncRepository.operationsById[op2.id]?.status == .failed)
        #expect(syncRepository.operationsById[op1.id]?.retryCount == 1)
        #expect(syncRepository.operationsById[op2.id]?.retryCount == 1)
    }

    @MainActor
    @Test
    func syncRepository_pendingOperations_includesFailedForRetry() throws {
        let context = makeInMemoryModelContext()
        let repository = SwiftDataSyncRepository(modelContext: context)
        let payload = try encodeSyncPayload(EmptySyncPayload())

        try repository.enqueue(entityType: .task, entityId: UUID(), opType: .create, payloadJson: payload)
        let pendingId = try repository.pendingOperations().first!.id
        try repository.enqueue(entityType: .project, entityId: UUID(), opType: .update, payloadJson: payload)
        let ids = try repository.pendingOperations().map(\.id)
        let failedId = ids.first(where: { $0 != pendingId })!
        try repository.markAsFailed(operationIDs: [failedId])

        let retriable = try repository.pendingOperations().map(\.id)

        #expect(retriable.contains(pendingId))
        #expect(retriable.contains(failedId))
    }

    @MainActor
    @Test
    func repositoryPayloadEncoding_preservesQuotedStrings() throws {
        let context = makeInMemoryModelContext()
        let syncRepository = SwiftDataSyncRepository(modelContext: context)
        let repository = SwiftDataProjectRepository(modelContext: context, syncRepository: syncRepository)
        let name = #"Focus "deep" block"#

        _ = try repository.create(name: name, color: "#ABCDEF")
        let operation = try #require(syncRepository.pendingOperations().first)
        let payload = try decodeSyncPayload(operation.payloadJson, as: ProjectSyncPayload.self)

        #expect(payload.name == name)
        #expect(payload.color == "#ABCDEF")
    }

    @MainActor
    @Test
    func taskRepository_updateWhenReopeningTask_clearsCompletedAt() throws {
        let context = makeInMemoryModelContext()
        let syncRepository = SwiftDataSyncRepository(modelContext: context)
        let repository = SwiftDataTaskRepository(modelContext: context, syncRepository: syncRepository)
        let completedAt = Date(timeIntervalSince1970: 123)
        let task = Task(title: "Reopen me", notes: nil, status: .done, completedAt: completedAt)
        context.insert(task)
        try context.save()

        try repository.update(task: task, title: task.title, notes: task.notes, status: .inProgress, projectId: task.projectId)

        #expect(task.completedAt == nil)
    }

    @MainActor
    @Test
    func syncEngine_applyProjectUpsert_clearsDeletedAt() throws {
        let context = makeInMemoryModelContext()
        let project = Project(
            id: UUID(),
            name: "Archived locally",
            color: nil,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100),
            deletedAt: Date(timeIntervalSince1970: 110)
        )
        context.insert(project)
        try context.save()

        let payload = try encodeSyncPayload(ProjectSyncPayload(name: "Restored", color: "#123456", isArchived: false))
        let delta = SyncDeltaDTO(
            entityType: .project,
            operation: .upsert,
            entityId: project.id,
            payloadJson: payload,
            updatedAt: Date(timeIntervalSince1970: 120)
        )
        let engine = SyncEngine(
            syncRepository: FakeSyncRepository(operations: []),
            apiClient: FakeSyncAPIClient(pullResponse: SyncPullResponseDTO(nextToken: nil, deltas: [])),
            tokenStore: FakeSyncTokenStore(),
            modelContext: context
        )

        try engine.applyDeltasTransactionally([delta])

        #expect(project.name == "Restored")
        #expect(project.color == "#123456")
        #expect(project.deletedAt == nil)
    }

    @Test
    func activeSnapshot_whenAutoStartNextEnabled_switchesToBreakAfterWorkOverrun() throws {
        let taskRepository = FakeTaskRepository()
        let timerRepository = FakeTimerRepository()
        let settingsRepository = FakeSettingsRepository(workDurationSec: 60, breakDurationSec: 300, autoStartNext: true)
        let useCases = TimerUseCases(taskRepository: taskRepository, timerRepository: timerRepository, settingsRepository: settingsRepository)

        let startedAt = Date(timeIntervalSince1970: 70_000)
        _ = try useCases.startWork(taskId: nil, now: startedAt)

        let snapshot = try useCases.activeSnapshot(now: Date(timeIntervalSince1970: 70_061))

        #expect(snapshot?.mode == .break)
        #expect(snapshot?.plannedDurationSec == 300)
        #expect(snapshot?.remainingSec == 300)
    }
}

private final class FakeTaskRepository: TaskRepository {
    var tasks: [UUID: Task] = [:]

    func fetchAll(includeDeleted: Bool) throws -> [Task] {
        Array(tasks.values)
    }

    func task(by id: UUID) throws -> Task? {
        tasks[id]
    }

    func create(title: String, notes: String?, projectId: UUID?, estimateMinutes: Int?) throws -> Task {
        let task = Task(title: title, notes: notes, status: .todo, estimateMinutes: estimateMinutes)
        task.projectId = projectId
        tasks[task.id] = task
        return task
    }

    func update(task: Task, title: String, notes: String?, status: TaskStatus, projectId: UUID?) throws {
        task.title = title
        task.notes = notes
        task.status = status
        task.projectId = projectId
        tasks[task.id] = task
    }

    func complete(taskId: UUID, at now: Date) throws -> Task? {
        guard let task = tasks[taskId] else { return nil }
        task.status = .done
        task.completedAt = now
        task.updatedAt = now
        tasks[taskId] = task
        return task
    }
}

private final class FakeSettingsRepository: SettingsRepository {
    private let settings: TimerSettings

    init(workDurationSec: Int, breakDurationSec: Int, autoStartNext: Bool = false) {
        self.settings = TimerSettings(workDurationSec: workDurationSec, breakDurationSec: breakDurationSec, autoStartNext: autoStartNext)
    }

    func getOrCreate() throws -> TimerSettings {
        settings
    }

    func updateDurations(workDurationSec: Int, breakDurationSec: Int, at now: Date) throws -> TimerSettings {
        settings.workDurationSec = workDurationSec
        settings.breakDurationSec = breakDurationSec
        settings.updatedAt = now
        return settings
    }

    func updateAutoStartNext(_ autoStartNext: Bool, at now: Date) throws -> TimerSettings {
        settings.autoStartNext = autoStartNext
        settings.updatedAt = now
        return settings
    }
}

private struct RecordedEvent {
    let sessionId: UUID
    let type: TimeEventType
    let payloadJson: String
    let occurredAt: Date
}

private final class FakeTimerRepository: TimerRepository {
    private var state = TimerState()
    private(set) var sessions: [UUID: TimerSession] = [:]
    private var thresholdEvents: Set<UUID> = []
    private(set) var events: [RecordedEvent] = []

    func getOrCreateState() throws -> TimerState {
        state
    }

    func activeSession() throws -> TimerSession? {
        guard state.isRunning, let activeId = state.activeSessionId else { return nil }
        guard let session = sessions[activeId], session.endedAt == nil else { return nil }
        return session
    }

    func session(by id: UUID) throws -> TimerSession? {
        sessions[id]
    }

    func startSession(mode: TimerMode, taskId: UUID?, plannedDurationSec: Int, now: Date) throws -> TimerSession {
        let session = TimerSession(mode: mode, taskId: taskId, plannedDurationSec: plannedDurationSec, startedAt: now, createdAt: now, updatedAt: now)
        sessions[session.id] = session
        return session
    }

    func endSession(_ session: TimerSession, reason: TimerEndedReason, now: Date) throws {
        guard session.endedAt == nil else { return }
        session.endedAt = now
        session.endedReason = reason
        session.updatedAt = now
        sessions[session.id] = session
    }

    func setActiveSession(_ session: TimerSession?, now: Date) throws {
        if let session {
            state.isRunning = true
            state.activeSessionId = session.id
            state.activeMode = session.mode
            state.activeTaskId = session.taskId
            state.startedAt = session.startedAt
            state.plannedDurationSec = session.plannedDurationSec
            state.lastTickAt = now
        } else {
            state.isRunning = false
            state.activeSessionId = nil
            state.activeMode = nil
            state.activeTaskId = nil
            state.startedAt = nil
            state.plannedDurationSec = nil
            state.lastTickAt = now
        }
        state.updatedAt = now
    }

    func addEvent(sessionId: UUID, type: TimeEventType, payloadJson: String, occurredAt: Date) throws {
        events.append(RecordedEvent(sessionId: sessionId, type: type, payloadJson: payloadJson, occurredAt: occurredAt))
        if type == .thresholdReached {
            thresholdEvents.insert(sessionId)
        }
    }

    func hasThresholdEvent(sessionId: UUID) throws -> Bool {
        thresholdEvents.contains(sessionId)
    }
}

private final class FakeSyncRepository: SyncRepository {
    private(set) var operationsById: [UUID: SyncOperation] = [:]

    init(operations: [SyncOperation]) {
        self.operationsById = Dictionary(uniqueKeysWithValues: operations.map { ($0.id, $0) })
    }

    func enqueue(entityType: SyncEntityType, entityId: UUID, opType: SyncOperationType, payloadJson: String) throws {
        let operation = SyncOperation(entityType: entityType, entityId: entityId, opType: opType, payloadJson: payloadJson)
        operationsById[operation.id] = operation
    }

    func pendingOperations() throws -> [SyncOperation] {
        try pendingOperations(limit: nil)
    }

    func pendingOperations(limit: Int?) throws -> [SyncOperation] {
        let pending = operationsById.values
            .filter { $0.status == .pending || $0.status == .failed }
            .sorted(by: { $0.clientTimestamp < $1.clientTimestamp })
        if let limit {
            return Array(pending.prefix(limit))
        }
        return pending
    }

    func markAsSent(operationIDs: [UUID]) throws {
        for id in operationIDs {
            operationsById[id]?.status = .sent
        }
    }

    func markAsAcked(operationIDs: [UUID]) throws {
        for id in operationIDs {
            operationsById[id]?.status = .acked
        }
    }

    func markAsFailed(operationIDs: [UUID]) throws {
        for id in operationIDs {
            operationsById[id]?.status = .failed
            operationsById[id]?.retryCount += 1
        }
    }
}

private actor FakeSyncAPIClient: SyncAPIClientProtocol {
    let pushResponse: SyncPushResponseDTO?
    let pullResponse: SyncPullResponseDTO
    let pushError: Error?

    init(pushResponse: SyncPushResponseDTO? = nil, pushError: Error? = nil, pullResponse: SyncPullResponseDTO) {
        self.pushResponse = pushResponse
        self.pushError = pushError
        self.pullResponse = pullResponse
    }

    func push(_ request: SyncPushRequestDTO) async throws -> SyncPushResponseDTO {
        if let pushError {
            throw pushError
        }
        let ackedOperationIds = await MainActor.run {
            request.operations.map(\.operationId)
        }
        return pushResponse ?? SyncPushResponseDTO(ackedOperationIds: ackedOperationIds, serverToken: nil)
    }

    func pull(since token: String?) async throws -> SyncPullResponseDTO {
        pullResponse
    }
}

private final class FakeSyncTokenStore: SyncTokenStoreProtocol {
    private var token: String?
    private var syncDate: Date?

    func currentToken() -> String? {
        token
    }

    func updateToken(_ token: String) {
        self.token = token
    }

    func lastSyncAt() -> Date? {
        syncDate
    }

    func setLastSyncAt(_ date: Date) {
        syncDate = date
    }
}

@MainActor
private func makeInMemoryModelContext() -> ModelContext {
    let schema = Schema([
        Project.self,
        Task.self,
        TimerSettings.self,
        TimerSession.self,
        TimerState.self,
        TimeEvent.self,
        SyncOperation.self,
    ])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [configuration])
    return ModelContext(container)
}
