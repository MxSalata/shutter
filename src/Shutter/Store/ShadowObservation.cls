/// What a case's proposal gate saw in shadow mode, one row a plan: what was proposed and what the gate said, with nothing
/// sent. It is a record for the shadow report and authorises nothing.
Class Shutter.Store.ShadowObservation Extends %Persistent
{

Property CaseId As %String(MAXLEN = 32) [ Required ];

Property PlanId As %String(MAXLEN = 20);

/// The plan's version on the case: the round of the investigation.
Property Round As %Integer;

Property ObservedAt As %String(MAXLEN = 30);

Property Disposition As %String(MAXLEN = 32);

Property PlanOrigin As %String(MAXLEN = 100);

Property CatalogueEntry As %String(MAXLEN = 16);

Property GateOutcome As %String(MAXLEN = 16);

/// The failing checks' codes, comma separated.
Property BlockingCodes As %String(MAXLEN = 2000);

Property Mode As %String(MAXLEN = 16);

Property ControlGeneration As %Integer;

Index CaseIdx On CaseId;

/// Record what the proposal gate saw, when in shadow mode. It never stops a case: a row that cannot be written is logged.
ClassMethod Capture(case As Shutter.Store.Case, plan As Shutter.Store.Plan, result As Shutter.Msg.GateResult)
{
    Try {
        Quit:##class(Shutter.Util.RecoveryControl).Mode()'="shadow"
        Set o = ..%New()
        Set o.CaseId = case.CaseId, o.PlanId = plan.%Id(), o.Round = plan.Version, o.ObservedAt = ##class(Shutter.Util.Time).NowUTC()
        Set o.Disposition = plan.Disposition, o.PlanOrigin = plan.CreatedBy, o.CatalogueEntry = plan.CatalogueEntry
        Set o.GateOutcome = result.Outcome, o.BlockingCodes = ..FailingCodes(result.ChecksJSON), o.Mode = "shadow"
        Set o.ControlGeneration = ##class(Shutter.Util.RecoveryControl).Control().Generation
        $$$ThrowOnError(o.%Save())
    } Catch ex {
        Do ##class(Ens.Util.Log).LogWarning($CLASSNAME(), "Capture", "No shadow observation for " _ case.CaseId _ ": " _ ex.DisplayString())
    }
}

ClassMethod FailingCodes(checksJSON As %String) As %String [ Private ]
{
    Set checks = ##class(Shutter.Util.Json).Parse(checksJSON, .sc), codes = ""
    If '$ISOBJECT(checks) Quit ""
    Set it = checks.%GetIterator()
    While it.%GetNext(, .c) {
        Continue:(##class(Shutter.Util.Json).Str(c, "result") = "pass")
        Set code = ##class(Shutter.Util.Json).Str(c, "reason_code")
        If code '= "" Set codes = codes _ $SELECT(codes = "": "", 1: ",") _ code
    }
    Quit $EXTRACT(codes, 1, 2000)
}

/// What a case says when a plan that writes goes no further, or "" when recovery may go on.
ClassMethod Words(plan As Shutter.Store.Plan, result As Shutter.Msg.GateResult) As %String
{
    Set refusal = ##class(Shutter.Util.RecoveryControl).Refusal(.code)
    If code = "recovery_shadow" Quit "Shadow observation: nothing sent. Proposed outcome: " _ plan.Disposition _ ". Proposal gate: " _ result.Outcome _ ". A receiver rehearsal and final dispatch were not tested. This is not a verified recovery."
    If refusal '= "" Quit "Nothing sent: " _ refusal _ ". A person decides; reinvestigate once it is cleared."
    Quit ""
}

Storage Default
{
<Data name="ShadowObservationDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>CaseId</Value>
</Value>
<Value name="3">
<Value>PlanId</Value>
</Value>
<Value name="4">
<Value>Round</Value>
</Value>
<Value name="5">
<Value>ObservedAt</Value>
</Value>
<Value name="6">
<Value>Disposition</Value>
</Value>
<Value name="7">
<Value>PlanOrigin</Value>
</Value>
<Value name="8">
<Value>CatalogueEntry</Value>
</Value>
<Value name="9">
<Value>GateOutcome</Value>
</Value>
<Value name="10">
<Value>BlockingCodes</Value>
</Value>
<Value name="11">
<Value>Mode</Value>
</Value>
<Value name="12">
<Value>ControlGeneration</Value>
</Value>
</Data>
<DataLocation>^Shutter.Store.ShadowObser75F5D</DataLocation>
<DefaultData>ShadowObservationDefaultData</DefaultData>
<IdLocation>^Shutter.Store.ShadowObser75F5D</IdLocation>
<IndexLocation>^Shutter.Store.ShadowObser75F5I</IndexLocation>
<StreamLocation>^Shutter.Store.ShadowObser75F5S</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
