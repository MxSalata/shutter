/// A stand-in for Shutter.Setup for the unit tests: its HardenPortal refuses as the real one does for a process without
/// %Admin_Secure and changes nothing, so ApplyRuntime's failure path runs whatever the login's roles, through
/// ##class(Shutter.Test.FakeSetup).ApplyRuntime(...). Not a test case: the runner leaves it alone.
Class Shutter.Test.FakeSetup Extends Shutter.Setup
{

ClassMethod HardenPortal(hospital As %String = "") As %String
{
    Quit {"error": "%Admin_Secure is required"}.%ToJSON()
}

}
