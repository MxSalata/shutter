/// Time helpers. Every timestamp Interlock stores or sends is ISO 8601 in UTC with a trailing Z,
/// for example 2026-10-15T09:20:00Z, so values compare as strings.
Class Interlock.Util.Time Extends %RegisteredObject
{

/// The current time, UTC, to the second.
ClassMethod NowUTC() As %String
{
    Set ts = $ZTIMESTAMP
    Quit $ZDATE(ts, 3) _ "T" _ $ZTIME($PIECE(ts, ",", 2) \ 1, 1) _ "Z"
}

/// The current time, UTC, with milliseconds.
ClassMethod NowUTCms() As %String
{
    Set ts = $ZTIMESTAMP
    Set secs = $PIECE(ts, ",", 2)
    Set ms = $JUSTIFY((secs - (secs \ 1)) * 1000 \ 1, 3)
    Set ms = $TRANSLATE(ms, " ", "0")
    Quit $ZDATE(ts, 3) _ "T" _ $ZTIME(secs \ 1, 1) _ "." _ ms _ "Z"
}

/// An ISO UTC time a number of seconds from now (negative values go back).
ClassMethod FromNow(seconds As %Integer) As %String
{
    Set ts = $ZTIMESTAMP
    Set h = $ZDATETIMEH($ZDATETIME(ts, 3, 1), 3, 1)
    Set total = ($PIECE(h, ",", 1) * 86400) + ($PIECE(h, ",", 2) \ 1) + seconds
    Set days = total \ 86400, secs = total # 86400
    Quit $ZDATE(days, 3) _ "T" _ $ZTIME(secs, 1) _ "Z"
}

/// An HL7 timestamp (YYYYMMDD[HHMM[SS[.ssss]]][+/-ZZZZ]) as ISO 8601 UTC. Without an offset the
/// value is taken as UTC, which is how the fixtures are written. Returns "" for an empty input.
ClassMethod FromHL7(ts As %String) As %String
{
    Set ts = $ZSTRIP(ts, "<>W")
    If ts = "" Quit ""
    Set offset = ""
    If ts [ "+" { Set offset = "+" _ $PIECE(ts, "+", 2), ts = $PIECE(ts, "+", 1) }
    ElseIf ($LENGTH(ts) > 8) && (ts [ "-") { Set offset = "-" _ $PIECE(ts, "-", 2), ts = $PIECE(ts, "-", 1) }
    Set ts = $PIECE(ts, ".", 1)
    Set y = $EXTRACT(ts, 1, 4), mo = $EXTRACT(ts, 5, 6), d = $EXTRACT(ts, 7, 8)
    Set hh = $EXTRACT(ts, 9, 10), mi = $EXTRACT(ts, 11, 12), ss = $EXTRACT(ts, 13, 14)
    If hh = "" Set hh = "00"
    If mi = "" Set mi = "00"
    If ss = "" Set ss = "00"
    Set iso = y _ "-" _ mo _ "-" _ d _ "T" _ hh _ ":" _ mi _ ":" _ ss
    If offset = "" Quit iso _ "Z"
    // Apply the offset so the result is UTC.
    Set sign = $EXTRACT(offset, 1), oh = +$EXTRACT(offset, 2, 3), om = +$EXTRACT(offset, 4, 5)
    Set shift = (oh * 3600) + (om * 60)
    Set h = $ZDATETIMEH(iso, 3, 1)
    Set total = ($PIECE(h, ",", 1) * 86400) + $PIECE(h, ",", 2)
    Set total = $SELECT(sign = "+": total - shift, 1: total + shift)
    Quit $ZDATE(total \ 86400, 3) _ "T" _ $ZTIME(total # 86400, 1) _ "Z"
}

/// Seconds between two ISO UTC timestamps (b minus a). Returns "" when either is empty.
ClassMethod SecondsBetween(a As %String, b As %String) As %Integer
{
    If (a = "") || (b = "") Quit ""
    Set ha = $ZDATETIMEH($TRANSLATE($PIECE(a, "Z", 1), "T", " "), 3, 1)
    Set hb = $ZDATETIMEH($TRANSLATE($PIECE(b, "Z", 1), "T", " "), 3, 1)
    Quit (($PIECE(hb, ",", 1) - $PIECE(ha, ",", 1)) * 86400) + ($PIECE(hb, ",", 2) \ 1 - $PIECE(ha, ",", 2) \ 1)
}

}
