import Foundation

struct ActiveTimerSnapshot {
    let mode: TimerMode
    let taskId: UUID?
    let startedAt: Date
    let plannedDurationSec: Int
    let elapsedSec: Int
    let remainingSec: Int
    let extraSec: Int

    var isInExtraTime: Bool { extraSec > 0 }
}

final class TimerUseCases {
    private let taskRepository: TaskRepository
    private let timerRepository: TimerRepository
    private let settingsRepository: SettingsRepository

    init(taskRepository: TaskRepository, timerRepository: TimerRepository, settingsRepository: SettingsRepository) {
        self.taskRepository = taskRepository
        self.timerRepository = timerRepository
        self.settingsRepository = settingsRepository
    }

    @discardableResult
    func startWork(taskId: UUID?, now: Date = .now) throws -> TimerSession {
        if let active = try timerRepository.activeSession() {
            let reason: TimerEndedReason = active.mode == .work ? .switchedTask : .switchedMode
            try timerRepository.endSession(active, reason: reason, now: now)
            try timerRepository.addEvent(
                sessionId: active.id,
                type: .sessionEnded,
                payloadJson: try encodeSyncPayload(SessionEndedEventPayload(reason: reason)),
                occurredAt: now
            )
        }

        if let taskId, let task = try taskRepository.task(by: taskId), task.status != .done {
            try taskRepository.update(task: task, title: task.title, notes: task.notes, status: .inProgress, projectId: task.projectId)
        }

        let settings = try settingsRepository.getOrCreate()
        let session = try timerRepository.startSession(mode: .work, taskId: taskId, plannedDurationSec: settings.workDurationSec, now: now)
        try timerRepository.setActiveSession(session, now: now)
        try timerRepository.addEvent(
            sessionId: session.id,
            type: .sessionStarted,
            payloadJson: try encodeSyncPayload(SessionStartedEventPayload(mode: .work)),
            occurredAt: now
        )
        return session
    }

    @discardableResult
    func startBreak(now: Date = .now) throws -> TimerSession {
        if let active = try timerRepository.activeSession() {
            try timerRepository.endSession(active, reason: .switchedMode, now: now)
            try timerRepository.addEvent(
                sessionId: active.id,
                type: .modeSwitched,
                payloadJson: try encodeSyncPayload(ModeSwitchedEventPayload(to: .break)),
                occurredAt: now
            )
            try timerRepository.addEvent(
                sessionId: active.id,
                type: .sessionEnded,
                payloadJson: try encodeSyncPayload(SessionEndedEventPayload(reason: .switchedMode)),
                occurredAt: now
            )
        }

        let settings = try settingsRepository.getOrCreate()
        let session = try timerRepository.startSession(mode: .break, taskId: nil, plannedDurationSec: settings.breakDurationSec, now: now)
        try timerRepository.setActiveSession(session, now: now)
        try timerRepository.addEvent(
            sessionId: session.id,
            type: .sessionStarted,
            payloadJson: try encodeSyncPayload(SessionStartedEventPayload(mode: .break)),
            occurredAt: now
        )
        return session
    }

    @discardableResult
    func switchTask(to newTaskId: UUID, now: Date = .now) throws -> TimerSession {
        if let active = try timerRepository.activeSession() {
            try timerRepository.endSession(active, reason: .switchedTask, now: now)
            try timerRepository.addEvent(
                sessionId: active.id,
                type: .taskSwitched,
                payloadJson: try encodeSyncPayload(TaskSwitchedEventPayload(toTaskId: newTaskId)),
                occurredAt: now
            )
            try timerRepository.addEvent(
                sessionId: active.id,
                type: .sessionEnded,
                payloadJson: try encodeSyncPayload(SessionEndedEventPayload(reason: .switchedTask)),
                occurredAt: now
            )
        }
        return try startWork(taskId: newTaskId, now: now)
    }

    func completeTask(taskId: UUID, now: Date = .now) throws {
        _ = try taskRepository.complete(taskId: taskId, at: now)
        if let active = try timerRepository.activeSession(), active.taskId == taskId {
            try timerRepository.endSession(active, reason: .manualStop, now: now)
            try timerRepository.addEvent(
                sessionId: active.id,
                type: .sessionEnded,
                payloadJson: try encodeSyncPayload(SessionEndedEventPayload(reason: .manualStop)),
                occurredAt: now
            )
            try timerRepository.setActiveSession(nil, now: now)
        }
    }

    @discardableResult
    func skipToBreak(now: Date = .now) throws -> TimerSession {
        try startBreak(now: now)
    }

    @discardableResult
    func updateDurations(workDurationSec: Int, breakDurationSec: Int, now: Date = .now) throws -> TimerSettings {
        try settingsRepository.updateDurations(workDurationSec: workDurationSec, breakDurationSec: breakDurationSec, at: now)
    }

    @discardableResult
    func updateAutoStartNext(_ autoStartNext: Bool, now: Date = .now) throws -> TimerSettings {
        try settingsRepository.updateAutoStartNext(autoStartNext, at: now)
    }

    @discardableResult
    func updateAutoUpdatesEnabled(_ autoUpdatesEnabled: Bool, now: Date = .now) throws -> TimerSettings {
        try settingsRepository.updateAutoUpdatesEnabled(autoUpdatesEnabled, at: now)
    }

    func stopActiveSession(now: Date = .now) throws {
        guard let active = try timerRepository.activeSession() else { return }
        try timerRepository.endSession(active, reason: .manualStop, now: now)
        try timerRepository.addEvent(
            sessionId: active.id,
            type: .sessionEnded,
            payloadJson: try encodeSyncPayload(SessionEndedEventPayload(reason: .manualStop)),
            occurredAt: now
        )
        try timerRepository.setActiveSession(nil, now: now)
    }

    func recoverTimerStateOnLaunch(now: Date = .now) throws {
        let state = try timerRepository.getOrCreateState()
        guard state.isRunning else { return }

        guard let activeId = state.activeSessionId,
              let active = try timerRepository.session(by: activeId),
              active.endedAt == nil
        else {
            try timerRepository.setActiveSession(nil, now: now)
            return
        }

        if state.startedAt != active.startedAt || state.plannedDurationSec != active.plannedDurationSec {
            try timerRepository.setActiveSession(active, now: now)
        }
    }

    func activeSnapshot(now: Date = .now) throws -> ActiveTimerSnapshot? {
        guard let active = try timerRepository.activeSession() else { return nil }
        let metrics = active.metrics(at: now)
        let settings = try settingsRepository.getOrCreate()

        if metrics.isInExtraTime, settings.autoStartNext {
            let nextSession: TimerSession
            switch active.mode {
            case .work:
                nextSession = try startBreak(now: now)
            case .break:
                nextSession = try startWork(taskId: nil, now: now)
            }
            return makeSnapshot(for: nextSession, now: now)
        }

        if metrics.isInExtraTime, try !timerRepository.hasThresholdEvent(sessionId: active.id) {
            try timerRepository.addEvent(
                sessionId: active.id,
                type: .thresholdReached,
                payloadJson: try encodeSyncPayload(EmptySyncPayload()),
                occurredAt: now
            )
        }

        return makeSnapshot(for: active, now: now)
    }

    private func makeSnapshot(for session: TimerSession, now: Date) -> ActiveTimerSnapshot {
        let metrics = session.metrics(at: now)
        return ActiveTimerSnapshot(
            mode: session.mode,
            taskId: session.taskId,
            startedAt: session.startedAt,
            plannedDurationSec: session.plannedDurationSec,
            elapsedSec: metrics.elapsedSec,
            remainingSec: metrics.remainingSec,
            extraSec: metrics.extraSec
        )
    }
}
