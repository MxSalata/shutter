/// Asks the verifier to establish what holds at the receiver after an attempt, or after a
/// non-write disposition.
Class Interlock.Msg.VerifyRequest Extends Ens.Request
{

Property CaseId As %String(MAXLEN = 32);

Property PlanId As %String(MAXLEN = 20);

Property AttemptId As %String(MAXLEN = 20);

}
