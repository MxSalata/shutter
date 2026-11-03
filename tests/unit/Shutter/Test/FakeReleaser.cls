/// A stand-in for the Case Releaser (Shutter.Operation.Releaser) for the unit tests: made with %New outside the
/// production, it keeps every request it is asked to send instead of queueing it, so a release goes nowhere and the test
/// reads what would have gone; and when ThrowInChecks is set, its checks throw that text, as a check that fails does.
/// Not a test case: the runner leaves it alone.
Class Shutter.Test.FakeReleaser Extends Shutter.Operation.Releaser
{

/// What was sent, one entry per request: "target|CaseId|Reason" for a reinvestigation, else "target|class".
Property Sent As list Of %String;

/// When set, Checks throws an error with this text instead of running the two checks.
Property ThrowInChecks As %String(MAXLEN = 200);

Method SendRequestAsync(pTargetDispatchName As %String, pRequest As %Library.Persistent, pDescription As %String = "") As %Status
{
    If pRequest.%IsA("Shutter.Msg.Reinvestigate") {
        Do ..Sent.Insert(pTargetDispatchName _ "|" _ pRequest.CaseId _ "|" _ pRequest.Reason)
    } Else {
        Do ..Sent.Insert(pTargetDispatchName _ "|" _ $CLASSNAME(pRequest))
    }
    Quit $$$OK
}

Method Checks(Output waitingChecked As %Integer, Output waitingReleased As %Integer, Output heldChecked As %Integer, Output heldReleased As %Integer)
{
    If ..ThrowInChecks '= "" Throw ##class(%Exception.General).%New(..ThrowInChecks, "", "", ..ThrowInChecks)
    Do ##super(.waitingChecked, .waitingReleased, .heldChecked, .heldReleased)
}

}
