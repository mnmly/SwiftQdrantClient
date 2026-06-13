import Foundation
import QdrantProtos

// MARK: - VectorData

/// A vector value of any kind. Mirrors Python's vector union
/// (list[float] | sparse | list[list[float]]).
public enum VectorData: Sendable, Equatable {
    case dense([Float])
    case sparse(indices: [UInt32], values: [Float])
    case multiDense([[Float]])

    /// Build the gRPC upsert vector message.
    var proto: Qdrant_Vector {
        var v = Qdrant_Vector()
        switch self {
        case .dense(let data):
            var d = Qdrant_DenseVector(); d.data = data
            v.dense = d
        case .sparse(let indices, let values):
            var s = Qdrant_SparseVector(); s.indices = indices; s.values = values
            v.sparse = s
        case .multiDense(let rows):
            var m = Qdrant_MultiDenseVector()
            m.vectors = rows.map { var d = Qdrant_DenseVector(); d.data = $0; return d }
            v.multiDense = m
        }
        return v
    }

    /// Decode from a gRPC output vector message.
    init(output: Qdrant_VectorOutput) {
        switch output.vector {
        case .dense(let d): self = .dense(d.data)
        case .sparse(let s): self = .sparse(indices: s.indices, values: s.values)
        case .multiDense(let m): self = .multiDense(m.vectors.map(\.data))
        case .none: self = .dense(output.data) // legacy/plain dense
        }
    }
}

// MARK: - PointVectors

/// The vector(s) attached to a point being upserted.
public enum PointVectors: Sendable {
    case single(VectorData)
    case named([String: VectorData])

    var proto: Qdrant_Vectors {
        var vectors = Qdrant_Vectors()
        switch self {
        case .single(let data):
            vectors.vectorsOptions = .vector(data.proto)
        case .named(let map):
            var named = Qdrant_NamedVectors()
            named.vectors = map.mapValues(\.proto)
            vectors.vectorsOptions = .vectors(named)
        }
        return vectors
    }
}

// MARK: - VectorInput (query side)

/// A query vector input: a raw vector of any kind, or a reference to an existing
/// point's vector by id. Mirrors Python `models.VectorInput`.
public enum VectorInput: Sendable {
    case dense([Float])
    case sparse(indices: [UInt32], values: [Float])
    case multiDense([[Float]])
    case id(PointID)

    var proto: Qdrant_VectorInput {
        var v = Qdrant_VectorInput()
        switch self {
        case .dense(let data):
            var d = Qdrant_DenseVector(); d.data = data
            v.dense = d
        case .sparse(let indices, let values):
            var s = Qdrant_SparseVector(); s.indices = indices; s.values = values
            v.sparse = s
        case .multiDense(let rows):
            var m = Qdrant_MultiDenseVector()
            m.vectors = rows.map { var d = Qdrant_DenseVector(); d.data = $0; return d }
            v.multiDense = m
        case .id(let id):
            v.id = id.proto
        }
        return v
    }
}
