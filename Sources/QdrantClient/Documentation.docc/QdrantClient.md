# ``QdrantClient``

A Swift client for the Qdrant vector database, with gRPC, REST, and in-memory
backends behind one async API.

## Overview

`QdrantClient` is a 1-to-1 Swift port of the official [Qdrant](https://qdrant.tech)
Python client, built
on Swift concurrency (async/await and `actor` isolation). Three interchangeable
backends conform to ``QdrantClientProtocol`` so application code can switch
transports without changes:

| Backend | Type | Transport |
| --- | --- | --- |
| ``QdrantClient`` | remote | gRPC (`:6334`) |
| ``QdrantRESTClient`` | remote | REST/HTTP `URLSession` (`:6333`) |
| ``QdrantLocalClient`` | in-process | in-memory brute-force engine |

All three speak the same transport-neutral model types (``PointStruct``,
``Filter``, ``Query``, ``ScoredPoint``, …), so you write your data and query
logic once and pick a backend at construction time.

```swift
import QdrantClient

// Swap QdrantClient for QdrantRESTClient or QdrantLocalClient — same API.
let client = try QdrantClient(host: "localhost")
try await client.createCollection(name: "demo", size: 4, distance: .cosine)
try await client.upsert(collection: "demo", points: [
    .init(id: 1, vector: [0.1, 0.2, 0.3, 0.4], payload: ["city": "Berlin"]),
])
let hits = try await client.query(collection: "demo", vector: [0.1, 0.2, 0.3, 0.4], limit: 3)
try await client.close()
```

For "search by text", layer ``QdrantEmbeddings`` over any backend with a
``TextEmbedder`` (on-device ``NLEmbedder`` or dependency-free ``HashEmbedder``).

## Topics

### Connecting

- ``QdrantClient``
- ``QdrantRESTClient``
- ``QdrantLocalClient``
- ``QdrantClientProtocol``
- ``QdrantConfiguration``
- ``QdrantError``

### Creating and managing collections

- ``VectorsConfiguration``
- ``VectorParams``
- ``Distance``
- ``VectorDatatype``
- ``HnswConfig``
- ``OptimizersConfig``
- ``WalConfig``
- ``ShardingMethod``
- ``StrictModeConfig``
- ``MultivectorComparator``
- ``SparseVectorParams``
- ``SparseModifier``
- ``CollectionInfo``
- ``CollectionStatus``

### Quantization

- ``QuantizationConfig``
- ``ScalarQuantization``
- ``ProductQuantization``
- ``BinaryQuantization``
- ``QuantizationType``
- ``CompressionRatio``
- ``BinaryQuantizationEncoding``
- ``QuantizationSearchParams``

### Writing points

- ``PointStruct``
- ``PointID``
- ``VectorData``
- ``PointVectors``
- ``Payload``
- ``QdrantValue``
- ``PointsSelector``
- ``UpdateResult``
- ``UpdateStatus``
- ``UpdateOperation``

### Querying and searching

- ``Query``
- ``VectorInput``
- ``RecommendInput``
- ``RecommendStrategy``
- ``ContextPair``
- ``Mmr``
- ``Fusion``
- ``Prefetch``
- ``Formula``
- ``Expression``
- ``DecayParams``
- ``RelevanceFeedbackInput``
- ``FeedbackItem``
- ``SearchParams``
- ``QueryRequest``
- ``OrderBy``
- ``OrderValue``
- ``WithPayload``
- ``WithVectors``
- ``ScoredPoint``
- ``RetrievedPoint``

### Filtering

- ``Filter``
- ``Condition``
- ``MatchValue``
- ``QdrantRange``
- ``GeoPoint``

### Grouping, facets, and matrices

- ``PointGroup``
- ``GroupId``
- ``FacetHit``
- ``FacetValue``
- ``SearchMatrixPair``
- ``SearchMatrixOffsets``

### Embeddings (search by text)

- ``QdrantEmbeddings``
- ``TextEmbedder``
- ``NLEmbedder``
- ``HashEmbedder``

### Aliases, shard keys, and snapshots

- ``AliasOperation``
- ``AliasDescription``
- ``ShardKey``
- ``SnapshotDescription``

### Cluster administration

- ``ClusterOperation``
- ``VersionInfo``
- ``JSONValue``

### Payload field indexing

- ``FieldType``
- ``VectorNameConfig``
```
