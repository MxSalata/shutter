/// Points the scenario runner at tests/e2e/edge-fixtures and back, for tests/e2e/edge_rows_check.py: scenarios that prove
/// rows of docs/edge-cases.md, kept out of the demo's own list. <code>SELECT Shutter_Test.EdgeFixtures_Use(1)</code>.
/// The folder must be in the container: the repository mounted whole, as in CI. The compose demo mounts no tests/.
Class Shutter.Test.EdgeFixtures
{

/// Returns the folder the runner now reads, or an error's words.
ClassMethod Use(on As %Boolean = 1) As %String [ SqlProc ]
{
    If 'on {
        If $DATA(^Shutter.Test("edgeFixturesWere")) {
            Set ^Shutter.Config("fixtures") = ^Shutter.Test("edgeFixturesWere")
            Kill ^Shutter.Test("edgeFixturesWere")
        }
        Quit ##class(Shutter.Scenarios.Runner).FixturesDir()
    }
    Set current = ##class(Shutter.Scenarios.Runner).FixturesDir()
    Set:'$DATA(^Shutter.Test("edgeFixturesWere")) ^Shutter.Test("edgeFixturesWere") = current
    Set root = ^Shutter.Test("edgeFixturesWere")
    Set dir = $EXTRACT(root, 1, *-$LENGTH("fixtures/")) _ "tests/e2e/edge-fixtures/"
    If '##class(%File).Exists(dir _ "scenarios.json") Quit "no scenarios.json in " _ dir
    Set ^Shutter.Config("fixtures") = dir
    Quit dir
}

}
