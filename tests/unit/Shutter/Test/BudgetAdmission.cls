/// Admission to the day's model budget (R145-03, R145-04; Shutter.Util.Budget.Admit and Shutter.Bridge.Runner.Diagnostic):
/// a run is admitted only when the day's spend, the reservations in flight and its own estimate stay within the cap and the
/// asker's share, checked and reserved in one locked step; the SQL diagnostic goes through the same admission before any
/// runner is made and records what it spent as a diagnostic row with no case. No provider is contacted: the admitted
/// diagnostic runs on Shutter.Test.FakeRunner. The cap, the share, the estimate and the reservations are put back afterwards.
Class Shutter.Test.BudgetAdmission Extends %UnitTest.TestCase
{

Property SavedCap As %String;

Property SavedShare As %String;

Property SavedReserve As %String;

Property SavedReservations As %String [ MultiDimensional ];

Method OnBeforeAllTests() As %Status
{
    Set ..SavedCap = $GET(^Shutter.Config("dailyBudgetUsd"), "<none>")
    Set ..SavedShare = $GET(^Shutter.Config("judgeBudgetUsd"), "<none>")
    Set ..SavedReserve = $GET(^Shutter.Config("budgetReserveUsd"), "<none>")
    Merge ..SavedReservations = ^Shutter.Budget("reserve")
    Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
    If ..SavedCap = "<none>" { Kill ^Shutter.Config("dailyBudgetUsd") } Else { Set ^Shutter.Config("dailyBudgetUsd") = ..SavedCap }
    If ..SavedShare = "<none>" { Kill ^Shutter.Config("judgeBudgetUsd") } Else { Set ^Shutter.Config("judgeBudgetUsd") = ..SavedShare }
    If ..SavedReserve = "<none>" { Kill ^Shutter.Config("budgetReserveUsd") } Else { Set ^Shutter.Config("budgetReserveUsd") = ..SavedReserve }
    Kill ^Shutter.Budget("reserve"), ^Shutter.Test.BudgetRace, ^Shutter.Test.FakeRunner
    Merge ^Shutter.Budget("reserve") = ..SavedReservations
    Quit $$$OK
}

/// The cap set to the day's spend so far plus extra, to the micro-dollar, so the arithmetic holds on any instance.
ClassMethod CapAbove(extra As %Numeric) As %Numeric
{
    Set spent = ##class(Shutter.Util.Budget).Spent(##class(Shutter.Util.Budget).Status().since)
    Quit ##class(Shutter.Util.Budget).Configure($FNUMBER(spent + extra, "", 6))
}

/// Well under the cap, admission behaves as before: admitted, the estimate reserved for the asker, the day not exhausted;
/// with no cap at all, admitted too. Settling the key releases the reservation.
Method TestWellUnderTheCapIsAdmittedAsBefore()
{
    Set b = "Shutter.Util.Budget"
    Kill ^Shutter.Budget("reserve")
    Set ^Shutter.Config("budgetReserveUsd") = "0.50"
    Do $CLASSMETHOD(b, "ConfigureShare", "0")
    Do ..CapAbove(100)
    Do $$$AssertTrue($CLASSMETHOD(b, "Admit", "ut-adm-well", "approver", .st, .est), "a run well under the cap is admitted")
    Do $$$AssertEquals(est, .5, "with the site's estimate")
    Do $$$AssertNotTrue(st.exhausted, "and the day is not exhausted: " _ st.%ToJSON())
    Set r = $GET(^Shutter.Budget("reserve", "ut-adm-well"))
    Do $$$AssertEquals($LISTGET(r, 1) _ "|" _ $LISTGET(r, 3), ".5|approver", "the estimate is reserved for the asker")
    Do $$$AssertTrue($CLASSMETHOD(b, "AllowsFor", "approver", .st2), "the check ahead of a run agrees")
    Do $CLASSMETHOD(b, "Settle", "ut-adm-well")
    Do $$$AssertEquals($CLASSMETHOD(b, "Reserved", "", .n) _ "|" _ n, "0|0", "settling releases the reservation")
    Do $CLASSMETHOD(b, "Configure", "0")
    Do $$$AssertTrue($CLASSMETHOD(b, "Admit", "ut-adm-nocap", "approver", .st), "with no cap, admitted")
    Do $CLASSMETHOD(b, "Settle", "ut-adm-nocap")
    Do $$$AssertEquals($DATA(^Shutter.Budget("reserve", "ut-adm-nocap")), 0, "and settled")
}

/// Near the cap the estimate counts (the review's example: 4.90 of 5.00 spent, 0.50 estimated): refused with nothing
/// reserved and words that say what is left; a run whose estimate just fits is admitted, and the next one is refused.
Method TestNearTheCapTheEstimateCounts()
{
    Set b = "Shutter.Util.Budget"
    Kill ^Shutter.Budget("reserve")
    Set ^Shutter.Config("budgetReserveUsd") = "0.50"
    Do $CLASSMETHOD(b, "ConfigureShare", "0")
    Do ..CapAbove(.1)
    Set s = $CLASSMETHOD(b, "Status")
    Do $$$AssertNotTrue(s.exhausted, "0.10 left: the day is not spent")
    Do $$$AssertNotTrue($CLASSMETHOD(b, "Admit", "ut-adm-near", "approver", .st), "but a run estimated at 0.50 is refused")
    Do $$$AssertEquals($DATA(^Shutter.Budget("reserve", "ut-adm-near")), 0, "and nothing is reserved")
    Set words = $CLASSMETHOD(b, "Refusal", st)
    Do $$$AssertTrue((words [ "has 0.10 USD left") && (words [ "less than a run's estimate of 0.50 USD") && (words [ "not sent"), "the refusal says what is left and the estimate: " _ words)
    Do $$$AssertNotTrue($CLASSMETHOD(b, "AllowsFor", "approver", .st2), "the check ahead of a run refuses it too")
    Do $$$AssertNotTrue($CLASSMETHOD(b, "Allows", .st3), "and so does Allows")
    Do ..CapAbove(.5)
    Do $$$AssertTrue($CLASSMETHOD(b, "Admit", "ut-adm-fit", "approver", .st), "an estimate that just fits is admitted")
    Do $$$AssertNotTrue($CLASSMETHOD(b, "Admit", "ut-adm-next", "operator", .st), "and the next run is refused on its reservation")
    Do $$$AssertTrue($CLASSMETHOD(b, "Refusal", st) [ "1 run(s) in flight, 0.50 USD reserved", "the refusal names the run in flight: " _ $CLASSMETHOD(b, "Refusal", st))
    Do $CLASSMETHOD(b, "Settle", "ut-adm-fit")
    Do $$$AssertTrue($CLASSMETHOD(b, "Admit", "ut-adm-next", "operator"), "once it settles, the next is admitted")
    Do $CLASSMETHOD(b, "Settle", "ut-adm-next")
    Do $$$AssertEquals($CLASSMETHOD(b, "Reserved", "", .n) _ "|" _ n, "0|0", "all settled")
    // The review's own figures, with the spend recorded: a 5.00 cap above what the day had, 4.90 spent in a row, 0.50
    // estimated. Before admission counted the estimate, this run was admitted.
    Set since = $CLASSMETHOD(b, "Status").since, before = $CLASSMETHOD(b, "Spent", since)
    Do $CLASSMETHOD(b, "Configure", $FNUMBER(before + 5, "", 6))
    Set resp = ##class(Shutter.Bridge.Msg.AgentResponse).%New()
    Set resp.Mode = "live", resp.Model = "claude-opus-5-5", resp.PromptTokens = 1225000, resp.CompletionTokens = 0, resp.Status = "ok"
    Set resp.StartedAt = ##class(Shutter.Util.Time).NowUTC(), resp.RequestedBy = "ut-adm-spender"
    Set sc = ##class(Shutter.Store.AgentRun).FromDiagnostic("conformance", resp, .row)
    Do $$$AssertStatusOK(sc, "a row of 4.90 recorded")
    If $$$ISERR(sc) Quit
    Set s = $CLASSMETHOD(b, "Status")
    Do $$$AssertEquals(s.spentTodayUsd - before, 4.9, "the day's spend reads it: " _ s.spentTodayUsd)
    Do $$$AssertNotTrue(s.exhausted, "4.90 of 5.00: not spent")
    Do $$$AssertNotTrue($CLASSMETHOD(b, "Admit", "ut-adm-review", "approver", .st), "and a run estimated at 0.50 is refused")
    Do $$$AssertTrue($CLASSMETHOD(b, "Refusal", st) [ "has 0.10 USD left", "with what is left: " _ $CLASSMETHOD(b, "Refusal", st))
    Do $$$AssertEquals($DATA(^Shutter.Budget("reserve", "ut-adm-review")), 0, "nothing reserved")
    Do ##class(Shutter.Store.AgentRun).%DeleteId(row.%Id())
}

/// The asker's share counts the estimate too, per user; the feed's own runs ("system") have no share.
Method TestAShareCountsTheEstimate()
{
    Set b = "Shutter.Util.Budget"
    Kill ^Shutter.Budget("reserve")
    Set ^Shutter.Config("budgetReserveUsd") = "0.50"
    Do $CLASSMETHOD(b, "Configure", "0")
    Set user = "ut-adm-share-" _ $JOB, other = "ut-adm-other-" _ $JOB
    Do $CLASSMETHOD(b, "ConfigureShare", "0.30")
    Do $$$AssertNotTrue($CLASSMETHOD(b, "StatusFor", user).shareExhausted, "a share of 0.30 with nothing spent is not spent")
    Do $$$AssertNotTrue($CLASSMETHOD(b, "Admit", "ut-share-a", user, .st), "but a run estimated at 0.50 does not fit it")
    Set words = $CLASSMETHOD(b, "Refusal", st)
    Do $$$AssertTrue((words [ "Your share") && (words [ "has 0.30 USD left") && (words [ "less than a run's estimate of 0.50 USD"), "named as the user's share: " _ words)
    Do $$$AssertTrue($CLASSMETHOD(b, "Admit", "ut-share-sys", "system"), "the feed's own runs have no share")
    Do $CLASSMETHOD(b, "Settle", "ut-share-sys")
    Do $CLASSMETHOD(b, "ConfigureShare", "0.50")
    Do $$$AssertTrue($CLASSMETHOD(b, "Admit", "ut-share-a", user), "a share of 0.50 takes one run")
    Do $$$AssertNotTrue($CLASSMETHOD(b, "Admit", "ut-share-b", user, .st), "and refuses the user's second")
    Do $$$AssertTrue($CLASSMETHOD(b, "Admit", "ut-share-c", other), "while another user's run is admitted on their own share")
    Do $CLASSMETHOD(b, "Settle", "ut-share-a"), $CLASSMETHOD(b, "Settle", "ut-share-c")
    Do $CLASSMETHOD(b, "ConfigureShare", "0")
    Do $$$AssertEquals($CLASSMETHOD(b, "Reserved", "", .n) _ "|" _ n, "0|0", "all settled")
}

/// Two admissions race on the last allowance: two jobs wait on the admission's lock, the lock is let go, and exactly one is
/// admitted; the other sees the first one's reservation.
Method TestTwoAdmissionsRaceForTheLastAllowance()
{
    Set b = "Shutter.Util.Budget"
    Kill ^Shutter.Budget("reserve"), ^Shutter.Test.BudgetRace
    Set ^Shutter.Config("budgetReserveUsd") = "0.50"
    Do $CLASSMETHOD(b, "ConfigureShare", "0")
    Do ..CapAbove(.6)
    // Hold the admission's lock so both jobs reach it before either can pass.
    Lock +^Shutter.Budget("admit"):5
    Do $$$AssertTrue($TEST, "the test holds the admission's lock")
    Job ##class(Shutter.Test.BudgetAdmission).RaceOne("a")::5
    Set started = $TEST
    Job ##class(Shutter.Test.BudgetAdmission).RaceOne("b")::5
    Set started = started && $TEST
    Do $$$AssertTrue(started, "two jobs started")
    For i = 1:1:100 { Quit:$DATA(^Shutter.Test.BudgetRace("a", "go"))&&$DATA(^Shutter.Test.BudgetRace("b", "go"))  Hang .05 }
    Hang .3
    Do $$$AssertEquals($DATA(^Shutter.Test.BudgetRace("a", "admitted")) + $DATA(^Shutter.Test.BudgetRace("b", "admitted")), 0, "neither has been admitted while the lock is held")
    Lock -^Shutter.Budget("admit")
    For i = 1:1:200 { Quit:$DATA(^Shutter.Test.BudgetRace("a", "admitted"))&&$DATA(^Shutter.Test.BudgetRace("b", "admitted"))  Hang .05 }
    Set a = $GET(^Shutter.Test.BudgetRace("a", "admitted"), "none"), bb = $GET(^Shutter.Test.BudgetRace("b", "admitted"), "none")
    Do $$$AssertTrue((a _ bb = "10") || (a _ bb = "01"), "exactly one of the two is admitted: a " _ a _ ", b " _ bb)
    Do $$$AssertEquals($CLASSMETHOD(b, "Reserved", "", .n) _ "|" _ n, ".5|1", "and one reservation holds the last allowance")
    Do $CLASSMETHOD(b, "Settle", "ut-race-a"), $CLASSMETHOD(b, "Settle", "ut-race-b")
    Kill ^Shutter.Test.BudgetRace
}

/// One racer, run as a job: says it is ready, asks for admission (waiting on the lock), and writes the answer.
ClassMethod RaceOne(tag As %String)
{
    Set ^Shutter.Test.BudgetRace(tag, "go") = 1
    Set ^Shutter.Test.BudgetRace(tag, "admitted") = ##class(Shutter.Util.Budget).Admit("ut-race-" _ tag, "ut-race")
}

/// The SQL diagnostic's path (Runner.Diagnostic, which AIHub.TestRun calls): refused when the allowance is spent, before
/// any runner is made and with nothing recorded; admitted, it runs, its cost is recorded as a diagnostic row with no case,
/// no question and its asker, the day's spend and the asker's share count it, its reservation is settled, and no case's
/// runs or events change.
Method TestDiagnosticRunsAreAdmittedAndRecorded()
{
    Set b = "Shutter.Util.Budget"
    Kill ^Shutter.Budget("reserve"), ^Shutter.Test.FakeRunner
    Set ^Shutter.Config("budgetReserveUsd") = "0.50"
    Do $CLASSMETHOD(b, "ConfigureShare", "0")
    Set user = "ut-diag-" _ $JOB
    Set spec = ##class(Shutter.Bridge.RunSpec).%New()
    Set spec.AgentClass = "Shutter.Agent.Conformance", spec.Role = "specialist", spec.MemberCode = "conformance"
    Set spec.Mode = "live", spec.RunnerClass = "Shutter.Test.FakeRunner", spec.MockConfig = "", spec.EnsMessageId = "test:ut:conformance:1"
    Set before = ..Counts()
    // Spent: refused before the runner is made.
    Do ..CapAbove(.1)
    Set sc = ##class(Shutter.Bridge.Runner).Diagnostic(spec, user, .response, .runId)
    Do $$$AssertStatusOK(sc, "a refusal is an answer, not an error")
    Do $$$AssertEquals(response.Status, "budget_exhausted", "refused when the allowance is spent")
    Do $$$AssertTrue(response.Error [ "less than a run's estimate", "with the budget's words: " _ response.Error)
    Do $$$AssertEquals(+$GET(^Shutter.Test.FakeRunner("calls")), 0, "and no runner was made, so nothing was contacted")
    Do $$$AssertEquals(runId, "", "nothing recorded")
    Do $$$AssertEquals(..Counts(), before, "no row of any kind written")
    // Room for it: admitted, run, recorded, settled.
    Do ..CapAbove(100)
    Set spentBefore = $CLASSMETHOD(b, "SpentBy", user, $CLASSMETHOD(b, "Status").since)
    Set sc = ##class(Shutter.Bridge.Runner).Diagnostic(spec, user, .response, .runId)
    Do $$$AssertStatusOK(sc, "admitted and run")
    Do $$$AssertEquals(response.Status, "ok", "the runner answered")
    Do $$$AssertEquals(+$GET(^Shutter.Test.FakeRunner("calls")), 1, "the runner ran once")
    Do $$$AssertTrue(runId '= "", "a row was recorded: " _ runId)
    Set run = ##class(Shutter.Store.AgentRun).%OpenId(runId)
    Do $$$AssertTrue($ISOBJECT(run), "and opens")
    If '$ISOBJECT(run) Quit
    Do $$$AssertEquals(run.Purpose, "diagnostic", "marked as diagnostic")
    Do $$$AssertEquals(run.CaseGetObjectId() _ "|" _ run.SnapshotGetObjectId() _ "|" _ run.QuestionId, "||", "with no case, snapshot or question")
    Do $$$AssertEquals(run.RequestedBy _ "|" _ run.MemberCode _ "|" _ run.Mode _ "|" _ run.Status, user _ "|conformance|live|ok", "who asked, the member, the mode and the outcome")
    Set cost = ##class(Shutter.Store.ModelPrice).Cost(##class(Shutter.Test.FakeRunner).#MODEL, ##class(Shutter.Test.FakeRunner).#PROMPTTOKENS, ##class(Shutter.Test.FakeRunner).#COMPLETIONTOKENS, 0, 0)
    Do $$$AssertEquals(+run.CostUSD, +cost, "priced as every run is: " _ run.CostUSD)
    Set spentAfter = $CLASSMETHOD(b, "SpentBy", user, $CLASSMETHOD(b, "Status").since)
    Do $$$AssertEquals(spentAfter - spentBefore, +cost, "the asker's share counts it")
    Do $$$AssertEquals($CLASSMETHOD(b, "Reserved", "", .n) _ "|" _ n, "0|0", "and the reservation was settled once the row was saved")
    Set after = ..Counts()
    Do $$$AssertEquals($PIECE(after, "|", 1, 2), $PIECE(before, "|", 1, 2), "no case's runs or events changed")
    Do $$$AssertEquals($PIECE(after, "|", 3), $PIECE(before, "|", 3) + 1, "one caseless row more")
    // A failed diagnostic is recorded too, at what it cost.
    Set spec.RunnerClass = "Shutter.Test.NoSuchRunner"
    Set sc = ##class(Shutter.Bridge.Runner).Diagnostic(spec, user, .response, .runId2)
    Do $$$AssertEquals(response.Status, "error", "a runner that cannot be made fails the run")
    Set run2 = ##class(Shutter.Store.AgentRun).%OpenId(runId2)
    Do $$$AssertTrue($ISOBJECT(run2) && (run2.Purpose = "diagnostic") && (run2.Status = "error"), "and the failure is recorded as a diagnostic row")
    Do $$$AssertEquals($CLASSMETHOD(b, "Reserved", "", .n) _ "|" _ n, "0|0", "settled too")
    // The rows are this test's own: take them away again.
    Do ##class(Shutter.Store.AgentRun).%DeleteId(runId), ##class(Shutter.Store.AgentRun).%DeleteId(runId2)
    Kill ^Shutter.Test.FakeRunner
}

/// AIHub.TestRun goes through Runner.Diagnostic before it makes a runner, and writes no row itself (read from its code;
/// the aihub module's classes are not on the core edition).
Method TestTestRunGoesThroughAdmission()
{
    If '##class(%Dictionary.CompiledClass).%ExistsId("Shutter.Bridge.Runner.AIHub") {
        Do $$$AssertSkipped("the aihub module is not installed here")
        Quit
    }
    Set m = ##class(%Dictionary.MethodDefinition).%OpenId("Shutter.Bridge.Runner.AIHub||TestRun")
    Do $$$AssertTrue($ISOBJECT(m), "TestRun's definition is here")
    If '$ISOBJECT(m) Quit
    Do m.Implementation.Rewind()
    Set code = m.Implementation.Read(1000000)
    Set at = $FIND(code, "##class(Shutter.Bridge.Runner).Diagnostic(spec, $USERNAME")
    Do $$$AssertTrue(at > 0, "TestRun calls the diagnostic path, charged to the caller")
    Do $$$AssertNotTrue(code [ "runner.Run(", "and makes no runner of its own")
    Do $$$AssertTrue(code [ "If response.Status = ""budget_exhausted"" Return", "a refusal answers before anything else")
}

/// Rows of AgentRun with a case, case events, and AgentRun rows with no case and no question.
ClassMethod Counts() As %String
{
    Set withCase = 0, events = 0, caseless = 0
    &sql(SELECT COUNT(*) INTO :withCase FROM Shutter_Store.AgentRun WHERE "Case" IS NOT NULL)
    &sql(SELECT COUNT(*) INTO :events FROM Shutter_Store.CaseEvent)
    &sql(SELECT COUNT(*) INTO :caseless FROM Shutter_Store.AgentRun WHERE "Case" IS NULL AND QuestionId IS NULL)
    Quit (+withCase) _ "|" _ (+events) _ "|" _ (+caseless)
}

}
