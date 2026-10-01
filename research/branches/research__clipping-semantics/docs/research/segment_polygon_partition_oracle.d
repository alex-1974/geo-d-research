module segment_polygon_partition_oracle;

import std.bigint : BigInt;
import std.stdio : writeln;


/*
 * Independent integer/rational oracle for #58.
 *
 * Deliberately does not import geo.intersection, geo.internal.*, the
 * production segment/polygon relationship classifier, or any clipping code.
 *
 * The first oracle stage uses integer input coordinates and arbitrary-
 * precision rational query parameters. This is sufficient to establish the
 * exact ordered-cell semantics independently of the production arithmetic.
 */


private enum Location : ubyte
{
    exterior,
    boundary,
    interior,
}


private struct IPoint
{
    long x;
    long y;
}


private struct ISegment
{
    IPoint a;
    IPoint b;
}


private struct Ring
{
    IPoint[] point;
}


private struct Polygon
{
    Ring[] ring;
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


private bool rationalInClosedUnit(
    ref const Rational value
)
{
    return
        value.numerator >= 0 &&
        value.numerator <= value.denominator;
}


private Rational queryParameterForPoint(
    ISegment query,
    IPoint point
)
{
    const long dx =
        query.b.x - query.a.x;

    const long dy =
        query.b.y - query.a.y;

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
    if (!rationalInClosedUnit(value))
        return;

    values ~= value;
}


private void appendEdgeContacts(
    ISegment query,
    ISegment edge,
    ref Rational[] breakpoints
)
{
    const long rx =
        query.b.x - query.a.x;

    const long ry =
        query.b.y - query.a.y;

    const long sx =
        edge.b.x - edge.a.x;

    const long sy =
        edge.b.y - edge.a.y;

    const long qpx =
        edge.a.x - query.a.x;

    const long qpy =
        edge.a.y - query.a.y;

    const BigInt denominator =
        cross(rx, ry, sx, sy);

    const BigInt queryOffsetCross =
        cross(qpx, qpy, rx, ry);

    if (denominator == 0)
    {
        if (queryOffsetCross != 0)
            return;

        /*
         * Collinear intersection. Each connected overlap endpoint is one of
         * the represented endpoints, so adding both edge endpoints and then
         * clipping to [0,1] is sufficient together with query endpoints.
         */
        appendBreakpoint(
            breakpoints,
            queryParameterForPoint(query, edge.a)
        );

        appendBreakpoint(
            breakpoints,
            queryParameterForPoint(query, edge.b)
        );

        return;
    }

    const BigInt tNumerator =
        cross(qpx, qpy, sx, sy);

    const BigInt uNumerator =
        cross(qpx, qpy, rx, ry);

    const Rational t =
        Rational(tNumerator, denominator);

    const Rational u =
        Rational(uNumerator, denominator);

    if (
        rationalInClosedUnit(t) &&
        rationalInClosedUnit(u)
    )
    {
        appendBreakpoint(
            breakpoints,
            t
        );
    }
}


private void sortUnique(
    ref Rational[] values
)
{
    /*
     * Deliberately simple insertion sort. Oracle independence and exactness
     * matter more than asymptotic performance for the bounded research grids.
     */
    foreach (i; 1 .. values.length)
    {
        Rational value =
            values[i];

        size_t j = i;

        while (
            j > 0 &&
            compareRational(
                value,
                values[j - 1]
            ) < 0
        )
        {
            values[j] =
                values[j - 1];

            --j;
        }

        values[j] = value;
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


private void queryPointNumerators(
    ISegment query,
    ref const Rational t,
    out BigInt xNumerator,
    out BigInt yNumerator,
    out BigInt denominator
)
{
    denominator =
        t.denominator;

    const BigInt oneMinusNumerator =
        t.denominator - t.numerator;

    xNumerator =
        BigInt(query.a.x) * oneMinusNumerator +
        BigInt(query.b.x) * t.numerator;

    yNumerator =
        BigInt(query.a.y) * oneMinusNumerator +
        BigInt(query.b.y) * t.numerator;
}


private int compareIntegerToRational(
    long integer,
    ref const BigInt numerator,
    ref const BigInt denominator
)
{
    const BigInt scaled =
        BigInt(integer) * denominator;

    if (scaled < numerator)
        return -1;

    if (scaled > numerator)
        return 1;

    return 0;
}


private BigInt orientationRationalPoint(
    IPoint a,
    IPoint b,
    ref const BigInt pxNumerator,
    ref const BigInt pyNumerator,
    ref const BigInt denominator
)
{
    const BigInt bax =
        BigInt(b.x) - BigInt(a.x);

    const BigInt bay =
        BigInt(b.y) - BigInt(a.y);

    const BigInt pax =
        pxNumerator -
        BigInt(a.x) * denominator;

    const BigInt pay =
        pyNumerator -
        BigInt(a.y) * denominator;

    return
        bax * pay -
        bay * pax;
}


private bool pointOnEdge(
    IPoint a,
    IPoint b,
    ref const BigInt pxNumerator,
    ref const BigInt pyNumerator,
    ref const BigInt denominator
)
{
    if (
        orientationRationalPoint(
            a,
            b,
            pxNumerator,
            pyNumerator,
            denominator
        ) != 0
    )
    {
        return false;
    }

    const long minX =
        a.x < b.x ? a.x : b.x;

    const long maxX =
        a.x > b.x ? a.x : b.x;

    const long minY =
        a.y < b.y ? a.y : b.y;

    const long maxY =
        a.y > b.y ? a.y : b.y;

    return
        compareIntegerToRational(
            minX,
            pxNumerator,
            denominator
        ) <= 0 &&
        compareIntegerToRational(
            maxX,
            pxNumerator,
            denominator
        ) >= 0 &&
        compareIntegerToRational(
            minY,
            pyNumerator,
            denominator
        ) <= 0 &&
        compareIntegerToRational(
            maxY,
            pyNumerator,
            denominator
        ) >= 0;
}


private Location classifyRationalPoint(
    ref const Polygon polygon,
    ref const BigInt pxNumerator,
    ref const BigInt pyNumerator,
    ref const BigInt denominator
)
{
    bool inside = false;

    foreach (ref const ring; polygon.ring)
    {
        if (ring.point.length < 2)
            continue;

        foreach (i; 0 .. ring.point.length)
        {
            const IPoint a =
                ring.point[i];

            const IPoint b =
                ring.point[
                    (i + 1) % ring.point.length
                ];

            if (
                pointOnEdge(
                    a,
                    b,
                    pxNumerator,
                    pyNumerator,
                    denominator
                )
            )
            {
                return Location.boundary;
            }

            /*
             * Exact half-open ray crossing.
             *
             * Upward edge:
             *     a.y <= p.y < b.y and p is left of a->b
             *
             * Downward edge:
             *     b.y <= p.y < a.y and p is right of a->b
             */
            const int aY =
                compareIntegerToRational(
                    a.y,
                    pyNumerator,
                    denominator
                );

            const int bY =
                compareIntegerToRational(
                    b.y,
                    pyNumerator,
                    denominator
                );

            const BigInt orient =
                orientationRationalPoint(
                    a,
                    b,
                    pxNumerator,
                    pyNumerator,
                    denominator
                );

            if (
                aY <= 0 &&
                bY > 0 &&
                orient > 0
            )
            {
                inside = !inside;
            }
            else if (
                bY <= 0 &&
                aY > 0 &&
                orient < 0
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


private Location classifyAt(
    ISegment query,
    ref const Polygon polygon,
    ref const Rational t
)
{
    BigInt xNumerator;
    BigInt yNumerator;
    BigInt denominator;

    queryPointNumerators(
        query,
        t,
        xNumerator,
        yNumerator,
        denominator
    );

    return classifyRationalPoint(
        polygon,
        xNumerator,
        yNumerator,
        denominator
    );
}


private char locationCode(Location location)
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


private string partitionOracle(
    ISegment query,
    ref const Polygon polygon,
    out size_t breakpointCount
)
{
    if (
        query.a.x == query.b.x &&
        query.a.y == query.b.y
    )
    {
        breakpointCount = 1;

        Rational zero =
            rational(0);

        return [
            locationCode(
                classifyAt(
                    query,
                    polygon,
                    zero
                )
            )
        ];
    }

    Rational[] breakpoints;

    breakpoints ~= rational(0);
    breakpoints ~= rational(1);

    foreach (ref const ring; polygon.ring)
    {
        if (ring.point.length < 2)
            continue;

        foreach (i; 0 .. ring.point.length)
        {
            appendEdgeContacts(
                query,
                ISegment(
                    ring.point[i],
                    ring.point[
                        (i + 1) %
                        ring.point.length
                    ]
                ),
                breakpoints
            );
        }
    }

    sortUnique(breakpoints);

    breakpointCount =
        breakpoints.length;

    char[] cells;

    foreach (i; 0 .. breakpoints.length)
    {
        cells ~=
            locationCode(
                classifyAt(
                    query,
                    polygon,
                    breakpoints[i]
                )
            );

        if (i + 1 < breakpoints.length)
        {
            Rational middle =
                midpoint(
                    breakpoints[i],
                    breakpoints[i + 1]
                );

            cells ~=
                locationCode(
                    classifyAt(
                        query,
                        polygon,
                        middle
                    )
                );
        }
    }

    return cast(string) cells;
}


private Polygon polygon(Ring[] rings...)
{
    return Polygon(rings.dup);
}


private Ring ring(IPoint[] points...)
{
    return Ring(points.dup);
}


private void expect(
    string name,
    ISegment query,
    ref const Polygon polygon,
    string expected,
    size_t polygonEdgeCount
)
{
    size_t breakpointCount;

    const string actual =
        partitionOracle(
            query,
            polygon,
            breakpointCount
        );

    if (actual != expected)
    {
        import std.format : format;

        assert(
            false,
            format(
                "%s: expected %s, got %s",
                name,
                expected,
                actual
            )
        );
    }

    /*
     * Research bound:
     *
     *     breakpoints <= 2n + 2
     *     intervals   <= 2n + 1
     */
    assert(
        breakpointCount <=
        2 * polygonEdgeCount + 2
    );

    if (breakpointCount > 0)
    {
        assert(
            breakpointCount - 1 <=
            2 * polygonEdgeCount + 1
        );
    }
}


void main()
{
    const Polygon square =
        polygon(
            ring(
                IPoint(0, 0),
                IPoint(10, 0),
                IPoint(10, 10),
                IPoint(0, 10)
            )
        );

    expect(
        "outside",
        ISegment(
            IPoint(-5, -2),
            IPoint(-1, -2)
        ),
        square,
        "EEE",
        4
    );

    expect(
        "inside",
        ISegment(
            IPoint(2, 2),
            IPoint(8, 8)
        ),
        square,
        "III",
        4
    );

    expect(
        "proper crossing",
        ISegment(
            IPoint(-5, 5),
            IPoint(15, 5)
        ),
        square,
        "EEBIBEE",
        4
    );

    expect(
        "convex tangency",
        ISegment(
            IPoint(-5, 5),
            IPoint(5, -5)
        ),
        square,
        "EEBEE",
        4
    );

    expect(
        "boundary endpoint to interior",
        ISegment(
            IPoint(0, 5),
            IPoint(5, 5)
        ),
        square,
        "BII",
        4
    );

    expect(
        "boundary chord",
        ISegment(
            IPoint(0, 5),
            IPoint(10, 5)
        ),
        square,
        "BIB",
        4
    );

    expect(
        "boundary only",
        ISegment(
            IPoint(0, 2),
            IPoint(0, 8)
        ),
        square,
        "BBB",
        4
    );

    expect(
        "boundary overlap plus exterior",
        ISegment(
            IPoint(0, -5),
            IPoint(0, 5)
        ),
        square,
        "EEBBB",
        4
    );

    expect(
        "degenerate exterior",
        ISegment(
            IPoint(-1, -1),
            IPoint(-1, -1)
        ),
        square,
        "E",
        4
    );

    expect(
        "degenerate boundary",
        ISegment(
            IPoint(0, 5),
            IPoint(0, 5)
        ),
        square,
        "B",
        4
    );

    expect(
        "degenerate interior",
        ISegment(
            IPoint(5, 5),
            IPoint(5, 5)
        ),
        square,
        "I",
        4
    );


    const Polygon concaveU =
        polygon(
            ring(
                IPoint(0, 0),
                IPoint(10, 0),
                IPoint(10, 10),
                IPoint(7, 10),
                IPoint(7, 3),
                IPoint(3, 3),
                IPoint(3, 10),
                IPoint(0, 10)
            )
        );

    expect(
        "concave exterior chord",
        ISegment(
            IPoint(3, 5),
            IPoint(7, 5)
        ),
        concaveU,
        "BEB",
        8
    );

    expect(
        "separated boundary overlaps",
        ISegment(
            IPoint(0, 10),
            IPoint(10, 10)
        ),
        concaveU,
        "BBBEBBB",
        8
    );


    const Polygon withHole =
        polygon(
            ring(
                IPoint(0, 0),
                IPoint(20, 0),
                IPoint(20, 20),
                IPoint(0, 20)
            ),
            ring(
                IPoint(5, 5),
                IPoint(15, 5),
                IPoint(15, 15),
                IPoint(5, 15)
            )
        );

    expect(
        "hole crossing",
        ISegment(
            IPoint(2, 10),
            IPoint(18, 10)
        ),
        withHole,
        "IIBEBII",
        8
    );

    expect(
        "wholly in hole",
        ISegment(
            IPoint(6, 10),
            IPoint(14, 10)
        ),
        withHole,
        "EEE",
        8
    );

    expect(
        "full exterior-polygon-hole crossing",
        ISegment(
            IPoint(-2, 10),
            IPoint(22, 10)
        ),
        withHole,
        "EEBIBEBIBEE",
        8
    );

    expect(
        "hole boundary overlap",
        ISegment(
            IPoint(5, 6),
            IPoint(5, 14)
        ),
        withHole,
        "BBB",
        8
    );


    const Polygon empty =
        Polygon.init;

    expect(
        "empty polygon",
        ISegment(
            IPoint(1, 2),
            IPoint(3, 4)
        ),
        empty,
        "EEE",
        0
    );


    /*
     * Reversal law: reversing the query reverses the ordered cell sequence.
     */
    {
        size_t forwardCount;
        size_t reverseCount;

        const string forward =
            partitionOracle(
                ISegment(
                    IPoint(-5, 5),
                    IPoint(15, 5)
                ),
                square,
                forwardCount
            );

        const string reverse =
            partitionOracle(
                ISegment(
                    IPoint(15, 5),
                    IPoint(-5, 5)
                ),
                square,
                reverseCount
            );

        char[] expectedReverse =
            forward.dup;

        size_t left = 0;
        size_t right = expectedReverse.length;

        while (left < right)
        {
            --right;

            if (left >= right)
                break;

            const char temporary =
                expectedReverse[left];

            expectedReverse[left] =
                expectedReverse[right];

            expectedReverse[right] =
                temporary;

            ++left;
        }

        assert(
            reverse ==
            cast(string) expectedReverse
        );

        assert(
            forwardCount ==
            reverseCount
        );
    }


    writeln(
        "SEGMENT POLYGON PARTITION BIGINT ORACLE PASS"
    );
}