#if DEBUG
import Foundation
import Observation
import SwiftUI

/// Xcode builds only: change how the car handles from inside the race, to tune it before it ships. Changes take effect
/// at once and survive a relaunch. A tuned car isn't the one the boards are for (`RaceTuning.isStock`), so its laps
/// keep their own best lap and never reach a leaderboard or the lap service.
@Observable
final class Tuner {
    struct Knob: Identifiable {
        let id: String
        let name: String
        let note: String
        let range: ClosedRange<Double>
        let step: Double
        fileprivate let read: () -> Double
        fileprivate let write: (Double) -> Void

        func format(_ value: Double) -> String {
            String(format: step < 1 ? "%.1f" : "%.0f", value)
        }
    }

    /// The constants that shape the steering and how straightness turns into speed: the ones worth feeling for.
    static let knobs: [Knob] = [
        Knob(id: "steerRate", name: "Steering", note: "How fast the nose swings (rad/s)", range: 1...4, step: 0.1,
             read: { RaceTuning.steerRate }, write: { RaceTuning.steerRate = $0 }),
        Knob(id: "steerReturn", name: "Return", note: "How hard it pulls back straight (/s)", range: 1...8, step: 0.1,
             read: { RaceTuning.steerReturn }, write: { RaceTuning.steerReturn = $0 }),
        Knob(id: "straightnessLength", name: "Smoothing", note: "Longer forgives small corrections", range: 40...200,
             step: 5, read: { RaceTuning.straightnessLength }, write: { RaceTuning.straightnessLength = $0 }),
        Knob(id: "grip", name: "Grip", note: "Higher is faster through corners", range: 300...800, step: 10,
             read: { RaceTuning.grip }, write: { RaceTuning.grip = $0 }),
        Knob(id: "acceleration", name: "Acceleration", note: "How much a slow exit costs", range: 150...450, step: 10,
             read: { RaceTuning.acceleration }, write: { RaceTuning.acceleration = $0 }),
    ]

    static let shared = Tuner()

    /// The knobs as released.
    let stock: [String: Double]
    let stockHandling = RaceTuning.Handling.current
    private(set) var values: [String: Double]
    /// Goes up with every change, so the race knows to start over on the new car.
    private(set) var version = 0
    @ObservationIgnored private let store: UserDefaults
    @ObservationIgnored private let key = "apex.tuner.v1"

    init(defaults store: UserDefaults = .standard) {
        self.store = store
        stock = Dictionary(uniqueKeysWithValues: Self.knobs.map { ($0.id, $0.read()) })
        values = stock
    }

    /// Puts back the last session's tuning, at launch. Tests always run on the stock car.
    func restore() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              let saved = store.dictionary(forKey: key) as? [String: Double] else { return }
        for knob in Self.knobs {
            if let value = saved[knob.id] { apply(value, to: knob) }
        }
        version += 1
    }

    func value(of knob: Knob) -> Double { values[knob.id] ?? knob.read() }

    func set(_ value: Double, for knob: Knob) {
        let before = self.value(of: knob)
        apply(value, to: knob)
        guard self.value(of: knob) != before else { return }
        version += 1
        store.set(values, forKey: key)
    }

    func resetToStock() {
        guard values != stock else { return }
        for knob in Self.knobs { apply(stock[knob.id] ?? knob.read(), to: knob) }
        version += 1
        store.removeObject(forKey: key)
    }

    private func apply(_ value: Double, to knob: Knob) {
        let stepped = ((value - knob.range.lowerBound) / knob.step).rounded() * knob.step + knob.range.lowerBound
        let clamped = min(max(stepped, knob.range.lowerBound), knob.range.upperBound)
        knob.write(clamped)
        values[knob.id] = clamped
    }
}

/// Bot laps on one circuit, as in `LapTimeTests` and the README's table: the flying laps' average for each driver.
struct BotLaps: Equatable {
    var perfect: Double
    var skilled: Double
    var middle: Double
    var sloppy: Double

    static let drivers: [(name: String, lap: KeyPath<BotLaps, Double>)] = [
        ("Perfect, ideal line", \.perfect),
        ("~90 ms, ideal line", \.skilled),
        ("~90 ms, middle", \.middle),
        ("Sloppy, middle", \.sloppy),
    ]

    init(track: Track, line: RacingLine, handling: RaceTuning.Handling) {
        let ideal: (Double) -> Double = { line.offset(at: $0) }
        func lap(_ driver: AutoDriver) -> Double {
            let session = RaceSession(track: track, handling: handling)
            var driver = driver
            var times: [Double] = []
            session.start()
            while times.count < 3, session.clock < 200 {
                for case .timing(.lap(let lap)) in session.advance(by: RaceTuning.physicsStep, control: {
                    driver.decide($0)
                }) {
                    times.append(lap.time)
                }
            }
            // The first lap starts from rest.
            let flying = times.dropFirst()
            return flying.isEmpty ? .infinity : flying.reduce(0, +) / Double(flying.count)
        }
        perfect = lap(AutoDriver(line: ideal))
        skilled = lap(AutoDriver(line: ideal, decisionInterval: 0.09, hesitation: 0.04))
        middle = lap(AutoDriver(line: { _ in 0 }, decisionInterval: 0.09, hesitation: 0.04))
        sloppy = lap(AutoDriver(line: { _ in 0 }, decisionInterval: 0.12, tolerance: 30, hesitation: 0.08))
    }
}

/// Times bot laps on one circuit off the main thread, for a car as tuned and for the stock car. Each run drives its own
/// copy of the handling, so sliders moving meanwhile don't touch it. Only the latest request's answer is delivered, on
/// the main thread.
final class BotStopwatch {
    private let track: Track
    private let queue = DispatchQueue(label: "apex.tuner", qos: .userInitiated)
    /// Built on `queue` the first time they're needed.
    private var line: RacingLine?
    private var stockLaps: BotLaps?
    private var request = 0

    init(track: Track) {
        self.track = track
    }

    func time(_ handling: RaceTuning.Handling, stock: RaceTuning.Handling,
              completion: @escaping (_ laps: BotLaps, _ stock: BotLaps) -> Void) {
        request += 1
        let id = request
        let track = self.track
        queue.async { [weak self] in
            guard let self else { return }
            if line == nil { line = RacingLine(track: track) }
            guard let line else { return }
            let stockLaps = self.stockLaps ?? BotLaps(track: track, line: line, handling: stock)
            self.stockLaps = stockLaps
            let laps = handling == stock ? stockLaps : BotLaps(track: track, line: line, handling: handling)
            DispatchQueue.main.async {
                guard id == self.request else { return }
                completion(laps, stockLaps)
            }
        }
    }

    /// Drops the answer to any request still running.
    func cancel() {
        request += 1
    }
}

/// The tuning panel: a slider per knob, and what the bots lap in on this circuit with the car as tuned, against the
/// car as released.
struct TunerPanel: View {
    let tuner: Tuner
    let trackName: String
    let laps: BotLaps?
    let stockLaps: BotLaps?
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("TUNE CONTROLS")
                    .font(.system(size: 22, weight: .black, design: .rounded).italic())
                Text("XCODE BUILDS ONLY")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.15), in: Capsule())
                Spacer()
                Button("RESET") { tuner.resetToStock() }
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .disabled(RaceTuning.isStock)
                    .opacity(RaceTuning.isStock ? 0.35 : 1)
                    .padding(.trailing, 6)
                Button(action: onDone) {
                    Text("DONE")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 7)
                        .background(Color(red: 0.9, green: 0.12, blue: 0.1), in: Capsule())
                }
            }
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Tuner.knobs) { knob in
                        KnobRow(tuner: tuner, knob: knob)
                    }
                    Text(settling)
                        .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                        .opacity(0.7)
                }
                .frame(maxWidth: .infinity)
                botTable
                    .frame(width: 210, alignment: .leading)
            }
        }
        .padding(16)
        .frame(maxWidth: 720)
        .background(Color(white: 0.07).opacity(0.96), in: RoundedRectangle(cornerRadius: 18))
        .foregroundStyle(.white)
    }

    /// Holding settles the nose at steerRate / steerReturn, about 1 / steerReturn seconds after a change.
    private var settling: String {
        let angle = RaceTuning.steerRate / RaceTuning.steerReturn * 180 / .pi
        return String(format: "Holding settles %.0f° off the track's direction, most of the way there in %.2f s.",
                      angle, 1 / RaceTuning.steerReturn)
    }

    private var botTable: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("BOT LAPS · \(trackName.uppercased())")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .opacity(0.7)
            ForEach(BotLaps.drivers, id: \.name) { driver in
                HStack(alignment: .firstTextBaseline) {
                    Text(driver.name)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Spacer()
                    if let laps {
                        let time = laps[keyPath: driver.lap]
                        Text(LapFormat.time(time, decimals: 2))
                            .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                        if let stock = stockLaps?[keyPath: driver.lap], !RaceTuning.isStock {
                            Text(LapFormat.delta(time - stock, decimals: 2))
                                .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(time <= stock ? Color(red: 0.3, green: 0.9, blue: 0.45)
                                                               : Color(red: 1, green: 0.38, blue: 0.32))
                                .frame(width: 42, alignment: .trailing)
                        }
                    } else {
                        ProgressView().controlSize(.mini).tint(.white)
                    }
                }
            }
            Text(RaceTuning.isStock
                 ? "Stock car. The game aims for a middle-of-the-road lap near 30 s."
                 : "Tuned car: its laps keep their own best lap and stay off the leaderboards and lap service.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .opacity(0.6)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }
}

/// One knob: its name and value, a slider, and what it does.
private struct KnobRow: View {
    let tuner: Tuner
    let knob: Tuner.Knob

    var body: some View {
        let value = tuner.value(of: knob)
        let stock = tuner.stock[knob.id] ?? value
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(knob.name.uppercased())
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                Text(knob.note)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .opacity(0.55)
                Spacer()
                Text(knob.format(value))
                    .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(value == stock ? .white : Color(red: 1, green: 0.62, blue: 0.1))
                if value != stock {
                    Text("stock \(knob.format(stock))")
                        .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                        .opacity(0.55)
                }
            }
            Slider(value: Binding(get: { value }, set: { tuner.set($0, for: knob) }), in: knob.range,
                   step: knob.step)
                .tint(Color(red: 1, green: 0.62, blue: 0.1))
                .controlSize(.small)
        }
    }
}
#endif
