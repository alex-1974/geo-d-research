module segment_polygon_partition_differential;

import geo.internal.polygon_union_exact :
    ExactOverlayPoint,
    appendSegmentPairNodingEvents,
    exactOverlayPoint,
    seedExactEdgeEvents,
    sortUniqueExactEdgeEvents;

import geo.linear_ring_view : LinearRing2View;
import geo.point : Point2;
import geo.polygon_view : Polygon2View;
import geo.segment : Segment2;

import std.bigint : BigInt;
import std.stdio : writeln;


/*
 * Differential research harness for geo-d #58.
 *
 * Candidate path:
 *   geo-d exact contact/event machinery -> exact ordered breakpoints
 *   -> independent BigInt label bridge.
 *
 * Oracle path:
 *   independent BigInt/rational segment-edge intersection
 *   -> independent exact breakpoint ordering
 *   -> independent BigInt point-in-polygon.
 *
 * The two paths share only the integer input fixtures and the mathematical
 * E/B/I output alphabet.
 */


private enum Location : ubyte
{
    exterior,
    boundary,
    interior,
}


private char code(Location location)
{
    final switch (location)
    {
        case Location.exterior:
            return 'E';

        case Location.boundary:
            return 'B';

        case Location.interior:
            return 'I';
    }
}


private struct Rational
{
    BigInt numerator;
    BigInt denominator;

    this(BigInt numerator, BigInt denominator)
    {
        assert(denominator != 0);

        if (denominator < 0)
        {
            numerator = -numerator;
            denominator = -denominator;
        }

        this.numerator = numerator;
        this.denominator = denominator;
    }
}


private Rational rational(long value)
{
    return Rational(BigInt(value), BigInt(1));
}


private int compareRational(
    ref const Rational lhs,
    ref const Rational rhs
)
{
    const BigInt left =
        lhs.numerator * rhs.denominator;

    const BigInt right =
        rhs.numerator * lhs.denominator;

    if (left < right)
        return -1;

    if (left > right)
        return 1;

    return 0;
}


private bool rationalEqual(
    ref const Rational lhs,
    ref const Rational rhs
)
{
    return compareRational(lhs, rhs) == 0;
}


private Rational midpoint(
    ref const Rational lhs,
    ref const Rational rhs
)
{
    return Rational(
        lhs.numerator * rhs.denominator +
            rhs.numerator * lhs.denominator,
        BigInt(2) * lhs.denominator * rhs.denominator
    );
}


private bool inClosedUnit(ref const Rational value)
{
    return
        value.numerator >= 0 &&
        value.numerator <= value.denominator;
}


private BigInt cross(
    BigInt ax,
    BigInt ay,
    BigInt bx,
    BigInt by
)
{
    return ax * by - ay * bx;
}


private BigInt cross(
    long ax,
    long ay,
    long bx,
    long by
)
{
    return cross(
        BigInt(ax),
        BigInt(ay),
        BigInt(bx),
        BigInt(by)
    );
}


/*
 * Shared integer fixture representation.
 *
 * This is not geometry logic; both candidate and oracle adapt from these
 * immutable coordinates independently.
 */
private struct FixtureRing
{
    Point2!int[] points;
}


private struct FixturePolygon
{
    FixtureRing[] rings;
}


private FixtureRing fixtureRing(Point2!int[] points...)
{
    return FixtureRing(points.dup);
}


private FixturePolygon fixturePolygon(FixtureRing[] rings...)
{
    return FixturePolygon(rings.dup);
}


private size_t fixtureEdgeCount(ref const FixturePolygon polygon)
{
    size_t result;

    foreach (ref const ring; polygon.rings)
        result += ring.points.length;

    return result;
}


/* ------------------------------------------------------------------------- */
/* Candidate path: geo-d exact breakpoints                                   */
/* ------------------------------------------------------------------------- */


private BigInt fixedUnsignedToBigInt(Fixed)(ref const Fixed value)
{
    BigInt result = 0;

    for (size_t i = value.limb.length; i != 0; --i)
    {
        result <<= 32;
        result += value.limb[i - 1];
    }

    return result;
}


private BigInt signedNumeratorToBigInt(Num)(ref const Num value)
{
    BigInt magnitude =
        fixedUnsignedToBigInt(
            value.magnitude
        );

    if (value.sign < 0)
        magnitude = -magnitude;

    return magnitude;
}


private BigInt denominatorToBigInt(Den)(ref const Den value)
{
    return fixedUnsignedToBigInt(value);
}


private Rational candidateEventParameter(
    Segment2!int query,
    ref const ExactOverlayPoint event
)
{
    enum size_t scaleBits = 1074;

    const BigInt denominator =
        denominatorToBigInt(
            event.denominator
        );

    const BigInt scale =
        BigInt(1) << scaleBits;

    if (query.a.x != query.b.x)
    {
        const BigInt eventX =
            signedNumeratorToBigInt(
                event.xNumerator
            );

        const BigInt aX =
            BigInt(query.a.x) *
            denominator *
            scale;

        const BigInt deltaX =
            BigInt(query.b.x - query.a.x) *
            denominator *
            scale;

        return Rational(
            eventX - aX,
            deltaX
        );
    }

    assert(query.a.y != query.b.y);

    const BigInt eventY =
        signedNumeratorToBigInt(
            event.yNumerator
        );

    const BigInt aY =
        BigInt(query.a.y) *
        denominator *
        scale;

    const BigInt deltaY =
        BigInt(query.b.y - query.a.y) *
        denominator *
        scale;

    return Rational(
        eventY - aY,
        deltaY
    );
}


private string candidatePartition(
    Segment2!int query,
    ref const FixturePolygon fixture,
    out size_t breakpointCount
)
{
    /*
     * Build transient geo-d views only for the candidate path.
     */
    auto ringStorage =
        new LinearRing2View!int[
            fixture.rings.length
        ];

    foreach (i, ref const ring; fixture.rings)
    {
        ringStorage[i] =
            LinearRing2View!int(
                ring.points
            );
    }

    const polygon =
        Polygon2View!int(
            ringStorage
        );

    if (query.a == query.b)
    {
        breakpointCount = 1;

        Rational zero = rational(0);

        return [
            code(
                classifyCandidateRationalPoint(
                    query,
                    polygon,
                    zero
                )
            )
        ];
    }

    const size_t n =
        fixtureEdgeCount(fixture);

    ExactOverlayPoint[] events =
        new ExactOverlayPoint[
            2 * n + 2
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
            ExactOverlayPoint[2] ignoredEdgeEvents;
            size_t ignoredCount;

            assert(
                appendSegmentPairNodingEvents(
                    query,
                    ring.segment(edgeIndex),
                    events[],
                    count,
                    ignoredEdgeEvents[],
                    ignoredCount
                )
            );
        }
    }

    count =
        sortUniqueExactEdgeEvents(
            query,
            events[0 .. count]
        );

    breakpointCount = count;

    assert(count <= 2 * n + 2);
    assert(count > 0);
    assert(count - 1 <= 2 * n + 1);

    Rational[] parameter =
        new Rational[count];

    foreach (i; 0 .. count)
    {
        parameter[i] =
            candidateEventParameter(
                query,
                events[i]
            );
    }

    char[] result;

    foreach (i; 0 .. parameter.length)
    {
        result ~=
            code(
                classifyCandidateRationalPoint(
                    query,
                    polygon,
                    parameter[i]
                )
            );

        if (i + 1 < parameter.length)
        {
            Rational middle =
                midpoint(
                    parameter[i],
                    parameter[i + 1]
                );

            result ~=
                code(
                    classifyCandidateRationalPoint(
                        query,
                        polygon,
                        middle
                    )
                );
        }
    }

    return cast(string) result;
}


/*
 * Candidate label bridge.
 *
 * This routine is intentionally separate from the oracle's fixture-based
 * point-in-polygon function below. It traverses geo-d Polygon2View edges.
 */
private void candidateQueryPoint(
    Segment2!int query,
    ref const Rational t,
    out BigInt xNumerator,
    out BigInt yNumerator,
    out BigInt denominator
)
{
    denominator = t.denominator;

    const BigInt oneMinus =
        t.denominator - t.numerator;

    xNumerator =
        BigInt(query.a.x) * oneMinus +
        BigInt(query.b.x) * t.numerator;

    yNumerator =
        BigInt(query.a.y) * oneMinus +
        BigInt(query.b.y) * t.numerator;
}


private int compareIntToRational(
    int value,
    ref const BigInt numerator,
    ref const BigInt denominator
)
{
    const BigInt scaled =
        BigInt(value) * denominator;

    if (scaled < numerator)
        return -1;

    if (scaled > numerator)
        return 1;

    return 0;
}


private BigInt candidateOrientation(
    Point2!int a,
    Point2!int b,
    ref const BigInt px,
    ref const BigInt py,
    ref const BigInt denominator
)
{
    return
        (BigInt(b.x) - BigInt(a.x)) *
            (py - BigInt(a.y) * denominator)
        -
        (BigInt(b.y) - BigInt(a.y)) *
            (px - BigInt(a.x) * denominator);
}


private bool candidatePointOnEdge(
    Point2!int a,
    Point2!int b,
    ref const BigInt px,
    ref const BigInt py,
    ref const BigInt denominator
)
{
    if (
        candidateOrientation(
            a,
            b,
            px,
            py,
            denominator
        ) != 0
    )
    {
        return false;
    }

    const int minX = a.x < b.x ? a.x : b.x;
    const int maxX = a.x > b.x ? a.x : b.x;
    const int minY = a.y < b.y ? a.y : b.y;
    const int maxY = a.y > b.y ? a.y : b.y;

    return
        compareIntToRational(minX, px, denominator) <= 0 &&
        compareIntToRational(maxX, px, denominator) >= 0 &&
        compareIntToRational(minY, py, denominator) <= 0 &&
        compareIntToRational(maxY, py, denominator) >= 0;
}


private Location classifyCandidateRationalPoint(
    Segment2!int query,
    scope Polygon2View!int polygon,
    ref const Rational t
)
{
    BigInt px;
    BigInt py;
    BigInt denominator;

    candidateQueryPoint(
        query,
        t,
        px,
        py,
        denominator
    );

    bool inside = false;

    foreach (ringIndex; 0 .. polygon.length)
    {
        const auto ring =
            polygon[ringIndex];

        foreach (edgeIndex; 0 .. ring.segmentCount)
        {
            const auto edge =
                ring.segment(edgeIndex);

            if (
                candidatePointOnEdge(
                    edge.a,
                    edge.b,
                    px,
                    py,
                    denominator
                )
            )
            {
                return Location.boundary;
            }

            const int aY =
                compareIntToRational(
                    edge.a.y,
                    py,
                    denominator
                );

            const int bY =
                compareIntToRational(
                    edge.b.y,
                    py,
                    denominator
                );

            const BigInt orientation =
                candidateOrientation(
                    edge.a,
                    edge.b,
                    px,
                    py,
                    denominator
                );

            if (
                aY <= 0 &&
                bY > 0 &&
                orientation > 0
            )
            {
                inside = !inside;
            }
            else if (
                bY <= 0 &&
                aY > 0 &&
                orientation < 0
            )
            {
                inside = !inside;
            }
        }
    }

    return
        inside
            ? Location.interior
            : Location.exterior;
}


/* ------------------------------------------------------------------------- */
/* Independent oracle path                                                   */
/* ------------------------------------------------------------------------- */


private Rational oracleQueryParameterForPoint(
    Segment2!int query,
    Point2!int point
)
{
    const long dx =
        cast(long) query.b.x -
        cast(long) query.a.x;

    const long dy =
        cast(long) query.b.y -
        cast(long) query.a.y;

    assert(dx != 0 || dy != 0);

    if (dx != 0)
    {
        return Rational(
            BigInt(point.x) - BigInt(query.a.x),
            BigInt(dx)
        );
    }

    return Rational(
        BigInt(point.y) - BigInt(query.a.y),
        BigInt(dy)
    );
}


private void oracleAppendBreakpoint(
    ref Rational[] values,
    Rational value
)
{
    if (inClosedUnit(value))
        values ~= value;
}


private void oracleAppendEdgeContacts(
    Segment2!int query,
    Point2!int edgeA,
    Point2!int edgeB,
    ref Rational[] breakpoint
)
{
    const long rx =
        cast(long) query.b.x -
        cast(long) query.a.x;

    const long ry =
        cast(long) query.b.y -
        cast(long) query.a.y;

    const long sx =
        cast(long) edgeB.x -
        cast(long) edgeA.x;

    const long sy =
        cast(long) edgeB.y -
        cast(long) edgeA.y;

    const long qpx =
        cast(long) edgeA.x -
        cast(long) query.a.x;

    const long qpy =
        cast(long) edgeA.y -
        cast(long) query.a.y;

    const BigInt denominator =
        cross(rx, ry, sx, sy);

    const BigInt collinear =
        cross(qpx, qpy, rx, ry);

    if (denominator == 0)
    {
        if (collinear != 0)
            return;

        oracleAppendBreakpoint(
            breakpoint,
            oracleQueryParameterForPoint(
                query,
                edgeA
            )
        );

        oracleAppendBreakpoint(
            breakpoint,
            oracleQueryParameterForPoint(
                query,
                edgeB
            )
        );

        return;
    }

    Rational t =
        Rational(
            cross(qpx, qpy, sx, sy),
            denominator
        );

    Rational u =
        Rational(
            cross(qpx, qpy, rx, ry),
            denominator
        );

    if (
        inClosedUnit(t) &&
        inClosedUnit(u)
    )
    {
        oracleAppendBreakpoint(
            breakpoint,
            t
        );
    }
}


private void oracleSortUnique(ref Rational[] value)
{
    foreach (i; 1 .. value.length)
    {
        Rational current =
            value[i];

        size_t j = i;

        while (
            j > 0 &&
            compareRational(
                current,
                value[j - 1]
            ) < 0
        )
        {
            value[j] =
                value[j - 1];

            --j;
        }

        value[j] = current;
    }

    if (value.length < 2)
        return;

    size_t write = 1;

    foreach (read; 1 .. value.length)
    {
        if (
            !rationalEqual(
                value[write - 1],
                value[read]
            )
        )
        {
            if (write != read)
                value[write] = value[read];

            ++write;
        }
    }

    value.length = write;
}


private void oracleQueryPoint(
    Segment2!int query,
    ref const Rational t,
    out BigInt px,
    out BigInt py,
    out BigInt denominator
)
{
    denominator = t.denominator;

    const BigInt left =
        t.denominator - t.numerator;

    px =
        BigInt(query.a.x) * left +
        BigInt(query.b.x) * t.numerator;

    py =
        BigInt(query.a.y) * left +
        BigInt(query.b.y) * t.numerator;
}


private BigInt oracleOrientation(
    Point2!int a,
    Point2!int b,
    ref const BigInt px,
    ref const BigInt py,
    ref const BigInt denominator
)
{
    const BigInt bax =
        BigInt(b.x) - BigInt(a.x);

    const BigInt bay =
        BigInt(b.y) - BigInt(a.y);

    const BigInt pax =
        px - BigInt(a.x) * denominator;

    const BigInt pay =
        py - BigInt(a.y) * denominator;

    return
        bax * pay -
        bay * pax;
}


private bool oraclePointOnEdge(
    Point2!int a,
    Point2!int b,
    ref const BigInt px,
    ref const BigInt py,
    ref const BigInt denominator
)
{
    if (
        oracleOrientation(
            a,
            b,
            px,
            py,
            denominator
        ) != 0
    )
    {
        return false;
    }

    const int minX = a.x < b.x ? a.x : b.x;
    const int maxX = a.x > b.x ? a.x : b.x;
    const int minY = a.y < b.y ? a.y : b.y;
    const int maxY = a.y > b.y ? a.y : b.y;

    return
        compareIntToRational(minX, px, denominator) <= 0 &&
        compareIntToRational(maxX, px, denominator) >= 0 &&
        compareIntToRational(minY, py, denominator) <= 0 &&
        compareIntToRational(maxY, py, denominator) >= 0;
}


private Location oracleClassifyAt(
    Segment2!int query,
    ref const FixturePolygon polygon,
    ref const Rational t
)
{
    BigInt px;
    BigInt py;
    BigInt denominator;

    oracleQueryPoint(
        query,
        t,
        px,
        py,
        denominator
    );

    bool inside = false;

    foreach (ref const ring; polygon.rings)
    {
        const size_t length =
            ring.points.length;

        if (length == 0)
            continue;

        foreach (i; 0 .. length)
        {
            const Point2!int a =
                ring.points[i];

            const Point2!int b =
                ring.points[
                    (i + 1) % length
                ];

            if (
                oraclePointOnEdge(
                    a,
                    b,
                    px,
                    py,
                    denominator
                )
            )
            {
                return Location.boundary;
            }

            const int aY =
                compareIntToRational(
                    a.y,
                    py,
                    denominator
                );

            const int bY =
                compareIntToRational(
                    b.y,
                    py,
                    denominator
                );

            const BigInt orientation =
                oracleOrientation(
                    a,
                    b,
                    px,
                    py,
                    denominator
                );

            if (
                aY <= 0 &&
                bY > 0 &&
                orientation > 0
            )
            {
                inside = !inside;
            }
            else if (
                bY <= 0 &&
                aY > 0 &&
                orientation < 0
            )
            {
                inside = !inside;
            }
        }
    }

    return
        inside
            ? Location.interior
            : Location.exterior;
}


private string oraclePartition(
    Segment2!int query,
    ref const FixturePolygon polygon,
    out size_t breakpointCount
)
{
    if (query.a == query.b)
    {
        breakpointCount = 1;

        Rational zero = rational(0);

        return [
            code(
                oracleClassifyAt(
                    query,
                    polygon,
                    zero
                )
            )
        ];
    }

    Rational[] breakpoint;

    breakpoint ~= rational(0);
    breakpoint ~= rational(1);

    foreach (ref const ring; polygon.rings)
    {
        const size_t length =
            ring.points.length;

        if (length == 0)
            continue;

        foreach (i; 0 .. length)
        {
            oracleAppendEdgeContacts(
                query,
                ring.points[i],
                ring.points[
                    (i + 1) % length
                ],
                breakpoint
            );
        }
    }

    oracleSortUnique(breakpoint);

    breakpointCount =
        breakpoint.length;

    const size_t n =
        fixtureEdgeCount(polygon);

    assert(
        breakpointCount <=
        2 * n + 2
    );

    assert(
        breakpointCount - 1 <=
        2 * n + 1
    );

    char[] result;

    foreach (i; 0 .. breakpoint.length)
    {
        result ~=
            code(
                oracleClassifyAt(
                    query,
                    polygon,
                    breakpoint[i]
                )
            );

        if (i + 1 < breakpoint.length)
        {
            Rational middle =
                midpoint(
                    breakpoint[i],
                    breakpoint[i + 1]
                );

            result ~=
                code(
                    oracleClassifyAt(
                        query,
                        polygon,
                        middle
                    )
                );
        }
    }

    return cast(string) result;
}


/* ------------------------------------------------------------------------- */
/* Differential matrix                                                       */
/* ------------------------------------------------------------------------- */


private struct Case
{
    string name;
    FixturePolygon polygon;
    int minCoordinate;
    int maxCoordinate;
}


private void runCase(
    ref const Case test,
    ref ulong checked
)
{
    foreach (ax; test.minCoordinate .. test.maxCoordinate + 1)
    foreach (ay; test.minCoordinate .. test.maxCoordinate + 1)
    foreach (bx; test.minCoordinate .. test.maxCoordinate + 1)
    foreach (by; test.minCoordinate .. test.maxCoordinate + 1)
    {
        const Segment2!int query =
            Segment2!int(
                Point2!int(ax, ay),
                Point2!int(bx, by)
            );

        size_t candidateBreakpoints;
        size_t oracleBreakpoints;

        const string candidate =
            candidatePartition(
                query,
                test.polygon,
                candidateBreakpoints
            );

        const string oracle =
            oraclePartition(
                query,
                test.polygon,
                oracleBreakpoints
            );

        if (
            candidate != oracle ||
            candidateBreakpoints != oracleBreakpoints
        )
        {
            import std.format : format;

            assert(
                false,
                format(
                    "%s mismatch query (%s,%s)->(%s,%s): "
                    ~ "candidate=%s oracle=%s "
                    ~ "candidateBreakpoints=%s oracleBreakpoints=%s",
                    test.name,
                    ax,
                    ay,
                    bx,
                    by,
                    candidate,
                    oracle,
                    candidateBreakpoints,
                    oracleBreakpoints
                )
            );
        }

        ++checked;
    }

    writeln(
        test.name,
        ": cumulative checked ",
        checked
    );
}


void main()
{
    alias P = Point2!int;

    Case[] cases = [
        Case(
            "square",
            fixturePolygon(
                fixtureRing(
                    P(0, 0),
                    P(6, 0),
                    P(6, 6),
                    P(0, 6)
                )
            ),
            -2,
            8
        ),

        Case(
            "square-reversed",
            fixturePolygon(
                fixtureRing(
                    P(0, 6),
                    P(6, 6),
                    P(6, 0),
                    P(0, 0)
                )
            ),
            -2,
            8
        ),

        Case(
            "concave-u",
            fixturePolygon(
                fixtureRing(
                    P(0, 0),
                    P(8, 0),
                    P(8, 8),
                    P(6, 8),
                    P(6, 3),
                    P(2, 3),
                    P(2, 8),
                    P(0, 8)
                )
            ),
            -1,
            9
        ),

        Case(
            "concave-l",
            fixturePolygon(
                fixtureRing(
                    P(0, 0),
                    P(7, 0),
                    P(7, 3),
                    P(3, 3),
                    P(3, 7),
                    P(0, 7)
                )
            ),
            -1,
            8
        ),

        Case(
            "with-hole",
            fixturePolygon(
                fixtureRing(
                    P(0, 0),
                    P(10, 0),
                    P(10, 10),
                    P(0, 10)
                ),
                fixtureRing(
                    P(3, 3),
                    P(7, 3),
                    P(7, 7),
                    P(3, 7)
                )
            ),
            -1,
            11
        ),

        Case(
            "with-hole-reversed",
            fixturePolygon(
                fixtureRing(
                    P(0, 10),
                    P(10, 10),
                    P(10, 0),
                    P(0, 0)
                ),
                fixtureRing(
                    P(3, 7),
                    P(7, 7),
                    P(7, 3),
                    P(3, 3)
                )
            ),
            -1,
            11
        ),

        Case(
            "redundant-collinear",
            fixturePolygon(
                fixtureRing(
                    P(0, 0),
                    P(3, 0),
                    P(6, 0),
                    P(6, 6),
                    P(0, 6)
                )
            ),
            -2,
            8
        )
    ];

    ulong checked;

    foreach (ref const test; cases)
        runCase(test, checked);

    writeln(
        "TOTAL ",
        checked
    );

    writeln(
        "SEGMENT POLYGON PARTITION DIFFERENTIAL PASS"
    );
}
