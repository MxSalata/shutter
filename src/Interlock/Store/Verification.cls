/// What the verifier established after an attempt, or after a non-write disposition: the committed
/// history, the receipt, and whether the intended effect holds. "Acknowledged" is never "verified".
Class Interlock.Store.Verification Extends (%Persistent, %JSON.Adaptor)
{

Property Case As Interlock.Store.Case(%JSONFIELDNAME = "caseId", %JSONREFERENCE = "ID") [ Required ];

Index CaseIdx On Case;

Property Attempt As Interlock.Store.ExecutionAttempt(%JSONFIELDNAME = "attemptId", %JSONREFERENCE = "ID");

Property At As %String(%JSONFIELDNAME = "at", MAXLEN = 30);

/// verified, superseded_after, unresolved, failed.
Property Outcome As %String(%JSONFIELDNAME = "outcome", MAXLEN = 32);

Property Summary As %String(%JSONFIELDNAME = "summary", MAXLEN = 2000);

Property DetailJSON As %String(%JSONFIELDNAME = "detail", MAXLEN = "");

ClassMethod Create(case As Interlock.Store.Case, attempt As Interlock.Store.ExecutionAttempt, outcome As %String, summary As %String, detail As %DynamicObject, Output v As Interlock.Store.Verification) As %Status
{
    Set v = ..%New()
    Set v.Case = case
    If $ISOBJECT(attempt) Set v.Attempt = attempt
    Set v.At = ##class(Interlock.Util.Time).NowUTC(), v.Outcome = outcome, v.Summary = $EXTRACT(summary, 1, 2000)
    Set v.DetailJSON = ##class(Interlock.Util.Json).Text(detail)
    Quit v.%Save()
}

Storage Default
{
<Data name="VerificationDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Case</Value>
</Value>
<Value name="3">
<Value>Attempt</Value>
</Value>
<Value name="4">
<Value>At</Value>
</Value>
<Value name="5">
<Value>Outcome</Value>
</Value>
<Value name="6">
<Value>Summary</Value>
</Value>
<Value name="7">
<Value>DetailJSON</Value>
</Value>
</Data>
<DataLocation>^Interlock.Store.VerificationD</DataLocation>
<DefaultData>VerificationDefaultData</DefaultData>
<IdLocation>^Interlock.Store.VerificationD</IdLocation>
<IndexLocation>^Interlock.Store.VerificationI</IndexLocation>
<StreamLocation>^Interlock.Store.VerificationS</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
