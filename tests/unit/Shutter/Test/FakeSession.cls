/// A stand-in for %session for the unit tests: records whether the API logged it out and asked for it to end, the two
/// things DELETE /session does (Shutter.API.Dispatch.Logout). Not a test case: the runner leaves it alone.
Class Shutter.Test.FakeSession Extends %RegisteredObject
{

Property EndSession As %Boolean [ InitialExpression = 0 ];

Property LoggedOut As %Boolean [ InitialExpression = 0 ];

Method Logout() As %Status
{
    Set ..LoggedOut = 1
    Quit $$$OK
}

}
