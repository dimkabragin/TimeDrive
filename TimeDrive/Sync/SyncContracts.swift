import Foundation

struct SyncOperationDTO: Codable {
    let operationId: UUID
    let entityType: SyncEntityType
    let opType: SyncOperationType
    let entityId: UUID
    let payloadJson: String
    let clientTimestamp: Date
}

struct SyncPushRequestDTO: Codable {
    let operations: [SyncOperationDTO]
}

struct SyncPushResponseDTO: Codable {
    let ackedOperationIds: [UUID]
    let serverToken: String?
}

enum SyncDeltaEntityType: String, Codable {
    case project
    case task
    case settings
}

enum SyncDeltaOperationType: String, Codable {
    case upsert
    case delete
}

struct SyncDeltaDTO: Codable {
    let entityType: SyncDeltaEntityType
    let operation: SyncDeltaOperationType
    let entityId: UUID
    let payloadJson: String
    let updatedAt: Date
}

struct SyncPullResponseDTO: Codable {
    let nextToken: String?
    let deltas: [SyncDeltaDTO]
}

protocol SyncAPIClientProtocol {
    func push(_ request: SyncPushRequestDTO) async throws -> SyncPushResponseDTO
    func pull(since token: String?) async throws -> SyncPullResponseDTO
}

struct EmptySyncPayload: Codable {}

struct ProjectSyncPayload: Codable {
    let name: String?
    let color: String?
    let isArchived: Bool?
}

struct TaskSyncPayload: Codable {
    let title: String?
    let notes: String?
    let status: String?
    let projectId: UUID?
    let estimateMinutes: Int?
    let completedAt: Date?
    let deletedAt: Date?
}

struct SettingsSyncPayload: Codable {
    let workDurationSec: Int?
    let breakDurationSec: Int?
    let autoStartNext: Bool?
    let autoUpdatesEnabled: Bool?
}

struct SessionSyncPayload: Codable {
    let mode: TimerMode?
    let taskId: UUID?
    let plannedDurationSec: Int?
    let endedReason: TimerEndedReason?
}

struct TimerStateSyncPayload: Codable {
    let isRunning: Bool
}

struct SessionStartedEventPayload: Codable {
    let mode: TimerMode
}

struct SessionEndedEventPayload: Codable {
    let reason: TimerEndedReason
}

struct ModeSwitchedEventPayload: Codable {
    let to: TimerMode
}

struct TaskSwitchedEventPayload: Codable {
    let toTaskId: UUID
}

private let syncPayloadEncoder = JSONEncoder()
private let syncPayloadDecoder = JSONDecoder()

func encodeSyncPayload<T: Encodable>(_ payload: T) throws -> String {
    let data = try syncPayloadEncoder.encode(payload)
    guard let json = String(data: data, encoding: .utf8) else {
        throw NSError(domain: "SyncContracts", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to encode payload to UTF-8"])
    }
    return json
}

func decodeSyncPayload<T: Decodable>(_ payloadJson: String, as type: T.Type) throws -> T {
    guard let data = payloadJson.data(using: .utf8) else {
        throw NSError(domain: "SyncContracts", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON payload"])
    }
    return try syncPayloadDecoder.decode(T.self, from: data)
}

actor OfflineStubSyncAPIClient: SyncAPIClientProtocol {
    func push(_ request: SyncPushRequestDTO) async throws -> SyncPushResponseDTO {
        let acked = request.operations.map(\.operationId)
        return SyncPushResponseDTO(
            ackedOperationIds: acked,
            serverToken: "stub-token-\(Int(Date.now.timeIntervalSince1970))"
        )
    }

    func pull(since token: String?) async throws -> SyncPullResponseDTO {
        let nextToken = token ?? "stub-token-\(Int(Date.now.timeIntervalSince1970))"
        return SyncPullResponseDTO(nextToken: nextToken, deltas: [])
    }
}

protocol SyncTokenStoreProtocol {
    func currentToken() -> String?
    func updateToken(_ token: String)
    func lastSyncAt() -> Date?
    func setLastSyncAt(_ date: Date)
}

final class UserDefaultsSyncTokenStore: SyncTokenStoreProtocol {
    private let defaults: UserDefaults
    private let tokenKey: String
    private let lastSyncAtKey: String

    init(
        defaults: UserDefaults = .standard,
        tokenKey: String = "sync.lastToken",
        lastSyncAtKey: String = "sync.lastSyncAt"
    ) {
        self.defaults = defaults
        self.tokenKey = tokenKey
        self.lastSyncAtKey = lastSyncAtKey
    }

    func currentToken() -> String? {
        defaults.string(forKey: tokenKey)
    }

    func updateToken(_ token: String) {
        defaults.set(token, forKey: tokenKey)
    }

    func lastSyncAt() -> Date? {
        defaults.object(forKey: lastSyncAtKey) as? Date
    }

    func setLastSyncAt(_ date: Date) {
        defaults.set(date, forKey: lastSyncAtKey)
    }
}
