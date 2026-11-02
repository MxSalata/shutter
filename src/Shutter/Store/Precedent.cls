/// A precedent: what a person decided before on the same evidence at the same receiver, and whether it held
/// (CONTRACTS 6.4, v1.35). A row is written when an approved plan's resend was verified at the receiver (an approval
/// that worked), and when an approver rejected a plan. The site's automatic releases (approver "policy") write none:
/// they are the policy, not a precedent. The signature is the receiver and the snapshot's condition vocabulary
/// (6.1), canonical JSON hashed: exact, like the message index, because a near match would be another situation.
/// The approver reads the count in the task's text and the app; a model never does (the model view's allowlist
/// leaves the summary's "precedents" out), so a run of approvals cannot anchor the board.
Class Shutter.Store.Precedent Extends (%Persistent, %JSON.Adaptor)
{

Property CaseId As %String(%JSONFIELDNAME = "caseId", MAXLEN = 32) [ Required ];

Index CaseIdx On CaseId;

Property Receiver As %String(%JSONFIELDNAME = "receiver", MAXLEN = 128);

/// SHA-256 of the canonical conditions, so that two snapshots with the same vocabulary values share one signature.
Property Signature As %String(%JSONFIELDNAME = "signature", MAXLEN = 80);

Index SignatureIdx On (Receiver, Signature);

/// The conditions as the snapshot showed them (6.1), for the app to display beside the count.
Property ConditionsJSON As %String(%JSONFIELDNAME = "conditions", MAXLEN = "");

Property CatalogueEntry As %String(%JSONFIELDNAME = "catalogueEntry", MAXLEN = 16);

Property CatalogueOutcome As %String(%JSONFIELDNAME = "catalogueOutcome", MAXLEN = 32);

Property Disposition As %String(%JSONFIELDNAME = "disposition", MAXLEN = 32);

Property PlanDigest As %String(%JSONFIELDNAME = "planDigest", MAXLEN = 80);

Property Approver As %String(%JSONFIELDNAME = "approver", MAXLEN = 100);

/// approved: the person approved and the resend was verified at the receiver. rejected: the person rejected the plan.
Property Decision As %String(%JSONFIELDNAME = "decision", MAXLEN = 16, VALUELIST = ",approved,rejected");

Property PolicyVersion As %String(%JSONFIELDNAME = "policyVersion", MAXLEN = 32);

Property SiteProfileVersion As %String(%JSONFIELDNAME = "siteProfileVersion", MAXLEN = 32);

Property CatalogueVersion As %String(%JSONFIELDNAME = "catalogueVersion", MAXLEN = 400);

Property CreatedAt As %String(%JSONFIELDNAME = "createdAt", MAXLEN = 30);

Index CreatedIdx On CreatedAt;

/// A retired precedent stays on record but counts for nothing.
Property Active As %Boolean(%JSONFIELDNAME = "active") [ InitialExpression = 1 ];

Property RetiredAt As %String(%JSONFIELDNAME = "retiredAt", MAXLEN = 30);

Property RetiredBy As %String(%JSONFIELDNAME = "retiredBy", MAXLEN = 100);

Property RetiredReason As %String(%JSONFIELDNAME = "retiredReason", MAXLEN = 500);

/// Default window: a precedent older than this many days counts for nothing (^Shutter.Config("precedentDays")).
Parameter DEFAULTDAYS = 180;

/// How many days back a precedent counts: ^Shutter.Config("precedentDays"), 1 to 3650, 180 by default.
ClassMethod Days() As %Integer
{
    Set d = $GET(^Shutter.Config("precedentDays"))
    If (d '? 1.N) || (d < 1) || (d > 3650) Quit ..#DEFAULTDAYS
    Quit +d
}

/// The signature of a receiver and a conditions object: the receiver's name, then the SHA-256 of the canonical
/// conditions (keys sorted), so key order and whitespace never make two signatures of one situation.
ClassMethod SignatureOf(conditions As %DynamicObject) As %String
{
    If '$ISOBJECT(conditions) Quit ""
    Quit ##class(Shutter.Util.Digest).OfObject(conditions)
}

/// The conditions of a case's current snapshot (its summary's catalogue.conditions), or "" when it has none.
ClassMethod ConditionsOf(case As Shutter.Store.Case) As %DynamicObject
{
    If '$ISOBJECT(case) || '$ISOBJECT(case.CurrentSnapshot) Quit ""
    Set summary = ""
    Try { Set summary = case.CurrentSnapshot.SummaryObject() } Catch ex { Set summary = "" }
    If '$ISOBJECT(summary) Quit ""
    Set cat = summary.%Get("catalogue")
    If '$ISOBJECT(cat) Quit ""
    Set c = cat.%Get("conditions")
    Quit $SELECT($ISOBJECT(c): c, 1: "")
}

/// Record a case's decision as a precedent, from its current snapshot, the plan and the approval of record. Nothing
/// is written for an automatic release (approver "policy"), for a case with no snapshot conditions, or when the same
/// case and plan digest were recorded already (a verification read twice writes one row).
ClassMethod Record(case As Shutter.Store.Case, plan As Shutter.Store.Plan, approval As Shutter.Store.Approval, decision As %String, Output p As Shutter.Store.Precedent) As %Status
{
    Set p = ""
    If '$ISOBJECT(case) || '$ISOBJECT(plan) || '$ISOBJECT(approval) Quit $$$OK
    If (approval.Approver = "") || (approval.Approver = "policy") Quit $$$OK
    Set conditions = ..ConditionsOf(case)
    If '$ISOBJECT(conditions) Quit $$$OK
    Set entry = "", outcome = ""
    Try {
        Set cat = case.CurrentSnapshot.SummaryObject().%Get("catalogue")
        If $ISOBJECT(cat) Set entry = ##class(Shutter.Util.Json).Str(cat, "entry"), outcome = ##class(Shutter.Util.Json).Str(cat, "outcome")
    } Catch ex {}
    Set caseId = case.CaseId, digest = plan.Digest, existing = ""
    &sql(SELECT TOP 1 ID INTO :existing FROM Shutter_Store.Precedent WHERE CaseId = :caseId AND PlanDigest = :digest AND Decision = :decision)
    If (SQLCODE = 0) && (existing '= "") Quit $$$OK
    Quit ..RecordValues(case.CaseId, case.Receiver, conditions, entry, outcome, plan.Disposition, plan.Digest, approval.Approver, decision, approval.PolicyVersion, approval.SiteProfileVersion, .p)
}

/// Write one precedent from its values (the writer above, and the unit test).
ClassMethod RecordValues(caseId As %String, receiver As %String, conditions As %DynamicObject, entry As %String, outcome As %String, disposition As %String, planDigest As %String, approver As %String, decision As %String, policyVersion As %String = "", siteProfileVersion As %String = "", Output p As Shutter.Store.Precedent) As %Status
{
    If '$LISTFIND($LISTBUILD("approved", "rejected"), decision) Quit $$$ERROR($$$GeneralError, "a precedent's decision is approved or rejected, not " _ decision)
    If '$ISOBJECT(conditions) Quit $$$ERROR($$$GeneralError, "a precedent needs the snapshot's conditions")
    Set p = ..%New()
    Set p.CaseId = caseId, p.Receiver = receiver
    Set p.Signature = ..SignatureOf(conditions), p.ConditionsJSON = conditions.%ToJSON()
    Set p.CatalogueEntry = entry, p.CatalogueOutcome = outcome, p.Disposition = disposition, p.PlanDigest = planDigest
    Set p.Approver = approver, p.Decision = decision
    Set p.PolicyVersion = policyVersion, p.SiteProfileVersion = siteProfileVersion
    Try { Set p.CatalogueVersion = $EXTRACT(##class(Shutter.Catalogue.Entry).CatalogueVersion(), 1, 400) } Catch ex { Set p.CatalogueVersion = "" }
    Set p.CreatedAt = ##class(Shutter.Util.Time).NowUTC()
    Quit p.%Save()
}

/// What the precedents say for a receiver and a conditions object, within the window: the counts of approved (and
/// verified) and rejected decisions, the last decision and who made it, and whether that last decision was taken
/// under the policy and site profile versions in force now (samePolicy). Retired rows and rows older than the window
/// count for nothing. Never an error: a lookup that fails answers the empty summary with "error".
ClassMethod Summary(receiver As %String, conditions As %DynamicObject) As %DynamicObject
{
    Set out = {"approved": 0, "rejected": 0, "lastDecision": "", "lastApprover": "", "lastAt": "", "lastCaseId": "", "samePolicy": false, "windowDays": (..Days()), "signature": ""}
    If '$ISOBJECT(conditions) Quit out
    Set sig = ..SignatureOf(conditions)
    Set out.signature = sig
    Try {
        Set since = ##class(Shutter.Util.Time).FromNow(-86400 * ..Days())
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.Precedent WHERE Receiver = ? AND Signature = ? AND Active = 1 AND CreatedAt >= ? ORDER BY CreatedAt DESC, ID DESC", receiver, sig, since)
        Set policy = ##class(Shutter.Operation.Gate).#POLICYVERSION
        Set profile = ##class(Shutter.Util.Json).Str(##class(Shutter.Store.SiteProfile).Current(), "version", 0)
        Set first = 1
        While rs.%Next() {
            Set p = ..%OpenId(rs.%Get("ID"))
            Continue:'$ISOBJECT(p)
            If p.Decision = "approved" { Set out.approved = out.approved + 1 } Else { Set out.rejected = out.rejected + 1 }
            If first {
                Set first = 0
                Set out.lastDecision = p.Decision, out.lastApprover = p.Approver, out.lastAt = p.CreatedAt, out.lastCaseId = p.CaseId
                Do out.%Set("samePolicy", (p.PolicyVersion = policy) && (p.SiteProfileVersion = profile), "boolean")
            }
        }
    } Catch ex {
        Set out.error = ex.DisplayString()
    }
    Quit out
}

/// The summary for a case's current snapshot.
ClassMethod SummaryFor(case As Shutter.Store.Case) As %DynamicObject
{
    If '$ISOBJECT(case) Quit ..Summary("", "")
    Quit ..Summary(case.Receiver, ..ConditionsOf(case))
}

/// The precedents in words, for the approval task's text: "" when there is none to tell.
ClassMethod Words(summary As %DynamicObject) As %String
{
    If '$ISOBJECT(summary) Quit ""
    Set approved = +summary.%Get("approved"), rejected = +summary.%Get("rejected")
    If (approved = 0) && (rejected = 0) Quit "Precedents: none; these conditions at this receiver have not reached an approver in the last " _ summary.%Get("windowDays") _ " days."
    Set text = "Precedents: approved and verified " _ approved _ " time" _ $SELECT(approved = 1: "", 1: "s") _ ", rejected " _ rejected _ " time" _ $SELECT(rejected = 1: "", 1: "s") _ " in the last " _ summary.%Get("windowDays") _ " days"
    Set text = text _ "; last " _ summary.%Get("lastDecision") _ " by " _ summary.%Get("lastApprover") _ " on " _ $EXTRACT(summary.%Get("lastAt"), 1, 10) _ " (case " _ summary.%Get("lastCaseId") _ ")"
    If 'summary.%Get("samePolicy") Set text = text _ ", under an earlier policy or site profile"
    Quit text _ "."
}

/// The precedents a case's conditions match, newest first, with its own rows included: for the API.
ClassMethod RowsFor(case As Shutter.Store.Case) As %DynamicArray
{
    Set out = []
    If '$ISOBJECT(case) Quit out
    Set conditions = ..ConditionsOf(case)
    If '$ISOBJECT(conditions) Quit out
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.Precedent WHERE Receiver = ? AND Signature = ? ORDER BY CreatedAt DESC, ID DESC", case.Receiver, ..SignatureOf(conditions))
    While rs.%Next() {
        Set p = ..%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(p)
        Do out.%Push(p.Projection())
    }
    Quit out
}

/// The row as JSON, with the conditions as an object.
Method Projection() As %DynamicObject
{
    Set sc = ..%JSONExportToString(.json)
    Set o = ##class(%DynamicObject).%FromJSON($SELECT($$$ISOK(sc): json, 1: "{}"))
    Set o.id = ..%Id()
    If o.%GetTypeOf("conditions") = "string" Set o.conditions = ##class(Shutter.Util.Json).Parse(o.conditions, .psc)
    Quit o
}

/// Retire a precedent: it stays on record and counts for nothing. Returns "" when done, "not_found" or "already_retired".
ClassMethod Retire(id As %String, by As %String, reason As %String = "", Output p As Shutter.Store.Precedent) As %String
{
    Set p = ..%OpenId(id)
    If '$ISOBJECT(p) Quit "not_found"
    If 'p.Active Quit "already_retired"
    Set p.Active = 0, p.RetiredAt = ##class(Shutter.Util.Time).NowUTC(), p.RetiredBy = by, p.RetiredReason = $EXTRACT(reason, 1, 500)
    Set sc = p.%Save()
    Quit $SELECT($$$ISOK(sc): "", 1: $SYSTEM.Status.GetErrorText(sc))
}

Storage Default
{
<Data name="PrecedentDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>CaseId</Value>
</Value>
<Value name="3">
<Value>Receiver</Value>
</Value>
<Value name="4">
<Value>Signature</Value>
</Value>
<Value name="5">
<Value>ConditionsJSON</Value>
</Value>
<Value name="6">
<Value>CatalogueEntry</Value>
</Value>
<Value name="7">
<Value>CatalogueOutcome</Value>
</Value>
<Value name="8">
<Value>Disposition</Value>
</Value>
<Value name="9">
<Value>PlanDigest</Value>
</Value>
<Value name="10">
<Value>Approver</Value>
</Value>
<Value name="11">
<Value>Decision</Value>
</Value>
<Value name="12">
<Value>PolicyVersion</Value>
</Value>
<Value name="13">
<Value>SiteProfileVersion</Value>
</Value>
<Value name="14">
<Value>CatalogueVersion</Value>
</Value>
<Value name="15">
<Value>CreatedAt</Value>
</Value>
<Value name="16">
<Value>Active</Value>
</Value>
<Value name="17">
<Value>RetiredAt</Value>
</Value>
<Value name="18">
<Value>RetiredBy</Value>
</Value>
<Value name="19">
<Value>RetiredReason</Value>
</Value>
</Data>
<DataLocation>^Shutter.Store.PrecedentD</DataLocation>
<DefaultData>PrecedentDefaultData</DefaultData>
<IdLocation>^Shutter.Store.PrecedentD</IdLocation>
<IndexLocation>^Shutter.Store.PrecedentI</IndexLocation>
<StreamLocation>^Shutter.Store.PrecedentS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
