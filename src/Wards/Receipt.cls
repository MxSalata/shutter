/// The ward's record that an operation was committed under its operation key. A receipt exists only for a committed
/// operation; its absence means the operation was not committed under that key.
Class Wards.Receipt Extends %Persistent
{

Property OperationKey As %String(COLLATION = "EXACT", MAXLEN = 255) [ Required ];

Property EncounterId As %String(COLLATION = "EXACT", MAXLEN = 64) [ Required ];

Property Event As %String(VALUELIST = ",admit,transfer,discharge,update") [ Required ];

Property Ward As %String(COLLATION = "EXACT", MAXLEN = 64);

Property EventTime As %String(MAXLEN = 32) [ Required ];

Property AppliedAt As %String(MAXLEN = 32) [ Required ];

Property VersionBefore As %Integer [ Required ];

Property VersionAfter As %Integer [ Required ];

/// <code>sha256:</code> and the lower-case hex digest of the canonical payload.
Property PayloadDigest As %String(MAXLEN = 80) [ Required ];

Property SourceMessageId As %String(MAXLEN = 64);

Property Status As %String(VALUELIST = ",committed") [ InitialExpression = "committed", Required ];

Index OperationKeyIdx On OperationKey [ Unique ];

Method %OnBeforeSave(insert As %Boolean) As %Status [ Private, ServerOnly = 1 ]
{
    Quit:'insert $$$ERROR($$$GeneralError, "Ward receipts are immutable")
    Quit $$$OK
}

Method ToJSON() As %DynamicObject
{
    Set out = {"operation_key": (..OperationKey), "encounter_id": (..EncounterId), "event": (..Event)}
    If ..Ward = "" { Do out.%Set("ward", "", "null") } Else { Do out.%Set("ward", ..Ward) }
    Do out.%Set("event_time", ..EventTime)
    Do out.%Set("applied_at", ..AppliedAt)
    Do out.%Set("version_before", ..VersionBefore, "number")
    Do out.%Set("version_after", ..VersionAfter, "number")
    Do out.%Set("payload_digest", ..PayloadDigest)
    Do out.%Set("status", ..Status)
    Quit out
}

}
