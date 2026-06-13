import Foundation

// MARK: - JSONValue

/// A minimal, `Codable` JSON value used to build/parse REST request and response
/// bodies — and the public return type for admin/telemetry endpoints whose
/// server responses are deeply nested (cluster status, telemetry, optimizations).
public enum JSONValue: Codable, Sendable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let i = try? c.decode(Int64.self) { self = .int(i); return }
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON"))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    // Convenience accessors.
    public var objectValue: [String: JSONValue]? { if case .object(let o) = self { return o } else { return nil } }
    public var arrayValue: [JSONValue]? { if case .array(let a) = self { return a } else { return nil } }
    public var stringValue: String? { if case .string(let s) = self { return s } else { return nil } }
    public var doubleValue: Double? {
        switch self { case .double(let d): return d; case .int(let i): return Double(i); default: return nil }
    }
    public var intValue: Int64? {
        switch self { case .int(let i): return i; case .double(let d): return Int64(d); default: return nil }
    }
    public var boolValue: Bool? { if case .bool(let b) = self { return b } else { return nil } }
    public subscript(_ key: String) -> JSONValue? { objectValue?[key] }
}

// MARK: - Model → JSON (request encoding)

extension Distance {
    var restValue: String {
        switch self {
        case .cosine: return "Cosine"
        case .euclid: return "Euclid"
        case .dot: return "Dot"
        case .manhattan: return "Manhattan"
        }
    }
}

extension PointID {
    var json: JSONValue {
        switch self { case .int(let n): return .int(Int64(n)); case .uuid(let s): return .string(s) }
    }
    init(json: JSONValue) {
        if let i = json.intValue { self = .int(UInt64(i)) }
        else if let s = json.stringValue { self = .uuid(s) }
        else { self = .int(0) }
    }
}

extension QdrantValue {
    var json: JSONValue {
        switch self {
        case .null: return .null
        case .bool(let b): return .bool(b)
        case .int(let i): return .int(i)
        case .double(let d): return .double(d)
        case .string(let s): return .string(s)
        case .list(let xs): return .array(xs.map(\.json))
        case .object(let o): return .object(o.mapValues(\.json))
        }
    }
    init(json: JSONValue) {
        switch json {
        case .null: self = .null
        case .bool(let b): self = .bool(b)
        case .int(let i): self = .int(i)
        case .double(let d): self = .double(d)
        case .string(let s): self = .string(s)
        case .array(let a): self = .list(a.map(QdrantValue.init(json:)))
        case .object(let o): self = .object(o.mapValues(QdrantValue.init(json:)))
        }
    }
}

extension Payload {
    var json: JSONValue { .object(mapValues(\.json)) }
    init(json: JSONValue) { self = (json.objectValue ?? [:]).mapValues(QdrantValue.init(json:)) }
}

extension VectorData {
    var json: JSONValue {
        switch self {
        case .dense(let d): return .array(d.map { .double(Double($0)) })
        case .sparse(let i, let v):
            return .object(["indices": .array(i.map { .int(Int64($0)) }),
                            "values": .array(v.map { .double(Double($0)) })])
        case .multiDense(let rows):
            return .array(rows.map { .array($0.map { .double(Double($0)) }) })
        }
    }
}

extension VectorInput {
    var json: JSONValue {
        switch self {
        case .dense(let d): return .array(d.map { .double(Double($0)) })
        case .sparse(let i, let v):
            return .object(["indices": .array(i.map { .int(Int64($0)) }),
                            "values": .array(v.map { .double(Double($0)) })])
        case .multiDense(let rows): return .array(rows.map { .array($0.map { .double(Double($0)) }) })
        case .id(let id): return id.json
        }
    }
}

extension FieldType {
    var restValue: String {
        switch self {
        case .keyword: return "keyword"
        case .integer: return "integer"
        case .float: return "float"
        case .geo: return "geo"
        case .text: return "text"
        case .bool: return "bool"
        case .datetime: return "datetime"
        case .uuid: return "uuid"
        }
    }
}

extension ShardKey {
    var restJSON: JSONValue {
        switch self { case .keyword(let s): return .string(s); case .number(let n): return .int(Int64(n)) }
    }
}

extension AliasOperation {
    var restJSON: JSONValue {
        switch self {
        case .create(let collection, let alias):
            return .object(["create_alias": .object(["collection_name": .string(collection), "alias_name": .string(alias)])])
        case .delete(let alias):
            return .object(["delete_alias": .object(["alias_name": .string(alias)])])
        case .rename(let oldAlias, let newAlias):
            return .object(["rename_alias": .object(["old_alias_name": .string(oldAlias), "new_alias_name": .string(newAlias)])])
        }
    }
}

extension ClusterOperation {
    var restJSON: JSONValue {
        switch self {
        case .moveShard(let s, let f, let t):
            return .object(["move_shard": .object(["shard_id": .int(Int64(s)), "from_peer_id": .int(Int64(f)), "to_peer_id": .int(Int64(t))])])
        case .replicateShard(let s, let f, let t):
            return .object(["replicate_shard": .object(["shard_id": .int(Int64(s)), "from_peer_id": .int(Int64(f)), "to_peer_id": .int(Int64(t))])])
        case .abortTransfer(let s, let f, let t):
            return .object(["abort_transfer": .object(["shard_id": .int(Int64(s)), "from_peer_id": .int(Int64(f)), "to_peer_id": .int(Int64(t))])])
        case .dropReplica(let s, let p):
            return .object(["drop_replica": .object(["shard_id": .int(Int64(s)), "peer_id": .int(Int64(p))])])
        }
    }
}

extension QueryRequest {
    /// REST body for a single batched query.
    var restJSON: JSONValue {
        var o: [String: JSONValue] = [
            "limit": .int(Int64(limit)), "offset": .int(Int64(offset)),
            "with_payload": withPayload.restJSON, "with_vector": withVectors.restJSON,
        ]
        if let query { o["query"] = query.json }
        if let using { o["using"] = .string(using) }
        if !prefetch.isEmpty { o["prefetch"] = .array(prefetch.map(\.json)) }
        if let filter { o["filter"] = filter.json }
        if let params { o["params"] = params.json }
        if let scoreThreshold { o["score_threshold"] = .double(Double(scoreThreshold)) }
        return .object(o)
    }
}

extension VectorDatatype {
    var restValue: String {
        switch self { case .float32: return "float32"; case .uint8: return "uint8"; case .float16: return "float16" }
    }
}

extension VectorParams {
    var json: JSONValue {
        var o: [String: JSONValue] = ["size": .int(Int64(size)), "distance": .string(distance.restValue)]
        if let onDisk { o["on_disk"] = .bool(onDisk) }
        if let datatype { o["datatype"] = .string(datatype.restValue) }
        if let h = hnswConfig { o["hnsw_config"] = h.json }
        if let q = quantizationConfig { o["quantization_config"] = q.json }
        if let mv = multivectorComparator { o["multivector_config"] = .object(["comparator": .string(mv == .maxSim ? "max_sim" : "max_sim")]) }
        return .object(o)
    }
}

extension HnswConfig {
    var json: JSONValue {
        var o: [String: JSONValue] = [:]
        if let m { o["m"] = .int(Int64(m)) }
        if let efConstruct { o["ef_construct"] = .int(Int64(efConstruct)) }
        if let fullScanThreshold { o["full_scan_threshold"] = .int(Int64(fullScanThreshold)) }
        if let maxIndexingThreads { o["max_indexing_threads"] = .int(Int64(maxIndexingThreads)) }
        if let onDisk { o["on_disk"] = .bool(onDisk) }
        if let payloadM { o["payload_m"] = .int(Int64(payloadM)) }
        return .object(o)
    }
}

extension OptimizersConfig {
    var json: JSONValue {
        var o: [String: JSONValue] = [:]
        if let deletedThreshold { o["deleted_threshold"] = .double(deletedThreshold) }
        if let vacuumMinVectorNumber { o["vacuum_min_vector_number"] = .int(Int64(vacuumMinVectorNumber)) }
        if let defaultSegmentNumber { o["default_segment_number"] = .int(Int64(defaultSegmentNumber)) }
        if let maxSegmentSize { o["max_segment_size"] = .int(Int64(maxSegmentSize)) }
        if let memmapThreshold { o["memmap_threshold"] = .int(Int64(memmapThreshold)) }
        if let indexingThreshold { o["indexing_threshold"] = .int(Int64(indexingThreshold)) }
        if let flushIntervalSec { o["flush_interval_sec"] = .int(Int64(flushIntervalSec)) }
        if let maxOptimizationThreads { o["max_optimization_threads"] = .int(Int64(maxOptimizationThreads)) }
        return .object(o)
    }
}

extension WalConfig {
    var json: JSONValue {
        var o: [String: JSONValue] = [:]
        if let walCapacityMb { o["wal_capacity_mb"] = .int(Int64(walCapacityMb)) }
        if let walSegmentsAhead { o["wal_segments_ahead"] = .int(Int64(walSegmentsAhead)) }
        return .object(o)
    }
}

extension QuantizationConfig {
    var json: JSONValue {
        switch self {
        case .scalar(let s):
            var inner: [String: JSONValue] = ["type": .string("int8")]
            if let q = s.quantile { inner["quantile"] = .double(Double(q)) }
            if let r = s.alwaysRam { inner["always_ram"] = .bool(r) }
            return .object(["scalar": .object(inner)])
        case .product(let p):
            var inner: [String: JSONValue] = ["compression": .string(p.compression.restValue)]
            if let r = p.alwaysRam { inner["always_ram"] = .bool(r) }
            return .object(["product": .object(inner)])
        case .binary(let b):
            var inner: [String: JSONValue] = [:]
            if let r = b.alwaysRam { inner["always_ram"] = .bool(r) }
            return .object(["binary": .object(inner)])
        }
    }
}

extension CompressionRatio {
    var restValue: String {
        switch self {
        case .x4: return "x4"; case .x8: return "x8"; case .x16: return "x16"
        case .x32: return "x32"; case .x64: return "x64"
        }
    }
}

extension QuantizationSearchParams {
    var json: JSONValue {
        var o: [String: JSONValue] = [:]
        if let ignore { o["ignore"] = .bool(ignore) }
        if let rescore { o["rescore"] = .bool(rescore) }
        if let oversampling { o["oversampling"] = .double(oversampling) }
        return .object(o)
    }
}

extension SparseVectorParams {
    var json: JSONValue {
        var index: [String: JSONValue] = [:]
        if let onDisk { index["on_disk"] = .bool(onDisk) }
        if let fullScanThreshold { index["full_scan_threshold"] = .int(Int64(fullScanThreshold)) }
        if let datatype { index["datatype"] = .string(datatype.restValue) }
        var o: [String: JSONValue] = [:]
        if !index.isEmpty { o["index"] = .object(index) }
        if let modifier { o["modifier"] = .string(modifier == .idf ? "idf" : "none") }
        return .object(o)
    }
}

extension MatchValue {
    var json: JSONValue {
        switch self {
        case .keyword(let s): return .object(["value": .string(s)])
        case .integer(let i): return .object(["value": .int(i)])
        case .boolean(let b): return .object(["value": .bool(b)])
        case .text(let t), .textAny(let t): return .object(["text": .string(t)])
        case .phrase(let p): return .object(["phrase": .string(p)])
        case .anyKeywords(let v): return .object(["any": .array(v.map(JSONValue.string))])
        case .anyIntegers(let v): return .object(["any": .array(v.map(JSONValue.int))])
        case .exceptKeywords(let v): return .object(["except": .array(v.map(JSONValue.string))])
        case .exceptIntegers(let v): return .object(["except": .array(v.map(JSONValue.int))])
        }
    }
}

private func geoJSON(_ p: GeoPoint) -> JSONValue {
    .object(["lat": .double(p.lat), "lon": .double(p.lon)])
}

extension Condition {
    var json: JSONValue {
        switch self {
        case .match(let key, let value):
            return .object(["key": .string(key), "match": value.json])
        case .range(let key, let r):
            var range: [String: JSONValue] = [:]
            if let v = r.gt { range["gt"] = .double(v) }
            if let v = r.gte { range["gte"] = .double(v) }
            if let v = r.lt { range["lt"] = .double(v) }
            if let v = r.lte { range["lte"] = .double(v) }
            return .object(["key": .string(key), "range": .object(range)])
        case .geoRadius(let key, let center, let radius):
            return .object(["key": .string(key),
                            "geo_radius": .object(["center": geoJSON(center), "radius": .double(Double(radius))])])
        case .geoBoundingBox(let key, let tl, let br):
            return .object(["key": .string(key),
                            "geo_bounding_box": .object(["top_left": geoJSON(tl), "bottom_right": geoJSON(br)])])
        case .hasID(let ids):
            return .object(["has_id": .array(ids.map(\.json))])
        case .hasVector(let name):
            return .object(["has_vector": .string(name)])
        case .isEmpty(let key):
            return .object(["is_empty": .object(["key": .string(key)])])
        case .isNull(let key):
            return .object(["is_null": .object(["key": .string(key)])])
        case .nested(let key, let filter):
            return .object(["nested": .object(["key": .string(key), "filter": filter.json])])
        case .filter(let filter):
            return filter.json
        }
    }
}

extension Filter {
    var json: JSONValue {
        var o: [String: JSONValue] = [:]
        if !must.isEmpty { o["must"] = .array(must.map(\.json)) }
        if !should.isEmpty { o["should"] = .array(should.map(\.json)) }
        if !mustNot.isEmpty { o["must_not"] = .array(mustNot.map(\.json)) }
        if let ms = minShould {
            o["min_should"] = .object(["conditions": .array(ms.conditions.map(\.json)),
                                       "min_count": .int(Int64(ms.count))])
        }
        return .object(o)
    }
}

extension RecommendStrategy {
    var restValue: String {
        switch self {
        case .averageVector: return "average_vector"
        case .bestScore: return "best_score"
        case .sumScores: return "sum_scores"
        }
    }
}

extension Query {
    var json: JSONValue {
        switch self {
        case .nearest(let v): return .object(["nearest": v.json])
        case .nearestWithMmr(let v, let mmr):
            var m: [String: JSONValue] = [:]
            if let d = mmr.diversity { m["diversity"] = .double(Double(d)) }
            if let c = mmr.candidatesLimit { m["candidates_limit"] = .int(Int64(c)) }
            return .object(["nearest": v.json, "mmr": .object(m)])
        case .recommend(let input):
            var r: [String: JSONValue] = [
                "positive": .array(input.positive.map(\.json)),
                "negative": .array(input.negative.map(\.json)),
            ]
            if let s = input.strategy { r["strategy"] = .string(s.restValue) }
            return .object(["recommend": .object(r)])
        case .discover(let target, let context):
            return .object(["discover": .object([
                "target": target.json,
                "context": .array(context.map { .object(["positive": $0.positive.json, "negative": $0.negative.json]) }),
            ])])
        case .context(let pairs):
            return .object(["context": .array(pairs.map {
                .object(["positive": $0.positive.json, "negative": $0.negative.json])
            })])
        case .orderBy(let o):
            var ob: [String: JSONValue] = ["key": .string(o.key)]
            if let d = o.direction { ob["direction"] = .string(d == .asc ? "asc" : "desc") }
            return .object(["order_by": .object(ob)])
        case .fusion(let f): return .object(["fusion": .string(f == .rrf ? "rrf" : "dbsf")])
        case .sampleRandom: return .object(["sample": .string("random")])
        case .formula(let f): return f.json
        case .relevanceFeedback(let r): return .object(["relevance_feedback": r.json])
        }
    }
}

extension Prefetch {
    var json: JSONValue {
        var o: [String: JSONValue] = [:]
        if let q = query { o["query"] = q.json }
        if let u = using { o["using"] = .string(u) }
        if let f = filter { o["filter"] = f.json }
        if let p = params { o["params"] = p.json }
        if let s = scoreThreshold { o["score_threshold"] = .double(Double(s)) }
        if let l = limit { o["limit"] = .int(Int64(l)) }
        if !prefetch.isEmpty { o["prefetch"] = .array(prefetch.map(\.json)) }
        return .object(o)
    }
}

extension PointStruct {
    var json: JSONValue {
        var o: [String: JSONValue] = ["id": id.json, "payload": payload.json]
        switch vectors {
        case .single(let data): o["vector"] = data.json
        case .named(let map): o["vector"] = .object(map.mapValues(\.json))
        }
        return .object(o)
    }
}

// MARK: - JSON → result decoding helpers

extension VectorData {
    /// Decode from a REST vector JSON (dense array, sparse object, or multi array).
    init?(restJSON json: JSONValue) {
        switch json {
        case .array(let items):
            if let first = items.first, case .array = first {
                self = .multiDense(items.map { ($0.arrayValue ?? []).compactMap { $0.doubleValue.map(Float.init) } })
            } else {
                self = .dense(items.compactMap { $0.doubleValue.map(Float.init) })
            }
        case .object(let o):
            let idx = (o["indices"]?.arrayValue ?? []).compactMap { $0.intValue.map { UInt32($0) } }
            let val = (o["values"]?.arrayValue ?? []).compactMap { $0.doubleValue.map(Float.init) }
            self = .sparse(indices: idx, values: val)
        default:
            return nil
        }
    }
}

enum RESTDecode {
    static func vectors(_ json: JSONValue?) -> (vector: [Float]?, named: [String: VectorData]) {
        guard let json else { return (nil, [:]) }
        switch json {
        case .array(let items):
            return (items.compactMap { $0.doubleValue.map(Float.init) }, [:])
        case .object(let o):
            return (nil, o.compactMapValues { VectorData(restJSON: $0) })
        default:
            return (nil, [:])
        }
    }

    static func scored(_ json: JSONValue) -> ScoredPoint {
        let o = json.objectValue ?? [:]
        let (vec, named) = vectors(o["vector"])
        return ScoredPoint(
            id: PointID(json: o["id"] ?? .int(0)),
            score: Float(o["score"]?.doubleValue ?? 0),
            version: UInt64(o["version"]?.intValue ?? 0),
            payload: Payload(json: o["payload"] ?? .object([:])),
            vector: vec, vectors: named)
    }

    static func retrieved(_ json: JSONValue) -> RetrievedPoint {
        let o = json.objectValue ?? [:]
        let (vec, named) = vectors(o["vector"])
        return RetrievedPoint(
            id: PointID(json: o["id"] ?? .int(0)),
            payload: Payload(json: o["payload"] ?? .object([:])),
            vector: vec, vectors: named)
    }
}
