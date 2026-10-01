# Clipping research for geo-d

Status: research checkpoint
Issue: #58
Baseline develop: `5fe13fb577d24f49a392b642c1de41b5eae64d9a`
Research branch: `research/clipping-semantics`

## Purpose

Determine which clipping capabilities, if any, should be promoted into geo-d v3 from concrete consumer requirements.

This document is research evidence. It does not authorize production API or implementation.

## Workspace / repository constraints

geo-d remains a coordinate-system-agnostic Euclidean 2D geometry library.

New public API must be consumer-backed and research-gated. Rendering viewport policy, CRS/projection policy, OSM object/tag semantics, spatial indexing, and editor mutation/orchestration remain outside geo-d.

Topology classification and coordinate construction remain separate contracts. No global epsilon may define topology.

## Current consumer evidence

The OSM editor is a concrete recurring consumer of linear-way ↔ polygon geometry.

The already-promoted `SegmentPolygonRelationship` intentionally answers only existential facts:

- some segment point lies in polygon exterior;
- some segment point lies on polygon boundary;
- some segment point lies in polygon interior;
- a positive-length boundary overlap exists.

It deliberately does not retain:

- ordered contacts;
- contact parameters;
- contact coordinates;
- transition locations;
- result subsegments;
- clipping geometry.

Therefore workflows that must split or repair a linear way at area/building boundaries need a constructive operation beyond relationship classification.

OSM identity, shared node IDs, layer/level, bridge/tunnel/indoor/building-passage policy, warning severity, and repair orchestration remain editor/osm-d concerns.

## External reference findings

### Rectangular / convex line clipping

Liang-Barsky-style clipping represents a segment parametrically and reduces clipping against a convex window to bounds on the segment parameter.

Cyrus-Beck generalizes the same broad idea to convex polygons/polyhedra using boundary half-spaces.

These algorithms are useful references for bounded or convex clipping, but their existence is not by itself evidence for separate public geo-d operation families.

### General polygon / open-path clipping

JTS OverlayNG models intersection, union, difference, and symmetric difference as overlay operations and supports mixed-dimensional input. Its intersection result can include lower-dimensional components.

Clipper2 supports open subject paths clipped by closed polygon paths. Its documentation explicitly notes that collinear open-path portions on clipping boundaries do not always have one obvious inclusion rule; the result depends on neighboring path portions.

This is important evidence that boundary-overlap semantics must be explicit in geo-d rather than inherited accidentally from one library.

### Regularized polygon Boolean operations

CGAL's 2D Boolean-set package exposes regularized polygon Boolean operations and polygon-with-holes results. Its polygon intersection testing is explicitly interior-oriented.

This reinforces the distinction between:

- clipping a 1D segment/polyline by a closed 2D polygonal set; and
- regularized 2D polygon overlay.

They should not be forced into one result contract.

## Candidate matrix — first checkpoint

| Candidate | Consumer evidence | Existing composition | Initial disposition |
|---|---|---|---|
| Segment ↔ Bounds2 | no concrete independent consumer yet; viewport clipping is application/rendering policy | straightforward specialized parametric algorithms exist | **DEFER as public API; retain as algorithm/reference candidate** |
| Segment ↔ convex polygon | no distinct consumer; current editor consumer uses general polygons | Cyrus-Beck/related methods provide O(n) convex clipping | **DEFER as separate public family** |
| Segment ↔ general valid Polygon2View | concrete editor split/repair need; relationship classifier intentionally lacks ordered construction | cannot be reconstructed cleanly from four existential facts alone | **ADOPT FOR FURTHER RESEARCH / DESIGN CANDIDATE** |
| Polyline ↔ general valid Polygon2View | concrete linear-way consumer; component order and continuity matter | repeated segment clipping is possible but shared vertices, duplicate contacts, component joining, and ordering require a coherent aggregate contract | **ADAPT / research after segment contract** |
| Polygon ↔ polygon clipping / intersection / difference | mature overlay references exist, and geo-d already has exact polygon-union machinery | union core is reusable evidence, but no concrete current editor operation yet requires generic intersection/difference | **DEFER pending consumer** |

These are research dispositions, not final #58 exit decisions.

## Key semantic question: clipping versus partition

A simple API called "clip segment to polygon" must choose what happens to positive-length portions lying exactly on the polygon boundary.

That choice is not universally obvious for open paths.

A more fundamental candidate is therefore an ordered partition of the closed segment by polygon location:

- exterior intervals;
- boundary intervals;
- interior intervals;
- exact transition events between them.

Consumers can then deliberately select:

- interior only;
- interior + boundary (closed-set intersection);
- exterior only;
- or retain boundary portions separately.

This may avoid baking application policy into a low-level clipping operation.

Research must determine whether the partition representation is small enough to be a stable reusable geo-d contract or whether it exposes too much construction detail.

## Construction and numerical requirements

For supported robust scalar domains, topology decisions must remain exact/certified.

A proper segment/polygon boundary crossing can require a rational coordinate even for integral input, so construction cannot generally remain in the input scalar type.

The existing `IntersectionScalar!T` / correctly-rounded binary64 construction policy is the first candidate to investigate, but it must not be adopted automatically.

Important cases:

- segment wholly outside / inside;
- one or both endpoints on boundary;
- proper crossings;
- polygon-vertex crossing;
- tangency;
- positive-length boundary overlap;
- overlap followed by inside;
- overlap followed by outside;
- multiple separated clipped components in concave polygons;
- holes;
- degenerate query segment;
- redundant collinear polygon vertices;
- distinct exact transition points that round to the same binary64 coordinate.

The last case is especially important: rounded construction must not be used to decide topology or event order.

## Complexity / ownership direction

For one segment against a general polygon with n boundary edges, the target should remain linear in n unless evidence demonstrates a need for a heavier structure.

A segment can intersect a non-convex polygon many times, so the result has variable size.

Therefore a production design will likely need one of:

- caller-provided destination storage plus a sizing/preflight operation;
- a visitor/callback traversal of ordered pieces;
- an owning result that allocates explicitly;
- or a two-level API separating an allocation-free iterator/visitor kernel from optional materialization.

No choice is frozen yet.

For a polyline of m segments against a polygon of n edges, naive independent segment clipping is O(mn). Spatial indexing remains outside geo-d; an editor may broad-phase candidates before calling the geometry kernel.

## Reuse boundary

Do not route segment/polyline clipping through the full polygon-pair arrangement merely because it already exists.

The segment↔polygon relationship research demonstrated that a specialized linear algorithm can be both exact and substantially simpler.

Reuse lower-level exact intersection/noding/construction machinery where semantics match.

Do not expose internal `SegmentContactKind` merely to make clipping easier.

For future polygon intersection/difference, the existing polygon-pair topology / union arrangement is the natural implementation evidence, but generalized overlay should only be designed after a concrete consumer exists.

## Exact ordered-partition reference model

Let a finite nondegenerate query segment be parameterized mathematically as:

~~~text
q(t) = a + t (b - a),    0 <= t <= 1
~~~

and let a valid polygon define the usual disjoint point-location partition:

~~~text
Exterior(P)
Boundary(P)
Interior(P)
~~~

The segment/polygon partition is the pullback of these three locations onto the closed parameter interval.

The exact reference representation is a one-dimensional cell decomposition, not merely a list of closed result segments.

Let:

~~~text
0 = t0 < t1 < ... < tk = 1
~~~

be the sorted unique query parameters containing:

- both query endpoints; and
- every endpoint of every connected component of
  `q([0,1]) ∩ Boundary(P)`.

The decomposition contains:

- one point cell for every `ti`, labelled by the exact polygon location of `q(ti)`; and
- one open interval cell `(ti, ti+1)` for every adjacent pair, labelled by the unique polygon location of all points in that interval.

For a valid polygon, an open interval cell cannot change location without crossing the boundary, and all boundary-component endpoints are already breakpoints. Therefore one exact witness is sufficient to classify each open interval in the independent reference model.

This cell model is required because a simple list of closed `Segment2` pieces is not topologically faithful.

For example, at a proper exterior→interior crossing:

~~~text
exterior open interval
boundary singleton
interior open interval
~~~

The transition point belongs to the polygon boundary. If both neighboring pieces were represented as ordinary closed segments, the same point would be incorrectly labelled exterior and interior as well.

### Degenerate query segment

For `a == b`, the mathematical segment is a single point.

The partition therefore contains exactly one point cell and no interval cells. Its label is the exact point-in-polygon result.

This includes the valid empty polygon case, for which the one point cell is exterior.

### Empty polygon

A valid empty polygon has no boundary and no interior.

For a nondegenerate query segment, the exact partition is:

~~~text
endpoint exterior
one open exterior interval
endpoint exterior
~~~

For a degenerate query segment it is one exterior point cell.

## Output-size bounds

Let `n` be the total number of polygon boundary edges over all rings.

Each polygon edge intersects the query segment in one of:

- the empty set;
- one point;
- one closed positive-length segment.

Therefore `Boundary(P) ∩ query` is the union of at most `n` connected closed subsets of the query segment before merging.

After merging overlaps and duplicate contacts, it has at most `n` connected boundary components.

Consequently:

- boundary-component count <= `n`;
- boundary-component endpoint count <= `2n`;
- breakpoint count, including the two query endpoints, <= `2n + 2`;
- open interval-cell count <= `2n + 1`;
- a maximally alternating location partition has O(n) total cells.

A coarser bound for a representation storing every breakpoint and every interval cell separately is therefore:

~~~text
point cells     <= 2n + 2
interval cells  <= 2n + 1
total cells     <= 4n + 3
~~~

This is a storage bound for the explicit cell representation, not a claim that every valid polygon can realize all terms simultaneously.

A representation that stores only breakpoints plus one label per adjacent interval needs at most:

~~~text
2n + 2 exact breakpoints
2n + 1 interval labels
~~~

before optional compaction.

## Exact event ordering

The reference model does not require a floating `t`.

For any nondegenerate represented query segment:

- if `a.x != b.x`, x is strictly monotone along the segment;
- otherwise y is strictly monotone.

All event points lie on the query segment.

Therefore exact comparison of the monotone coordinate orders all events in `a -> b` traversal order.

This is already established in geo-d twice:

- `compareProperIntersectionsAlongSegment` orders exact proper-intersection events this way;
- `compareExactOverlayPointsAlongSegment` generalizes the same rule to represented endpoints and rational overlay points.

This ordering is preferable to constructing a rounded floating segment parameter.

## Existing exact machinery and second-use evidence

The polygon-union internals already contain an implementation-only exact point model:

~~~text
ExactOverlayPoint
    xNumerator
    yNumerator
    positive denominator
~~~

and helpers that:

- lift represented input points exactly;
- promote `ExactProperIntersection` without rounding;
- compare exact rational points;
- compare them in source-segment order;
- append touch, proper-crossing, and overlap endpoints;
- sort and deduplicate event points using caller-provided storage.

These capabilities match the mathematical needs of segment/polygon partition closely.

However, `ExactOverlayPoint` is currently named and housed as polygon-union infrastructure.

Clipping would be a genuine second independent consumer inside geo-d. That is evidence for considering a private geometry-neutral refactor of exact event-point/noding machinery.

It is not evidence for:

- exposing exact rational coordinates publicly;
- moving the machinery to `euclid-core-d`;
- exposing `SegmentContactKind`;
- routing clipping through the full polygon-pair arrangement.

Any internal refactor should occur only when the external prototype demonstrates that the contracts are in fact identical.

## Boundary-component construction

For every polygon boundary edge, exact segment/segment contact provides:

~~~text
none
touch
proper crossing
positive-length overlap
~~~

The independent reference model lifts these contacts onto the query parameter line:

- touch -> one exact breakpoint;
- proper crossing -> one exact rational breakpoint;
- overlap -> two exact represented breakpoints spanning one boundary interval.

After exact sort and deduplication, the reference model determines for each adjacent breakpoint pair whether the open interval lies on the polygon boundary.

One direct oracle method is to retain the union of overlap intervals explicitly in exact query order.

Every remaining open interval is disjoint from the polygon boundary and can then be classified as wholly interior or wholly exterior with one independent exact rational witness.

This is intentionally an oracle-oriented method. Production need not perform a point-in-polygon classification for every interval if a cheaper exact transition-state algorithm is proven equivalent.

## Independent rational oracle direction

The oracle should remain structurally independent from the production candidate.

For integer-grid and exactly decoded finite floating inputs it can use arbitrary-precision rational arithmetic for:

1. exact query/boundary segment intersections;
2. exact query-order coordinates or rational parameters;
3. exact sorting/deduplication;
4. exact overlap-interval union;
5. exact rational witness construction between adjacent breakpoints;
6. winding/even-odd point-in-polygon classification of those witnesses.

The oracle output is the ordered cell sequence:

~~~text
point location at t0
interval location (t0,t1)
point location at t1
...
interval location (tk-1,tk)
point location at tk
~~~

This is stronger than comparing only clipped coordinates because it independently checks the complete transition topology.

## Rounded construction is a second layer

Exact cell topology must be complete before any public coordinate rounding.

A public construction layer based on `IntersectionScalar!T == double` must not silently merge two distinct exact breakpoints that round to the same binary64 point.

Such a collapse can change:

- event count;
- event order;
- zero/nonzero result lengths;
- boundary versus interior/exterior adjacency;
- polyline split points.

Therefore a constructed public result needs an explicit policy for topologically unrepresentable rounding.

The existing polygon-union precedent suggests that a checked `unrepresentableConstruction`-style outcome is more appropriate than silently accepting topology-changing collapse.

This is a research direction, not yet a frozen status enum or API.

## Implication for a future public contract

The reference model separates three concerns:

~~~text
exact relationship facts
    SegmentPolygonRelationship

exact ordered 1D topology
    candidate partition kernel

rounded/materialized clipping geometry
    candidate construction layer
~~~

This means the likely public abstraction, if promoted, should not force application clipping policy into the exact topology layer.

Possible eventual surfaces include:

- a partition visitor/callback over point/interval cells;
- caller-provided breakpoint/piece storage;
- a checked materializer selecting interior, boundary, or exterior sets;
- or a narrower construction API backed by a private partition kernel.

No public spelling is chosen yet.

## Next research gates

1. Prototype the exact cell decomposition outside the production API.
2. Verify the `2n+2` breakpoint and `2n+1` interval bounds experimentally and with adversarial fixtures.
3. Compare two implementation directions:
   - sort all exact boundary events then classify intervals;
   - stream exact transitions without storing all boundary events where possible.
4. Determine whether overlap intervals can be handled without a second full polygon scan.
5. Construct a binary64-collapse fixture with two distinct exact breakpoints rounding to one public point.
6. Differentially verify candidate output against the independent arbitrary-precision rational oracle.
7. Only after those gates choose ownership, allocation, status, and public API shape.
8. After the segment contract is settled, test whether polyline clipping composes cleanly or deserves a dedicated aggregate API.
9. Keep polygon intersection/difference deferred until a real consumer identifies required regularization and lower-dimensional-result semantics.

## Current conclusion

The strongest #58 candidate is not generic clipping breadth.

It is a narrowly scoped, consumer-backed constructive segment ↔ valid-polygon operation that preserves ordered topology and transition geometry omitted deliberately by `SegmentPolygonRelationship`.

Rectangle/convex specializations are reference/performance candidates, not currently justified public APIs.

Polyline clipping depends on the segment result contract.

Generic polygon intersection/difference remains deferred pending consumer evidence.


## Executable qualification evidence

The research direction has now been exercised by three independent stages.

### Independent BigInt oracle

`docs/research/segment_polygon_partition_oracle.d`

Verified on DMD and LDC.

The oracle:

- imports no geo-d intersection, internal noding, or relationship code;
- constructs exact rational query parameters with `BigInt`;
- performs its own exact segment/edge intersection logic;
- performs its own exact point-in-polygon classification;
- produces the complete ordered E/B/I point+interval cell sequence.

### Exact breakpoint candidate

`docs/research/segment_polygon_partition_candidate.d`

Verified on DMD and LDC.

This candidate reuses geo-d's existing exact event machinery for:

- represented endpoints;
- touch contacts;
- proper rational crossings;
- positive-length overlap endpoints;
- exact source-order sorting;
- exact deduplication.

It does not use the full polygon-pair arrangement.

The successful candidate establishes genuine second-use evidence for the exact event/noding infrastructure.

### Full exact-cell candidate

`docs/research/segment_polygon_partition_full_candidate.d`

Verified on DMD and LDC.

The candidate uses geo-d exact breakpoints and an exact rational research-only label bridge to recover the complete ordered E/B/I cell sequence.

### Exhaustive differential

`docs/research/segment_polygon_partition_differential.d`

Verified on DMD and LDC.

The candidate and independent oracle matched for **125,686 directed integer-grid query segments per compiler** across:

- square;
- reversed square;
- concave U polygon;
- concave L polygon;
- polygon with hole;
- reversed exterior and hole winding;
- redundant collinear boundary vertex.

The differential compares both:

- exact breakpoint count; and
- the complete ordered point+interval E/B/I sequence.

No mismatch was observed.

This evidence is sufficient to move #58 from semantic qualification into result/workspace/construction design.


## Design disposition after semantic qualification

### 1. Keep the exact ordered partition private initially

The exact partition is mathematically useful and is the correct internal model, but the current concrete consumer does not require direct access to arbitrary exact partition cells.

The editor consumer needs constructed split/clip geometry.

Publishing the partition now would expose:

- point-cell versus open-interval-cell representation;
- exact transition ordering semantics;
- workspace/capacity details;
- potentially construction-neutral exact event concepts

without a demonstrated second public consumer.

The initial production direction is therefore:

~~~text
public SegmentPolygonRelationship
        |
        | existential facts only
        v

private exact segment/polygon partition kernel
        |
        | ordered exact topology
        v

public checked clipping construction
~~~

A public partition API remains possible later if an independent consumer requires it.

### 2. Initial public operation should be a constructive clip, not a policy-free cell stream

The concrete editor requirement is to construct the portions of a segment selected by polygon-set membership.

The most natural initial semantic operation is **closed-set intersection**:

~~~text
segment ∩ polygon
~~~

where polygon means the closed polygonal region:

~~~text
Interior(P) ∪ Boundary(P)
~~~

Consequences:

- wholly exterior segment -> successful empty result;
- wholly interior segment -> the complete segment;
- boundary-only segment -> the complete segment;
- proper crossing -> one or more clipped segment components;
- positive-length boundary overlap is retained;
- tangency may produce an isolated point in the mathematical intersection.

The last case requires a deliberate result-model decision because an ordinary `Segment2` cannot distinguish a retained isolated point from a degenerate segment component without assigning that interpretation explicitly.

Therefore the first public result design must decide whether isolated point contacts are:

- retained as explicit point components;
- retained as degenerate segment components;
- or omitted by a deliberately 1D-regularized clipping contract.

This semantic choice is still open and must be settled before public API freeze.

### 3. Do not copy polygon-union ownership mechanically

`polygonUnion` justifies an explicit owning immutable result because:

- output topology is complex;
- component/ring/point counts are data dependent;
- a caller-buffer preflight would effectively repeat substantial overlay work.

Segment/polygon clipping is materially smaller.

With `n` polygon boundary edges, the research has a hard O(n) result/event bound:

~~~text
breakpoints <= 2n + 2
intervals   <= 2n + 1
~~~

This makes caller-managed storage significantly more plausible than for polygon union.

The design gate should therefore compare:

#### Option A — caller-provided destination/workspace

Advantages:

- can remain allocation-free;
- natural fit for low-level geometry;
- explicit capacity;
- reusable by editor hot paths.

Costs:

- public sizing rules/workspace become API;
- a preflight may be required;
- isolated point components complicate layout.

#### Option B — explicit owning immutable result

Advantages:

- simplest consumer use;
- no caller capacity protocol;
- natural checked all-or-nothing construction.

Costs:

- allocation for a potentially small operation;
- weaker fit for repeated editor hot paths;
- may over-apply the polygon-union ownership pattern.

#### Option C — two-level kernel + convenience owner

Advantages:

- allocation-free low-level path remains possible;
- optional owning convenience can be layered later;
- matches the proven separation between exact topology and materialization.

Costs:

- more API surface if both levels become public;
- should not be introduced without actual dual-consumer evidence.

No ownership choice is frozen yet.

### 4. Checked construction status is justified

Unlike `SegmentPolygonRelationship`, clipping materializes transition coordinates.

Distinct exact breakpoints may round to the same `IntersectionScalar!T` coordinate.

Successful construction therefore must not be inferred merely from exact topology.

A checked result needs to distinguish at least:

~~~text
not computed / default state
success
unrepresentable construction
~~~

Input-validation status depends on the eventual precondition decision.

If the public operation accepts only a prevalidated polygon, then invalid-polygon status is unnecessary and the operation can preserve the established hot-query pattern used by `SegmentPolygonRelationship`.

If the public operation validates internally, checked invalid-input states become necessary but repeated editor clipping pays validation cost repeatedly.

Current consumer evidence favors **prevalidated polygon input** for repeated clipping, with validation performed once by the caller.

This is not yet frozen.

### 5. Construction scalar should follow the existing intersection family

Proper segment/polygon crossings can be rational for integral input.

The first construction-scalar candidate remains:

~~~text
IntersectionScalar!T
~~~

which is currently `double` for:

~~~text
int
long
float
double
~~~

This reuses the established exact-before-round construction policy.

The exact partition remains authoritative until all selected result geometry is known to be faithfully representable.

### 6. Geometry-neutral internal refactor is now justified in principle

Clipping is now a proven second internal consumer of exact event-point and source-order machinery previously housed under polygon-union naming.

A private refactor toward geometry-neutral internal names is therefore justified **if** production implementation proceeds and the shared contract is unchanged.

Candidate shared concepts include:

- exact represented/rational event point;
- exact point equality;
- exact source-segment ordering;
- touch/crossing/overlap event insertion;
- exact event sorting and deduplication.

This does not justify:

- public exact rational types;
- `euclid-core-d` growth;
- a public generic noding API;
- extracting polygon-arrangement-specific logic.

### 7. Polyline clipping remains downstream of the segment contract

Once segment clipping semantics, point-contact policy, construction failure, and ownership are frozen, polyline clipping can be evaluated as composition.

The polyline layer must additionally resolve:

- duplicate transition points at shared source vertices;
- joining adjacent clipped pieces;
- preservation of source traversal order;
- zero-length or point-only contacts;
- component boundaries across successive source segments.

No separate polyline public API is authorized yet.

## Remaining design gates

Before production API:

1. settle isolated point-contact semantics:
   - retain explicit point;
   - degenerate segment;
   - or 1D-regularized omission;
2. compare caller-buffer vs owning-result prototypes;
3. construct and verify a binary64 breakpoint-collapse fixture;
4. freeze prevalidated-input versus internally validated input contract;
5. define exact success/failure/result semantics;
6. verify scalar and attribute contracts;
7. decide public spelling only after those contracts are fixed;
8. then create a dedicated design issue/ADR if the public semantics warrant it.


## Isolated point-contact disposition

### Reference-library comparison

There is no single universal clipping-result convention for lower-dimensional
contacts.

JTS defines `intersection` as the point-set intersection. For mixed-dimensional
inputs, the result dimension is at most the minimum input dimension, and the
result may be heterogeneous. OverlayNG explicitly retains lower-dimensional
intersection components and may therefore return a point component together
with line components.

Boost.Geometry exposes intersection output through the requested output
geometry type. Point output computes intersection points, while linestring
output computes linear intersection results. This separates 0D and 1D result
families rather than forcing them into one heterogeneous result carrier.

Clipper2's open-path clipping is path-oriented. Its ordinary open-path model is
a sequence of line segments and normally requires at least two vertices.
Its documentation also demonstrates that boundary-collinear open-path policy
is application-oriented rather than a unique set-theoretic convention.

These differences are evidence that geo-d must choose semantics from its own
consumer and type model rather than copy one library.

### Consumer requirement

The current editor-backed requirement is to construct the positive-length
parts of a segment retained by a polygonal clipping region.

For the concrete workflows:

- a segment that crosses a polygon needs split line pieces;
- a segment partly or wholly on the polygon boundary may need retained
  positive-length boundary pieces;
- a segment that only touches the polygon at one isolated point does **not**
  produce a line portion to keep;
- the fact that this isolated boundary contact exists is already available
  through `SegmentPolygonRelationship.hasBoundary`.

Therefore retaining an isolated tangent point inside the constructive clipping
result would duplicate relationship information while forcing a heterogeneous
point-or-segment result type.

### Initial clipping semantics: 1D-regularized closed-set clip

The initial constructive operation should therefore return the
**positive-length one-dimensional components** of:

~~~text
segment ∩ (Interior(P) ∪ Boundary(P))
~~~

Equivalently, compute the ordinary closed-set intersection and discard
connected components of topological dimension zero.

This is a deliberate 1D regularization of the constructive result.

Consequences:

~~~text
wholly exterior
    -> successful empty result

proper tangent from exterior to exterior
    -> successful empty result

vertex touch with no retained line interval
    -> successful empty result

proper crossing
    -> retained positive-length inside/boundary components

wholly interior
    -> complete segment

positive-length boundary overlap
    -> retained

boundary-only positive-length segment
    -> complete segment
~~~

The operation is **not** a generic point-set intersection API.

Its documentation must say explicitly that isolated 0D contacts are omitted.

Consumers that need to know whether a point contact exists use
`SegmentPolygonRelationship`, whose exact relationship contract already
preserves that fact without construction.

### Degenerate input segment

A degenerate `Segment2` has geometric dimension zero and cannot contain a
positive-length 1D clipping component.

Under the 1D-regularized construction contract, a degenerate query therefore
produces a successful empty clipping result regardless of whether its point is
outside, on the boundary, or inside the polygon.

This does **not** erase its location semantics:

- `classifySegmentPolygonRelationship` still distinguishes exterior,
  boundary, and interior for the degenerate query;
- the constructive clipping operation answers the narrower question of which
  positive-length segment components can be materialized.

This split follows the established geo-d separation between relationship facts
and construction.

### Why not represent a point as a degenerate Segment2

Using `Segment2(p, p)` for an isolated point would make one storage type carry
two materially different result dimensions:

- a genuine retained 1D segment;
- a 0D point encoded as a degenerate segment.

That would force every consumer to inspect endpoint equality to recover result
kind and would make length/component semantics less explicit.

No current consumer evidence justifies that ambiguity.

### Why not publish a heterogeneous point/segment result

A tagged public component such as:

~~~text
point
segment
~~~

would preserve full set-theoretic intersection, but it expands the public
contract substantially:

- heterogeneous component iteration;
- 0D/1D ordering rules;
- construction failure for point coordinates and segment endpoints;
- polyline composition of isolated points;
- duplicate point suppression;
- interaction with adjacent retained line pieces.

JTS needs such heterogeneity because it exposes a generic set-theoretic overlay
model. geo-d currently has no corresponding consumer requirement.

The smaller 1D-regularized clip is therefore preferred.

### Design disposition

For the first production design:

- **ADOPT** positive-length 1D clipping components;
- **OMIT** isolated point contacts from constructed output;
- **REUSE** `SegmentPolygonRelationship` when the consumer needs contact
  existence/location facts;
- **DEFER** a generic heterogeneous point-set intersection API.

This disposition simplifies the remaining result/ownership design because every
successful output component is an ordinary nondegenerate
`Segment2!(IntersectionScalar!T)`.

The exact private partition kernel still retains 0D boundary events internally;
they are omitted only when selecting public 1D construction components.


## Ownership and workspace disposition

### Existing geo-d patterns

The repository currently contains two intentionally different variable-size
algorithm patterns.

`trySimplifyDouglasPeuckerInto` uses caller-owned destination and workspace
storage because its auxiliary state is simple, public-semantic-free data:

~~~text
destination : Point2!T[]
workspace   : size_t[]
~~~

The exact worst-case workspace size is cheaply known from input point count and
the workspace elements expose no internal numerical representation.

`polygonUnion` instead returns an explicit immutable owning result because its
workspace and output topology are data dependent and tightly coupled to private
exact overlay machinery.

Segment/polygon clipping lies between these cases.

### Why a public caller-owned exact-event workspace is unattractive

The efficient exact partition candidate needs up to:

~~~text
2n + 2 exact breakpoint events
~~~

for `n` polygon boundary edges.

Those events are not simple indices. They contain private exact rational
coordinate state equivalent to:

~~~text
signed exact x numerator
signed exact y numerator
positive exact denominator
~~~

Publishing a typed caller-owned workspace would therefore expose internal
exact-arithmetic representation merely to avoid allocation.

A byte-oriented opaque workspace API would avoid the type exposure but create
new public obligations for:

- byte capacity;
- alignment;
- internal layout/versioning;
- safe construction inside untyped storage.

That is a poor fit for the current geo-d API.

### O(1)-workspace alternative has a worse algorithmic trade-off

It is possible in principle to avoid storing all events by repeatedly scanning
all polygon edges to discover the next exact event along the query segment.

That preserves private exact representation and can use O(1) auxiliary
workspace, but ordering `O(n)` events by repeated full scans becomes O(n^2)
contact work.

The existing buffered candidate performs:

~~~text
event generation       O(n)
exact event sort        O(n log n)
selection/materialize   O(n) or O(n log n), depending final label strategy
workspace               O(n)
~~~

The research has no evidence that sacrificing this asymptotic behavior merely
to promise `@nogc` improves the real editor workflow.

### Hot relationship query and constructive clipping are different paths

The repeated validation/detection hot path is already served by:

~~~d
classifySegmentPolygonRelationship(...)
    pure nothrow @safe @nogc
~~~

Constructive clipping is needed only when the consumer actually requires split
geometry.

This is a materially different use case.

The constructive API therefore does not need to inherit the relationship
classifier's allocation-free contract by default.

### Initial ownership decision

The initial production design should use an **explicit immutable owning result**
for constructed clip components.

Conceptually, successful backing is only:

~~~text
immutable Segment2!double[]
~~~

because the settled 1D-regularized semantics expose only positive-length linear
components.

Ordinary result copies should share immutable backing and must not deep-copy
component geometry.

The components are stored in query traversal order.

No canonical reordering independent of query direction is required: traversal
order is part of the clipping result.

### Why the owning result is smaller than PolygonUnionResult

Segment clipping does not need public storage for:

- rings;
- polygon components;
- holes;
- arrangement vertices;
- boundary graphs;
- topology metadata.

After exact selection succeeds, each retained connected 1D component requires
only two public construction endpoints.

Adjacent selected exact interval cells are merged before materialization, so a
maximal retained component is represented by one output segment.

### Successful-empty versus default state

Successful empty output is common:

- wholly exterior query;
- isolated tangent contact;
- degenerate query under the 1D-regularized contract.

Therefore default/uncomputed state must remain distinguishable from successful
empty construction.

An owning result should consequently carry explicit checked status rather than
use an empty slice as both states.

The minimum currently justified status family is conceptually:

~~~text
notComputed
success
unrepresentableConstruction
~~~

Input-invalid states are not included if the final design keeps the existing
prevalidated-polygon contract.

Public spelling is not yet frozen.

### Construction failure

For each retained exact component with endpoints `aExact`, `bExact`:

1. both exact points must round to finite
   `Point2!(IntersectionScalar!T)`;
2. the two exact endpoints are known distinct;
3. their rounded public points must remain distinct.

If two distinct exact component endpoints round to the same binary64 point, the
positive-length exact component cannot be represented faithfully as
`Segment2!double`.

The complete construction must then fail with
`unrepresentableConstruction`; no partial component list is exposed.

For a one-dimensional result along one source segment, preserving strict
endpoint order and non-collapse is likely sufficient to preserve component
topology. The binary64-collapse probe remains the gate for proving the minimal
validation set.

### Allocation model

The initial implementation may allocate:

- O(n) private exact event workspace;
- temporary internal selection metadata where required;
- one final output array of retained `Segment2!double` components.

Allocation/resource exhaustion follows normal D runtime failure semantics and
is not a geometric clipping status, matching the polygon-union precedent.

The public operation therefore is not expected to promise `@nogc`.

### Deferred low-level API

A caller-managed or reusable-workspace clipping API is **DEFERRED**, not
rejected permanently.

It becomes justified if later profiling of real editor consumers demonstrates
that repeated constructive clipping allocation is material.

Such a future API should reuse the same exact topology/materialization
semantics rather than create a second clipping definition.

### Ownership disposition

For the first production design:

- **ADOPT** explicit immutable owning result;
- **KEEP PRIVATE** exact O(n) event workspace;
- **PRESERVE** query traversal order;
- **DISTINGUISH** successful empty from default/uncomputed;
- **CHECK** all-or-nothing representability;
- **DEFER** public caller-managed/reusable workspace until measured consumer
  evidence exists.


## Binary64 materialization contract for ordered 1D output

Two executable collapse probes establish that binary64 construction can change
the exact one-dimensional result topology in more than one way.

### Probe A — one exact component collapses

`docs/research/segment_polygon_binary64_collapse_probe.d`

Verified on DMD and LDC.

A positive-length exact component from:

~~~text
long.max - 1
to
long.max
~~~

has distinct, strictly ordered, individually finite exact endpoints.

Both endpoints correctly round to the same binary64 point.

Therefore finite rounding alone is insufficient.

### Probe B — an exact positive gap collapses

`docs/research/segment_polygon_binary64_component_gap_probe.d`

Verified on DMD and LDC.

A polygon with a narrow hole near `2^53` yields two distinct positive-length
exact clipping components separated by a positive exterior interval.

Both retained components remain individually nondegenerate after binary64
rounding, but the rounded end of the first component equals the rounded start
of the second.

Therefore per-component nondegeneracy is also insufficient.

### Authoritative traversal axis

All exact clipping endpoints lie on the same source segment.

For a nondegenerate source segment:

- if `query.a.x != query.b.x`, x is strictly monotone along the source;
- otherwise y is strictly monotone.

This is already the exact event-order rule used by geo-d.

The same source-axis choice provides the minimal public materialization gate.

Let the retained exact components in query traversal order be:

~~~text
[s0, e0], [s1, e1], ..., [sk-1, ek-1]
~~~

with exact order:

~~~text
s0 < e0 < s1 < e1 < ... < sk-1 < ek-1
~~~

where `<` means order along the authoritative source axis.

Successful binary64 construction requires the corresponding rounded public
coordinates to preserve the same strict axis order.

For a query traversing increasing x, for example:

~~~text
round(s0).x < round(e0).x
round(e0).x < round(s1).x
round(s1).x < round(e1).x
...
~~~

For decreasing source traversal, the inequalities reverse.

Vertical queries use y instead.

### Why strict source-axis order is stronger than endpoint inequality

A rounded component can theoretically remain geometrically nondegenerate while
its two endpoints collapse on the authoritative source axis and differ only in
the orthogonal coordinate.

Checking only:

~~~text
roundedStart != roundedEnd
~~~

would accept such a construction even though source traversal order was no
longer represented faithfully.

The correct gate is therefore strict preservation of source-axis order, not
merely nonzero Euclidean endpoint distance.

### Sufficiency for complete 1D component topology

Strict source-axis order of every consecutive materialized endpoint is
sufficient to preserve the complete ordered 1D component topology.

Reason:

1. every materialized output component endpoint is finite;
2. each component's start precedes its end strictly on the authoritative axis;
3. each component end precedes the next component start strictly on that axis;
4. by transitivity, every later component lies strictly beyond every earlier
   component on that axis;
5. the axis projections of distinct components are therefore disjoint;
6. two line segments whose projections on one coordinate axis are disjoint
   cannot intersect or overlap.

Thus no O(k^2) global segment-pair validation is needed for the one-source-
segment clipping result.

The required materialization validation is linear in output component count.

### Minimal checked construction gate

For each selected exact endpoint:

1. exact x and y must round to finite
   `IntersectionScalar!T` coordinates.

For the resulting ordered component endpoint sequence:

2. strict order on the authoritative source axis must match exact/query
   traversal order.

This one strict-order condition simultaneously guarantees:

- no retained component collapses;
- no retained component reverses;
- no positive exact gap collapses;
- distinct components remain disjoint;
- output component order remains faithful.

If either finite rounding or strict ordered-axis preservation fails, the
complete operation returns `unrepresentableConstruction`.

No partial geometry is exposed.

### Complexity

If `k` retained components are selected, the construction validation is:

~~~text
time  O(k)
space O(1) beyond result storage
~~~

after exact topology and component selection are complete.

This is substantially smaller than polygon-union materialization validation
because every result component derives from one common source segment and has
a globally monotone authoritative axis.

## Input-validation disposition

### Established neighboring contract

`classifySegmentPolygonRelationship` already defines the intended reusable
query boundary:

~~~text
polygon
    valid according to validatePolygon(polygon).valid

segment
    finite
~~~

Polygon validation is deliberately outside the operation so one validated
polygon can serve many segment queries.

The clipping consumer has the same reuse pattern.

A typical editor workflow is:

~~~text
construct/read polygon
        |
        v
validate once
        |
        +--------------------+
        |                    |
        v                    v
many relationship       selected constructive
queries                 clipping operations
~~~

Repeating polygon validation for every segment clip would therefore duplicate
work that the caller can perform once.

### Why polygonUnion differs

`polygonUnion` validates both operands internally and reports
`invalidFirstInput` / `invalidSecondInput`.

That is appropriate for its contract:

- both polygons are primary operation operands;
- the operation is a self-contained aggregate construction;
- there is no established one-polygon/many-query hot-path family around it.

Segment/polygon clipping is different.

Its polygon operand is naturally reusable across many segment queries and
already has a neighboring prevalidated operation with identical topology
domain.

The union status model should therefore not be copied mechanically.

### Frozen input domain

The initial clipping construction is defined for:

~~~text
Segment2!T segment
Polygon2View!T polygon
~~~

where:

1. `T` is one of `int`, `long`, `float`, or `double`;
2. `polygon` satisfies `validatePolygon(polygon).valid`;
3. `segment` is finite.

An empty polygon is valid.

A degenerate finite segment is valid input and, under the settled
1D-regularized construction semantics, produces successful empty output.

`real` remains outside the robust topology/construction domain.

### Public behavior outside preconditions

Invalid polygon topology and non-finite segment input are not checked geometry
result alternatives.

The operation may retain development-time assertions for these preconditions,
matching `classifySegmentPolygonRelationship`.

No successful clipping geometry has defined semantics outside the precondition
domain.

### Status consequence

Because validation is external, the checked result does not need:

~~~text
invalidPolygon
invalidSegment
invalidInput
~~~

states.

The minimum justified result status remains:

~~~text
notComputed
success
unrepresentableConstruction
~~~

Runtime resource/allocation exhaustion remains ordinary D runtime failure and
is not represented by the geometry status.

This keeps the status type focused on construction rather than validation.

### Validation responsibility

Consumers that do not already know polygon validity should call
`validatePolygon(polygon)` before clipping.

Consumers processing many segment queries against one polygon should validate
once and reuse the result.

This is particularly appropriate for the OSM editor workflow, where a selected
area/building geometry is typically queried by multiple linear segments or
operations.

### Consistency with relationship queries

The relationship and constructive APIs now share one semantic input boundary:

~~~text
prevalidated valid polygon
finite segment
robust scalar domain
~~~

and differ only in result purpose:

~~~text
relationship
    exact existential facts
    allocation-free
    no construction failure

clipping
    exact ordered topology internally
    rounded constructed 1D components
    owning result
    checked representability
~~~

This shared boundary reduces duplicated validation policy and keeps the two
families composable.

## Status/result contract direction

With point-contact semantics, ownership, materialization, and input validation
now settled, the remaining checked result shape is narrow.

Conceptually:

~~~text
Status
    notComputed
    success
    unrepresentableConstruction

Result
    status
    immutable ordered Segment2!double[] components
~~~

Successful empty output is represented by:

~~~text
status == success
components.length == 0
~~~

and is distinct from:

~~~text
Result.init
status == notComputed
~~~

On `unrepresentableConstruction`:

- no partial component list is exposed;
- result geometry access is invalid;
- exact topology remains authoritative but cannot be faithfully represented
  in the public construction scalar.

This is now sufficiently constrained for a dedicated design issue / ADR gate
before production implementation.
