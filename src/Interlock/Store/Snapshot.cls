/// An immutable set of observations about a case at one moment: the failed message, validation
/// results, the ward's state and receipts, later events, routes. Every agent on the board reads
/// the same snapshot, named by its digest; new evidence means a new snapshot.
Class Interlock.Store.Snapshot Extends (%Persistent, %JSON.Adaptor)
{

Property Case As Interlock.Store.Case(%JSONFIELDNAME = "caseId", %JSONREFERENCE = "ID") [ Required ];

Property Seq As %Integer(%JSONFIELDNAME = "seq") [ Required ];

Index CaseSeqIdx On (Case, Seq) [ Unique ];

/// The digest of the canonical JSON of all items, in order.
Property Digest As %String(%JSONFIELDNAME = "digest", MAXLEN = 80);

Index DigestIdx On Digest;

Property TakenAt As %String(%JSONFIELDNAME = "takenAt", MAXLEN = 30);

/// Observations of live state are not trusted after this time.
Property FreshUntil As %String(%JSONFIELDNAME = "freshUntil", MAXLEN = 30);

/// The normalised summary the agents and the gate read (JSON): the operation, the failure, the
/// message's named fields, the ward state and version, receipts, later events.
Property Summary As %String(%JSONFIELDNAME = "summary", MAXLEN = "");

/// Start a snapshot for a case. Add items, then Seal() to compute the digest and save.
ClassMethod Begin(case As Interlock.Store.Case, freshSeconds As %Integer = 300) As Interlock.Store.Snapshot
{
    Set s = ..%New()
    Set s.Case = case
    Set s.Seq = $INCREMENT(^Interlock.Counter("snapshot", case.%Id()))
    Set s.TakenAt = ##class(Interlock.Util.Time).NowUTC()
    Set s.FreshUntil = ##class(Interlock.Util.Time).FromNow(freshSeconds)
    Set s.Summary = "{}"
    Quit s
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
    Set ..Digest = ##class(Interlock.Util.Digest).OfObject(envelope)
    TSTART
    Set sc = ..%Save()
    If $$$ISOK(sc) {
        For n = 1:1:..PendingCount {
            Set item = i%Pending(n)
            Set si = ##class(Interlock.Store.SnapshotItem).%New()
            Set si.Snapshot = $THIS, si.Seq = n
            Set si.Kind = $LIST(item, 1), si.Source = $LIST(item, 2), si.ObservedAt = $LIST(item, 3), si.Json = $LIST(item, 4)
            Set si.Digest = ##class(Interlock.Util.Digest).SHA256Hex($LIST(item, 4))
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
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Interlock_Store.SnapshotItem WHERE Snapshot = ? ORDER BY Seq", ..%Id())
    While rs.%Next() {
        Set si = ##class(Interlock.Store.SnapshotItem).%OpenId(rs.%Get("ID"))
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
    Quit ##class(Interlock.Util.Time).NowUTC() ']] ..FreshUntil
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
</Data>
<DataLocation>^Interlock.Store.SnapshotD</DataLocation>
<DefaultData>SnapshotDefaultData</DefaultData>
<IdLocation>^Interlock.Store.SnapshotD</IdLocation>
<IndexLocation>^Interlock.Store.SnapshotI</IndexLocation>
<StreamLocation>^Interlock.Store.SnapshotS</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
