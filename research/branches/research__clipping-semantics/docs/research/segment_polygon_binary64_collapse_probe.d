module segment_polygon_binary64_collapse_probe;

import geo.internal.exact_coordinate :
    roundsToFiniteBinary64;

import geo.internal.exact_coordinate_round :
    roundExactCoordinateBinary64;

import geo.internal.polygon_union_exact :
    ExactOverlayPoint,
    compareExactOverlayPointsAlongSegment,
    exactOverlayPoint,
    exactOverlayPointsEqual;

import geo.intersection :
    IntersectionScalar;

import geo.linear_ring_view :
    LinearRing2View;

import geo.point :
    Point2;

import geo.polygon_view :
    Polygon2View;

import geo.segment :
    Segment2;

import geo.segment_polygon_relationship :
    SegmentPolygonRelationship,
    classifySegmentPolygonRelationship;

import geo.topology_validation :
    validatePolygon;

import std.stdio :
    writeln;


/*
 * Research probe for geo-d #58.
 *
 * Establishes a positive-length exact clipping component whose two exact
 * endpoints correctly round to the same binary64 point.
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
    static assert(
        is(
            IntersectionScalar!long ==
            double
        )
    );

    alias P = Point2!long;
    alias S = Segment2!long;
    alias R = LinearRing2View!long;
    alias G = Polygon2View!long;

    enum long x0 =
        long.max - 1;

    enum long x1 =
        long.max;

    P[4] polygonPoints = [
        P(x0, 0),
        P(x1, 0),
        P(x1, 10),
        P(x0, 10)
    ];

    R[1] rings = [
        R(polygonPoints[])
    ];

    const G polygon =
        G(rings[]);

    const validation =
        validatePolygon(polygon);

    assert(validation.valid);

    const S query =
        S(
            P(x0, 5),
            P(x1, 5)
        );

    assert(query.a != query.b);

    const SegmentPolygonRelationship relationship =
        classifySegmentPolygonRelationship(
            query,
            polygon
        );

    /*
     * The complete positive-length query lies in the closed polygon.
     * Endpoints are boundary; strict interior points are interior.
     */
    assert(!relationship.hasExterior);
    assert(relationship.hasBoundary);
    assert(relationship.hasInterior);
    assert(!relationship.hasBoundaryOverlap);

    const ExactOverlayPoint firstExact =
        exactOverlayPoint(
            query.a
        );

    const ExactOverlayPoint secondExact =
        exactOverlayPoint(
            query.b
        );

    assert(
        !exactOverlayPointsEqual(
            firstExact,
            secondExact
        )
    );

    assert(
        compareExactOverlayPointsAlongSegment(
            query,
            firstExact,
            secondExact
        ) < 0
    );

    Point2!double firstRounded;
    Point2!double secondRounded;

    assert(
        tryMaterialize(
            firstExact,
            firstRounded
        )
    );

    assert(
        tryMaterialize(
            secondExact,
            secondRounded
        )
    );

    /*
     * Both exact endpoints are finite and individually representable as
     * binary64, yet their correctly rounded public points collapse.
     */
    assert(
        firstRounded ==
        secondRounded
    );

    /*
     * The exact component has positive length, but naive endpoint
     * materialization would produce a zero-length public Segment2.
     */
    const Segment2!double roundedSegment =
        Segment2!double(
            firstRounded,
            secondRounded
        );

    assert(
        roundedSegment.a ==
        roundedSegment.b
    );

    writeln(
        "x0 exact: ",
        x0
    );

    writeln(
        "x1 exact: ",
        x1
    );

    writeln(
        "rounded x0: ",
        firstRounded.x
    );

    writeln(
        "rounded x1: ",
        secondRounded.x
    );

    writeln(
        "SEGMENT POLYGON BINARY64 COLLAPSE PROBE PASS"
    );
}
