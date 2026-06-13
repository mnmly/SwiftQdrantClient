import Foundation
import GRPC

/// Errors surfaced by ``QdrantClient``.
public enum QdrantError: Error, CustomStringConvertible {
    /// The underlying gRPC call failed with a status.
    case rpc(GRPCStatus)
    /// A response was missing an expected field.
    case unexpectedResponse(String)
    /// The client was used after ``QdrantClient/close()``.
    case closed
    /// A REST/HTTP request failed with a status code and body.
    case http(status: Int, body: String)
    /// The named collection does not exist.
    case collectionNotFound(String)
    /// The requested operation isn't available on this backend (e.g. local mode).
    case unsupported(String)

    public var description: String {
        switch self {
        case .rpc(let status):
            return "Qdrant gRPC error: \(status.code) - \(status.message ?? "")"
        case .unexpectedResponse(let detail):
            return "Unexpected Qdrant response: \(detail)"
        case .closed:
            return "QdrantClient has been closed"
        case .http(let status, let body):
            return "Qdrant HTTP error \(status): \(body)"
        case .collectionNotFound(let name):
            return "Collection not found: \(name)"
        case .unsupported(let detail):
            return "Unsupported operation: \(detail)"
        }
    }
}
