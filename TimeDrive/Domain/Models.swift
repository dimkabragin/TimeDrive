import Foundation
import SwiftData

enum TaskStatus: String, Codable, CaseIterable {
    case todo
    case inProgress
    case done
}

enum TimerMode: String, Codable, CaseIterable {
    case work
    case `break`
}

enum TimerEndedReason: String, Codable, CaseIterable {
    case manualStop
    case switchedMode
    case switchedTask
    case appTerminationRecovery
}

enum TimeEventType: String, Codable, CaseIterable {
    case sessionStarted
    case thresholdReached
    case modeSwitched
    case taskSwitched
    case sessionEnded
}

enum SyncEntityType: String, Codable, CaseIterable {
    case project
    case task
    case session
    case event
    case settings
    case timerState
}

enum SyncOperationType: String, Codable, CaseIterable {
    case create
    case update
    case delete
}

enum SyncStatus: String, Codable, CaseIterable {
    case pending
    case sent
    case acked
    case failed
}

@Model
final class Project {
    @Attribute(.unique) var id: UUID
    var name: String
    var color: String?
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        color: String? = nil,
        isArchived: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

@Model
final class Task {
    @Attribute(.unique) var id: UUID
    var projectId: UUID?
    var title: String
    var notes: String?
    var status: TaskStatus
    var estimateMinutes: Int?
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        projectId: UUID? = nil,
        title: String,
        notes: String? = nil,
        status: TaskStatus = .todo,
        estimateMinutes: Int? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        completedAt: Date? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.title = title
        self.notes = notes
        self.status = status
        self.estimateMinutes = estimateMinutes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.deletedAt = deletedAt
    }
}

@Model
final class TimerSettings {
    @Attribute(.unique) var id: UUID
    var workDurationSec: Int
    var breakDurationSec: Int
    var autoStartNext: Bool
    var autoUpdatesEnabled: Bool
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        workDurationSec: Int = 25 * 60,
        breakDurationSec: Int = 5 * 60,
        autoStartNext: Bool = false,
        autoUpdatesEnabled: Bool = false,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.workDurationSec = workDurationSec
        self.breakDurationSec = breakDurationSec
        self.autoStartNext = autoStartNext
        self.autoUpdatesEnabled = autoUpdatesEnabled
        self.updatedAt = updatedAt
    }
}

@Model
final class TimerSession {
    @Attribute(.unique) var id: UUID
    var mode: TimerMode
    var taskId: UUID?
    var plannedDurationSec: Int
    var startedAt: Date
    var endedAt: Date?
    var endedReason: TimerEndedReason?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        mode: TimerMode,
        taskId: UUID? = nil,
        plannedDurationSec: Int,
        startedAt: Date = .now,
        endedAt: Date? = nil,
        endedReason: TimerEndedReason? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.mode = mode
        self.taskId = taskId
        self.plannedDurationSec = plannedDurationSec
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.endedReason = endedReason
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func metrics(at now: Date) -> TimerMetrics {
        TimerMetrics(startedAt: startedAt, plannedDurationSec: plannedDurationSec, now: now)
    }
}

struct TimerMetrics: Equatable {
    let elapsedSec: Int
    let remainingSec: Int
    let extraSec: Int

    var isInExtraTime: Bool { remainingSec < 0 }

    init(startedAt: Date, plannedDurationSec: Int, now: Date) {
        let elapsed = max(0, Int(now.timeIntervalSince(startedAt)))
        self.elapsedSec = elapsed
        self.remainingSec = plannedDurationSec - elapsed
        self.extraSec = max(0, elapsed - plannedDurationSec)
    }
}

@Model
final class TimerState {
    @Attribute(.unique) var id: UUID
    var isRunning: Bool
    var activeSessionId: UUID?
    var activeMode: TimerMode?
    var activeTaskId: UUID?
    var startedAt: Date?
    var plannedDurationSec: Int?
    var lastTickAt: Date?
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        isRunning: Bool = false,
        activeSessionId: UUID? = nil,
        activeMode: TimerMode? = nil,
        activeTaskId: UUID? = nil,
        startedAt: Date? = nil,
        plannedDurationSec: Int? = nil,
        lastTickAt: Date? = nil,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.isRunning = isRunning
        self.activeSessionId = activeSessionId
        self.activeMode = activeMode
        self.activeTaskId = activeTaskId
        self.startedAt = startedAt
        self.plannedDurationSec = plannedDurationSec
        self.lastTickAt = lastTickAt
        self.updatedAt = updatedAt
    }
}

@Model
final class TimeEvent {
    @Attribute(.unique) var id: UUID
    var sessionId: UUID
    var type: TimeEventType
    var payloadJson: String
    var occurredAt: Date

    init(
        id: UUID = UUID(),
        sessionId: UUID,
        type: TimeEventType,
        payloadJson: String = "{}",
        occurredAt: Date = .now
    ) {
        self.id = id
        self.sessionId = sessionId
        self.type = type
        self.payloadJson = payloadJson
        self.occurredAt = occurredAt
    }
}

@Model
final class SyncOperation {
    @Attribute(.unique) var id: UUID
    var entityType: SyncEntityType
    var entityId: UUID
    var opType: SyncOperationType
    var payloadJson: String
    var clientTimestamp: Date
    var status: SyncStatus
    var retryCount: Int

    init(
        id: UUID = UUID(),
        entityType: SyncEntityType,
        entityId: UUID,
        opType: SyncOperationType,
        payloadJson: String = "{}",
        clientTimestamp: Date = .now,
        status: SyncStatus = .pending,
        retryCount: Int = 0
    ) {
        self.id = id
        self.entityType = entityType
        self.entityId = entityId
        self.opType = opType
        self.payloadJson = payloadJson
        self.clientTimestamp = clientTimestamp
        self.status = status
        self.retryCount = retryCount
    }
}
