import AppKit

/// `Blinders --shake-bench`: scores detector settings against simulated input.
/// Hits = share of deliberate shakes caught. False toggles = fires per hour of
/// ordinary mouse use. Seeded, so runs are reproducible. Synthetic, not recorded.
enum ShakeBench {
    typealias Sample = (x: CGFloat, y: CGFloat, t: Double)
    static let hz = 120.0

    struct SplitMix: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// amp = peak-to-peak travel (pt), freq = full cycles per second.
    struct Kind { let name: String; let amp: ClosedRange<Double>; let freq: ClosedRange<Double>; let cycles: ClosedRange<Double> }
    static let kinds = [
        Kind(name: "gentle", amp: 40...80, freq: 3...4.5, cycles: 1.5...2.5),
        Kind(name: "normal", amp: 80...160, freq: 3...5, cycles: 2...3.5),
        Kind(name: "vigorous", amp: 160...300, freq: 4...6.5, cycles: 2.5...5),
    ]

    static func shake(_ k: Kind, rng: inout SplitMix) -> [Sample] {
        let amp = Double.random(in: k.amp, using: &rng)
        let f = Double.random(in: k.freq, using: &rng)
        let dur = Double.random(in: k.cycles, using: &rng) / f
        let vertical = Bool.random(using: &rng)
        let cx = Double.random(in: 300...1500, using: &rng), cy = Double.random(in: 200...900, using: &rng)
        let driftX = Double.random(in: -60...60, using: &rng), driftY = Double.random(in: -60...60, using: &rng)
        let wobble = Double.random(in: 0...(2 * .pi), using: &rng)
        var out: [Sample] = []
        for i in 0...Int(dur * hz) {
            let t = Double(i) / hz
            // Legs vary ±20% in size, the way a hand does.
            let s = amp / 2 * (1 + 0.2 * sin(2 * .pi * 0.7 * f * t + wobble)) * sin(2 * .pi * f * t)
            let ox = driftX * t / dur + Double.random(in: -2...2, using: &rng)
            let oy = driftY * t / dur + Double.random(in: -2...2, using: &rng)
            out.append((CGFloat(vertical ? cx + ox : cx + s + ox), CGFloat(vertical ? cy + s + oy : cy + oy), t))
        }
        return out
    }

    /// Point-and-click with overshoot, target hunting, text-selection scrubs,
    /// scrollbar drags, and idle fidgets, separated by pauses.
    static func ordinaryUse(seconds: Double, rng: inout SplitMix) -> [Sample] {
        var out: [Sample] = []
        var x = 900.0, y = 580.0, t = 0.0
        func r(_ range: ClosedRange<Double>) -> Double { Double.random(in: range, using: &rng) }
        func move(_ tx: Double, _ ty: Double, _ duration: Double) {
            let sx = x, sy = y
            let steps = max(2, Int(duration * hz))
            for i in 1...steps {
                let p = Double(i) / Double(steps)
                let e = 10 * pow(p, 3) - 15 * pow(p, 4) + 6 * pow(p, 5)   // minimum-jerk
                x = sx + (tx - sx) * e + r(-0.7...0.7)
                y = sy + (ty - sy) * e + r(-0.7...0.7)
                t += 1 / hz
                out.append((CGFloat(x), CGFloat(y), t))
            }
        }
        while t < seconds {
            let pick = r(0...1)
            if pick < 0.60 {
                let tx = r(0...1800), ty = r(0...1169)
                let d = max(hypot(tx - x, ty - y), 1)
                let dur = 0.15 + 0.12 * log2(d / 20 + 1)
                if r(0...1) < 0.35 {
                    let over = r(5...40)
                    move(tx + (tx - x) / d * over, ty + (ty - y) / d * over, dur)
                    move(tx, ty, r(0.08...0.2))
                } else {
                    move(tx, ty, dur)
                }
            } else if pick < 0.75 {
                for _ in 0..<Int.random(in: 2...4, using: &rng) { move(x + r(-30...30), y + r(-15...15), r(0.08...0.2)) }
            } else if pick < 0.87 {
                let len = r(100...400)
                for k in 0..<Int.random(in: 2...4, using: &rng) { move(x + (k % 2 == 0 ? len : -len), y + r(-5...5), r(0.3...0.8)) }
            } else if pick < 0.95 {
                let len = r(150...600)
                for k in 0..<Int.random(in: 1...3, using: &rng) { move(x + r(-10...10), y + (k % 2 == 0 ? len : -len), r(0.25...0.6)) }
            } else {
                let len = r(30...120)
                let vert = Bool.random(using: &rng)
                for k in 0..<Int.random(in: 2...4, using: &rng) {
                    let s = k % 2 == 0 ? len : -len
                    move(x + (vert ? 0 : s), y + (vert ? s : 0), r(0.12...0.25))
                }
            }
            t += r(0.1...2.5)
        }
        return out
    }

    struct Config { let minLeg: CGFloat; let turns: Int; let window: Double; var maxLeg: Double = .infinity }

    static func detector(_ c: Config) -> ShakeDetector {
        var d = ShakeDetector()
        d.minLeg = c.minLeg
        d.requiredTurns = c.turns
        d.window = c.window
        d.maxLegTime = c.maxLeg
        return d
    }

    static func score(_ c: Config, shakes: [[[Sample]]], ordinary: [Sample], hours: Double) -> (hits: [Double], falsePerHour: Double) {
        let hits = shakes.map { trials -> Double in
            let caught = trials.filter { samples in
                var d = detector(c)
                return samples.contains { d.feed(x: $0.x, y: $0.y, t: $0.t) }
            }.count
            return Double(caught) / Double(trials.count)
        }
        var d = detector(c)
        let fires = ordinary.reduce(0) { $0 + (d.feed(x: $1.x, y: $1.y, t: $1.t) ? 1 : 0) }
        return (hits, Double(fires) / hours)
    }

    static func run() -> Int32 {
        var rng = SplitMix(state: 2026_11_18)
        let shakes = kinds.map { k in (0..<600).map { _ in shake(k, rng: &rng) } }
        let hours = 20.0
        let ordinary = ordinaryUse(seconds: hours * 3600, rng: &rng)

        print("Presets (4 turns, 0.6 s window, legs <= 0.3 s)")
        for p in ShakeSensitivity.allCases {
            let c = Config(minLeg: p.minLeg, turns: 4, window: 0.6, maxLeg: 0.3)
            let s = score(c, shakes: shakes, ordinary: ordinary, hours: hours)
            print(String(format: "%-6@ | gentle %3.0f%%  normal %3.0f%%  vigorous %3.0f%% | false/hr %.2f",
                         p.title, s.hits[0] * 100, s.hits[1] * 100, s.hits[2] * 100, s.falsePerHour))
        }
        print("")
        print("minLeg turns window maxLeg | gentle normal vigorous | false/hr")
        for minLeg in [20, 25, 35, 50, 70] as [CGFloat] {
            for turns in [3, 4] {
                for maxLeg in [0.2, 0.25, 0.3, Double.infinity] {
                    let c = Config(minLeg: minLeg, turns: turns, window: 0.6, maxLeg: maxLeg)
                    let s = score(c, shakes: shakes, ordinary: ordinary, hours: hours)
                    print(String(format: "%6.0f %5d %6.1f %6.2f | %5.0f%% %5.0f%% %7.0f%% | %7.2f",
                                 minLeg, turns, c.window, maxLeg, s.hits[0] * 100, s.hits[1] * 100, s.hits[2] * 100, s.falsePerHour))
                }
            }
        }
        return 0
    }
}
