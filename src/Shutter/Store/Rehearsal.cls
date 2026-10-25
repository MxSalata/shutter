/// A rehearsal: the exact planned write sent to the receiver as a dry run, which it validates and
/// rolls back. Evidence about what would happen now, not a guarantee about later.
Class Shutter.Store.Rehearsal Extends (%Persistent, %JSON.Adaptor)
{

Property Case As Shutter.Store.Case(%JSONFIELDNAME = "caseId", %JSONREFERENCE = "ID") [ Required ];

Index CaseIdx On Case;

Property Plan As Shutter.Store.Plan(%JSONFIELDNAME = "planId", %JSONREFERENCE = "ID");

Property At As %String(%JSONFIELDNAME = "at", MAXLEN = 30);

Property HttpStatus As %Integer(%JSONFIELDNAME = "httpStatus");

Property WouldApply As %Boolean(%JSONFIELDNAME = "wouldApply");

Property Reason As %String(%JSONFIELDNAME = "reason", MAXLEN = 200);

/// The receiver's version the dry run was checked against (encounter_before).
Property ReceiverVersion As %Integer(%JSONFIELDNAME = "receiverVersion");

/// The version the write would leave (encounter_after), when it would apply.
Property VersionAfter As %Integer(%JSONFIELDNAME = "versionAfter");

/// The receiver's epoch at the time.
Property Epoch As %Integer(%JSONFIELDNAME = "epoch");

Property ResponseJSON As %String(%JSONFIELDNAME = "response", MAXLEN = "");

/// What was sent (v1.19): the receiver version the dry run was conditional on, and the digest of the payload. The dispatch
/// gate's rehearsal check compares them with the write it releases.
Property ExpectedVersion As %Integer(%JSONFIELDNAME = "expectedVersion");

Property PayloadDigest As %String(%JSONFIELDNAME = "payloadDigest", MAXLEN = 80);

/// Records a dry run: <var>sent</var> is the operation that went to the receiver, <var>response</var> what it answered.
ClassMethod Create(case As Shutter.Store.Case, plan As Shutter.Store.Plan, sent As Shutter.Msg.WardOperation, httpStatus As %Integer, response As %DynamicObject, Output r As Shutter.Store.Rehearsal) As %Status
{
    Set r = ..%New()
    // By id, not the caller's copy (as Snapshot.Begin does): a save of the rehearsal never writes the case copy whole.
    Do r.CaseSetObjectId(case.%Id())
    Set r.Plan = plan, r.At = ##class(Shutter.Util.Time).NowUTC(), r.HttpStatus = httpStatus
    If $ISOBJECT(sent) Set r.ExpectedVersion = sent.ExpectedVersion, r.PayloadDigest = sent.PayloadDigest
    Set r.WouldApply = ##class(Shutter.Util.Json).Bool(response, "would_apply")
    Set r.Reason = ##class(Shutter.Util.Json).Str(response, "reason")
    Set before = response.%Get("encounter_before"), after = response.%Get("encounter_after")
    If $ISOBJECT(before) Set r.ReceiverVersion = ##class(Shutter.Util.Json).Str(before, "version")
    If $ISOBJECT(after) {
        Set r.VersionAfter = ##class(Shutter.Util.Json).Str(after, "version")
        If '$ISOBJECT(before) Set r.ReceiverVersion = r.VersionAfter - 1
    }
    Set epoch = ##class(Shutter.Util.Json).Str(response, "epoch")
    If epoch '= "" Set r.Epoch = epoch
    Set r.ResponseJSON = ##class(Shutter.Util.Json).Text(response)
    Quit r.%Save()
}

Storage Default
{
<Data name="RehearsalDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Case</Value>
</Value>
<Value name="3">
<Value>Plan</Value>
</Value>
<Value name="4">
<Value>At</Value>
</Value>
<Value name="5">
<Value>HttpStatus</Value>
</Value>
<Value name="6">
<Value>WouldApply</Value>
</Value>
<Value name="7">
<Value>Reason</Value>
</Value>
<Value name="8">
<Value>ReceiverVersion</Value>
</Value>
<Value name="9">
<Value>VersionAfter</Value>
</Value>
<Value name="10">
<Value>Epoch</Value>
</Value>
<Value name="11">
<Value>ResponseJSON</Value>
</Value>
<Value name="12">
<Value>ExpectedVersion</Value>
</Value>
<Value name="13">
<Value>PayloadDigest</Value>
</Value>
</Data>
<DataLocation>^Shutter.Store.RehearsalD</DataLocation>
<DefaultData>RehearsalDefaultData</DefaultData>
<IdLocation>^Shutter.Store.RehearsalD</IdLocation>
<IndexLocation>^Shutter.Store.RehearsalI</IndexLocation>
<StreamLocation>^Shutter.Store.RehearsalS</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
