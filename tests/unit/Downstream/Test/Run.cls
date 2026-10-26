/// Runs the downstream system's tests, for scripts that reach IRIS through SQL: <code>SELECT Downstream_Test.Run_Contract()</code>.
Class Downstream.Test.Run
{

/// Loads and runs the test classes under <var>repo</var><code>tests/unit/Downstream</code> (the repository as the
/// container mounts it) with the unit test manager, keeping them loaded afterwards. Returns JSON: the result index,
/// how many test methods passed and failed, and the names of the failures. When <var>repo</var> has no such folder, the
/// test class already loaded is run as it is.
ClassMethod Contract(repo As %String = "/home/irisowner/dev/") As %String [ SqlProc ]
{
    If (repo = "") || (repo = $CHAR(0)) Set repo = "/home/irisowner/dev/"
    Set root = $GET(^UnitTestRoot)
    Set ^UnitTestRoot = repo _ "tests/unit/"
    Set before = $ORDER(^UnitTest.Result(""), -1)
    If ##class(%File).DirectoryExists(repo _ "tests/unit/Downstream") {
        Set sc = ##class(%UnitTest.Manager).RunTest("Downstream", "/nodelete")
    } Else {
        // The tests are not on the mounted path (a worktree loaded them by hand): run the loaded test class as it is,
        // with the manager pointed at a root directory that exists.
        Set ^UnitTestRoot = $SYSTEM.Util.ManagerDirectory()
        Set sc = ##class(%UnitTest.Manager).DebugRunTestCase("", "Downstream.Test.Contract", "/noload/nodelete")
    }
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
    Do ##class(Downstream.Service).SetCapabilities({"last_contract_check": {"at": (##class(Downstream.Service).Now()), "result": ("in process: " _ passed _ " of " _ (passed + failed) _ " passed")}}, .ignore)
    Quit {"run": (run), "passed": (passed), "failed": (failed), "failures": (failures)}.%ToJSON()
}

}
