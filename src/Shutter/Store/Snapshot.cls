/// An immutable set of observations about a case at one moment: the failed message, validation
/// results, the downstream system's state and receipts, later events, routes. Every agent on the board reads
/// the same snapshot, named by its digest; new evidence means a new snapshot.
Class Shutter.Store.Snapshot Extends (%Persistent, %JSON.Adaptor)
{

Property Case As Shutter.Store.Case(%JSONFIELDNAME = "caseId", %JSONREFERENCE = "ID") [ Required ];

Property Seq As %Integer(%JSONFIELDNAME = "seq") [ Required ];

Index CaseSeqIdx On (Case, Seq) [ Unique ];

/// The digest of the canonical JSON of all items, in order.
Property Digest As %String(%JSONFIELDNAME = "digest", MAXLEN = 80);

/// The digest of what a decision rests on (the operation, the failure, the receiver's state and history, the receipt,
/// the later events, the capabilities, the match), without observation times: two collections of the same evidence
/// share it, so an approval survives a refresh that changed nothing material (A7).
Property MaterialDigest As %String(%JSONFIELDNAME = "materialDigest", MAXLEN = 80);

Index DigestIdx On Digest;

Property TakenAt As %String(%JSONFIELDNAME = "takenAt", MAXLEN = 30);

/// Observations of live state are not trusted after this time.
Property FreshUntil As %String(%JSONFIELDNAME = "freshUntil", MAXLEN = 30);

/// The normalised summary the agents and the gate read (JSON): the operation, the failure, the
/// message's named fields, the downstream system's state and version, receipts, later events.
Property Summary As %String(%JSONFIELDNAME = "summary", MAXLEN = "");

/// Start a snapshot for a case. Add items, then Seal() to compute the digest and save.
ClassMethod Begin(case As Shutter.Store.Case, freshSeconds As %Integer = 300) As Shutter.Store.Snapshot
{
    Set s = ..%New()
    // By id, not the caller's copy: the evidence collector holds that copy across its HTTP calls, and a save of the
    // snapshot would otherwise also write the copy whole if it had changed.
    Do s.CaseSetObjectId(case.%Id())
    Set s.Seq = $INCREMENT(^Shutter.Counter("snapshot", case.%Id()))
    Set s.TakenAt = ##class(Shutter.Util.Time).NowUTC()
    Set s.FreshUntil = ##class(Shutter.Util.Time).FromNow(freshSeconds)
    Set s.Summary = "{}"
    Quit s
}

/// The decision-relevant view of a summary (A7): what the gate, the matcher and the board decide on, with no
/// observation times, so that the same evidence collected twice gives the same digest.
ClassMethod Material(summary As %DynamicObject) As %DynamicObject
{
    Set json = "Shutter.Util.Json", m = {}
    Set op = summary.%Get("operation")
    If $ISOBJECT(op) Set m.operation = {"operation_key": ($CLASSMETHOD(json, "Str", op, "operation_key")), "payload_digest": ($CLASSMETHOD(json, "Str", op, "payload_digest"))}
    Set f = summary.%Get("failure")
    If $ISOBJECT(f) Set m.failure = {"kind": ($CLASSMETHOD(json, "Str", f, "kind")), "reason_code": ($CLASSMETHOD(json, "Str", f, "reason_code")), "http_status": ($CLASSMETHOD(json, "Str", f, "http_status"))}
    Set w = summary.%Get("ward_state"), ws = {}
    Set ws."http_status" = $CLASSMETHOD(json, "Str", summary, "ward_state_http_status")
    If $ISOBJECT(w) {
        Set ws.state = $CLASSMETHOD(json, "Str", w, "state"), ws.ward = $CLASSMETHOD(json, "Str", w, "ward"), ws.version = $CLASSMETHOD(json, "Str", w, "version")
        Set ws."patient_id" = $CLASSMETHOD(json, "Str", w, "patient_id"), ws.epoch = $CLASSMETHOD(json, "Str", w, "epoch")
        Set ws.history = []
        Set h = w.%Get("history")
        If $ISOBJECT(h) {
            Set it = h.%GetIterator()
            While it.%GetNext(.i, .e) { Do ws.history.%Push({"event": ($CLASSMETHOD(json, "Str", e, "event")), "event_time": ($CLASSMETHOD(json, "Str", e, "event_time")), "ward": ($CLASSMETHOD(json, "Str", e, "ward"))}) }
        }
    }
    Set m."ward_state" = ws
    Set r = summary.%Get("receipt"), rc = {}
    Set rc."http_status" = $CLASSMETHOD(json, "Str", summary, "receipt_http_status")
    If $ISOBJECT(r) Set rc."operation_key" = $CLASSMETHOD(json, "Str", r, "operation_key"), rc."applied_at" = $CLASSMETHOD(json, "Str", r, "applied_at"), rc."version_after" = $CLASSMETHOD(json, "Str", r, "version_after")
    Set m.receipt = rc
    Set m.later = []
    Set t = summary.%Get("timeline")
    If $ISOBJECT(t) {
        Set it = t.%GetIterator()
        While it.%GetNext(.i, .e) {
            Continue:'$CLASSMETHOD(json, "Bool", e, "later")
            Do m.later.%Push({"operation_key": ($CLASSMETHOD(json, "Str", e, "operation_key")), "event": ($CLASSMETHOD(json, "Str", e, "event")), "outcome": ($CLASSMETHOD(json, "Str", e, "outcome"))})
        }
    }
    Set route = summary.%Get("route")
    If $ISOBJECT(route) Set m.route = {"conditional_writes": ($CLASSMETHOD(json, "Str", route, "conditional_writes")), "receipts": ($CLASSMETHOD(json, "Str", route, "receipts")), "dry_run": ($CLASSMETHOD(json, "Str", route, "dry_run")), "capabilities_http_status": ($CLASSMETHOD(json, "Str", route, "capabilities_http_status"))}
    Set cat = summary.%Get("catalogue")
    If $ISOBJECT(cat) Set m.catalogue = {"decision": ($CLASSMETHOD(json, "Str", cat, "decision")), "entry": ($CLASSMETHOD(json, "Str", cat, "entry")), "outcome": ($CLASSMETHOD(json, "Str", cat, "outcome")), "conditions": (cat.%Get("conditions"))}
    Set inc = summary.%Get("incident")
    If $ISOBJECT(inc) Set m.incident = {"incident_id": ($CLASSMETHOD(json, "Str", inc, "incident_id")), "chain_seq": ($CLASSMETHOD(json, "Str", inc, "chain_seq")), "position": ($CLASSMETHOD(json, "Str", inc, "position"))}
    Quit m
}

/// Add an observation. kind: message, validation, ward_state, receipt, later_event, route, error.
/// source: message_store, ward_api, production, validator. The item is kept in memory until Seal().
Method AddItem(kind As %String, source As %String, observedAt As %String, json As %DynamicAbstractObject) As %Status
{
    Set n = $INCREMENT(i%PendingCount)
    Set i%Pending(n) = $LISTBUILD(kind, source, observedAt, json.%ToJSON())
    Quit $$$OK
}

Property PendingCount As %Integer(%JSONINCLUDE = "none") [ InitialExpression = 0, Transient ];

Property Pending As %String(%JSONINCLUDE = "none") [ MultiDimensional, Transient ];

/// Compute the digest over the items and the summary, save the snapshot and its items.
Method Seal(summary As %DynamicObject) As %Status
{
    Set ..Summary = summary.%ToJSON()
    Set all = []
    For n = 1:1:..PendingCount {
        Set item = i%Pending(n)
        Set obj = {}
        Set obj.kind = $LIST(item, 1), obj.source = $LIST(item, 2), obj."observed_at" = $LIST(item, 3)
        Set obj.data = ##class(%DynamicAbstractObject).%FromJSON($LIST(item, 4))
        Do all.%Push(obj)
    }
    Set envelope = {}
    Set envelope.items = all
    Set envelope.summary = summary
    Set ..Digest = ##class(Shutter.Util.Digest).OfObject(envelope)
    Set ..MaterialDigest = ##class(Shutter.Util.Digest).OfObject(..Material(summary))
    TSTART
    Set sc = ..%Save()
    If $$$ISOK(sc) {
        For n = 1:1:..PendingCount {
            Set item = i%Pending(n)
            Set si = ##class(Shutter.Store.SnapshotItem).%New()
            Set si.Snapshot = $THIS, si.Seq = n
            Set si.Kind = $LIST(item, 1), si.Source = $LIST(item, 2), si.ObservedAt = $LIST(item, 3), si.Json = $LIST(item, 4)
            Set si.Digest = ##class(Shutter.Util.Digest).SHA256Hex($LIST(item, 4))
            Set sc = si.%Save()
            Quit:$$$ISERR(sc)
        }
    }
    If $$$ISOK(sc) { TCOMMIT } Else { TROLLBACK }
    Quit sc
}

/// The items as a dynamic array of {seq, kind, source, observed_at, data}.
Method Items() As %DynamicArray
{
    Set out = []
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.SnapshotItem WHERE Snapshot = ? ORDER BY Seq", ..%Id())
    While rs.%Next() {
        Set si = ##class(Shutter.Store.SnapshotItem).%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(si)
        Set obj = {}
        Set obj.seq = si.Seq, obj.kind = si.Kind, obj.source = si.Source, obj."observed_at" = si.ObservedAt
        Set obj.data = ##class(%DynamicAbstractObject).%FromJSON(si.Json)
        Do out.%Push(obj)
    }
    Quit out
}

/// The parsed summary.
Method SummaryObject() As %DynamicObject
{
    Quit ##class(%DynamicObject).%FromJSON(..Summary)
}

/// True when the snapshot's live observations are still within their freshness window.
Method IsFresh() As %Boolean
{
    Quit ##class(Shutter.Util.Time).NowUTC() ']] ..FreshUntil
}

Storage Default
{
<Data name="SnapshotDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Case</Value>
</Value>
<Value name="3">
<Value>Seq</Value>
</Value>
<Value name="4">
<Value>Digest</Value>
</Value>
<Value name="5">
<Value>TakenAt</Value>
</Value>
<Value name="6">
<Value>FreshUntil</Value>
</Value>
<Value name="7">
<Value>Summary</Value>
</Value>
<Value name="8">
<Value>MaterialDigest</Value>
</Value>
</Data>
<DataLocation>^Shutter.Store.SnapshotD</DataLocation>
<DefaultData>SnapshotDefaultData</DefaultData>
<IdLocation>^Shutter.Store.SnapshotD</IdLocation>
<IndexLocation>^Shutter.Store.SnapshotI</IndexLocation>
<StreamLocation>^Shutter.Store.SnapshotS</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
