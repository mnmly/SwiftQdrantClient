import Foundation
import QdrantProtos

// MARK: - Expression

/// A scoring expression for formula queries. Mirrors Python `models.Expression`.
///
/// Built recursively from constants, payload variables, conditions, arithmetic,
/// geo distance, and decay functions.
public indirect enum Expression: Sendable {
    case constant(Float)
    /// A payload field or a special score variable (e.g. `"$score"`).
    case variable(String)
    /// 1.0 if the condition matches the point, else 0.0.
    case condition(Condition)
    /// Geographic distance (metres) from `origin` to the point's `key` geo field.
    case geoDistance(origin: GeoPoint, key: String)
    /// Parse an RFC-3339 datetime constant to a timestamp.
    case datetime(String)
    /// Treat a payload `key` as a datetime and use its timestamp.
    case datetimeKey(String)
    case mult([Expression])
    case sum([Expression])
    case div(left: Expression, right: Expression, byZeroDefault: Float? = nil)
    case neg(Expression)
    case abs(Expression)
    case sqrt(Expression)
    case pow(base: Expression, exponent: Expression)
    case exp(Expression)
    case log10(Expression)
    case ln(Expression)
    case expDecay(DecayParams)
    case gaussDecay(DecayParams)
    case linDecay(DecayParams)

    var proto: Qdrant_Expression {
        var e = Qdrant_Expression()
        switch self {
        case .constant(let v): e.constant = v
        case .variable(let s): e.variable = s
        case .condition(let c): e.condition = c.proto
        case .geoDistance(let origin, let key):
            var g = Qdrant_GeoDistance(); g.origin = origin.proto; g.to = key
            e.geoDistance = g
        case .datetime(let s): e.datetime = s
        case .datetimeKey(let s): e.datetimeKey = s
        case .mult(let xs):
            var m = Qdrant_MultExpression(); m.mult = xs.map(\.proto); e.mult = m
        case .sum(let xs):
            var s = Qdrant_SumExpression(); s.sum = xs.map(\.proto); e.sum = s
        case .div(let l, let r, let dz):
            var d = Qdrant_DivExpression(); d.left = l.proto; d.right = r.proto
            if let dz { d.byZeroDefault = dz }
            e.div = d
        case .neg(let x): e.neg = x.proto
        case .abs(let x): e.abs = x.proto
        case .sqrt(let x): e.sqrt = x.proto
        case .pow(let b, let ex):
            var p = Qdrant_PowExpression(); p.base = b.proto; p.exponent = ex.proto; e.pow = p
        case .exp(let x): e.exp = x.proto
        case .log10(let x): e.log10 = x.proto
        case .ln(let x): e.ln = x.proto
        case .expDecay(let p): e.expDecay = p.proto
        case .gaussDecay(let p): e.gaussDecay = p.proto
        case .linDecay(let p): e.linDecay = p.proto
        }
        return e
    }

    var json: JSONValue {
        switch self {
        case .constant(let v): return .double(Double(v))
        case .variable(let s): return .string(s)
        case .condition(let c): return c.json
        case .geoDistance(let origin, let key):
            return .object(["geo_distance": .object([
                "origin": .object(["lat": .double(origin.lat), "lon": .double(origin.lon)]),
                "to": .string(key)])])
        case .datetime(let s): return .object(["datetime": .string(s)])
        case .datetimeKey(let s): return .object(["datetime_key": .string(s)])
        case .mult(let xs): return .object(["mult": .array(xs.map(\.json))])
        case .sum(let xs): return .object(["sum": .array(xs.map(\.json))])
        case .div(let l, let r, let dz):
            var o: [String: JSONValue] = ["left": l.json, "right": r.json]
            if let dz { o["by_zero_default"] = .double(Double(dz)) }
            return .object(["div": .object(o)])
        case .neg(let x): return .object(["neg": x.json])
        case .abs(let x): return .object(["abs": x.json])
        case .sqrt(let x): return .object(["sqrt": x.json])
        case .pow(let b, let e): return .object(["pow": .object(["base": b.json, "exponent": e.json])])
        case .exp(let x): return .object(["exp": x.json])
        case .log10(let x): return .object(["log10": x.json])
        case .ln(let x): return .object(["ln": x.json])
        case .expDecay(let p): return .object(["exp_decay": p.json])
        case .gaussDecay(let p): return .object(["gauss_decay": p.json])
        case .linDecay(let p): return .object(["lin_decay": p.json])
        }
    }
}

/// Decay-function parameters. Mirrors Python `models.DecayParamsExpression`.
public struct DecayParams: Sendable {
    public var x: Expression?
    public var target: Expression?
    public var scale: Float?
    public var midpoint: Float?

    public init(x: Expression? = nil, target: Expression? = nil,
                scale: Float? = nil, midpoint: Float? = nil) {
        self.x = x; self.target = target; self.scale = scale; self.midpoint = midpoint
    }

    var proto: Qdrant_DecayParamsExpression {
        var d = Qdrant_DecayParamsExpression()
        if let x { d.x = x.proto }
        if let target { d.target = target.proto }
        if let scale { d.scale = scale }
        if let midpoint { d.midpoint = midpoint }
        return d
    }
    var json: JSONValue {
        var o: [String: JSONValue] = [:]
        if let x { o["x"] = x.json }
        if let target { o["target"] = target.json }
        if let scale { o["scale"] = .double(Double(scale)) }
        if let midpoint { o["midpoint"] = .double(Double(midpoint)) }
        return .object(o)
    }
}

/// A score-formula query body. Mirrors Python `models.FormulaQuery`.
public struct Formula: Sendable {
    public var expression: Expression
    /// Default values for variables referenced but absent from a point's payload.
    public var defaults: Payload

    public init(_ expression: Expression, defaults: Payload = [:]) {
        self.expression = expression
        self.defaults = defaults
    }

    var proto: Qdrant_Formula {
        var f = Qdrant_Formula()
        f.expression = expression.proto
        f.defaults = defaults.proto
        return f
    }
    var json: JSONValue {
        var o: [String: JSONValue] = ["formula": expression.json]
        if !defaults.isEmpty { o["defaults"] = defaults.json }
        return .object(o)
    }
}

// MARK: - Relevance feedback

/// One feedback example for a relevance-feedback query.
/// Mirrors Python `models.FeedbackItem`.
public struct FeedbackItem: Sendable {
    public var example: VectorInput
    public var score: Float
    public init(example: VectorInput, score: Float) {
        self.example = example; self.score = score
    }
    var proto: Qdrant_FeedbackItem {
        var f = Qdrant_FeedbackItem(); f.example = example.proto; f.score = score; return f
    }
    var json: JSONValue { .object(["example": example.json, "score": .double(Double(score))]) }
}

/// Relevance-feedback query input: a target plus scored feedback examples.
/// Mirrors Python `models.RelevanceFeedbackInput`.
public struct RelevanceFeedbackInput: Sendable {
    public var target: VectorInput
    public var feedback: [FeedbackItem]

    public init(target: VectorInput, feedback: [FeedbackItem] = []) {
        self.target = target; self.feedback = feedback
    }

    var proto: Qdrant_RelevanceFeedbackInput {
        var r = Qdrant_RelevanceFeedbackInput()
        r.target = target.proto
        r.feedback = feedback.map(\.proto)
        var strategy = Qdrant_FeedbackStrategy()
        strategy.naive = Qdrant_NaiveFeedbackStrategy()
        r.strategy = strategy
        return r
    }
    var json: JSONValue {
        .object([
            "target": target.json,
            "feedback": .array(feedback.map(\.json)),
            "strategy": .string("naive"),
        ])
    }
}
