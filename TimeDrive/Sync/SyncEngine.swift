import Foundation
import SwiftData

@MainActor
final class SyncEngine {
    private let syncRepository: SyncRepository
    private let apiClient: SyncAPIClientProtocol
    private let tokenStore: SyncTokenStoreProtocol
    private let modelContext: ModelContext

    init(
        syncRepository: SyncRepository,
        apiClient: SyncAPIClientProtocol,
        tokenStore: SyncTokenStoreProtocol,
        modelContext: ModelContext
    ) {
        self.syncRepository = syncRepository
        self.apiClient = apiClient
        self.tokenStore = tokenStore
        self.modelContext = modelContext
    }

    func pushPendingOperations(limit: Int = 100) async throws -> SyncPushResponseDTO {
        let operations = try syncRepository.pendingOperations(limit: limit)
        guard !operations.isEmpty else {
            return SyncPushResponseDTO(ackedOperationIds: [], serverToken: nil)
        }

        let operationIDs = operations.map(\.id)
        try syncRepository.markAsSent(operationIDs: operationIDs)

        let request = SyncPushRequestDTO(
            operations: operations.map {
                SyncOperationDTO(
                    operationId: $0.id,
                    entityType: $0.entityType,
                    opType: $0.opType,
                    entityId: $0.entityId,
                    payloadJson: $0.payloadJson,
                    clientTimestamp: $0.clientTimestamp
                )
            }
        )

        do {
            let response = try await apiClient.push(request)
            if !response.ackedOperationIds.isEmpty {
                try syncRepository.markAsAcked(operationIDs: response.ackedOperationIds)
            }

            let unacked = Set(operationIDs).subtracting(Set(response.ackedOperationIds))
            if !unacked.isEmpty {
                try syncRepository.markAsFailed(operationIDs: Array(unacked))
            }
            return response
        } catch {
            try syncRepository.markAsFailed(operationIDs: operationIDs)
            throw error
        }
    }

    func pullDeltas(sinceToken: String?) async throws -> SyncPullResponseDTO {
        try await apiClient.pull(since: sinceToken)
    }

    func applyDeltasTransactionally(_ deltas: [SyncDeltaDTO]) throws {
        for delta in deltas.sorted(by: { $0.updatedAt < $1.updatedAt }) {
            switch delta.entityType {
            case .task:
                try applyTaskDelta(delta)
            case .project:
                try applyProjectDelta(delta)
            case .settings:
                try applySettingsDelta(delta)
            }
        }
        try modelContext.save()
    }

    func updateToken(_ token: String?) {
        guard let token else { return }
        tokenStore.updateToken(token)
    }

    func currentToken() -> String? {
        tokenStore.currentToken()
    }

    func lastSyncAt() -> Date? {
        tokenStore.lastSyncAt()
    }

    func syncNow() async throws {
        var firstError: Error?

        do {
            let pushResponse = try await pushPendingOperations(limit: 100)
            updateToken(pushResponse.serverToken)
        } catch {
            firstError = error
        }

        do {
            let pullResponse = try await pullDeltas(sinceToken: tokenStore.currentToken())
            try applyDeltasTransactionally(pullResponse.deltas)
            updateToken(pullResponse.nextToken)
            tokenStore.setLastSyncAt(.now)
        } catch {
            if firstError == nil {
                firstError = error
            }
        }

        if let firstError {
            throw firstError
        }
    }

    private func applyProjectDelta(_ delta: SyncDeltaDTO) throws {
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == delta.entityId })
        let existing = try modelContext.fetch(descriptor).first

        switch delta.operation {
        case .delete:
            if let existing {
                existing.deletedAt = delta.updatedAt
                existing.updatedAt = delta.updatedAt
            }
        case .upsert:
            let payload = try decodeSyncPayload(delta.payloadJson, as: ProjectSyncPayload.self)
            let project = existing ?? Project(id: delta.entityId, name: payload.name ?? "Untitled", color: payload.color)
            if existing == nil {
                modelContext.insert(project)
            }
            if let name = payload.name {
                project.name = name
            }
            project.color = payload.color
            if let isArchived = payload.isArchived {
                project.isArchived = isArchived
            }
            project.deletedAt = nil
            project.updatedAt = delta.updatedAt
        }
    }

    private func applyTaskDelta(_ delta: SyncDeltaDTO) throws {
        let descriptor = FetchDescriptor<Task>(predicate: #Predicate { $0.id == delta.entityId })
        let existing = try modelContext.fetch(descriptor).first

        switch delta.operation {
        case .delete:
            if let existing {
                existing.deletedAt = delta.updatedAt
                existing.updatedAt = delta.updatedAt
            }
        case .upsert:
            let payload = try decodeSyncPayload(delta.payloadJson, as: TaskSyncPayload.self)
            let task = existing ?? Task(id: delta.entityId, projectId: payload.projectId, title: payload.title ?? "Untitled")
            if existing == nil {
                modelContext.insert(task)
            }

            if let title = payload.title {
                task.title = title
            }
            task.notes = payload.notes
            task.projectId = payload.projectId
            if let estimateMinutes = payload.estimateMinutes {
                task.estimateMinutes = estimateMinutes
            }
            if let statusRaw = payload.status, let status = TaskStatus(rawValue: statusRaw) {
                task.status = status
            }
            task.completedAt = payload.completedAt
            task.deletedAt = payload.deletedAt
            task.updatedAt = delta.updatedAt
        }
    }

    private func applySettingsDelta(_ delta: SyncDeltaDTO) throws {
        let descriptor = FetchDescriptor<TimerSettings>(predicate: #Predicate { $0.id == delta.entityId })
        let existing = try modelContext.fetch(descriptor).first

        guard delta.operation == .upsert else { return }
        let payload = try decodeSyncPayload(delta.payloadJson, as: SettingsSyncPayload.self)
        let settings = existing ?? TimerSettings(id: delta.entityId)
        if existing == nil {
            modelContext.insert(settings)
        }

        if let workDurationSec = payload.workDurationSec {
            settings.workDurationSec = workDurationSec
        }
        if let breakDurationSec = payload.breakDurationSec {
            settings.breakDurationSec = breakDurationSec
        }
        if let autoStartNext = payload.autoStartNext {
            settings.autoStartNext = autoStartNext
        }
        settings.updatedAt = delta.updatedAt
    }
}
