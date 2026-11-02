/// A watched production's failures (CONTRACTS 11, v1.38): their cases run in the site's watched mode, policy unless the
/// site set another, whatever mode the scenarios run in, and a case the alert intake opened first takes the production's
/// own report of the failure when it arrives before the evidence is collected. The globals and the case are put back.
Class Shutter.Test.WatchedIntake Extends %UnitTest.TestCase
{

Method TestWatchedModeIsPolicyWhateverTheScenariosRunIn()
{
    Set keepMode = $GET(^Shutter.Config("mode")), keepWatched = $DATA(^Shutter.Config("watchedMode")), watched = $GET(^Shutter.Config("watchedMode"))
    Set ^Shutter.Config("mode") = "board"
    Kill ^Shutter.Config("watchedMode")
    Set r = ##class(Shutter.Msg.ExternalIntake).%New()
    Do $$$AssertEquals(##class(Shutter.Process.Intake).ModeFor(r), "board", "the API's own intake with no source follows the scenarios' mode")
    Set r.SourceNamespace = "HOSPITAL"
    Do $$$AssertEquals(##class(Shutter.Process.Intake).ModeFor(r), "policy", "a watched production's failure runs in policy mode, though the scenarios run boards")
    Set r.Mode = "rules"
    Do $$$AssertEquals(##class(Shutter.Process.Intake).ModeFor(r), "rules", "a mode the request names wins")
    Set r.Mode = "", ^Shutter.Config("watchedMode") = "single"
    Do $$$AssertEquals(##class(Shutter.Process.Intake).ModeFor(r), "single", "a site's own watched mode wins over the default")
    Set ^Shutter.Config("mode") = keepMode
    Kill ^Shutter.Config("watchedMode")
    If keepWatched Set ^Shutter.Config("watchedMode") = watched
}

Method TestTheProductionsReportReplacesTheAlertsWords()
{
    Set op = {"operation_key": "PAS^HOSP^MRN-UT-WI^ENC-UT-WI^admit^2026-11-02T19:00:00Z", "encounter_id": "ENC-UT-WI", "patient_id": "MRN-UT-WI", "patient_id_authority": "HOSP", "event": "admit", "ward": "WARD-A", "event_time": "2026-11-02T19:00:00Z", "source_system": "PAS"}
    Set sc = ##class(Shutter.Store.Case).Open(op, "delivery_failed", "Alert from Downstream Out at 2026-11-02 19:00:01 UTC: Received non-OK status 503", "", "", "policy", .case, .opened, "Downstream Out")
    If '$$$AssertStatusOK(sc, "a case as the alert intake opens it") Quit
    Set case.FailureReasonCode = "alert", case.FailureOutcome = "error", case.FailureHttpStatus = 503
    Do case.%Save()
    Set id = case.%Id()
    Set report = ##class(Shutter.Msg.CaseIntake).%New()
    Set report.FailureKind = "delivery_failed", report.FailureText = "Delivery unavailable (ward_unavailable), HTTP 503: The ward system is unavailable"
    Set report.WardResultJSON = {"outcome": "unavailable", "reason_code": "ward_unavailable", "http_status": 503, "retry_after_seconds": 20}.%ToJSON()
    Set report.SourceHeaderId = "0"
    Do $$$AssertEquals(##class(Shutter.Process.CaseWorkflow).TakeReport(case, report), 1, "the report is taken while the case is detected")
    Set again = ##class(Shutter.Store.Case).%OpenId(id)
    Do $$$AssertEquals(again.FailureReasonCode _ "|" _ again.FailureOutcome _ "|" _ again.FailureHttpStatus, "ward_unavailable|unavailable|503", "the connector's answer replaces the alert's")
    Do $$$AssertEquals(again.FailureText, report.FailureText, "and its words")
    Do $$$AssertNotEquals(again.RetryAfterUntil, "", "and the Retry-After")
    Do $$$AssertTrue(again.Headline [ "not delivered", "the headline is rebuilt from them: " _ again.Headline)
    Do $$$AssertEquals(##class(Shutter.Process.CaseWorkflow).TakeReport(again, report), 0, "a case whose failure is already the report's takes nothing")
    Set again.FailureReasonCode = "alert", again.State = "investigating"
    Do again.%Save()
    Do $$$AssertEquals(##class(Shutter.Process.CaseWorkflow).TakeReport(again, report), 0, "nor one whose evidence is collected")
    Set none = ##class(Shutter.Msg.CaseIntake).%New()
    Set none.FailureKind = "delivery_failed", none.FailureText = "Alert from Downstream Out: timeout", none.WardResultJSON = ""
    Set again.State = "detected"
    Do again.%Save()
    Do $$$AssertEquals(##class(Shutter.Process.CaseWorkflow).TakeReport(again, none), 0, "nor a second alert with no connector answer")
    Do ##class(Shutter.Store.Case).PurgeCase(id)
    Do $$$AssertEquals(##class(Shutter.Store.Case).%ExistsId(id), 0, "the test's case is gone")
}

}
