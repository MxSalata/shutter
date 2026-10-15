/// Runs the ward tests in the current namespace, for scripts that reach IRIS through SQL:
/// <code>SELECT Wards_Test.Run_Contract()</code>.
Class Wards.Test.Run
{

/// Runs <class>Wards.Test.Contract</class> (already loaded) and returns JSON: the result index, the number of test
/// methods that passed and failed, and the names of the failures.
ClassMethod Contract() As %String [ SqlProc ]
{
    Set before = $ORDER(^UnitTest.Result(""), -1)
    Do ##class(%UnitTest.Manager).DebugRunTestCase("", "Wards.Test.Contract", "/noload/nodelete", "")
    Set run = $ORDER(^UnitTest.Result(""), -1)
    If run = before {
        Quit {"error": "no result was recorded"}.%ToJSON()
    }
    Set passed = 0, failed = 0, failures = []
    Set suite = ""
    For {
        Set suite = $ORDER(^UnitTest.Result(run, suite))
        Quit:suite=""
        Set case = ""
        For {
            Set case = $ORDER(^UnitTest.Result(run, suite, case))
            Quit:case=""
            Set method = ""
            For {
                Set method = $ORDER(^UnitTest.Result(run, suite, case, method))
                Quit:method=""
                If $LISTGET(^UnitTest.Result(run, suite, case, method), 1) {
                    Set passed = passed + 1
                } Else {
                    Set failed = failed + 1
                    Do failures.%Push(method)
                }
            }
        }
    }
    Quit {"run": (run), "passed": (passed), "failed": (failed), "failures": (failures)}.%ToJSON()
}

}
