/// The publisher's tools (Shutter.Publish.Tools; CONTRACTS 15, v1.35): the shapes, that no patient or encounter identifier
/// leaves, and the audit row per call. Runs where the aihub module is loaded (the tools class is compiled) and is skipped
/// on the core edition.
Class Shutter.Test.Publish Extends %UnitTest.TestCase
{

Method TestPublisher()
{
    If '##class(%Dictionary.CompiledClass).%ExistsId("Shutter.Publish.Tools") {
        Do $$$AssertTrue(1, "Shutter.Publish.Tools is not compiled here (the core edition): the publisher's test is skipped")
        Quit
    }
    Set t = "Shutter.Publish.Tools", audit = "Shutter.Store.PublishCall"
    Set before = $CLASSMETHOD(audit, "CountSince", "2000-01-01T00:00:00Z"), want = 0
    Set h = $CLASSMETHOD(t, "Health"), want = want + 1
    Do $$$AssertTrue(h.%IsDefined("edition") && h.%IsDefined("casesOpen") && h.%IsDefined("publisherCallsToday"), "Health names the edition and the counts: " _ h.%ToJSON())
    Set list = $CLASSMETHOD(t, "ListCases", "", "", 3), want = want + 1
    Do $$$AssertTrue(list.%IsDefined("cases") && (list.count = list.cases.%Size()) && (list.count <= 3), "ListCases answers at most three cases: " _ list.count)
    Set unknown = $CLASSMETHOD(t, "GetCase", "C-NOSUCH")
    Do $$$AssertEquals(unknown.error, "not_found", "an unknown case is not_found")
    Do $$$AssertEquals($CLASSMETHOD(t, "GetIncident", "I-NOSUCH").error, "not_found", "and so is an unknown incident")
    Set incidents = $CLASSMETHOD(t, "ListIncidents", "", 2), want = want + 1
    Do $$$AssertTrue(incidents.%IsDefined("incidents") && (incidents.count <= 2), "ListIncidents answers")
    If list.count > 0 {
        Set row = list.cases.%Get(0)
        For k = "patientId", "encounterId", "ward", "bed", "patientIdAuthority", "priorPatientId" {
            Do $$$AssertNotTrue(row.%IsDefined(k), "a case row carries no " _ k)
        }
        Set case = ##class(Shutter.Store.Case).ByCaseId(row.caseId)
        Set one = $CLASSMETHOD(t, "GetCase", row.caseId), want = want + 1
        Do $$$AssertEquals(one.caseId _ "|" _ one.version, case.CaseId _ "|" _ case.Version, "GetCase names the case and its version")
        Do $$$AssertTrue(one.%IsDefined("plan") && one.%IsDefined("approval") && one.%IsDefined("precedents"), "with its plan, approval and precedents (null when none)")
        Set text = one.%ToJSON()
        If case.EncounterId '= "" Do $$$AssertNotTrue(text [ case.EncounterId, "the encounter id does not leave: " _ case.EncounterId)
        If case.PatientId '= "" Do $$$AssertNotTrue(text [ case.PatientId, "the patient id does not leave: " _ case.PatientId)
        Set events = $CLASSMETHOD(t, "GetEvents", row.caseId, 5), want = want + 1
        Do $$$AssertTrue(events.%IsDefined("events") && (events.count <= 5), "GetEvents answers at most five")
        If (case.EncounterId '= "") Do $$$AssertNotTrue(events.%ToJSON() [ case.EncounterId, "nor from the events")
        Set plan = $CLASSMETHOD(t, "GetPlan", row.caseId)
        Do $$$AssertTrue(plan.%IsDefined("plan") || (plan.error = "no_plan"), "GetPlan answers the plan or no_plan")
        // A plan the case does not have yet writes no audit row (v1.37), nor does an unknown case or incident.
        If plan.%IsDefined("plan") Set want = want + 1
        Set pre = $CLASSMETHOD(t, "GetPrecedents", row.caseId), want = want + 1
        Do $$$AssertTrue(pre.%IsDefined("summary") && pre.%IsDefined("precedents"), "GetPrecedents answers the summary and the rows")
    }
    Set after = $CLASSMETHOD(audit, "CountSince", "2000-01-01T00:00:00Z")
    Do $$$AssertTrue(after >= (before + want), "every call that found its subject wrote an audit row (" _ (after - before) _ " new, " _ want _ " expected)")
    Set recent = $CLASSMETHOD(audit, "Recent", 1)
    Do $$$AssertTrue((recent.%Size() = 1) && (recent.%Get(0).tool '= ""), "the newest row names its tool: " _ recent.%ToJSON())
}

}
