/// Runs Shutter's own unit tests, for scripts that reach IRIS through SQL: <code>SELECT Shutter_Test.Run_Triggers()</code>.
Class Shutter.Test.Run
{

/// Loads and runs the test classes under <var>repo</var><code>tests/unit/Shutter</code> (the repository as the container
/// mounts it) with the unit test manager, keeping them loaded afterwards. Returns JSON: the (last) result index, how
/// many test methods passed, failed and were skipped, the names of the failures, and the skipped methods with their
/// classes. A skipped method is one that called $$$AssertSkipped (what it needs is not on this instance: the aihub
/// module's classes on the core edition, for one); the manager records it with the status 2, apart from a pass (1) and
/// a failure (0), so the three counts add up to the methods run.
ClassMethod Triggers(repo As %String = "/home/irisowner/dev/") As %String [ SqlProc ]
{
    // Called over HTTP, the suite can outlast the web gateway's 60-second response timeout: ask it to wait (as the
    // scenario runner does for a long run).
    Set:$ISOBJECT($GET(%response)) %response.Timeout = 900
    If (repo = "") || (repo = $CHAR(0)) Set repo = "/home/irisowner/dev/"
    Set root = $GET(^UnitTestRoot)
    Set ^UnitTestRoot = repo _ "tests/unit/"
    Set before = $ORDER(^UnitTest.Result(""), -1)
    If ##class(%File).DirectoryExists(repo _ "tests/unit/Shutter") {
        Set sc = ##class(%UnitTest.Manager).RunTest("Shutter", "/nodelete")
    } Else {
        // The tests are not on the mounted path (a worktree loaded them by hand): run every loaded test class of the
        // package as it is. The manager still looks for the root directory, so it is pointed at one that exists.
        Set ^UnitTestRoot = $SYSTEM.Util.ManagerDirectory()
        Set sc = $$$ERROR($$$GeneralError, "no test class of the package Shutter.Test is loaded")
        Set classes = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM %Dictionary.CompiledClass WHERE Name %STARTSWITH 'Shutter.Test.' ORDER BY Name")
        While classes.%Next() {
            Set class = classes.%Get("Name")
            Continue:'$CLASSMETHOD(class, "%Extends", "%UnitTest.TestCase")
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
    Set passed = 0, failed = 0, skipped = 0, failures = [], skips = [], r = before
    For {
        Set r = $ORDER(^UnitTest.Result(r))
        Quit:r=""
        Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TestCase, Name, Status FROM %UnitTest_Result.TestMethod WHERE TestCase %STARTSWITH ?", r _ "||")
        While rs.%Next() {
            Set status = rs.%Get("Status")
            If status = 2 {
                Set skipped = skipped + 1
                Do skips.%Push($PIECE(rs.%Get("TestCase"), "||", 3) _ ":" _ rs.%Get("Name"))
            } ElseIf status {
                Set passed = passed + 1
            } Else {
                Set failed = failed + 1
                Do failures.%Push(rs.%Get("Name"))
            }
        }
    }
    Quit {"run": (run), "passed": (passed), "failed": (failed), "skipped": (skipped), "failures": (failures), "skips": (skips)}.%ToJSON()
}

}
