/// Runs Shutter's own unit tests, for scripts that reach IRIS through SQL: <code>SELECT Shutter_Test.Run_Triggers()</code>.
Class Shutter.Test.Run
{

/// Loads and runs the test classes under <var>repo</var><code>tests/unit/Shutter</code> (the repository as the container
/// mounts it) with the unit test manager, keeping them loaded afterwards. Returns JSON: the (last) result index, how
/// many test methods passed and failed, and the names of the failures.
ClassMethod Triggers(repo As %String = "/home/irisowner/dev/") As %String [ SqlProc ]
{
    If (repo = "") || (repo = $CHAR(0)) Set repo = "/home/irisowner/dev/"
    Set root = $GET(^UnitTestRoot)
    Set ^UnitTestRoot = repo _ "tests/unit/"
    Set before = $ORDER(^UnitTest.Result(""), -1)
    If ##class(%File).DirectoryExists(repo _ "tests/unit/Shutter") {
        Set sc = ##class(%UnitTest.Manager).RunTest("Shutter", "/nodelete")
    } Else {
        // The tests are not on the mounted path (a worktree loaded them by hand): run the loaded classes as they are.
        // The manager still looks for the root directory, so it is pointed at one that exists.
        Set ^UnitTestRoot = $SYSTEM.Util.ManagerDirectory()
        For class = "Shutter.Test.Triggers", "Shutter.Test.Gate", "Shutter.Test.Matcher" {
            Set sc = ##class(%UnitTest.Manager).DebugRunTestCase("", class, "/noload/nodelete")
        }
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
    // Every result recorded since the call began: one, or one per class run by hand.
    Set passed = 0, failed = 0, failures = [], r = before
    For {
        Set r = $ORDER(^UnitTest.Result(r))
        Quit:r=""
        Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name, Status FROM %UnitTest_Result.TestMethod WHERE TestCase %STARTSWITH ?", r _ "||")
        While rs.%Next() {
            If rs.%Get("Status") {
                Set passed = passed + 1
            } Else {
                Set failed = failed + 1
                Do failures.%Push(rs.%Get("Name"))
            }
        }
    }
    Quit {"run": (run), "passed": (passed), "failed": (failed), "failures": (failures)}.%ToJSON()
}

}
