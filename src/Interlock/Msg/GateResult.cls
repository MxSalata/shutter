/// The gate's decision: pass, block or unknown, with every check and its reason code.
Class Interlock.Msg.GateResult Extends Ens.Response
{

Property Outcome As %String(MAXLEN = 16);

Property DecisionId As %String(MAXLEN = 20);

Property PolicyVersion As %String(MAXLEN = 32);

Property ChecksJSON As %String(MAXLEN = "");

Property Summary As %String(MAXLEN = 2000);

Property Error As %String(MAXLEN = 2000);

}
