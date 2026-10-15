/// What the verifier established: verified, superseded_after, unresolved or failed.
Class Interlock.Msg.VerifyResult Extends Ens.Response
{

Property Outcome As %String(MAXLEN = 32);

Property VerificationId As %String(MAXLEN = 20);

Property Summary As %String(MAXLEN = 2000);

Property DetailJSON As %String(MAXLEN = "");

Property Error As %String(MAXLEN = 2000);

}
