# Upstream provenance

SwiftQdrantClient is a port of the official Python client. This file records the
exact source revision so future upgrades can diff against it.

## Ported from

| | |
| --- | --- |
| Source repo | https://github.com/qdrant/qdrant-client |
| Version | **1.18.0** |
| Commit | `326adefcc2158121dd0d04877e1a483b5aa2627b` ("bump version to v1.18.0") |
| Ported on | 2026-06-13 |

The contract we tracked is `qdrant_client/client_base.py` (`QdrantBase`, 58
methods) plus the `.proto` files under `qdrant_client/proto/` (committed verbatim
into `Sources/QdrantProtos/protos/`). REST paths/bodies follow
`qdrant_client/http/api/*.py` from the same revision.

## Pinned build dependencies

| Dependency | Version | Why |
| --- | --- | --- |
| swift-protobuf | from 1.38.0 | message codegen |
| grpc-swift | exact 1.27.5 | service codegen (v1 line; `*AsyncClient`) |
| swift-docc-plugin | from 1.4.3 | docs only |

Generated Swift (`Sources/QdrantProtos/Generated/`) was produced with a locally
built `protoc-gen-grpc-swift` from grpc-swift 1.27.5 — see README "Regenerating".

## Known intentional deviations from 1.18.0

- `init_from` (create collection) is **omitted** — deprecated and already removed
  from the gRPC `CreateCollection` message upstream; not wireable over gRPC.
- Local mode throws `QdrantError.unsupported` for the same operations Python's
  local mode rejects (snapshots, shard keys, cluster) plus the server-only query
  variants (fusion/prefetch/formula/relevance-feedback).
- A transformer embedder (FastEmbed's ONNX models) is not bundled; the
  `TextEmbedder` protocol + `NLEmbedder`/`HashEmbedder` cover the integration.

## Migrating to a newer upstream version

1. Check out the target tag of qdrant-client and note its commit.
2. **Proto diff** — copy the new `qdrant_client/proto/*.proto` over
   `Sources/QdrantProtos/protos/`, regenerate (README "Regenerating"), and
   rebuild. New/changed messages surface as compile changes.
3. **Method-surface diff** — diff `qdrant_client/client_base.py` against this
   revision for added/changed/removed methods on `QdrantBase`; reconcile
   `QdrantClientProtocol` + all three backends.
4. **Model-field diff** — for each config/model type, diff the proto message
   fields against the Swift struct (lesson learned: field completeness matters,
   not just method coverage). A quick check per type:
   `awk '/struct Qdrant_<Name>:/{p=1} p{print} p&&/init\(\)/{exit}' Generated/*.pb.swift | grep 'public var'`
5. **REST diff** — `grep -rhoE 'url="/[^"]*"' qdrant_client/http/api/*.py` and
   reconcile with `QdrantRESTClient*.swift`.
6. Bump this file's version/commit, run `QDRANT_INTEGRATION=1 swift test` against
   the matching `qdrant/qdrant` server image, and regenerate docs.
