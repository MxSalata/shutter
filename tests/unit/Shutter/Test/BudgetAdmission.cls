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

/// Another run in flight for the test: a reservation of amount under the key ut-adm-held, which the test settles. With
/// something held against the cap, the estimate counts (with nothing spent or reserved, one run is admitted whatever its
/// estimate: TestALimitBelowOneEstimateStillAdmitsARun).
ClassMethod Hold(amount As %Numeric)
{
    Set ^Shutter.Budget("reserve", "ut-adm-held") = $LISTBUILD(+amount, ##class(Shutter.Util.Time).EpochSeconds(), "ut-adm-holder")
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
    // Another run is in flight, 0.10 of it, and the cap is 0.20 above the day's spend: 0.10 left.
    Do ..Hold(.1)
    Do ..CapAbove(.2)
    Set s = $CLASSMETHOD(b, "Status")
    Do $$$AssertNotTrue(s.exhausted, "0.10 left: the day is not spent")
    Do $$$AssertNotTrue($CLASSMETHOD(b, "Admit", "ut-adm-near", "approver", .st), "but a run estimated at 0.50 is refused")
    Do $$$AssertEquals($DATA(^Shutter.Budget("reserve", "ut-adm-near")), 0, "and nothing is reserved")
    Set words = $CLASSMETHOD(b, "Refusal", st)
    Do $$$AssertTrue((words [ "has 0.10 USD left") && (words [ "less than a run's estimate of 0.50 USD") && (words [ "not sent"), "the refusal says what is left and the estimate: " _ words)
    Do $$$AssertNotTrue($CLASSMETHOD(b, "AllowsFor", "approver", .st2), "the check ahead of a run refuses it too")
    Do $$$AssertNotTrue($CLASSMETHOD(b, "Allows", .st3), "and so does Allows")
    Do ..CapAbove(.6)
    Do $$$AssertTrue($CLASSMETHOD(b, "Admit", "ut-adm-fit", "approver", .st), "an estimate that just fits is admitted")
    Do $$$AssertNotTrue($CLASSMETHOD(b, "Admit", "ut-adm-next", "operator", .st), "and the next run is refused on its reservation")
    Do $$$AssertTrue($CLASSMETHOD(b, "Refusal", st) [ "2 run(s) in flight, 0.60 USD reserved", "the refusal names the runs in flight: " _ $CLASSMETHOD(b, "Refusal", st))
    Do $CLASSMETHOD(b, "Settle", "ut-adm-fit")
    Do $$$AssertTrue($CLASSMETHOD(b, "Admit", "ut-adm-next", "operator"), "once it settles, the next is admitted")
    Do $CLASSMETHOD(b, "Settle", "ut-adm-next"), $CLASSMETHOD(b, "Settle", "ut-adm-held")
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

/// The asker's share counts the estimate too, per user, once the user has anything spent or in flight; the feed's own runs
/// ("system") have no share. A share below one run's estimate still admits the user's first run (R146-01): refusing it
/// would refuse every run of theirs for good, as the estimate moves only when live runs land.
Method TestAShareCountsTheEstimate()
{
    Set b = "Shutter.Util.Budget"
    Kill ^Shutter.Budget("reserve")
    Set ^Shutter.Config("budgetReserveUsd") = "0.50"
    Do $CLASSMETHOD(b, "Configure", "0")
    Set user = "ut-adm-share-" _ $JOB, other = "ut-adm-other-" _ $JOB
    Do $CLASSMETHOD(b, "ConfigureShare", "0.30")
    Do $$$AssertNotTrue($CLASSMETHOD(b, "StatusFor", user).shareExhausted, "a share of 0.30 with nothing spent is not spent")
    Do $$$AssertTrue($CLASSMETHOD(b, "AllowsFor", user, .st), "with nothing of the user's spent or in flight, a run estimated at 0.50 may start")
    Do $$$AssertTrue($CLASSMETHOD(b, "Admit", "ut-share-a", user, .st), "and is admitted, though its estimate is over the share")
    Do $$$AssertNotTrue($CLASSMETHOD(b, "Admit", "ut-share-b", user, .st), "the user's next run is refused while the first is in flight")
    Set words = $CLASSMETHOD(b, "Refusal", st)
    Do $$$AssertTrue((words [ "Your share") && (words [ "0.30 USD"), "named as the user's share: " _ words)
    Do $$$AssertTrue($CLASSMETHOD(b, "Admit", "ut-share-sys", "system"), "the feed's own runs have no share")
    Do $CLASSMETHOD(b, "Settle", "ut-share-sys"), $CLASSMETHOD(b, "Settle", "ut-share-a")
    Do $CLASSMETHOD(b, "ConfigureShare", "0.50")
    Do $$$AssertTrue($CLASSMETHOD(b, "Admit", "ut-share-a", user), "a share of 0.50 takes one run")
    Do $$$AssertNotTrue($CLASSMETHOD(b, "Admit", "ut-share-b", user, .st), "and refuses the user's second")
    Do $$$AssertTrue($CLASSMETHOD(b, "Admit", "ut-share-c", other), "while another user's run is admitted on their own share")
    Do $CLASSMETHOD(b, "Settle", "ut-share-a"), $CLASSMETHOD(b, "Settle", "ut-share-c")
    Do $CLASSMETHOD(b, "ConfigureShare", "0")
    Do $$$AssertEquals($CLASSMETHOD(b, "Reserved", "", .n) _ "|" _ n, "0|0", "all settled")
}

/// A cap or a share below one run's estimate (R146-01): with nothing spent or reserved under that limit, one run is
/// admitted whatever its estimate, so such a limit does not refuse every run for good; once anything is spent or in flight
/// under it, the estimate counts again, and the refusal names the limit that stopped the run. Read on day states made by
/// hand (Fits is what Admit and AllowsFor decide with), so the arithmetic holds on any instance.
Method TestALimitBelowOneEstimateStillAdmitsARun()
{
    Set b = "Shutter.Util.Budget"
    Set day = {"dailyUsd": 0.3, "spentTodayUsd": 0, "reservedUsd": 0, "estimateUsd": 0.5, "since": "2026-11-15T00:00:00Z", "resetsAt": "2026-11-16T00:00:00Z"}
    Do $$$AssertTrue($CLASSMETHOD(b, "Fits", day, ""), "a cap of 0.30 with nothing spent or reserved admits a run estimated at 0.50")
    Do $$$AssertTrue($CLASSMETHOD(b, "Fits", day, "approver"), "for a user with no share too")
    Set day.spentTodayUsd = 0.01
    Do $$$AssertNotTrue($CLASSMETHOD(b, "Fits", day, ""), "with 0.01 spent, the estimate counts and the run is refused")
    Set words = $CLASSMETHOD(b, "Refusal", day)
    Do $$$AssertTrue((words [ "has 0.29 USD left") && (words [ "less than a run's estimate of 0.50 USD"), "and the refusal says what is left: " _ words)
    Set day.spentTodayUsd = 0, day.reservedUsd = 0.5
    Do $$$AssertNotTrue($CLASSMETHOD(b, "Fits", day, ""), "with a run in flight and nothing spent, refused too")
    Set day.reservedUsd = 0, day.dailyUsd = 1
    Do $$$AssertTrue($CLASSMETHOD(b, "Fits", day, ""), "well within a cap, admitted as before")
    Set day.spentTodayUsd = 0.6
    Do $$$AssertNotTrue($CLASSMETHOD(b, "Fits", day, ""), "0.40 left of 1.00: an estimate of 0.50 does not fit, as before")
    // The share, per user, with the day's cap out of play.
    Set mine = {"dailyUsd": 0, "spentTodayUsd": 2, "reservedUsd": 0, "perUserUsd": 0.3, "spentByMeUsd": 0, "reservedByMeUsd": 0, "estimateUsd": 0.5, "shareExhausted": false, "since": "2026-11-15T00:00:00Z", "resetsAt": "2026-11-16T00:00:00Z"}
    Do $$$AssertTrue($CLASSMETHOD(b, "Fits", mine, "judge"), "a share of 0.30 with nothing of the user's spent or reserved admits their run")
    Set mine.reservedByMeUsd = 0.5
    Do $$$AssertNotTrue($CLASSMETHOD(b, "Fits", mine, "judge"), "their next, while the first is in flight, is refused")
    Set mine.reservedByMeUsd = 0, mine.spentByMeUsd = 0.12
    Do $$$AssertNotTrue($CLASSMETHOD(b, "Fits", mine, "judge"), "once they have spent, the estimate counts")
    Do $$$AssertTrue($CLASSMETHOD(b, "Fits", mine, "system"), "the feed's own runs have no share")
    // A day with room in its cap: the share is what stopped the run, and the words say so.
    Set mine.dailyUsd = 5
    Set words = $CLASSMETHOD(b, "Refusal", mine)
    Do $$$AssertTrue((words [ "Your share") && (words [ "has 0.18 USD left") && (words [ "less than a run's estimate of 0.50 USD"), "the refusal names the user's share: " _ words)
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
    // The other was refused on the figures, not because the lock was busy: it read the first one's reservation.
    Set loser = $SELECT(a = 1: "b", 1: "a")
    Do $$$AssertEquals($GET(^Shutter.Test.BudgetRace(loser, "busy")), 0, "the one refused was not refused as busy")
    Set words = $GET(^Shutter.Test.BudgetRace(loser, "words"))
    Do $$$AssertTrue(words [ "less than a run's estimate of 0.50 USD", "the one refused says the estimate does not fit: " _ words)
    Do $$$AssertTrue(words [ "1 run(s) in flight, 0.50 USD reserved", "and names the first one's reservation: " _ words)
    Do $CLASSMETHOD(b, "Settle", "ut-race-a"), $CLASSMETHOD(b, "Settle", "ut-race-b")
    Kill ^Shutter.Test.BudgetRace
}

/// One racer, run as a job: says it is ready, asks for admission (waiting on the lock), and writes whether it was refused
/// as busy, the refusal's words, and last the answer.
ClassMethod RaceOne(tag As %String)
{
    Set ^Shutter.Test.BudgetRace(tag, "go") = 1
    Set ok = ##class(Shutter.Util.Budget).Admit("ut-race-" _ tag, "ut-race", .status)
    Set ^Shutter.Test.BudgetRace(tag, "busy") = +status.%Get("busy")
    Set ^Shutter.Test.BudgetRace(tag, "words") = $SELECT(ok: "", 1: ##class(Shutter.Util.Budget).Refusal(status))
    Set ^Shutter.Test.BudgetRace(tag, "admitted") = ok
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
    // Short: another run in flight and 0.10 left, refused before the runner is made.
    Do ..Hold(.1)
    Do ..CapAbove(.2)
    Set sc = ##class(Shutter.Bridge.Runner).Diagnostic(spec, user, .response, .runId)
    Do $$$AssertStatusOK(sc, "a refusal is an answer, not an error")
    Do $$$AssertEquals(response.Status, "budget_exhausted", "refused when the allowance is spent")
    Do $$$AssertTrue(response.Error [ "less than a run's estimate", "with the budget's words: " _ response.Error)
    Do $$$AssertEquals(+$GET(^Shutter.Test.FakeRunner("calls")), 0, "and no runner was made, so nothing was contacted")
    Do $$$AssertEquals(runId, "", "nothing recorded")
    Do $$$AssertEquals(..Counts(), before, "no row of any kind written")
    // Room for it: admitted, run, recorded, settled.
    Do $CLASSMETHOD(b, "Settle", "ut-adm-held")
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
    Do $$$AssertTrue(code [ "If $LISTFIND($LISTBUILD(""budget_exhausted"", ""budget_busy""), response.Status) Return", "a refusal, spent or busy, answers before anything else")
}

/// A busy admission (R146-05, R146-07): while another process holds the admission's lock past ADMITLOCKSECONDS, the SQL
/// diagnostic is refused budget_busy, not budget_exhausted, with words that say to try again, before any runner is made
/// and with nothing recorded; Reserve() writes nothing and says so. With the lock free again, Reserve reserves. No cap or
/// share is in play, so only the lock can refuse.
Method TestABusyAdmissionIsNotASpentBudget()
{
    Set b = "Shutter.Util.Budget"
    Kill ^Shutter.Budget("reserve"), ^Shutter.Test.FakeRunner, ^Shutter.Test.BudgetRace
    Set ^Shutter.Config("budgetReserveUsd") = "0.50"
    Do $CLASSMETHOD(b, "Configure", "0"), $CLASSMETHOD(b, "ConfigureShare", "0")
    Set user = "ut-busy-" _ $JOB
    Try {
        Job ##class(Shutter.Test.BudgetAdmission).HoldLock(90)::5
        Do $$$AssertTrue($TEST, "a job started to hold the admission's lock")
        For i = 1:1:100 { Quit:$DATA(^Shutter.Test.BudgetRace("holder", "held"))  Hang .1 }
        Do $$$AssertEquals($GET(^Shutter.Test.BudgetRace("holder", "held")), 1, "and holds it")
        Set spec = ##class(Shutter.Bridge.RunSpec).%New()
        Set spec.AgentClass = "Shutter.Agent.Conformance", spec.Role = "specialist", spec.MemberCode = "conformance"
        Set spec.Mode = "live", spec.RunnerClass = "Shutter.Test.FakeRunner", spec.MockConfig = "", spec.EnsMessageId = "test:ut:conformance:busy"
        Set sc = ##class(Shutter.Bridge.Runner).Diagnostic(spec, user, .response, .runId)
        Do $$$AssertStatusOK(sc, "a busy refusal is an answer, not an error")
        Do $$$AssertEquals(response.Status, "budget_busy", "refused as busy, not as a spent budget")
        Do $$$AssertTrue((response.Error [ "could not be checked in time") && (response.Error [ "Try again"), "with words that say to try again: " _ response.Error)
        Do $$$AssertEquals(+$GET(^Shutter.Test.FakeRunner("calls")), 0, "no runner was made")
        Do $$$AssertEquals(runId, "", "and nothing recorded")
        Set est = $CLASSMETHOD(b, "Reserve", "ut-busy-reserve", user)
        Do $$$AssertEquals(est, "", "Reserve says it reserved nothing")
        Do $$$AssertEquals($DATA(^Shutter.Budget("reserve", "ut-busy-reserve")), 0, "and wrote nothing while the lock was another's")
    } Catch ex {
        Do $$$AssertTrue(0, "error: " _ ex.DisplayString())
    }
    Set ^Shutter.Test.BudgetRace("holder", "release") = 1
    For i = 1:1:100 { Quit:$DATA(^Shutter.Test.BudgetRace("holder", "done"))  Hang .1 }
    Do $$$AssertEquals($CLASSMETHOD(b, "Reserve", "ut-busy-reserve", user), .5, "with the lock free, Reserve reserves the estimate")
    Do $CLASSMETHOD(b, "Settle", "ut-busy-reserve")
    Do $$$AssertEquals($CLASSMETHOD(b, "Reserved", "", .n) _ "|" _ n, "0|0", "all settled")
    Kill ^Shutter.Test.BudgetRace, ^Shutter.Test.FakeRunner
}

/// Holds the admission's lock, run as a job, until the test writes release or seconds pass; writes held, then done.
ClassMethod HoldLock(seconds As %Integer = 60)
{
    Lock +^Shutter.Budget("admit"):5
    Set ^Shutter.Test.BudgetRace("holder", "held") = $TEST
    If '^Shutter.Test.BudgetRace("holder", "held") Quit
    For i = 1:1:(seconds * 10) { Quit:$DATA(^Shutter.Test.BudgetRace("holder", "release"))  Hang .1 }
    Lock -^Shutter.Budget("admit")
    Set ^Shutter.Test.BudgetRace("holder", "done") = 1
}

/// The status a refused admission ends a run with comes from the budget (R146-05): budget_busy when the lock was not
/// free in time, budget_exhausted when the figures refused it. The Agent item takes it from there (read from its code: a
/// business operation is not made outside the production), as the SQL diagnostic does.
Method TestARefusalNamesItsOwnStatus()
{
    Set b = "Shutter.Util.Budget"
    Do $$$AssertEquals($CLASSMETHOD(b, "RefusalStatus", {"busy": true, "dailyUsd": 1, "spentTodayUsd": 0}), "budget_busy", "a busy refusal has its own status")
    Do $$$AssertEquals($CLASSMETHOD(b, "RefusalStatus", {"dailyUsd": 1, "spentTodayUsd": 1}), "budget_exhausted", "a spent budget keeps budget_exhausted")
    For pair = $LISTBUILD("Shutter.Bridge.Operation.Agent", "OnAgentRequest"), $LISTBUILD("Shutter.Bridge.Runner", "Diagnostic") {
        Set m = ##class(%Dictionary.MethodDefinition).%OpenId($LIST(pair, 1) _ "||" _ $LIST(pair, 2))
        Do $$$AssertTrue($ISOBJECT(m), $LIST(pair, 1) _ "." _ $LIST(pair, 2) _ " is here")
        Continue:'$ISOBJECT(m)
        Do m.Implementation.Rewind()
        Set code = m.Implementation.Read(1000000)
        Do $$$AssertTrue(code [ "##class(Shutter.Util.Budget).RefusalStatus(budget)", $LIST(pair, 1) _ " takes the refusal's status from the budget")
        Do $$$AssertNotTrue(code [ "Status = ""budget_exhausted""", "and never sets budget_exhausted whatever the refusal")
    }
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
