/// The routes of the recovery control and the shadow report (CONTRACTS 17), called from Shutter.API.Dispatch's map. The
/// actor is always the signed-in user, never a name from the body.
Class Shutter.API.Recovery Extends %RegisteredObject
{

/// GET /recovery-control: the mode, the stop, the generation and the outstanding calls.
ClassMethod ControlGet() As %Status
{
    If '##class(Shutter.API.Dispatch).Allow() Quit $$$OK
    Quit ##class(Shutter.API.Dispatch).Json(##class(Shutter.Util.RecoveryControl).Read())
}

/// POST /recovery-control/stop: stops at once, needs a reason, and a second stop changes nothing. Every operator and
/// approver holds the right, so stopping doesn't wait for whoever may configure the site.
ClassMethod ControlStop() As %Status
{
    If '##class(Shutter.API.Dispatch).Allow("Shutter_StopRecovery", 1) Quit $$$OK
    Set body = ##class(Shutter.API.Dispatch).Body()
    Set sc = ##class(Shutter.Util.RecoveryControl).Stop(##class(Shutter.Util.Json).Str(body, "reason"), ##class(Shutter.API.Dispatch).User())
    Quit ..Answer(sc)
}

/// POST /recovery-control/clear: needs both the site's and an approver's right, the generation the person read and a
/// reason. It enables nothing and releases nothing.
ClassMethod ControlClear() As %Status
{
    If '##class(Shutter.API.Dispatch).Allow("Shutter_Configure", 1) Quit $$$OK
    If '##class(Shutter.API.Dispatch).Allow("Shutter_Approve", 1) Quit $$$OK
    Set body = ##class(Shutter.API.Dispatch).Body()
    Set sc = ##class(Shutter.Util.RecoveryControl).ClearStop(##class(Shutter.Util.Json).Str(body, "reason"), ##class(Shutter.Util.Json).Str(body, "expectedGeneration"), ##class(Shutter.API.Dispatch).User())
    Quit ..Answer(sc)
}

ClassMethod Answer(sc As %Status) As %Status [ Private ]
{
    If $$$ISOK(sc) Quit ##class(Shutter.API.Dispatch).Json(##class(Shutter.Util.RecoveryControl).Read())
    Set text = $SYSTEM.Status.GetErrorText(sc)
    If text [ "reason_required" Quit ##class(Shutter.API.Dispatch).Fail("400 Bad Request", "bad_request", "A reason is required")
    If text [ "stale_generation" Quit ##class(Shutter.API.Dispatch).Fail("409 Conflict", "stale_version", "expectedGeneration is not the control's generation")
    If text [ "not_stopped" Quit ##class(Shutter.API.Dispatch).Fail("409 Conflict", "wrong_state", "Shutter recovery is not stopped")
    If text [ "control_busy" Quit ##class(Shutter.API.Dispatch).Fail("503 Service Unavailable", "control_busy", "The recovery control is busy; try again")
    Quit ##class(Shutter.API.Dispatch).Fail("500 Internal Server Error", "control_failed", text)
}

/// GET /shadow-observations?from=&to=&receiver=: the report's summary and rows, bounded.
ClassMethod ReportGet() As %Status
{
    If '##class(Shutter.API.Dispatch).Allow() Quit $$$OK
    Set rows = ..ReportRows(.truncated)
    Quit ##class(Shutter.API.Dispatch).Json({"summary": (##class(Shutter.Util.ShadowReport).Summary(rows, truncated)), "rows": (rows)})
}

/// GET /shadow-observations.csv: the same rows.
ClassMethod ReportCsv() As %Status
{
    If '##class(Shutter.API.Dispatch).Allow() Quit $$$OK
    Set rows = ..ReportRows(.truncated)
    Set %response.ContentType = "text/csv", %response.CharSet = "UTF-8"
    Do %response.SetHeader("Content-Disposition", "attachment; filename=""shutter-shadow-report.csv""")
    Write ##class(Shutter.Util.ShadowReport).Csv(rows)
    Quit $$$OK
}

ClassMethod ReportRows(Output truncated As %Boolean) As %DynamicArray [ Private ]
{
    Quit ##class(Shutter.Util.ShadowReport).Rows($GET(%request.Data("from", 1)), $GET(%request.Data("to", 1)), $GET(%request.Data("receiver", 1)), .truncated)
}

}
