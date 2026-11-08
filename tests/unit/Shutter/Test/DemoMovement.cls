/// Another visit's in-patient movement on a demo whose profile a person saved (Shutter.Store.SiteProfile.FurtherMovement,
/// CONTRACTS 6.5): a stored profile that doesn't name further_messages.in_patient_movement reads stop on a demo instance,
/// whoever saved it, and show on a site's. The install's policy (Shutter.Setup.DemoProfilePolicy) never touches a profile a
/// person saved, so the reading itself keeps the demo's stop. The profile and the demo flag are put back afterwards.
Class Shutter.Test.DemoMovement Extends %UnitTest.TestCase
{

Property SavedJson As %String(MAXLEN = "");

Property SavedSource As %String(MAXLEN = 500);

Property HadRow As %Boolean [ InitialExpression = 0 ];

Property HadDemo As %Boolean [ InitialExpression = 0 ];

Property SavedDemo As %String;

Method OnBeforeOneTest() As %Status
{
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    Set ..HadRow = $ISOBJECT(row)
    If ..HadRow Set ..SavedJson = row.Json, ..SavedSource = row.Source
    Set ..HadDemo = ($DATA(^Shutter.Config("demo")) # 2)
    If ..HadDemo Set ..SavedDemo = ^Shutter.Config("demo")
    Quit $$$OK
}

Method OnAfterOneTest() As %Status
{
    If ..HadDemo {
        Set ^Shutter.Config("demo") = ..SavedDemo
    } Else {
        Kill ^Shutter.Config("demo")
    }
    If ..HadRow {
        Do ##class(Shutter.Store.SiteProfile).Store(..SavedJson, ..SavedSource, "test", "", .v)
    } Else {
        Set row = ##class(Shutter.Store.SiteProfile).Row()
        If $ISOBJECT(row) Do ##class(Shutter.Store.SiteProfile).%DeleteId(row.%Id())
    }
    Quit $$$OK
}

/// Stores the shipped profile without further_messages, as a person saves it through the API (source api).
Method StorePersonProfile()
{
    Set p = ##class(Shutter.Store.SiteProfile).Default()
    Do p.%Remove("further_messages")
    Do $$$AssertStatusOK(##class(Shutter.Store.SiteProfile).Store(p.%ToJSON(), "api", "approver", "", .v), "a profile a person saved, with no further_messages")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Row().Source, "api", "stored as the person's")
}

Method TestPersonSavedDemoKeepsTheStop()
{
    Set ^Shutter.Config("demo") = 1
    Do ..StorePersonProfile()
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).FurtherMovement(), "stop", "a demo keeps the stop when a person's profile doesn't say")
    Do $$$AssertStatusOK(##class(Shutter.Setup).DemoProfilePolicy("/tmp/shutter-test-seed/profile.json", 1), "a demo reinstall")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Row().Source, "api", "leaves the person's profile alone")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).FurtherMovement(), "stop", "and the demo still stops")
}

Method TestPersonSavedSiteShows()
{
    Set ^Shutter.Config("demo") = 0
    Do ..StorePersonProfile()
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).FurtherMovement(), "show", "a site shows another visit's movement when its profile doesn't say")
}

/// A profile that names the setting is read as it says, on a demo and on a site alike.
Method TestANamedSettingIsRead()
{
    Set p = ##class(Shutter.Store.SiteProfile).Default()
    For demo = 1, 0 {
        Set ^Shutter.Config("demo") = demo
        For word = "stop", "show" {
            Set p."further_messages"."in_patient_movement" = word
            Do $$$AssertStatusOK(##class(Shutter.Store.SiteProfile).Store(p.%ToJSON(), "api", "approver", "", .v), "a person's profile that says " _ word)
            Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).FurtherMovement(), word, "demo " _ demo _ ": " _ word _ " is read as " _ word)
        }
    }
}

}
