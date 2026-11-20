/// The form of Shutter's approval tasks in the Workflow inbox (CONTRACTS 6.4, 7.3): what the task is bound to, shown
/// read-only (Shutter.Process.TaskBinding), a link to the case or incident page in the web application, and the one
/// field the approver fills, Comment. For a case it shows the plan the approval releases: its version and disposition,
/// the exact action read from the plan the task was made for, the plan's digest, the evidence's digest, the rehearsal,
/// and the versions the decision rests on. The task names this page as its form template, and the inbox draws it with
/// the task in %task, below the task's message; the inbox then saves only the task's form fields, so nothing shown here
/// can be changed from the form, and approving takes Accept and Approve. Asked for as a page of its own, it answers 404.
Class Shutter.Process.ApprovalForm Extends %CSP.Page
{

Parameter CHARSET = "utf-8";

/// The text boxes' width: the pane's, at most a digest's length, so a narrow screen never scrolls sideways.
Parameter BOXSTYLE = "width:100%;max-width:78ch;box-sizing:border-box";

/// The web application's page for a case or an incident.
Parameter APPPAGE = "/shutter/index.html#/";

/// The page is only ever drawn inside the inbox's form, which calls OnPage and never OnPreHTTP.
ClassMethod OnPreHTTP() As %Boolean [ ServerOnly = 1 ]
{
    Set %response.Status = "404 Not Found"
    Quit 0
}

/// Writes the form for the task the inbox put in %task; nothing when there is none.
ClassMethod OnPage() As %Status [ ServerOnly = 1 ]
{
    If '$ISOBJECT($GET(%task)) Quit $$$OK
    Write ..FormHTML(%task)
    Quit $$$OK
}

/// The form's HTML for a task (EnsLib.Workflow.TaskResponse, or the request it came from): a table of what the task is
/// bound to, read-only, a link to the page in the web application, and the Comment field with the task's comment. A task
/// that is not bound (made before tasks were bound) shows only the comment, and its message says what to paste.
ClassMethod FormHTML(task As %Library.Persistent) As %String
{
    Set v = task.%FormValues, kind = v.GetAt("Shutter.Kind")
    Set html = "<table class=""shutterApproval"">"
    If kind = "incident" {
        Set html = html _ ..IncidentRows(v)
    } ElseIf (kind = "case") || (kind = "fhir") {
        Set html = html _ ..CaseRows(v, kind)
    }
    Set html = html _ "<tr><th scope=""row""><label for=""shutterComment"">Comment</label></th><td><input type=""text"" name=""Comment"" id=""shutterComment"" style=""" _ ..#BOXSTYLE _ """ value=""" _ ..Esc(v.GetAt("Comment")) _ """></td></tr>"
    If kind '= "" Set html = html _ "<tr><td></td><td>" _ ..Esc(..BoundWords(kind)) _ "</td></tr>"
    Quit html _ "</table>"
}

/// What the note under the form says the binding does.
ClassMethod BoundWords(kind As %String) As %String
{
    If kind = "incident" Quit "Bound on the server when the task was made. Approve releases exactly this plan, with nothing to paste; if the incident's plan has moved by then, these chains are not released and nothing is written."
    Quit "Bound on the server when the task was made. Approve releases exactly this plan, with nothing to paste; if any of it has moved by then (the plan, the case, the evidence, the receiver, the policy, the site profile or the catalogue), the case blocks and nothing is written."
}

/// The rows of a case's task: the binding, and the plan the binding names as its record reads.
ClassMethod CaseRows(v, kind As %String) As %String
{
    Set id = v.GetAt("Shutter.Case"), digest = v.GetAt("Shutter.PlanDigest"), receiver = v.GetAt("Shutter.ReceiverVersion")
    Set html = ..Row("Case", id _ ", version " _ v.GetAt("Shutter.CaseVersion"))
    Set plan = ""
    Try { Set plan = ##class(Shutter.Store.Plan).%OpenId(v.GetAt("Shutter.Plan")) } Catch ex { Set plan = "" }
    If '$ISOBJECT(plan) || (plan.Digest '= digest) {
        Set html = html _ ..Row("Plan", "v" _ v.GetAt("Shutter.PlanVersion") _ ": its record could not be read here, or no longer matches this task. Read the case before deciding; an approval of a plan that moved blocks the case.")
    } Else {
        Set html = html _ ..Row("Plan", "v" _ plan.Version _ " (" _ plan.Disposition _ ")")
        If kind = "fhir" {
            Set html = html _ ..Row("Exact action", "One update of the Encounter, sent with If-Match on ETag " _ receiver)
        } Else {
            Set html = html _ ..Row("Exact action", plan.ActionType _ " " _ plan.OperationKey _ " at receiver version " _ receiver)
        }
    }
    Set html = html _ ..Row("Plan digest", digest, 1)
    Set html = html _ ..Row("Evidence digest", v.GetAt("Shutter.SnapshotDigest"), 1)
    If kind = "fhir" {
        Set html = html _ ..Row("Dry run", "None exists for this receiver")
    } Else {
        Set html = html _ ..Row("Rehearsal", ..RehearsalWords(v.GetAt("Shutter.Rehearsal")))
    }
    Set html = html _ ..Row("Versions", "Receiver version " _ receiver _ $SELECT(v.GetAt("Shutter.ReceiverEpoch") '= "": " in epoch " _ v.GetAt("Shutter.ReceiverEpoch"), 1: "") _ ", gate policy " _ v.GetAt("Shutter.Policy") _ ", site profile v" _ v.GetAt("Shutter.SiteProfile"))
    Quit html _ ..LinkRow("cases/" _ id, "Open the case in Shutter")
}

/// The rehearsal a task binds, in words.
ClassMethod RehearsalWords(rehearsalId As %String) As %String
{
    If rehearsalId = "" Quit "None bound"
    Set r = ""
    Try { Set r = ##class(Shutter.Store.Rehearsal).%OpenId(rehearsalId) } Catch ex { Set r = "" }
    If '$ISOBJECT(r) Quit "Rehearsal " _ rehearsalId _ " (its record could not be read here)"
    Quit "Rehearsal " _ rehearsalId _ ": " _ $SELECT(r.WouldApply: "would apply (rolled back)", 1: "would not apply")
}

/// The rows of an incident's task: the incident, the chain, the plan's digest and the versions its plan names.
ClassMethod IncidentRows(v) As %String
{
    Set id = v.GetAt("Shutter.Incident"), seq = v.GetAt("Shutter.Chain")
    Set html = ..Row("Incident", id _ $SELECT(seq '= "": ", chain " _ seq, 1: ", the chains under one approval"))
    Set html = html _ ..Row("Plan digest", v.GetAt("Shutter.PlanDigest"), 1)
    Set inc = ""
    Try { Set inc = ##class(Shutter.Store.Incident).ByIncidentId(id) } Catch ex { Set inc = "" }
    If $ISOBJECT(inc) && (inc.PlanDigest = v.GetAt("Shutter.PlanDigest")) {
        Set html = html _ ..Row("Versions", "Catalogue " _ $EXTRACT(inc.CatalogueVersion, 1, 240) _ ", site profile v" _ inc.ProfileVersion _ ", gate policy " _ inc.PolicyVersion)
    }
    Quit html _ ..LinkRow("incidents/" _ id, "Open the incident in Shutter")
}

/// A row of the table: a label and a value, read-only. A digest is a read-only text box with no name, so it can be
/// selected and copied and is never sent with the form; its label names it for a screen reader.
ClassMethod Row(label As %String, value As %String, box As %Boolean = 0) As %String
{
    Set shown = ..Esc(value), words = ..Esc(label)
    If box Set shown = "<input type=""text"" readonly aria-label=""" _ words _ """ style=""" _ ..#BOXSTYLE _ """ value=""" _ shown _ """>"
    Quit "<tr><th scope=""row"">" _ words _ "</th><td>" _ shown _ "</td></tr>"
}

/// A row with a link to a page of the web application, opened beside the inbox.
ClassMethod LinkRow(path As %String, words As %String) As %String
{
    Quit "<tr><td></td><td><a href=""" _ ..Esc(..#APPPAGE _ path) _ """ target=""_blank"" rel=""noopener"">" _ ..Esc(words) _ "</a></td></tr>"
}

/// Text escaped for HTML, quotes included.
ClassMethod Esc(text As %String) As %String
{
    Quit $ZCONVERT(text, "O", "HTML")
}

}
