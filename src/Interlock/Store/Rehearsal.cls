/// A rehearsal: the exact planned write sent to the receiver as a dry run, which it validates and
/// rolls back. Evidence about what would happen now, not a guarantee about later.
Class Interlock.Store.Rehearsal Extends (%Persistent, %JSON.Adaptor)
{

Property Case As Interlock.Store.Case(%JSONFIELDNAME = "caseId", %JSONREFERENCE = "ID") [ Required ];

Index CaseIdx On Case;

Property Plan As Interlock.Store.Plan(%JSONFIELDNAME = "planId", %JSONREFERENCE = "ID");

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

ClassMethod Create(case As Interlock.Store.Case, plan As Interlock.Store.Plan, httpStatus As %Integer, response As %DynamicObject, Output r As Interlock.Store.Rehearsal) As %Status
{
    Set r = ..%New()
    Set r.Case = case, r.Plan = plan, r.At = ##class(Interlock.Util.Time).NowUTC(), r.HttpStatus = httpStatus
    Set r.WouldApply = ##class(Interlock.Util.Json).Bool(response, "would_apply")
    Set r.Reason = ##class(Interlock.Util.Json).Str(response, "reason")
    Set before = response.%Get("encounter_before"), after = response.%Get("encounter_after")
    If $ISOBJECT(before) Set r.ReceiverVersion = ##class(Interlock.Util.Json).Str(before, "version")
    If $ISOBJECT(after) {
        Set r.VersionAfter = ##class(Interlock.Util.Json).Str(after, "version")
        If '$ISOBJECT(before) Set r.ReceiverVersion = r.VersionAfter - 1
    }
    Set epoch = ##class(Interlock.Util.Json).Str(response, "epoch")
    If epoch '= "" Set r.Epoch = epoch
    Set r.ResponseJSON = ##class(Interlock.Util.Json).Text(response)
    Quit r.%Save()
}

}
