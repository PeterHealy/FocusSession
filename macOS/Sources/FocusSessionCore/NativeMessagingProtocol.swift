import Foundation

public enum NativeMessageRequestType: String, Codable, Sendable {
    case getState
    case startBreak
    case extendBreak
    case recordBlockedAttempt
    case recordDomainActivity
    case importHistorySummary
}

public struct NativeMessageRequest: Codable, Equatable, Sendable {
    public var type: NativeMessageRequestType
    public var service: String?
    public var domain: String?
    public var attemptCount: Int?
    public var activeSeconds: TimeInterval?
    public var visitCount: Int?
    public var sessionID: UUID?
    public var wasOnBreak: Bool?
    public var historyEnabledAtObservation: Bool?
    public var historySummary: [HistorySummaryEntry]?

    public init(
        type: NativeMessageRequestType,
        service: String? = nil,
        domain: String? = nil,
        attemptCount: Int? = nil,
        activeSeconds: TimeInterval? = nil,
        visitCount: Int? = nil,
        sessionID: UUID? = nil,
        wasOnBreak: Bool? = nil,
        historyEnabledAtObservation: Bool? = nil,
        historySummary: [HistorySummaryEntry]? = nil
    ) {
        self.type = type
        self.service = service
        self.domain = domain
        self.attemptCount = attemptCount
        self.activeSeconds = activeSeconds
        self.visitCount = visitCount
        self.sessionID = sessionID
        self.wasOnBreak = wasOnBreak
        self.historyEnabledAtObservation = historyEnabledAtObservation
        self.historySummary = historySummary
    }
}

public struct NativeMessageErrorPayload: Codable, Equatable, Sendable {
    public var code: String
    public var message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

public struct NativeMessageResponse: Codable, Equatable, Sendable {
    public var ok: Bool
    public var state: PublicSessionState
    public var error: NativeMessageErrorPayload?

    public init(
        ok: Bool,
        state: PublicSessionState,
        error: NativeMessageErrorPayload? = nil
    ) {
        self.ok = ok
        self.state = state
        self.error = error
    }
}

public final class NativeMessageProcessor {
    private let service: SessionService

    public init(service: SessionService) {
        self.service = service
    }

    public func process(
        _ request: NativeMessageRequest,
        now: Date = Date()
    ) -> NativeMessageResponse {
        do {
            var resultingState: PublicSessionState?
            switch request.type {
            case .getState:
                break
            case .startBreak:
                resultingState = try service.startBreak(now: now)
            case .extendBreak:
                resultingState = try service.extendBreak(now: now)
            case .recordBlockedAttempt:
                guard let serviceName = request.service else {
                    throw NativeMessageProtocolError.missingField("service")
                }
                try service.recordBlockedAttempt(
                    service: serviceName,
                    count: min(max(request.attemptCount ?? 1, 1), 10_000),
                    sessionID: request.sessionID,
                    wasOnBreak: request.wasOnBreak,
                    historyEnabledAtObservation:
                        request.historyEnabledAtObservation,
                    now: now
                )
            case .recordDomainActivity:
                guard let domain = request.domain else {
                    throw NativeMessageProtocolError.missingField("domain")
                }
                try service.recordDomainActivity(
                    domain: domain,
                    activeSeconds: request.activeSeconds ?? 0,
                    visitCount: request.visitCount ?? 0,
                    sessionID: request.sessionID,
                    wasOnBreak: request.wasOnBreak,
                    historyEnabledAtObservation:
                        request.historyEnabledAtObservation,
                    now: now
                )
            case .importHistorySummary:
                guard let entries = request.historySummary else {
                    throw NativeMessageProtocolError.missingField(
                        "historySummary"
                    )
                }
                try service.importHistorySummary(entries, now: now)
            }

            let responseState: PublicSessionState
            if let resultingState {
                responseState = resultingState
            } else {
                responseState = try service.publicState(now: now)
            }
            return NativeMessageResponse(ok: true, state: responseState)
        } catch {
            return NativeMessageResponse(
                ok: false,
                state: fallbackPublicState(now: now),
                error: NativeMessageErrorPayload(
                    code: Self.errorCode(for: error),
                    message: error.localizedDescription
                )
            )
        }
    }

    public func failureResponse(
        for error: Error,
        now: Date = Date()
    ) -> NativeMessageResponse {
        NativeMessageResponse(
            ok: false,
            state: fallbackPublicState(now: now),
            error: NativeMessageErrorPayload(
                code: Self.errorCode(for: error),
                message: error.localizedDescription
            )
        )
    }

    private func fallbackPublicState(now: Date) -> PublicSessionState {
        (try? service.publicState(now: now)) ?? PublicSessionState(
            generatedAt: now,
            phase: .inactive,
            isSessionActive: false,
            shouldBlockRestrictedServices: false,
            sessionID: nil,
            startedAt: nil,
            scheduledEndAt: nil,
            sessionRemainingSeconds: 0,
            focusAvailableAt: nil,
            focusRemainingSeconds: 0,
            breakEndsAt: nil,
            breakRemainingSeconds: 0,
            canStartBreak: false,
            canExtendBreak: false,
            focusDurationSeconds: 55 * 60,
            breakDurationSeconds: 5 * 60,
            usageObservationEnabled: false,
            historyEnabled: false,
            blockedDomains: []
        )
    }

    private static func errorCode(for error: Error) -> String {
        if let serviceError = error as? SessionServiceError {
            return String(describing: serviceError)
        }
        if let protocolError = error as? NativeMessageProtocolError {
            return protocolError.code
        }
        return "internalError"
    }
}

public enum NativeMessageProtocolError: LocalizedError, Equatable {
    case missingField(String)
    case malformedFrame
    case messageTooLarge

    public var code: String {
        switch self {
        case let .missingField(field):
            return "missingField.\(field)"
        case .malformedFrame:
            return "malformedFrame"
        case .messageTooLarge:
            return "messageTooLarge"
        }
    }

    public var errorDescription: String? {
        switch self {
        case let .missingField(field):
            return "The \(field) field is required for this request."
        case .malformedFrame:
            return "The native messaging frame is malformed."
        case .messageTooLarge:
            return "The native messaging request is too large."
        }
    }
}
