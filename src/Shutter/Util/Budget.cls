/// The day's model budget (CONTRACTS 9, v1.34): a cap in US dollars on what the live and record agent runs may spend between
/// one 00:00 UTC and the next, read from SHUTTER_DAILY_BUDGET_USD at the install into ^Shutter.Config("dailyBudgetUsd");
/// 0 or unset means no cap. The Agent item asks Allows() before a run that would call a model and refuses the run with the
/// status budget_exhausted when the day's spend (the AgentRun rows' CostUSD since 00:00 UTC; replays and the mimic's runs
/// spend nothing, as GET /costs counts them) has reached the cap. The board then takes the rules path and the gate judges
/// the plain resend (CaseWorkflow.AfterBoard); a question or a review fails with the status. GET /settings and the Doctor
/// carry Status(). The public demo sets the cap with its own API key, so a day of visitors spends at most the cap.
/// Reserve, then settle (v1.35): a run in flight has no row yet, so three members running at once were not counted against
/// the cap. The Agent item reserves an estimate for each live run it starts (Reserve) and settles it when the run ends
/// (Settle); the day's state counts the reservations beside the spend (reservedUsd, inFlight), and a run is refused when
/// spend plus reservations reach the cap. The estimate is ^Shutter.Config("budgetReserveUsd") when the site sets it, else
/// the mean cost of the last twenty live runs, else 0.50 USD; a reservation older than twenty minutes is stale and dropped.
Class Shutter.Util.Budget
{

/// The reserve for a run when nothing better is known, in USD.
Parameter DEFAULTRESERVEUSD = 0.5;

/// A reservation older than this many seconds was left behind by a run that never settled (a job that died).
Parameter RESERVESTALESECONDS = 1200;

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

/// Reserve the estimate for a run about to call a model, under a key the caller settles with. Returns the estimate.
ClassMethod Reserve(key As %String, user As %String = "") As %Numeric
{
    Set est = ..Estimate()
    Set now = ##class(Shutter.Util.Time).EpochSeconds()
    Set ^Shutter.Budget("reserve", key) = $LISTBUILD(est, now, user)
    Quit est
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

/// Each user's share of the day, in USD (SHUTTER_JUDGE_BUDGET_USD; the owner's judges, v1.34): what one signed-in user's
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

/// Whether a run that would call a model may go for a user: the day's cap, then the user's share (the feed's own runs,
/// "system" or nobody, have no share). status gets StatusFor(user).
ClassMethod AllowsFor(user As %String, Output status As %DynamicObject) As %Boolean
{
    Set status = ..StatusFor(user)
    Quit 'status.exhausted
}

/// Whether a run that would call a model may go: no cap, or the day's spend below it. status gets Status().
ClassMethod Allows(Output status As %DynamicObject) As %Boolean
{
    Set status = ..Status()
    Quit 'status.exhausted
}

/// The refusal's words, for the run's error and the case's note; the figures in dollars and cents. A user's spent share is
/// named as theirs when that is what stopped the run.
ClassMethod Refusal(status As %DynamicObject) As %String
{
    Set flight = $SELECT(+status.%Get("inFlight") > 0: " with " _ status.inFlight _ " run(s) in flight, " _ ..Dollars(status.%Get("reservedUsd")) _ " reserved", 1: "")
    If status.%IsDefined("shareExhausted") && status.shareExhausted && '..Exhausted(status.dailyUsd, status.spentTodayUsd + +status.%Get("reservedUsd")) {
        Quit "Your share of the day's model budget, " _ ..Dollars(status.perUserUsd) _ ", is spent (" _ ..Dollars(status.spentByMeUsd) _ " since " _ status.since _ "); the run was not sent. It resets at " _ status.resetsAt _ "."
    }
    Quit "The day's model budget of " _ ..Dollars(status.dailyUsd) _ " is spent (" _ ..Dollars(status.spentTodayUsd) _ " since " _ status.since _ flight _ "); the run was not sent. It resets at " _ status.resetsAt _ "."
}

/// An amount as "0.01 USD": a leading zero and two decimals.
ClassMethod Dollars(amount As %Numeric) As %String
{
    Quit $FNUMBER(+amount, "", 2) _ " USD"
}

}
