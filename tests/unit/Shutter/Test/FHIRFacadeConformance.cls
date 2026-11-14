/// Runs every exchange of <code>tests/conformance/fhir-facade-v1.json</code> whose targets include the test FHIR server,
/// in order, in process through <code>FHIRFacade.Service.Handle</code>, after its reset and with its clock fixed, with the
/// kit's runner <code>FHIRFacade.Kit</code>. The exchanges are the S0 measurements of IRIS for Health's own FHIR server, so
/// a pass says the test server answers as IRIS was measured to. The cases are embedded in the kit's runner (XData Cases,
/// written from the file by <code>tests/conformance/embed.py</code>), because a stock-install container does not mount the
/// repository; the second test checks the copy against the file when the file can be read.
/// <code>tests/conformance/fhir_conformance.py</code> runs the same file over HTTP, against IRIS or the test server.
Class Shutter.Test.FHIRFacadeConformance Extends %UnitTest.TestCase
{

Parameter SERVICE = "FHIRFacade.Service";

Parameter KIT = "FHIRFacade.Kit";

Method OnBeforeOneTest(testname As %String) As %Status
{
    If ..Loaded() {
        Do $CLASSMETHOD(..#SERVICE, "Reset")
        Do $CLASSMETHOD(..#SERVICE, "SetClock", $PARAMETER(..#KIT, "CLOCK"))
    }
    Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
    If ..Loaded() {
        Do $CLASSMETHOD(..#SERVICE, "Reset")
        Do $CLASSMETHOD(..#SERVICE, "SetClock", "")
    }
    Quit $$$OK
}

Method TestEveryFacadeExchange()
{
    If '..Loaded() {
        Do $$$AssertSkipped("FHIRFacade is not loaded on this instance")
        Quit
    }
    Set kit = ..#KIT
    Set doc = $CLASSMETHOD(kit, "Cases"), vars = {}, run = 0
    Set iter = doc.exchanges.%GetIterator()
    While iter.%GetNext(, .x) {
        Continue:'$CLASSMETHOD(kit, "Targets", x, "facade")
        Set run = run + 1
        Set got = $CLASSMETHOD(kit, "Send", x.request, vars)
        Set problems = $CLASSMETHOD(kit, "Check", x.expect, got, vars)
        Do $$$AssertEquals(problems.%Size(), 0, x.id _ $SELECT(problems.%Size() = 0: "", 1: ": " _ problems.%ToJSON()))
        Do $CLASSMETHOD(kit, "Capture", x, got, vars)
    }
    Do $$$AssertTrue(run >= 60, run _ " exchanges ran against the test server")
}

/// The embedded copy is the file, when the file is where the unit runner was pointed.
Method TestEmbeddedCopyMatchesTheFile()
{
    Set file = $GET(^UnitTestRoot) _ "../conformance/fhir-facade-v1.json"
    If ($GET(^UnitTestRoot) = "") || '##class(%File).Exists(file) {
        Do $$$AssertSkipped("the conformance file is not on this instance (" _ file _ "); tests/conformance/embed.py --check compares them")
        Quit
    }
    Set stream = ##class(%Stream.FileCharacter).%New()
    Do stream.LinkToFile(file)
    Set stream.TranslateTable = "UTF8"
    Set fromFile = {}.%FromJSON(stream)
    Do $$$AssertEquals(fromFile.%ToJSON(), $CLASSMETHOD(..#KIT, "Cases").%ToJSON(), "XData Cases is the conformance file")
}

Method Loaded() As %Boolean
{
    Quit ##class(%Dictionary.CompiledClass).%ExistsId(..#SERVICE) && ##class(%Dictionary.CompiledClass).%ExistsId(..#KIT)
}

}
