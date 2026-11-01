/// HL7 schemas as the namespace holds them (Shutter.Util.Schemas; CONTRACTS 12, v1.32): the loaded categories, what the
/// production and the messages need, the import's refusals, and the gate's SCHEMA_UNKNOWN through the Doctor's shape.
Class Shutter.Test.Schemas Extends %UnitTest.TestCase
{

Method TestLoadedAndKnown()
{
    Set loaded = ##class(Shutter.Util.Schemas).Categories()
    Do $$$AssertTrue(loaded.%Size() > 0, "schema categories are loaded here")
    Set has251 = 0, li = loaded.%GetIterator()
    While li.%GetNext(, .c) { If c.category = "2.5.1" Set has251 = 1 }
    Do $$$AssertTrue(has251, "2.5.1 is among them")
    Do $$$AssertTrue(##class(Shutter.Util.Schemas).Known("2.5.1"), "2.5.1 is known")
    Do $$$AssertNotTrue(##class(Shutter.Util.Schemas).Known("2.5.ZZZ"), "a made-up category is not")
    Do $$$AssertNotTrue(##class(Shutter.Util.Schemas).Known(""), "nor an empty one")
}

Method TestNeededAndReport()
{
    Set needed = ##class(Shutter.Util.Schemas).Needed(50)
    Set found = 0, ni = needed.%GetIterator()
    While ni.%GetNext(, .n) { If (n.category = "2.5.1") && n.known Set found = 1 }
    Do $$$AssertTrue(found, "the production's ADT In names 2.5.1, which is known: " _ needed.%ToJSON())
    Set r = ##class(Shutter.Util.Schemas).Report()
    Do $$$AssertTrue(r.%IsDefined("loaded") && r.%IsDefined("needed") && r.%IsDefined("missing"), "the report has its three lists")
    Do $$$AssertEquals(r.fix, $SELECT(r.missing.%Size() = 0: "", 1: r.fix), "the fix is named only when something is missing")
    If r.missing.%Size() = 0 Do $$$AssertEquals(r.fix, "", "nothing missing, no fix to name")
}

Method TestImportRefusals()
{
    Do $$$AssertStatusNotOK(##class(Shutter.Util.Schemas).Import("", .cat), "an empty path is refused")
    Do $$$AssertStatusNotOK(##class(Shutter.Util.Schemas).Import("/etc/passwd", .cat), "a file that is not .xml is refused")
    Do $$$AssertStatusNotOK(##class(Shutter.Util.Schemas).Import("/nonexistent/schema.xml", .cat), "a file that is not there is refused")
    Do $$$AssertEquals(cat, "", "and no category comes back")
}

}
