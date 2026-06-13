import Foundation
import QdrantProtos

// MARK: - WithPayload

/// Selects which payload to return. Mirrors Python's
/// `bool | Sequence[str] | PayloadSelector`.
///
/// Expressible by `true`/`false` and by an array literal of field names, so
/// `withPayload: true` and `withPayload: ["city", "country"]` both work.
public enum WithPayload: Sendable, ExpressibleByBooleanLiteral, ExpressibleByArrayLiteral {
    case bool(Bool)
    /// Return only these payload fields.
    case include([String])
    /// Return all payload fields except these.
    case exclude([String])

    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(arrayLiteral elements: String...) { self = .include(elements) }

    var proto: Qdrant_WithPayloadSelector {
        var s = Qdrant_WithPayloadSelector()
        switch self {
        case .bool(let b): s.selectorOptions = .enable(b)
        case .include(let f):
            var inc = Qdrant_PayloadIncludeSelector(); inc.fields = f
            s.selectorOptions = .include(inc)
        case .exclude(let f):
            var exc = Qdrant_PayloadExcludeSelector(); exc.fields = f
            s.selectorOptions = .exclude(exc)
        }
        return s
    }

    var restJSON: JSONValue {
        switch self {
        case .bool(let b): return .bool(b)
        case .include(let f): return .array(f.map(JSONValue.string))
        case .exclude(let f): return .object(["exclude": .array(f.map(JSONValue.string))])
        }
    }

    /// Apply the selection to a stored payload (used by the local backend).
    func apply(_ payload: Payload) -> Payload {
        switch self {
        case .bool(let b): return b ? payload : [:]
        case .include(let f):
            let keep = Set(f); return payload.filter { keep.contains($0.key) }
        case .exclude(let f):
            let drop = Set(f); return payload.filter { !drop.contains($0.key) }
        }
    }
}

// MARK: - WithVectors

/// Selects which vectors to return. Mirrors Python's `bool | Sequence[str]`.
///
/// Expressible by `true`/`false` and by an array literal of vector names.
public enum WithVectors: Sendable, ExpressibleByBooleanLiteral, ExpressibleByArrayLiteral {
    case bool(Bool)
    /// Return only these named vectors.
    case names([String])

    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(arrayLiteral elements: String...) { self = .names(elements) }

    var proto: Qdrant_WithVectorsSelector {
        var s = Qdrant_WithVectorsSelector()
        switch self {
        case .bool(let b): s.selectorOptions = .enable(b)
        case .names(let n):
            var sel = Qdrant_VectorsSelector(); sel.names = n
            s.selectorOptions = .include(sel)
        }
        return s
    }

    var restJSON: JSONValue {
        switch self {
        case .bool(let b): return .bool(b)
        case .names(let n): return .array(n.map(JSONValue.string))
        }
    }

    /// Whether any vectors are requested (used by the local backend).
    var isEnabled: Bool {
        switch self { case .bool(let b): return b; case .names: return true }
    }
    /// Filter a stored vectors dict to the requested names (used by the local backend).
    func apply(_ vectors: [String: VectorData]) -> [String: VectorData] {
        switch self {
        case .bool(let b): return b ? vectors : [:]
        case .names(let n): let keep = Set(n); return vectors.filter { keep.contains($0.key) }
        }
    }
}

// MARK: - OrderValue

/// The value a point was ordered by (when an `OrderBy` query/scroll was used).
/// Mirrors Python `models.OrderValue`.
public enum OrderValue: Sendable, Equatable {
    case int(Int64)
    case float(Double)

    init?(_ proto: Qdrant_OrderValue) {
        switch proto.variant {
        case .int(let i): self = .int(i)
        case .float(let f): self = .float(f)
        case .none: return nil
        }
    }
}
