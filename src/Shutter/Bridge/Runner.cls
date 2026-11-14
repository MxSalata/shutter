/// A runner carries out one agent run described by a RunSpec and fills the response. The core
/// module ships the replay runner; the aihub module ships the live one. Runners return an error
/// status only for programming errors; a run that failed is reported in the response's Status.
Class Shutter.Bridge.Runner Extends %RegisteredObject [ Abstract ]
{

Method Run(spec As Shutter.Bridge.RunSpec, ByRef response As Shutter.Bridge.Msg.AgentResponse) As %Status [ Abstract ]
{
}

/// A diagnostic run outside the production (AIHub.TestRun, R145-04), held by the day's budget as the Agent item's runs are:
/// admitted by Shutter.Util.Budget.Admit (the estimate counted, check and reservation in one locked step) before the runner
/// is made, so a refusal contacts no provider and answers with the status budget_exhausted (budget_busy when the budget
/// could not be checked in time, Budget.RefusalStatus); run by spec.RunnerClass; then
/// recorded as an AgentRun row with Purpose "diagnostic" and no case (AgentRun.FromDiagnostic), charged to user, and only
/// then settled, so its cost is counted somewhere throughout. A row that cannot be saved leaves the reservation to lapse
/// after twenty minutes, and the error is returned. runId gets the row's id, "" when refused or not saved.
ClassMethod Diagnostic(spec As Shutter.Bridge.RunSpec, user As %String, Output response As Shutter.Bridge.Msg.AgentResponse, Output runId As %String) As %Status
{
    Set response = ##class(Shutter.Bridge.Msg.AgentResponse).%New(), runId = ""
    Set response.RequestedBy = user
    Set key = "diagnostic|" _ spec.MemberCode _ "|" _ $JOB _ "|" _ $ZHOROLOG
    If '##class(Shutter.Util.Budget).Admit(key, user, .budget) {
        Set response.Status = ##class(Shutter.Util.Budget).RefusalStatus(budget), response.Error = ##class(Shutter.Util.Budget).Refusal(budget)
        Do ..Stamp(spec, response)
        Quit $$$OK
    }
    Set start = $ZHOROLOG
    Try {
        Set runner = $CLASSMETHOD(spec.RunnerClass, "%New")
        Set sc = runner.Run(spec, .response)
        If $$$ISERR(sc) Set response.Status = "error", response.Error = $SYSTEM.Status.GetErrorText(sc)
    } Catch ex {
        Set response.Status = "error", response.Error = ex.DisplayString()
    }
    Do ..Stamp(spec, response)
    Set response.RequestedBy = user
    If response.Status = "" Set response.Status = "ok"
    If response.StartedAt = "" Set response.StartedAt = ##class(Shutter.Util.Time).NowUTC()
    If response.StartedAtMs = "" Set response.StartedAtMs = ##class(Shutter.Util.Time).NowUTCms()
    If response.DurationMs = "" Set response.DurationMs = (($ZHOROLOG - start) * 1000) \ 1
    Set sc = ##class(Shutter.Store.AgentRun).FromDiagnostic(spec.MemberCode, response, .run)
    If $$$ISERR(sc) Quit sc
    Set runId = run.%Id()
    Do ##class(Shutter.Util.Budget).Settle(key)
    Quit $$$OK
}

/// Copy the specification's identity into a response.
ClassMethod Stamp(spec As Shutter.Bridge.RunSpec, response As Shutter.Bridge.Msg.AgentResponse)
{
    Set response.AgentClass = spec.AgentClass
    Set response.ConfigVersion = spec.ConfigVersion
    Set response.Mode = spec.Mode
    If response.Model = "" Set response.Model = spec.Model
    If response.ProviderConfig = "" Set response.ProviderConfig = spec.ProviderConfig
}

}
