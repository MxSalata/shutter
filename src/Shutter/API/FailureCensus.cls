/// The failure coverage census's routes (docs/CONTRACTS.md, section 19), under /failure-census, all Shutter_Operate. A caller
/// names a registered receiver and a window, never a namespace or SQL text. The run happens in the Failure Census item. The
/// routes are in Shutter.API.Dispatch's map.
Class Shutter.API.FailureCensus Extends Shutter.API.Dispatch
{

/// Whether it is on, what it can run on, its limits and the latest runs.
ClassMethod List() As %Status
{
    If '..Allow("Shutter_Operate") Quit $$$OK
    Set util = "Shutter.Util.FailureCensus", settings = $CLASSMETHOD(util, "Settings")
    Set r = {"statement": ($PARAMETER(util, "STATEMENT")), "maxWindowHours": (settings."max_window_hours"), "maxHeaders": (settings."max_headers"), "scopes": ($CLASSMETHOD(util, "Scopes")), "items": []}
    Do r.%Set("enabled", settings.%Get("enabled"), "boolean")
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 50 ID FROM Shutter_Store.CensusRun ORDER BY ID DESC")
    While rs.%Next() {
        Set run = ##class(Shutter.Store.CensusRun).%OpenId(rs.%Get("ID"))
        If $ISOBJECT(run) Do r.items.%Push($CLASSMETHOD(util, "Report", run, 0))
    }
    Quit ..Json(r)
}

/// POST {receiver, from?, to?}: to defaults to now, from to the longest window before it. 201 with the report, whatever it found;
/// 409 not_enabled while the profile has it off; 400 bad_request for a receiver not registered or a window refused; 503 and 502 as
/// the production review's start.
ClassMethod Start() As %Status
{
    If '..Allow("Shutter_Operate", 1) Quit $$$OK
    Set bodyText = $SELECT($ISOBJECT(%request.Content): %request.Content.Read($$$MaxStringLength), 1: $GET(%request.Content))
    Set body = ##class(Shutter.Util.Json).Parse(bodyText, .psc)
    If '$ISOBJECT(body) || $$$ISERR(psc) || ($CLASSNAME(body) '= "%Library.DynamicObject") Quit ..Fail("400 Bad Request", "bad_request", "The body must be a JSON object: {receiver, from?, to?}")
    Set settings = ##class(Shutter.Util.FailureCensus).Settings()
    If 'settings.%Get("enabled") Quit ..Fail("409 Conflict", "not_enabled", "The census is off: a site turns it on with failure_census.enabled in the site profile")
    Set receiver = ##class(Shutter.Util.Json).Str(body, "receiver")
    If '##class(Shutter.Util.FailureCensus).ScopeOf(receiver, .ns, .item) Quit ..Fail("400 Bad Request", "bad_request", "receiver must be a registered receiver in a watched namespace: GET /failure-census lists them")
    Set to = ##class(Shutter.Util.Json).Str(body, "to")
    If to = "" Set to = ##class(Shutter.Util.Time).NowUTC()
    Set from = ##class(Shutter.Util.Json).Str(body, "from")
    If from = "" Set from = ##class(Shutter.Util.Time).FromNow(-3600 * settings."max_window_hours" + 1)
    Set problem = ##class(Shutter.Util.FailureCensus).WindowProblem(from, to, settings)
    If problem '= "" Quit ..Fail("400 Bad Request", "bad_request", problem)
    Set r = ..Idempotent(bodyText, .replayed)
    If replayed Quit $$$OK
    Set msg = ##class(Shutter.Msg.CensusRequest).%New()
    Set msg.Receiver = receiver, msg.FromUTC = from, msg.ToUTC = to, msg.RequestedBy = ..User()
    Set sc = ##class(Ens.Director).CreateBusinessService("Shutter API", .service)
    If $$$ISERR(sc) || '$ISOBJECT(service) Quit ..Fail("503 Service Unavailable", "no_service", "The API service is not running: " _ $SYSTEM.Status.GetErrorText(sc))
    Set service.Target = "Failure Census", service.Timeout = 120
    Set sc = service.ProcessInput(msg, .answer)
    If $$$ISERR(sc) Quit ..Fail("503 Service Unavailable", "not_queued", "The census could not be started: " _ $SYSTEM.Status.GetErrorText(sc))
    If '$ISOBJECT(answer) || 'answer.%IsA("Shutter.Msg.CensusAnswer") Quit ..Fail("502 Bad Gateway", "no_answer", "The Failure Census item did not answer")
    If answer.RunId = "" Quit ..Fail("400 Bad Request", "bad_request", answer.Error)
    Set run = ##class(Shutter.Store.CensusRun).ByRunId(answer.RunId)
    If '$ISOBJECT(run) Quit ..Fail("500 Internal Server Error", "census_failed", answer.Error)
    Set text = ##class(Shutter.Util.FailureCensus).Report(run, 0).%ToJSON()
    Do ..Remember(bodyText, "201 Created", text)
    Set %response.Status = "201 Created"
    Write text
    Quit $$$OK
}

ClassMethod Get(id As %String) As %Status
{
    If '..Allow("Shutter_Operate") Quit $$$OK
    Set run = ##class(Shutter.Store.CensusRun).ByRunId(id)
    If '$ISOBJECT(run) Quit ..Fail("404 Not Found", "not_found", "No census run " _ id)
    Quit ..Json(##class(Shutter.Util.FailureCensus).Report(run))
}

ClassMethod Csv(id As %String) As %Status
{
    If '..Allow("Shutter_Operate") Quit $$$OK
    Set run = ##class(Shutter.Store.CensusRun).ByRunId(id)
    If '$ISOBJECT(run) Quit ..Fail("404 Not Found", "not_found", "No census run " _ id)
    Set %response.ContentType = "text/csv"
    Do %response.SetHeader("Content-Disposition", "attachment; filename=""" _ run.RunId _ ".csv""")
    Quit ##class(Shutter.Util.FailureCensus).Csv(run).OutputToDevice()
}

}
