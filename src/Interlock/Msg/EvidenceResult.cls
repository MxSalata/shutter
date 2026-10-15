/// The snapshot the evidence collector took: its id, its digest and the summary the agents and the
/// gate read.
Class Interlock.Msg.EvidenceResult Extends Ens.Response
{

Property SnapshotId As %String(MAXLEN = 20);

Property Digest As %String(MAXLEN = 80);

Property SummaryJSON As %String(MAXLEN = "");

Property ItemCount As %Integer;

Property Error As %String(MAXLEN = 2000);

}
