/// One case in a chain, at its position in event order.
Class Interlock.Store.ChainItem Extends %Persistent
{

Property Chain As Interlock.Store.Chain [ Required ];

Property Position As %Integer [ Required ];

Index ChainPosition On (Chain, Position) [ Unique ];

Property Case As Interlock.Store.Case [ Required ];

/// The entry the case matched, its outcome and decision.
Property Entry As %String(MAXLEN = 16);

Property CatalogueOutcome As %String(MAXLEN = 32);

Property Decides As %String(MAXLEN = 16);

/// The version this item expects at dispatch: the first item's from the evidence, the others from the previous
/// item's verified receipt.
Property ExpectedVersion As %Integer;

/// pending, released, resolved, stopped, escalated, closed.
Property State As %String(MAXLEN = 16) [ InitialExpression = "pending" ];

Method ToObject() As %DynamicObject
{
    Set o = {}
    Set o.position = ..Position, o.caseId = ..Case.CaseId, o.event = ..Case.Event, o.eventTime = ..Case.EventTime
    Set o.operationKey = ..Case.OperationKey, o.entry = ..Entry, o.outcome = ..CatalogueOutcome, o.decides = ..Decides
    Set o.expectedVersion = ..ExpectedVersion, o.state = ..State, o.caseState = ..Case.State
    Quit o
}

}
