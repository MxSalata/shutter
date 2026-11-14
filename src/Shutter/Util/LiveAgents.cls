/// Whether the live agents can run now (CONTRACTS 12, v1.37), for the web's notice and the routes' refusals: the day's
/// model budget (Shutter.Util.Budget) and the model provider's answer to the key. GET /settings carries
/// live.agents = {available, reason, until, detail}: reason "budget" when the day's cap or the caller's share has no
/// room for the next run (spent, or since 1.4.6 less left than its estimate) (until = when the cap resets),
/// "provider_auth" when a live run failed with an authentication error in the last fifteen minutes (until = the next
/// 00:00 UTC, when a key a site deactivates for the day comes back; the flag clears on the next live run the provider
/// accepts), null when live runs can go. While the provider refuses the key, the Agent item refuses live runs itself
/// with the status provider_auth and makes no call (a board nobody answers then ends as for budget_exhausted:
/// CaseWorkflow.NoBoard), and POST /cases/{id}/board and a live question with no recorded answer answer 409
/// live_unavailable.
Class Shutter.Util.LiveAgents
{

/// How long a refused key keeps live runs off, in seconds: then one run tries the provider again.
Parameter AUTHDOWNSECONDS = 900;

/// Whether a run's error is the provider refusing the key: an authentication error, a 401, a bad API key.
ClassMethod IsAuthFailure(text As %String) As %Boolean
{
    Set t = $ZCONVERT($GET(text), "L")
    If t = "" Quit 0
    For word = "authentication", "unauthorized", "unauthorised", "invalid api key", "invalid x-api-key", "api key", "api-key", "401" {
        If t [ word Return 1
    }
    Quit 0
}

/// A run that called the provider ended: an accepted call clears the flag, a refused key sets it. A replay calls nothing.
ClassMethod NoteRun(mode As %String, status As %String, error As %String = "")
{
    If mode = "replay" Quit
    If status = "ok" Kill ^Shutter.Config("provider", "authFailedAt"), ^Shutter.Config("provider", "authFailedText") Quit
    If (status = "error") && ..IsAuthFailure(error) {
        Set ^Shutter.Config("provider", "authFailedAt") = ##class(Shutter.Util.Time).NowUTC()
        Set ^Shutter.Config("provider", "authFailedText") = $EXTRACT(error, 1, 300)
    }
}

/// Whether the provider refused the key within the last AUTHDOWNSECONDS: then until is the next 00:00 UTC and text says
/// what happened, for the run's own error and the routes' refusals.
ClassMethod ProviderDown(Output until As %String, Output text As %String) As %Boolean
{
    Set until = "", text = ""
    Set at = $GET(^Shutter.Config("provider", "authFailedAt"))
    If at = "" Quit 0
    Set now = ##class(Shutter.Util.Time).NowUTC()
    If ##class(Shutter.Util.Time).SecondsBetween(at, now) > ..#AUTHDOWNSECONDS Quit 0
    Set until = ..NextMidnightUTC(now)
    Set text = "The model provider refused Shutter's key at " _ at _ " (" _ $GET(^Shutter.Config("provider", "authFailedText")) _ "); live runs are off until it accepts the key again, and the next try is at " _ ##class(Shutter.Util.Time).FromNow(..#AUTHDOWNSECONDS - ##class(Shutter.Util.Time).SecondsBetween(at, now)) _ " (provider_auth)"
    Quit 1
}

/// The next 00:00 UTC after an ISO UTC time.
ClassMethod NextMidnightUTC(now As %String) As %String
{
    Quit $ZDATE($ZDATEH($EXTRACT(now, 1, 10), 3) + 1, 3) _ "T00:00:00Z"
}

/// {available, reason, until, detail} for a user: provider_auth first (it outlasts the budget), then the budget.
ClassMethod Availability(user As %String = "") As %DynamicObject
{
    Set a = {}
    Do a.%Set("available", 1, "boolean"), a.%Set("reason", "", "null"), a.%Set("until", "", "null")
    Set a.detail = ""
    If ..ProviderDown(.until, .text) {
        Do a.%Set("available", 0, "boolean")
        Set a.reason = "provider_auth", a.until = until, a.detail = text
        Quit a
    }
    If '##class(Shutter.Util.Budget).AllowsFor(user, .budget) {
        Do a.%Set("available", 0, "boolean")
        Set a.reason = "budget", a.until = budget.resetsAt, a.detail = ##class(Shutter.Util.Budget).Refusal(budget)
    }
    Quit a
}

}
