/// The approval task of an incident at any size (CONTRACTS 7.3): the task always fits the engine's limits, names the
/// counts, the digest, the first chains and how many more, and points to the incident page; the digest binds the chains
/// it does not list; and an error raising a task stops for a person, naming the incident, instead of closing it. Every
/// incident here takes an UT-INC- id, so a run cut off is cleared by Shutter.Test.IncidentPlan too, and each test deletes
/// its own rows. Nothing is sent to the production: the workflow is Shutter.Test.FakeIncidentWorkflow.
Class Shutter.Test.IncidentTask Extends %UnitTest.TestCase
{

/// The incidents made by the current test, for the clean-up.
Property Made As %String [ MultiDimensional ];

/// Whether this run made the approval target's Workflow role, where no install had (it is removed afterwards).
Property MadeRole As %Boolean [ InitialExpression = 0 ];

/// The workflow raises a task only for a Workflow role that exists (IncidentTaskCheck.RoleMissing): the role of the
/// workflow's own approval target, which an install makes, is made here for the run where it is missing.
Method OnBeforeAllTests() As %Status
{
    Set role = ##class(Shutter.Process.IncidentWorkflow).%New("Incident Workflow").ApprovalTarget
    If '##class(EnsLib.Workflow.RoleDefinition).%ExistsId(role) {
        Set sc = ##class(EnsLib.Workflow.RoleDefinition).CreateRole(role)
        Quit:$$$ISERR(sc) sc
        Set ..MadeRole = 1
    }
    Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
    If ..MadeRole Do ##class(EnsLib.Workflow.RoleDefinition).%DeleteId(##class(Shutter.Process.IncidentWorkflow).%New("Incident Workflow").ApprovalTarget)
    Quit $$$OK
}

Method OnAfterOneTest() As %Status
{
    Set id = ""
    For {
        Set id = $ORDER(i%Made(id))
        Quit:id=""
        Do ##class(Shutter.Test.IncidentPlan).Purge(id)
    }
    Kill i%Made
    Quit $$$OK
}

/// The limits the task's text is held to are the engine's own, on whichever image this runs.
Method TestTheLimitIsTheEngines()
{
    Set limit = $PARAMETER("Shutter.Process.IncidentTaskText", "MESSAGELIMIT")
    Do $$$AssertTrue(limit > 0, "the text has a limit")
    For class = "EnsLib.Workflow.TaskRequest", "EnsLib.Workflow.TaskResponse" {
        Set p = ##class(%Dictionary.CompiledProperty).%OpenId(class _ "||%Message")
        Do $$$AssertTrue($ISOBJECT(p), class _ " has a message property")
        Continue:'$ISOBJECT(p)
        Set max = p.Parameters.GetAt("MAXLEN")
        Do $$$AssertTrue((max = "") || (limit <= max), class _ " takes the text: its limit is " _ max _ ", the text's " _ limit)
    }
}

/// Four chains of two fit, as ever: every chain and item is listed and nothing points elsewhere.
Method TestAFewChainsAreAllListed()
{
    Set inc = ..NewIncident(4, 2)
    Set wf = ..Workflow(inc)
    Do $$$AssertStatusOK(wf.AskApproval(inc, inc.ChainList(), ""), "the task is raised")
    Do $$$AssertEquals(wf.PendingTasks, 1, "one task")
    Set msg = wf.LastTask.%Message
    For seq = 1:1:4 Do $$$AssertTrue(msg [ ($CHAR(10) _ "Chain " _ seq _ " ("), "chain " _ seq _ " is listed")
    Do $$$AssertTrue(msg [ (inc.IncidentId _ "-4-2"), "with the last item")
    Do $$$AssertNotTrue(msg [ "/shutter/index.html#/incidents/", "and nothing points elsewhere")
    Do $$$AssertTrue(msg [ ("Plan digest: " _ inc.PlanDigest), "the digest is there")
}

/// Thirty chains under one approval raise one task that fits: the counts, the whole digest, the first chains, how many
/// more, the incident page, and the instruction the inbox's approver needs.
Method TestAStormRaisesOneTaskThatFits()
{
    Set inc = ..NewIncident(30, 2)
    Set wf = ..Workflow(inc)
    Do $$$AssertStatusOK(wf.AskApproval(inc, inc.ChainList(), ""), "the task is raised")
    Do $$$AssertEquals(wf.PendingTasks, 1, "one task")
    Do $$$AssertEquals(wf.Sent.Count(), 2, "one request, and the check that its task was made")
    Do $$$AssertEquals(wf.Sent.GetAt(1), wf.ApprovalTarget _ "|approval", "under the shared completion key")
    Do $$$AssertEquals($PIECE(wf.Sent.GetAt(2), ":", 1), "Ens.Alarm|taskcheck", "the check")
    Set task = wf.LastTask
    Do $$$AssertTrue($ISOBJECT(task), "the engine's checks took it")
    Quit:'$ISOBJECT(task)
    Set msg = task.%Message
    Do $$$AssertTrue($LENGTH(msg) <= 2000, "it fits: " _ $LENGTH(msg))
    Do $$$AssertEquals(task.%Subject, "Shutter " _ inc.IncidentId _ ": approve the release of 30 chain(s) to " _ inc.Receiver, "the subject the decision finds it by")
    Do $$$AssertTrue(msg [ "60 failures to", "the failures are counted")
    Do $$$AssertTrue(msg [ ("Plan digest: " _ inc.PlanDigest), "the whole digest is there")
    Do $$$AssertTrue(msg [ ($CHAR(10) _ "Chain 1 ("), "the first chain is listed")
    Do $$$AssertTrue(msg [ (inc.IncidentId _ "-1-2"), "with its items")
    Do $$$AssertNotTrue(msg [ ($CHAR(10) _ "Chain 30 ("), "the last chain is not")
    Set shown = $LENGTH(msg, $CHAR(10) _ "Chain ") - 1
    Do $$$AssertTrue(msg [ ("the first " _ shown _ " of 30 chains"), "it says how many it lists")
    Do $$$AssertTrue(msg [ ((30 - shown) _ " more chain"), "and how many more")
    Do $$$AssertTrue(msg [ ("/shutter/index.html#/incidents/" _ inc.IncidentId), "it points to the incident page")
    Do $$$AssertTrue(msg [ "binds all 30 chains", "and says the approval covers them all")
    Do $$$AssertTrue(msg [ "PlanDigest field", "the inbox's instruction is there")
    Do $$$AssertTrue($LENGTH(msg, $CHAR(10) _ "  ") - 1 = (2 * shown), "whole chains only: " _ shown _ " chains, each with its two items")
}

/// Every field as long as the store allows: the task still fits, with the digest whole. A chain's line too long to list
/// is left to the incident page. The task names the chain's own subject too.
Method TestTheLongestFieldsStillFit()
{
    Set inc = ##class(Shutter.Store.Incident).%New()
    Set inc.IncidentId = ..Long("I", 32), inc.Receiver = ..Long("R", 128), inc.OpenedAt = ..Long("T", 30), inc.PlanDigest = ..Long("D", 80)
    Set inc.CatalogueVersion = ..Long("C", 2000), inc.ProfileVersion = ..Long("P", 32), inc.PolicyVersion = ..Long("G", 32)
    Set chain = $CHAR(10) _ "Chain 1 (interleaved, " _ ..Long("E", 200) _ "): encounter " _ ..Long("N", 100) _ ", patient " _ ..Long("M", 100) _ ", first at receiver version 1234567890"
    For size = 1, 5, 500 {
        Set lines = ""
        For i = 1:1:size Set lines = lines _ chain
        Set task = ##class(Shutter.Process.IncidentWorkflow).ApprovalTask(inc, "", size, 2 * size, lines)
        Do $$$AssertStatusOK(task.%ValidateObject(), "the shared task of " _ size _ " such chains is valid")
        Do $$$AssertTrue($LENGTH(task.%Message) <= 2000, "at " _ size _ ": " _ $LENGTH(task.%Message))
        Do $$$AssertTrue(task.%Message [ inc.PlanDigest, "with the digest whole")
        Set task = ##class(Shutter.Process.IncidentWorkflow).ApprovalTask(inc, 2147483647, 1, 2 * size, lines)
        Do $$$AssertStatusOK(task.%ValidateObject(), "a chain's own task, with the longest subject, is valid at " _ size)
    }
    Set task = ##class(Shutter.Process.IncidentWorkflow).ApprovalTask(inc, "", 1, 2, $CHAR(10) _ "Chain 1 (" _ ..Long("X", 3000))
    Do $$$AssertStatusOK(task.%ValidateObject(), "a line longer than the whole limit is valid")
    Do $$$AssertTrue(task.%Message [ "1 more chain", "and is left to the incident page")
}

/// One chain with more items than the text holds (a chain's own task, or a long shared one): the first items, and how
/// many more.
Method TestOneLongChainSaysHowManyMore()
{
    Set inc = ##class(Shutter.Store.Incident).%New()
    Set inc.IncidentId = "I-000009", inc.Receiver = "Downstream Out", inc.OpenedAt = "2026-11-06T09:00:00Z", inc.PlanDigest = "sha256:abc"
    Set inc.CatalogueVersion = "E1@1", inc.ProfileVersion = "3", inc.PolicyVersion = "2026-10-26.1"
    Set lines = $CHAR(10) _ "Chain 2 (ordered, E4): encounter ENC-1, patient MRN-1, first at receiver version 1"
    For p = 1:1:70 Set lines = lines _ $CHAR(10) _ "  " _ p _ ". transfer at 2026-11-06T09:00:00Z (C-000001, E4 resend_chain)"
    Set task = ##class(Shutter.Process.IncidentWorkflow).ApprovalTask(inc, "2", 1, 70, lines)
    Do $$$AssertStatusOK(task.%ValidateObject(), "the chain's task is valid")
    Do $$$AssertTrue(task.%Message [ ($CHAR(10) _ "Chain 2 ("), "the chain is named")
    Do $$$AssertTrue(task.%Message [ ($CHAR(10) _ "  1. transfer"), "with its first item")
    Do $$$AssertNotTrue(task.%Message [ ($CHAR(10) _ "  70. transfer"), "not its last")
    Do $$$AssertTrue(task.%Message [ "of 70 operations", "and it says how many")
    Do $$$AssertTrue(task.%Message [ "part of the first chain", "that it is only part of the chain")
    Do $$$AssertTrue(task.%Message [ "/shutter/index.html#/incidents/I-000009", "the page has them all")
}

/// A text whose room ends exactly where the next chain's line begins lists the chain before it as whole, and says so;
/// one character less and that chain is left out, not counted.
Method TestACutOnAChainsLineCountsTheChainBefore()
{
    Set inc = ##class(Shutter.Store.Incident).%New()
    Set inc.IncidentId = "I-000010", inc.Receiver = "Downstream Out", inc.OpenedAt = "2026-11-06T09:00:00Z", inc.PlanDigest = "sha256:abc"
    Set inc.CatalogueVersion = "E1@1", inc.ProfileVersion = "3", inc.PolicyVersion = "2026-10-26.1"
    Set nl = $CHAR(10)
    Set chains = ""
    For seq = 1:1:8 {
        Set chain = nl _ "Chain " _ seq _ " (ordered, E4): encounter ENC-" _ seq _ ", patient MRN-" _ seq _ ", first at receiver version 1"
        For p = 1:1:2 Set chain = chain _ nl _ "  " _ p _ ". transfer at 2026-11-06T09:00:00Z (C-00000" _ seq _ ", E4 resend_chain)"
        Set chains(seq) = chain
    }
    // The room the long text leaves for the lines: the limit less the text round them and the note's reserve.
    Set room = $PARAMETER("Shutter.Process.IncidentTaskText", "MESSAGELIMIT") - $LENGTH(##class(Shutter.Process.IncidentTaskText).Message(inc, 8, 16, "")) - 260
    Set pad = room - $LENGTH(chains(1) _ chains(2))
    Do $$$AssertTrue(pad > 0, "two chains fit with room to spare: " _ pad)
    Set chains(2) = chains(2) _ ..Long("X", pad)
    Set lines = ""
    For seq = 1:1:8 Set lines = lines _ chains(seq)
    Set end = ##class(Shutter.Process.IncidentTaskText).FirstLines(lines, room, .shown, .items)
    Do $$$AssertEquals(end, room, "the cut falls on chain 3's line")
    Do $$$AssertEquals(shown, 2, "both chains before it are whole")
    Do $$$AssertEquals(items, 4, "with their items")
    Set end = ##class(Shutter.Process.IncidentTaskText).FirstLines(lines, room - 1, .shown, .items)
    Do $$$AssertEquals(end, $LENGTH(chains(1)), "a character less ends after the first chain")
    Do $$$AssertEquals(shown, 1, "the second chain is not counted")
    Do $$$AssertEquals(items, 2, "nor its items")
    Set msg = ##class(Shutter.Process.IncidentTaskText).Message(inc, 8, 16, lines)
    Do $$$AssertTrue($LENGTH(msg) <= 2000, "it fits: " _ $LENGTH(msg))
    Do $$$AssertTrue(msg [ (chains(2) _ nl _ "Listed here: "), "the second chain is listed whole")
    Do $$$AssertNotTrue(msg [ (nl _ "Chain 3 ("), "the third is not")
    Do $$$AssertTrue(msg [ "Listed here: the first 2 of 8 chains, 4 of 16 operations.", "the note counts both chains")
    Do $$$AssertTrue(msg [ "6 more chains and every operation are on the incident page", "and the six left")
}

/// The digest moves with a chain the task does not list, so an approval from the text binds that chain too.
Method TestTheDigestBindsAChainNotListed()
{
    Set inc = ..NewIncident(20, 2)
    Set wf = ..Workflow(inc)
    Do $$$AssertStatusOK(wf.AskApproval(inc, inc.ChainList(), ""), "the task is raised")
    Do $$$AssertNotTrue(wf.LastTask.%Message [ ($CHAR(10) _ "Chain 20 ("), "chain 20 is not in the text")
    Set before = inc.PlanDigest
    Set item = inc.ChainAt(20).ItemAt(2)
    Set item.CatalogueOutcome = "escalate"
    Do $$$AssertStatusOK(item.%Save(), "chain 20's last item changes")
    Do $$$AssertStatusOK(inc.BuildPlan(inc.PolicyVersion), "the plan is built again")
    Do $$$AssertNotEquals(inc.PlanDigest, before, "and the digest moves")
}

/// An error raising the task: nothing closes, no case fails, the chains wait, and a person is told by the incident's
/// timeline and an alert, each naming the incident. It is tried again, and when the task goes the incident carries on.
Method TestAnErrorRaisingTheTaskStopsForAPerson()
{
    Set inc = ..NewIncident(2, 2)
    Set wf = ..Workflow(inc)
    Set wf.Refuse = "the target is not there"
    Do $$$AssertStatusOK(wf.AskApproval(inc, inc.ChainList(), ""), "the error does not reach the workflow's abandon")
    Do $$$AssertEquals(wf.PendingTasks, 0, "no task is open")
    Do ..AssertStillForAPerson(inc, wf, "raise")
    // Still refused: no second event or alert.
    Set events = inc.Events().%Size()
    Do $$$AssertStatusOK(wf.OnResponse("", "", "", "", "raise"), "the second try fails quietly")
    Do $$$AssertEquals(inc.Events().%Size(), events, "with no more events")
    Do $$$AssertEquals(wf.Alerts.Count(), 1, "or alerts")
    Do $$$AssertEquals(wf.Sent.GetAt(wf.Sent.Count()), "Ens.Alarm|raise", "and it will try again")
    // The cause is cleared.
    Set wf.Refuse = ""
    Do $$$AssertStatusOK(wf.OnResponse("", "", "", "", "raise"), "the next try")
    Do $$$AssertEquals(wf.PendingTasks, 1, "raises the task")
    Do $$$AssertTrue($ISOBJECT(wf.LastTask), "and the engine has it")
    Do $$$AssertEquals(##class(Shutter.Store.Incident).%OpenId(inc.%Id()).State, "awaiting_approval", "the incident waits for the answer")
}

/// The same for a chain's own task, under its own key.
Method TestAChainsOwnTaskStopsForAPerson()
{
    Set inc = ..NewIncident(1, 2, "per_chain")
    Set wf = ..Workflow(inc)
    Set wf.Refuse = "the target is not there"
    Do $$$AssertStatusOK(wf.AskApproval(inc, inc.ChainList(), 1), "the error does not reach the workflow's abandon")
    Do ..AssertStillForAPerson(inc, wf, "raise:1")
}

/// A chain's own task cannot be raised while an automatic chain goes on: once the automatic chain is done, the incident
/// rests in awaiting_approval with the reason, not in releasing, so the state filter still lists the chain a person
/// must approve.
Method TestAFailedTaskBesideAnAutomaticChainRestsForAPerson()
{
    Set inc = ..NewIncident(2, 1, "per_chain")
    Set auto = inc.ChainAt(2)
    Set auto.Policy = "automatic", auto.State = "approved"
    Do $$$AssertStatusOK(auto.%Save(), "chain 2 is automatic")
    Set wf = ..Workflow(inc)
    Set wf.Refuse = "the target is not there"
    Do $$$AssertStatusOK(wf.AskApproval(inc, inc.ChainList(), 1), "chain 1's task cannot be raised")
    Do $$$AssertEquals(wf.PendingTasks, 0, "no task is open")
    Set inc = ##class(Shutter.Store.Incident).%OpenId(inc.%Id())
    Do $$$AssertStatusOK(wf.Advance(inc), "the automatic chain is released")
    Set inc = ##class(Shutter.Store.Incident).%OpenId(inc.%Id())
    Do $$$AssertEquals(inc.State, "releasing", "while it goes, the incident is releasing")
    // The released case resolves: the item is done and the workflow moves on.
    Set item = ##class(Shutter.Store.ChainItem).%OpenId(wf.CurrentItemId)
    Set item.State = "resolved"
    Do $$$AssertStatusOK(item.%Save(), "the automatic chain's item resolves")
    Set wf.CurrentCaseId = "", wf.CurrentItemId = ""
    Do $$$AssertStatusOK(wf.Advance(inc), "the workflow moves on")
    Set now = ##class(Shutter.Store.Incident).%OpenId(inc.%Id())
    Do $$$AssertEquals(now.ChainAt(2).State, "resolved", "the automatic chain is resolved")
    Do $$$AssertEquals(now.ChainAt(1).State, "awaiting_approval", "chain 1 still waits for a person")
    Do $$$AssertEquals(now.State, "awaiting_approval", "the incident rests where a person sees it")
    Set last = "", it = now.Events().%GetIterator()
    While it.%GetNext(.k, .e) { If e.kind = "state" Set last = e.text }
    Do $$$AssertTrue(last [ "no approval task is open", "its transition says why: " _ last)
    Set listed = 0, rows = ##class(Shutter.Publish.Tools).ListIncidents("awaiting_approval", 200).incidents.%GetIterator()
    While rows.%GetNext(.k, .row) { If row.incidentId = inc.IncidentId Set listed = 1 }
    Do $$$AssertTrue(listed, "the state filter lists it")
    Set again = 0
    For i = 1:1:wf.Sent.Count() { If wf.Sent.GetAt(i) = "Ens.Alarm|raise:1" Set again = 1 }
    Do $$$AssertTrue(again, "and the task is tried again")
}

/// The Workflow item answers the task's call with an error: the same stop, not an abandon.
Method TestAnErrorFromTheTasksCallStopsForAPerson()
{
    Set inc = ..NewIncident(2, 2)
    Set wf = ..Workflow(inc)
    Do $$$AssertStatusOK(wf.AskApproval(inc, inc.ChainList(), ""), "the task is raised")
    Do $$$AssertStatusOK(wf.OnError("", "", "", $$$ERROR($$$GeneralError, "no such role"), "approval"), "the call answers with an error")
    Do $$$AssertEquals(wf.PendingTasks, 0, "no task is open")
    Do ..AssertStillForAPerson(inc, wf, "raise")
}

/// The Workflow item keeps answering each try with the same error: one error event, one alert and one "raised" note,
/// however many tries; it goes on trying, and a different error is told once more.
Method TestACallThatKeepsFailingIsToldOnce()
{
    Set inc = ..NewIncident(2, 2)
    Set wf = ..Workflow(inc)
    Do $$$AssertStatusOK(wf.AskApproval(inc, inc.ChainList(), ""), "the task is raised")
    For try = 1:1:4 {
        Do $$$AssertStatusOK(wf.OnError("", "", "", $$$ERROR($$$GeneralError, "no such role, try " _ try), "approval"), "the call answers with an error")
        Do $$$AssertEquals(wf.Sent.GetAt(wf.Sent.Count()), "Ens.Alarm|raise", "it will try again")
        Do $$$AssertStatusOK(wf.OnResponse("", "", "", "", "raise"), "the next try")
        Do $$$AssertEquals(wf.PendingTasks, 1, "a task is out again")
    }
    Do $$$AssertEquals(..Said(inc, "error", "No approval task"), 1, "one error on the timeline")
    Do $$$AssertEquals(wf.Alerts.Count(), 1, "one alert")
    Do $$$AssertEquals(..Said(inc, "note", "Approval task raised"), 1, "one note that the task was raised")
    Do $$$AssertStatusOK(wf.OnError("", "", "", $$$ERROR($$$GeneralError, "the Workflow item is disabled"), "approval"), "another cause")
    Do $$$AssertEquals(..Said(inc, "error", "No approval task"), 2, "is told")
    Do $$$AssertEquals(wf.Alerts.Count(), 2, "with its own alert")
}

/// A chain's own task keeps its own count: two chains, each told once.
Method TestEachChainsTaskIsToldOnce()
{
    Set inc = ..NewIncident(2, 2, "per_chain")
    Set wf = ..Workflow(inc)
    Set wf.Refuse = "the target is not there"
    For seq = 1, 2, 1, 2 { Do $$$AssertStatusOK(wf.AskApproval(inc, inc.ChainList(), seq), "chain " _ seq) }
    Do $$$AssertEquals(..Said(inc, "error", "No approval task"), 2, "one error for each chain")
    Do $$$AssertEquals(wf.Alerts.Count(), 2, "one alert for each")
}

/// The approval target's Workflow role is not defined (deleted, or the target renamed): the Workflow item would defer
/// its reply and make no task, so no call goes, and the incident stops for a person as for any error raising the task.
/// Once the role is there, the next try raises one task.
Method TestAMissingRoleStopsForAPerson()
{
    Set inc = ..NewIncident(2, 2)
    Set wf = ..Workflow(inc)
    Set wf.ApprovalTarget = "UT No Such Role " _ $JOB
    Do $$$AssertNotTrue(##class(EnsLib.Workflow.RoleDefinition).%ExistsId(wf.ApprovalTarget), "the role is not defined")
    Do $$$AssertStatusOK(wf.AskApproval(inc, inc.ChainList(), ""), "the error does not reach the workflow's abandon")
    Do $$$AssertEquals(wf.PendingTasks, 0, "no task is open")
    Do $$$AssertEquals(wf.Sent.Count(), 1, "no request went to the Workflow item")
    Do $$$AssertEquals(wf.Sent.GetAt(1), "Ens.Alarm|raise", "and it will try again")
    Do ..AssertWaits(inc, wf, "is not defined")
    // The next try reads the item's own target, whose role is there: one task.
    Do $$$AssertStatusOK(wf.OnResponse("", "", "", "", "raise"), "the next try")
    Do $$$AssertEquals(wf.PendingTasks, 1, "raises the task")
    Do $$$AssertEquals(..Requests(wf), 1, "once")
    Do $$$AssertEquals(##class(Shutter.Store.Incident).%OpenId(inc.%Id()).State, "awaiting_approval", "the incident waits for the answer")
}

/// The same for a chain's own task, under its own key.
Method TestAMissingRoleStopsAChainsOwnTask()
{
    Set inc = ..NewIncident(1, 2, "per_chain")
    Set wf = ..Workflow(inc)
    Set wf.ApprovalTarget = "UT No Such Role " _ $JOB
    Do $$$AssertStatusOK(wf.AskApproval(inc, inc.ChainList(), 1), "the error does not reach the workflow's abandon")
    Do $$$AssertEquals(wf.PendingTasks, 0, "no task is open")
    Do $$$AssertEquals(wf.Sent.GetAt(wf.Sent.Count()), "Ens.Alarm|raise:1", "and it will try again")
    Do ..AssertWaits(inc, wf, "is not defined")
}

/// The Workflow item took the task's request and made no task (an error inside it, which never answers the call): the
/// check after the call stops for a person as for any error raising the task, and the next try raises one task.
Method TestATaskTheItemDidNotMakeStopsForAPerson()
{
    Set inc = ..NewIncident(2, 2)
    Set wf = ..Workflow(inc)
    Set req = ..Request(inc, "", 6, 60, .header)
    Do inc.Transition("awaiting_approval", "1 approval task(s) raised for the Workflow role", "system")
    Do wf.TaskSent.SetAt(req.%Id(), wf.TaskKey(""))
    Set wf.PendingTasks = 1
    Do $$$AssertStatusOK(wf.OnResponse("", "", "", "", "taskcheck::" _ req.%Id()), "the check")
    Do $$$AssertEquals(wf.PendingTasks, 0, "no task is open")
    Do $$$AssertEquals(wf.Sent.GetAt(wf.Sent.Count()), "Ens.Alarm|raise", "it will try again")
    Do ..AssertWaits(inc, wf, "made no task")
    // A second check of the same request, or one of a request since replaced, changes nothing.
    Do $$$AssertStatusOK(wf.OnResponse("", "", "", "", "taskcheck::" _ req.%Id()), "the same check again")
    Do $$$AssertEquals(wf.PendingTasks, 0, "still no task counted")
    Do $$$AssertEquals(wf.Alerts.Count(), 1, "and no second alert")
    Do $$$AssertStatusOK(wf.OnResponse("", "", "", "", "raise"), "the next try")
    Do $$$AssertEquals(wf.PendingTasks, 1, "raises the task")
    Do $$$AssertEquals(..Requests(wf), 1, "once")
    Do ..Unsend(req, header)
}

/// A chain's own request, deferred by the item with no task, under its own key.
Method TestAChainsTaskTheItemDidNotMakeStopsForAPerson()
{
    Set inc = ..NewIncident(1, 2, "per_chain")
    Set wf = ..Workflow(inc)
    Set req = ..Request(inc, 1, 6, 60, .header)
    Do inc.Transition("awaiting_approval", "1 approval task(s) raised for the Workflow role", "system")
    Do wf.TaskSent.SetAt(req.%Id(), wf.TaskKey(1))
    Set wf.PendingTasks = 1
    Do $$$AssertStatusOK(wf.OnResponse("", "", "", "", "taskcheck:1:" _ req.%Id()), "the check")
    Do $$$AssertEquals(wf.PendingTasks, 0, "no task is open")
    Do $$$AssertEquals(wf.Sent.GetAt(wf.Sent.Count()), "Ens.Alarm|raise:1", "it will try again")
    Do ..AssertWaits(inc, wf, "made no task")
    Do ..Unsend(req, header)
}

/// The check leaves alone a task the item made (open or answered), a request the item has not finished with (it checks
/// again later), one it finished with only seconds ago, and a request since answered with an error or sent again.
Method TestTheCheckLeavesAMadeTaskAlone()
{
    Set inc = ..NewIncident(2, 2)
    Set wf = ..Workflow(inc)
    Set role = wf.ApprovalTarget
    // A task made from the request.
    Set task = ##class(Shutter.Test.Workflow).SavedTask(role, inc.IncidentId)
    Do $$$AssertTrue($ISOBJECT(task), "a task as the engine saves it")
    Quit:'$ISOBJECT(task)
    Set reqId = task.%TaskStatus.RequestGetObjectId()
    Set header = ..Header(reqId, 6, 60)
    Do wf.TaskSent.SetAt(reqId, wf.TaskKey(""))
    Set wf.PendingTasks = 1
    Do $$$AssertStatusOK(wf.OnResponse("", "", "", "", "taskcheck::" _ reqId), "the check")
    Do $$$AssertEquals(wf.PendingTasks, 1, "the task stays counted")
    Do $$$AssertEquals(wf.Alerts.Count(), 0, "no alert")
    Do $$$AssertEquals(wf.Sent.Count(), 0, "nothing sent")
    Do ##class(Ens.MessageHeader).%DeleteId(header)
    Do ##class(Shutter.Test.Workflow).DeleteTask(task)
    // Queued, or being delivered: checked again later, nothing else.
    For status = 2, 3 {
        Set req = ..Request(inc, "", status, 60, .header)
        Do wf.TaskSent.SetAt(req.%Id(), wf.TaskKey(""))
        Do $$$AssertStatusOK(wf.OnResponse("", "", "", "", "taskcheck::" _ req.%Id()), "the check at status " _ status)
        Do $$$AssertEquals(wf.PendingTasks, 1, "the task stays counted")
        Do $$$AssertEquals(wf.Sent.GetAt(wf.Sent.Count()), "Ens.Alarm|taskcheck::" _ req.%Id(), "it checks again")
        Do ..Unsend(req, header)
    }
    // Deferred a moment ago: the item may still be making it.
    Set req = ..Request(inc, "", 6, 1, .header)
    Do wf.TaskSent.SetAt(req.%Id(), wf.TaskKey(""))
    Do $$$AssertStatusOK(wf.OnResponse("", "", "", "", "taskcheck::" _ req.%Id()), "the check")
    Do $$$AssertEquals(wf.PendingTasks, 1, "the task stays counted")
    Do $$$AssertEquals(wf.Sent.GetAt(wf.Sent.Count()), "Ens.Alarm|taskcheck::" _ req.%Id(), "it checks again")
    // Answered with an error since (OnError), or sent again: the check is not this request's.
    Do $$$AssertStatusOK(wf.OnError("", "", "", $$$ERROR($$$GeneralError, "no such role"), "approval"), "the call answers with an error")
    Set events = ##class(Shutter.Store.Incident).%OpenId(inc.%Id()).Events().%Size()
    Do ##class(Ens.MessageHeader).%DeleteId(header)
    Set header = ..Header(req.%Id(), 8, 60)
    Do $$$AssertStatusOK(wf.OnResponse("", "", "", "", "taskcheck::" _ req.%Id()), "the check after the error")
    Do $$$AssertEquals(wf.PendingTasks, 0, "counted down once, by the error")
    Do $$$AssertEquals(wf.Alerts.Count(), 1, "one alert, the error's")
    Do $$$AssertEquals(##class(Shutter.Store.Incident).%OpenId(inc.%Id()).Events().%Size(), events, "no more events")
    Do ..Unsend(req, header)
}

/// The words of a stop for a person: the incident and its chains wait, no case failed, one error event names the
/// incident and the cause, and one alert names the incident.
Method AssertWaits(inc As Shutter.Store.Incident, wf As Shutter.Test.FakeIncidentWorkflow, cause As %String)
{
    Set now = ##class(Shutter.Store.Incident).%OpenId(inc.%Id())
    Do $$$AssertEquals(now.State, "awaiting_approval", "the incident is not closed: it waits for a person")
    Do $$$AssertEquals(now.ChainAt(1).State, "awaiting_approval", "its chain still waits")
    Do $$$AssertEquals(now.ChainAt(1).ItemAt(1).Case.State, "grouped", "no case failed")
    Do $$$AssertEquals(..Said(inc, "error", "No approval task"), 1, "one error on the timeline")
    Set found = "", it = now.Events().%GetIterator()
    While it.%GetNext(.k, .e) { If e.kind = "error" Set found = e.text }
    Do $$$AssertTrue(found [ inc.IncidentId, "it names the incident: " _ $EXTRACT(found, 1, 200))
    Do $$$AssertTrue(found [ cause, "and the cause: " _ $EXTRACT(found, 1, 400))
    Do $$$AssertEquals(wf.Alerts.Count(), 1, "one alert")
    Do $$$AssertTrue(wf.Alerts.GetAt(1) [ inc.IncidentId, "names the incident")
}

/// How many task requests the workflow sent.
Method Requests(wf As Shutter.Test.FakeIncidentWorkflow) As %Integer
{
    Set n = 0
    For i = 1:1:wf.Sent.Count() { If $PIECE(wf.Sent.GetAt(i), "|", 1) '= "Ens.Alarm" Set n = n + 1 }
    Quit n
}

/// A saved task request for the incident's shared task (seq "") or a chain's, with a header at this status, processed
/// this many seconds ago: what the Workflow item leaves when it defers its reply and makes no task (status 6).
Method Request(inc As Shutter.Store.Incident, seq As %String, status As %Integer, age As %Integer, Output header As %String) As EnsLib.Workflow.TaskRequest
{
    Set req = ##class(Shutter.Process.IncidentWorkflow).ApprovalTask(inc, seq, 1, 2, "")
    Do $$$AssertStatusOK(req.%Save(), "the request is saved")
    Set header = ..Header(req.%Id(), status, age)
    Quit req
}

/// A request's header, as the engine keeps it, at this status, created and processed this many seconds ago.
Method Header(requestId As %String, status As %Integer, age As %Integer) As %String
{
    Set h = ##class(Ens.MessageHeader).%New()
    Set h.Type = 1, h.MessageBodyClassName = "EnsLib.Workflow.TaskRequest", h.MessageBodyId = requestId
    Set h.SourceConfigName = "Incident Workflow", h.TargetConfigName = "UT Shutter.Test.IncidentTask"
    Set then = ##class(%Library.UTC).Normalize($SYSTEM.SQL.Functions.DATEADD("s", -age, ##class(%Library.UTC).NowUTC()))
    Set h.TimeCreated = then, h.TimeProcessed = then, h.Status = status
    Do $$$AssertStatusOK(h.%Save(), "its header, at status " _ status)
    Quit h.%Id()
}

Method Unsend(req As EnsLib.Workflow.TaskRequest, header As %String)
{
    If header '= "" Do ##class(Ens.MessageHeader).%DeleteId(header)
    Do ##class(EnsLib.Workflow.TaskRequest).%DeleteId(req.%Id())
}

Method Said(inc As Shutter.Store.Incident, kind As %String, start As %String) As %Integer
{
    Set n = 0, it = ##class(Shutter.Store.Incident).%OpenId(inc.%Id()).Events().%GetIterator()
    While it.%GetNext(.k, .e) { If (e.kind = kind) && ($EXTRACT(e.text, 1, $LENGTH(start)) = start) Set n = n + 1 }
    Quit n
}

/// Another call's error still abandons, as before.
Method TestAnotherCallsErrorStillAbandons()
{
    Set inc = ..NewIncident(1, 2)
    Set wf = ..Workflow(inc)
    Do $$$AssertStatusOK(wf.OnError("", "", "", $$$ERROR($$$GeneralError, "broken"), "poll"), "an error from another call")
    Do $$$AssertEquals(##class(Shutter.Store.Incident).%OpenId(inc.%Id()).State, "closed", "closes the incident")
}

/// A rejection with a comment longer than the chain's outcome can hold rejects the chains; it does not abandon them.
Method TestALongCommentRejectsAndDoesNotAbandon()
{
    Set inc = ..NewIncident(2, 2)
    Set wf = ..Workflow(inc)
    Set answer = ##class(EnsLib.Workflow.TaskResponse).%New()
    Set answer.%Action = "Reject", answer.%UserName = "approver"
    Do answer.%FormValues.SetAt(..Long("c", 5000), "Comment")
    Do $$$AssertStatusOK(wf.AskApproval(inc, inc.ChainList(), ""), "the task is raised")
    Do $$$AssertStatusOK(wf.OnResponse("", "", "", answer, "approval"), "the answer is taken")
    Set inc = ##class(Shutter.Store.Incident).%OpenId(inc.%Id())
    Do $$$AssertEquals(inc.ChainAt(1).State, "rejected", "the chain is rejected")
    Do $$$AssertEquals(inc.ChainAt(2).State, "rejected", "and the next")
    Do $$$AssertEquals(inc.ChainAt(1).ItemAt(1).Case.State, "escalated", "its cases go to a person")
    Do $$$AssertTrue(inc.ChainAt(1).Outcome [ "rejected by approver: ccc", "the outcome keeps the start of the comment")
    Do $$$AssertEquals($EXTRACT(inc.ApprovalComment, 1, 3), "ccc", "the approval keeps it")
}

/// A chain of more operations than Entries holds is classified, not refused: the first entries and how many more,
/// each item keeping its own.
Method TestALongChainIsClassified()
{
    Set inc = ..NewIncident(1, 120, "approval", "E44")
    Set ch = inc.ChainAt(1)
    Do $$$AssertStatusOK(##class(Shutter.Store.IncidentDetector).Classify(ch), "120 items are classified")
    Set ch = inc.ChainAt(1)
    Do $$$AssertTrue($LENGTH(ch.Entries) <= 200, "the entries fit: " _ $LENGTH(ch.Entries))
    Do $$$AssertTrue($PIECE(ch.Entries, ",", *) ? 1"+"1.N, "and say how many more: " _ $PIECE(ch.Entries, ",", *))
    Do $$$AssertEquals($LENGTH(ch.Entries, ",") - 1 + $EXTRACT($PIECE(ch.Entries, ",", *), 2, *), 120, "which add up")
}

Method AssertStillForAPerson(inc As Shutter.Store.Incident, wf As Shutter.Test.FakeIncidentWorkflow, key As %String)
{
    Set now = ##class(Shutter.Store.Incident).%OpenId(inc.%Id())
    Do $$$AssertEquals(now.State, "awaiting_approval", "the incident is not closed: it waits for a person")
    Do $$$AssertEquals(now.ChainAt(1).State, "awaiting_approval", "its chain still waits")
    Do $$$AssertEquals(now.ChainAt(1).ItemAt(1).Case.State, "grouped", "no case failed")
    Set events = now.Events(), found = ""
    Set it = events.%GetIterator()
    While it.%GetNext(.k, .e) { If e.kind = "error" Set found = e.text }
    Do $$$AssertTrue(found [ inc.IncidentId, "an error on its timeline names the incident: " _ $EXTRACT(found, 1, 200))
    Do $$$AssertTrue(found [ "the target is not there" || (found [ "no such role"), "and the error")
    Do $$$AssertEquals(wf.Alerts.Count(), 1, "one alert")
    Do $$$AssertTrue(wf.Alerts.GetAt(1) [ inc.IncidentId, "names the incident")
    Do $$$AssertEquals(wf.Sent.GetAt(wf.Sent.Count()), "Ens.Alarm|" _ key, "and it will try again")
}

Method Workflow(inc As Shutter.Store.Incident) As Shutter.Test.FakeIncidentWorkflow
{
    Set wf = ##class(Shutter.Test.FakeIncidentWorkflow).%New("Incident Workflow")
    Do $$$AssertTrue($ISOBJECT(wf), "an instance outside the production")
    Set wf.IncidentId = inc.IncidentId
    Quit wf
}

ClassMethod Long(letter As %String, size As %Integer) As %String
{
    Quit $TRANSLATE($JUSTIFY("", size), " ", letter)
}

/// An incident, its plan built, of this many ordered chains of this many items, each under this policy, as the workflow
/// holds it when it asks for the approval.
Method NewIncident(chains As %Integer, items As %Integer, policy As %String = "approval", entry As %String = "E4") As Shutter.Store.Incident
{
    Set now = ##class(Shutter.Util.Time).NowUTC()
    Set inc = ##class(Shutter.Store.Incident).%New()
    Set inc.IncidentId = "UT-INC-T" _ $JOB _ "-" _ $INCREMENT(^||Shutter.Test.IncidentTask)
    Set inc.Receiver = $PARAMETER("Shutter.Production", "RECEIVER"), inc.Mode = "policy", inc.State = "classified"
    Set inc.OpenedAt = now, inc.LastFailureAt = now, inc.IntakeClosedAt = now
    Do $$$AssertStatusOK(inc.%Save(), "the incident is saved")
    Set i%Made(inc.%Id()) = ""
    For seq = 1:1:chains {
        Set ch = ##class(Shutter.Store.Chain).%New()
        Do ch.IncidentSetObjectId(inc.%Id())
        Set ch.Seq = seq, ch.EncounterId = "ENC-" _ seq, ch.PatientId = "MRN" _ seq, ch.PatientIdAuthority = "HOSP"
        Set ch.Kind = "ordered", ch.Decides = "policy", ch.Policy = policy, ch.FirstExpectedVersion = 1, ch.State = "awaiting_approval"
        For p = 1:1:$SELECT(items > 6: 6, 1: items) Set ch.Entries = ch.Entries _ $SELECT(p = 1: "", 1: ",") _ entry
        Do $$$AssertStatusOK(ch.%Save(), "chain " _ seq)
        For p = 1:1:items {
            Set case = ..NewCase(inc, seq, p, ch.EncounterId, ch.PatientId)
            Set it = ##class(Shutter.Store.ChainItem).%New()
            Do it.ChainSetObjectId(ch.%Id())
            Do it.CaseSetObjectId(case.%Id())
            Set it.Position = p, it.Entry = entry, it.CatalogueOutcome = "resend_chain", it.Decides = "policy"
            Do $$$AssertStatusOK(it.%Save(), "item " _ seq _ "." _ p)
        }
    }
    Do $$$AssertStatusOK(inc.BuildPlan("2026-10-26.1"), "the plan is built")
    Quit inc
}

Method NewCase(inc As Shutter.Store.Incident, seq As %Integer, position As %Integer, encounter As %String, patient As %String) As Shutter.Store.Case
{
    Set now = ##class(Shutter.Util.Time).NowUTC()
    Set case = ##class(Shutter.Store.Case).%New()
    Set case.CaseId = inc.IncidentId _ "-" _ seq _ "-" _ position
    Set case.Event = "transfer", case.EventTime = "2026-10-19T09:00:" _ $TRANSLATE($JUSTIFY(position # 60, 2), " ", "0") _ "Z", case.EncounterId = encounter
    Set case.PatientId = patient, case.PatientIdAuthority = "HOSP", case.FailureKind = "delivery_failed"
    Set case.FailureText = "Delivery unavailable (ward_unavailable), HTTP 503", case.SourceSystem = "PAS", case.Ward = "WARD-B", case.Receiver = inc.Receiver
    Set case.OperationKey = "PAS^HOSP^" _ patient _ "^" _ encounter _ "^transfer^" _ position
    Set case.State = "grouped", case.Mode = "policy", case.OpenedAt = now, case.UpdatedAt = now
    Do case.IncidentSetObjectId(inc.%Id())
    Do $$$AssertStatusOK(case.%Save(), "the case " _ case.CaseId)
    Set summary = {"operation": {"operation_key": (case.OperationKey), "payload_digest": ("sha256:ut-" _ seq _ "-" _ position)}, "epoch": 1, "ward_state_http_status": 200, "ward_state": {"state": "admitted", "ward": "WARD-A", "version": 1}}
    Set snap = ##class(Shutter.Store.Snapshot).Begin(case, 300)
    Do $$$AssertStatusOK(snap.Seal(summary), "its snapshot is sealed")
    Do $$$AssertStatusOK(case.SetSnapshot(snap), "and current")
    Quit case
}

}
