/// Runs the ward tests, for scripts that reach IRIS through SQL: <code>SELECT Wards_Test.Run_Contract()</code>.
Class Wards.Test.Run
{

/// Loads and runs the test classes under <var>repo</var><code>tests/unit/Wards</code> (the repository as the
/// container mounts it) with the unit test manager, keeping them loaded afterwards. Returns JSON: the result index,
/// how many test methods passed and failed, and the names of the failures.
ClassMethod Contract(repo As %String = "/home/irisowner/dev/") As %String [ SqlProc ]
{
    Set root = $GET(^UnitTestRoot)
    Set ^UnitTestRoot = repo _ "tests/unit/"
    Set before = $ORDER(^UnitTest.Result(""), -1)
    Set sc = ##class(%UnitTest.Manager).RunTest("Wards", "/nodelete")
    If root = "" {
        Kill ^UnitTestRoot
    } Else {
        Set ^UnitTestRoot = root
    }
    Set run = $ORDER(^UnitTest.Result(""), -1)
    If run = before {
        Quit {"error": ("no result was recorded: " _ $SYSTEM.Status.GetErrorText(sc))}.%ToJSON()
    }
    Set passed = 0, failed = 0, failures = []
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name, Status FROM %UnitTest_Result.TestMethod WHERE TestCase %STARTSWITH ?", run _ "||")
    While rs.%Next() {
        If rs.%Get("Status") {
            Set passed = passed + 1
        } Else {
            Set failed = failed + 1
            Do failures.%Push(rs.%Get("Name"))
        }
    }
    // The capability profile shows the last contract check
    Do ##class(Wards.Service).SetCapabilities({"last_contract_check": {"at": (##class(Wards.Service).Now()), "result": ("in process: " _ passed _ " of " _ (passed + failed) _ " passed")}}, .ignore)
    Quit {"run": (run), "passed": (passed), "failed": (failed), "failures": (failures)}.%ToJSON()
}

}
