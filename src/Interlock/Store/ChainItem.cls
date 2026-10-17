/// One case in a chain, at its position in event order.
Class Interlock.Store.ChainItem Extends %Persistent
{

Property Chain As Interlock.Store.Chain [ Required ];

Property Position As %Integer [ Required ];

Index ChainPosition On (Chain, Position) [ Unique ];

Property Case As Interlock.Store.Case [ Required ];

Index CaseIdx On Case;

/// The entry the case matched, its outcome and decision.
Property Entry As %String(MAXLEN = 16);

Property CatalogueOutcome As %String(MAXLEN = 32);

Property Decides As %String(MAXLEN = 16);

/// The version this item expects at dispatch: the previous item's verified version, or for the first item the
/// chain's when a person approved it; empty when fresh evidence decides.
Property ExpectedVersion As %String(MAXLEN = 20);

/// The receiver's version after this item's case resolved: the next item's expectation.
Property VerifiedVersion As %String(MAXLEN = 20);

/// The entry and outcome the released case matched on its fresh evidence (the Entry above is the chain-time match).
Property ReleaseEntry As %String(MAXLEN = 16);

Property ReleaseOutcome As %String(MAXLEN = 32);

/// pending, released, resolved, blocked, escalated, failed, stopped (never released: the chain stopped before it).
Property State As %String(MAXLEN = 16) [ InitialExpression = "pending" ];

Property ReleasedAt As %String(MAXLEN = 30);

Property ClosedAt As %String(MAXLEN = 30);

/// The item that holds a case, or "".
ClassMethod ForCase(case As Interlock.Store.Case) As Interlock.Store.ChainItem
{
    If '$ISOBJECT(case) Quit ""
    Set cid = case.%Id(), rid = ""
    &sql(SELECT TOP 1 ID INTO :rid FROM Interlock_Store.ChainItem WHERE "Case" = :cid ORDER BY ID DESC)
    If (SQLCODE '= 0) || (rid = "") Quit ""
    Quit ..%OpenId(rid)
}

/// The kind of the chain a case belongs to, or single.
ClassMethod KindFor(case As Interlock.Store.Case) As %String
{
    Set item = ..ForCase(case)
    If '$ISOBJECT(item) || (item.Chain.Kind = "") Quit "single"
    Quit item.Chain.Kind
}

/// The case's place in its incident, for the evidence summary and the API: an empty object when the case
/// belongs to no incident; the incident alone while the chains are not formed yet.
ClassMethod IncidentContext(case As Interlock.Store.Case) As %DynamicObject
{
    Set o = {}
    If '$ISOBJECT(case) || '$ISOBJECT(case.Incident) Quit o
    Set o."incident_id" = case.Incident.IncidentId, o."incident_state" = case.Incident.State
    Set item = ..ForCase(case)
    If '$ISOBJECT(item) Quit o
    Set o."chain_seq" = item.Chain.Seq, o.position = item.Position, o."chain_kind" = item.Chain.Kind
    Set o.decides = item.Chain.Decides, o."chain_policy" = item.Chain.Policy, o."item_state" = item.State
    If item.ExpectedVersion '= "" Do o.%Set("expected_version", +item.ExpectedVersion, "number")
    Quit o
}

Method ToObject() As %DynamicObject
{
    Set o = {}
    Set o.position = ..Position, o.caseId = ..Case.CaseId, o.event = ..Case.Event, o.eventTime = ..Case.EventTime
    Set o.operationKey = ..Case.OperationKey, o.entry = ..Entry, o.outcome = ..CatalogueOutcome, o.decides = ..Decides
    If ..ExpectedVersion '= "" { Do o.%Set("expectedVersion", +..ExpectedVersion, "number") } Else { Do o.%Set("expectedVersion", "", "null") }
    If ..VerifiedVersion '= "" { Do o.%Set("verifiedVersion", +..VerifiedVersion, "number") } Else { Do o.%Set("verifiedVersion", "", "null") }
    Set o.state = ..State, o.caseState = ..Case.State, o.caseHeadline = ..Case.Headline
    If ..ReleaseEntry '= "" Set o.releaseEntry = ..ReleaseEntry, o.releaseOutcome = ..ReleaseOutcome
    If ..ReleasedAt '= "" Set o.releasedAt = ..ReleasedAt
    If ..ClosedAt '= "" Set o.closedAt = ..ClosedAt
    Quit o
}

Storage Default
{
<Data name="ChainItemDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Chain</Value>
</Value>
<Value name="3">
<Value>Position</Value>
</Value>
<Value name="4">
<Value>Case</Value>
</Value>
<Value name="5">
<Value>Entry</Value>
</Value>
<Value name="6">
<Value>CatalogueOutcome</Value>
</Value>
<Value name="7">
<Value>Decides</Value>
</Value>
<Value name="8">
<Value>ExpectedVersion</Value>
</Value>
<Value name="9">
<Value>VerifiedVersion</Value>
</Value>
<Value name="10">
<Value>State</Value>
</Value>
<Value name="11">
<Value>ReleasedAt</Value>
</Value>
<Value name="12">
<Value>ClosedAt</Value>
</Value>
<Value name="13">
<Value>ReleaseEntry</Value>
</Value>
<Value name="14">
<Value>ReleaseOutcome</Value>
</Value>
</Data>
<DataLocation>^Interlock.Store.ChainItemD</DataLocation>
<DefaultData>ChainItemDefaultData</DefaultData>
<IdLocation>^Interlock.Store.ChainItemD</IdLocation>
<IndexLocation>^Interlock.Store.ChainItemI</IndexLocation>
<StreamLocation>^Interlock.Store.ChainItemS</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
