import Foundation

/// Situação do protocolo, derivada das datas (RF-PRO-02). A ordem dos casos é a ordem da lista.
public enum ProtocolStatus: Int, CaseIterable, Sendable, Comparable {
    case active
    case scheduled
    case ended

    public static func resolve(start: LocalDay, end: LocalDay, endedManually: Bool, today: LocalDay) -> ProtocolStatus {
        if endedManually || today > end { return .ended }
        if today < start { return .scheduled }
        return .active
    }

    public static func < (lhs: ProtocolStatus, rhs: ProtocolStatus) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Como o usuário resolveu uma aplicação prevista.
public enum OccurrenceResolution: Sendable {
    case applied
    case skipped
}

/// Situação de uma aplicação prevista (RF-AGE-03).
public enum OccurrenceStatus: CaseIterable, Sendable {
    case planned
    case overdue
    case applied
    case skipped
    case missed

    /// Tempo após o qual uma atrasada vira "Não registrada".
    public static let missedThreshold: TimeInterval = 7 * 24 * 60 * 60

    public static func resolve(scheduledAt: Date, resolution: OccurrenceResolution?, now: Date) -> OccurrenceStatus {
        switch resolution {
        case .applied: return .applied
        case .skipped: return .skipped
        case nil: break
        }
        if now < scheduledAt { return .planned }
        if now.timeIntervalSince(scheduledAt) > missedThreshold { return .missed }
        return .overdue
    }

    /// Prevista ou atrasada: ainda pode ser aplicada ou pulada.
    public var isPending: Bool { self == .planned || self == .overdue }
}
