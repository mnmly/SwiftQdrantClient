import Foundation
import QdrantProtos

// MARK: - Recommend / discover inputs

/// How recommendation combines positive/negative examples.
/// Mirrors Python `models.RecommendStrategy`.
public enum RecommendStrategy: Sendable {
    case averageVector, bestScore, sumScores

    var proto: Qdrant_RecommendStrategy {
        switch self {
        case .averageVector: return .averageVector
        case .bestScore: return .bestScore
        case .sumScores: return .sumScores
        }
    }
}

/// Recommendation input: positive/negative example vectors (or point ids).
/// Mirrors Python `models.RecommendInput`.
public struct RecommendInput: Sendable {
    public var positive: [VectorInput]
    public var negative: [VectorInput]
    public var strategy: RecommendStrategy?

    public init(positive: [VectorInput] = [], negative: [VectorInput] = [],
                strategy: RecommendStrategy? = nil) {
        self.positive = positive
        self.negative = negative
        self.strategy = strategy
    }

    var proto: Qdrant_RecommendInput {
        var r = Qdrant_RecommendInput()
        r.positive = positive.map(\.proto)
        r.negative = negative.map(\.proto)
        if let strategy { r.strategy = strategy.proto }
        return r
    }
}

/// A positive/negative pair for discovery & context search.
/// Mirrors Python `models.ContextPair`.
public struct ContextPair: Sendable {
    public var positive: VectorInput
    public var negative: VectorInput

    public init(positive: VectorInput, negative: VectorInput) {
        self.positive = positive
        self.negative = negative
    }

    var proto: Qdrant_ContextInputPair {
        var p = Qdrant_ContextInputPair()
        p.positive = positive.proto
        p.negative = negative.proto
        return p
    }
}

/// Maximal Marginal Relevance parameters. Mirrors Python `models.Mmr`.
public struct Mmr: Sendable {
    public var diversity: Float?
    public var candidatesLimit: UInt32?

    public init(diversity: Float? = nil, candidatesLimit: UInt32? = nil) {
        self.diversity = diversity
        self.candidatesLimit = candidatesLimit
    }

    var proto: Qdrant_Mmr {
        var m = Qdrant_Mmr()
        if let diversity { m.diversity = diversity }
        if let candidatesLimit { m.candidatesLimit = candidatesLimit }
        return m
    }
}

/// Score-fusion method for combining prefetch results.
/// Mirrors Python `models.Fusion`.
public enum Fusion: Sendable {
    /// Reciprocal Rank Fusion.
    case rrf
    /// Distribution-Based Score Fusion.
    case dbsf

    var proto: Qdrant_Fusion {
        switch self {
        case .rrf: return .rrf
        case .dbsf: return .dbsf
        }
    }
}

// MARK: - Query

/// A query operation. Mirrors Python `models.Query` variants.
public indirect enum Query: Sendable {
    /// Nearest neighbours to a vector (or to an existing point's vector).
    case nearest(VectorInput)
    /// Nearest neighbours re-ranked for diversity (MMR).
    case nearestWithMmr(VectorInput, Mmr)
    /// Recommendation from positive/negative examples.
    case recommend(RecommendInput)
    /// Discovery: steer toward `target` using context pairs.
    case discover(target: VectorInput, context: [ContextPair])
    /// Context search using only context pairs (no target).
    case context([ContextPair])
    /// Order results by a payload field (no vector).
    case orderBy(OrderBy)
    /// Fuse the scores of prefetch branches.
    case fusion(Fusion)
    /// Randomly sample points.
    case sampleRandom
    /// Re-score results with an arbitrary formula expression.
    case formula(Formula)
    /// Refine a target query using scored feedback examples.
    case relevanceFeedback(RelevanceFeedbackInput)

    var proto: Qdrant_Query {
        var q = Qdrant_Query()
        switch self {
        case .nearest(let v):
            q.variant = .nearest(v.proto)
        case .nearestWithMmr(let v, let mmr):
            var n = Qdrant_NearestInputWithMmr()
            n.nearest = v.proto
            n.mmr = mmr.proto
            q.variant = .nearestWithMmr(n)
        case .recommend(let input):
            q.variant = .recommend(input.proto)
        case .discover(let target, let context):
            var d = Qdrant_DiscoverInput()
            d.target = target.proto
            var ctx = Qdrant_ContextInput()
            ctx.pairs = context.map(\.proto)
            d.context = ctx
            q.variant = .discover(d)
        case .context(let pairs):
            var ctx = Qdrant_ContextInput()
            ctx.pairs = pairs.map(\.proto)
            q.variant = .context(ctx)
        case .orderBy(let orderBy):
            q.variant = .orderBy(orderBy.proto)
        case .fusion(let fusion):
            q.variant = .fusion(fusion.proto)
        case .sampleRandom:
            q.variant = .sample(.random)
        case .formula(let f):
            q.variant = .formula(f.proto)
        case .relevanceFeedback(let r):
            q.variant = .relevanceFeedback(r.proto)
        }
        return q
    }
}

// MARK: - Search params

/// Search tuning parameters. Mirrors Python `models.SearchParams`.
public struct SearchParams: Sendable {
    public var hnswEf: UInt64?
    public var exact: Bool?
    public var indexedOnly: Bool?
    /// Per-query quantization controls (ignore / rescore / oversampling).
    public var quantization: QuantizationSearchParams?

    public init(hnswEf: UInt64? = nil, exact: Bool? = nil, indexedOnly: Bool? = nil,
                quantization: QuantizationSearchParams? = nil) {
        self.hnswEf = hnswEf
        self.exact = exact
        self.indexedOnly = indexedOnly
        self.quantization = quantization
    }

    var proto: Qdrant_SearchParams {
        var p = Qdrant_SearchParams()
        if let hnswEf { p.hnswEf = hnswEf }
        if let exact { p.exact = exact }
        if let indexedOnly { p.indexedOnly = indexedOnly }
        if let quantization { p.quantization = quantization.proto }
        return p
    }

    var json: JSONValue {
        var o: [String: JSONValue] = [:]
        if let hnswEf { o["hnsw_ef"] = .int(Int64(hnswEf)) }
        if let exact { o["exact"] = .bool(exact) }
        if let indexedOnly { o["indexed_only"] = .bool(indexedOnly) }
        if let quantization { o["quantization"] = quantization.json }
        return .object(o)
    }
}

// MARK: - Prefetch

/// A prefetch sub-query, used to build hybrid / multi-stage queries.
/// Mirrors Python `models.Prefetch`.
public struct Prefetch: Sendable {
    public var query: Query?
    public var using: String?
    public var filter: Filter?
    public var params: SearchParams?
    public var scoreThreshold: Float?
    public var limit: UInt64?
    public var prefetch: [Prefetch]

    public init(
        query: Query? = nil,
        using: String? = nil,
        filter: Filter? = nil,
        params: SearchParams? = nil,
        scoreThreshold: Float? = nil,
        limit: UInt64? = nil,
        prefetch: [Prefetch] = []
    ) {
        self.query = query
        self.using = using
        self.filter = filter
        self.params = params
        self.scoreThreshold = scoreThreshold
        self.limit = limit
        self.prefetch = prefetch
    }

    var proto: Qdrant_PrefetchQuery {
        var p = Qdrant_PrefetchQuery()
        if let query { p.query = query.proto }
        if let using { p.using = using }
        if let filter { p.filter = filter.proto }
        if let params { p.params = params.proto }
        if let scoreThreshold { p.scoreThreshold = scoreThreshold }
        if let limit { p.limit = limit }
        p.prefetch = prefetch.map(\.proto)
        return p
    }
}
