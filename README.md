# SwiftQdrantClient

A Swift port of the [Qdrant](https://qdrant.tech) Python client. Built with Swift
concurrency (async/await + `actor` clients), `swift-protobuf` 1.38.0 and
`grpc-swift` 1.27.5.

Three interchangeable backends conform to one `QdrantClientProtocol`:

| Backend | Type | Transport |
|---|---|---|
| `QdrantClient` | remote | gRPC (`:6334`) |
| `QdrantRESTClient` | remote | REST/HTTP `URLSession` (`:6333`) |
| `QdrantLocalClient` | in-process | in-memory brute-force engine |

Plus an embeddings layer (`TextEmbedder` + `QdrantEmbeddings`) for "search by text".

Ported from qdrant-client **v1.18.0** (commit `326adef`). See
[UPSTREAM.md](UPSTREAM.md) for provenance and the upgrade checklist.

## Layout

```
Sources/
  QdrantProtos/
    protos/      # .proto sources copied from the Python client (source of truth)
    Generated/   # committed protoc output (*.pb.swift + *.grpc.swift)
  QdrantClient/  # high-level async clients, models, local engine, embeddings
Tests/
  QdrantClientTests/   # model + local + embeddings unit tests, gated integration tests
```

## Usage

```swift
import QdrantClient

// gRPC (or swap for QdrantRESTClient / QdrantLocalClient — same API)
let client = try QdrantClient(host: "localhost")
try await client.createCollection(name: "demo", size: 4, distance: .cosine)
try await client.upsert(collection: "demo", points: [
    .init(id: 1, vector: [0.1, 0.2, 0.3, 0.4], payload: ["city": "Berlin"]),
])
let hits = try await client.query(collection: "demo", vector: [0.1, 0.2, 0.3, 0.4], limit: 3)
try await client.close()

// In-memory, no server:
let local = QdrantLocalClient()

// Search by text (FastEmbed-style):
let store = QdrantEmbeddings(client: local, embedder: try NLEmbedder())
try await store.createCollection("docs")
try await store.add(collection: "docs", documents: ["qdrant is a vector database", "swift uses actors"])
let results = try await store.query(collection: "docs", text: "vector search", limit: 1)
```

## Regenerating the gRPC/protobuf code

Generated code is committed (mirroring how the Python client commits `_pb2.py`).
To regenerate after updating `Sources/QdrantProtos/protos/*.proto`:

```sh
# one-time: build the gRPC plugin from grpc-swift 1.27.5
git clone --depth 1 --branch 1.27.5 https://github.com/grpc/grpc-swift.git /tmp/grpc-swift-build
( cd /tmp/grpc-swift-build && swift build -c release --product protoc-gen-grpc-swift )

cd Sources/QdrantProtos/protos
OUT=../Generated
protoc --proto_path=. \
  --plugin=protoc-gen-swift=$(which protoc-gen-swift) \
  --swift_out=$OUT --swift_opt=Visibility=Public *.proto
protoc --proto_path=. \
  --plugin=protoc-gen-grpc-swift=/tmp/grpc-swift-build/.build/release/protoc-gen-grpc-swift \
  --grpc-swift_out=$OUT --grpc-swift_opt=Visibility=Public,Client=true,Server=false \
  collections_service.proto points_service.proto snapshots_service.proto qdrant.proto
```

## Parity

All 58 methods of the Python `QdrantBase` contract are implemented across the
backends (collections, points, payload, vectors, query/recommend/discover/
context, batch & grouped queries, facets, distance matrix, aliases, shard keys,
payload & vector-name management, snapshots incl. shard & recover, cluster /
peer / telemetry / optimizations, `info`, `recreate`, bulk `upload_*`, and
`migrate`). The gRPC client transparently uses an internal REST client for the
handful of operations the gRPC API doesn't expose (snapshot recovery, cluster
status, peers, telemetry, optimizations) — mirroring the Python `QdrantRemote`.

The local in-memory backend implements the same surface Python's local mode
does (including discovery/context queries and the distance matrix) and throws
`QdrantError.unsupported` for exactly the operations Python local also rejects
(snapshots, shard keys, cluster/peer/telemetry).

## Roadmap (porting the rest of the Python client)

gRPC remote client — **done & verified live**:
- [x] Collections: create (named/sparse vectors, HNSW/optimizer/shard/replication),
      get info, update, exists, list, delete, aliases, shard keys.
- [x] Points: upsert, retrieve, scroll, count, delete, payload set/overwrite/
      delete/clear, field indexes, update/delete vectors.
- [x] Named / sparse / multi vectors (upsert + query).
- [x] Filters + query DSL (match/range/geo/hasId/nested/…).
- [x] Query / search / recommend / discover / context / fusion / sample, plus
      `prefetch` hybrid queries, batch, and groups.
- [x] Facets, distance matrix (pairs/offsets).
- [x] Snapshots (collection + full).

Beyond gRPC — **done & verified**:
- [x] REST transport over `URLSession` behind the shared `QdrantClientProtocol`
      (collections, points, payload, scroll, count, query/recommend/discover,
      filters) — verified live against `:6333`.
- [x] Local in-memory mode: brute-force dense/sparse/multi search, full filter
      evaluation (match/range/geo/nested/hasId/…), payload ops, recommend.
- [x] Embeddings layer: `TextEmbedder` protocol, on-device `NLEmbedder`
      (NaturalLanguage), dependency-free `HashEmbedder`, and `QdrantEmbeddings`
      (`add`/`query` by text).

Full model surface — **done & verified**:
- [x] Config completeness: quantization (scalar/product/binary), full HNSW &
      optimizer fields, WAL, sharding method, strict mode, multivector — on
      create & update collection.
- [x] Read selectors: `WithPayload` (bool/include/exclude) and `WithVectors`
      (bool/names).
- [x] Advanced query variants: `Formula` (full `Expression` tree incl. decay
      functions) and `RelevanceFeedback`.
- [x] Enriched responses: `ScoredPoint`/`RetrievedPoint` shard key + order value;
      `CollectionInfo` optimizer status + payload schema.

Not ported (deprecated / out of scope):
- `init_from` on create collection — **deprecated and removed from the gRPC
  `CreateCollection` message upstream**, so not wireable through the primary
  transport.
- Local mode: fusion/prefetch/formula/relevance-feedback queries are server-only
  and throw `QdrantError.unsupported` (matching Python's local mode).
- A transformer embedder (e.g. BGE via mlx-swift / swift-transformers) — the
  `TextEmbedder` protocol is ready for one to conform.

## Testing

```sh
swift test                                    # unit tests (model/local/embeddings)

# integration (gRPC :6334 + REST :6333):
docker run -p 6333:6333 -p 6334:6334 qdrant/qdrant
QDRANT_INTEGRATION=1 swift test               # full suite
```

## Documentation

```sh
Scripts/build_docs.sh                 # static DocC site -> docs/QdrantClient/
Scripts/build_docs.sh preview         # live local preview

# LLM-friendly single-file export (docs/llms.txt). Needs a recent swift.org
# toolchain for docc's experimental Markdown flags — the script auto-sources
# ~/.swiftly/env.sh, so `swiftly use main-snapshot` once and this just works.
EMIT_LLMS_TXT=1 Scripts/build_docs.sh
```
```
