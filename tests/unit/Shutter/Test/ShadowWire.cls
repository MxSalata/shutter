/// What reaches the wire with no recovery.mode in the site profile: a profile that doesn't say enabled means shadow, so a
/// rehearsal and a recovery write send nothing at all, counted at the connector's adapter.
Class Shutter.Test.ShadowWire Extends %UnitTest.TestCase
{

Property SavedProfile As %String(MAXLEN = "");

Property HadRow As %Boolean;

Method OnBeforeOneTest() As %Status
{
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    Set ..HadRow = $ISOBJECT(row), ..SavedProfile = $SELECT($ISOBJECT(row): row.Json, 1: "")
    Do ##class(Shutter.Test.CountingAdapter).Clear()
    Quit $$$OK
}

Method OnAfterOneTest() As %Status
{
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    If ..HadRow { Set row.Json = ..SavedProfile Do row.%Save() } ElseIf $ISOBJECT(row) { Do ##class(Shutter.Store.SiteProfile).%DeleteId(row.%Id()) }
    Do ##class(Shutter.Test.CountingAdapter).Clear()
    Quit $$$OK
}

/// The stored profile without the recovery field.
ClassMethod ProfileWithoutMode()
{
    Set p = ##class(Shutter.Store.SiteProfile).Current()
    Do p.%Remove("recovery")
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    If '$ISOBJECT(row) Set row = ##class(Shutter.Store.SiteProfile).%New()
    // Beside the store, so that it leaves no version in the profile's history.
    Set row.Json = p.%ToJSON()
    Do row.%Save()
}

ClassMethod Operation(purpose As %String) As Shutter.Msg.WardOperation
{
    Set w = ##class(Shutter.Msg.WardOperation).%New()
    Set w.Purpose = purpose, w.DryRun = (purpose = "rehearsal"), w.OperationKey = "PAS^HOSP^MRN9005^ENC-9005^transfer^2026-10-15T08:20:00Z"
    Set w.EncounterId = "ENC-9005", w.PatientId = "MRN9005", w.Event = "transfer", w.Ward = "WARD-B", w.EventTime = "2026-10-15T08:20:00Z"
    Set w.SourceSystem = "PAS", w.SourceMessageId = "M1"
    Quit w
}

/// The connector with the counting adapter in place of its own.
ClassMethod Connector() As Shutter.Operation.Ward
{
    Set op = ##class(Shutter.Operation.Ward).%New("UT Shadow Ward")
    Set op.Adapter = ##class(Shutter.Test.CountingAdapter).%New()
    Set op.OperationsPath = "/operations"
    Quit op
}

Method TestNoModeMeansNothingOnTheWire()
{
    Do ..ProfileWithoutMode()
    Do ##class(Shutter.Test.CountingAdapter).Answer()
    For purpose = "rehearsal", "recovery" {
        Do $$$AssertStatusOK(..Connector().OnWardOperation(..Operation(purpose), .result), purpose)
        Do $$$AssertEquals(result.Outcome, "refused", purpose _ " is refused: " _ result.Outcome)
    }
    Do $$$AssertEquals(##class(Shutter.Test.CountingAdapter).Count(), 0, "no POST reached the receiver")
}

}
