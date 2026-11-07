/// The incident workflow with its alarms and its next release taken away, for tests that drive an instance outside the
/// production: they count instead, so a test can tell a chain that waits from a chain that stops.
Class Shutter.Test.QuietIncident Extends Shutter.Process.IncidentWorkflow
{

/// The alarm keys asked for, each followed by a semicolon.
Property Alarms As %String [ Transient ];

/// How many times the next release was asked for.
Property Advances As %Integer [ InitialExpression = 0, Transient ];

Method Alarm(seconds As %Integer, key As %String) As %Status
{
    Set ..Alarms = ..Alarms _ key _ ";"
    Quit $$$OK
}

Method Advance(incident As Shutter.Store.Incident) As %Status
{
    Set ..Advances = ..Advances + 1
    Quit $$$OK
}

}
