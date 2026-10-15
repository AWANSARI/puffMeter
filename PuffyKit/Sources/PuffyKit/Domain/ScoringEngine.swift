import Foundation

/// Maps raw, IPD-normalized face metrics to a 0–100 Puffiness Score (lower is better).
///
/// This is a cosmetic, personal-relative estimate. 30 is roughly the user's typical good
/// day; each personal standard deviation above that adds 15 points. The engine is pure and
/// deterministic so the same metrics always produce the same score.
public enum ScoringEngine {
    public static let zoneWeights: [FaceZone: Double] = [.underEyes: 0.40, .cheeks: 0.30, .jawline: 0.30]
    public static let typicalScore = 30.0
    public static let pointsPerSpread = 15.0
    /// Below this quality composite a score is flagged as lower confidence.
    public static let lowConfidenceThreshold = 0.6
    /// Personal statistics are trusted only once this many scans exist.
    public static let minimumHistoryForPersonalSpread = 7
    public static let historyWindow = 30
    public static let referencePercentile = 0.20

    /// Floor for each zone's spread so early scores don't swing wildly. Units are the
    /// analyzer's IPD-normalized measurements; calibrate alongside `FaceAnalyzer`.
    public static let minimumSpread: [FaceZone: Double] = [.underEyes: 0.012, .cheeks: 0.015, .jawline: 0.015]

    public struct ZoneReference: Hashable, Sendable {
        public var center: Double
        public var spread: Double
        public init(center: Double, spread: Double) {
            self.center = center
            self.spread = spread
        }
    }

    public struct Reference: Hashable, Sendable {
        public var zones: [FaceZone: ZoneReference]
        public init(zones: [FaceZone: ZoneReference]) { self.zones = zones }
    }

    public struct Result: Hashable, Sendable {
        public var zones: ZoneScores
        public var overall: Int
        public var lowConfidence: Bool
    }

    /// Builds the personal reference. Until enough history exists, the baseline scan is the
    /// center and the minimum spread is used; afterwards the 20th percentile of the last 30
    /// scans ("least puffy typical state") is the center.
    public static func reference(baseline: RawFaceMetrics, history: [RawFaceMetrics]) -> Reference {
        let recent = Array(history.suffix(historyWindow))
        var zones: [FaceZone: ZoneReference] = [:]
        for zone in FaceZone.allCases {
            let floor = minimumSpread[zone] ?? 0.015
            if recent.count < minimumHistoryForPersonalSpread {
                zones[zone] = ZoneReference(center: baseline.value(for: zone), spread: floor)
            } else {
                let values = recent.map { $0.value(for: zone) }
                zones[zone] = ZoneReference(center: percentile(values, referencePercentile),
                                            spread: max(standardDeviation(values), floor))
            }
        }
        return Reference(zones: zones)
    }

    public static func zoneScore(raw: Double, reference: ZoneReference) -> Int {
        let z = (raw - reference.center) / reference.spread
        return Int((typicalScore + pointsPerSpread * z).rounded()).clamped(to: 0...100)
    }

    public static func overall(_ zones: ZoneScores) -> Int {
        let total = FaceZone.allCases.reduce(0.0) { sum, zone in
            sum + Double(zones.value(for: zone)) * (zoneWeights[zone] ?? 0)
        }
        return Int(total.rounded()).clamped(to: 0...100)
    }

    public static func score(raw: RawFaceMetrics, quality: ScanQuality, reference: Reference) -> Result {
        func zone(_ z: FaceZone) -> Int {
            let ref = reference.zones[z] ?? ZoneReference(center: raw.value(for: z), spread: 1)
            return zoneScore(raw: raw.value(for: z), reference: ref)
        }
        let zones = ZoneScores(underEyes: zone(.underEyes), cheeks: zone(.cheeks), jawline: zone(.jawline))
        return Result(zones: zones, overall: overall(zones),
                      lowConfidence: quality.composite < lowConfidenceThreshold)
    }

    // MARK: Statistics

    static func percentile(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let position = p * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = Int(position.rounded(.up))
        let fraction = position - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
    }

    static func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count - 1)
        return variance.squareRoot()
    }
}
