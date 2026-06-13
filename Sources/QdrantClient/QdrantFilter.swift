import Foundation
import QdrantProtos

// MARK: - Match value

/// A payload match condition value. Mirrors Python `models.Match*`.
public enum MatchValue: Sendable {
    case keyword(String)
    case integer(Int64)
    case boolean(Bool)
    /// Full-text "match any token" search.
    case text(String)
    /// Full-text phrase search.
    case phrase(String)
    /// Full-text "match any word" search.
    case textAny(String)
    case anyKeywords([String])
    case anyIntegers([Int64])
    case exceptKeywords([String])
    case exceptIntegers([Int64])

    var proto: Qdrant_Match {
        var m = Qdrant_Match()
        switch self {
        case .keyword(let s): m.keyword = s
        case .integer(let i): m.integer = i
        case .boolean(let b): m.boolean = b
        case .text(let s): m.text = s
        case .phrase(let s): m.phrase = s
        case .textAny(let s): m.textAny = s
        case .anyKeywords(let v):
            var r = Qdrant_RepeatedStrings(); r.strings = v; m.keywords = r
        case .anyIntegers(let v):
            var r = Qdrant_RepeatedIntegers(); r.integers = v; m.integers = r
        case .exceptKeywords(let v):
            var r = Qdrant_RepeatedStrings(); r.strings = v; m.exceptKeywords = r
        case .exceptIntegers(let v):
            var r = Qdrant_RepeatedIntegers(); r.integers = v; m.exceptIntegers = r
        }
        return m
    }
}

// MARK: - Range

/// Numeric range condition. Any combination of bounds may be set.
public struct QdrantRange: Sendable {
    public var lt: Double?
    public var gt: Double?
    public var gte: Double?
    public var lte: Double?

    public init(lt: Double? = nil, gt: Double? = nil, gte: Double? = nil, lte: Double? = nil) {
        self.lt = lt; self.gt = gt; self.gte = gte; self.lte = lte
    }

    var proto: Qdrant_Range {
        var r = Qdrant_Range()
        if let lt { r.lt = lt }
        if let gt { r.gt = gt }
        if let gte { r.gte = gte }
        if let lte { r.lte = lte }
        return r
    }
}

/// Geographic point (lon/lat).
public struct GeoPoint: Sendable {
    public var lon: Double
    public var lat: Double
    public init(lon: Double, lat: Double) { self.lon = lon; self.lat = lat }
    var proto: Qdrant_GeoPoint {
        var p = Qdrant_GeoPoint(); p.lon = lon; p.lat = lat; return p
    }
}

// MARK: - Condition

/// A single filter condition. Mirrors Python `models.*Condition`.
public enum Condition: Sendable {
    case match(key: String, value: MatchValue)
    case range(key: String, range: QdrantRange)
    case geoRadius(key: String, center: GeoPoint, radius: Float)
    case geoBoundingBox(key: String, topLeft: GeoPoint, bottomRight: GeoPoint)
    case hasID([PointID])
    case hasVector(name: String)
    case isEmpty(key: String)
    case isNull(key: String)
    case nested(key: String, filter: Filter)
    /// A nested sub-filter as a condition.
    case filter(Filter)

    var proto: Qdrant_Condition {
        var c = Qdrant_Condition()
        switch self {
        case .match(let key, let value):
            var fc = Qdrant_FieldCondition(); fc.key = key; fc.match = value.proto
            c.field = fc
        case .range(let key, let range):
            var fc = Qdrant_FieldCondition(); fc.key = key; fc.range = range.proto
            c.field = fc
        case .geoRadius(let key, let center, let radius):
            var gr = Qdrant_GeoRadius(); gr.center = center.proto; gr.radius = radius
            var fc = Qdrant_FieldCondition(); fc.key = key; fc.geoRadius = gr
            c.field = fc
        case .geoBoundingBox(let key, let topLeft, let bottomRight):
            var bb = Qdrant_GeoBoundingBox(); bb.topLeft = topLeft.proto; bb.bottomRight = bottomRight.proto
            var fc = Qdrant_FieldCondition(); fc.key = key; fc.geoBoundingBox = bb
            c.field = fc
        case .hasID(let ids):
            var h = Qdrant_HasIdCondition(); h.hasID_p = ids.map(\.proto)
            c.hasID_p = h
        case .hasVector(let name):
            var h = Qdrant_HasVectorCondition(); h.hasVector_p = name
            c.hasVector_p = h
        case .isEmpty(let key):
            var e = Qdrant_IsEmptyCondition(); e.key = key
            c.isEmpty = e
        case .isNull(let key):
            var n = Qdrant_IsNullCondition(); n.key = key
            c.isNull = n
        case .nested(let key, let filter):
            var n = Qdrant_NestedCondition(); n.key = key; n.filter = filter.proto
            c.nested = n
        case .filter(let filter):
            c.filter = filter.proto
        }
        return c
    }
}

// MARK: - Filter

/// A query filter combining conditions. Mirrors Python `models.Filter`.
public struct Filter: Sendable {
    public var must: [Condition]
    public var should: [Condition]
    public var mustNot: [Condition]
    /// At least `count` of these conditions must match.
    public var minShould: (conditions: [Condition], count: UInt64)?

    public init(
        must: [Condition] = [],
        should: [Condition] = [],
        mustNot: [Condition] = [],
        minShould: (conditions: [Condition], count: UInt64)? = nil
    ) {
        self.must = must
        self.should = should
        self.mustNot = mustNot
        self.minShould = minShould
    }

    var proto: Qdrant_Filter {
        var f = Qdrant_Filter()
        f.must = must.map(\.proto)
        f.should = should.map(\.proto)
        f.mustNot = mustNot.map(\.proto)
        if let minShould {
            var ms = Qdrant_MinShould()
            ms.conditions = minShould.conditions.map(\.proto)
            ms.minCount = minShould.count
            f.minShould = ms
        }
        return f
    }
}

// MARK: - Convenience builders

extension Condition {
    /// Match a keyword value (`key == value`).
    public static func match(_ key: String, _ keyword: String) -> Condition {
        .match(key: key, value: .keyword(keyword))
    }
    /// Match an integer value.
    public static func match(_ key: String, _ integer: Int64) -> Condition {
        .match(key: key, value: .integer(integer))
    }
    /// Match a boolean value.
    public static func match(_ key: String, _ boolean: Bool) -> Condition {
        .match(key: key, value: .boolean(boolean))
    }
    /// Numeric range condition.
    public static func range(
        _ key: String, lt: Double? = nil, gt: Double? = nil, gte: Double? = nil, lte: Double? = nil
    ) -> Condition {
        .range(key: key, range: .init(lt: lt, gt: gt, gte: gte, lte: lte))
    }
}
