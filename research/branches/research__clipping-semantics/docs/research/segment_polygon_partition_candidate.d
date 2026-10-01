module segment_polygon_partition_candidate;

import geo.internal.polygon_union_exact :
    ExactOverlayPoint,
    appendSegmentPairNodingEvents,
    compareExactOverlayPointsAlongSegment,
    exactOverlayPoint,
    exactOverlayPointsEqual,
    seedExactEdgeEvents,
    sortUniqueExactEdgeEvents;

import geo.linear_ring_view : LinearRing2View;
import geo.point : Point2;
import geo.polygon_view : Polygon2View;
import geo.segment : Segment2;

import std.stdio : writeln;


/*
 * Research-only breakpoint candidate for #58.
 *
 * This intentionally exercises existing geo-d exact event/noding machinery.
 * It is not public API and does not yet classify open intervals.
 */


private size_t polygonEdgeCount(T)(
    scope Polygon2View!T polygon
)
{
    size_t result;

    foreach (ringIndex; 0 .. polygon.length)
        result += polygon[ringIndex].segmentCount;

    return result;
}


private ExactOverlayPoint[] collectExactBreakpoints(T)(
    Segment2!T query,
    scope Polygon2View!T polygon
)
if (
    is(T == int) ||
    is(T == long) ||
    is(T == float) ||
    is(T == double)
)
{
    if (query.a == query.b)
    {
        ExactOverlayPoint[] result =
            new ExactOverlayPoint[1];

        result[0] =
            exactOverlayPoint(
                query.a
            );

        return result;
    }

    const size_t edgeCount =
        polygonEdgeCount(polygon);

    /*
     * Hard research bound:
     *
     * two query endpoints
     * +
     * at most two contact endpoints contributed by each polygon edge.
     */
    ExactOverlayPoint[] events =
        new ExactOverlayPoint[
            2 * edgeCount + 2
        ];

    size_t count;

    assert(
        seedExactEdgeEvents(
            query,
            events[],
            count
        )
    );

    foreach (ringIndex; 0 .. polygon.length)
    {
        const auto ring =
            polygon[ringIndex];

        foreach (edgeIndex; 0 .. ring.segmentCount)
        {
            const Segment2!T edge =
                ring.segment(edgeIndex);

            /*
             * Only the query-side events are retained.
             *
             * appendSegmentPairNodingEvents requires storage for both source
             * segments; one pair can contribute at most two events to the
             * polygon edge side.
             */
            ExactOverlayPoint[2] edgeEvents;
            size_t edgeEventCount;

            const bool appended =
                appendSegmentPairNodingEvents(
                    query,
                    edge,
                    events[],
                    count,
                    edgeEvents[],
                    edgeEventCount
                );

            assert(appended);
        }
    }

    count =
        sortUniqueExactEdgeEvents(
            query,
            events[0 .. count]
        );

    events.length = count;

    return events;
}


private void assertStrictQueryOrder(T)(
    Segment2!T query,
    scope const(ExactOverlayPoint)[] events
)
if (
    is(T == int) ||
    is(T == long) ||
    is(T == float) ||
    is(T == double)
)
{
    if (query.a == query.b)
    {
        assert(events.length == 1);
        return;
    }

    foreach (i; 1 .. events.length)
    {
        assert(
            compareExactOverlayPointsAlongSegment(
                query,
                events[i - 1],
                events[i]
            ) < 0
        );
    }
}


private void expectBreakpoints(T)(
    string name,
    Segment2!T query,
    scope Polygon2View!T polygon,
    size_t expectedCount
)
if (
    is(T == int) ||
    is(T == long) ||
    is(T == float) ||
    is(T == double)
)
{
    const auto events =
        collectExactBreakpoints(
            query,
            polygon
        );

    if (events.length != expectedCount)
    {
        import std.format : format;

        assert(
            false,
            format(
                "%s: expected %s breakpoints, got %s",
                name,
                expectedCount,
                events.length
            )
        );
    }

    assertStrictQueryOrder(
        query,
        events
    );

    if (query.a == query.b)
    {
        const auto endpoint =
            exactOverlayPoint(
                query.a
            );

        assert(
            exactOverlayPointsEqual(
                events[0],
                endpoint
            )
        );

        return;
    }

    const auto first =
        exactOverlayPoint(
            query.a
        );

    const auto last =
        exactOverlayPoint(
            query.b
        );

    assert(
        exactOverlayPointsEqual(
            events[0],
            first
        )
    );

    assert(
        exactOverlayPointsEqual(
            events[$ - 1],
            last
        )
    );

    const size_t edgeCount =
        polygonEdgeCount(polygon);

    assert(
        events.length <=
        2 * edgeCount + 2
    );
}


private Polygon2View!int squarePolygon(
    ref Point2!int[4] points,
    ref LinearRing2View!int[1] rings
)
{
    points = [
        Point2!int(0, 0),
        Point2!int(10, 0),
        Point2!int(10, 10),
        Point2!int(0, 10)
    ];

    rings[0] =
        LinearRing2View!int(
            points[]
        );

    return
        Polygon2View!int(
            rings[]
        );
}


void main()
{
    alias P = Point2!int;
    alias S = Segment2!int;
    alias R = LinearRing2View!int;
    alias G = Polygon2View!int;

    P[4] squarePoints;
    R[1] squareRings;

    const G square =
        squarePolygon(
            squarePoints,
            squareRings
        );

    expectBreakpoints(
        "outside",
        S(
            P(-5, -2),
            P(-1, -2)
        ),
        square,
        2
    );

    expectBreakpoints(
        "inside",
        S(
            P(2, 2),
            P(8, 8)
        ),
        square,
        2
    );

    expectBreakpoints(
        "proper crossing",
        S(
            P(-5, 5),
            P(15, 5)
        ),
        square,
        4
    );

    expectBreakpoints(
        "convex tangency",
        S(
            P(-5, 5),
            P(5, -5)
        ),
        square,
        3
    );

    expectBreakpoints(
        "boundary endpoint to interior",
        S(
            P(0, 5),
            P(5, 5)
        ),
        square,
        2
    );

    expectBreakpoints(
        "boundary chord",
        S(
            P(0, 5),
            P(10, 5)
        ),
        square,
        2
    );

    expectBreakpoints(
        "boundary only",
        S(
            P(0, 2),
            P(0, 8)
        ),
        square,
        2
    );

    expectBreakpoints(
        "boundary overlap plus exterior",
        S(
            P(0, -5),
            P(0, 5)
        ),
        square,
        3
    );

    expectBreakpoints(
        "degenerate",
        S(
            P(0, 5),
            P(0, 5)
        ),
        square,
        1
    );


    P[8] concavePoints = [
        P(0, 0),
        P(10, 0),
        P(10, 10),
        P(7, 10),
        P(7, 3),
        P(3, 3),
        P(3, 10),
        P(0, 10)
    ];

    R[1] concaveRings = [
        R(concavePoints[])
    ];

    const G concaveU =
        G(concaveRings[]);

    expectBreakpoints(
        "concave exterior chord",
        S(
            P(3, 5),
            P(7, 5)
        ),
        concaveU,
        2
    );

    expectBreakpoints(
        "separated boundary overlaps",
        S(
            P(0, 10),
            P(10, 10)
        ),
        concaveU,
        4
    );


    P[4] outerPoints = [
        P(0, 0),
        P(20, 0),
        P(20, 20),
        P(0, 20)
    ];

    P[4] holePoints = [
        P(5, 5),
        P(15, 5),
        P(15, 15),
        P(5, 15)
    ];

    R[2] holeRings = [
        R(outerPoints[]),
        R(holePoints[])
    ];

    const G withHole =
        G(holeRings[]);

    expectBreakpoints(
        "hole crossing",
        S(
            P(2, 10),
            P(18, 10)
        ),
        withHole,
        4
    );

    expectBreakpoints(
        "wholly in hole",
        S(
            P(6, 10),
            P(14, 10)
        ),
        withHole,
        2
    );

    expectBreakpoints(
        "full exterior-polygon-hole crossing",
        S(
            P(-2, 10),
            P(22, 10)
        ),
        withHole,
        6
    );

    expectBreakpoints(
        "hole boundary overlap",
        S(
            P(5, 6),
            P(5, 14)
        ),
        withHole,
        2
    );


    R[] noRings;

    const G empty =
        G(noRings);

    expectBreakpoints(
        "empty polygon",
        S(
            P(1, 2),
            P(3, 4)
        ),
        empty,
        2
    );


    /*
     * Rational proper crossings: no represented integer point exists at
     * either transition.
     */
    {
        P[4] rationalPoints = [
            P(0, 0),
            P(7, 0),
            P(7, 7),
            P(0, 7)
        ];

        R[1] rationalRings = [
            R(rationalPoints[])
        ];

        const G rationalSquare =
            G(rationalRings[]);

        expectBreakpoints(
            "rational proper crossings",
            S(
                P(-2, 1),
                P(9, 6)
            ),
            rationalSquare,
            4
        );
    }


    /*
     * Query reversal must preserve the same exact event count and strict
     * traversal ordering in the opposite direction.
     */
    {
        const S forward =
            S(
                P(-5, 5),
                P(15, 5)
            );

        const S reverse =
            S(
                forward.b,
                forward.a
            );

        const auto forwardEvents =
            collectExactBreakpoints(
                forward,
                square
            );

        const auto reverseEvents =
            collectExactBreakpoints(
                reverse,
                square
            );

        assert(
            forwardEvents.length ==
            reverseEvents.length
        );

        foreach (i; 0 .. forwardEvents.length)
        {
            assert(
                exactOverlayPointsEqual(
                    forwardEvents[i],
                    reverseEvents[
                        reverseEvents.length - 1 - i
                    ]
                )
            );
        }
    }


    writeln(
        "SEGMENT POLYGON EXACT BREAKPOINT CANDIDATE PASS"
    );
}
