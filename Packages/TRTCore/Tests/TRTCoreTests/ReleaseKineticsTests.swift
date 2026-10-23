import XCTest
@testable import TRTCore

/// Seção 5 da spec de cinética: invariantes analíticos. Falha indica erro de implementação, não de parametrização.
final class ReleaseKineticsTests: XCTestCase {
    let ka = ReleaseKinetics.absorptionRate(halfLifeHours: 108)
    let ke = ReleaseKinetics.rate(halfLifeHours: 4.3)

    /// 1. Meia-vida: F_lib(t½) = 0,5.
    func testCumulativeReleaseAtHalfLife() {
        for halfLife in [19.2, 108, 813.6] {
            let ka = ReleaseKinetics.absorptionRate(halfLifeHours: halfLife)
            XCTAssertEqual(ReleaseKinetics.cumulativeRelease(halfLife, ka: ka), 0.5, accuracy: 1e-12)
        }
    }

    /// 2. t_90 = ln(10)/k_a (e t_99 = ln(100)/k_a).
    func testTimeToNinetyPercent() {
        XCTAssertEqual(ReleaseKinetics.timeToFraction(ka: ka, fraction: 0.9), log(10) / ka, accuracy: 1e-9)
        XCTAssertEqual(ReleaseKinetics.timeToFraction(ka: ka, fraction: 0.99), log(100) / ka, accuracy: 1e-9)
        XCTAssertEqual(ReleaseKinetics.cumulativeRelease(log(10) / ka, ka: ka), 0.9, accuracy: 1e-12)
    }

    /// 3. Normalização: max(C_norm) = 1.
    func testNormalizedMaximumIsOne() {
        let tMax = ReleaseKinetics.tMax(ka: ka, ke: ke)
        let grid = stride(from: 0.0, through: 2000, by: 0.5).map { $0 } + [tMax]
        let values = ReleaseKinetics.batemanNormalized(grid, ka: ka, ke: ke)
        XCTAssertEqual(values.max()!, 1.0, accuracy: 1e-12)
        XCTAssertTrue(values.allSatisfy { $0 <= 1 + 1e-12 })
    }

    /// 4. t_max analítico coincide com o argmax numérico.
    func testAnalyticTMaxMatchesNumericArgmax() {
        for (absorption, elimination) in [(19.2, 1.0), (108, 4.3), (36, 24), (813.6, 12)] {
            let ka = ReleaseKinetics.absorptionRate(halfLifeHours: absorption)
            let ke = ReleaseKinetics.rate(halfLifeHours: elimination)
            let step = 0.01
            let grid = stride(from: 0.0, through: 200, by: step).map { $0 }
            let values = ReleaseKinetics.batemanNormalized(grid, ka: ka, ke: ke)
            let argmax = grid[values.indices.max { values[$0] < values[$1] }!]
            XCTAssertEqual(argmax, ReleaseKinetics.tMax(ka: ka, ke: ke), accuracy: step, "t½ \(absorption)/\(elimination)")
        }
    }

    /// 5. AUC₀–∞ de C_bruto = 1/k_e para qualquer k_a: o éster não altera a exposição total.
    func testAreaUnderCurveIsIndependentOfKa() {
        for absorption in [19.2, 36, 108, 180] {
            let ka = ReleaseKinetics.absorptionRate(halfLifeHours: absorption)
            let step = 0.05
            let end = 40 * max(absorption, 4.3)
            var area = 0.0
            var previous = ReleaseKinetics.batemanRaw(0, ka: ka, ke: ke)
            var t = step
            while t <= end {
                let value = ReleaseKinetics.batemanRaw(t, ka: ka, ke: ke)
                area += (previous + value) / 2 * step
                previous = value
                t += step
            }
            XCTAssertEqual(area, 1 / ke, accuracy: 1e-3 / ke, "t½ absorção \(absorption) h")
        }
    }

    /// 6. Limite flip-flop: com k_e/k_a → ∞, C_norm(t) → exp(−k_a·t).
    func testFlipFlopLimit() {
        let ke = ka * 1e5
        for t in [10.0, 100, 500, 1000] {
            XCTAssertEqual(ReleaseKinetics.batemanNormalized(t, ka: ka, ke: ke), exp(-ka * t), accuracy: 1e-3)
        }
    }

    /// 7. Monotonicidade: F_lib estritamente crescente, com assíntota em 1.
    func testCumulativeReleaseIsMonotonic() {
        let values = ReleaseKinetics.cumulativeRelease(stride(from: 0.0, through: 3000, by: 1).map { $0 }, ka: ka)
        XCTAssertTrue(zip(values, values.dropFirst()).allSatisfy { $0 < $1 })
        XCTAssertTrue(values.allSatisfy { $0 >= 0 && $0 < 1 })
        XCTAssertEqual(ReleaseKinetics.cumulativeRelease(40 * 108, ka: ka), 1, accuracy: 1e-9)
    }

    /// Guarda numérica: |k_a − k_e| < 1e−9 usa o caso-limite k·t·exp(−k·t).
    func testDegenerateCase() {
        let k = 0.1
        XCTAssertEqual(ReleaseKinetics.batemanRaw(5, ka: k, ke: k), k * 5 * exp(-k * 5), accuracy: 1e-15)
        XCTAssertEqual(ReleaseKinetics.tMax(ka: k, ke: k), 10, accuracy: 1e-12)
        XCTAssertEqual(ReleaseKinetics.batemanRaw(5, ka: k, ke: k + 1e-12), k * 5 * exp(-k * 5), accuracy: 1e-12)
        XCTAssertEqual(ReleaseKinetics.batemanNormalized(10, ka: k, ke: k), 1, accuracy: 1e-12)
    }

    func testParentDoseCorrection() {
        XCTAssertEqual(ReleaseKinetics.parentDose(injected: 100, activeDosePercent: 69), 69, accuracy: 1e-12)
    }
}

final class CatalogLoaderTests: XCTestCase {
    let catalog = CompoundCatalog.shared

    func testLoadsBundledCatalogWithoutErrors() {
        XCTAssertEqual(catalog.compounds.count, 15)
        XCTAssertEqual(catalog.entries.count, 32)
        XCTAssertTrue(catalog.issues.filter { $0.severity == .error }.isEmpty, "\(catalog.issues)")
        XCTAssertEqual(Set(catalog.entries.map(\.key)).count, catalog.entries.count, "chaves únicas")
        XCTAssertEqual(Set(catalog.entries.map(\.displayName)).count, catalog.entries.count, "nomes únicos")
    }

    /// Filtro obrigatório: só via intramuscular com éster.
    func testDepotFilter() {
        XCTAssertEqual(catalog.depotEntries.count, 22)
        XCTAssertTrue(catalog.depotEntries.allSatisfy { $0.variant.route == .intramuscular && $0.variant.ester != nil })
        XCTAssertFalse(catalog.entries.first { $0.displayName == "Testosterona (Suspensão aquosa)" }!.isDepotModelEligible)
        XCTAssertFalse(catalog.entries.first { $0.displayName == "Anavar" }!.isDepotModelEligible)
        XCTAssertFalse(catalog.depotCompounds.contains { $0.name == "Anavar" })
    }

    /// origemMeiaVida dos ésteres de testosterona, conforme a tabela da spec.
    func testHalfLifeOrigins() {
        let testosterone = Dictionary(uniqueKeysWithValues: catalog.depotEntries
            .filter { $0.compoundName == "Testosterona" }
            .map { ($0.variantLabel ?? "", $0.variant.halfLifeOrigin) })
        XCTAssertEqual(testosterone["Propionato"], .measured)
        XCTAssertEqual(testosterone["Fenilpropionato"], .extrapolated)
        XCTAssertEqual(testosterone["Isocaproato"], .extrapolated)
        XCTAssertEqual(testosterone["Enantato"], .measured)
        XCTAssertEqual(testosterone["Cipionato"], .extrapolated)
        XCTAssertEqual(testosterone["Decanoato"], .extrapolated)
        XCTAssertEqual(testosterone["Undecanoato (Óleo de semente de chá)"], .measured)
        XCTAssertEqual(testosterone["Undecanoato (Óleo de rícino)"], .measured)
        XCTAssertEqual(testosterone["Durateston"], .some(nil), "sem origem informada")
    }

    func testValidationRejectsInvalidVariants() throws {
        let json = """
        { "compostos": [ { "nome": "X", "nomeQuimico": "X", "esteres": [
          { "ester": "A", "via": "intramuscular", "meiaVidaDias": 1, "meiaVidaHoras": 24, "doseAtivaPercentual": 70 },
          { "ester": "B", "via": "intramuscular", "meiaVidaDias": 0, "meiaVidaHoras": 0, "doseAtivaPercentual": 70 },
          { "ester": "C", "via": "intramuscular", "meiaVidaDias": 1, "meiaVidaHoras": 24, "doseAtivaPercentual": 120 },
          { "ester": "D", "via": "intramuscular", "meiaVidaDias": 3, "meiaVidaHoras": 24, "doseAtivaPercentual": 70 },
          { "ester": "A", "via": "intramuscular", "meiaVidaDias": 1, "meiaVidaHoras": 24, "doseAtivaPercentual": 70 }
        ] } ] }
        """
        let catalog = try CompoundCatalog.decode(Data(json.utf8))
        XCTAssertEqual(catalog.entries.map { $0.variant.ester }, ["A", "D"])
        XCTAssertEqual(catalog.issues.filter { $0.severity == .error }.count, 3)
        XCTAssertEqual(catalog.issues.filter { $0.severity == .warning }.count, 1)
    }

    func testDisplayNames() {
        XCTAssertNotNil(catalog.entries.first { $0.displayName == "Testosterona Cipionato" })
        XCTAssertNotNil(catalog.entries.first { $0.displayName == "Testosterona Undecanoato (Óleo de rícino)" })
        XCTAssertEqual(catalog.referenceEntry?.displayName, "Testosterona Propionato")
    }
}

final class ReleaseMetricsTests: XCTestCase {
    let catalog = CompoundCatalog.shared

    func testMetrics() {
        let metrics = ReleaseMetricsBuilder.metrics(for: catalog.depotEntries, reference: catalog.referenceEntry, uncertainty: nil)
        XCTAssertEqual(metrics.count, 22)
        XCTAssertEqual(metrics.map(\.halfLifeHours), metrics.map(\.halfLifeHours).sorted(), "ordenadas por t½")
        let propionate = metrics.first { $0.entry.displayName == "Testosterona Propionato" }!
        XCTAssertEqual(propionate.cmaxRelative, 1, accuracy: 1e-12)
        let enanthate = metrics.first { $0.entry.displayName == "Testosterona Enantato" }!
        XCTAssertEqual(enanthate.cmaxRelative, 19.2 / 108, accuracy: 1e-12)
        XCTAssertEqual(enanthate.t90, log(10) / enanthate.ka, accuracy: 1e-9)
        XCTAssertEqual(enanthate.t99, log(100) / enanthate.ka, accuracy: 1e-9)
        XCTAssertEqual(enanthate.tMax.map(\.eliminationHalfLifeHours), [1, 4.3, 12, 24])
        XCTAssertEqual(enanthate.origin, .measured)
    }

    /// Seção 7: a incerteza do C_max absoluto é várias vezes o valor pontual, e maior com t½ extrapolado.
    /// Com V_d 0,5–2 L/kg, F 0,5–1 e t½ ×/÷2 (extrapolado), a razão P95/P5 fica perto de 7; passar de uma
    /// ordem de grandeza depende de uma incerteza de t½ mais larga, que a spec não fixa.
    func testUncertaintyPropagation() {
        let parameters = UncertaintyParameters()
        let extrapolated = ReleaseMetricsBuilder.cmaxUncertainty(halfLifeHours: 120, origin: .extrapolated, key: "x", parameters: parameters)
        let measured = ReleaseMetricsBuilder.cmaxUncertainty(halfLifeHours: 108, origin: .measured, key: "y", parameters: parameters)
        XCTAssertGreaterThan(extrapolated.ratio, 5)
        XCTAssertGreaterThan(extrapolated.ratio, measured.ratio)
        XCTAssertGreaterThan(measured.ratio, 1)
        let again = ReleaseMetricsBuilder.cmaxUncertainty(halfLifeHours: 120, origin: .extrapolated, key: "x", parameters: parameters)
        XCTAssertEqual(extrapolated, again, "reprodutível")
    }

    func testCSV() {
        let metrics = ReleaseMetricsBuilder.metrics(for: catalog.depotEntries.filter { $0.compoundName == "Testosterona" },
                                                    reference: catalog.referenceEntry, uncertainty: nil)
        let lines = ReleaseMetricsBuilder.csv(metrics).split(separator: "\n")
        XCTAssertEqual(lines.count, 10)
        XCTAssertTrue(lines[0].hasPrefix("composto,ester,veiculo,t_meia_h,origem_t_meia,k_a_por_h,t_90_h,t_99_h,cmax_relativo_propionato"))
        XCTAssertTrue(lines[1].hasPrefix("Testosterona,Propionato,,19.2,medido,0.036101,63.78,127.56,1,4.5,11.96,"))
        XCTAssertTrue(lines.contains { $0.contains("Durateston") && $0.contains("nao_informado") })
    }
}

final class RegimenProfileTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// Uma dose de referência: o perfil é a própria C_norm, com pico 1 no t_max.
    func testSingleDoseMatchesNormalizedBateman() {
        let ka = ReleaseKinetics.absorptionRate(halfLifeHours: 108)
        let ke = ReleaseKinetics.rate(halfLifeHours: 4.3)
        let doses = [RelativeDose(date: start, amount: 1)]
        let tMax = ReleaseKinetics.tMax(ka: ka, ke: ke)
        XCTAssertEqual(RegimenProfile.level(at: start.addingTimeInterval(tMax * 3600), doses: doses, ka: ka, ke: ke), 1, accuracy: 1e-9)
        XCTAssertEqual(RegimenProfile.level(at: start, doses: doses, ka: ka, ke: ke), 0)
    }

    func testEnvelopeAndSteadyState() {
        // 2x por semana por 12 semanas: acumula acima de 1 pico de dose única.
        let doses = stride(from: 0.0, to: 84, by: 3.5).map { RelativeDose(date: start.addingTimeInterval($0 * 86400), amount: 1) }
        let end = start.addingTimeInterval(84 * 86400)
        let envelope = RegimenProfile.envelope(doses: doses, absorptionHalfLifeHours: 108, from: start, to: end)
        XCTAssertTrue(envelope.allSatisfy { $0.low <= $0.high })
        XCTAssertEqual(envelope.map(\.date), envelope.map(\.date).sorted())
        let steady = RegimenProfile.steadyState(doses: doses, absorptionHalfLifeHours: 108, to: end)!
        XCTAssertGreaterThan(steady.peak.lowerBound, 1.5)
        // As faixas se sobrepõem entre valores de k_e; a ordem vale para cada k_e.
        XCTAssertLessThan(steady.trough.lowerBound, steady.peak.lowerBound)
        XCTAssertLessThan(steady.trough.upperBound, steady.peak.upperBound)
        XCTAssertEqual(steady.reachedAt, start.addingTimeInterval(5 * 108 * 3600))
    }

    /// Mesma dose total semanal: aplicações mais frequentes oscilam menos.
    func testMoreFrequentDosingReducesFluctuation() {
        let end = start.addingTimeInterval(84 * 86400)
        let weekly = stride(from: 0.0, to: 84, by: 7).map { RelativeDose(date: start.addingTimeInterval($0 * 86400), amount: 2) }
        let twice = stride(from: 0.0, to: 84, by: 3.5).map { RelativeDose(date: start.addingTimeInterval($0 * 86400), amount: 1) }
        let a = RegimenProfile.steadyState(doses: weekly, absorptionHalfLifeHours: 108, to: end)!
        let b = RegimenProfile.steadyState(doses: twice, absorptionHalfLifeHours: 108, to: end)!
        XCTAssertLessThan(b.peak.upperBound / b.trough.lowerBound, a.peak.upperBound / a.trough.lowerBound)
    }
}
