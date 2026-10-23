import Foundation

/// Dose de um regime relativa à dose de referência (mesmo composto e éster): r = D_i / D_ref.
/// Por ser uma razão, F, V_d e a correção de peso do éster se cancelam.
public struct RelativeDose: Equatable, Sendable {
    public let date: Date
    public let amount: Double

    public init(date: Date, amount: Double) {
        self.date = date
        self.amount = amount
    }
}

/// Faixa do perfil normalizado num instante, sobre a varredura de k_e.
public struct EnvelopePoint: Equatable, Sendable {
    public let date: Date
    public let low: Double
    public let high: Double
}

/// Pico e vale no estado estável, como faixas sobre a varredura de k_e.
public struct SteadyStateEnvelope: Equatable, Sendable {
    /// 5 meias-vidas de absorção após a primeira dose.
    public let reachedAt: Date
    public let peak: ClosedRange<Double>
    public let trough: ClosedRange<Double>
}

/// Perfil plasmático normalizado de um regime de várias doses (superposição de Bateman).
///
/// perfil(t) = Σ rᵢ · C_bruto(t − tᵢ) / max(C_bruto), em múltiplos do pico de uma dose única de
/// referência — grandeza adimensional. Cinética linear: o fator F·D/V_d se cancela na normalização.
public enum RegimenProfile {
    public static let steadyStateHalfLives = 5.0
    /// Janela de leitura do estado estável: a última semana de doses (um ciclo de qualquer agenda do app).
    public static let steadyStateWindow: TimeInterval = 7 * 86400

    public static func level(at date: Date, doses: [RelativeDose], ka: Double, ke: Double) -> Double {
        let peak = ReleaseKinetics.batemanPeak(ka: ka, ke: ke)
        var total = 0.0
        for dose in doses where dose.date < date {
            total += dose.amount * ReleaseKinetics.batemanRaw(date.timeIntervalSince(dose.date) / 3600, ka: ka, ke: ke)
        }
        return total / peak
    }

    /// Instantes amostrados: grade regular + início de cada dose e o t_max de cada k_e após cada dose,
    /// para que picos e vales apareçam mesmo com ésteres curtos.
    public static func sampleTimes(doses: [RelativeDose], ka: Double, from: Date, to: Date, maxGridPoints: Int = 240) -> [Date] {
        guard to > from else { return [] }
        let step = max(1800, to.timeIntervalSince(from) / Double(max(1, maxGridPoints)))
        var times: [Date] = []
        var t = from
        while t < to {
            times.append(t)
            t = t.addingTimeInterval(step)
        }
        times.append(to)
        let peaks = ReleaseKinetics.eliminationHalfLivesHours.map {
            ReleaseKinetics.tMax(ka: ka, ke: ReleaseKinetics.rate(halfLifeHours: $0)) * 3600
        }
        for dose in doses {
            for offset in [0] + peaks {
                let time = dose.date.addingTimeInterval(offset)
                if time >= from && time <= to { times.append(time) }
            }
        }
        return Array(Set(times)).sorted()
    }

    /// Envelope do perfil normalizado sob a varredura de k_e.
    public static func envelope(doses: [RelativeDose], absorptionHalfLifeHours: Double, from: Date, to: Date,
                                maxGridPoints: Int = 240) -> [EnvelopePoint] {
        let ka = ReleaseKinetics.absorptionRate(halfLifeHours: absorptionHalfLifeHours)
        let kes = ReleaseKinetics.eliminationHalfLivesHours.map { ReleaseKinetics.rate(halfLifeHours: $0) }
        let sorted = doses.sorted { $0.date < $1.date }
        return sampleTimes(doses: sorted, ka: ka, from: from, to: to, maxGridPoints: maxGridPoints).map { date in
            let values = kes.map { level(at: date, doses: sorted, ka: ka, ke: $0) }
            return EnvelopePoint(date: date, low: values.min() ?? 0, high: values.max() ?? 0)
        }
    }

    /// Pico e vale na última semana de doses até `to`, se já tiverem passado 5 meias-vidas de absorção.
    public static func steadyState(doses: [RelativeDose], absorptionHalfLifeHours: Double, to: Date) -> SteadyStateEnvelope? {
        let sorted = doses.sorted { $0.date < $1.date }
        guard absorptionHalfLifeHours > 0, let first = sorted.first, let last = sorted.last(where: { $0.date <= to }) else { return nil }
        let reachedAt = first.date.addingTimeInterval(steadyStateHalfLives * absorptionHalfLifeHours * 3600)
        let windowEnd = last.date
        guard reachedAt < windowEnd else { return nil }
        let windowStart = max(reachedAt, windowEnd.addingTimeInterval(-steadyStateWindow))
        let ka = ReleaseKinetics.absorptionRate(halfLifeHours: absorptionHalfLifeHours)
        let times = sampleTimes(doses: sorted, ka: ka, from: windowStart, to: windowEnd, maxGridPoints: 400)
        var peaks: [Double] = []
        var troughs: [Double] = []
        for halfLife in ReleaseKinetics.eliminationHalfLivesHours {
            let ke = ReleaseKinetics.rate(halfLifeHours: halfLife)
            let values = times.map { level(at: $0, doses: sorted, ka: ka, ke: ke) }
            guard let max = values.max(), let min = values.min() else { continue }
            peaks.append(max)
            troughs.append(min)
        }
        guard let peakLow = peaks.min(), let peakHigh = peaks.max(),
              let troughLow = troughs.min(), let troughHigh = troughs.max() else { return nil }
        return SteadyStateEnvelope(reachedAt: reachedAt, peak: peakLow...peakHigh, trough: troughLow...troughHigh)
    }
}
