import Foundation
import Combine

#if os(macOS) && canImport(Sparkle)
import Sparkle
#endif

private enum SparkleConfig {
    static let appcastURLKey = "SUFeedURL"
    static let publicEDKeyKey = "SUPublicEDKey"
}

@MainActor
final class SparkleUpdateService: UpdateService {
    private enum Availability {
#if os(macOS) && canImport(Sparkle)
        case available(controller: SPUStandardUpdaterController)
#endif
        case misconfigured(message: String)
        case unsupported
    }

    private let availability: Availability
    private let checkForUpdatesSubject = PassthroughSubject<UpdateCheckResult, Never>()
#if os(macOS) && canImport(Sparkle)
    private var delegateProxy: SparkleDelegateProxy?
#endif

    var checkForUpdatesEvents: AnyPublisher<UpdateCheckResult, Never> {
        checkForUpdatesSubject.eraseToAnyPublisher()
    }

    var isAutoUpdateSupported: Bool {
        if case .available = availability {
            return true
        }
        return false
    }

    convenience init(bundle: Bundle = .main) {
        self.init(infoValueProvider: { key in
            bundle.object(forInfoDictionaryKey: key)
        })
    }

    init(infoValueProvider: (String) -> Any?) {
        guard let configuration = Self.readConfiguration(infoValueProvider: infoValueProvider) else {
            availability = .misconfigured(message: "Missing Sparkle appcast URL or public key in app configuration")
            return
        }

        guard configuration.appcastURL.scheme?.lowercased() == "https" else {
            availability = .misconfigured(message: "Sparkle appcast URL must use HTTPS")
            return
        }

#if os(macOS) && canImport(Sparkle)
        let delegateProxy = SparkleDelegateProxy(subject: checkForUpdatesSubject)
        self.delegateProxy = delegateProxy
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: delegateProxy,
            userDriverDelegate: nil
        )
        availability = .available(controller: controller)
#else
        availability = .unsupported
#endif
    }

    func setAutomaticChecksEnabled(_ isEnabled: Bool) {
#if os(macOS) && canImport(Sparkle)
        guard case .available(let controller) = availability else { return }
        controller.updater.automaticallyChecksForUpdates = isEnabled
#endif
    }

    func checkForUpdates() async -> UpdateCheckResult {
#if os(macOS) && canImport(Sparkle)
        guard case .available(let controller) = availability else {
            if case .misconfigured(let message) = availability {
                checkForUpdatesSubject.send(.failed(message: message))
                return .failed(message: message)
            }
            checkForUpdatesSubject.send(.unavailable)
            return .unavailable
        }

        controller.checkForUpdates(nil)
        return .checking
#else
        if case .misconfigured(let message) = availability {
            return .failed(message: message)
        }
        return .unavailable
#endif
    }

    private static func readConfiguration(infoValueProvider: (String) -> Any?) -> (appcastURL: URL, publicKey: String)? {
        guard
            let appcastURLValue = infoValueProvider(SparkleConfig.appcastURLKey) as? String,
            !appcastURLValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let appcastURL = URL(string: appcastURLValue),
            let publicKeyValue = infoValueProvider(SparkleConfig.publicEDKeyKey) as? String,
            !publicKeyValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        return (appcastURL: appcastURL, publicKey: publicKeyValue)
    }
}

#if os(macOS) && canImport(Sparkle)
private final class SparkleDelegateProxy: NSObject, SPUUpdaterDelegate {
    private let subject: PassthroughSubject<UpdateCheckResult, Never>

    init(subject: PassthroughSubject<UpdateCheckResult, Never>) {
        self.subject = subject
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let displayVersion = item.displayVersionString.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackVersion = item.versionString.trimmingCharacters(in: .whitespacesAndNewlines)
        let version = displayVersion.isEmpty ? fallbackVersion : displayVersion
        subject.send(.updateAvailable(version: version))
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        subject.send(.upToDate)
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        subject.send(.failed(message: error.localizedDescription))
    }
}
#endif
