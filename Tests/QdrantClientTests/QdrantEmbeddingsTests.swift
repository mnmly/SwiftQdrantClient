import XCTest
@testable import QdrantClient

/// Embeddings layer over the local backend — no server required.
final class QdrantEmbeddingsTests: XCTestCase {
    func testHashEmbedder() async throws {
        let embedder = HashEmbedder(dimension: 64)
        let vectors = try await embedder.embed(["hello world", "hello world", "totally different text"])
        XCTAssertEqual(vectors.count, 3)
        XCTAssertEqual(vectors[0], vectors[1]) // deterministic
        XCTAssertNotEqual(vectors[0], vectors[2])
        XCTAssertEqual(vectors[0].count, 64)
    }

    func testEmbedAddQuery() async throws {
        let store = QdrantEmbeddings(client: QdrantLocalClient(), embedder: HashEmbedder(dimension: 128))
        try await store.createCollection("docs")
        try await store.add(collection: "docs", documents: [
            "the quick brown fox jumps over the lazy dog",
            "swift concurrency uses actors and async await",
            "qdrant is a vector database for similarity search",
        ])
        let hits = try await store.query(collection: "docs", text: "vector database similarity", limit: 1)
        XCTAssertEqual(hits.first?.payload["document"], "qdrant is a vector database for similarity search")
    }

    #if canImport(NaturalLanguage)
    func testNLEmbedderIfAvailable() async throws {
        let embedder: NLEmbedder
        do { embedder = try NLEmbedder() }
        catch { throw XCTSkip("NaturalLanguage embedding model not available on this machine") }

        let store = QdrantEmbeddings(client: QdrantLocalClient(), embedder: embedder)
        try await store.createCollection("nl")
        try await store.add(collection: "nl", documents: [
            "I love programming in Swift",
            "The weather is sunny today",
            "Dogs and cats are popular pets",
        ])
        // Semantically closest to a programming query.
        let hits = try await store.query(collection: "nl", text: "writing code on my computer", limit: 1)
        XCTAssertEqual(hits.first?.payload["document"], "I love programming in Swift")
    }
    #endif
}
