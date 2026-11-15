/// The case workflow for tests that drive an instance outside the production, with the evidence request taken away as
/// well as the gate's and the verifier's (Shutter.Test.QuietWorkflow): a case sent back for fresh evidence moves to
/// collecting, and the request that would follow is counted in ^||Shutter.Test.SiteWorkflow instead of sent.
Class Shutter.Test.SiteWorkflow Extends Shutter.Test.QuietWorkflow
{

Method StartEvidence(case As Shutter.Store.Case) As %Status
{
    Set ..Round = ..Round + 1
    Set ^||Shutter.Test.SiteWorkflow("evidence") = $GET(^||Shutter.Test.SiteWorkflow("evidence")) + 1
    Quit case.Transition("collecting", "Collecting evidence", "system")
}

}
