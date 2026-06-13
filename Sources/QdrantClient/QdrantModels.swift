import Foundation
import QdrantProtos

// MARK: - Distance

/// Distance metric for vector similarity. Mirrors Python `models.Distance`.
public enum Distance: Sendable {
    case cosine
    case euclid
    case dot
    case manhattan

    var proto: Qdrant_Distance {
        switch self {
        case .cosine: return .cosine
        case .euclid: return .euclid
        case .dot: return .dot
        case .manhattan: return .manhattan
        }
    }
}

// MARK: - Point identifiers

/// A point identifier — either an unsigned integer or a UUID string.
public enum PointID: Sendable, Hashable, ExpressibleByIntegerLiteral, ExpressibleByStringLiteral {
    case int(UInt64)
    case uuid(String)

    public init(integerLiteral value: UInt64) { self = .int(value) }
    public init(stringLiteral value: String) { self = .uuid(value) }

    var proto: Qdrant_PointId {
        var id = Qdrant_PointId()
        switch self {
        case .int(let n): id.num = n
        case .uuid(let s): id.uuid = s
        }
        return id
    }

    init(_ proto: Qdrant_PointId) {
        switch proto.pointIDOptions {
        case .num(let n): self = .int(n)
        case .uuid(let s): self = .uuid(s)
        case .none: self = .int(0)
        }
    }
}

// MARK: - Payload values

/// A JSON-like payload value. Mirrors the gRPC `Value` / JSON payload.
public indirect enum QdrantValue: Sendable, Equatable,
    ExpressibleByStringLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral,
    ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral, ExpressibleByNilLiteral
{
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case list([QdrantValue])
    case object([String: QdrantValue])

    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int64) { self = .int(value) }
    public init(floatLiteral value: Double) { self = .double(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(arrayLiteral elements: QdrantValue...) { self = .list(elements) }
    public init(dictionaryLiteral elements: (String, QdrantValue)...) {
        self = .object(Dictionary(uniqueKeysWithValues: elements))
    }
    public init(nilLiteral: ()) { self = .null }

    var proto: Qdrant_Value {
        var v = Qdrant_Value()
        switch self {
        case .null:
            v.nullValue = .nullValue
        case .bool(let b):
            v.boolValue = b
        case .int(let i):
            v.integerValue = i
        case .double(let d):
            v.doubleValue = d
        case .string(let s):
            v.stringValue = s
        case .list(let items):
            var list = Qdrant_ListValue()
            list.values = items.map(\.proto)
            v.listValue = list
        case .object(let dict):
            var s = Qdrant_Struct()
            s.fields = dict.mapValues(\.proto)
            v.structValue = s
        }
        return v
    }

    init(_ proto: Qdrant_Value) {
        switch proto.kind {
        case .nullValue, .none: self = .null
        case .boolValue(let b): self = .bool(b)
        case .integerValue(let i): self = .int(i)
        case .doubleValue(let d): self = .double(d)
        case .stringValue(let s): self = .string(s)
        case .listValue(let l): self = .list(l.values.map(QdrantValue.init))
        case .structValue(let s): self = .object(s.fields.mapValues(QdrantValue.init))
        }
    }
}

/// A payload dictionary.
public typealias Payload = [String: QdrantValue]

extension Payload {
    var proto: [String: Qdrant_Value] { mapValues(\.proto) }
    init(proto: [String: Qdrant_Value]) { self = proto.mapValues(QdrantValue.init) }
}

// MARK: - PointStruct

/// A point to upsert: id, its vector(s), and an optional payload.
///
/// Supports a single unnamed vector (dense / sparse / multi) or a set of named
/// vectors. Mirrors Python `models.PointStruct`.
public struct PointStruct: Sendable {
    public var id: PointID
    public var vectors: PointVectors
    public var payload: Payload

    /// A single unnamed dense vector (the common case).
    public init(id: PointID, vector: [Float], payload: Payload = [:]) {
        self.id = id
        self.vectors = .single(.dense(vector))
        self.payload = payload
    }

    /// A single unnamed vector of any kind (dense / sparse / multi).
    public init(id: PointID, vector: VectorData, payload: Payload = [:]) {
        self.id = id
        self.vectors = .single(vector)
        self.payload = payload
    }

    /// A set of named vectors.
    public init(id: PointID, vectors: [String: VectorData], payload: Payload = [:]) {
        self.id = id
        self.vectors = .named(vectors)
        self.payload = payload
    }

    var proto: Qdrant_PointStruct {
        var p = Qdrant_PointStruct()
        p.id = id.proto
        p.vectors = vectors.proto
        p.payload = payload.proto
        return p
    }
}

// MARK: - RetrievedPoint

/// A point returned by `retrieve` / `scroll`: id, payload, optional vector.
public struct RetrievedPoint: Sendable {
    public let id: PointID
    public let payload: Payload
    /// The single unnamed dense vector, if it was requested and present.
    public let vector: [Float]?
    /// Named vectors, if the point uses them (dense only are decoded as `.dense`).
    public let vectors: [String: VectorData]

    public init(id: PointID, payload: Payload = [:], vector: [Float]? = nil,
                vectors: [String: VectorData] = [:]) {
        self.id = id
        self.payload = payload
        self.vector = vector
        self.vectors = vectors
    }

    init(_ proto: Qdrant_RetrievedPoint) {
        self.id = PointID(proto.id)
        self.payload = Payload(proto: proto.payload)
        if proto.hasVectors {
            switch proto.vectors.vectorsOptions {
            case .vector(let v):
                self.vector = v.data
                self.vectors = [:]
            case .vectors(let named):
                self.vector = nil
                self.vectors = named.vectors.mapValues { VectorData(output: $0) }
            case .none:
                self.vector = nil
                self.vectors = [:]
            }
        } else {
            self.vector = nil
            self.vectors = [:]
        }
    }
}

// MARK: - Payload field index types

/// Payload field index type. Mirrors Python `models.PayloadSchemaType`.
public enum FieldType: Sendable {
    case keyword, integer, float, geo, text, bool, datetime, uuid

    var proto: Qdrant_FieldType {
        switch self {
        case .keyword: return .keyword
        case .integer: return .integer
        case .float: return .float
        case .geo: return .geo
        case .text: return .text
        case .bool: return .bool
        case .datetime: return .datetime
        case .uuid: return .uuid
        }
    }
}

// MARK: - Points selector

/// Selects points either by explicit ids or by a filter.
public enum PointsSelector: Sendable {
    case ids([PointID])
    case filter(Filter)

    var proto: Qdrant_PointsSelector {
        var s = Qdrant_PointsSelector()
        switch self {
        case .ids(let ids):
            var list = Qdrant_PointsIdsList()
            list.ids = ids.map(\.proto)
            s.points = list
        case .filter(let f):
            s.filter = f.proto
        }
        return s
    }
}

// MARK: - ScoredPoint

/// A search/query result: id, score, and (optionally) payload/vectors.
public struct ScoredPoint: Sendable {
    public let id: PointID
    public let score: Float
    public let version: UInt64
    public let payload: Payload
    /// The single unnamed dense vector, if requested.
    public let vector: [Float]?
    /// Named vectors, if requested and present.
    public let vectors: [String: VectorData]

    public init(
        id: PointID, score: Float, version: UInt64 = 0,
        payload: Payload = [:], vector: [Float]? = nil, vectors: [String: VectorData] = [:]
    ) {
        self.id = id
        self.score = score
        self.version = version
        self.payload = payload
        self.vector = vector
        self.vectors = vectors
    }

    init(_ proto: Qdrant_ScoredPoint) {
        self.id = PointID(proto.id)
        self.score = proto.score
        self.version = proto.version
        self.payload = Payload(proto: proto.payload)
        if proto.hasVectors {
            switch proto.vectors.vectorsOptions {
            case .vector(let v): self.vector = v.data; self.vectors = [:]
            case .vectors(let named): self.vector = nil; self.vectors = named.vectors.mapValues { VectorData(output: $0) }
            case .none: self.vector = nil; self.vectors = [:]
            }
        } else {
            self.vector = nil
            self.vectors = [:]
        }
    }
}
