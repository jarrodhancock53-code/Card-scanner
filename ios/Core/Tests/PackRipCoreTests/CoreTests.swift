import XCTest
@testable import PackRipCore

final class PriceTableTests: XCTestCase {
    let table = PriceTable(file: PriceFile(updatedAt: "2026-11-21", cards: [
        "sv1-1": ["normal": PriceEntry(market: 0.12, low: 0.05, high: 0.5),
                  "reverseHolo": PriceEntry(market: 0.25, low: 0.1, high: 1.0)],
        "sv1-5": ["holo": PriceEntry(market: 52.5, low: 38, high: 80)],
        "x-1": ["normal": PriceEntry(market: 0.20), "reverseHolo": PriceEntry(market: 4.00)],
    ]))

    func testExactPrinting() {
        let q = table.quote(cardId: "sv1-1", printing: .reverseHolo)
        XCTAssertEqual(q?.market, 0.25)
        XCTAssertEqual(q?.printing, .reverseHolo)
        XCTAssertEqual(q?.isRange, false)
    }

    func testUnknownPrintingGivesRange() {
        let q = table.quote(cardId: "x-1", printing: nil)
        XCTAssertEqual(q?.low, 0.20)
        XCTAssertEqual(q?.high, 4.00)
        XCTAssertEqual(q?.isRange, true)
    }

    func testSinglePrintingNeedsNoGuess() {
        let q = table.quote(cardId: "sv1-5", printing: nil)
        XCTAssertEqual(q?.printing, .holo)
        XCTAssertEqual(q?.market, 52.5)
    }

    func testMissingPrintingIsNil() {
        XCTAssertNil(table.quote(cardId: "sv1-5", printing: .normal))
        XCTAssertNil(table.quote(cardId: "nope", printing: nil))
    }

    func testPrintingMatters() {
        XCTAssertTrue(table.printingMatters(cardId: "x-1"))
        XCTAssertFalse(table.printingMatters(cardId: "sv1-5"))
        XCTAssertFalse(table.printingMatters(cardId: "sv1-1")) // 0.13 apart: below the 0.25 threshold
    }

    func testDecodesSyncOutput() throws {
        let json = #"{"updatedAt":"2026-11-21","cards":{"sv1-1":{"normal":{"market":0.12,"low":0.05,"high":0.5}}}}"#
        let f = try JSONDecoder().decode(PriceFile.self, from: Data(json.utf8))
        XCTAssertEqual(PriceTable(file: f).quote(cardId: "sv1-1", printing: .normal)?.high, 0.5)
    }
}

final class MatchDeciderTests: XCTestCase {
    let table = PriceTable(file: PriceFile(updatedAt: "d", cards: [
        "a": ["normal": PriceEntry(market: 0.2), "reverseHolo": PriceEntry(market: 0.9)],
        "hit": ["normal": PriceEntry(market: 0.5), "reverseHolo": PriceEntry(market: 9.0)],
        "solo": ["holo": PriceEntry(market: 3.0)],
    ]))

    func cands(_ top: Double, _ second: Double, id: String = "a", number: String = "15") -> [Candidate] {
        [Candidate(cardId: id, number: number, distance: top), Candidate(cardId: "b", number: "2", distance: second)]
    }

    func testAcceptsClearMatchWithNumber() {
        let r = MatchDecider.decide(candidates: cands(0.2, 0.5), ocrNumber: "015/198",
                                    printingGuess: PrintingGuess(printing: .reverseHolo, confidence: 0.9), prices: table)
        XCTAssertFalse(r.needsTap)
        XCTAssertEqual(r.cardId, "a")
        XCTAssertEqual(r.printing, .reverseHolo)
        XCTAssertFalse(r.flagged)
    }

    func testNumberMismatchNeedsTap() {
        let r = MatchDecider.decide(candidates: cands(0.2, 0.5), ocrNumber: "99/198", printingGuess: nil, prices: table)
        XCTAssertTrue(r.needsTap)
        XCTAssertEqual(r.reason, .numberMismatch)
    }

    func testCloseSecondNeedsTap() {
        let r = MatchDecider.decide(candidates: cands(0.2, 0.22), ocrNumber: "15/198", printingGuess: nil, prices: table)
        XCTAssertTrue(r.needsTap)
        XCTAssertEqual(r.reason, .closeSecond)
    }

    func testTooFarNeedsTap() {
        let r = MatchDecider.decide(candidates: cands(0.9, 1.5), ocrNumber: "15/198", printingGuess: nil, prices: table)
        XCTAssertTrue(r.needsTap)
        XCTAssertEqual(r.reason, .tooFar)
    }

    func testUnreadableNumberNeedsStrongMargin() {
        XCTAssertTrue(MatchDecider.decide(candidates: cands(0.2, 0.3), ocrNumber: nil, printingGuess: nil, prices: table).needsTap)
        XCTAssertFalse(MatchDecider.decide(candidates: cands(0.1, 0.5), ocrNumber: nil, printingGuess: nil, prices: table).needsTap)
    }

    func testUnclearPrintingLowValueShowsRangeUnflagged() {
        let r = MatchDecider.decide(candidates: cands(0.2, 0.5), ocrNumber: "15", printingGuess: PrintingGuess(printing: .holo, confidence: 0.3), prices: table)
        XCTAssertFalse(r.needsTap)
        XCTAssertNil(r.printing)
        XCTAssertEqual(r.reason, .printingUnclear)
        XCTAssertFalse(r.flagged)
    }

    func testUnclearPrintingAboveValueFloorIsFlagged() {
        let r = MatchDecider.decide(candidates: cands(0.2, 0.5, id: "hit"), ocrNumber: "15", printingGuess: nil, prices: table)
        XCTAssertTrue(r.flagged)
        XCTAssertNil(r.printing)
    }

    func testSinglePrintingCardTakesThatPrinting() {
        let r = MatchDecider.decide(candidates: cands(0.2, 0.5, id: "solo"), ocrNumber: "15", printingGuess: nil, prices: table)
        XCTAssertEqual(r.printing, .holo)
        XCTAssertFalse(r.flagged)
    }

    func testEmpty() {
        XCTAssertTrue(MatchDecider.decide(candidates: [], ocrNumber: nil, printingGuess: nil, prices: table).needsTap)
    }

    func testNormalizeNumber() {
        XCTAssertEqual(MatchDecider.normalizeNumber("015/198"), "15")
        XCTAssertEqual(MatchDecider.normalizeNumber("244"), "244")
        XCTAssertEqual(MatchDecider.normalizeNumber("0"), "0")
        XCTAssertEqual(MatchDecider.normalizeNumber("TG05/TG30"), "TG05")
    }
}

final class RecapTests: XCTestCase {
    func card(_ v: Double, flagged: Bool = false) -> PulledCard {
        PulledCard(cardId: "c", name: "n", setId: "sv1", number: "1", rarity: "Rare", printing: .holo, value: v, flagged: flagged)
    }

    func testRecapMatchesHandCalculation() {
        // Box $40 for 10 packs = $4/pack. Two packs opened.
        var s = PackSession(totalCost: 40, packCount: 10, hitThreshold: 5)
        s.packs = [Pack(setId: "sv1", cards: [card(0.1), card(12.5), card(0.3, flagged: true)]),
                   Pack(setId: "sv1", cards: [card(6.0), card(0.2)]),
                   Pack(setId: "sv1", cards: [])]
        let r = Recapper.recap(s)
        XCTAssertEqual(r.cost, 8.0, accuracy: 1e-9)
        XCTAssertEqual(r.totalValue, 19.1, accuracy: 1e-9)
        XCTAssertEqual(r.net, 11.1, accuracy: 1e-9)
        XCTAssertEqual(r.cardCount, 5)
        XCTAssertEqual(r.hits, 2)
        XCTAssertEqual(r.hitRate, 0.4, accuracy: 1e-9)
        XCTAssertEqual(r.flaggedCount, 1)
        XCTAssertEqual(r.best?.value, 12.5)
    }

    func testEmptySession() {
        let r = Recapper.recap(PackSession(totalCost: 4, packCount: 1))
        XCTAssertEqual(r.cost, 0)
        XCTAssertEqual(r.hitRate, 0)
        XCTAssertNil(r.best)
    }

    func testSessionSurvivesJSONRoundTrip() throws {
        var s = PackSession(totalCost: 4.5, packCount: 1)
        s.packs = [Pack(setId: "sv1", cards: [card(1.5)])]
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(PackSession.self, from: data)
        XCTAssertEqual(back, s)
    }

    func testCSV() {
        var s = PackSession(totalCost: 4, packCount: 1)
        s.packs = [Pack(setId: "sv1", cards: [PulledCard(cardId: "sv1-3", name: "Meowscarada, ex \"big\"", setId: "sv1", number: "15", rarity: "Double Rare", printing: nil, value: 1.4)])]
        let lines = CSVExport.csv(for: s).split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[1].contains("\"Meowscarada, ex \"\"big\"\"\""))
        XCTAssertTrue(lines[1].contains(",unknown,"))
    }
}

final class TrackerAndScoringTests: XCTestCase {
    func testSameCardWithinGapCountsOnce() {
        var t = CardTracker(gap: 1.0)
        XCTAssertTrue(t.observe(cardId: "a", at: 0))
        XCTAssertFalse(t.observe(cardId: "a", at: 0.4))
        XCTAssertFalse(t.observe(cardId: "a", at: 1.2))
        XCTAssertTrue(t.observe(cardId: "b", at: 1.5))
        XCTAssertTrue(t.observe(cardId: "a", at: 1.9))   // a different card in between: a new copy
        XCTAssertTrue(t.observe(cardId: "a", at: 5.0))   // long gap: another copy
    }

    func testSharpBeatsBlurry() {
        let w = 32, h = 32
        var sharp = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h { for x in 0..<w { sharp[y * w + x] = ((x / 2 + y / 2) % 2 == 0) ? 255 : 0 } }
        let flat = [UInt8](repeating: 128, count: w * h)
        XCTAssertGreaterThan(FrameScoring.laplacianVariance(luma: sharp, width: w, height: h),
                             FrameScoring.laplacianVariance(luma: flat, width: w, height: h))
        XCTAssertEqual(FrameScoring.laplacianVariance(luma: flat, width: w, height: h), 0, accuracy: 1e-9)
    }

    func testGlare() {
        XCTAssertEqual(FrameScoring.glareFraction(luma: [255, 255, 0, 0]), 0.5, accuracy: 1e-9)
        XCTAssertGreaterThan(FrameScoring.score(sharpness: 400, glare: 0, fill: 0.8),
                             FrameScoring.score(sharpness: 400, glare: 0.3, fill: 0.8))
    }

    func testSkipRules() {
        XCTAssertTrue(SkipRules.isZeroValue(supertype: "Energy"))
        XCTAssertFalse(SkipRules.isZeroValue(supertype: "Pokémon"))
        XCTAssertTrue(SkipRules.isCodeCard(cardId: "code-card"))
    }
}

final class BestFramePickerTests: XCTestCase {
    func testEmitsBestFrameAfterCardLeaves() {
        var p = BestFramePicker<String>(absentGap: 0.5, maxHold: 4, minFrames: 3)
        XCTAssertNil(p.add(frame: "blur", score: 0.2, at: 0.0))
        XCTAssertNil(p.add(frame: "sharp", score: 0.9, at: 0.1))
        XCTAssertNil(p.add(frame: "glare", score: 0.4, at: 0.2))
        XCTAssertNil(p.add(frame: nil, score: 0, at: 0.4))      // gone for 0.2s: not yet
        XCTAssertEqual(p.add(frame: nil, score: 0, at: 0.8), "sharp")
        XCTAssertNil(p.add(frame: nil, score: 0, at: 1.5))      // nothing more to emit
    }

    func testTwoCardsEmitTwice() {
        var p = BestFramePicker<String>(absentGap: 0.3, maxHold: 4, minFrames: 2)
        _ = p.add(frame: "a1", score: 0.5, at: 0.0)
        _ = p.add(frame: "a2", score: 0.6, at: 0.1)
        XCTAssertEqual(p.add(frame: nil, score: 0, at: 0.5), "a2")
        _ = p.add(frame: "b1", score: 0.7, at: 1.0)
        _ = p.add(frame: "b2", score: 0.3, at: 1.1)
        XCTAssertEqual(p.add(frame: nil, score: 0, at: 1.6), "b1")
    }

    func testTooFewFramesIsNoise() {
        var p = BestFramePicker<String>(absentGap: 0.3, maxHold: 4, minFrames: 3)
        _ = p.add(frame: "flicker", score: 0.9, at: 0.0)
        XCTAssertNil(p.add(frame: nil, score: 0, at: 0.5))
    }

    func testMaxHoldEmitsWhileStillInView() {
        var p = BestFramePicker<String>(absentGap: 0.5, maxHold: 1.0, minFrames: 2)
        _ = p.add(frame: "a", score: 0.4, at: 0.0)
        _ = p.add(frame: "b", score: 0.8, at: 0.5)
        XCTAssertEqual(p.add(frame: "c", score: 0.1, at: 1.0), "b")
    }

    func testFlush() {
        var p = BestFramePicker<String>(absentGap: 0.5, maxHold: 4, minFrames: 2)
        _ = p.add(frame: "a", score: 0.4, at: 0.0)
        _ = p.add(frame: "b", score: 0.5, at: 0.1)
        XCTAssertEqual(p.flush(), "b")
        XCTAssertNil(p.flush())
    }
}
