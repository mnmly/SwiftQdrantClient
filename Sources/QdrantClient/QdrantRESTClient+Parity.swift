import Foundation

/// Full-parity REST methods. Paths mirror the Qdrant OpenAPI surface used by the
/// Python client.
extension QdrantRESTClient {
    // MARK: - Payload (extended)

    @discardableResult
    public func overwritePayload(collection: String, payload: Payload, selector: PointsSelector, wait: Bool = true) async throws -> UpdateResult {
        var body: [String: JSONValue] = ["payload": payload.json]
        applySelector(selector, into: &body)
        return updateResult(try await send(.put, "/collections/\(collection)/points/payload?wait=\(wait)", .object(body)))
    }

    @discardableResult
    public func deletePayload(collection: String, keys: [String], selector: PointsSelector, wait: Bool = true) async throws -> UpdateResult {
        var body: [String: JSONValue] = ["keys": .array(keys.map(JSONValue.string))]
        applySelector(selector, into: &body)
        return updateResult(try await send(.post, "/collections/\(collection)/points/payload/delete?wait=\(wait)", .object(body)))
    }

    @discardableResult
    public func clearPayload(collection: String, selector: PointsSelector, wait: Bool = true) async throws -> UpdateResult {
        let body: JSONValue
        switch selector {
        case .ids(let ids): body = .object(["points": .array(ids.map(\.json))])
        case .filter(let f): body = .object(["filter": f.json])
        }
        return updateResult(try await send(.post, "/collections/\(collection)/points/payload/clear?wait=\(wait)", body))
    }

    @discardableResult
    public func createPayloadIndex(collection: String, fieldName: String, fieldType: FieldType, wait: Bool = true) async throws -> UpdateResult {
        let body: JSONValue = .object(["field_name": .string(fieldName), "field_schema": .string(fieldType.restValue)])
        return updateResult(try await send(.put, "/collections/\(collection)/index?wait=\(wait)", body))
    }

    @discardableResult
    public func deletePayloadIndex(collection: String, fieldName: String, wait: Bool = true) async throws -> UpdateResult {
        updateResult(try await send(.delete, "/collections/\(collection)/index/\(fieldName)?wait=\(wait)"))
    }

    // MARK: - Vectors (extended)

    @discardableResult
    public func updateVectors(collection: String, points: [(id: PointID, vectors: PointVectors)], wait: Bool = true) async throws -> UpdateResult {
        let pts = points.map { pair -> JSONValue in
            let vectorJSON: JSONValue
            switch pair.vectors {
            case .single(let d): vectorJSON = d.json
            case .named(let map): vectorJSON = .object(map.mapValues(\.json))
            }
            return .object(["id": pair.id.json, "vector": vectorJSON])
        }
        let body: JSONValue = .object(["points": .array(pts)])
        return updateResult(try await send(.put, "/collections/\(collection)/points/vectors?wait=\(wait)", body))
    }

    @discardableResult
    public func deleteVectors(collection: String, vectorNames: [String], selector: PointsSelector, wait: Bool = true) async throws -> UpdateResult {
        var body: [String: JSONValue] = ["vector": .array(vectorNames.map(JSONValue.string))]
        applySelector(selector, into: &body)
        return updateResult(try await send(.post, "/collections/\(collection)/points/vectors/delete?wait=\(wait)", .object(body)))
    }

    @discardableResult
    public func createVectorName(collection: String, vectorName: String, config: VectorNameConfig, wait: Bool = true) async throws -> UpdateResult {
        updateResult(try await send(.put, "/collections/\(collection)/vectors/\(vectorName)?wait=\(wait)", config.json))
    }

    @discardableResult
    public func deleteVectorName(collection: String, vectorName: String, wait: Bool = true) async throws -> UpdateResult {
        updateResult(try await send(.delete, "/collections/\(collection)/vectors/\(vectorName)?wait=\(wait)"))
    }

    // MARK: - Query (extended)

    public func facet(collection: String, key: String, filter: Filter? = nil, limit: UInt64? = nil, exact: Bool = false) async throws -> [FacetHit] {
        var body: [String: JSONValue] = ["key": .string(key), "exact": .bool(exact)]
        if let filter { body["filter"] = filter.json }
        if let limit { body["limit"] = .int(Int64(limit)) }
        let result = try await send(.post, "/collections/\(collection)/facet", .object(body))
        return (result["hits"]?.arrayValue ?? []).map { hit in
            FacetHit(value: facetValue(hit["value"]), count: UInt64(hit["count"]?.intValue ?? 0))
        }
    }

    public func queryBatch(collection: String, queries: [QueryRequest]) async throws -> [[ScoredPoint]] {
        let searches = queries.map { $0.restJSON }
        let result = try await send(.post, "/collections/\(collection)/points/query/batch", .object(["searches": .array(searches)]))
        return (result.arrayValue ?? []).map { ($0["points"]?.arrayValue ?? []).map(RESTDecode.scored) }
    }

    public func queryGroups(
        collection: String, groupBy: String, query: Query? = nil, using: String? = nil, prefetch: [Prefetch] = [],
        filter: Filter? = nil, params: SearchParams? = nil, scoreThreshold: Float? = nil, limit: UInt64 = 10,
        groupSize: UInt64 = 3, withPayload: WithPayload = true, withVectors: WithVectors = false
    ) async throws -> [PointGroup] {
        var body: [String: JSONValue] = [
            "group_by": .string(groupBy), "limit": .int(Int64(limit)), "group_size": .int(Int64(groupSize)),
            "with_payload": withPayload.restJSON, "with_vector": withVectors.restJSON,
        ]
        if let query { body["query"] = query.json }
        if let using { body["using"] = .string(using) }
        if !prefetch.isEmpty { body["prefetch"] = .array(prefetch.map(\.json)) }
        if let filter { body["filter"] = filter.json }
        if let params { body["params"] = params.json }
        if let scoreThreshold { body["score_threshold"] = .double(Double(scoreThreshold)) }
        let result = try await send(.post, "/collections/\(collection)/points/query/groups", .object(body))
        return (result["groups"]?.arrayValue ?? []).map(restPointGroup)
    }

    public func searchMatrixPairs(collection: String, filter: Filter? = nil, sample: UInt64 = 10, limit: UInt64 = 3, using: String? = nil) async throws -> [SearchMatrixPair] {
        let result = try await send(.post, "/collections/\(collection)/points/search/matrix/pairs", matrixBody(filter, sample, limit, using))
        return (result["pairs"]?.arrayValue ?? []).map { p in
            SearchMatrixPair(a: PointID(json: p["a"] ?? .int(0)), b: PointID(json: p["b"] ?? .int(0)), score: Float(p["score"]?.doubleValue ?? 0))
        }
    }

    public func searchMatrixOffsets(collection: String, filter: Filter? = nil, sample: UInt64 = 10, limit: UInt64 = 3, using: String? = nil) async throws -> SearchMatrixOffsets {
        let r = try await send(.post, "/collections/\(collection)/points/search/matrix/offsets", matrixBody(filter, sample, limit, using))
        return SearchMatrixOffsets(
            offsetsRow: (r["offsets_row"]?.arrayValue ?? []).compactMap { $0.intValue.map(UInt64.init) },
            offsetsCol: (r["offsets_col"]?.arrayValue ?? []).compactMap { $0.intValue.map(UInt64.init) },
            scores: (r["scores"]?.arrayValue ?? []).compactMap { $0.doubleValue.map(Float.init) },
            ids: (r["ids"]?.arrayValue ?? []).map { PointID(json: $0) })
    }

    // MARK: - Collections (extended)

    @discardableResult
    public func updateCollection(name: String, optimizersConfig: OptimizersConfig? = nil, hnswConfig: HnswConfig? = nil, quantizationConfig: QuantizationConfig? = nil, strictModeConfig: StrictModeConfig? = nil) async throws -> Bool {
        var body: [String: JSONValue] = [:]
        if let optimizersConfig { body["optimizers_config"] = optimizersConfig.json }
        if let hnswConfig { body["hnsw_config"] = hnswConfig.json }
        if let quantizationConfig { body["quantization_config"] = quantizationConfig.json }
        if let strictModeConfig { body["strict_mode_config"] = strictModeConfig.json }
        return (try await send(.patch, "/collections/\(name)", .object(body))).boolValue ?? true
    }

    // MARK: - Aliases

    @discardableResult
    public func updateAliases(_ actions: [AliasOperation]) async throws -> Bool {
        let body: JSONValue = .object(["actions": .array(actions.map(\.restJSON))])
        return (try await send(.post, "/collections/aliases", body)).boolValue ?? true
    }

    public func listCollectionAliases(_ collection: String) async throws -> [AliasDescription] {
        aliasList(try await send(.get, "/collections/\(collection)/aliases"))
    }

    public func listAliases() async throws -> [AliasDescription] {
        aliasList(try await send(.get, "/aliases"))
    }

    // MARK: - Shard keys

    @discardableResult
    public func createShardKey(collection: String, shardKey: ShardKey, shardsNumber: UInt32? = nil, replicationFactor: UInt32? = nil) async throws -> Bool {
        var body: [String: JSONValue] = ["shard_key": shardKey.restJSON]
        if let shardsNumber { body["shards_number"] = .int(Int64(shardsNumber)) }
        if let replicationFactor { body["replication_factor"] = .int(Int64(replicationFactor)) }
        return (try await send(.put, "/collections/\(collection)/shards", .object(body))).boolValue ?? true
    }

    @discardableResult
    public func deleteShardKey(collection: String, shardKey: ShardKey) async throws -> Bool {
        (try await send(.post, "/collections/\(collection)/shards/delete", .object(["shard_key": shardKey.restJSON]))).boolValue ?? true
    }

    public func listShardKeys(collection: String) async throws -> [ShardKey] {
        let result = try await send(.get, "/collections/\(collection)/shards")
        return (result["shard_keys"]?.arrayValue ?? []).compactMap { shardKeyFromJSON($0["shard_key"] ?? $0) }
    }

    // MARK: - Snapshots

    @discardableResult
    public func createSnapshot(collection: String) async throws -> SnapshotDescription? {
        snapshot(try await send(.post, "/collections/\(collection)/snapshots?wait=true"))
    }
    public func listSnapshots(collection: String) async throws -> [SnapshotDescription] {
        (try await send(.get, "/collections/\(collection)/snapshots")).arrayValue?.compactMap(snapshot) ?? []
    }
    public func deleteSnapshot(collection: String, snapshotName: String) async throws {
        _ = try await send(.delete, "/collections/\(collection)/snapshots/\(snapshotName)?wait=true")
    }
    @discardableResult
    public func createFullSnapshot() async throws -> SnapshotDescription? {
        snapshot(try await send(.post, "/snapshots?wait=true"))
    }
    public func listFullSnapshots() async throws -> [SnapshotDescription] {
        (try await send(.get, "/snapshots")).arrayValue?.compactMap(snapshot) ?? []
    }
    public func deleteFullSnapshot(snapshotName: String) async throws {
        _ = try await send(.delete, "/snapshots/\(snapshotName)?wait=true")
    }
    @discardableResult
    public func recoverSnapshot(collection: String, location: String) async throws -> Bool {
        (try await send(.put, "/collections/\(collection)/snapshots/recover", .object(["location": .string(location)]))).boolValue ?? true
    }
    public func listShardSnapshots(collection: String, shardId: UInt32) async throws -> [SnapshotDescription] {
        (try await send(.get, "/collections/\(collection)/shards/\(shardId)/snapshots")).arrayValue?.compactMap(snapshot) ?? []
    }
    @discardableResult
    public func createShardSnapshot(collection: String, shardId: UInt32) async throws -> SnapshotDescription? {
        snapshot(try await send(.post, "/collections/\(collection)/shards/\(shardId)/snapshots?wait=true"))
    }
    public func deleteShardSnapshot(collection: String, shardId: UInt32, snapshotName: String) async throws {
        _ = try await send(.delete, "/collections/\(collection)/shards/\(shardId)/snapshots/\(snapshotName)?wait=true")
    }
    @discardableResult
    public func recoverShardSnapshot(collection: String, shardId: UInt32, location: String) async throws -> Bool {
        (try await send(.put, "/collections/\(collection)/shards/\(shardId)/snapshots/recover", .object(["location": .string(location)]))).boolValue ?? true
    }

    // MARK: - Cluster / service

    public func info() async throws -> VersionInfo {
        let r = try await sendRaw(.get, "/")
        return VersionInfo(title: r["title"]?.stringValue ?? "", version: r["version"]?.stringValue ?? "", commit: r["commit"]?.stringValue)
    }
    public func collectionClusterInfo(collection: String) async throws -> JSONValue {
        try await send(.get, "/collections/\(collection)/cluster")
    }
    @discardableResult
    public func clusterCollectionUpdate(collection: String, operation: ClusterOperation) async throws -> Bool {
        (try await send(.post, "/collections/\(collection)/cluster", operation.restJSON)).boolValue ?? true
    }
    public func clusterStatus() async throws -> JSONValue { try await send(.get, "/cluster") }
    @discardableResult
    public func recoverCurrentPeer() async throws -> Bool { (try await send(.post, "/cluster/recover")).boolValue ?? true }
    @discardableResult
    public func removePeer(peerId: UInt64, force: Bool = false) async throws -> Bool {
        (try await send(.delete, "/cluster/peer/\(peerId)?force=\(force)")).boolValue ?? true
    }
    public func getOptimizations(collection: String) async throws -> JSONValue {
        try await send(.get, "/collections/\(collection)/optimizations")
    }
    public func clusterTelemetry() async throws -> JSONValue { try await send(.get, "/cluster/telemetry") }

    // MARK: - Helpers

    private func applySelector(_ selector: PointsSelector, into body: inout [String: JSONValue]) {
        switch selector {
        case .ids(let ids): body["points"] = .array(ids.map(\.json))
        case .filter(let f): body["filter"] = f.json
        }
    }
    private func matrixBody(_ filter: Filter?, _ sample: UInt64, _ limit: UInt64, _ using: String?) -> JSONValue {
        var body: [String: JSONValue] = ["sample": .int(Int64(sample)), "limit": .int(Int64(limit))]
        if let filter { body["filter"] = filter.json }
        if let using { body["using"] = .string(using) }
        return .object(body)
    }
    private func snapshot(_ json: JSONValue) -> SnapshotDescription? {
        guard let name = json["name"]?.stringValue else { return nil }
        return SnapshotDescription(name: name, size: json["size"]?.intValue ?? 0, checksum: json["checksum"]?.stringValue)
    }
    private func aliasList(_ json: JSONValue) -> [AliasDescription] {
        (json["aliases"]?.arrayValue ?? []).compactMap {
            guard let a = $0["alias_name"]?.stringValue, let c = $0["collection_name"]?.stringValue else { return nil }
            return AliasDescription(aliasName: a, collectionName: c)
        }
    }
    private func facetValue(_ json: JSONValue?) -> FacetValue {
        guard let json else { return .string("") }
        if let s = json.stringValue { return .string(s) }
        if let b = json.boolValue { return .bool(b) }
        if let i = json.intValue { return .integer(i) }
        return .string("")
    }
    private func restPointGroup(_ json: JSONValue) -> PointGroup {
        let id: GroupId
        if let i = json["id"]?.intValue { id = .integer(i) }
        else if let s = json["id"]?.stringValue { id = .string(s) }
        else { id = .unsigned(0) }
        let hits = (json["hits"]?.arrayValue ?? []).map(RESTDecode.scored)
        let lookup = json["lookup"].flatMap { l -> RetrievedPoint? in
            if case .null = l { return nil }; return RESTDecode.retrieved(l)
        }
        return PointGroup(id: id, hits: hits, lookup: lookup)
    }
    private func shardKeyFromJSON(_ json: JSONValue) -> ShardKey? {
        if let s = json.stringValue { return .keyword(s) }
        if let i = json.intValue { return .number(UInt64(i)) }
        return nil
    }
}
