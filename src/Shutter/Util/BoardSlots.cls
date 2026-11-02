/// How many boards convened in the current minute (CONTRACTS 6.6, v1.35): the Case Workflow asks before it convenes one and,
/// when the minute's cap is reached, defers the case for a minute instead of paying for another run at once. A storm of
/// failures then costs the cap a minute, not one board per message, and no case is lost: each waits its turn. The count is a
/// global node per minute (^Shutter.Board("convened", yyyymmddhhmm in UTC)); the nodes of earlier minutes are dropped when a
/// new minute's slot is taken.
Class Shutter.Util.BoardSlots
{

/// The current minute's key, UTC.
ClassMethod MinuteKey(now As %String = "") As %String
{
    If now = "" Set now = ##class(Shutter.Util.Time).NowUTC()
    Quit $TRANSLATE($EXTRACT(now, 1, 16), "-T:", "")
}

/// Boards convened in the minute.
ClassMethod Count(minute As %String = "") As %Integer
{
    If minute = "" Set minute = ..MinuteKey()
    Quit +$GET(^Shutter.Board("convened", minute))
}

/// Whether the minute's cap is reached: cap boards (0 means no cap) already convened this minute.
ClassMethod Full(cap As %Integer, minute As %String = "") As %Boolean
{
    If +cap <= 0 Quit 0
    Quit ..Count(minute) >= +cap
}

/// One more board this minute; the nodes of earlier minutes are dropped. Returns the new count.
ClassMethod Take(minute As %String = "") As %Integer
{
    If minute = "" Set minute = ..MinuteKey()
    Set n = $INCREMENT(^Shutter.Board("convened", minute))
    Set k = ""
    For {
        Set k = $ORDER(^Shutter.Board("convened", k))
        Quit:((k = "") || (k >= minute))
        Kill ^Shutter.Board("convened", k)
    }
    Quit n
}

}
