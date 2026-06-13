import Foundation
import QdrantProtos

// MARK: - Quantization

/// Scalar quantization type. Mirrors Python `models.ScalarType`.
public enum QuantizationType: Sendable {
    case int8
    var proto: Qdrant_QuantizationType {
        switch self { case .int8: return .int8 }
    }
}

/// Product-quantization compression ratio. Mirrors Python `models.CompressionRatio`.
public enum CompressionRatio: Sendable {
    case x4, x8, x16, x32, x64
    var proto: Qdrant_CompressionRatio {
        switch self {
        case .x4: return .x4
        case .x8: return .x8
        case .x16: return .x16
        case .x32: return .x32
        case .x64: return .x64
        }
    }
}

/// Binary-quantization bit encoding. Mirrors Python `models.BinaryQuantizationEncoding`.
public enum BinaryQuantizationEncoding: Sendable {
    case oneBit, twoBits, oneAndHalfBits
    var proto: Qdrant_BinaryQuantizationEncoding {
        switch self {
        case .oneBit: return .oneBit
        case .twoBits: return .twoBits
        case .oneAndHalfBits: return .oneAndHalfBits
        }
    }
}

/// Scalar quantization parameters. Mirrors Python `models.ScalarQuantization`.
public struct ScalarQuantization: Sendable {
    public var type: QuantizationType
    public var quantile: Float?
    public var alwaysRam: Bool?
    public init(type: QuantizationType = .int8, quantile: Float? = nil, alwaysRam: Bool? = nil) {
        self.type = type; self.quantile = quantile; self.alwaysRam = alwaysRam
    }
    var proto: Qdrant_ScalarQuantization {
        var s = Qdrant_ScalarQuantization()
        s.type = type.proto
        if let quantile { s.quantile = quantile }
        if let alwaysRam { s.alwaysRam = alwaysRam }
        return s
    }
}

/// Product quantization parameters. Mirrors Python `models.ProductQuantization`.
public struct ProductQuantization: Sendable {
    public var compression: CompressionRatio
    public var alwaysRam: Bool?
    public init(compression: CompressionRatio = .x4, alwaysRam: Bool? = nil) {
        self.compression = compression; self.alwaysRam = alwaysRam
    }
    var proto: Qdrant_ProductQuantization {
        var p = Qdrant_ProductQuantization()
        p.compression = compression.proto
        if let alwaysRam { p.alwaysRam = alwaysRam }
        return p
    }
}

/// Binary quantization parameters. Mirrors Python `models.BinaryQuantization`.
public struct BinaryQuantization: Sendable {
    public var alwaysRam: Bool?
    public var encoding: BinaryQuantizationEncoding?
    public init(alwaysRam: Bool? = nil, encoding: BinaryQuantizationEncoding? = nil) {
        self.alwaysRam = alwaysRam; self.encoding = encoding
    }
    var proto: Qdrant_BinaryQuantization {
        var b = Qdrant_BinaryQuantization()
        if let alwaysRam { b.alwaysRam = alwaysRam }
        if let encoding { b.encoding = encoding.proto }
        return b
    }
}

/// Vector quantization configuration. Mirrors Python `models.QuantizationConfig`.
public enum QuantizationConfig: Sendable {
    case scalar(ScalarQuantization)
    case product(ProductQuantization)
    case binary(BinaryQuantization)

    var proto: Qdrant_QuantizationConfig {
        var c = Qdrant_QuantizationConfig()
        switch self {
        case .scalar(let s): c.scalar = s.proto
        case .product(let p): c.product = p.proto
        case .binary(let b): c.binary = b.proto
        }
        return c
    }
}

/// Per-query quantization search params. Mirrors Python `models.QuantizationSearchParams`.
public struct QuantizationSearchParams: Sendable {
    public var ignore: Bool?
    public var rescore: Bool?
    public var oversampling: Double?
    public init(ignore: Bool? = nil, rescore: Bool? = nil, oversampling: Double? = nil) {
        self.ignore = ignore; self.rescore = rescore; self.oversampling = oversampling
    }
    var proto: Qdrant_QuantizationSearchParams {
        var q = Qdrant_QuantizationSearchParams()
        if let ignore { q.ignore = ignore }
        if let rescore { q.rescore = rescore }
        if let oversampling { q.oversampling = oversampling }
        return q
    }
}

// MARK: - WAL config & sharding method

/// Write-ahead-log configuration. Mirrors Python `models.WalConfigDiff`.
public struct WalConfig: Sendable {
    public var walCapacityMb: UInt64?
    public var walSegmentsAhead: UInt64?
    public init(walCapacityMb: UInt64? = nil, walSegmentsAhead: UInt64? = nil) {
        self.walCapacityMb = walCapacityMb; self.walSegmentsAhead = walSegmentsAhead
    }
    var proto: Qdrant_WalConfigDiff {
        var w = Qdrant_WalConfigDiff()
        if let walCapacityMb { w.walCapacityMb = walCapacityMb }
        if let walSegmentsAhead { w.walSegmentsAhead = walSegmentsAhead }
        return w
    }
}

/// Strict-mode limits for a collection. Mirrors Python `models.StrictModeConfig`.
public struct StrictModeConfig: Sendable {
    public var enabled: Bool?
    public var maxQueryLimit: UInt32?
    public var maxTimeout: UInt32?
    public var unindexedFilteringRetrieve: Bool?
    public var unindexedFilteringUpdate: Bool?
    public var searchMaxHnswEf: UInt32?
    public var searchAllowExact: Bool?
    public var searchMaxOversampling: Float?
    public var upsertMaxBatchsize: UInt64?
    public var maxCollectionVectorSizeBytes: UInt64?
    public var maxCollectionPayloadSizeBytes: UInt64?
    public var maxPointsCount: UInt64?
    public var filterMaxConditions: UInt64?
    public var conditionMaxSize: UInt64?

    public init(
        enabled: Bool? = nil, maxQueryLimit: UInt32? = nil, maxTimeout: UInt32? = nil,
        unindexedFilteringRetrieve: Bool? = nil, unindexedFilteringUpdate: Bool? = nil,
        searchMaxHnswEf: UInt32? = nil, searchAllowExact: Bool? = nil, searchMaxOversampling: Float? = nil,
        upsertMaxBatchsize: UInt64? = nil, maxCollectionVectorSizeBytes: UInt64? = nil,
        maxCollectionPayloadSizeBytes: UInt64? = nil, maxPointsCount: UInt64? = nil,
        filterMaxConditions: UInt64? = nil, conditionMaxSize: UInt64? = nil
    ) {
        self.enabled = enabled; self.maxQueryLimit = maxQueryLimit; self.maxTimeout = maxTimeout
        self.unindexedFilteringRetrieve = unindexedFilteringRetrieve
        self.unindexedFilteringUpdate = unindexedFilteringUpdate
        self.searchMaxHnswEf = searchMaxHnswEf; self.searchAllowExact = searchAllowExact
        self.searchMaxOversampling = searchMaxOversampling; self.upsertMaxBatchsize = upsertMaxBatchsize
        self.maxCollectionVectorSizeBytes = maxCollectionVectorSizeBytes
        self.maxCollectionPayloadSizeBytes = maxCollectionPayloadSizeBytes
        self.maxPointsCount = maxPointsCount; self.filterMaxConditions = filterMaxConditions
        self.conditionMaxSize = conditionMaxSize
    }

    var proto: Qdrant_StrictModeConfig {
        var c = Qdrant_StrictModeConfig()
        if let enabled { c.enabled = enabled }
        if let maxQueryLimit { c.maxQueryLimit = maxQueryLimit }
        if let maxTimeout { c.maxTimeout = maxTimeout }
        if let unindexedFilteringRetrieve { c.unindexedFilteringRetrieve = unindexedFilteringRetrieve }
        if let unindexedFilteringUpdate { c.unindexedFilteringUpdate = unindexedFilteringUpdate }
        if let searchMaxHnswEf { c.searchMaxHnswEf = searchMaxHnswEf }
        if let searchAllowExact { c.searchAllowExact = searchAllowExact }
        if let searchMaxOversampling { c.searchMaxOversampling = searchMaxOversampling }
        if let upsertMaxBatchsize { c.upsertMaxBatchsize = upsertMaxBatchsize }
        if let maxCollectionVectorSizeBytes { c.maxCollectionVectorSizeBytes = maxCollectionVectorSizeBytes }
        if let maxCollectionPayloadSizeBytes { c.maxCollectionPayloadSizeBytes = maxCollectionPayloadSizeBytes }
        if let maxPointsCount { c.maxPointsCount = maxPointsCount }
        if let filterMaxConditions { c.filterMaxConditions = filterMaxConditions }
        if let conditionMaxSize { c.conditionMaxSize = conditionMaxSize }
        return c
    }

    var json: JSONValue {
        var o: [String: JSONValue] = [:]
        if let enabled { o["enabled"] = .bool(enabled) }
        if let maxQueryLimit { o["max_query_limit"] = .int(Int64(maxQueryLimit)) }
        if let maxTimeout { o["max_timeout"] = .int(Int64(maxTimeout)) }
        if let unindexedFilteringRetrieve { o["unindexed_filtering_retrieve"] = .bool(unindexedFilteringRetrieve) }
        if let unindexedFilteringUpdate { o["unindexed_filtering_update"] = .bool(unindexedFilteringUpdate) }
        if let searchMaxHnswEf { o["search_max_hnsw_ef"] = .int(Int64(searchMaxHnswEf)) }
        if let searchAllowExact { o["search_allow_exact"] = .bool(searchAllowExact) }
        if let searchMaxOversampling { o["search_max_oversampling"] = .double(Double(searchMaxOversampling)) }
        if let upsertMaxBatchsize { o["upsert_max_batchsize"] = .int(Int64(upsertMaxBatchsize)) }
        if let maxCollectionVectorSizeBytes { o["max_collection_vector_size_bytes"] = .int(Int64(maxCollectionVectorSizeBytes)) }
        if let maxCollectionPayloadSizeBytes { o["max_collection_payload_size_bytes"] = .int(Int64(maxCollectionPayloadSizeBytes)) }
        if let maxPointsCount { o["max_points_count"] = .int(Int64(maxPointsCount)) }
        if let filterMaxConditions { o["filter_max_conditions"] = .int(Int64(filterMaxConditions)) }
        if let conditionMaxSize { o["condition_max_size"] = .int(Int64(conditionMaxSize)) }
        return .object(o)
    }
}

/// Collection sharding method. Mirrors Python `models.ShardingMethod`.
public enum ShardingMethod: Sendable {
    case auto, custom
    var proto: Qdrant_ShardingMethod {
        switch self { case .auto: return .auto; case .custom: return .custom }
    }
    var restValue: String {
        switch self { case .auto: return "auto"; case .custom: return "custom" }
    }
}
