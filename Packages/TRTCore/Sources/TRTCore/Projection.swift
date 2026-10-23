import Foundation

/// Estado mínimo de um vial para os cálculos de consumo.
public struct VialSupply: Equatable, Sendable {
    public let id: UUID
    public var remainingMicroliters: Int
    public let concentrationMicrogramsPerMl: Int

    public init(id: UUID, remainingMicroliters: Int, concentrationMicrogramsPerMl: Int) {
        self.id = id
        self.remainingMicroliters = remainingMicroliters
        self.concentrationMicrogramsPerMl = concentrationMicrogramsPerMl
    }

    public var remainingMicrograms: Int {
        VolumeMath.micrograms(microliters: remainingMicroliters, concentrationMicrogramsPerMl: concentrationMicrogramsPerMl)
    }
}

/// Parte de uma aplicação retirada de um vial.
public struct Portion: Equatable, Sendable {
    public let vialID: UUID
    public let microliters: Int
}

public enum Consumption {
    /// Desconta uma dose dos vials em ordem (RF-VIA-03): se o restante do primeiro for menor que a dose,
    /// consome o restante e completa com o próximo, usando a concentração de cada um.
    /// Retorna as partes descontadas e a massa que nenhum vial conseguiu cobrir.
    public static func consume(doseMicrograms: Int, from vials: inout [VialSupply]) -> (portions: [Portion], uncoveredMicrograms: Int) {
        var need = max(0, doseMicrograms)
        var portions: [Portion] = []
        for index in vials.indices where need > 0 {
            let vial = vials[index]
            guard vial.remainingMicroliters > 0, vial.concentrationMicrogramsPerMl > 0 else { continue }
            let needMicroliters = VolumeMath.microliters(micrograms: need, concentrationMicrogramsPerMl: vial.concentrationMicrogramsPerMl)
            if needMicroliters == 0 {
                need = 0
                break
            }
            if vial.remainingMicroliters >= needMicroliters {
                vials[index].remainingMicroliters -= needMicroliters
                portions.append(Portion(vialID: vial.id, microliters: needMicroliters))
                need = 0
            } else {
                let covered = vial.remainingMicrograms
                portions.append(Portion(vialID: vial.id, microliters: vial.remainingMicroliters))
                vials[index].remainingMicroliters = 0
                need = max(0, need - covered)
            }
        }
        return (portions, need)
    }
}

/// Projeção do vial atual (RF-VIA-06).
public struct CurrentVialProjection: Equatable, Sendable {
    /// Aplicações previstas que o volume restante cobre por inteiro.
    public let coveredCount: Int
    /// "Dura até": data da última aplicação coberta.
    public let lastCovered: Date?
    /// Primeira aplicação que vai precisar do próximo vial (nil se o vial cobre todas até o fim).
    public let firstNeedingNext: Date?
    public let remainingAfterMicroliters: Int

    public var coversAllUpcoming: Bool { firstNeedingNext == nil }
}

/// Projeção do estoque total do composto (RF-VIA-07).
public struct StockProjection: Equatable, Sendable {
    public let coveredCount: Int
    /// Data da última aplicação coberta pelo estoque.
    public let lastCovered: Date?
    /// Data de falta: primeira aplicação que o estoque não cobre.
    public let firstShortage: Date?
    /// Massa que falta para cobrir até o fim do protocolo.
    public let shortageMicrograms: Int
    /// Volume que sobra no fim do protocolo (somente quando o estoque é suficiente).
    public let leftoverMicroliters: Int

    public var isSufficient: Bool { firstShortage == nil }
}

public enum Projection {
    /// Seção 8, passos 1 a 3: percorre as aplicações previstas futuras e desconta do vial atual
    /// enquanto o restante for maior ou igual ao ml por aplicação.
    /// `upcoming` deve conter apenas previstas a partir de agora até o fim, já sem registradas, puladas ou atrasadas.
    public static func currentVial(remainingMicroliters: Int, perApplicationMicroliters: Int, upcoming: [Date]) -> CurrentVialProjection {
        var remaining = max(0, remainingMicroliters)
        var covered = 0
        var last: Date?
        var next: Date?
        for date in upcoming.sorted() {
            if perApplicationMicroliters > 0, remaining >= perApplicationMicroliters {
                remaining -= perApplicationMicroliters
                covered += 1
                last = date
            } else {
                next = date
                break
            }
        }
        return CurrentVialProjection(coveredCount: covered, lastCovered: last, firstNeedingNext: next, remainingAfterMicroliters: remaining)
    }

    /// Seção 8, passo 4: repete o processo encadeando os vials da fila, com a concentração de cada um.
    public static func stock(vials: [VialSupply], doseMicrograms: Int, upcoming: [Date]) -> StockProjection {
        var supplies = vials
        let dates = upcoming.sorted()
        var covered = 0
        var last: Date?
        for (index, date) in dates.enumerated() {
            let result = Consumption.consume(doseMicrograms: doseMicrograms, from: &supplies)
            if result.uncoveredMicrograms > 0 {
                let pendingAfter = dates.count - index - 1
                let shortage = result.uncoveredMicrograms + pendingAfter * max(0, doseMicrograms)
                return StockProjection(coveredCount: covered, lastCovered: last, firstShortage: date,
                                       shortageMicrograms: shortage, leftoverMicroliters: 0)
            }
            covered += 1
            last = date
        }
        let leftover = supplies.reduce(0) { $0 + $1.remainingMicroliters }
        return StockProjection(coveredCount: covered, lastCovered: last, firstShortage: nil,
                               shortageMicrograms: 0, leftoverMicroliters: leftover)
    }
}
