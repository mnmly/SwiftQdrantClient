import Foundation
import GRPC
import NIOCore
import NIOHPACK
import NIOPosix
import QdrantProtos

/// A high-level async client for Qdrant over gRPC.
///
/// This is the Swift counterpart of the Python `QdrantClient`. It owns a gRPC
/// channel and an `EventLoopGroup`, exposing async methods that map onto the
/// generated service clients. Call ``close()`` when finished.
///
/// ```swift
/// let client = try QdrantClient(configuration: .init(host: "localhost"))
/// try await client.createCollection(name: "demo", size: 4, distance: .cosine)
/// try await client.upsert(collection: "demo", points: [
///     .init(id: 1, vector: [0.1, 0.2, 0.3, 0.4], payload: ["city": "Berlin"])
/// ])
/// let hits = try await client.query(collection: "demo", vector: [0.1, 0.2, 0.3, 0.4], limit: 3)
/// try await client.close()
/// ```
public actor QdrantClient {
    private let group: EventLoopGroup
    private let channel: GRPCChannel
    private let callOptions: CallOptions
    private var isClosed = false

    let collections: Qdrant_CollectionsAsyncClient
    let points: Qdrant_PointsAsyncClient
    let service: Qdrant_QdrantAsyncClient
    let snapshots: Qdrant_SnapshotsAsyncClient

    /// REST client used for operations the gRPC API doesn't expose
    /// (snapshot recovery, cluster status, peers, telemetry, optimizations).
    let rest: QdrantRESTClient

    /// Create a client and open the gRPC channel.
    public init(configuration: QdrantConfiguration) throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.group = group

        let security: GRPCChannelPool.Configuration.TransportSecurity =
            configuration.useTLS ? .tls(.makeClientDefault(compatibleWith: group)) : .plaintext

        self.channel = try GRPCChannelPool.with(
            target: .host(configuration.host, port: configuration.grpcPort),
            transportSecurity: security,
            eventLoopGroup: group
        ) { config in
            // Default is 4 MB, which is too small for large named/multivectors
            // (e.g. dense per-patch feature maps). Allow up to 256 MB on receive.
            config.maximumReceiveMessageLength = 256 * 1024 * 1024
        }

        var metadata: [(String, String)] = []
        if let apiKey = configuration.apiKey {
            metadata.append(("api-key", apiKey))
        }
        var options = CallOptions(customMetadata: HPACKHeaders(metadata))
        if let timeout = configuration.timeout {
            options.timeLimit = TimeLimit.timeout(TimeAmount.nanoseconds(Int64(timeout * 1_000_000_000)))
        }
        self.callOptions = options

        self.collections = Qdrant_CollectionsAsyncClient(channel: channel, defaultCallOptions: options)
        self.points = Qdrant_PointsAsyncClient(channel: channel, defaultCallOptions: options)
        self.service = Qdrant_QdrantAsyncClient(channel: channel, defaultCallOptions: options)
        self.snapshots = Qdrant_SnapshotsAsyncClient(channel: channel, defaultCallOptions: options)
        self.rest = QdrantRESTClient(
            host: configuration.host, port: configuration.restPort,
            useTLS: configuration.useTLS, apiKey: configuration.apiKey)
    }

    /// Convenience initializer from host/port.
    public init(host: String = "localhost", grpcPort: Int = 6334, apiKey: String? = nil) throws {
        try self.init(configuration: .init(host: host, grpcPort: grpcPort, apiKey: apiKey))
    }

    /// Gracefully close the channel and shut down the event loop group.
    public func close() async throws {
        guard !isClosed else { return }
        isClosed = true
        try await rest.close()
        try await channel.close().get()
        try await group.shutdownGracefully()
    }

    // MARK: - Service

    /// Health check; returns the server's reported title/version.
    @discardableResult
    public func healthCheck() async throws -> Qdrant_HealthCheckReply {
        try await call { try await service.healthCheck(Qdrant_HealthCheckRequest()) }
    }

    // MARK: - Collections

    /// Whether a collection exists.
    public func collectionExists(_ name: String) async throws -> Bool {
        var request = Qdrant_CollectionExistsRequest()
        request.collectionName = name
        let response = try await call { try await collections.collectionExists(request) }
        return response.result.exists
    }

    /// List all collection names.
    public func listCollections() async throws -> [String] {
        let response = try await call { try await collections.list(Qdrant_ListCollectionsRequest()) }
        return response.collections.map(\.name)
    }

    /// Delete a collection.
    @discardableResult
    public func deleteCollection(_ name: String) async throws -> Bool {
        var request = Qdrant_DeleteCollection()
        request.collectionName = name
        let response = try await call { try await collections.delete(request) }
        return response.result
    }

    // MARK: - Points

    /// Upsert points with single unnamed dense vectors.
    @discardableResult
    public func upsert(
        collection: String,
        points pts: [PointStruct],
        wait: Bool = true
    ) async throws -> UpdateResult {
        var request = Qdrant_UpsertPoints()
        request.collectionName = collection
        request.wait = wait
        request.points = pts.map { $0.proto }
        let response = try await call { try await points.upsert(request) }
        return UpdateResult(response.result)
    }

    // MARK: - Helpers

    /// Run a gRPC call, mapping `GRPCStatus` into ``QdrantError``.
    func call<T: Sendable>(_ body: () async throws -> T) async throws -> T {
        guard !isClosed else { throw QdrantError.closed }
        do {
            return try await body()
        } catch let status as GRPCStatus {
            throw QdrantError.rpc(status)
        }
    }
}
