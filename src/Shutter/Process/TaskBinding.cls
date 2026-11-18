/// What an approval task in the Workflow inbox is bound to (CONTRACTS 6.4, 7.3), written on the task request on the
/// server when the workflow makes it, and checked when the task is answered. The Workflow engine copies the request's
/// form values to the task, and the inbox's submit writes back only the fields named in %FormFields, which is Comment
/// alone; the workflow reads the binding from the request it sent, never from the answer, so nothing an approver or a
/// changed form sends can move it. An approval from the inbox names no digest: it approves what the task is bound to,
/// and only while nothing bound has moved (CaseMoved, IncidentMoved), else the case blocks (or the chains are rejected)
/// with nothing written. An answer that names a digest (the web application's and SQL's, through
/// Shutter.Util.Workflow.Decide) is checked as before: the route's own checks, then that digest against the plan.
Class Shutter.Process.TaskBinding Extends %RegisteredObject
{

/// The form page the bound tasks name, which the inbox resolves against its own application (Shutter.Process.ApprovalForm).
Parameter TEMPLATE = "Shutter.Process.ApprovalForm.cls";

/// Binds a case's approval task (kind "case", or "fhir" for a FHIR receiver's update): the case and its version; the
/// plan's id, version and digest; the evidence (the case's current snapshot: its id, digest and material digest); the
/// rehearsal (its id, "" for a receiver with no dry run); the receiver version the plan is conditioned on (for a FHIR
/// receiver, the ETag) and the receiver's epoch; the policy version of the gate that decides; the site profile's version
/// and a digest of the catalogue's version. The form shows these and takes only a comment.
ClassMethod BindCase(task As EnsLib.Workflow.TaskRequest, kind As %String, case As Shutter.Store.Case, plan As Shutter.Store.Plan, rehearsalId As %String, receiverVersion As %String, epoch As %String, policyVersion As %String)
{
    Set v = task.%FormValues, snap = case.CurrentSnapshot
    Do v.SetAt(kind, "Shutter.Kind")
    Do v.SetAt(case.CaseId, "Shutter.Case")
    Do v.SetAt(case.Version, "Shutter.CaseVersion")
    Do v.SetAt(plan.%Id(), "Shutter.Plan")
    Do v.SetAt(plan.Version, "Shutter.PlanVersion")
    Do v.SetAt(plan.Digest, "Shutter.PlanDigest")
    Do v.SetAt($SELECT($ISOBJECT(snap): snap.%Id(), 1: ""), "Shutter.Snapshot")
    Do v.SetAt($SELECT($ISOBJECT(snap): snap.Digest, 1: ""), "Shutter.SnapshotDigest")
    Do v.SetAt($SELECT($ISOBJECT(snap): snap.MaterialDigest, 1: ""), "Shutter.MaterialDigest")
    Do v.SetAt(rehearsalId, "Shutter.Rehearsal")
    Do v.SetAt(receiverVersion, "Shutter.ReceiverVersion")
    Do v.SetAt(epoch, "Shutter.ReceiverEpoch")
    Do v.SetAt(policyVersion, "Shutter.Policy")
    Do v.SetAt(..ProfileVersion(), "Shutter.SiteProfile")
    Do v.SetAt(..CatalogueDigest(), "Shutter.Catalogue")
    Set task.%FormFields = "Comment"
    Set task.%FormTemplate = ..#TEMPLATE
}

/// Binds an incident's approval task (kind "incident"): the incident, the chain (seq, "" for the chains under one
/// approval) and the incident plan's digest, which holds every chain's first expected version and the receiver's epoch.
/// The catalogue, site profile and gate policy the incident plan names are checked again at each item's dispatch (7.4).
/// The incident's own version is not bound: it moves while other chains release with a task open.
ClassMethod BindIncident(task As EnsLib.Workflow.TaskRequest, incident As Shutter.Store.Incident, seq As %String)
{
    Set v = task.%FormValues
    Do v.SetAt("incident", "Shutter.Kind")
    Do v.SetAt(incident.IncidentId, "Shutter.Incident")
    Do v.SetAt(seq, "Shutter.Chain")
    Do v.SetAt(incident.PlanDigest, "Shutter.PlanDigest")
    Set task.%FormFields = "Comment"
    Set task.%FormTemplate = ..#TEMPLATE
}

/// Whether <var>sent</var>, the request the workflow sent, is a bound task: a task made before tasks were bound (one
/// still open across an upgrade) is not, and is decided as it was, by the digest its answer names.
ClassMethod IsBound(sent As %Library.Persistent) As %Boolean
{
    If '$ISOBJECT(sent) || 'sent.%IsA("EnsLib.Workflow.TaskRequest") Quit 0
    Quit sent.%FormValues.GetAt("Shutter.PlanDigest") '= ""
}

/// The digest a bound task approves, read from the request the workflow sent; "" when it is not bound.
ClassMethod BoundDigest(sent As %Library.Persistent) As %String
{
    Quit $SELECT(..IsBound(sent): sent.%FormValues.GetAt("Shutter.PlanDigest"), 1: "")
}

/// What moved since a case's approval task was made, in words, or "" when its binding holds: the request the workflow
/// sent (<var>sent</var>, bound by BindCase) against the case now, the plan the workflow holds, the rehearsal of that
/// plan now (<var>rehearsalId</var>), the receiver version and epoch the workflow holds and the policy version of the
/// gate. The evidence keeps the binding when only its non-material part was refreshed (A7). A request that is not bound
/// gives "the task is not bound": the caller asks IsBound first.
ClassMethod CaseMoved(sent As %Library.Persistent, case As Shutter.Store.Case, plan As Shutter.Store.Plan, rehearsalId As %String, receiverVersion As %String, epoch As %String, policyVersion As %String) As %String
{
    If '..IsBound(sent) Quit "the task is not bound"
    Set v = sent.%FormValues, moved = ""
    If v.GetAt("Shutter.Case") '= case.CaseId Set moved = moved _ "; the task is for case " _ v.GetAt("Shutter.Case")
    Set planId = $SELECT($ISOBJECT(plan): plan.%Id(), 1: ""), planVersion = $SELECT($ISOBJECT(plan): plan.Version, 1: ""), planDigest = $SELECT($ISOBJECT(plan): plan.Digest, 1: "")
    Set made = "the task was made for plan v" _ v.GetAt("Shutter.PlanVersion") _ " (" _ $EXTRACT(v.GetAt("Shutter.PlanDigest"), 1, 19) _ ")"
    If (v.GetAt("Shutter.Plan") '= planId) || (v.GetAt("Shutter.PlanVersion") '= planVersion) || (v.GetAt("Shutter.PlanDigest") '= planDigest) {
        Set moved = moved _ "; the plan moved: " _ made _ ", the case's plan is " _ $SELECT(planDigest '= "": "v" _ planVersion _ " (" _ $EXTRACT(planDigest, 1, 19) _ ")", 1: "gone")
    } ElseIf (case.CurrentPlanGetObjectId() '= "") && (case.CurrentPlanGetObjectId() '= v.GetAt("Shutter.Plan")) {
        // The case's own current plan as well as the workflow's: the two are set together, so this only names a case
        // whose plan another path replaced.
        Set moved = moved _ "; the plan moved: " _ made _ ", the case's current plan is another (" _ case.CurrentPlanGetObjectId() _ ")"
    }
    If v.GetAt("Shutter.CaseVersion") '= case.Version Set moved = moved _ "; the case moved: version " _ v.GetAt("Shutter.CaseVersion") _ " when the task was made, " _ case.Version _ " now"
    Set snap = case.CurrentSnapshot
    Set digest = $SELECT($ISOBJECT(snap): snap.Digest, 1: ""), material = $SELECT($ISOBJECT(snap): snap.MaterialDigest, 1: "")
    If (v.GetAt("Shutter.SnapshotDigest") '= digest) && ((v.GetAt("Shutter.MaterialDigest") = "") || (v.GetAt("Shutter.MaterialDigest") '= material)) {
        Set moved = moved _ "; the evidence moved: snapshot " _ ..Short(v.GetAt("Shutter.SnapshotDigest")) _ " when the task was made, " _ ..Short(digest) _ " now"
    }
    Set moved = moved _ ..Differs("the rehearsal", v.GetAt("Shutter.Rehearsal"), rehearsalId)
    Set moved = moved _ ..Differs("the receiver version", v.GetAt("Shutter.ReceiverVersion"), receiverVersion)
    Set moved = moved _ ..Differs("the receiver's epoch", v.GetAt("Shutter.ReceiverEpoch"), epoch)
    Set moved = moved _ ..Differs("the gate's policy", v.GetAt("Shutter.Policy"), policyVersion)
    Set moved = moved _ ..Differs("the site profile", v.GetAt("Shutter.SiteProfile"), ..ProfileVersion())
    If v.GetAt("Shutter.Catalogue") '= ..CatalogueDigest() Set moved = moved _ "; the catalogue moved since the task was made"
    Quit $EXTRACT(moved, 3, *)
}

/// What moved since an incident's approval task was made, in words, or "" when its binding holds: the request the
/// workflow sent (bound by BindIncident) against the incident now and the chain the answer is for.
ClassMethod IncidentMoved(sent As %Library.Persistent, incident As Shutter.Store.Incident, seq As %String) As %String
{
    If '..IsBound(sent) Quit "the task is not bound"
    Set v = sent.%FormValues, moved = ""
    If v.GetAt("Shutter.Incident") '= incident.IncidentId Set moved = moved _ "; the task is for incident " _ v.GetAt("Shutter.Incident")
    If v.GetAt("Shutter.Chain") '= seq Set moved = moved _ "; the task is for " _ $SELECT(v.GetAt("Shutter.Chain") '= "": "chain " _ v.GetAt("Shutter.Chain"), 1: "the chains under one approval")
    If v.GetAt("Shutter.PlanDigest") '= incident.PlanDigest Set moved = moved _ "; the plan moved: the task was made for " _ ..Short(v.GetAt("Shutter.PlanDigest")) _ ", the incident's plan is " _ ..Short(incident.PlanDigest)
    Quit $EXTRACT(moved, 3, *)
}

/// "; <what> moved: <was> when the task was made, <now> now" when the two differ, else "".
ClassMethod Differs(what As %String, was As %String, now As %String) As %String [ Private ]
{
    If was = now Quit ""
    Quit "; " _ what _ " moved: " _ $SELECT(was = "": "none", 1: was) _ " when the task was made, " _ $SELECT(now = "": "none", 1: now) _ " now"
}

/// The first 19 characters of a digest ("sha256:" and 12 hex), or "none".
ClassMethod Short(digest As %String) As %String
{
    Quit $SELECT(digest = "": "none", 1: $EXTRACT(digest, 1, 19))
}

/// The current site profile's version.
ClassMethod ProfileVersion() As %String
{
    Quit ##class(Shutter.Util.Json).Str(##class(Shutter.Store.SiteProfile).Current(), "version", 0)
}

/// A digest of the catalogue's version (the shipped entries' ids and versions and the site's own): the version itself
/// can be longer than a form value is meant to hold.
ClassMethod CatalogueDigest() As %String
{
    Quit ##class(Shutter.Util.Digest).SHA256Hex(##class(Shutter.Catalogue.Entry).CatalogueVersion())
}

}
