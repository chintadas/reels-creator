import XCTest
@testable import ReelsCreatorCore

final class BeatOnsetDetectorTests: XCTestCase {
    func testDetectsSyntheticRmsPeaks() {
        var energies = Array(repeating: 0.1, count: 40)
        let timestamps = (0..<40).map { Double($0) * 0.05 }

        // Inject two distinct peaks at index 10 (0.50s) and index 25 (1.25s).
        energies[10] = 0.85
        energies[25] = 0.95

        let beats = BeatOnsetDetector.detectOnsets(
            energies: energies,
            timestamps: timestamps,
            cooldownSeconds: 0.35
        )

        XCTAssertEqual(beats.count, 2)
        XCTAssertEqual(beats[0], 0.50, accuracy: 0.0001)
        XCTAssertEqual(beats[1], 1.25, accuracy: 0.0001)
    }

    func testCooldownFiltersRapidDoublePeaks() {
        var energies = Array(repeating: 0.05, count: 30)
        let timestamps = (0..<30).map { Double($0) * 0.05 }

        // Peak at 0.50s, then another spike 0.15s later at 0.65s (inside 0.35s cooldown),
        // then another valid peak at 1.00s (0.50s after first).
        energies[10] = 0.9
        energies[13] = 0.95
        energies[20] = 0.9

        let beats = BeatOnsetDetector.detectOnsets(
            energies: energies,
            timestamps: timestamps,
            cooldownSeconds: 0.35
        )

        XCTAssertEqual(beats.count, 2)
        XCTAssertEqual(beats[0], 0.50, accuracy: 0.0001)
        XCTAssertEqual(beats[1], 1.00, accuracy: 0.0001)
    }

    func testReturnsEmptyForInvalidInputs() {
        XCTAssertEqual(BeatOnsetDetector.detectOnsets(energies: [], timestamps: []), [])
        XCTAssertEqual(BeatOnsetDetector.detectOnsets(energies: [0.0, 0.0, 0.0], timestamps: [0.0, 0.05, 0.10]), [])
        XCTAssertEqual(BeatOnsetDetector.detectOnsets(energies: [0.5, 0.8], timestamps: [0.0]), [])
    }

    func testGlobalPeakThresholdIgnoresLowLevelNoise() {
        var energies = Array(repeating: 0.01, count: 30)
        let timestamps = (0..<30).map { Double($0) * 0.05 }

        // Small noise spike (0.05) next to dominant peak (1.0):
        // 0.05 <= 1.0 * 0.12 (0.12), so only the real peak at index 20 (1.00s) is detected.
        energies[5] = 0.05
        energies[20] = 1.0

        let beats = BeatOnsetDetector.detectOnsets(
            energies: energies,
            timestamps: timestamps,
            cooldownSeconds: 0.35
        )

        XCTAssertEqual(beats.count, 1)
        XCTAssertEqual(beats[0], 1.00, accuracy: 0.0001)
    }
}
