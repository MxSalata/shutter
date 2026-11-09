/// The ledger of Shutter's own resends of a receiver's failed messages through the engine: one row per message of an
/// approved set, written by the approval and by Engine Resend before and after each call, and one row per message a person
/// recorded as handled by hand (RunId "H" and the outage id). PatientCheck reads NewHeaderId so that a run never counts its
/// own clones as newer messages; a hand resend's clone has no row, and counts. ResendSet.Place reads a closed_as_present or
/// handled_by_hand row first, so such a message is never offered again.
Class Shutter.Store.ResendRecord Extends %Persistent
{

/// The approved set this row belongs to: the outage's run, one approval.
Property RunId As %String(MAXLEN = 64) [ Required ];

Index RunIdx On RunId;

/// The message's place in the approved order, from 1.
Property Position As %Integer;

/// The outage the set came from.
Property OutageId As %String(MAXLEN = 32);

/// The namespace of the production that holds the messages.
Property Namespace As %String(MAXLEN = 64) [ Required ];

/// The operation item the messages go to.
Property Item As %String(MAXLEN = 128) [ Required ];

/// The header resent: the origin, or Shutter's own earlier clone standing in its place.
Property OriginHeaderId As %String(MAXLEN = 40) [ Required ];

/// The header the engine made for the resend, once the call returned it.
Property NewHeaderId As %String(MAXLEN = 40);

Index NewHeaderIdx On (Namespace, NewHeaderId);

/// The case of the message, when it has one.
Property CaseId As %String(MAXLEN = 32);

/// approved (in the approved run, not sent yet), sending (before the call), completed, failed (the new header did not end Completed), closed_as_present (the receiver
/// already held it, so it was not sent), handled_by_hand (a person resent or re-entered it), stopped (not sent: the run
/// stopped before it) or unknown (a restart mid-call).
Property State As %String(MAXLEN = 24, VALUELIST = ",approved,sending,completed,failed,closed_as_present,handled_by_hand,stopped,unknown") [ InitialExpression = "sending" ];

/// SHA-256 of the stored body before the call, hex.
Property DigestBefore As %String(MAXLEN = 64);

/// Whether the new header's body is the stored body unchanged.
Property SameBody As %Boolean;

/// The digest of the approved set, which the approval names.
Property SetDigest As %String(MAXLEN = 64);

/// The approval and the person who gave it.
Property ApprovalId As %String(MAXLEN = 64);

Property ApprovedBy As %String(MAXLEN = 128);

/// The operation's settings as read before the first send, which the approval binds: a change stops the run.
Property DefCharEncoding As %String(MAXLEN = 64);

Property IPAddress As %String(MAXLEN = 256);

Property Port As %String(MAXLEN = 16);

/// UTC, ISO 8601.
Property StartedAt As %String(MAXLEN = 30);

Property EndedAt As %String(MAXLEN = 30);

/// What happened, in words, for the case and the outage.
Property Words As %String(MAXLEN = 1000);

/// The message's control id (MSH-10), as the set's Row named it.
Property ControlId As %String(MAXLEN = 200);

/// Who recorded a hand closure (handled_by_hand), the signed-in user.
Property RecordedBy As %String(MAXLEN = 128);

/// Whether <var>headerId</var> in <var>ns</var> is a clone one of Shutter's runs made.
ClassMethod IsOwnClone(ns As %String, headerId As %String) As %Boolean
{
    Quit:headerId="" 0
    &sql(SELECT COUNT(*) INTO :n FROM Shutter_Store.ResendRecord WHERE Namespace = :ns AND NewHeaderId = :headerId)
    Quit (SQLCODE = 0) && (n > 0)
}

/// The ledger row of Shutter's own resend that <var>headerId</var> in <var>ns</var> is: the row whose clone it is, or the
/// latest started row on it as an origin; "" for a header no run of Shutter's has touched.
ClassMethod OwnResendRow(ns As %String, headerId As %String) As Shutter.Store.ResendRecord
{
    Quit:headerId="" ""
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 ID FROM Shutter_Store.ResendRecord WHERE Namespace = ? AND (NewHeaderId = ? OR (OriginHeaderId = ? AND StartedAt IS NOT NULL AND StartedAt <> '')) ORDER BY ID DESC", ns, headerId, headerId)
    Quit:rs.%SQLCODE<0 ""
    Quit:'rs.%Next() ""
    Quit ..%OpenId(rs.%Get("ID"))
}

/// The origin a header stands for: the origin of the run whose clone it is, else the header itself.
ClassMethod OriginOf(ns As %String, headerId As %String) As %String
{
    Set origin = ""
    &sql(SELECT TOP 1 OriginHeaderId INTO :origin FROM Shutter_Store.ResendRecord WHERE Namespace = :ns AND NewHeaderId = :headerId)
    Quit $SELECT((SQLCODE = 0) && (origin '= ""): origin, 1: headerId)
}

/// Whether <var>headerId</var> in <var>ns</var> is an origin a run of Shutter's has started to send (a row with StartedAt).
ClassMethod Started(ns As %String, headerId As %String) As %Boolean
{
    Quit:headerId="" 0
    &sql(SELECT COUNT(*) INTO :n FROM Shutter_Store.ResendRecord WHERE Namespace = :ns AND OriginHeaderId = :headerId AND StartedAt IS NOT NULL AND StartedAt <> '')
    Quit (SQLCODE = 0) && (n > 0)
}

/// The row that closed <var>headerId</var> in <var>ns</var> without a send of its own, closed_as_present or
/// handled_by_hand, the latest: {"id", "state", "closure", "by", "at", "words", "caseId"}, or "". A row that names the header
/// as the clone it sent counts for the clone's origin too: <var>also</var> is a $LIST of more header ids (the origin's
/// clones).
ClassMethod ClosedFor(ns As %String, headerId As %String, also As %List = "") As %DynamicObject
{
    Set ids = $LISTBUILD(headerId) _ also, out = ""
    For i = 1:1:$LISTLENGTH(ids) {
        Set h = $LIST(ids, i)
        Continue:h=""
        Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 ID FROM Shutter_Store.ResendRecord WHERE Namespace = ? AND OriginHeaderId = ? AND State IN ('closed_as_present', 'handled_by_hand') ORDER BY ID DESC", ns, h)
        Continue:rs.%SQLCODE<0
        If rs.%Next() {
            Set row = ..%OpenId(rs.%Get("ID"))
            If $ISOBJECT(row) Set out = row.ToObject() Quit
        }
    }
    Quit out
}

/// closure as the routes give it: sent (completed), already_delivered (closed_as_present), handled_by_hand, failed,
/// unknown, or "" (null) while approved, sending or stopped.
ClassMethod Closure(state As %String) As %String
{
    Quit $CASE(state, "completed": "sent", "closed_as_present": "already_delivered", "handled_by_hand": "handled_by_hand", "failed": "failed", "unknown": "unknown", : "")
}

/// One row as the routes give it (CONTRACTS 17.8): {"runId", "position", "headerId", "controlId", "newHeaderId", "state",
/// "closure", "words", "by", "at", "caseId"}, null where nothing has filled it.
Method ToObject() As %DynamicObject
{
    Set o = {"runId": (..RunId)}
    Do o.%Set("position", +..Position, "number")
    Do ..Put(o, "headerId", ..OriginHeaderId), ..Put(o, "controlId", ..ControlId), ..Put(o, "newHeaderId", ..NewHeaderId)
    Set o.state = ..State
    Do ..Put(o, "closure", ..Closure(..State)), ..Put(o, "words", ..Words)
    Do ..Put(o, "by", $SELECT(..RecordedBy '= "": ..RecordedBy, 1: ..ApprovedBy))
    Do ..Put(o, "at", $SELECT(..EndedAt '= "": ..EndedAt, 1: ..StartedAt))
    Do ..Put(o, "caseId", ..CaseId)
    Quit o
}

/// Every row of an outage, its runs in order and each in position order.
ClassMethod OfOutage(outageId As %String) As %DynamicArray
{
    Set out = []
    Quit:outageId="" out
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Shutter_Store.ResendRecord WHERE OutageId = ? ORDER BY ID", outageId)
    Quit:rs.%SQLCODE<0 out
    Kill rows
    While rs.%Next() {
        Set row = ..%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(row)
        // Ordered by the run's first row, then position: a run's rows are written together, a hand closure on its own.
        Set run = row.RunId
        Set:'$DATA(first(run)) first(run) = rs.%Get("ID")
        Set rows(first(run), +row.Position, rs.%Get("ID")) = ""
        Set objs(rs.%Get("ID")) = row
    }
    Set a = ""
    For {
        Set a = $ORDER(rows(a)) Quit:a=""
        Set b = ""
        For {
            Set b = $ORDER(rows(a, b)) Quit:b=""
            Set c = ""
            For {
                Set c = $ORDER(rows(a, b, c)) Quit:c=""
                Do out.%Push(objs(c).ToObject())
            }
        }
    }
    Quit out
}

/// Every row on one origin header of ns (or on Shutter's clone sent in its place), oldest first, as the routes give it.
ClassMethod OfHeader(ns As %String, headerId As %String) As %DynamicArray
{
    Set out = []
    Quit:(ns="")||(headerId="") out
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Shutter_Store.ResendRecord WHERE Namespace = ? AND OriginHeaderId = ? ORDER BY ID", ns, headerId)
    Quit:rs.%SQLCODE<0 out
    While rs.%Next() {
        Set row = ..%OpenId(rs.%Get("ID"))
        Do:$ISOBJECT(row) out.%Push(row.ToObject())
    }
    Quit out
}

ClassMethod Put(o As %DynamicObject, key As %String, value As %String) [ Private ]
{
    If value = "" Do o.%Set(key, "", "null") Quit
    Do o.%Set(key, value)
}

Storage Default
{
<Data name="ResendRecordDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>RunId</Value>
</Value>
<Value name="3">
<Value>Position</Value>
</Value>
<Value name="4">
<Value>OutageId</Value>
</Value>
<Value name="5">
<Value>Namespace</Value>
</Value>
<Value name="6">
<Value>Item</Value>
</Value>
<Value name="7">
<Value>OriginHeaderId</Value>
</Value>
<Value name="8">
<Value>NewHeaderId</Value>
</Value>
<Value name="9">
<Value>CaseId</Value>
</Value>
<Value name="10">
<Value>State</Value>
</Value>
<Value name="11">
<Value>DigestBefore</Value>
</Value>
<Value name="12">
<Value>SameBody</Value>
</Value>
<Value name="13">
<Value>SetDigest</Value>
</Value>
<Value name="14">
<Value>ApprovalId</Value>
</Value>
<Value name="15">
<Value>ApprovedBy</Value>
</Value>
<Value name="16">
<Value>DefCharEncoding</Value>
</Value>
<Value name="17">
<Value>IPAddress</Value>
</Value>
<Value name="18">
<Value>Port</Value>
</Value>
<Value name="19">
<Value>StartedAt</Value>
</Value>
<Value name="20">
<Value>EndedAt</Value>
</Value>
<Value name="21">
<Value>Words</Value>
</Value>
<Value name="22">
<Value>ControlId</Value>
</Value>
<Value name="23">
<Value>RecordedBy</Value>
</Value>
</Data>
<DataLocation>^Shutter.Store.ResendRecordD</DataLocation>
<DefaultData>ResendRecordDefaultData</DefaultData>
<IdLocation>^Shutter.Store.ResendRecordD</IdLocation>
<IndexLocation>^Shutter.Store.ResendRecordI</IndexLocation>
<StreamLocation>^Shutter.Store.ResendRecordS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
