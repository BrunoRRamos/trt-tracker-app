import XCTest
@testable import TRTCore

final class LocalDayTests: XCTestCase {
    func testRoundTripAndWeekday() {
        let day = LocalDay(year: 2026, month: 10, day: 22)
        XCTAssertEqual(day.key, "2026-10-22")
        XCTAssertEqual(LocalDay(key: "2026-10-22"), day)
        XCTAssertEqual(day.weekday, .thursday)
        XCTAssertEqual(LocalDay(year: 2026, month: 11, day: 2).weekday, .monday)
        XCTAssertEqual(LocalDay(year: 2027, month: 1, day: 24).weekday, .sunday)
        XCTAssertEqual(day.adding(days: 10).key, "2026-11-01")
        XCTAssertEqual(LocalDay(year: 2028, month: 2, day: 28).adding(days: 1).key, "2028-02-29")
        XCTAssertEqual(LocalDay(year: 2026, month: 2, day: 1).numberOfDaysInMonth, 28)
        XCTAssertEqual(LocalDay(year: 2026, month: 12, day: 5).addingMonths(1).key, "2027-01-01")
    }
}

final class ScheduleTests: XCTestCase {
    let start = LocalDay(year: 2026, month: 10, day: 22)

    func testDailyAndEveryOtherDay() {
        let end = start.adding(days: 9)
        XCTAssertEqual(Schedule(frequency: .daily).days(from: start, through: end, protocolStart: start).count, 10)
        let alternate = Schedule(frequency: .everyOtherDay).days(from: start, through: end, protocolStart: start)
        XCTAssertEqual(alternate.map(\.key), ["2026-10-22", "2026-10-24", "2026-10-26", "2026-10-28", "2026-10-30"])
    }

    func testEveryOtherDayRestart() {
        // Recontagem a partir de 25/10: antes segue a paridade do início, depois a da nova data.
        let schedule = Schedule(frequency: .everyOtherDay, alternateAnchor: LocalDay(year: 2026, month: 10, day: 25))
        let days = schedule.days(from: start, through: start.adding(days: 6), protocolStart: start)
        XCTAssertEqual(days.map(\.key), ["2026-10-22", "2026-10-24", "2026-10-25", "2026-10-27"])
    }

    func testWeekdaysRequireExactCount() {
        XCTAssertTrue(Schedule(frequency: .threeTimesWeek).isValid)
        XCTAssertEqual(Frequency.threeTimesWeek.defaultWeekdays, [.monday, .wednesday, .friday])
        XCTAssertEqual(Frequency.twoTimesWeek.defaultWeekdays, [.monday, .thursday])
        XCTAssertFalse(Schedule(frequency: .threeTimesWeek, weekdays: [.monday]).isValid)
        XCTAssertFalse(Schedule(frequency: .twoTimesWeek, weekdays: [.monday, .tuesday, .friday]).isValid)
        XCTAssertEqual(Weekday.set(fromMask: Weekday.mask([.monday, .thursday])), [.monday, .thursday])
    }
}

final class StatusTests: XCTestCase {
    func testProtocolStatus() {
        let start = LocalDay(year: 2026, month: 11, day: 1)
        let end = LocalDay(year: 2026, month: 11, day: 30)
        XCTAssertEqual(ProtocolStatus.resolve(start: start, end: end, endedManually: false, today: start.adding(days: -1)), .scheduled)
        XCTAssertEqual(ProtocolStatus.resolve(start: start, end: end, endedManually: false, today: start), .active)
        XCTAssertEqual(ProtocolStatus.resolve(start: start, end: end, endedManually: false, today: end), .active)
        XCTAssertEqual(ProtocolStatus.resolve(start: start, end: end, endedManually: false, today: end.adding(days: 1)), .ended)
        XCTAssertEqual(ProtocolStatus.resolve(start: start, end: end, endedManually: true, today: start), .ended)
    }

    func testOccurrenceStatus() {
        let scheduled = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(OccurrenceStatus.resolve(scheduledAt: scheduled, resolution: nil, now: scheduled.addingTimeInterval(-60)), .planned)
        XCTAssertEqual(OccurrenceStatus.resolve(scheduledAt: scheduled, resolution: nil, now: scheduled.addingTimeInterval(60)), .overdue)
        XCTAssertEqual(OccurrenceStatus.resolve(scheduledAt: scheduled, resolution: nil, now: scheduled.addingTimeInterval(7 * 86400)), .overdue)
        XCTAssertEqual(OccurrenceStatus.resolve(scheduledAt: scheduled, resolution: nil, now: scheduled.addingTimeInterval(7 * 86400 + 1)), .missed)
        XCTAssertEqual(OccurrenceStatus.resolve(scheduledAt: scheduled, resolution: .applied, now: scheduled), .applied)
        XCTAssertEqual(OccurrenceStatus.resolve(scheduledAt: scheduled, resolution: .skipped, now: scheduled), .skipped)
    }
}

final class VolumeTests: XCTestCase {
    func testPercentRemaining() {
        XCTAssertEqual(VolumeMath.percentRemaining(remainingMicroliters: 5500, totalMicroliters: 10_000), .whole(55))
        XCTAssertEqual(VolumeMath.percentRemaining(remainingMicroliters: 5599, totalMicroliters: 10_000), .whole(55))
        XCTAssertEqual(VolumeMath.percentRemaining(remainingMicroliters: 50, totalMicroliters: 10_000), .lessThanOne)
        XCTAssertEqual(VolumeMath.percentRemaining(remainingMicroliters: 0, totalMicroliters: 10_000), .whole(0))
        XCTAssertEqual(VolumeMath.applicationsRemaining(remainingMicroliters: 7000, perApplicationMicroliters: 500), 14)
        XCTAssertEqual(VolumeMath.applicationsRemaining(remainingMicroliters: 7400, perApplicationMicroliters: 500), 14)
    }

    func testConsumptionSplitsAcrossVials() {
        let a = UUID(), b = UUID()
        var vials = [
            VialSupply(id: a, remainingMicroliters: 200, concentrationMicrogramsPerMl: 200_000),
            VialSupply(id: b, remainingMicroliters: 10_000, concentrationMicrogramsPerMl: 250_000)
        ]
        // 100 mg: 0,2 ml do primeiro (40 mg) e 60 mg do segundo a 250 mg/ml = 0,24 ml.
        let result = Consumption.consume(doseMicrograms: 100_000, from: &vials)
        XCTAssertEqual(result.portions, [Portion(vialID: a, microliters: 200), Portion(vialID: b, microliters: 240)])
        XCTAssertEqual(result.uncoveredMicrograms, 0)
        XCTAssertEqual(vials[0].remainingMicroliters, 0)
        XCTAssertEqual(vials[1].remainingMicroliters, 9760)
    }

    func testConsumptionWithoutEnoughStock() {
        let a = UUID()
        var vials = [VialSupply(id: a, remainingMicroliters: 300, concentrationMicrogramsPerMl: 200_000)]
        let result = Consumption.consume(doseMicrograms: 100_000, from: &vials)
        XCTAssertEqual(result.portions, [Portion(vialID: a, microliters: 300)])
        XCTAssertEqual(result.uncoveredMicrograms, 40_000)
        XCTAssertEqual(vials[0].remainingMicroliters, 0)
    }

    func testStockProjectionShortageAndLeftover() {
        let day = LocalDay(year: 2026, month: 11, day: 2)
        let upcoming = (0..<10).map { day.adding(days: $0 * 3).date() }
        let vials = [
            VialSupply(id: UUID(), remainingMicroliters: 1000, concentrationMicrogramsPerMl: 200_000),
            VialSupply(id: UUID(), remainingMicroliters: 1200, concentrationMicrogramsPerMl: 200_000)
        ]
        // 2,2 ml = 440 mg → 4 doses de 100 mg cobertas; a 5ª falta 60 mg; mais 5 doses inteiras.
        let shortage = Projection.stock(vials: vials, doseMicrograms: 100_000, upcoming: upcoming)
        XCTAssertEqual(shortage.coveredCount, 4)
        XCTAssertEqual(shortage.firstShortage, upcoming[4])
        XCTAssertEqual(shortage.lastCovered, upcoming[3])
        XCTAssertEqual(shortage.shortageMicrograms, 60_000 + 5 * 100_000)

        let sufficient = Projection.stock(vials: vials, doseMicrograms: 100_000, upcoming: Array(upcoming.prefix(3)))
        XCTAssertTrue(sufficient.isSufficient)
        XCTAssertEqual(sufficient.leftoverMicroliters, 700)
    }
}

final class InputTests: XCTestCase {
    func testDecimalInputAcceptsComma() {
        XCTAssertEqual(DecimalInput.parse("0,5"), Decimal(string: "0.5"))
        XCTAssertEqual(DecimalInput.parse("10.25"), Decimal(string: "10.25"))
        XCTAssertNil(DecimalInput.parse("1,2,3"))
        XCTAssertNil(DecimalInput.parse("abc"))
        XCTAssertEqual(DecimalInput.text(fromScaled: 500), "0,5")
        XCTAssertEqual(DecimalInput.text(fromScaled: 2_400_000), "2400")
    }

    func testValidation() {
        XCTAssertEqual(Validation.protocolName("   "), .empty)
        XCTAssertNil(Validation.protocolName("  TRT  "))
        XCTAssertEqual(Validation.protocolName(String(repeating: "a", count: 51)), .tooLong(max: 50))
        XCTAssertEqual(Validation.compoundName(String(repeating: "a", count: 41)), .tooLong(max: 40))
        XCTAssertEqual(try Validation.vialVolume("10").get(), 10_000)
        XCTAssertEqual(try Validation.vialVolume("0,1").get(), 100)
        XCTAssertEqual(Validation.vialVolume("0,05"), .failure(.belowMinimum))
        XCTAssertEqual(Validation.vialVolume("10,25"), .failure(.step))
        XCTAssertEqual(Validation.vialVolume("100,1"), .failure(.aboveMaximum))
        XCTAssertEqual(try Validation.concentration("200").get(), 200_000)
        XCTAssertEqual(Validation.concentration("0,5"), .failure(.belowMinimum))
        XCTAssertEqual(Validation.concentration("1001"), .failure(.aboveMaximum))
        XCTAssertEqual(Validation.dose("0"), .failure(.belowMinimum))
        XCTAssertEqual(try Validation.dose("0,25").get(), 250)
        XCTAssertEqual(Validation.remainingVolume("11", totalMicroliters: 10_000), .failure(.aboveMaximum))
        XCTAssertTrue(Validation.isValidPeriod(start: LocalDay(year: 2026, month: 1, day: 1), end: LocalDay(year: 2026, month: 1, day: 1)))
        XCTAssertFalse(Validation.isValidPeriod(start: LocalDay(year: 2026, month: 1, day: 2), end: LocalDay(year: 2026, month: 1, day: 1)))
    }

    func testFormatting() {
        XCTAssertEqual(Formatting.numericDate(LocalDay(year: 2026, month: 10, day: 2)), "02/10/2026")
        XCTAssertEqual(Formatting.time(hour: 9, minute: 5), "09:05")
        XCTAssertEqual(Formatting.milligrams(250), "0,25 mg")
        XCTAssertEqual(Formatting.weekdayDayMonth(LocalDay(year: 2026, month: 11, day: 13)), "sex, 13 nov")
        XCTAssertEqual(Formatting.monthYear(LocalDay(year: 2026, month: 10, day: 1)), "Outubro de 2026")
    }
}
