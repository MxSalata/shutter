/// A chain of an incident: the failed operations for one encounter, oldest event first (CONTRACTS 7.1), with
/// its kind (single, ordered, interleaved), the entry its cases matched, and its outcome.
Class Interlock.Store.Chain Extends (%Persistent, %JSON.Adaptor)
{

Property Incident As Interlock.Store.Incident(%JSONFIELDNAME = "incidentId", %JSONREFERENCE = "ID") [ Required ];

Property Seq As %Integer(%JSONFIELDNAME = "seq") [ Required ];

Index IncidentSeq On (Incident, Seq) [ Unique ];

Property EncounterId As %String(%JSONFIELDNAME = "encounterId", MAXLEN = 100);

Property PatientId As %String(%JSONFIELDNAME = "patientId", MAXLEN = 100);

Property PatientIdAuthority As %String(%JSONFIELDNAME = "patientIdAuthority", MAXLEN = 100);

/// single, ordered, interleaved.
Property Kind As %String(%JSONFIELDNAME = "kind", MAXLEN = 16);

/// policy (the catalogue settles every item), board, or person.
Property Decides As %String(%JSONFIELDNAME = "decides", MAXLEN = 16);

/// The entries the items matched, in order (E2,E2).
Property Entries As %String(%JSONFIELDNAME = "entries", MAXLEN = 200);

/// pending, approved, releasing, resolved, stopped, escalated, closed (no write).
Property State As %String(%JSONFIELDNAME = "state", MAXLEN = 16) [ InitialExpression = "pending" ];

Property Outcome As %String(%JSONFIELDNAME = "outcome", MAXLEN = 2000);

/// The receiver's version the first item expects; each later item goes at the version the previous verified.
Property FirstExpectedVersion As %Integer(%JSONFIELDNAME = "firstExpectedVersion");

/// The item that stopped the chain, when one did.
Property StoppedAt As %Integer(%JSONFIELDNAME = "stoppedAt");

Method Items() As %DynamicArray
{
    Set out = []
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Interlock_Store.ChainItem WHERE Chain = ? ORDER BY Position", ..%Id())
    While rs.%Next() {
        Set it = ##class(Interlock.Store.ChainItem).%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(it)
        Do out.%Push(it.ToObject())
    }
    Quit out
}

Method ToObject() As %DynamicObject
{
    Set o = {}
    Set o.chainId = ..%Id(), o.seq = ..Seq, o.encounterId = ..EncounterId, o.patientId = ..PatientId
    Set o.kind = ..Kind, o.decides = ..Decides, o.entries = ..Entries, o.state = ..State, o.outcome = ..Outcome
    Set o.firstExpectedVersion = ..FirstExpectedVersion
    If ..StoppedAt '= "" Set o.stoppedAt = ..StoppedAt
    Set o.items = ..Items()
    Quit o
}

}
