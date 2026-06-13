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
