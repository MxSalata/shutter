/// The day's model budget (CONTRACTS 9, v1.34): a cap in US dollars on what the live and record agent runs may spend between
/// one 00:00 UTC and the next, read from SHUTTER_DAILY_BUDGET_USD at the install into ^Shutter.Config("dailyBudgetUsd");
/// 0 or unset means no cap. The Agent item asks Allows() before a run that would call a model and refuses the run with the
/// status budget_exhausted when the day's spend (the AgentRun rows' CostUSD since 00:00 UTC; replays and the mimic's runs
/// spend nothing, as GET /costs counts them) has reached the cap. The board then takes the rules path and the gate judges
/// the plain resend (CaseWorkflow.AfterBoard); a question or a review fails with the status. GET /settings and the Doctor
/// carry Status(). The public demo sets the cap with its own API key, so a day of visitors spends at most the cap.
Class Shutter.Util.Budget
{

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
    Set cap = ..Cap(), spent = ..Spent(since)
    Set s = {}
    Set s.dailyUsd = cap, s.spentTodayUsd = spent, s.since = since, s.resetsAt = resets, s.perUserUsd = ..Share()
    Do s.%Set("exhausted", ..Exhausted(cap, spent), "boolean")
    Quit s
}

/// The day's state for one user: Status() with spentByMeUsd, and exhausted also when the user's share is spent (v1.34).
ClassMethod StatusFor(user As %String, now As %String = "") As %DynamicObject
{
    Set s = ..Status(now)
    Set mine = $SELECT((user = "") || (user = "system"): 0, 1: ..SpentBy(user, s.since))
    Set s.spentByMeUsd = mine
    Do s.%Set("shareExhausted", ..Exhausted(s.perUserUsd, mine), "boolean")
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
    If status.%IsDefined("shareExhausted") && status.shareExhausted && '..Exhausted(status.dailyUsd, status.spentTodayUsd) {
        Quit "Your share of the day's model budget, " _ ..Dollars(status.perUserUsd) _ ", is spent (" _ ..Dollars(status.spentByMeUsd) _ " since " _ status.since _ "); the run was not sent. It resets at " _ status.resetsAt _ "."
    }
    Quit "The day's model budget of " _ ..Dollars(status.dailyUsd) _ " is spent (" _ ..Dollars(status.spentTodayUsd) _ " since " _ status.since _ "); the run was not sent. It resets at " _ status.resetsAt _ "."
}

/// An amount as "0.01 USD": a leading zero and two decimals.
ClassMethod Dollars(amount As %Numeric) As %String
{
    Quit $FNUMBER(+amount, "", 2) _ " USD"
}

}
