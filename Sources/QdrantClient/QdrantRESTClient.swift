import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A Qdrant client over the REST/HTTP API (`URLSession`), implementing the same
/// ``QdrantClientProtocol`` as the gRPC and local backends.
///
/// Qdrant serves REST on port 6333 by default.
public actor QdrantRESTClient: QdrantClientProtocol {
    private let baseURL: URL
    private let apiKey: String?
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(host: String = "localhost", port: Int = 6333, useTLS: Bool = false, apiKey: String? = nil) {
        let scheme = useTLS ? "https" : "http"
        self.baseURL = URL(string: "\(scheme)://\(host):\(port)")!
        self.apiKey = apiKey
        self.session = URLSession(configuration: .ephemeral)
    }

    public init(url: URL, apiKey: String? = nil) {
        self.baseURL = url
        self.apiKey = apiKey
        self.session = URLSession(configuration: .ephemeral)
    }

    // MARK: - Collections

    @discardableResult
    public func createCollection(
        name: String,
        vectors: VectorsConfiguration,
        sparseVectors: [String: SparseVectorParams]? = nil,
        hnswConfig: HnswConfig? = nil,
        optimizersConfig: OptimizersConfig? = nil,
        onDiskPayload: Bool? = nil,
        shardNumber: UInt32? = nil,
        replicationFactor: UInt32? = nil
    ) async throws -> Bool {
        var body: [String: JSONValue] = [:]
        switch vectors {
        case .single(let p): body["vectors"] = p.json
        case .named(let map): body["vectors"] = .object(map.mapValues(\.json))
        }
        if let sparseVectors { body["sparse_vectors"] = .object(sparseVectors.mapValues(\.json)) }
        if let hnswConfig { body["hnsw_config"] = hnswConfig.json }
        if let optimizersConfig { body["optimizers_config"] = optimizersConfig.json }
        if let onDiskPayload { body["on_disk_payload"] = .bool(onDiskPayload) }
        if let shardNumber { body["shard_number"] = .int(Int64(shardNumber)) }
        if let replicationFactor { body["replication_factor"] = .int(Int64(replicationFactor)) }
        let result = try await send(.put, "/collections/\(name)", .object(body))
        return result.boolValue ?? true
    }

    public func collectionExists(_ name: String) async throws -> Bool {
        let result = try await send(.get, "/collections/\(name)/exists")
        return result["exists"]?.boolValue ?? false
    }

    public func listCollections() async throws -> [String] {
        let result = try await send(.get, "/collections")
        return (result["collections"]?.arrayValue ?? []).compactMap { $0["name"]?.stringValue }
    }

    @discardableResult
    public func deleteCollection(_ name: String) async throws -> Bool {
        let result = try await send(.delete, "/collections/\(name)")
        return result.boolValue ?? true
    }

    public func getCollection(_ name: String) async throws -> CollectionInfo {
        let result = try await send(.get, "/collections/\(name)")
        let status: CollectionStatus
        switch result["status"]?.stringValue {
        case "green": status = .green
        case "yellow": status = .yellow
        case "red": status = .red
        case "grey": status = .grey
        default: status = .unknown
        }
        return CollectionInfo(
            status: status,
            pointsCount: UInt64(result["points_count"]?.intValue ?? 0),
            segmentsCount: UInt64(result["segments_count"]?.intValue ?? 0),
            indexedVectorsCount: UInt64(result["indexed_vectors_count"]?.intValue ?? 0))
    }

    // MARK: - Write

    @discardableResult
    public func upsert(collection: String, points: [PointStruct], wait: Bool = true) async throws -> UpdateResult {
        let body: JSONValue = .object(["points": .array(points.map(\.json))])
        let result = try await send(.put, "/collections/\(collection)/points?wait=\(wait)", body)
        return updateResult(result)
    }

    @discardableResult
    public func delete(collection: String, selector: PointsSelector, wait: Bool = true) async throws -> UpdateResult {
        let body: JSONValue
        switch selector {
        case .ids(let ids): body = .object(["points": .array(ids.map(\.json))])
        case .filter(let f): body = .object(["filter": f.json])
        }
        let result = try await send(.post, "/collections/\(collection)/points/delete?wait=\(wait)", body)
        return updateResult(result)
    }

    @discardableResult
    public func setPayload(
        collection: String, payload: Payload, selector: PointsSelector,
        key: String? = nil, wait: Bool = true
    ) async throws -> UpdateResult {
        var body: [String: JSONValue] = ["payload": payload.json]
        switch selector {
        case .ids(let ids): body["points"] = .array(ids.map(\.json))
        case .filter(let f): body["filter"] = f.json
        }
        if let key { body["key"] = .string(key) }
        let result = try await send(.post, "/collections/\(collection)/points/payload?wait=\(wait)", .object(body))
        return updateResult(result)
    }

    // MARK: - Read

    public func retrieve(
        collection: String, ids: [PointID], withPayload: Bool = true, withVectors: Bool = false
    ) async throws -> [RetrievedPoint] {
        let body: JSONValue = .object([
            "ids": .array(ids.map(\.json)),
            "with_payload": .bool(withPayload),
            "with_vector": .bool(withVectors),
        ])
        let result = try await send(.post, "/collections/\(collection)/points", body)
        return (result.arrayValue ?? []).map(RESTDecode.retrieved)
    }

    public func scroll(
        collection: String, filter: Filter? = nil, limit: UInt32 = 10, offset: PointID? = nil,
        withPayload: Bool = true, withVectors: Bool = false, orderBy: OrderBy? = nil
    ) async throws -> (points: [RetrievedPoint], nextOffset: PointID?) {
        var body: [String: JSONValue] = [
            "limit": .int(Int64(limit)),
            "with_payload": .bool(withPayload),
            "with_vector": .bool(withVectors),
        ]
        if let filter { body["filter"] = filter.json }
        if let offset { body["offset"] = offset.json }
        if let orderBy {
            var ob: [String: JSONValue] = ["key": .string(orderBy.key)]
            if let d = orderBy.direction { ob["direction"] = .string(d == .asc ? "asc" : "desc") }
            body["order_by"] = .object(ob)
        }
        let result = try await send(.post, "/collections/\(collection)/points/scroll", .object(body))
        let points = (result["points"]?.arrayValue ?? []).map(RESTDecode.retrieved)
        let next = result["next_page_offset"].flatMap { j -> PointID? in
            if case .null = j { return nil }
            return PointID(json: j)
        }
        return (points, next)
    }

    public func count(collection: String, filter: Filter? = nil, exact: Bool = true) async throws -> UInt64 {
        var body: [String: JSONValue] = ["exact": .bool(exact)]
        if let filter { body["filter"] = filter.json }
        let result = try await send(.post, "/collections/\(collection)/points/count", .object(body))
        return UInt64(result["count"]?.intValue ?? 0)
    }

    // MARK: - Query

    public func query(
        collection: String, query: Query? = nil, using: String? = nil, prefetch: [Prefetch] = [],
        filter: Filter? = nil, params: SearchParams? = nil, scoreThreshold: Float? = nil,
        limit: UInt64 = 10, offset: UInt64 = 0, withPayload: Bool = true, withVectors: Bool = false
    ) async throws -> [ScoredPoint] {
        var body: [String: JSONValue] = [
            "limit": .int(Int64(limit)),
            "offset": .int(Int64(offset)),
            "with_payload": .bool(withPayload),
            "with_vector": .bool(withVectors),
        ]
        if let query { body["query"] = query.json }
        if let using { body["using"] = .string(using) }
        if !prefetch.isEmpty { body["prefetch"] = .array(prefetch.map(\.json)) }
        if let filter { body["filter"] = filter.json }
        if let params { body["params"] = params.json }
        if let scoreThreshold { body["score_threshold"] = .double(Double(scoreThreshold)) }
        let result = try await send(.post, "/collections/\(collection)/points/query", .object(body))
        return (result["points"]?.arrayValue ?? []).map(RESTDecode.scored)
    }

    public func close() async throws { session.invalidateAndCancel() }

    // MARK: - HTTP plumbing

    enum Method: String { case get = "GET", post = "POST", put = "PUT", delete = "DELETE", patch = "PATCH" }

    /// Send a request and return the decoded `result` field of the envelope.
    @discardableResult
    func send(_ method: Method, _ path: String, _ body: JSONValue? = nil) async throws -> JSONValue {
        try await sendRaw(method, path, body)["result"] ?? .null
    }

    /// Send a request and return the full decoded response body (no `result` unwrap).
    @discardableResult
    func sendRaw(_ method: Method, _ path: String, _ body: JSONValue? = nil) async throws -> JSONValue {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw QdrantError.unexpectedResponse("bad path \(path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey { request.setValue(apiKey, forHTTPHeaderField: "api-key") }
        if let body { request.httpBody = try encoder.encode(body) }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw QdrantError.unexpectedResponse("non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw QdrantError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return try decoder.decode(JSONValue.self, from: data)
    }

    func updateResult(_ result: JSONValue) -> UpdateResult {
        let status: UpdateStatus
        switch result["status"]?.stringValue {
        case "acknowledged": status = .acknowledged
        case "completed": status = .completed
        default: status = .unknown
        }
        return UpdateResult(operationId: result["operation_id"]?.intValue.map(UInt64.init), status: status)
    }
}
