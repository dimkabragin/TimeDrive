import Foundation
import SwiftData

protocol SyncRepository {
    func enqueue(entityType: SyncEntityType, entityId: UUID, opType: SyncOperationType, payloadJson: String) throws
    func pendingOperations() throws -> [SyncOperation]
    func pendingOperations(limit: Int?) throws -> [SyncOperation]
    func markAsSent(operationIDs: [UUID]) throws
    func markAsAcked(operationIDs: [UUID]) throws
    func markAsFailed(operationIDs: [UUID]) throws
}

protocol ProjectRepository {
    func fetchAll(includeDeleted: Bool) throws -> [Project]
    func create(name: String, color: String?) throws -> Project
    func update(project: Project, name: String, color: String?, isArchived: Bool) throws
    func softDelete(projectId: UUID) throws
}

protocol TaskRepository {
    func fetchAll(includeDeleted: Bool) throws -> [Task]
    func task(by id: UUID) throws -> Task?
    func create(title: String, notes: String?, projectId: UUID?, estimateMinutes: Int?) throws -> Task
    func update(task: Task, title: String, notes: String?, status: TaskStatus, projectId: UUID?) throws
    func complete(taskId: UUID, at now: Date) throws -> Task?
    func softDelete(taskId: UUID) throws
}

protocol SettingsRepository {
    func getOrCreate() throws -> TimerSettings
    func updateDurations(workDurationSec: Int, breakDurationSec: Int, at now: Date) throws -> TimerSettings
    func updateAutoStartNext(_ autoStartNext: Bool, at now: Date) throws -> TimerSettings
}

protocol TimerRepository {
    func getOrCreateState() throws -> TimerState
    func activeSession() throws -> TimerSession?
    func session(by id: UUID) throws -> TimerSession?
    func startSession(mode: TimerMode, taskId: UUID?, plannedDurationSec: Int, now: Date) throws -> TimerSession
    func endSession(_ session: TimerSession, reason: TimerEndedReason, now: Date) throws
    func setActiveSession(_ session: TimerSession?, now: Date) throws
    func addEvent(sessionId: UUID, type: TimeEventType, payloadJson: String, occurredAt: Date) throws
    func hasThresholdEvent(sessionId: UUID) throws -> Bool
    func sessions(taskIds: [UUID]) throws -> [TimerSession]
}

final class SwiftDataSyncRepository: SyncRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func enqueue(entityType: SyncEntityType, entityId: UUID, opType: SyncOperationType, payloadJson: String) throws {
        let operation = SyncOperation(entityType: entityType, entityId: entityId, opType: opType, payloadJson: payloadJson)
        modelContext.insert(operation)
        try modelContext.save()
    }

    func pendingOperations() throws -> [SyncOperation] {
        try pendingOperations(limit: nil)
    }

    func pendingOperations(limit: Int?) throws -> [SyncOperation] {
        let descriptor = FetchDescriptor<SyncOperation>(
            sortBy: [SortDescriptor(\SyncOperation.clientTimestamp)]
        )
        let retriable = try modelContext.fetch(descriptor).filter {
            $0.status == .pending || $0.status == .failed
        }
        guard let limit else { return retriable }
        return Array(retriable.prefix(limit))
    }

    func markAsSent(operationIDs: [UUID]) throws {
        guard !operationIDs.isEmpty else { return }
        for operationID in operationIDs {
            if let operation = try operation(by: operationID) {
                operation.status = .sent
            }
        }
        try modelContext.save()
    }

    func markAsAcked(operationIDs: [UUID]) throws {
        guard !operationIDs.isEmpty else { return }
        for operationID in operationIDs {
            if let operation = try operation(by: operationID) {
                operation.status = .acked
            }
        }
        try modelContext.save()
    }

    func markAsFailed(operationIDs: [UUID]) throws {
        guard !operationIDs.isEmpty else { return }
        for operationID in operationIDs {
            if let operation = try operation(by: operationID) {
                operation.status = .failed
                operation.retryCount += 1
            }
        }
        try modelContext.save()
    }

    private func operation(by id: UUID) throws -> SyncOperation? {
        let descriptor = FetchDescriptor<SyncOperation>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(descriptor).first
    }
}

final class SwiftDataProjectRepository: ProjectRepository {
    private let modelContext: ModelContext
    private let syncRepository: SyncRepository

    init(modelContext: ModelContext, syncRepository: SyncRepository) {
        self.modelContext = modelContext
        self.syncRepository = syncRepository
    }

    func fetchAll(includeDeleted: Bool = false) throws -> [Project] {
        if includeDeleted {
            return try modelContext.fetch(FetchDescriptor<Project>(sortBy: [SortDescriptor(\Project.updatedAt, order: .reverse)]))
        }
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\Project.updatedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func create(name: String, color: String?) throws -> Project {
        let project = Project(name: name, color: color)
        modelContext.insert(project)
        try modelContext.save()
        let payload = try encodeSyncPayload(ProjectSyncPayload(name: project.name, color: project.color, isArchived: project.isArchived))
        try syncRepository.enqueue(entityType: .project, entityId: project.id, opType: .create, payloadJson: payload)
        return project
    }

    func update(project: Project, name: String, color: String?, isArchived: Bool) throws {
        project.name = name
        project.color = color
        project.isArchived = isArchived
        project.updatedAt = .now
        try modelContext.save()
        let payload = try encodeSyncPayload(ProjectSyncPayload(name: project.name, color: project.color, isArchived: project.isArchived))
        try syncRepository.enqueue(entityType: .project, entityId: project.id, opType: .update, payloadJson: payload)
    }

    func softDelete(projectId: UUID) throws {
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == projectId })
        guard let project = try modelContext.fetch(descriptor).first else { return }
        let now = Date.now
        project.deletedAt = now
        project.updatedAt = now

        let linkedTasksDescriptor = FetchDescriptor<Task>(predicate: #Predicate { $0.projectId == projectId })
        let linkedTasks = try modelContext.fetch(linkedTasksDescriptor)
        for task in linkedTasks {
            task.projectId = nil
            task.updatedAt = now
        }

        try modelContext.save()

        for task in linkedTasks {
            let taskPayload = try encodeSyncPayload(TaskSyncPayload(
                title: task.title,
                notes: task.notes,
                status: task.status.rawValue,
                projectId: task.projectId,
                estimateMinutes: task.estimateMinutes,
                completedAt: task.completedAt,
                deletedAt: task.deletedAt
            ))
            try syncRepository.enqueue(entityType: .task, entityId: task.id, opType: .update, payloadJson: taskPayload)
        }

        let payload = try encodeSyncPayload(EmptySyncPayload())
        try syncRepository.enqueue(entityType: .project, entityId: project.id, opType: .delete, payloadJson: payload)
    }
}

final class SwiftDataTaskRepository: TaskRepository {
    private let modelContext: ModelContext
    private let syncRepository: SyncRepository

    init(modelContext: ModelContext, syncRepository: SyncRepository) {
        self.modelContext = modelContext
        self.syncRepository = syncRepository
    }

    func fetchAll(includeDeleted: Bool = false) throws -> [Task] {
        if includeDeleted {
            return try modelContext.fetch(FetchDescriptor<Task>(sortBy: [SortDescriptor(\Task.updatedAt, order: .reverse)]))
        }
        let descriptor = FetchDescriptor<Task>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\Task.updatedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func task(by id: UUID) throws -> Task? {
        let descriptor = FetchDescriptor<Task>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(descriptor).first
    }

    func create(title: String, notes: String?, projectId: UUID?, estimateMinutes: Int?) throws -> Task {
        let task = Task(title: title, notes: notes, status: .todo, estimateMinutes: estimateMinutes)
        task.projectId = projectId
        modelContext.insert(task)
        try modelContext.save()
        let payload = try encodeSyncPayload(TaskSyncPayload(
            title: task.title,
            notes: task.notes,
            status: task.status.rawValue,
            projectId: task.projectId,
            estimateMinutes: task.estimateMinutes,
            completedAt: task.completedAt,
            deletedAt: task.deletedAt
        ))
        try syncRepository.enqueue(entityType: .task, entityId: task.id, opType: .create, payloadJson: payload)
        return task
    }

    func update(task: Task, title: String, notes: String?, status: TaskStatus, projectId: UUID?) throws {
        task.title = title
        task.notes = notes
        task.status = status
        task.projectId = projectId
        task.updatedAt = .now
        if status == .done, task.completedAt == nil {
            task.completedAt = .now
        } else if status != .done {
            task.completedAt = nil
        }
        try modelContext.save()
        let payload = try encodeSyncPayload(TaskSyncPayload(
            title: task.title,
            notes: task.notes,
            status: task.status.rawValue,
            projectId: task.projectId,
            estimateMinutes: task.estimateMinutes,
            completedAt: task.completedAt,
            deletedAt: task.deletedAt
        ))
        try syncRepository.enqueue(entityType: .task, entityId: task.id, opType: .update, payloadJson: payload)
    }

    func complete(taskId: UUID, at now: Date) throws -> Task? {
        guard let task = try task(by: taskId) else { return nil }
        task.status = .done
        task.completedAt = now
        task.updatedAt = now
        try modelContext.save()
        let payload = try encodeSyncPayload(TaskSyncPayload(
            title: task.title,
            notes: task.notes,
            status: task.status.rawValue,
            projectId: task.projectId,
            estimateMinutes: task.estimateMinutes,
            completedAt: task.completedAt,
            deletedAt: task.deletedAt
        ))
        try syncRepository.enqueue(entityType: .task, entityId: task.id, opType: .update, payloadJson: payload)
        return task
    }

    func softDelete(taskId: UUID) throws {
        guard let task = try task(by: taskId) else { return }
        let now = Date.now
        task.deletedAt = now
        task.updatedAt = now
        try modelContext.save()
        let payload = try encodeSyncPayload(TaskSyncPayload(
            title: task.title,
            notes: task.notes,
            status: task.status.rawValue,
            projectId: task.projectId,
            estimateMinutes: task.estimateMinutes,
            completedAt: task.completedAt,
            deletedAt: task.deletedAt
        ))
        try syncRepository.enqueue(entityType: .task, entityId: task.id, opType: .delete, payloadJson: payload)
    }
}

final class SwiftDataSettingsRepository: SettingsRepository {
    private let modelContext: ModelContext
    private let syncRepository: SyncRepository

    init(modelContext: ModelContext, syncRepository: SyncRepository) {
        self.modelContext = modelContext
        self.syncRepository = syncRepository
    }

    func getOrCreate() throws -> TimerSettings {
        let descriptor = FetchDescriptor<TimerSettings>()
        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }
        let settings = TimerSettings()
        modelContext.insert(settings)
        try modelContext.save()
        let payload = try encodeSyncPayload(SettingsSyncPayload(
            workDurationSec: settings.workDurationSec,
            breakDurationSec: settings.breakDurationSec,
            autoStartNext: settings.autoStartNext
        ))
        try syncRepository.enqueue(entityType: .settings, entityId: settings.id, opType: .create, payloadJson: payload)
        return settings
    }

    func updateDurations(workDurationSec: Int, breakDurationSec: Int, at now: Date = .now) throws -> TimerSettings {
        let settings = try getOrCreate()
        settings.workDurationSec = workDurationSec
        settings.breakDurationSec = breakDurationSec
        settings.updatedAt = now
        try modelContext.save()
        let payload = try encodeSyncPayload(SettingsSyncPayload(
            workDurationSec: settings.workDurationSec,
            breakDurationSec: settings.breakDurationSec,
            autoStartNext: settings.autoStartNext
        ))
        try syncRepository.enqueue(entityType: .settings, entityId: settings.id, opType: .update, payloadJson: payload)
        return settings
    }

    func updateAutoStartNext(_ autoStartNext: Bool, at now: Date = .now) throws -> TimerSettings {
        let settings = try getOrCreate()
        settings.autoStartNext = autoStartNext
        settings.updatedAt = now
        try modelContext.save()
        let payload = try encodeSyncPayload(SettingsSyncPayload(
            workDurationSec: settings.workDurationSec,
            breakDurationSec: settings.breakDurationSec,
            autoStartNext: settings.autoStartNext
        ))
        try syncRepository.enqueue(entityType: .settings, entityId: settings.id, opType: .update, payloadJson: payload)
        return settings
    }
}

final class SwiftDataTimerRepository: TimerRepository {
    private let modelContext: ModelContext
    private let syncRepository: SyncRepository

    init(modelContext: ModelContext, syncRepository: SyncRepository) {
        self.modelContext = modelContext
        self.syncRepository = syncRepository
    }

    func getOrCreateState() throws -> TimerState {
        let descriptor = FetchDescriptor<TimerState>()
        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }
        let state = TimerState()
        modelContext.insert(state)
        try modelContext.save()
        let payload = try encodeSyncPayload(TimerStateSyncPayload(isRunning: state.isRunning))
        try syncRepository.enqueue(entityType: .timerState, entityId: state.id, opType: .create, payloadJson: payload)
        return state
    }

    func activeSession() throws -> TimerSession? {
        let state = try getOrCreateState()
        guard state.isRunning, let activeId = state.activeSessionId else { return nil }
        guard let session = try session(by: activeId), session.endedAt == nil else {
            return nil
        }
        return session
    }

    func session(by id: UUID) throws -> TimerSession? {
        let descriptor = FetchDescriptor<TimerSession>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(descriptor).first
    }

    func startSession(mode: TimerMode, taskId: UUID?, plannedDurationSec: Int, now: Date = .now) throws -> TimerSession {
        let session = TimerSession(mode: mode, taskId: taskId, plannedDurationSec: plannedDurationSec, startedAt: now, createdAt: now, updatedAt: now)
        modelContext.insert(session)
        try modelContext.save()
        let payload = try encodeSyncPayload(SessionSyncPayload(
            mode: session.mode,
            taskId: session.taskId,
            plannedDurationSec: session.plannedDurationSec,
            endedReason: session.endedReason
        ))
        try syncRepository.enqueue(entityType: .session, entityId: session.id, opType: .create, payloadJson: payload)
        return session
    }

    func endSession(_ session: TimerSession, reason: TimerEndedReason, now: Date = .now) throws {
        guard session.endedAt == nil else { return }
        session.endedAt = now
        session.endedReason = reason
        session.updatedAt = now
        try modelContext.save()
        let payload = try encodeSyncPayload(SessionSyncPayload(
            mode: session.mode,
            taskId: session.taskId,
            plannedDurationSec: session.plannedDurationSec,
            endedReason: session.endedReason
        ))
        try syncRepository.enqueue(entityType: .session, entityId: session.id, opType: .update, payloadJson: payload)
    }

    func setActiveSession(_ session: TimerSession?, now: Date = .now) throws {
        let state = try getOrCreateState()
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
        try modelContext.save()
        let payload = try encodeSyncPayload(TimerStateSyncPayload(isRunning: state.isRunning))
        try syncRepository.enqueue(entityType: .timerState, entityId: state.id, opType: .update, payloadJson: payload)
    }

    func addEvent(sessionId: UUID, type: TimeEventType, payloadJson: String = "{}", occurredAt: Date = .now) throws {
        let event = TimeEvent(sessionId: sessionId, type: type, payloadJson: payloadJson, occurredAt: occurredAt)
        modelContext.insert(event)
        try modelContext.save()
        try syncRepository.enqueue(entityType: .event, entityId: event.id, opType: .create, payloadJson: payloadJson)
    }

    func hasThresholdEvent(sessionId: UUID) throws -> Bool {
        let descriptor = FetchDescriptor<TimeEvent>(predicate: #Predicate { $0.sessionId == sessionId })
        return try modelContext.fetch(descriptor).contains { $0.type == .thresholdReached }
    }

    func sessions(taskIds: [UUID]) throws -> [TimerSession] {
        guard !taskIds.isEmpty else { return [] }
        let descriptor = FetchDescriptor<TimerSession>(sortBy: [SortDescriptor(\TimerSession.startedAt)])
        let sessions = try modelContext.fetch(descriptor)
        let taskIdSet = Set(taskIds)
        return sessions.filter { session in
            guard let taskId = session.taskId else { return false }
            return taskIdSet.contains(taskId)
        }
    }
}
