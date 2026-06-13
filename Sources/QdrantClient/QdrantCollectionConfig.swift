import Foundation
import QdrantProtos

// MARK: - Vector datatype

/// Storage datatype for vectors. Mirrors Python `models.Datatype`.
public enum VectorDatatype: Sendable {
    case float32, uint8, float16

    var proto: Qdrant_Datatype {
        switch self {
        case .float32: return .float32
        case .uint8: return .uint8
        case .float16: return .float16
        }
    }
}

// MARK: - HNSW / optimizers diffs

/// HNSW index parameters. Mirrors Python `models.HnswConfigDiff` (all fields).
public struct HnswConfig: Sendable {
    public var m: UInt64?
    public var efConstruct: UInt64?
    public var fullScanThreshold: UInt64?
    public var maxIndexingThreads: UInt64?
    public var onDisk: Bool?
    public var payloadM: UInt64?
    public var inlineStorage: Bool?

    public init(m: UInt64? = nil, efConstruct: UInt64? = nil,
                fullScanThreshold: UInt64? = nil, maxIndexingThreads: UInt64? = nil,
                onDisk: Bool? = nil, payloadM: UInt64? = nil, inlineStorage: Bool? = nil) {
        self.m = m; self.efConstruct = efConstruct
        self.fullScanThreshold = fullScanThreshold; self.maxIndexingThreads = maxIndexingThreads
        self.onDisk = onDisk; self.payloadM = payloadM; self.inlineStorage = inlineStorage
    }

    var proto: Qdrant_HnswConfigDiff {
        var c = Qdrant_HnswConfigDiff()
        if let m { c.m = m }
        if let efConstruct { c.efConstruct = efConstruct }
        if let fullScanThreshold { c.fullScanThreshold = fullScanThreshold }
        if let maxIndexingThreads { c.maxIndexingThreads = maxIndexingThreads }
        if let onDisk { c.onDisk = onDisk }
        if let payloadM { c.payloadM = payloadM }
        if let inlineStorage { c.inlineStorage = inlineStorage }
        return c
    }
}

/// Optimizer parameters. Mirrors Python `models.OptimizersConfigDiff` (all fields).
public struct OptimizersConfig: Sendable {
    public var deletedThreshold: Double?
    public var vacuumMinVectorNumber: UInt64?
    public var defaultSegmentNumber: UInt64?
    public var maxSegmentSize: UInt64?
    public var memmapThreshold: UInt64?
    public var indexingThreshold: UInt64?
    public var flushIntervalSec: UInt64?
    public var maxOptimizationThreads: UInt64?

    public init(deletedThreshold: Double? = nil, vacuumMinVectorNumber: UInt64? = nil,
                defaultSegmentNumber: UInt64? = nil, maxSegmentSize: UInt64? = nil,
                memmapThreshold: UInt64? = nil, indexingThreshold: UInt64? = nil,
                flushIntervalSec: UInt64? = nil, maxOptimizationThreads: UInt64? = nil) {
        self.deletedThreshold = deletedThreshold
        self.vacuumMinVectorNumber = vacuumMinVectorNumber
        self.defaultSegmentNumber = defaultSegmentNumber
        self.maxSegmentSize = maxSegmentSize
        self.memmapThreshold = memmapThreshold
        self.indexingThreshold = indexingThreshold
        self.flushIntervalSec = flushIntervalSec
        self.maxOptimizationThreads = maxOptimizationThreads
    }

    var proto: Qdrant_OptimizersConfigDiff {
        var c = Qdrant_OptimizersConfigDiff()
        if let deletedThreshold { c.deletedThreshold = deletedThreshold }
        if let vacuumMinVectorNumber { c.vacuumMinVectorNumber = vacuumMinVectorNumber }
        if let defaultSegmentNumber { c.defaultSegmentNumber = defaultSegmentNumber }
        if let maxSegmentSize { c.maxSegmentSize = maxSegmentSize }
        if let memmapThreshold { c.memmapThreshold = memmapThreshold }
        if let indexingThreshold { c.indexingThreshold = indexingThreshold }
        if let flushIntervalSec { c.flushIntervalSec = flushIntervalSec }
        if let maxOptimizationThreads {
            var mot = Qdrant_MaxOptimizationThreads()
            mot.value = maxOptimizationThreads
            c.maxOptimizationThreads = mot
        }
        return c
    }
}

// MARK: - Vector params

/// Comparator for multivectors (a per-point list of vectors). Mirrors Python
/// `models.MultiVectorComparator`.
public enum MultivectorComparator: Sendable {
    case maxSim
    var proto: Qdrant_MultiVectorComparator {
        switch self {
        case .maxSim: return .maxSim
        }
    }
}

/// Parameters for a single (named or unnamed) dense vector.
/// Mirrors Python `models.VectorParams`.
public struct VectorParams: Sendable {
    public var size: UInt64
    public var distance: Distance
    public var onDisk: Bool?
    public var datatype: VectorDatatype?
    public var hnswConfig: HnswConfig?
    /// Per-vector quantization configuration (scalar / product / binary).
    public var quantizationConfig: QuantizationConfig?
    /// When set, this named vector stores a *multivector* (a list of vectors per
    /// point) compared with the given comparator (e.g. ColBERT-style MaxSim).
    public var multivectorComparator: MultivectorComparator?

    public init(size: UInt64, distance: Distance = .cosine, onDisk: Bool? = nil,
                datatype: VectorDatatype? = nil, hnswConfig: HnswConfig? = nil,
                quantizationConfig: QuantizationConfig? = nil,
                multivectorComparator: MultivectorComparator? = nil) {
        self.size = size; self.distance = distance; self.onDisk = onDisk
        self.datatype = datatype; self.hnswConfig = hnswConfig
        self.quantizationConfig = quantizationConfig
        self.multivectorComparator = multivectorComparator
    }

    var proto: Qdrant_VectorParams {
        var p = Qdrant_VectorParams()
        p.size = size
        p.distance = distance.proto
        if let onDisk { p.onDisk = onDisk }
        if let datatype { p.datatype = datatype.proto }
        if let hnswConfig { p.hnswConfig = hnswConfig.proto }
        if let quantizationConfig { p.quantizationConfig = quantizationConfig.proto }
        if let multivectorComparator {
            var mv = Qdrant_MultiVectorConfig()
            mv.comparator = multivectorComparator.proto
            p.multivectorConfig = mv
        }
        return p
    }
}

/// The vectors configuration of a collection: one unnamed vector, or many named.
/// Mirrors Python's `vectors_config` (VectorParams | dict[str, VectorParams]).
public enum VectorsConfiguration: Sendable {
    case single(VectorParams)
    case named([String: VectorParams])

    var proto: Qdrant_VectorsConfig {
        var c = Qdrant_VectorsConfig()
        switch self {
        case .single(let p):
            c.config = .params(p.proto)
        case .named(let map):
            var m = Qdrant_VectorParamsMap()
            m.map = map.mapValues(\.proto)
            c.config = .paramsMap(m)
        }
        return c
    }
}

// MARK: - Sparse vectors

/// IDF / no modifier for sparse vectors. Mirrors Python `models.Modifier`.
public enum SparseModifier: Sendable {
    case none, idf
    var proto: Qdrant_Modifier {
        switch self {
        case .none: return .none
        case .idf: return .idf
        }
    }
}

/// Parameters for a named sparse vector. Mirrors Python `models.SparseVectorParams`.
public struct SparseVectorParams: Sendable {
    public var onDisk: Bool?
    public var fullScanThreshold: UInt64?
    public var datatype: VectorDatatype?
    public var modifier: SparseModifier?

    public init(onDisk: Bool? = nil, fullScanThreshold: UInt64? = nil,
                datatype: VectorDatatype? = nil, modifier: SparseModifier? = nil) {
        self.onDisk = onDisk; self.fullScanThreshold = fullScanThreshold
        self.datatype = datatype; self.modifier = modifier
    }

    var proto: Qdrant_SparseVectorParams {
        var p = Qdrant_SparseVectorParams()
        if onDisk != nil || fullScanThreshold != nil || datatype != nil {
            var idx = Qdrant_SparseIndexConfig()
            if let onDisk { idx.onDisk = onDisk }
            if let fullScanThreshold { idx.fullScanThreshold = fullScanThreshold }
            if let datatype { idx.datatype = datatype.proto }
            p.index = idx
        }
        if let modifier { p.modifier = modifier.proto }
        return p
    }
}

// MARK: - Collection info

/// Lightweight collection status. Mirrors Python `models.CollectionStatus`.
public enum CollectionStatus: Sendable {
    case green, yellow, red, grey, unknown

    init(_ proto: Qdrant_CollectionStatus) {
        switch proto {
        case .green: self = .green
        case .yellow: self = .yellow
        case .red: self = .red
        case .grey: self = .grey
        default: self = .unknown
        }
    }
}

// MARK: - Shard keys

/// A custom shard key. Mirrors Python `models.ShardKey`.
public enum ShardKey: Sendable, Hashable {
    case keyword(String)
    case number(UInt64)

    var proto: Qdrant_ShardKey {
        var s = Qdrant_ShardKey()
        switch self {
        case .keyword(let k): s.keyword = k
        case .number(let n): s.number = n
        }
        return s
    }

    init(_ proto: Qdrant_ShardKey) {
        switch proto.key {
        case .keyword(let k): self = .keyword(k)
        case .number(let n): self = .number(n)
        case .none: self = .keyword("")
        }
    }
}

/// An alias and the collection it points to. Mirrors Python `models.AliasDescription`.
public struct AliasDescription: Sendable {
    public let aliasName: String
    public let collectionName: String

    public init(aliasName: String, collectionName: String) {
        self.aliasName = aliasName
        self.collectionName = collectionName
    }

    init(_ proto: Qdrant_AliasDescription) {
        self.aliasName = proto.aliasName
        self.collectionName = proto.collectionName
    }
}

/// A single alias mutation. Mirrors Python `models.AliasOperations`.
public enum AliasOperation: Sendable {
    case create(collection: String, alias: String)
    case delete(alias: String)
    case rename(oldAlias: String, newAlias: String)

    var proto: Qdrant_AliasOperations {
        var op = Qdrant_AliasOperations()
        switch self {
        case .create(let collection, let alias):
            var c = Qdrant_CreateAlias()
            c.collectionName = collection
            c.aliasName = alias
            op.createAlias = c
        case .delete(let alias):
            var d = Qdrant_DeleteAlias()
            d.aliasName = alias
            op.deleteAlias = d
        case .rename(let oldAlias, let newAlias):
            var r = Qdrant_RenameAlias()
            r.oldAliasName = oldAlias
            r.newAliasName = newAlias
            op.renameAlias = r
        }
        return op
    }
}

/// A summary view of a collection. Mirrors the most-used fields of Python
/// `models.CollectionInfo`.
public struct CollectionInfo: Sendable {
    public let status: CollectionStatus
    public let pointsCount: UInt64
    public let segmentsCount: UInt64
    public let indexedVectorsCount: UInt64
    /// `true` if the optimizer is healthy; `false` carries an error.
    public let optimizerStatusOK: Bool
    /// Optimizer error message, when `optimizerStatusOK` is `false`.
    public let optimizerError: String?
    /// Indexed payload fields and their schema type.
    public let payloadSchema: [String: FieldType]

    public init(status: CollectionStatus = .green, pointsCount: UInt64,
                segmentsCount: UInt64 = 1, indexedVectorsCount: UInt64 = 0,
                optimizerStatusOK: Bool = true, optimizerError: String? = nil,
                payloadSchema: [String: FieldType] = [:]) {
        self.status = status
        self.pointsCount = pointsCount
        self.segmentsCount = segmentsCount
        self.indexedVectorsCount = indexedVectorsCount
        self.optimizerStatusOK = optimizerStatusOK
        self.optimizerError = optimizerError
        self.payloadSchema = payloadSchema
    }

    init(_ proto: Qdrant_CollectionInfo) {
        self.status = CollectionStatus(proto.status)
        self.pointsCount = proto.hasPointsCount ? proto.pointsCount : 0
        self.segmentsCount = proto.segmentsCount
        self.indexedVectorsCount = proto.hasIndexedVectorsCount ? proto.indexedVectorsCount : 0
        if proto.hasOptimizerStatus {
            self.optimizerStatusOK = proto.optimizerStatus.ok
            self.optimizerError = proto.optimizerStatus.ok ? nil : proto.optimizerStatus.error
        } else {
            self.optimizerStatusOK = true
            self.optimizerError = nil
        }
        self.payloadSchema = proto.payloadSchema.reduce(into: [:]) { acc, kv in
            if let t = FieldType(schema: kv.value.dataType) { acc[kv.key] = t }
        }
    }
}
