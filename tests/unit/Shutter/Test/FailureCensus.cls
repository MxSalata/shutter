/// The failure coverage census (CONTRACTS 17): it compares a watched receiver's failed deliveries with Shutter's cases, and
/// never opens or closes a case and never sends anything. The fixture here uses real Ens.MessageHeader rows and real cases in
/// this namespace, under its own item names, all taken away afterwards; tests/e2e/census_check.py plays it on real failures in a
/// real watched namespace.
Class Shutter.Test.FailureCensus Extends %UnitTest.TestCase
{

Parameter ITEM = "UT Census Out";

Method OnAfterAllTests() As %Status
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Ens.MessageHeader WHERE SourceConfigName = ?", "UT Census Source")
    While rs.%Next() { Do ##class(Ens.MessageHeader).%DeleteId(rs.%Get("ID")) }
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Shutter_Store.""Case"" WHERE Receiver %STARTSWITH ?", ..#ITEM)
    While rs.%Next() { Do ##class(Shutter.Store.Case).PurgeCase(rs.%Get("ID")) }
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT RunId FROM Shutter_Store.CensusRun WHERE Item %STARTSWITH ?", ..#ITEM)
    While rs.%Next() { Do ##class(Shutter.Store.CensusRun).Remove(rs.%Get("RunId")) }
    Quit $$$OK
}

/// An item name no other test has used, so that one test's rows stay out of another's window.
Method Fresh() As %String
{
    Quit ..#ITEM _ " " _ $INCREMENT(^||censusItem)
}

/// A real header: a delivery to the item (or a header of the session when type says so).
Method Header(target As %String, session As %Integer, status As %Integer, body As %String = "", bodyClass As %String = "EnsLib.HL7.Message", isError As %Boolean = 0, description As %String = "", type As %Integer = 1) As %String
{
    Set h = ##class(Ens.MessageHeader).%New()
    Set h.Type = type, h.SessionId = session, h.Status = status, h.IsError = isError
    Set h.SourceConfigName = "UT Census Source", h.TargetConfigName = target
    Set h.MessageBodyClassName = bodyClass, h.MessageBodyId = body, h.Description = description
    Set h.TimeCreated = $ZDATETIME($ZTIMESTAMP, 3, 1, 3)
    Do $$$AssertStatusOK(h.%Save(), "a header to " _ target)
    Quit h.%Id()
}

/// A real HL7 body with this control id.
Method Body(control As %String) As %String
{
    Set m = ##class(EnsLib.HL7.Message).ImportFromString("MSH|^~\&|UT|HOSP|X|HOSP|20261106010000||ADT^A01^ADT_A01|" _ control _ "|P|2.5.1" _ $CHAR(13) _ "PID|1||MRN" _ control _ "^^^HOSP^MR||SYNTH^SECRETNAME" _ $CHAR(13))
    Do m.%Save()
    Quit m.%Id()
}

/// A real case of a forwarded failure, as Case Intake leaves it.
Method Case(receiver As %String, origin As %String, tag As %String) As %String
{
    Set op = {"operation_key": ("PAS^HOSP^MRN-UT-FC^ENC-" _ tag _ "^admit^2026-11-06T01:00:00Z"), "encounter_id": ("ENC-" _ tag), "patient_id": "MRN-UT-FC", "patient_id_authority": "HOSP", "event": "admit", "ward": "WARD-A", "event_time": "2026-11-06T01:00:00Z", "source_system": "PAS"}
    Set sc = ##class(Shutter.Store.Case).Open(op, "delivery_failed", "UT census", "", "", "policy", .case, .opened, receiver)
    Do $$$AssertStatusOK(sc, "a case for " _ tag)
    Set case.SourceNamespace = $NAMESPACE, case.SourceProduction = "UT.Production", case.SourceRoute = "UT In", case.OriginHeaderId = origin
    Do $$$AssertStatusOK(case.%Save(), "its source")
    Quit case.CaseId
}

/// The settings a test runs under: on, with nothing settling, as a site would set them.
Method Settings(maxHeaders As %Integer = 10000) As %DynamicObject
{
    Quit {"enabled": true, "max_window_hours": 24, "max_headers": (maxHeaders), "retention_days": 30, "settle_seconds": 0}
}

/// A session number no other test uses.
Method Session() As %Integer
{
    Quit 900000000 + $INCREMENT(^||censusSession) + ($RANDOM(9000000) * 10)
}

Method TestItIsOffUnlessTheProfileSaysOn()
{
    Set util = "Shutter.Util.FailureCensus"
    Set p = ##class(Shutter.Store.SiteProfile).Default()
    Do $$$AssertNotTrue(p.%IsDefined("failure_census"), "the shipped default names no census")
    Set s = $CLASSMETHOD(util, "Settings", p)
    Do $$$AssertEquals(s.%Get("enabled"), 0, "so it is off")
    Do $$$AssertEquals(s."max_window_hours" _ "|" _ s."max_headers" _ "|" _ s."retention_days" _ "|" _ s."settle_seconds", "24|10000|30|120", "the limits' defaults")
    Do p.%Set("failure_census", {"enabled": true, "max_headers": 50})
    Set s = $CLASSMETHOD(util, "Settings", p)
    Do $$$AssertEquals(s.%Get("enabled"), 1, "the profile turns it on")
    Do $$$AssertEquals(s."max_headers", 50, "and sets a limit")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Validate(p), "", "the validator takes the block")
    For bad = {"enabled": "yes"}, {"max_window_hours": 0}, {"max_window_hours": 1000}, {"max_headers": -1}, {"max_headers": 1.5}, {"retention_days": "x"}, {"settle_seconds": -1}, {"nonsense": 1} {
        Do p.%Set("failure_census", bad)
        Do $$$AssertNotEquals(##class(Shutter.Store.SiteProfile).Validate(p), "", "refused: " _ bad.%ToJSON())
    }
    Do p.%Set("failure_census", "on")
    Do $$$AssertNotEquals(##class(Shutter.Store.SiteProfile).Validate(p), "", "refused: not an object")
}

Method TestAWindowIsWholeAndInsideTheLimit()
{
    Set util = "Shutter.Util.FailureCensus", s = ..Settings()
    Set now = ##class(Shutter.Util.Time).NowUTC(), hour = ##class(Shutter.Util.Time).FromNow(-3600), old = ##class(Shutter.Util.Time).FromNow(-90000), soon = ##class(Shutter.Util.Time).FromNow(3600)
    Do $$$AssertEquals($CLASSMETHOD(util, "WindowProblem", hour, now, s), "", "an hour up to now")
    Do $$$AssertNotEquals($CLASSMETHOD(util, "WindowProblem", now, hour, s), "", "refused: it ends before it starts")
    Do $$$AssertNotEquals($CLASSMETHOD(util, "WindowProblem", old, now, s), "", "refused: 25 hours over a limit of 24")
    Do $$$AssertNotEquals($CLASSMETHOD(util, "WindowProblem", hour, soon, s), "", "refused: it ends in the future, so the count is not final")
    Do $$$AssertNotEquals($CLASSMETHOD(util, "WindowProblem", "yesterday", now, s), "", "refused: not a time")
    Do $$$AssertNotEquals($CLASSMETHOD(util, "WindowProblem", "2026-13-45T99:00:00Z", now, s), "", "refused: no such date")
    Do $$$AssertNotEquals($CLASSMETHOD(util, "WindowProblem", hour _ "' OR 1=1 --", now, s), "", "refused: SQL text")
}

/// The link rule, on plain data: a case is tied to a delivery only as far as the record establishes it.
Method TestTheLinkRule()
{
    Set util = "Shutter.Util.FailureCensus"
    Set origins = {"100": "7", "101": "7", "200": "8", "300": ""}
    Set cands = [{"origin": "100", "caseId": "C-1"}]
    Set r = $CLASSMETHOD(util, "Link", "101", "7", 1, cands, origins)
    Do $$$AssertEquals(r.quality _ "|" _ r.code, "exact|only_delivery_in_session", "the session's one message to the receiver: exact")
    Do $$$AssertEquals(r.cases.%Get(0), "C-1", "with its case")
    Set r = $CLASSMETHOD(util, "Link", "101", "7", 2, cands, origins)
    Do $$$AssertEquals(r.quality _ "|" _ r.code, "ambiguous|several_deliveries_in_session", "two different messages to the receiver in the session: ambiguous, not guessed")
    Do $$$AssertEquals(r.cases.%Get(0), "C-1", "and it still names the candidate")
    Set r = $CLASSMETHOD(util, "Link", "100", "7", 2, cands, origins)
    Do $$$AssertEquals(r.quality _ "|" _ r.code, "exact|origin_is_this_delivery", "a case that names this very delivery is exact, however many others the session has")
    Set r = $CLASSMETHOD(util, "Link", "200", "8", 1, cands, origins)
    Do $$$AssertEquals(r.quality _ "|" _ r.code, "none|no_case", "another session: no link")
    Do $$$AssertEquals(r.cases.%Size(), 0, "and no case")
    Set r = $CLASSMETHOD(util, "Link", "102", "7", 1, [{"origin": "100", "caseId": "C-1"}, {"origin": "101", "caseId": "C-2"}], origins)
    Do $$$AssertEquals(r.cases.%Size(), 2, "two cases for one delivery are both named")
    Set r = $CLASSMETHOD(util, "Link", "101", "7", 1, [{"origin": "300", "caseId": "C-3"}], origins)
    Do $$$AssertEquals(r.quality, "none", "an origin that is gone ties to nothing")
}

/// The fixture: ten deliveries, four failures, two exactly linked, one never forwarded, one ambiguous; a real run.
Method TestTheFixtureGivesItsExactCategories()
{
    Set item = ..Fresh(), other = item _ " Other"
    Set from = ##class(Shutter.Util.Time).FromNow(-2)
    // Six that completed; one shares its session with the ambiguous failure.
    For i = 1:1:5 { Do ..Header(item, ..Session(), 9, ..Body("C" _ i)) }
    // Exact: the session's only delivery, the case naming the session's first header.
    Set s1 = ..Session(), first1 = ..Header("UT Router", s1, 9, ..Body("E1")), f1 = ..Header(item, s1, 8, ..Body("E1B"), , 1)
    Set c1 = ..Case(item, first1, "FC1" _ s1)
    // Exact: the case names the delivery itself.
    Set s2 = ..Session(), f2 = ..Header(item, s2, 5, ..Body("E2"), , 1)
    Set c2 = ..Case(item, f2, "FC2" _ s2)
    // Never forwarded.
    Set s3 = ..Session(), f3 = ..Header(item, s3, 8, ..Body("N1"), , 1)
    // Ambiguous: two different messages to the item in one session, one failed, the case naming the session's first header.
    Set s4 = ..Session(), first4 = ..Header("UT Router", s4, 9, ..Body("A0")), ok4 = ..Header(item, s4, 9, ..Body("A1")), f4 = ..Header(item, s4, 8, ..Body("A2"), , 1)
    Set c4 = ..Case(item, first4, "FC4" _ s4)
    // The same control id at another receiver: its failure and case do not touch this receiver's count.
    Set s5 = ..Session(), o1 = ..Header(other, s5, 8, ..Body("N1"), , 1)
    Set c5 = ..Case(other, o1, "FC5" _ s5)
    Set before = ..Counts()
    Set sc = ##class(Shutter.Util.FailureCensus).RunScope(item, $NAMESPACE, item, from, ##class(Shutter.Util.Time).FromNow(2), "ut", ..Settings(), .run)
    If '$$$AssertStatusOK(sc, "the run") Quit
    Set t = ##class(%DynamicObject).%FromJSON(run.TotalsJson)
    Do $$$AssertEquals(t.deliveries, 10, "ten deliveries")
    Do $$$AssertEquals(t.completed, 6, "six completed, outside the denominator")
    Do $$$AssertEquals(t.eligible, 4, "four engine-visible failures")
    Do $$$AssertEquals(t.exact, 2, "two exactly linked")
    Do $$$AssertEquals(t.none, 1, "one with no linked case")
    Do $$$AssertEquals(t.ambiguous, 1, "one ambiguous")
    Do $$$AssertEquals(t.excluded, 0, "none excluded")
    Do $$$AssertEquals(t.unassessable, 0, "none unassessable")
    Do $$$AssertEquals(..LinkOf(run, f1), "exact|" _ c1, "the session's only delivery")
    Do $$$AssertEquals(..LinkOf(run, f2), "exact|" _ c2, "the delivery the case names")
    Do $$$AssertEquals(..LinkOf(run, f3), "none|", "the unforwarded failure, in spite of the same control id at another receiver")
    Do $$$AssertEquals(..LinkOf(run, f4), "ambiguous|" _ c4, "the two-message session")
    Do $$$AssertEquals(..LinkOf(run, ok4), "", "a completed delivery has no row")
    Do $$$AssertEquals(..Counts(), before, "the run opened, closed and changed no case, and wrote no header")
    Set text = ##class(Shutter.Util.FailureCensus).Report(run).%ToJSON()
    Do $$$AssertTrue(text '[ "SECRETNAME", "no message content in the report")
    Do $$$AssertTrue(text '[ "MRN", "nor the patient's number")
    Do $$$AssertEquals(##class(Shutter.Util.FailureCensus).Report(run).items.%Get(0).family, "ADT", "the family, not the content")
    Set stream = ##class(Shutter.Util.FailureCensus).Csv(run)
    Set csv = stream.Read(1000000)
    Do $$$AssertTrue(csv '[ "SECRETNAME", "no message content in the CSV")
    Do $$$AssertEquals($LENGTH(csv, $CHAR(13, 10)) - 1, 6, "the header, the run's row and four rows")
    Do $$$AssertTrue($PIECE(csv, $CHAR(13, 10), 1) = ##class(Shutter.Util.FailureCensus).#CSVCOLUMNS, "the columns")
}

/// Two failures that went to one open case: both exact, one case, through the intake trail in Shutter's own messages.
Method TestAFurtherFailureOnOneCaseIsManyToOne()
{
    Set util = "Shutter.Util.FailureCensus"
    Set data = {"readable": true, "error": "", "scanned": 2, "truncated": false, "completed": 0, "notFinished": 0, "missingIds": 0, "reachesBack": false,
        "failures": [{"id": "11", "session": "5", "status": 8, "isError": true, "time": "2026-11-06 01:00:00.000", "bodyClass": "EnsLib.HL7.Message", "bodyPresent": true, "family": "ADT", "hl7InSession": true, "toTarget": 1, "resendOf": ""},
                     {"id": "12", "session": "6", "status": 8, "isError": true, "time": "2026-11-06 01:00:01.000", "bodyClass": "EnsLib.HL7.Message", "bodyPresent": true, "family": "ADT", "hl7InSession": true, "toTarget": 1, "resendOf": ""}],
        "origins": {"11": "5", "12": "6"}}
    Set cands = [{"origin": "11", "caseId": "C-9", "inWindow": true}, {"origin": "12", "caseId": "C-9", "inWindow": true}]
    Set out = $CLASSMETHOD(util, "Compare", data, cands, ..Settings(), 0)
    Do $$$AssertEquals(out.totals.exact, 2, "two failures are exactly linked")
    Do $$$AssertEquals(out.totals.distinctCases, 1, "to one case, counted once")
    Do $$$AssertEquals(out.completeness, "complete", "and nothing is missing")
}

/// No answer from the source is unknown: no total reads zero, and none reads as covered.
Method TestAnUnreadableSourceIsUnknownNotZero()
{
    For ns = "NOSUCHNAMESPACE", "%SYS" {
        Set sc = ##class(Shutter.Util.FailureCensus).RunScope(..#ITEM, ns, ..#ITEM, ##class(Shutter.Util.Time).FromNow(-60), ##class(Shutter.Util.Time).NowUTC(), "ut", ..Settings(), .run)
        If '$$$AssertStatusOK(sc, "the run ends with its answer, " _ ns) Continue
        Do $$$AssertEquals(run.Completeness, "unknown", ns _ ": unknown")
        Do $$$AssertEquals(run.SourceRead, "unavailable", ns _ ": the source could not be read")
        Do $$$AssertNotEquals(run.SourceError, "", ns _ ": and it says why")
        Set r = ##class(Shutter.Util.FailureCensus).Report(run)
        Do $$$AssertEquals(r.totals.%GetTypeOf("eligible"), "null", ns _ ": failures are null, not 0")
        Do $$$AssertEquals(r.totals.%GetTypeOf("none"), "null", ns _ ": and so is no linked case")
        Do $$$AssertEquals(r.totals.%GetTypeOf("deliveries"), "null", ns _ ": and the deliveries")
        Set csv = ##class(Shutter.Util.FailureCensus).Csv(run).Read(100000)
        Do $$$AssertTrue($PIECE(csv, $CHAR(13, 10), 2) [ "unknown", ns _ ": the CSV says unknown on its run row")
    }
}

/// A cap hit is an incomplete census, however good the part read looks.
Method TestACapHitIsIncomplete()
{
    Set item = ..Fresh(), from = ##class(Shutter.Util.Time).FromNow(-2)
    For i = 1:1:4 { Do ..Header(item, ..Session(), 9, ..Body("K" _ i)) }
    Set sc = ##class(Shutter.Util.FailureCensus).RunScope(item, $NAMESPACE, item, from, ##class(Shutter.Util.Time).FromNow(2), "ut", ..Settings(3), .run)
    If '$$$AssertStatusOK(sc, "the run") Quit
    Do $$$AssertEquals(run.Completeness, "incomplete", "incomplete")
    Do $$$AssertEquals(run.Scanned, 3, "it stopped at the cap")
    Do $$$AssertTrue(run.ReasonsJson [ "header_cap_hit", "and says so: " _ run.ReasonsJson)
    Do $$$AssertEquals(##class(Shutter.Util.FailureCensus).Report(run).complete, 0, "the report never says complete")
    // On plain data: no failure seen and a cap hit is still not complete.
    Set data = {"readable": true, "error": "", "scanned": 3, "truncated": true, "completed": 3, "notFinished": 0, "missingIds": 0, "reachesBack": false, "failures": [], "origins": {}}
    Do $$$AssertEquals(##class(Shutter.Util.FailureCensus).Compare(data, [], ..Settings(3), 0).completeness, "incomplete", "no failures in the part read proves nothing")
}

/// A header deleted from the store is an evidence gap, and so is a case whose origin is gone.
Method TestAPurgedHeaderIsAnEvidenceGap()
{
    Set item = ..Fresh(), from = ##class(Shutter.Util.Time).FromNow(-2), to = ##class(Shutter.Util.Time).FromNow(2)
    Set s = ..Session(), a = ..Header(item, s, 8, ..Body("P1"), , 1), b = ..Header(item, ..Session(), 8, ..Body("P2"), , 1), c = ..Header(item, ..Session(), 9, ..Body("P3"))
    Set caseB = ..Case(item, b, "FCP" _ s)
    Do ##class(Shutter.Util.FailureCensus).RunScope(item, $NAMESPACE, item, from, to, "ut", ..Settings(), .before)
    Do ##class(Ens.MessageHeader).%DeleteId(b)
    Set sc = ##class(Shutter.Util.FailureCensus).RunScope(item, $NAMESPACE, item, from, to, "ut", ..Settings(), .after)
    If '$$$AssertStatusOK(sc, "the run") Quit
    Set t0 = ##class(%DynamicObject).%FromJSON(before.TotalsJson), t1 = ##class(%DynamicObject).%FromJSON(after.TotalsJson)
    Do $$$AssertEquals(t1.missingIds, t0.missingIds + 1, "the missing header is counted")
    Do $$$AssertEquals(after.Completeness, "incomplete", "so the census is incomplete")
    Do $$$AssertTrue(after.ReasonsJson [ "header_ids_missing", "for that reason: " _ after.ReasonsJson)
    Do $$$AssertTrue(after.ReasonsJson [ "case_origin_purged", "and for the case: " _ after.ReasonsJson)
    Set row = ..RowOfCase(after, caseB)
    Do $$$AssertEquals(row, "unknown|none|case_origin_purged", "the case's row says the evidence is gone")
    // A window reaching back past what the store keeps.
    Set data = {"readable": true, "error": "", "scanned": 0, "truncated": false, "completed": 0, "notFinished": 0, "missingIds": 0, "reachesBack": true, "failures": [], "origins": {}}
    Do $$$AssertEquals(##class(Shutter.Util.FailureCensus).Compare(data, [], ..Settings(), 0).completeness, "incomplete", "no headers in a window older than the store is not zero failures")
}

/// What a failure is, and what it is not: the completed transport answer stays outside; an error flag on a completed header
/// is inside; a failure with no HL7 in its session is excluded, since the intake takes HL7 only; a very new one with no case
/// may still be on its way; a body that is gone is unassessable.
Method TestWhatCountsAndWhatDoesNot()
{
    Set item = ..Fresh(), from = ##class(Shutter.Util.Time).FromNow(-2)
    Set comp = ..Header(item, ..Session(), 9, ..Body("W1"))
    Set flagged = ..Header(item, ..Session(), 9, ..Body("W2"), , 1)
    Set sus = ..Header(item, ..Session(), 5, ..Body("W3"))
    Set queued = ..Header(item, ..Session(), 2, ..Body("W4"))
    Set plain = ..Header(item, ..Session(), 8, "1", "Ens.StringRequest", 1)
    Set gone = ..Header(item, ..Session(), 8, "999999999", , 1)
    Set resent = ..Header(item, ..Session(), 8, ..Body("W5"), , 1, "Resent " _ sus)
    Set response = ..Header(item, ..Session(), 8, ..Body("W6"), , 1, "", 2)
    Set sc = ##class(Shutter.Util.FailureCensus).RunScope(item, $NAMESPACE, item, from, ##class(Shutter.Util.Time).FromNow(2), "ut", ..Settings(), .run)
    If '$$$AssertStatusOK(sc, "the run") Quit
    Do $$$AssertEquals(..LinkOf(run, comp), "", "completed: no row")
    Do $$$AssertEquals(..LinkOf(run, queued), "", "queued: no row")
    Do $$$AssertEquals(..LinkOf(run, response), "", "a response is not a delivery")
    Do $$$AssertEquals(..LinkOf(run, flagged), "none|", "completed with the error flag: a failure")
    Do $$$AssertEquals(..LinkOf(run, sus), "none|", "suspended: a failure")
    Do $$$AssertEquals(..EligibilityOf(run, plain), "excluded|no_hl7_in_session", "no HL7 in the session: excluded")
    Do $$$AssertEquals(..EligibilityOf(run, gone), "unknown|body_missing", "the body is gone: unassessable")
    Set row = ##class(Shutter.Store.CensusItem).Of(run, resent)
    Do $$$AssertEquals(row.ResendOf, sus, "the engine's own record of a resend")
    Set t = ##class(%DynamicObject).%FromJSON(run.TotalsJson)
    Do $$$AssertEquals(t.completed, 1, "completed counted")
    Do $$$AssertEquals(t.notFinished, 1, "unfinished counted apart")
    Do $$$AssertEquals(t.excluded, 1, "excluded counted")
    // Settling: a failure younger than the setting, with no case yet.
    Set s = ..Settings(), s."settle_seconds" = 3600
    Set sc = ##class(Shutter.Util.FailureCensus).RunScope(item, $NAMESPACE, item, from, ##class(Shutter.Util.Time).FromNow(2), "ut", s, .young)
    Do $$$AssertEquals(..EligibilityOf(young, sus), "unknown|settling", "too new to say it has no case")
    Do $$$AssertEquals(young.Completeness, "incomplete", "so the census is not complete yet")
}

Method TestTheScopeIsOnlyWhatIsRegistered()
{
    Set util = "Shutter.Util.FailureCensus"
    Merge keep = ^Shutter.Config("onboard")
    Kill ^Shutter.Config("onboard")
    Set ^Shutter.Config("onboard", "UTWARD", "receivers", "Lab Out") = "UTWARD Lab Out"
    Set ^Shutter.Config("onboard", $NAMESPACE, "receivers", "Own Out") = "Own Out"
    Set found = $CLASSMETHOD(util, "ScopeOf", "UTWARD Lab Out", .ns, .item)
    Do $$$AssertEquals(found _ "|" _ ns _ "|" _ item, "1|UTWARD|Lab Out", "the reported name finds the namespace and the item, past the prefix")
    Do $$$AssertEquals($CLASSMETHOD(util, "ScopeOf", "Lab Out", .ns, .item), 0, "the bare item is not what was registered")
    Do $$$AssertEquals($CLASSMETHOD(util, "ScopeOf", "Own Out", .ns, .item), 0, "Shutter's own namespace is not a watched one")
    Do $$$AssertEquals($CLASSMETHOD(util, "ScopeOf", "' OR 1=1 --", .ns, .item), 0, "nor is free text")
    Do $$$AssertEquals($CLASSMETHOD(util, "Scopes").%Size(), 1, "one scope to offer")
    Kill ^Shutter.Config("onboard")
    Merge ^Shutter.Config("onboard") = keep
}

Method TestTheCsvCannotRunInASpreadsheet()
{
    Set util = "Shutter.Util.FailureCensus"
    Do $$$AssertEquals($CLASSMETHOD(util, "Cell", "plain"), "plain", "plain text")
    Do $$$AssertEquals($CLASSMETHOD(util, "Cell", "a,b"), """a,b""", "a comma is quoted")
    Do $$$AssertEquals($CLASSMETHOD(util, "Cell", "say ""hi"""), """say """"hi""""""", "a quote is doubled")
    For bad = "=1+1", "+1", "-1", "@x" {
        Do $$$AssertEquals($EXTRACT($CLASSMETHOD(util, "Cell", bad), 1), "'", "a formula is defused: " _ bad)
    }
}

Method TestOldRunsGo()
{
    Set sc = ##class(Shutter.Util.FailureCensus).RunScope(..#ITEM, "NOSUCHNAMESPACE", ..#ITEM, ##class(Shutter.Util.Time).FromNow(-60), ##class(Shutter.Util.Time).NowUTC(), "ut", ..Settings(), .old)
    Set id = old.RunId, old.StartedAt = ##class(Shutter.Util.Time).FromNow(-40 * 86400)
    Do old.%Save()
    Do $$$AssertEquals(##class(Shutter.Store.CensusRun).PurgeOlder(30) >= 1, 1, "a run past the retention goes")
    Do $$$AssertNotTrue($ISOBJECT(##class(Shutter.Store.CensusRun).ByRunId(id)), "and is gone")
}

/// The cases' states, versions and events, and the headers: all the run may not touch.
Method Counts() As %String
{
    Set out = ""
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS N, SUM(Version) AS V FROM Shutter_Store.""Case""")
    Do rs.%Next() Set out = out _ rs.%Get("N") _ "/" _ rs.%Get("V")
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS N FROM Shutter_Store.CaseEvent")
    Do rs.%Next() Set out = out _ "/" _ rs.%Get("N")
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS N FROM Shutter_Store.ExecutionAttempt")
    Do rs.%Next() Set out = out _ "/" _ rs.%Get("N")
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS N FROM Ens.MessageHeader")
    Do rs.%Next() Set out = out _ "/" _ rs.%Get("N")
    Quit out
}

Method LinkOf(run As Shutter.Store.CensusRun, header As %String) As %String
{
    Set row = ##class(Shutter.Store.CensusItem).Of(run, header)
    If '$ISOBJECT(row) Quit ""
    Quit row.LinkQuality _ "|" _ row.CaseIds
}

Method EligibilityOf(run As Shutter.Store.CensusRun, header As %String) As %String
{
    Set row = ##class(Shutter.Store.CensusItem).Of(run, header)
    If '$ISOBJECT(row) Quit ""
    Quit row.Eligibility _ "|" _ row.Explanation
}

Method RowOfCase(run As Shutter.Store.CensusRun, caseId As %String) As %String
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Eligibility, LinkQuality, Explanation FROM Shutter_Store.CensusItem WHERE Run = ? AND CaseIds = ?", run.%Id(), caseId)
    If 'rs.%Next() Quit ""
    Quit rs.%Get("Eligibility") _ "|" _ rs.%Get("LinkQuality") _ "|" _ rs.%Get("Explanation")
}

}
