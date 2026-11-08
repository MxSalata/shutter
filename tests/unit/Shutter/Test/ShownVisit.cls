/// Another visit's movement that the site profile shows instead of stopping is for a person to read
/// (Shutter.Util.ShownVisit): a case at an automatic tier whose snapshot shows one waits for a person's approval, an item
/// released under an incident's approval whose fresh evidence shows one stops, and an incident's chain with such an item
/// leaves the shared approval for each case's own path. Each test has a control without the line, which goes as before.
/// Cases take UT-SV- ids and incidents UT-INC- ids (Shutter.Test.IncidentPlan clears those too); each test deletes its own
/// rows and puts the site profile back. Nothing is sent to the production.
Class Shutter.Test.ShownVisit Extends %UnitTest.TestCase
{

/// The incidents and cases made by the current test, for the clean-up.
Property Made As %String [ MultiDimensional ];

Property MadeCases As %String [ MultiDimensional ];

/// The stored site profile's text before the test changed it, or $CHAR(0) when the test changed nothing.
Property SavedProfile As %String(MAXLEN = "") [ InitialExpression = {$CHAR(0)} ];

Method OnBeforeAllTests() As %Status
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Shutter_Store.""Case"" WHERE CaseId %STARTSWITH 'UT-SV-'")
    While rs.%Next() { Do ##class(Shutter.Test.IncidentPlan).PurgeCase(rs.%Get("ID")) }
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
    Set id = ""
    For {
        Set id = $ORDER(i%MadeCases(id))
        Quit:id=""
        Do ##class(Shutter.Test.IncidentPlan).PurgeCase(id)
    }
    Kill i%Made, i%MadeCases
    Do ..RestoreProfile()
    Quit $$$OK
}

/// The helper reads only another visit's movement among the shows: an out-patient attendance shown on the plan is not one.
Method TestOnlyAnotherVisitCounts()
{
    Set sv = "Shutter.Util.ShownVisit"
    Do $$$AssertTrue($CLASSMETHOD(sv, "In", ..Summary("ENC-UT-SV1", 1)), "another visit's movement shown")
    Do $$$AssertNotTrue($CLASSMETHOD(sv, "In", ..Summary("ENC-UT-SV1", 0)), "nothing shown")
    Set s = ..Summary("ENC-UT-SV1", 0)
    Set s."further_messages".shows = [{"why": "shown", "event": "discharge", "visit_number": "ENC-UT-OP"}]
    Do $$$AssertNotTrue($CLASSMETHOD(sv, "In", s), "an out-patient attendance shown")
    Do $$$AssertNotTrue($CLASSMETHOD(sv, "In", ""), "no summary")
    Do $$$AssertNotTrue($CLASSMETHOD(sv, "In", {"further_messages": {"shows": "x"}}), "shows that are not a list")
}

/// At a tier the site's profile releases automatically, a case whose snapshot shows another visit's movement waits for a
/// person's approval, with a note saying why, as a lost admission on a 404 does; the same case with nothing shown is
/// released by policy.
Method TestAnAutomaticTierAsksAPerson()
{
    Do ..SetPolicy("automatic")
    For shown = 0, 1 {
        Set case = ..NewCase("UT-SV-A" _ shown _ "-" _ $JOB, "ENC-UT-SVA" _ shown, shown, "")
        Set wf = ##class(Shutter.Test.QuietWorkflow).%New("Case Workflow")
        Set wf.CaseId = case.CaseId, wf.Mode = "policy"
        Do $$$AssertStatusOK(wf.PolicyPath(case, case.CurrentSnapshot.SummaryObject(), ..Catalogue()), "the policy path runs, shown " _ shown)
        If shown {
            Do $$$AssertEquals(wf.Policy, "approval", "another visit's movement shown: a person approves")
            Do $$$AssertTrue(..CaseSays(case, "a person approves, so that someone reads it"), "and the case says why")
        } Else {
            Do $$$AssertEquals(wf.Policy, "automatic", "the control, with nothing shown, is released by policy")
        }
    }
}

/// An item released under an incident's approval, whose fresh evidence shows another visit's movement the approval never
/// listed, stops for a person and nothing is planned; the same item with nothing shown goes on.
Method TestAReleasedItemWithAFreshLineStops()
{
    For shown = 0, 1 {
        Set case = ..NewCase("UT-SV-R" _ shown _ "-" _ $JOB, "ENC-UT-SVR" _ shown, shown, "")
        Set wf = ##class(Shutter.Test.QuietWorkflow).%New("Case Workflow")
        Set wf.CaseId = case.CaseId, wf.Mode = "policy", wf.Release = 1, wf.ReleasePolicy = "incident", wf.IncidentId = "UT-INC-SV"
        Set wf.ChainSeq = 1, wf.ChainKind = "single", wf.ChainDecides = "policy", wf.IncidentEntry = "E2", wf.IncidentOutcome = "resend"
        Do $$$AssertStatusOK(wf.PolicyPath(case, case.CurrentSnapshot.SummaryObject(), ..Catalogue()), "the policy path runs, shown " _ shown)
        Set case = ##class(Shutter.Store.Case).ByCaseId(case.CaseId)
        If shown {
            Do $$$AssertEquals(case.State, "blocked", "a line the incident's approval never listed: the item stops")
            Do $$$AssertTrue(case.Headline [ "another visit", "the headline says why: " _ case.Headline)
        } Else {
            Do $$$AssertEquals(wf.Policy, "incident", "the control goes under the incident's approval")
            Do $$$AssertNotTrue(case.State = "blocked", "and does not stop")
        }
    }
}

/// An incident of two single chains that the catalogue gives to site policy under one approval: the chain whose case
/// shows another visit's movement leaves the shared approval and goes on each case's own path, released at once to its
/// case's workflow, which asks a person with the line on the plan; the other stays under the one approval, whose task
/// counts it alone.
Method TestAnIncidentChainLeavesTheSharedApproval()
{
    // The demo's profile releases tier 2 single chains automatically: the shared approval is the site's choice here.
    Do ..SetPolicy("approval")
    Set inc = ..NewIncident()
    Set shownCase = ..NewCase(inc.IncidentId _ "-1", "ENC-UT-SVI1", 1, inc)
    Set plainCase = ..NewCase(inc.IncidentId _ "-2", "ENC-UT-SVI2", 0, inc)
    Set wf = ##class(Shutter.Test.FakeIncidentWorkflow).%New("Incident Workflow")
    Do $$$AssertTrue($ISOBJECT(wf), "an instance outside the production")
    Set wf.IncidentId = inc.IncidentId
    Do $$$AssertStatusOK(wf.Classify(inc), "the incident is classified")
    Set inc = ##class(Shutter.Store.Incident).%OpenId(inc.%Id())
    Set shown = "", plain = "", chains = inc.ChainList()
    For i = 1:1:chains.Count() {
        Set ch = chains.GetAt(i)
        If ch.EncounterId = "ENC-UT-SVI1" Set shown = ch
        If ch.EncounterId = "ENC-UT-SVI2" Set plain = ch
    }
    Do $$$AssertTrue($ISOBJECT(shown) && $ISOBJECT(plain), "two chains formed")
    Quit:'($ISOBJECT(shown) && $ISOBJECT(plain))
    // The control: the catalogue gave the plain chain to site policy, under the one approval.
    Do $$$AssertEquals(plain.Decides _ " " _ plain.Policy _ " " _ plain.State, "policy approval awaiting_approval", "the plain chain waits under the one approval")
    Do $$$AssertEquals(shown.Policy, "path", "the chain showing another visit's movement goes on each case's own path")
    Do $$$AssertNotTrue(shown.State = "awaiting_approval", "and does not wait for the shared approval: " _ shown.State)
    Do $$$AssertTrue(..IncidentSays(inc, "leaves the shared approval"), "the incident says why")
    Do $$$AssertTrue($ISOBJECT(wf.LastTask), "one approval task is raised")
    Do:$ISOBJECT(wf.LastTask) $$$AssertTrue(wf.LastTask.%Subject [ "approve the release of 1 chain(s)", "for the plain chain alone: " _ wf.LastTask.%Subject)
    Do:$ISOBJECT(wf.LastTask) $$$AssertNotTrue(wf.LastTask.%Message [ "ENC-UT-SVI1", "and its text does not list the chain that left")
    // The plan the incident's digest binds says so too.
    Set planned = $SELECT(inc.PlanJSON '= "": ##class(%DynamicObject).%FromJSON(inc.PlanJSON), 1: ""), found = ""
    If $ISOBJECT(planned) && $ISOBJECT(planned.chains) {
        Set ci = planned.chains.%GetIterator()
        While ci.%GetNext(, .co) { If co.seq = shown.Seq Set found = co.policy }
    }
    Do $$$AssertEquals(found, "path", "the recorded plan has the chain on its own path")
}

/// The same incident where the site's policy releases these chains automatically, as the demo's profile does: the chain
/// showing another visit's movement goes on each case's own path too, so its case asks a person; the plain chain is
/// released by policy, and no task is raised.
Method TestAnAutomaticIncidentChainTakesItsOwnPath()
{
    Do ..SetPolicy("automatic")
    Set inc = ..NewIncident()
    Do ..NewCase(inc.IncidentId _ "-1", "ENC-UT-SVJ1", 1, inc)
    Do ..NewCase(inc.IncidentId _ "-2", "ENC-UT-SVJ2", 0, inc)
    Set wf = ##class(Shutter.Test.FakeIncidentWorkflow).%New("Incident Workflow")
    Set wf.IncidentId = inc.IncidentId
    Do $$$AssertStatusOK(wf.Classify(inc), "the incident is classified")
    Set inc = ##class(Shutter.Store.Incident).%OpenId(inc.%Id())
    Set got = "", chains = inc.ChainList()
    For i = 1:1:chains.Count() { Set ch = chains.GetAt(i), got(ch.EncounterId) = ch.Decides _ " " _ ch.Policy }
    Do $$$AssertEquals($GET(got("ENC-UT-SVJ2")), "policy automatic", "the plain chain is released by policy")
    Do $$$AssertEquals($GET(got("ENC-UT-SVJ1")), "policy path", "the chain showing another visit's movement goes on each case's own path")
    Do $$$AssertNotTrue($ISOBJECT(wf.LastTask), "no approval task is raised")
}

/// A single-chain E2 case of the demo receiver (a transfer that never arrived, the receiver admitted at version 1 and
/// able to take a conditional write), with a sealed snapshot, showing another visit's movement or not.
Method NewCase(caseId As %String, encounter As %String, shown As %Boolean, inc) As Shutter.Store.Case
{
    Set now = ##class(Shutter.Util.Time).NowUTC()
    Set case = ##class(Shutter.Store.Case).%New()
    Set case.CaseId = caseId, case.Event = "transfer", case.EventTime = "2026-10-19T09:00:00Z", case.EncounterId = encounter
    Set case.PatientId = "MRN-" _ encounter, case.PatientIdAuthority = "HOSP"
    Set case.FailureKind = "delivery_failed", case.FailureText = "Delivery unavailable (ward_unavailable), HTTP 503"
    Set case.SourceSystem = "PAS", case.Ward = "WARD-B", case.Receiver = $PARAMETER("Shutter.Production", "RECEIVER")
    Set case.OperationKey = "PAS^HOSP^" _ case.PatientId _ "^" _ encounter _ "^transfer^2026-10-19T09:00:00Z"
    Set case.State = $SELECT($ISOBJECT(inc): "grouped", 1: "investigating"), case.Mode = "policy", case.OpenedAt = now, case.UpdatedAt = now
    If $ISOBJECT(inc) Do case.IncidentSetObjectId(inc.%Id())
    Do $$$AssertStatusOK(case.%Save(), "the case " _ caseId _ " is saved")
    Set i%MadeCases(case.%Id()) = ""
    Set snap = ##class(Shutter.Store.Snapshot).Begin(case, 300)
    Do $$$AssertStatusOK(snap.Seal(..Summary(encounter, shown, case)), "its snapshot is sealed")
    Do $$$AssertStatusOK(case.SetSnapshot(snap), "and current")
    Quit case
}

Method Summary(encounter As %String, shown As %Boolean, case = "") As %DynamicObject
{
    Set patient = "MRN-" _ encounter
    Set s = {"operation": {"operation_key": ($SELECT($ISOBJECT(case): case.OperationKey, 1: "")), "payload_digest": ("sha256:ut-sv-" _ encounter)}, "epoch": 1,
        "ward_state_http_status": 200, "ward_state": {"state": "admitted", "ward": "WARD-A", "version": 1, "epoch": 1, "patient_id": (patient), "patient_id_authority": "HOSP", "history": []},
        "receipt_http_status": 404, "route": {"capabilities": {"conditional_writes": true}}, "validation": {"parsed": true},
        "further_messages": {"identifier": "read", "stops": [], "shows": [], "unread": ""}}
    If shown Do s."further_messages".shows.%Push({"why": "other_visit", "event": "admit", "message_type": "ADT_A01", "visit_number": (encounter _ "-OTHER"), "event_time": "2026-10-19T09:05:00Z", "sent_at": "2026-10-19 09:05:01", "control_id": ("M-UT-SV-" _ encounter), "location": "WARD-C", "where": "RIG"})
    Quit s
}

/// The catalogue's answer for the case: E2 alone, by site policy, resend.
ClassMethod Catalogue() As %DynamicObject
{
    Quit {"decision": "policy", "entry": "E2", "outcome": "resend", "outcome_ref": "preferred", "conditions": {"chain": "single"},
        "matches": [{"id": "E2", "title": "Not delivered, still current", "decides": "policy", "preferred": {"outcome": "resend", "why": "The movement never reached the receiver."}}]}
}

Method NewIncident() As Shutter.Store.Incident
{
    Set now = ##class(Shutter.Util.Time).NowUTC()
    Set inc = ##class(Shutter.Store.Incident).%New()
    Set inc.IncidentId = "UT-INC-SV" _ $JOB _ "-" _ $INCREMENT(^||Shutter.Test.ShownVisit)
    Set inc.Receiver = $PARAMETER("Shutter.Production", "RECEIVER"), inc.Mode = "policy", inc.State = "open"
    Set inc.OpenedAt = now, inc.LastFailureAt = now, inc.IntakeClosedAt = now
    Do $$$AssertStatusOK(inc.%Save(), "the incident is saved")
    Set i%Made(inc.%Id()) = ""
    Quit inc
}

/// The site's policy for tier 2 single chains, set for the test; the stored profile is put back after it.
Method SetPolicy(word As %String)
{
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    If ..SavedProfile = $CHAR(0) Set ..SavedProfile = $SELECT($ISOBJECT(row): row.Json, 1: "")
    Set p = ##class(Shutter.Store.SiteProfile).Current()
    Set version = +p.version
    Do p.%Remove("version")
    If '$ISOBJECT(p.%Get("policy")) Set p.policy = {}
    If '$ISOBJECT(p.policy.%Get("2")) Do p.policy.%Set("2", {})
    Do p.policy.%Get("2").%Set("single", word)
    If '$ISOBJECT(row) Set row = ##class(Shutter.Store.SiteProfile).%New(), row.Version = version
    Set row.Json = p.%ToJSON()
    Do $$$AssertStatusOK(row.%Save(), "the site's policy for tier 2 single is " _ word _ " for the test")
}

Method RestoreProfile()
{
    Quit:(..SavedProfile = $CHAR(0))
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    If ..SavedProfile = "" {
        If $ISOBJECT(row) Do ##class(Shutter.Store.SiteProfile).%DeleteId(row.%Id())
    } ElseIf $ISOBJECT(row) {
        Set row.Json = ..SavedProfile
        Do row.%Save()
    }
    Set ..SavedProfile = $CHAR(0)
}

Method CaseSays(case As Shutter.Store.Case, text As %String) As %Boolean
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Text FROM Shutter_Store.CaseEvent WHERE ""Case"" = ?", case.%Id())
    While rs.%Next() { If rs.%Get("Text") [ text Return 1 }
    Quit 0
}

Method IncidentSays(inc As Shutter.Store.Incident, text As %String) As %Boolean
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Text FROM Shutter_Store.IncidentEvent WHERE Incident = ?", inc.%Id())
    While rs.%Next() { If rs.%Get("Text") [ text Return 1 }
    Quit 0
}

}
