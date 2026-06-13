# SwiftQdrantClient

A 1-to-1 Swift port of the Qdrant Python client. Three backends (gRPC
``QdrantClient``, REST ``QdrantRESTClient``, in-memory ``QdrantLocalClient``)
conform to one `QdrantClientProtocol`. See `README.md` for the surface.

Ported from qdrant-client **v1.18.0** (commit `326adef`). When upgrading to a
newer upstream, follow the migration checklist in `UPSTREAM.md` and update the
version/commit recorded there.

Generated gRPC/protobuf code lives under `Sources/QdrantProtos/Generated/` and is
committed; regenerate via the command in `README.md` when the `.proto` files
change. Don't hand-edit generated files.

Integration tests are gated behind `QDRANT_INTEGRATION=1` and need a running
Qdrant (`docker run -p 6333:6333 -p 6334:6334 qdrant/qdrant`). Unit tests
(model/local/embeddings) run with plain `swift test`.

## Documentation

`QdrantClient` ships DocC-generated reference docs (see
`Sources/QdrantClient/Documentation.docc/` and `Scripts/build_docs.sh`).
**`///` doc comments on public/`open` symbols are published** to the static site
at https://mnmly.github.io/SwiftQdrantClient/ and (if `EMIT_LLMS_TXT=1` is used)
into `docs/llms.txt`.

When you add or modify a `public` or `open` declaration:

- Write a `///` doc comment. One-sentence summary, then a paragraph if the *why*
  is non-obvious. Skip restating what the signature already says.
- Document each parameter with `- Parameter name:` (use the **internal** name
  when there's an external label — DocC warns otherwise).
- Cross-reference related symbols with double-backtick links, e.g.
  `` ``OtherType/method(_:)`` ``. DocC link syntax is signature-sensitive:
  `foo(_:)` and `foo(_:_:)` are different.
- When you add a new top-level symbol that belongs in the curated sidebar, add it
  under the appropriate `## Topics` group in
  `Sources/QdrantClient/Documentation.docc/QdrantClient.md`. Topics are organized
  by *user task*, not alphabetic order.

Verify before declaring documentation work done:

```bash
Scripts/build_docs.sh
```

Expect exit 0 and no new "doesn't exist at" or "external name used to document
parameter" warnings attributable to your changes.
