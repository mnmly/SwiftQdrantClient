import Foundation

/// Connection configuration for a Qdrant server.
///
/// Mirrors the constructor arguments of the Python ``QdrantClient`` for the
/// gRPC transport (host/port/api-key/TLS).
public struct QdrantConfiguration: Sendable {
    /// Server host name, e.g. `"localhost"`.
    public var host: String
    /// gRPC port. Qdrant defaults to `6334` for gRPC (`6333` is REST).
    public var grpcPort: Int
    /// REST/HTTP port, used for operations the gRPC API doesn't expose
    /// (snapshot recovery, cluster status, peers, telemetry). Defaults to `6333`.
    public var restPort: Int
    /// Use TLS for the gRPC connection.
    public var useTLS: Bool
    /// Optional API key sent as the `api-key` metadata header on every call.
    public var apiKey: String?
    /// Default per-call deadline. `nil` means no client-imposed deadline.
    public var timeout: TimeInterval?

    public init(
        host: String = "localhost",
        grpcPort: Int = 6334,
        restPort: Int = 6333,
        useTLS: Bool = false,
        apiKey: String? = nil,
        timeout: TimeInterval? = nil
    ) {
        self.host = host
        self.grpcPort = grpcPort
        self.restPort = restPort
        self.useTLS = useTLS
        self.apiKey = apiKey
        self.timeout = timeout
    }

    /// Build a configuration from a URL such as `https://xyz.qdrant.io:6334`.
    public init(url: URL, apiKey: String? = nil, timeout: TimeInterval? = nil) {
        let tls = url.scheme == "https"
        self.host = url.host ?? "localhost"
        self.grpcPort = url.port ?? 6334
        self.restPort = 6333
        self.useTLS = tls
        self.apiKey = apiKey
        self.timeout = timeout
    }
}
