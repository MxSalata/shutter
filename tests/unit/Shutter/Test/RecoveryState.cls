/// For a test that needs Shutter recovery on, off or stopped (CONTRACTS 18): what the stored profile and the control row said
/// before it, and putting them back after. The mode is written straight to the stored profile's text, as a test's receiver
/// is, so it moves no generation; a stop goes through Shutter.Util.RecoveryControl.Stop, as a person's does.
Class Shutter.Test.RecoveryState Extends %RegisteredObject
{

/// What to put back: whether a profile was stored, its text, and the stop's fields.
ClassMethod Keep() As %List
{
    Do ##class(Shutter.Util.RecoveryControl).Ensure()
    Set c = ##class(Shutter.Util.RecoveryControl).Control()
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    Quit $LISTBUILD($ISOBJECT(row), $SELECT($ISOBJECT(row): row.Json, 1: ""), c.StopLatched, c.StoppedAt, c.StoppedBy, c.StopReason)
}

/// Puts back what Keep read.
ClassMethod Put(kept As %List)
{
    Quit:$LISTLENGTH($GET(kept))<6
    Set c = ##class(Shutter.Util.RecoveryControl).Control()
    Set c.StopLatched = $LIST(kept, 3), c.StoppedAt = $LIST(kept, 4), c.StoppedBy = $LIST(kept, 5), c.StopReason = $LIST(kept, 6)
    Do c.%Save()
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    If $LIST(kept, 1) {
        If $ISOBJECT(row) Set row.Json = $LIST(kept, 2) Do row.%Save()
    } ElseIf $ISOBJECT(row) {
        Do ##class(Shutter.Store.SiteProfile).%DeleteId(row.%Id())
    }
}

/// The stored profile's recovery.mode: "enabled" or "shadow".
ClassMethod Mode(mode As %String)
{
    Set sp = "Shutter.Store.SiteProfile"
    Set row = $CLASSMETHOD(sp, "Row")
    If '$ISOBJECT(row) {
        Do $CLASSMETHOD(sp, "Store", $CLASSMETHOD(sp, "Default").%ToJSON(), "test", "test", "", .v)
        Set row = $CLASSMETHOD(sp, "Row")
    }
    Set p = {}.%FromJSON(row.Json)
    Do p.%Set("recovery", {"mode": (mode)})
    Set row.Json = p.%ToJSON()
    Do row.%Save()
}

/// The stop cleared on the control row, with no event: the test's starting point.
ClassMethod Unstopped()
{
    Set c = ##class(Shutter.Util.RecoveryControl).Control()
    Set c.StopLatched = 0, c.StoppedAt = "", c.StoppedBy = "", c.StopReason = ""
    Do c.%Save()
}

}
