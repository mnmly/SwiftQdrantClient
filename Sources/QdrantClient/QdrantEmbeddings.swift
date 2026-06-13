import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

// MARK: - TextEmbedder

/// Produces dense embedding vectors for text. This is the Swift equivalent of
/// the Python client's FastEmbed integration: a pluggable embedding provider.
///
/// Ship-with implementations:
/// - ``NLEmbedder`` — on-device sentence embeddings via Apple's NaturalLanguage.
/// - ``HashEmbedder`` — dependency-free hashing embedder (deterministic; for
///   tests, CI, and platforms without NaturalLanguage assets).
///
/// To use a transformer model (e.g. BGE) port it with mlx-swift / swift-transformers
/// and conform it to this protocol.
public protocol TextEmbedder: Sendable {
    /// The dimensionality of produced vectors.
    var dimension: Int { get }
    /// Embed a batch of texts. The result has one vector per input, in order.
    func embed(_ texts: [String]) async throws -> [[Float]]
}

extension TextEmbedder {
    /// Embed a single text.
    public func embed(_ text: String) async throws -> [Float] {
        try await embed([text]).first ?? []
    }
}

// MARK: - NaturalLanguage embedder

#if canImport(NaturalLanguage)
/// On-device sentence embeddings using Apple's NaturalLanguage framework.
///
/// Uses the sentence embedding when available, otherwise averages word vectors.
public final class NLEmbedder: TextEmbedder, @unchecked Sendable {
    public let dimension: Int
    private let sentence: NLEmbedding?
    private let word: NLEmbedding?

    public init(language: NLLanguage = .english) throws {
        let sentence = NLEmbedding.sentenceEmbedding(for: language)
        let word = NLEmbedding.wordEmbedding(for: language)
        guard let dim = sentence?.dimension ?? word?.dimension, dim > 0 else {
            throw QdrantError.unsupported("No NaturalLanguage embedding available for \(language.rawValue). Download the model or use HashEmbedder.")
        }
        self.sentence = sentence
        self.word = word
        self.dimension = dim
    }

    public func embed(_ texts: [String]) async throws -> [[Float]] {
        texts.map { vector(for: $0) }
    }

    private func vector(for text: String) -> [Float] {
        if let v = sentence?.vector(for: text) {
            return v.map(Float.init)
        }
        // Fall back to averaging word vectors.
        guard let word else { return [Float](repeating: 0, count: dimension) }
        var sum = [Double](repeating: 0, count: dimension)
        var n = 0
        for token in text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            if let v = word.vector(for: String(token)) {
                for i in 0..<dimension { sum[i] += v[i] }
                n += 1
            }
        }
        if n > 0 { for i in 0..<dimension { sum[i] /= Double(n) } }
        return sum.map(Float.init)
    }
}
#endif

// MARK: - Hashing embedder (dependency-free)

/// A deterministic, dependency-free embedder: hashes tokens into a fixed-size
/// bag-of-words vector (then L2-normalises). Not semantically rich, but real,
/// fast, and reproducible — useful for tests, CI, and offline use.
public struct HashEmbedder: TextEmbedder {
    public let dimension: Int

    public init(dimension: Int = 256) {
        self.dimension = dimension
    }

    public func embed(_ texts: [String]) async throws -> [[Float]] {
        texts.map(vector(for:))
    }

    private func vector(for text: String) -> [Float] {
        var v = [Float](repeating: 0, count: dimension)
        for token in text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            var hash: UInt64 = 1_469_598_103_934_665_603 // FNV-1a offset basis
            for byte in token.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 1_099_511_628_211
            }
            v[Int(hash % UInt64(dimension))] += 1
        }
        let norm = v.reduce(0) { $0 + $1 * $1 }.squareRoot()
        if norm > 0 { for i in 0..<dimension { v[i] /= norm } }
        return v
    }
}

// MARK: - QdrantEmbeddings convenience

/// High-level "embed → upsert → search by text" wrapper over any
/// ``QdrantClientProtocol`` backend and a ``TextEmbedder``. Mirrors the
/// ergonomics of the Python client's `add` / `query` FastEmbed helpers.
public struct QdrantEmbeddings: Sendable {
    public let client: any QdrantClientProtocol
    public let embedder: any TextEmbedder
    /// Payload key under which the original document text is stored.
    public let documentKey: String

    public init(client: any QdrantClientProtocol, embedder: any TextEmbedder, documentKey: String = "document") {
        self.client = client
        self.embedder = embedder
        self.documentKey = documentKey
    }

    /// Create a collection sized to the embedder's dimension.
    @discardableResult
    public func createCollection(_ name: String, distance: Distance = .cosine) async throws -> Bool {
        try await client.createCollection(name: name, size: UInt64(embedder.dimension), distance: distance)
    }

    /// Embed and upsert documents. Ids default to sequential integers; the
    /// original text is stored in the payload under ``documentKey``.
    @discardableResult
    public func add(
        collection: String,
        documents: [String],
        ids: [PointID]? = nil,
        payloads: [Payload]? = nil,
        wait: Bool = true
    ) async throws -> UpdateResult {
        let vectors = try await embedder.embed(documents)
        let points: [PointStruct] = documents.enumerated().map { index, text in
            let id = ids?[index] ?? .int(UInt64(index))
            var payload = payloads?[index] ?? [:]
            payload[documentKey] = .string(text)
            return PointStruct(id: id, vector: vectors[index], payload: payload)
        }
        return try await client.upsert(collection: collection, points: points, wait: wait)
    }

    /// Embed `text` and run a nearest-neighbour query.
    public func query(
        collection: String,
        text: String,
        limit: UInt64 = 10,
        filter: Filter? = nil
    ) async throws -> [ScoredPoint] {
        let vector = try await embedder.embed(text)
        return try await client.query(
            collection: collection, query: .nearest(.dense(vector)), using: nil, prefetch: [],
            filter: filter, params: nil, scoreThreshold: nil, limit: limit, offset: 0,
            withPayload: true, withVectors: false)
    }

    /// Embed several queries and run them as a batch (one result list per text).
    public func queryBatch(
        collection: String,
        texts: [String],
        limit: UInt64 = 10,
        filter: Filter? = nil
    ) async throws -> [[ScoredPoint]] {
        let vectors = try await embedder.embed(texts)
        let requests = vectors.map {
            QueryRequest(query: .nearest(.dense($0)), filter: filter, limit: limit)
        }
        return try await client.queryBatch(collection: collection, queries: requests)
    }
}
