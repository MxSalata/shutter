/// A chain of an incident: the failed operations for one encounter, oldest event first (CONTRACTS 7.1), with
/// its kind (single, ordered, interleaved), who decides it, the site's policy for it, and its outcome.
Class Shutter.Store.Chain Extends (%Persistent, %JSON.Adaptor)
{

Property Incident As Shutter.Store.Incident(%JSONINCLUDE = "none") [ Required ];

Property Seq As %Integer(%JSONFIELDNAME = "seq") [ Required ];

Index IncidentSeq On (Incident, Seq) [ Unique ];

Property EncounterId As %String(%JSONFIELDNAME = "encounterId", MAXLEN = 100);

Property PatientId As %String(%JSONFIELDNAME = "patientId", MAXLEN = 100);

Property PatientIdAuthority As %String(%JSONFIELDNAME = "patientIdAuthority", MAXLEN = 100);

/// single, ordered, interleaved.
Property Kind As %String(%JSONFIELDNAME = "kind", MAXLEN = 16);

/// policy (the catalogue settles every item), board, or person.
Property Decides As %String(%JSONFIELDNAME = "decides", MAXLEN = 16);

/// The site's policy for a policy chain (automatic, approval, per_chain); path for a chain whose cases run
/// their own path (board, person).
Property Policy As %String(%JSONFIELDNAME = "policy", MAXLEN = 16);

/// The entries the items matched, in order (E2,E2).
Property Entries As %String(%JSONFIELDNAME = "entries", MAXLEN = 200);

/// pending, awaiting_approval, approved, rejected, releasing, resolved, stopped, escalated.
Property State As %String(%JSONFIELDNAME = "state", MAXLEN = 20) [ InitialExpression = "pending" ];

Property Outcome As %String(%JSONFIELDNAME = "outcome", MAXLEN = 2000);

/// The receiver's version the first item expects; each later item goes at the version the previous verified.
Property FirstExpectedVersion As %Integer(%JSONFIELDNAME = "firstExpectedVersion");

/// The item that stopped the chain, when one did.
Property StoppedAt As %Integer(%JSONFIELDNAME = "stoppedAt");

/// The approval of this chain alone (policy per_chain).
Property ApprovedBy As %String(%JSONFIELDNAME = "approvedBy", MAXLEN = 100);

Property ApprovedAt As %String(%JSONFIELDNAME = "approvedAt", MAXLEN = 30);

Property ApprovalDecision As %String(%JSONFIELDNAME = "approvalDecision", MAXLEN = 16);

Property ApprovalComment As %String(%JSONFIELDNAME = "approvalComment", MAXLEN = 2000);

Property ApprovalTaskId As %String(%JSONFIELDNAME = "approvalTaskId", MAXLEN = 50);

Method Items() As %DynamicArray
{
    Set out = []
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.ChainItem WHERE Chain = ? ORDER BY Position", ..%Id())
    While rs.%Next() {
        Set it = ##class(Shutter.Store.ChainItem).%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(it)
        Do out.%Push(it.ToObject())
    }
    Quit out
}

/// The item at a position, or "".
Method ItemAt(position As %Integer) As Shutter.Store.ChainItem
{
    Set cid = ..%Id(), rid = ""
    &sql(SELECT ID INTO :rid FROM Shutter_Store.ChainItem WHERE Chain = :cid AND Position = :position)
    If (SQLCODE '= 0) || (rid = "") Quit ""
    Quit ##class(Shutter.Store.ChainItem).%OpenId(rid)
}

/// The next item still to release, or "".
Method NextPending() As Shutter.Store.ChainItem
{
    Set cid = ..%Id(), rid = ""
    &sql(SELECT TOP 1 ID INTO :rid FROM Shutter_Store.ChainItem WHERE Chain = :cid AND State = 'pending' ORDER BY Position)
    If (SQLCODE '= 0) || (rid = "") Quit ""
    Quit ##class(Shutter.Store.ChainItem).%OpenId(rid)
}

Method ItemCount() As %Integer
{
    Set cid = ..%Id(), n = 0
    &sql(SELECT COUNT(*) INTO :n FROM Shutter_Store.ChainItem WHERE Chain = :cid)
    Quit +n
}

/// The items not yet released are stopped, and their cases escalated with the reason (CONTRACTS 7.4).
Method StopRest(reason As %String, actor As %String = "system") As %Status
{
    Set sc = $$$OK
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.ChainItem WHERE Chain = ? AND State = 'pending' ORDER BY Position", ..%Id())
    While rs.%Next() {
        Set it = ##class(Shutter.Store.ChainItem).%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(it)
        Set it.State = "stopped", it.ClosedAt = ##class(Shutter.Util.Time).NowUTC()
        Set sc = it.%Save()
        Quit:$$$ISERR(sc)
        Set c = it.Case
        If $ISOBJECT(c) && 'c.IsClosed() {
            Set c.Headline = "Not released: " _ reason
            Set sc = c.Transition("escalated", "Not released: " _ reason _ ". This operation needs a person", actor, "incident:" _ ..Incident.IncidentId)
            Quit:$$$ISERR(sc)
        }
    }
    Quit sc
}

Method ToObject() As %DynamicObject
{
    Set o = {}
    Set o.chainId = ..%Id(), o.seq = ..Seq, o.encounterId = ..EncounterId, o.patientId = ..PatientId
    Set o.kind = ..Kind, o.decides = ..Decides, o.policy = ..Policy, o.entries = ..Entries, o.state = ..State, o.outcome = ..Outcome
    Set o.firstExpectedVersion = ..FirstExpectedVersion
    If ..StoppedAt '= "" Set o.stoppedAt = ..StoppedAt
    If ..ApprovalDecision '= "" {
        Set a = {}
        Set a.by = ..ApprovedBy, a.at = ..ApprovedAt, a.decision = ..ApprovalDecision, a.comment = ..ApprovalComment, a.taskId = ..ApprovalTaskId
        Set o.approval = a
    }
    Set o.items = ..Items()
    Quit o
}

Storage Default
{
<Data name="ChainDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Incident</Value>
</Value>
<Value name="3">
<Value>Seq</Value>
</Value>
<Value name="4">
<Value>EncounterId</Value>
</Value>
<Value name="5">
<Value>PatientId</Value>
</Value>
<Value name="6">
<Value>PatientIdAuthority</Value>
</Value>
<Value name="7">
<Value>Kind</Value>
</Value>
<Value name="8">
<Value>Decides</Value>
</Value>
<Value name="9">
<Value>Policy</Value>
</Value>
<Value name="10">
<Value>Entries</Value>
</Value>
<Value name="11">
<Value>State</Value>
</Value>
<Value name="12">
<Value>Outcome</Value>
</Value>
<Value name="13">
<Value>FirstExpectedVersion</Value>
</Value>
<Value name="14">
<Value>StoppedAt</Value>
</Value>
<Value name="15">
<Value>ApprovedBy</Value>
</Value>
<Value name="16">
<Value>ApprovedAt</Value>
</Value>
<Value name="17">
<Value>ApprovalDecision</Value>
</Value>
<Value name="18">
<Value>ApprovalComment</Value>
</Value>
<Value name="19">
<Value>ApprovalTaskId</Value>
</Value>
</Data>
<DataLocation>^Shutter.Store.ChainD</DataLocation>
<DefaultData>ChainDefaultData</DefaultData>
<IdLocation>^Shutter.Store.ChainD</IdLocation>
<IndexLocation>^Shutter.Store.ChainI</IndexLocation>
<StreamLocation>^Shutter.Store.ChainS</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
