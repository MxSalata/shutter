/// The case workflow with its send to the gate taken away, for tests that drive an instance outside the production: the
/// plan is stored before that send, and a send with no production under it is a runtime error in the Event Log. The send to
/// the verifier goes the same way.
Class Shutter.Test.QuietWorkflow Extends Shutter.Process.CaseWorkflow
{

Method SendGate(case As Shutter.Store.Case, stage As %String, key As %String) As %Status
{
    Quit $$$OK
}

Method SendVerify(case As Shutter.Store.Case) As %Status
{
    Quit $$$OK
}

}
