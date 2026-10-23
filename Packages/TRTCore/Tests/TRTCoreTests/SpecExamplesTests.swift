import XCTest
@testable import TRTCore

/// Exemplos da seção 8 da especificação.
final class SpecExamplesTests: XCTestCase {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        return c
    }()

    private func dates(_ days: [LocalDay], hour: Int = 9) -> [Date] {
        days.map { $0.date(hour: hour, calendar: calendar) }
    }

    /// Vial de 10 ml a 200 mg/ml com 7,0 ml restantes, 100 mg seg/qui, aplicação de qui 22/10/2026 já registrada.
    func testCurrentVialProjectionExample() {
        let perApplication = VolumeMath.microlitersPerApplication(doseMicrograms: 100_000, concentrationMicrogramsPerMl: 200_000)
        XCTAssertEqual(perApplication, 500)
        XCTAssertEqual(Formatting.milliliters(perApplication), "0,5 ml")
        XCTAssertEqual(Formatting.insulinUnits(perApplication), "50 UI")
        XCTAssertEqual(Formatting.percent(VolumeMath.percentRemaining(remainingMicroliters: 7000, totalMicroliters: 10_000)), "70%")
        XCTAssertEqual(Formatting.percent(VolumeMath.percentRemaining(remainingMicroliters: 6500, totalMicroliters: 10_000)), "65%")

        let schedule = Schedule(frequency: .twoTimesWeek)
        let start = LocalDay(year: 2026, month: 10, day: 1)
        let end = LocalDay(year: 2027, month: 3, day: 31)
        // A partir de sex, 23/10 (a de hoje já foi registrada).
        let upcoming = schedule.days(from: LocalDay(year: 2026, month: 10, day: 23), through: end, protocolStart: start)
        XCTAssertEqual(upcoming.first, LocalDay(year: 2026, month: 10, day: 26))

        let projection = Projection.currentVial(remainingMicroliters: 7000, perApplicationMicroliters: perApplication, upcoming: dates(upcoming))
        XCTAssertEqual(projection.coveredCount, 14)
        XCTAssertEqual(projection.remainingAfterMicroliters, 0)
        XCTAssertEqual(projection.lastCovered.map { LocalDay($0, calendar: calendar) }, LocalDay(year: 2026, month: 12, day: 10))
        XCTAssertEqual(projection.firstNeedingNext.map { LocalDay($0, calendar: calendar) }, LocalDay(year: 2026, month: 12, day: 14))
        XCTAssertEqual(Formatting.weekdayDayMonth(projection.lastCovered!, calendar: calendar), "qui, 10 dez")
        XCTAssertEqual(Formatting.weekdayDayMonth(projection.firstNeedingNext!, calendar: calendar), "seg, 14 dez")
    }

    /// Protocolo de seg 02/11/2026 a dom 24/01/2027, 100 mg seg/qui, vials de 10 ml a 200 mg/ml.
    func testMinimumVialsExample() {
        let schedule = Schedule(frequency: .twoTimesWeek)
        let count = schedule.applicationCount(start: LocalDay(year: 2026, month: 11, day: 2), end: LocalDay(year: 2027, month: 1, day: 24))
        XCTAssertEqual(count, 24)

        let reference = VialReference(volumeMicroliters: 10_000, concentrationMicrogramsPerMl: 200_000)
        XCTAssertEqual(reference.capacityMicrograms, 2_000_000)
        let requirement = VialRequirement.compute(doseMicrograms: 100_000, applicationCount: count, reference: reference)!
        XCTAssertEqual(requirement.totalMicrograms, 2_400_000)
        XCTAssertEqual(requirement.totalMicroliters, 12_000)
        XCTAssertEqual(requirement.vialsNeeded, 2)
        XCTAssertEqual(requirement.leftoverMicroliters, 8000)
        XCTAssertEqual(Formatting.milligrams(requirement.totalMicrograms), "2.400 mg")
        XCTAssertEqual(Formatting.milliliters(requirement.totalMicroliters), "12,0 ml")
        XCTAssertEqual(Formatting.milliliters(reference.volumeMicroliters, minFractionDigits: 0), "10 ml")
    }

    func testVialsToBuyNeverNegative() {
        XCTAssertEqual(VialRequirement.vialsToBuy(neededMicrograms: 1_000_000, stockMicrograms: 3_000_000, perVialMicrograms: 2_000_000), 0)
        XCTAssertEqual(VialRequirement.vialsToBuy(neededMicrograms: 2_400_000, stockMicrograms: 0, perVialMicrograms: 2_000_000), 2)
        XCTAssertEqual(VialRequirement.vialsToBuy(neededMicrograms: 2_400_000, stockMicrograms: 400_000, perVialMicrograms: 2_000_000), 1)
    }
}
