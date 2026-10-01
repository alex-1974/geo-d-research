module segment_polygon_clip_public_differential;

import geo;

import std.bigint : BigInt;
import std.stdio : writeln;


/*
 * Independent public-surface verifier for geo-d #73.
 *
 * Production side:
 *     import geo; only
 *
 * Oracle side:
 *     independent BigInt rational segment/edge intersections,
 *     independent sort/dedup,
 *     independent exact rational even/odd point-in-polygon,
 *     independent retained-interval merge.
 *
 * No geo.internal module is imported.
 */


private enum OracleLocation : ubyte
{
    exterior,
    boundary,
    interior,
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


private bool inClosedUnit(ref const Rational value)
{
    return
        value.numerator >= 0 &&
        value.numerator <= value.denominator;
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


private BigInt cross(
    long ax,
    long ay,
    long bx,
    long by
)
{
    return
        BigInt(ax) * BigInt(by) -
        BigInt(ay) * BigInt(bx);
}


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


private Rational parameterForPoint(
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


private void appendBreakpoint(
    ref Rational[] values,
    Rational value
)
{
    if (inClosedUnit(value))
        values ~= value;
}


private void appendEdgeContacts(
    Segment2!int query,
    Point2!int edgeA,
    Point2!int edgeB,
    ref Rational[] breakpoints
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

        appendBreakpoint(
            breakpoints,
            parameterForPoint(query, edgeA)
        );

        appendBreakpoint(
            breakpoints,
            parameterForPoint(query, edgeB)
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

    if (inClosedUnit(t) && inClosedUnit(u))
        appendBreakpoint(breakpoints, t);
}


private void sortUnique(ref Rational[] values)
{
    foreach (i; 1 .. values.length)
    {
        Rational current = values[i];

        size_t j = i;

        while (
            j > 0 &&
            compareRational(
                current,
                values[j - 1]
            ) < 0
        )
        {
            values[j] = values[j - 1];
            --j;
        }

        values[j] = current;
    }

    if (values.length < 2)
        return;

    size_t write = 1;

    foreach (read; 1 .. values.length)
    {
        if (
            !rationalEqual(
                values[write - 1],
                values[read]
            )
        )
        {
            if (write != read)
                values[write] = values[read];

            ++write;
        }
    }

    values.length = write;
}


private void queryPoint(
    Segment2!int query,
    ref const Rational t,
    out BigInt px,
    out BigInt py,
    out BigInt denominator
)
{
    denominator = t.denominator;

    const BigInt left =
        t.denominator -
        t.numerator;

    px =
        BigInt(query.a.x) * left +
        BigInt(query.b.x) * t.numerator;

    py =
        BigInt(query.a.y) * left +
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


private BigInt orientation(
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


private bool pointOnEdge(
    Point2!int a,
    Point2!int b,
    ref const BigInt px,
    ref const BigInt py,
    ref const BigInt denominator
)
{
    if (
        orientation(
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
        compareIntToRational(
            minX,
            px,
            denominator
        ) <= 0 &&
        compareIntToRational(
            maxX,
            px,
            denominator
        ) >= 0 &&
        compareIntToRational(
            minY,
            py,
            denominator
        ) <= 0 &&
        compareIntToRational(
            maxY,
            py,
            denominator
        ) >= 0;
}


private OracleLocation classifyAt(
    Segment2!int query,
    ref const FixturePolygon polygon,
    ref const Rational t
)
{
    BigInt px;
    BigInt py;
    BigInt denominator;

    queryPoint(
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
            const auto a =
                ring.points[i];

            const auto b =
                ring.points[
                    (i + 1) % length
                ];

            if (
                pointOnEdge(
                    a,
                    b,
                    px,
                    py,
                    denominator
                )
            )
            {
                return OracleLocation.boundary;
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

            const BigInt side =
                orientation(
                    a,
                    b,
                    px,
                    py,
                    denominator
                );

            if (
                aY <= 0 &&
                bY > 0 &&
                side > 0
            )
            {
                inside = !inside;
            }
            else if (
                bY <= 0 &&
                aY > 0 &&
                side < 0
            )
            {
                inside = !inside;
            }
        }
    }

    return
        inside
            ? OracleLocation.interior
            : OracleLocation.exterior;
}


private Rational[] oracleBreakpoints(
    Segment2!int query,
    ref const FixturePolygon polygon
)
{
    Rational[] result;

    result ~= rational(0);
    result ~= rational(1);

    foreach (ref const ring; polygon.rings)
    {
        const size_t length =
            ring.points.length;

        foreach (i; 0 .. length)
        {
            appendEdgeContacts(
                query,
                ring.points[i],
                ring.points[
                    (i + 1) % length
                ],
                result
            );
        }
    }

    sortUnique(result);

    return result;
}


private struct ExpectedComponent
{
    Rational start;
    Rational end;
}


private ExpectedComponent[] oracleComponents(
    Segment2!int query,
    ref const FixturePolygon polygon
)
{
    if (query.a == query.b)
        return null;

    auto breakpoints =
        oracleBreakpoints(
            query,
            polygon
        );

    if (breakpoints.length < 2)
        return null;

    bool[] retained =
        new bool[
            breakpoints.length - 1
        ];

    foreach (i; 0 .. retained.length)
    {
        Rational middle =
            midpoint(
                breakpoints[i],
                breakpoints[i + 1]
            );

        const location =
            classifyAt(
                query,
                polygon,
                middle
            );

        retained[i] =
            location !=
            OracleLocation.exterior;
    }

    ExpectedComponent[] result;

    bool inRun = false;
    size_t runStart;

    foreach (i; 0 .. retained.length + 1)
    {
        const bool keep =
            i < retained.length
                ? retained[i]
                : false;

        if (keep && !inRun)
        {
            inRun = true;
            runStart = i;
            continue;
        }

        if (keep || !inRun)
            continue;

        result ~=
            ExpectedComponent(
                breakpoints[runStart],
                breakpoints[i]
            );

        inRun = false;
    }

    return result;
}


/*
 * The exhaustive grid uses only small integer fixture coordinates. Oracle
 * rational numerators/denominators therefore fit easily in long.
 *
 * Numerically adversarial large-coordinate construction is verified separately
 * by status, not through this conversion.
 */
private double smallRationalToDouble(
    ref const BigInt numerator,
    ref const BigInt denominator
)
{
    const long n =
        cast(long) numerator;

    const long d =
        cast(long) denominator;

    assert(d != 0);

    return
        cast(double) n /
        cast(double) d;
}


private Point2!double expectedPoint(
    Segment2!int query,
    ref const Rational t
)
{
    const BigInt left =
        t.denominator -
        t.numerator;

    const BigInt xNumerator =
        BigInt(query.a.x) * left +
        BigInt(query.b.x) * t.numerator;

    const BigInt yNumerator =
        BigInt(query.a.y) * left +
        BigInt(query.b.y) * t.numerator;

    return
        Point2!double(
            smallRationalToDouble(
                xNumerator,
                t.denominator
            ),
            smallRationalToDouble(
                yNumerator,
                t.denominator
            )
        );
}


private void buildPublicPolygon(
    ref const FixturePolygon fixture,
    ref LinearRing2View!int[] ringViews,
    out Polygon2View!int polygon
)
{
    ringViews =
        new LinearRing2View!int[
            fixture.rings.length
        ];

    foreach (i, ref const ring; fixture.rings)
    {
        ringViews[i] =
            LinearRing2View!int(
                ring.points
            );
    }

    polygon =
        Polygon2View!int(
            ringViews
        );
}


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
    LinearRing2View!int[] ringViews;
    Polygon2View!int polygon;

    buildPublicPolygon(
        test.polygon,
        ringViews,
        polygon
    );

    assert(
        validatePolygon(polygon).valid
    );

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

        const expected =
            oracleComponents(
                query,
                test.polygon
            );

        const actual =
            clipSegmentToPolygon(
                query,
                polygon
            );

        assert(actual.succeeded);
        assert(actual.length == expected.length);

        foreach (i; 0 .. expected.length)
        {
            const Point2!double start =
                expectedPoint(
                    query,
                    expected[i].start
                );

            const Point2!double end =
                expectedPoint(
                    query,
                    expected[i].end
                );

            assert(
                actual[i] ==
                Segment2!double(
                    start,
                    end
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


private void verifyConstructionFailures()
{
    {
        alias P = Point2!long;
        alias R = LinearRing2View!long;
        alias G = Polygon2View!long;
        alias S = Segment2!long;

        enum long x0 =
            long.max - 1;

        enum long x1 =
            long.max;

        P[4] points = [
            P(x0, 0),
            P(x1, 0),
            P(x1, 10),
            P(x0, 10),
        ];

        R[1] rings = [
            R(points[])
        ];

        const G polygon =
            G(rings[]);

        assert(
            validatePolygon(polygon).valid
        );

        const result =
            clipSegmentToPolygon(
                S(P(x0, 5), P(x1, 5)),
                polygon
            );

        assert(!result.succeeded);

        assert(
            result.status ==
            SegmentPolygonClipStatus
                .unrepresentableConstruction
        );
    }


    {
        alias P = Point2!long;
        alias R = LinearRing2View!long;
        alias G = Polygon2View!long;
        alias S = Segment2!long;

        enum long base =
            9_007_199_254_740_992L;

        P[4] outerPoints = [
            P(base - 2, 0),
            P(base + 4, 0),
            P(base + 4, 10),
            P(base - 2, 10),
        ];

        P[4] holePoints = [
            P(base, 2),
            P(base + 1, 2),
            P(base + 1, 8),
            P(base, 8),
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

        const result =
            clipSegmentToPolygon(
                S(
                    P(base - 2, 5),
                    P(base + 4, 5)
                ),
                polygon
            );

        assert(!result.succeeded);

        assert(
            result.status ==
            SegmentPolygonClipStatus
                .unrepresentableConstruction
        );
    }
}


void main()
{
    static assert(
        !__traits(
            compiles,
            clipSegmentToPolygon(
                Segment2!real.init,
                Polygon2View!real.init
            )
        )
    );

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

    assert(checked == 125_686);

    verifyConstructionFailures();

    writeln("TOTAL ", checked);
    writeln(
        "SEGMENT POLYGON PUBLIC CLIP DIFFERENTIAL PASS"
    );
}
