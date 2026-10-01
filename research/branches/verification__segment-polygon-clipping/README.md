# Public segment/polygon clipping differential verifier

This standalone verifier compares the public `import geo;` clipping API with
an independent BigInt rational oracle. See [PROVENANCE.md](PROVENANCE.md) for
the exact source commit, blob and SHA-256 checksum.

The earlier partition oracle, breakpoint and full-cell candidates, and
Binary64 collapse probes remain in the adjacent
`research__clipping-semantics/docs/research/` snapshot.

## Reproduction

Use DMD 2.111.0 or LDC 1.41.0 with DUB 1.40.0 for the historical baseline.
Check out production `geo-d` at
`af50e095e47e004fd69d38acf4614f6fdd2c735a`, the source commit's parent.
Create a temporary DUB application with the archived verifier as
`source/app.d` and the following `dub.sdl`, replacing the absolute dependency
path with that production checkout:

```sdl
name "segment-polygon-public-differential"
targetType "executable"
dependency "geo-d" path="/absolute/path/to/pinned/geo-d"
```

Run each compiler separately:

```sh
dub run --compiler=dmd --force
dub run --compiler=ldc2 --force
```

The exact production dependency resolves its released `euclid-core-d`
dependency through DUB. Successful execution requires all 125,686 comparisons
and prints `SEGMENT POLYGON PUBLIC CLIP DIFFERENTIAL PASS`. Preservation of
this file is not a new execution result.

## Checksums

From the research repository root:

```sh
sha256sum -c research/SHA256SUMS
git hash-object research/branches/verification__segment-polygon-clipping/docs/verification/segment_polygon_clip_public_differential.d
```

The expected Git blob is recorded in `PROVENANCE.md`. The inherited checksum
manifest contained a stale checksum for itself. That single self-reference
was removed when adding this snapshot: a manifest cannot retain its own hash
after the hash is inserted. Existing evidence-file checksum entries are
unchanged; the original manifest remains in Git history.
