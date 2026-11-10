/// The live hospital's switch and cadence as anyone may read them (CONTRACTS 4.4 and 12, 1.4.2): a copy of those two
/// values alone in Shutter's own namespace, ^Shutter.Live("public") = {enabled, every_minutes, at}, at in epoch seconds.
/// The anonymous GET /health of the hardened public demo runs as UnknownUser with no roles: the web application lets it
/// read Shutter's database but not the hospital's, so Shutter.Setup.LiveStatus can't read the player's status there and
/// the sign-in page would never learn that the live hospital is on. The processes that may read and write both write the
/// copy whenever the values change: the hospital's player on every round, the live switch (Hospital.Setup.SetLive and the
/// hospital's install), and LiveStatus whenever it reads the hospital. A copy older than STALEPERIODS of the player's
/// period counts as unknown, so a player that has stopped never keeps a live hospital advertised.
Class Shutter.Util.LivePublic
{

/// How many of the player's periods (every_minutes) a copy stays good for. The player writes it every round, a few
/// seconds apart, so only a player that has stopped lets it grow this old.
Parameter STALEPERIODS = 3;

/// The player's period when a copy names none: Hospital.LivePlayer's EveryMinutes as shipped.
Parameter DEFAULTMINUTES = 7;

/// Writes the copy into Shutter's namespace ns ("" for this one): enabled, every_minutes when given, and the time. Never
/// throws: a process that may not write Shutter's database writes nothing. Returns whether it was written.
ClassMethod Write(ns As %String = "", enabled As %Boolean, everyMinutes As %String = "", now As %Integer = "") As %Boolean
{
    Try {
        Set text = ..CopyText(enabled, everyMinutes, $SELECT(now = "": ##class(Shutter.Util.Time).EpochSeconds(), 1: now))
        If (ns = "") || (ns = $CHAR(0)) || ($ZCONVERT(ns, "U") = $NAMESPACE) {
            Set ^Shutter.Live("public") = text
        } Else {
            Set ^|ns|Shutter.Live("public") = text
        }
        Return 1
    } Catch ex {
        Return 0
    }
    Quit 0
}

/// The copy's text for the given values: {"enabled", "every_minutes" (left out when not a whole number above 0), "at"}.
ClassMethod CopyText(enabled As %Boolean, everyMinutes As %String, at As %Integer) As %String
{
    Set o = {}
    Do o.%Set("enabled", ''enabled, "boolean")
    If (everyMinutes ? 1.N) && (+everyMinutes > 0) Do o.%Set("every_minutes", +everyMinutes, "number")
    Do o.%Set("at", +at, "number")
    Quit o.%ToJSON()
}

/// Writes the copy from a live status as LiveStatus read it ({enabled, every_minutes, ...}) when the copy in this
/// namespace says otherwise or is missing; a copy that already agrees keeps its time, so a reader never stands in for the
/// player's own rounds. Never throws. Returns whether it wrote.
ClassMethod Refresh(live As %DynamicObject) As %Boolean
{
    Try {
        Set enabled = ''live.%Get("enabled"), every = live.%Get("every_minutes")
        Set every = $SELECT((every ? 1.N) && (+every > 0): +every, 1: "")
        Set was = ##class(Shutter.Util.Json).Parse($GET(^Shutter.Live("public")), .sc)
        If $ISOBJECT(was) && was.%IsA("%DynamicObject") && was.%IsDefined("at") && (''was.%Get("enabled") = enabled) && ($SELECT(was.%IsDefined("every_minutes"): +was.%Get("every_minutes"), 1: "") = every) Return 0
        Return ..Write("", enabled, every)
    } Catch ex {
        Return 0
    }
    Quit 0
}

/// The anonymous health answer's live (CONTRACTS 12): enabled and every_minutes alone. From the status LiveStatus gave when
/// it read the hospital (read 1), else from the copy in this namespace; "" when neither says (no live key then).
ClassMethod Anonymous(live As %DynamicObject, read As %Boolean, now As %Integer = "") As %DynamicObject
{
    If 'read || '$ISOBJECT(live) Quit ..Read(now)
    Set l = {}
    Do l.%Set("enabled", ''live.%Get("enabled"), "boolean")
    If live.%IsDefined("every_minutes") Do l.%Set("every_minutes", +live.%Get("every_minutes"), "number")
    Quit l
}

/// The copy in this namespace as the anonymous health answer gives it, {enabled, every_minutes}, or "" when there is
/// none, it can't be read or parsed, or it is stale.
ClassMethod Read(now As %Integer = "") As %DynamicObject
{
    Set text = ""
    Try { Set text = $GET(^Shutter.Live("public")) } Catch ex { Set text = "" }
    Quit ..FromCopy(text, now)
}

/// The rule, on a copy's text at the epoch second now: {enabled, every_minutes} with nothing else, or "" for no copy, an
/// unreadable one, one with no time, or one older than STALEPERIODS times its period (every_minutes, else DEFAULTMINUTES).
ClassMethod FromCopy(text As %String, now As %Integer = "") As %DynamicObject
{
    If $ZSTRIP(text, "<>W") = "" Quit ""
    Set c = ##class(Shutter.Util.Json).Parse(text, .sc)
    If '$ISOBJECT(c) Quit ""
    If 'c.%IsA("%DynamicObject") || 'c.%IsDefined("at") Quit ""
    Set at = c.%Get("at")
    If at '? 1.N Quit ""
    If now = "" Set now = ##class(Shutter.Util.Time).EpochSeconds()
    Set every = c.%Get("every_minutes")
    Set every = $SELECT((every ? 1.N) && (+every > 0): +every, 1: "")
    If (now - at) > (..#STALEPERIODS * $SELECT(every = "": ..#DEFAULTMINUTES, 1: every) * 60) Quit ""
    Set l = {}
    Do l.%Set("enabled", ''c.%Get("enabled"), "boolean")
    If every '= "" Do l.%Set("every_minutes", every, "number")
    Quit l
}

}
