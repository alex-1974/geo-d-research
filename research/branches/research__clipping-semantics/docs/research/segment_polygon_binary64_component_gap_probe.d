module segment_polygon_binary64_component_gap_probe;

import geo.internal.exact_coordinate :
    roundsToFiniteBinary64;

import geo.internal.exact_coordinate_round :
    roundExactCoordinateBinary64;

import geo.internal.polygon_union_exact :
    ExactOverlayPoint,
    compareExactOverlayPointsAlongSegment,
    exactOverlayPoint,
    exactOverlayPointsEqual;

import geo.linear_ring_view :
    LinearRing2View;

import geo.point :
    Point2;

import geo.polygon_view :
    Polygon2View;

import geo.segment :
    Segment2;

import geo.segment_polygon_relationship :
    classifySegmentPolygonRelationship;

import geo.topology_validation :
    validatePolygon;

import std.stdio :
    writeln;


/*
 * Research probe for geo-d #58.
 *
 * Establishes two distinct positive-length exact clipping components that
 * remain individually non-degenerate after binary64 rounding while the exact
 * positive gap between them collapses, causing the public components to touch.
 */


private bool tryMaterialize(
    ref const ExactOverlayPoint exact,
    out Point2!double result
)
{
    result = Point2!double.init;

    if (
        !roundsToFiniteBinary64(
            exact.xNumerator,
            exact.denominator
        ) ||
        !roundsToFiniteBinary64(
            exact.yNumerator,
            exact.denominator
        )
    )
    {
        return false;
    }

    result =
        Point2!double(
            roundExactCoordinateBinary64(
                exact.xNumerator,
                exact.denominator
            ),
            roundExactCoordinateBinary64(
                exact.yNumerator,
                exact.denominator
            )
        );

    return result.isFinite;
}


void main()
{
    alias P = Point2!long;
    alias S = Segment2!long;
    alias R = LinearRing2View!long;
    alias G = Polygon2View!long;

    enum long base =
        9_007_199_254_740_992L; // 2^53

    enum long outerLeft =
        base - 2;

    enum long holeLeft =
        base;

    enum long holeRight =
        base + 1;

    enum long outerRight =
        base + 4;

    P[4] outerPoints = [
        P(outerLeft, 0),
        P(outerRight, 0),
        P(outerRight, 10),
        P(outerLeft, 10)
    ];

    P[4] holePoints = [
        P(holeLeft, 2),
        P(holeRight, 2),
        P(holeRight, 8),
        P(holeLeft, 8)
    ];

    R[2] rings = [
        R(outerPoints[]),
        R(holePoints[])
    ];

    const G polygon =
        G(rings[]);

    assert(
        validatePolygon(polygon).valid
    );

    const S query =
        S(
            P(outerLeft, 5),
            P(outerRight, 5)
        );

    const auto relationship =
        classifySegmentPolygonRelationship(
            query,
            polygon
        );

    /*
     * The query contains two retained polygon-interior components separated
     * by the hole, which is polygon exterior. The hole-boundary crossings
     * also establish boundary contact.
     */
    assert(relationship.hasExterior);
    assert(relationship.hasBoundary);
    assert(relationship.hasInterior);
    assert(!relationship.hasBoundaryOverlap);

    const ExactOverlayPoint firstStart =
        exactOverlayPoint(
            P(outerLeft, 5)
        );

    const ExactOverlayPoint firstEnd =
        exactOverlayPoint(
            P(holeLeft, 5)
        );

    const ExactOverlayPoint secondStart =
        exactOverlayPoint(
            P(holeRight, 5)
        );

    const ExactOverlayPoint secondEnd =
        exactOverlayPoint(
            P(outerRight, 5)
        );

    assert(
        compareExactOverlayPointsAlongSegment(
            query,
            firstStart,
            firstEnd
        ) < 0
    );

    assert(
        compareExactOverlayPointsAlongSegment(
            query,
            firstEnd,
            secondStart
        ) < 0
    );

    assert(
        compareExactOverlayPointsAlongSegment(
            query,
            secondStart,
            secondEnd
        ) < 0
    );

    assert(
        !exactOverlayPointsEqual(
            firstEnd,
            secondStart
        )
    );

    Point2!double firstStartRounded;
    Point2!double firstEndRounded;
    Point2!double secondStartRounded;
    Point2!double secondEndRounded;

    assert(tryMaterialize(firstStart, firstStartRounded));
    assert(tryMaterialize(firstEnd, firstEndRounded));
    assert(tryMaterialize(secondStart, secondStartRounded));
    assert(tryMaterialize(secondEnd, secondEndRounded));

    /*
     * Each retained exact component remains non-degenerate.
     */
    assert(
        firstStartRounded !=
        firstEndRounded
    );

    assert(
        secondStartRounded !=
        secondEndRounded
    );

    /*
     * But the positive exact gap (the hole interval) collapses.
     *
     * Two exact disconnected result components would become touching in the
     * public binary64 result.
     */
    assert(
        firstEndRounded ==
        secondStartRounded
    );

    writeln(
        "first:  ",
        firstStartRounded.x,
        " -> ",
        firstEndRounded.x
    );

    writeln(
        "second: ",
        secondStartRounded.x,
        " -> ",
        secondEndRounded.x
    );

    writeln(
        "SEGMENT POLYGON BINARY64 COMPONENT GAP COLLAPSE PROBE PASS"
    );
}