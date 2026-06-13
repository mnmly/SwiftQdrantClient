import Foundation
import QdrantProtos

// MARK: - UpdateResult

/// Status of a write operation. Mirrors Python `models.UpdateStatus`.
public enum UpdateStatus: Sendable {
    case unknown, acknowledged, completed, clockRejected, waitTimeout

    init(_ proto: Qdrant_UpdateStatus) {
        switch proto {
        case .acknowledged: self = .acknowledged
        case .completed: self = .completed
        case .clockRejected: self = .clockRejected
        case .waitTimeout: self = .waitTimeout
        default: self = .unknown
        }
    }
}

/// Result of a write operation. Mirrors Python `models.UpdateResult`.
public struct UpdateResult: Sendable {
    public let operationId: UInt64?
    public let status: UpdateStatus

    public init(operationId: UInt64? = nil, status: UpdateStatus = .completed) {
        self.operationId = operationId
        self.status = status
    }

    init(_ proto: Qdrant_UpdateResult) {
        self.operationId = proto.hasOperationID ? proto.operationID : nil
        self.status = UpdateStatus(proto.status)
    }
}

// MARK: - Groups

/// The key a group is formed around. Mirrors Python `models.GroupId`.
public enum GroupId: Sendable, Hashable {
    case unsigned(UInt64)
    case integer(Int64)
    case string(String)

    init(_ proto: Qdrant_GroupId) {
        switch proto.kind {
        case .unsignedValue(let v): self = .unsigned(v)
        case .integerValue(let v): self = .integer(v)
        case .stringValue(let v): self = .string(v)
        case .none: self = .unsigned(0)
        }
    }
}

/// A group of points sharing a payload value. Mirrors Python `models.PointGroup`.
public struct PointGroup: Sendable {
    public let id: GroupId
    public let hits: [ScoredPoint]
    public let lookup: RetrievedPoint?

    public init(id: GroupId, hits: [ScoredPoint], lookup: RetrievedPoint? = nil) {
        self.id = id
        self.hits = hits
        self.lookup = lookup
    }

    init(_ proto: Qdrant_PointGroup) {
        self.id = GroupId(proto.id)
        self.hits = proto.hits.map(ScoredPoint.init)
        self.lookup = proto.hasLookup ? RetrievedPoint(proto.lookup) : nil
    }
}

// MARK: - Facets

/// A facet value. Mirrors Python `models.FacetValue`.
public enum FacetValue: Sendable, Hashable {
    case string(String)
    case integer(Int64)
    case bool(Bool)

    init(_ proto: Qdrant_FacetValue) {
        switch proto.variant {
        case .stringValue(let v): self = .string(v)
        case .integerValue(let v): self = .integer(v)
        case .boolValue(let v): self = .bool(v)
        case .none: self = .string("")
        }
    }
}

/// A facet hit: a value and how many points carry it.
/// Mirrors Python `models.FacetValueHit`.
public struct FacetHit: Sendable {
    public let value: FacetValue
    public let count: UInt64

    public init(value: FacetValue, count: UInt64) {
        self.value = value
        self.count = count
    }

    init(_ proto: Qdrant_FacetHit) {
        self.value = FacetValue(proto.value)
        self.count = proto.count
    }
}

// MARK: - Search matrix

/// A scored pair of points from a distance matrix search.
public struct SearchMatrixPair: Sendable {
    public let a: PointID
    public let b: PointID
    public let score: Float

    public init(a: PointID, b: PointID, score: Float) {
        self.a = a
        self.b = b
        self.score = score
    }

    init(_ proto: Qdrant_SearchMatrixPair) {
        self.a = PointID(proto.a)
        self.b = PointID(proto.b)
        self.score = proto.score
    }
}

/// Offset-encoded distance matrix. Mirrors Python `models.SearchMatrixOffsetsResponse`.
public struct SearchMatrixOffsets: Sendable {
    public let offsetsRow: [UInt64]
    public let offsetsCol: [UInt64]
    public let scores: [Float]
    public let ids: [PointID]

    public init(offsetsRow: [UInt64], offsetsCol: [UInt64], scores: [Float], ids: [PointID]) {
        self.offsetsRow = offsetsRow
        self.offsetsCol = offsetsCol
        self.scores = scores
        self.ids = ids
    }

    init(_ proto: Qdrant_SearchMatrixOffsets) {
        self.offsetsRow = proto.offsetsRow
        self.offsetsCol = proto.offsetsCol
        self.scores = proto.scores
        self.ids = proto.ids.map(PointID.init)
    }
}
