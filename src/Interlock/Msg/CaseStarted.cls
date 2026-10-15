/// The answer to a case intake: which case, and whether it was opened by this intake.
Class Interlock.Msg.CaseStarted Extends Ens.Response
{

Property CaseId As %String(MAXLEN = 32);

Property Opened As %Boolean;

Property State As %String(MAXLEN = 32);

}
