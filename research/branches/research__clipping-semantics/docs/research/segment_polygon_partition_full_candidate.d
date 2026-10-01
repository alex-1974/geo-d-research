module segment_polygon_partition_full_candidate;

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
 * Research-only full-cell candidate for #58.
 *
 * Production-like part:
 *   geo-d exact breakpoint generation and ordering.
 *
 * Verification-only bridge:
 *   decode exact breakpoints to arbitrary-precision rational query
 *   parameters, then classify cells with an exact BigInt PIP routine.
 *
 * This deliberately does not freeze a production ExactOverlayPoint PIP API.
 */


private enum Location : ubyte
{
    exterior,
    boundary,
    interior,
}


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


private Rational eventParameter(
    Segment2!int query,
    ref const ExactOverlayPoint event
)
{
    /*
     * ExactOverlayPoint coordinates are:
     *
     *     numerator / denominator * 2^-1074
     *
     * For integer query coordinates, represented x/y are therefore
     * integer * 2^1074 in this common scale.
     */
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


private size_t polygonEdgeCount(
    scope Polygon2View!int polygon
)
{
    size_t result;

    foreach (ringIndex; 0 .. polygon.length)
        result += polygon[ringIndex].segmentCount;

    return result;
}


private ExactOverlayPoint[] collectExactBreakpoints(
    Segment2!int query,
    scope Polygon2View!int polygon
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
            ExactOverlayPoint[2] edgeEvents;
            size_t edgeEventCount;

            assert(
                appendSegmentPairNodingEvents(
                    query,
                    ring.segment(edgeIndex),
                    events[],
                    count,
                    edgeEvents[],
                    edgeEventCount
                )
            );
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


private void queryPointNumerators(
    Segment2!int query,
    ref const Rational t,
    out BigInt xNumerator,
    out BigInt yNumerator,
    out BigInt denominator
)
{
    denominator =
        t.denominator;

    const BigInt oneMinus =
        t.denominator -
        t.numerator;

    xNumerator =
        BigInt(query.a.x) * oneMinus +
        BigInt(query.b.x) * t.numerator;

    yNumerator =
        BigInt(query.a.y) * oneMinus +
        BigInt(query.b.y) * t.numerator;
}


private int compareIntegerToRational(
    int value,
    ref const BigInt numerator,
    ref const BigInt denominator
)
{
    const BigInt scaled =
        BigInt(value) *
        denominator;

    if (scaled < numerator)
        return -1;

    if (scaled > numerator)
        return 1;

    return 0;
}


private BigInt orientationRationalPoint(
    Point2!int a,
    Point2!int b,
    ref const BigInt pxNumerator,
    ref const BigInt pyNumerator,
    ref const BigInt denominator
)
{
    const BigInt bax =
        BigInt(b.x) -
        BigInt(a.x);

    const BigInt bay =
        BigInt(b.y) -
        BigInt(a.y);

    const BigInt pax =
        pxNumerator -
        BigInt(a.x) *
        denominator;

    const BigInt pay =
        pyNumerator -
        BigInt(a.y) *
        denominator;

    return
        bax * pay -
        bay * pax;
}


private bool pointOnEdge(
    Point2!int a,
    Point2!int b,
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

    const int minX =
        a.x < b.x ? a.x : b.x;

    const int maxX =
        a.x > b.x ? a.x : b.x;

    const int minY =
        a.y < b.y ? a.y : b.y;

    const int maxY =
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
    scope Polygon2View!int polygon,
    ref const BigInt pxNumerator,
    ref const BigInt pyNumerator,
    ref const BigInt denominator
)
{
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
                pointOnEdge(
                    edge.a,
                    edge.b,
                    pxNumerator,
                    pyNumerator,
                    denominator
                )
            )
            {
                return Location.boundary;
            }

            const int aY =
                compareIntegerToRational(
                    edge.a.y,
                    pyNumerator,
                    denominator
                );

            const int bY =
                compareIntegerToRational(
                    edge.b.y,
                    pyNumerator,
                    denominator
                );

            const BigInt orient =
                orientationRationalPoint(
                    edge.a,
                    edge.b,
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
    Segment2!int query,
    scope Polygon2View!int polygon,
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


private string partitionCandidate(
    Segment2!int query,
    scope Polygon2View!int polygon,
    out size_t breakpointCount
)
{
    if (query.a == query.b)
    {
        breakpointCount = 1;

        Rational zero =
            Rational(
                BigInt(0),
                BigInt(1)
            );

        return [
            code(
                classifyAt(
                    query,
                    polygon,
                    zero
                )
            )
        ];
    }

    const auto events =
        collectExactBreakpoints(
            query,
            polygon
        );

    breakpointCount =
        events.length;

    Rational[] parameters =
        new Rational[
            events.length
        ];

    foreach (i; 0 .. events.length)
    {
        parameters[i] =
            eventParameter(
                query,
                events[i]
            );
    }

    char[] cells;

    foreach (i; 0 .. parameters.length)
    {
        cells ~=
            code(
                classifyAt(
                    query,
                    polygon,
                    parameters[i]
                )
            );

        if (i + 1 < parameters.length)
        {
            Rational middle =
                midpoint(
                    parameters[i],
                    parameters[i + 1]
                );

            cells ~=
                code(
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


private void expect(
    string name,
    Segment2!int query,
    scope Polygon2View!int polygon,
    string expected
)
{
    size_t breakpointCount;

    const string actual =
        partitionCandidate(
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

    const size_t n =
        polygonEdgeCount(polygon);

    assert(
        breakpointCount <=
        2 * n + 2
    );

    if (breakpointCount > 0)
    {
        assert(
            breakpointCount - 1 <=
            2 * n + 1
        );
    }
}


void main()
{
    alias P = Point2!int;
    alias S = Segment2!int;
    alias R = LinearRing2View!int;
    alias G = Polygon2View!int;

    P[4] squarePoints = [
        P(0, 0),
        P(10, 0),
        P(10, 10),
        P(0, 10)
    ];

    R[1] squareRings = [
        R(squarePoints[])
    ];

    const G square =
        G(squareRings[]);

    expect(
        "outside",
        S(P(-5, -2), P(-1, -2)),
        square,
        "EEE"
    );

    expect(
        "inside",
        S(P(2, 2), P(8, 8)),
        square,
        "III"
    );

    expect(
        "proper crossing",
        S(P(-5, 5), P(15, 5)),
        square,
        "EEBIBEE"
    );

    expect(
        "convex tangency",
        S(P(-5, 5), P(5, -5)),
        square,
        "EEBEE"
    );

    expect(
        "boundary endpoint to interior",
        S(P(0, 5), P(5, 5)),
        square,
        "BII"
    );

    expect(
        "boundary chord",
        S(P(0, 5), P(10, 5)),
        square,
        "BIB"
    );

    expect(
        "boundary only",
        S(P(0, 2), P(0, 8)),
        square,
        "BBB"
    );

    expect(
        "boundary overlap plus exterior",
        S(P(0, -5), P(0, 5)),
        square,
        "EEBBB"
    );

    expect(
        "degenerate exterior",
        S(P(-1, -1), P(-1, -1)),
        square,
        "E"
    );

    expect(
        "degenerate boundary",
        S(P(0, 5), P(0, 5)),
        square,
        "B"
    );

    expect(
        "degenerate interior",
        S(P(5, 5), P(5, 5)),
        square,
        "I"
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

    expect(
        "concave exterior chord",
        S(P(3, 5), P(7, 5)),
        concaveU,
        "BEB"
    );

    expect(
        "separated boundary overlaps",
        S(P(0, 10), P(10, 10)),
        concaveU,
        "BBBEBBB"
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

    expect(
        "hole crossing",
        S(P(2, 10), P(18, 10)),
        withHole,
        "IIBEBII"
    );

    expect(
        "wholly in hole",
        S(P(6, 10), P(14, 10)),
        withHole,
        "EEE"
    );

    expect(
        "full exterior-polygon-hole crossing",
        S(P(-2, 10), P(22, 10)),
        withHole,
        "EEBIBEBIBEE"
    );

    expect(
        "hole boundary overlap",
        S(P(5, 6), P(5, 14)),
        withHole,
        "BBB"
    );


    R[] noRings;

    const G empty =
        G(noRings);

    expect(
        "empty polygon",
        S(P(1, 2), P(3, 4)),
        empty,
        "EEE"
    );


    /*
     * Rational proper crossings.
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

        /*
         * Exact cell sequence is derived from geo-d rational breakpoints,
         * then classified without rounding.
         */
        expect(
            "rational proper crossings",
            S(P(-2, 1), P(9, 6)),
            rationalSquare,
            "EEBIBEE"
        );
    }


    /*
     * Reversal law: ordered cell sequence reverses with the query.
     */
    {
        size_t forwardCount;
        size_t reverseCount;

        const string forward =
            partitionCandidate(
                S(P(-5, 5), P(15, 5)),
                square,
                forwardCount
            );

        const string reverse =
            partitionCandidate(
                S(P(15, 5), P(-5, 5)),
                square,
                reverseCount
            );

        assert(
            forward.length ==
            reverse.length
        );

        foreach (i; 0 .. forward.length)
        {
            assert(
                forward[i] ==
                reverse[
                    reverse.length - 1 - i
                ]
            );
        }

        assert(
            forwardCount ==
            reverseCount
        );
    }


    writeln(
        "SEGMENT POLYGON FULL EXACT CELL CANDIDATE PASS"
    );
}
