/// The day's model budget (CONTRACTS 9, v1.34): a cap in US dollars on what the live and record agent runs may spend between
/// one 00:00 UTC and the next, read from SHUTTER_DAILY_BUDGET_USD at the install into ^Shutter.Config("dailyBudgetUsd");
/// 0 or unset means no cap. The day's spend is the AgentRun rows' CostUSD since 00:00 UTC (replays and the mimic's runs
/// spend nothing, as GET /costs counts them). The Agent item admits a run that would call a model through Admit() and refuses
/// it with the status budget_exhausted when it does not fit; a case the catalogue gives to the board or a person then goes to
/// a person, and another takes the rules path (CaseWorkflow.NoBoard); a question or a review fails with the status. GET
/// /settings and the Doctor carry Status().
/// Reserve, then settle (v1.35): a run in flight has no row yet, so each admitted run holds a reservation of the estimate
/// until it ends (Settle); the day's state counts the reservations beside the spend (reservedUsd, inFlight). The estimate is
/// ^Shutter.Config("budgetReserveUsd") when the site sets it, else the mean cost of the last twenty live runs, else 0.50 USD;
/// a reservation older than twenty minutes is taken for a job that died and dropped.
/// Admission (R145-03): a run is admitted only when the day's spend, the reservations in flight and the run's own estimate
/// together stay within the cap, and for a user with a share, that user's spend, reservations and the estimate within the
/// share. The check and the reservation are one step under one lock, so two runs cannot both be admitted on the same
/// remaining allowance. What this bounds is spend plus estimates, not the bill: a run can cost more than its estimate, a run
/// still going after twenty minutes stops counting until its row is written, and a production review's cost is kept on the
/// review, not on an AgentRun row, so the day's spend does not read it. It is no ceiling on a provider's invoice; a hard
/// limit at the provider is that.
Class Shutter.Util.Budget
{

/// The reserve for a run when nothing better is known, in USD.
Parameter DEFAULTRESERVEUSD = 0.5;

/// A reservation older than this many seconds was left behind by a run that never settled (a job that died).
Parameter RESERVESTALESECONDS = 1200;

/// How long an admission waits for another one to finish, in seconds. The step under the lock is two sums and a write, so
/// a wait this long means something is wrong, and the run is refused rather than admitted unchecked.
Parameter ADMITLOCKSECONDS = 10;

/// What one live run is expected to cost: the site's figure, else the mean of the last twenty live runs that cost
/// anything, else the default; never below 0.01.
ClassMethod Estimate() As %Numeric
{
    Set fixed = $GET(^Shutter.Config("budgetReserveUsd"))
    If (fixed '= "") && (fixed ? .N.1(1"."1.N)) && (+fixed > 0) Quit +fixed
    Set mean = ""
    Try {
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT AVG(CostUSD) AS M FROM (SELECT TOP 20 CostUSD FROM Shutter_Store.AgentRun WHERE Mode <> 'replay' AND Model <> 'mock' AND CostUSD > 0 ORDER BY ID DESC)")
        If rs.%Next() Set mean = rs.%Get("M")
    } Catch ex {
        Set mean = ""
    }
    If (mean = "") || (+mean <= 0) Set mean = ..#DEFAULTRESERVEUSD
    If +mean < 0.01 Set mean = 0.01
    Quit +mean
}

/// Reserve the estimate for a run about to call a model, under a key the caller settles with, with no check. Returns the
/// estimate. The Agent item and the SQL diagnostic go through Admit(), which checks and reserves in one step.
ClassMethod Reserve(key As %String, user As %String = "") As %Numeric
{
    Set est = ..Estimate()
    Lock +^Shutter.Budget("admit"):..#ADMITLOCKSECONDS
    Set locked = $TEST
    Set ^Shutter.Budget("reserve", key) = $LISTBUILD(est, ##class(Shutter.Util.Time).EpochSeconds(), user)
    If locked Lock -^Shutter.Budget("admit")#"I"
    Quit est
}

/// Admission (R145-03): whether a run that would call a model may start for a user and, when it may, its reservation under
/// key, in one step under one lock (the lock Reserve takes too), so two callers cannot both be admitted on the same remaining
/// allowance. Admitted when the day's spend plus the reservations in flight plus this run's estimate stay within the cap,
/// and, for a user with a share (not "system" or nobody), that user's spend plus their reservations plus the estimate stay
/// within the share. status gets StatusFor(user) with estimateUsd, read under the lock; estimate gets the run's estimate.
/// Refused, nothing is reserved; the caller settles an admitted run's key when the run ends.
ClassMethod Admit(key As %String, user As %String, Output status As %DynamicObject, Output estimate As %Numeric) As %Boolean
{
    Set estimate = ..Estimate(), admitted = 0
    Lock +^Shutter.Budget("admit"):..#ADMITLOCKSECONDS
    If '$TEST {
        Set status = ..StatusFor(user)
        Set status.estimateUsd = estimate
        Do status.%Set("busy", 1, "boolean")
        Quit 0
    }
    Try {
        Set status = ..StatusFor(user)
        Set status.estimateUsd = estimate
        Set admitted = ..Fits(status, user)
        If admitted Set ^Shutter.Budget("reserve", key) = $LISTBUILD(estimate, ##class(Shutter.Util.Time).EpochSeconds(), user)
    } Catch ex {
        Lock -^Shutter.Budget("admit")#"I"
        Throw ex
    }
    Lock -^Shutter.Budget("admit")#"I"
    Quit admitted
}

/// Whether one more run of status.estimateUsd fits a day's state from StatusFor(user): the cap, then the user's share (the
/// feed's own runs, "system" or nobody, have no share).
ClassMethod Fits(status As %DynamicObject, user As %String) As %Boolean
{
    Set est = +status.%Get("estimateUsd")
    If (+status.dailyUsd > 0) && ((+status.spentTodayUsd + +status.%Get("reservedUsd") + est) > +status.dailyUsd) Quit 0
    If (user = "") || (user = "system") Quit 1
    If (+status.%Get("perUserUsd") > 0) && ((+status.%Get("spentByMeUsd") + +status.%Get("reservedByMeUsd") + est) > +status.perUserUsd) Quit 0
    Quit 1
}

/// The run ended, whatever its outcome: its row carries the real cost now.
ClassMethod Settle(key As %String)
{
    Kill ^Shutter.Budget("reserve", key)
}

/// The reservations in flight, in USD, for every user or for one; count gets how many. Stale ones are dropped on the way.
ClassMethod Reserved(user As %String = "", Output count As %Integer) As %Numeric
{
    Set total = 0, count = 0
    Set now = ##class(Shutter.Util.Time).EpochSeconds()
    Set key = ""
    For {
        Set key = $ORDER(^Shutter.Budget("reserve", key), 1, value) Quit:key=""
        If (now - $LISTGET(value, 2, 0)) > ..#RESERVESTALESECONDS { Kill ^Shutter.Budget("reserve", key) Continue }
        If (user '= "") && ($LISTGET(value, 3) '= user) Continue
        Set total = total + $LISTGET(value, 1, 0), count = count + 1
    }
    Quit +total
}

/// The cap in USD; 0 means none.
ClassMethod Cap() As %Numeric
{
    Quit +$GET(^Shutter.Config("dailyBudgetUsd"))
}

/// Each user's share of the day, in USD (SHUTTER_JUDGE_BUDGET_USD; the judges, v1.34): what one signed-in user's
/// live runs may cost between one 00:00 UTC and the next; 0 means no share, only the day's cap.
ClassMethod Share() As %Numeric
{
    Quit +$GET(^Shutter.Config("judgeBudgetUsd"))
}

/// The share from a text (the environment variable at the install), as Configure reads the cap.
ClassMethod ConfigureShare(value As %String) As %Numeric
{
    Set value = $ZSTRIP($GET(value), "<>W")
    If (value = "") || '(value ? 1.N.1(1"."1.N)) Set value = 0
    Set ^Shutter.Config("judgeBudgetUsd") = +value
    Quit +value
}

/// What one user's live and record runs spent since an ISO UTC time, in USD (the runs carry who asked: a question's asker,
/// a judge who convened the board; the feed's own runs are "system").
ClassMethod SpentBy(user As %String, sinceIso As %String) As %Numeric
{
    If user = "" Quit 0
    Set spent = 0
    &sql(SELECT SUM(CASE WHEN Mode = 'replay' OR Model = 'mock' THEN 0 ELSE CostUSD END) INTO :spent FROM Shutter_Store.AgentRun WHERE StartedAt >= :sinceIso AND RequestedBy = :user)
    Quit +spent
}

/// The cap from a text (the environment variable at the install): a non-negative number such as 5 or 2.50, anything else
/// (empty, words, a negative) means no cap. Writes it and returns what was set.
ClassMethod Configure(value As %String) As %Numeric
{
    Set value = $ZSTRIP($GET(value), "<>W")
    If (value = "") || '(value ? 1.N.1(1"."1.N)) Set value = 0
    Set ^Shutter.Config("dailyBudgetUsd") = +value
    Quit +value
}

/// The public demo's budget note (v1.37), for the live banner: what the demo's owner spends on live runs, as a figure a
/// visitor can read (SHUTTER_DEMO_BUDGET_USD and SHUTTER_DEMO_BUDGET_PERIOD, at the install and at every production
/// start), which a site may enforce outside Shutter (a key deactivated at the figure) while the cap here guards a burst.
/// usd empty, 0 or not a number clears the note; period is day or hour, day when not given. Returns the note or "".
ClassMethod ConfigureDemoBudget(usd As %String, period As %String = "") As %DynamicObject
{
    Set usd = $ZSTRIP($GET(usd), "<>W"), period = $ZCONVERT($ZSTRIP($GET(period), "<>W"), "L")
    If (usd = "") || '(usd ? 1.N.1(1"."1.N)) || (+usd <= 0) Kill ^Shutter.Config("demoBudget") Quit ""
    If '$LISTFIND($LISTBUILD("day", "hour"), period) Set period = "day"
    Set ^Shutter.Config("demoBudget", "usd") = +usd, ^Shutter.Config("demoBudget", "period") = period
    Quit ..DemoBudgetNote()
}

/// {amountUsd, period} when the demo's budget note is set, else "".
ClassMethod DemoBudgetNote() As %DynamicObject
{
    Set usd = $GET(^Shutter.Config("demoBudget", "usd"))
    If (usd = "") || (+usd <= 0) Quit ""
    Set n = {}
    Do n.%Set("amountUsd", +usd, "number")
    Set n.period = $GET(^Shutter.Config("demoBudget", "period"), "day")
    Quit n
}

/// What the live and record runs spent since an ISO UTC time, in USD (a replay or a run the API mimic answered spent
/// nothing, so they count 0, as GET /costs counts them).
ClassMethod Spent(sinceIso As %String) As %Numeric
{
    Set spent = 0
    &sql(SELECT SUM(CASE WHEN Mode = 'replay' OR Model = 'mock' THEN 0 ELSE CostUSD END) INTO :spent FROM Shutter_Store.AgentRun WHERE StartedAt >= :sinceIso)
    Quit +spent
}

/// Whether a cap is set and the spend has reached it.
ClassMethod Exhausted(cap As %Numeric, spent As %Numeric) As %Boolean
{
    Quit (+cap > 0) && (+spent >= +cap)
}

/// The day's state: {dailyUsd, spentTodayUsd, exhausted, since, resetsAt}; now is an ISO UTC time, the clock when empty.
ClassMethod Status(now As %String = "") As %DynamicObject
{
    If now = "" Set now = ##class(Shutter.Util.Time).NowUTC()
    Set day = $EXTRACT(now, 1, 10), since = day _ "T00:00:00Z"
    Set resets = $ZDATE($ZDATEH(day, 3) + 1, 3) _ "T00:00:00Z"
    Set cap = ..Cap(), spent = ..Spent(since), reserved = ..Reserved("", .inFlight)
    Set s = {}
    Set s.dailyUsd = cap, s.spentTodayUsd = spent, s.since = since, s.resetsAt = resets, s.perUserUsd = ..Share()
    // The runs in flight (v1.35): reserved against the cap until their rows carry the real cost.
    Set s.reservedUsd = reserved, s.inFlight = inFlight
    Do s.%Set("exhausted", ..Exhausted(cap, spent + reserved), "boolean")
    Quit s
}

/// The day's state for one user: Status() with spentByMeUsd, and exhausted also when the user's share is spent (v1.34).
ClassMethod StatusFor(user As %String, now As %String = "") As %DynamicObject
{
    Set s = ..Status(now)
    Set mine = $SELECT((user = "") || (user = "system"): 0, 1: ..SpentBy(user, s.since))
    Set reservedMine = $SELECT((user = "") || (user = "system"): 0, 1: ..Reserved(user, .n))
    Set s.spentByMeUsd = mine, s.reservedByMeUsd = reservedMine
    Do s.%Set("shareExhausted", ..Exhausted(s.perUserUsd, mine + reservedMine), "boolean")
    If s.shareExhausted Do s.%Set("exhausted", 1, "boolean")
    Quit s
}

/// Whether a run that would call a model would be admitted now for a user, as Admit() decides (the estimate counted), with
/// nothing reserved: for a check ahead of the runs, the board convened by hand and the live agents' availability. status
/// gets StatusFor(user) with estimateUsd.
ClassMethod AllowsFor(user As %String, Output status As %DynamicObject) As %Boolean
{
    Set status = ..StatusFor(user)
    Set status.estimateUsd = ..Estimate()
    Quit ..Fits(status, user)
}

/// Whether a run that would call a model would be admitted now with no user's share in play: the day's spend, the
/// reservations and the estimate within the cap. status gets Status() with estimateUsd.
ClassMethod Allows(Output status As %DynamicObject) As %Boolean
{
    Set status = ..Status()
    Set status.estimateUsd = ..Estimate()
    Quit ..Fits(status, "")
}

/// The refusal's words, for the run's error and the case's note; the figures in dollars and cents. A user's spent share is
/// named as theirs when that is what stopped the run.
ClassMethod Refusal(status As %DynamicObject) As %String
{
    Set flight = $SELECT(+status.%Get("inFlight") > 0: " with " _ status.inFlight _ " run(s) in flight, " _ ..Dollars(status.%Get("reservedUsd")) _ " reserved", 1: "")
    If status.%Get("busy") Quit "The day's model budget could not be checked in time (another run was being admitted); the run was not sent. Try again in a moment."
    Set dayFull = ..Exhausted(status.dailyUsd, status.spentTodayUsd + +status.%Get("reservedUsd"))
    Set est = status.%Get("estimateUsd")
    // Not spent, but the run's estimate does not fit what is left (Admit, R145-03): which limit, what is left, the estimate.
    Set dayShort = (est '= "") && 'dayFull && (+status.dailyUsd > 0) && ((+status.spentTodayUsd + +status.%Get("reservedUsd") + est) > +status.dailyUsd)
    If 'dayFull && 'dayShort && status.%IsDefined("shareExhausted") {
        Set mine = +status.%Get("spentByMeUsd") + +status.%Get("reservedByMeUsd")
        If status.shareExhausted {
            Quit "Your share of the day's model budget, " _ ..Dollars(status.perUserUsd) _ ", is spent (" _ ..Dollars(status.spentByMeUsd) _ " since " _ status.since _ "); the run was not sent. It resets at " _ status.resetsAt _ "."
        }
        If (est '= "") && (+status.%Get("perUserUsd") > 0) && ((mine + est) > +status.perUserUsd) {
            Quit "Your share of the day's model budget, " _ ..Dollars(status.perUserUsd) _ ", has " _ ..Dollars(status.perUserUsd - mine) _ " left (" _ ..Dollars(status.spentByMeUsd) _ " spent since " _ status.since _ $SELECT(+status.%Get("reservedByMeUsd") > 0: ", " _ ..Dollars(status.reservedByMeUsd) _ " reserved", 1: "") _ "), less than a run's estimate of " _ ..Dollars(est) _ "; the run was not sent. It resets at " _ status.resetsAt _ "."
        }
    }
    If dayShort {
        Quit "The day's model budget of " _ ..Dollars(status.dailyUsd) _ " has " _ ..Dollars(status.dailyUsd - status.spentTodayUsd - status.%Get("reservedUsd")) _ " left (" _ ..Dollars(status.spentTodayUsd) _ " spent since " _ status.since _ flight _ "), less than a run's estimate of " _ ..Dollars(est) _ "; the run was not sent. It resets at " _ status.resetsAt _ "."
    }
    Quit "The day's model budget of " _ ..Dollars(status.dailyUsd) _ " is spent (" _ ..Dollars(status.spentTodayUsd) _ " since " _ status.since _ flight _ "); the run was not sent. It resets at " _ status.resetsAt _ "."
}

/// An amount as "0.01 USD": a leading zero and two decimals.
ClassMethod Dollars(amount As %Numeric) As %String
{
    Quit $FNUMBER(+amount, "", 2) _ " USD"
}

}
