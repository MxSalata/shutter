/// Warehouse history's side in Shutter (docs/warehouse-history.md): whether it is on, one bounded call to the reader for a
/// case's own patient, and the stored result. Called only from a person's request on the case page: nothing in the
/// production or the case workflow calls it, and nothing that decides a case reads what it stores. A failure here costs
/// the supplement and nothing else.
/// Its settings are not in the site profile on purpose: the profile's version is part of what an approval rests on
/// (Shutter.Store.Approval, InvalidReason), so switching this on there would revoke every waiting approval.
Class Shutter.Warehouse.Client [ Abstract ]
{

/// The stored credential holding the reader's user and password.
Parameter CREDENTIAL = "WarehouseReader";

/// The reader's web application.
Parameter READERPATH = "/api/shutter-warehouse";

/// Seconds to wait for the reader.
Parameter TIMEOUT = 5;

ClassMethod Enabled() As %Boolean
{
    Quit ''$GET(^Shutter.Config("warehouse", "enabled")) && ($GET(^Shutter.Config("warehouse", "dataset")) '= "")
}

/// An administrator's settings, never a browser's. Setup.Enable and Setup.Disable are how a site calls this.
ClassMethod Configure(dataset As %String, enabled As %Boolean = 1, maxAgeMinutes As %Integer = 360, showOlder As %Boolean = 0, host As %String = "localhost", port As %Integer = 52773)
{
    Set ^Shutter.Config("warehouse", "dataset") = dataset, ^Shutter.Config("warehouse", "enabled") = ''enabled
    Set ^Shutter.Config("warehouse", "maxAgeMinutes") = +maxAgeMinutes, ^Shutter.Config("warehouse", "showOlder") = ''showOlder
    Set ^Shutter.Config("warehouse", "host") = host, ^Shutter.Config("warehouse", "port") = +port
}

/// Read the case's own patient once and store the result, whatever it was.
ClassMethod ReadForCase(case As Shutter.Store.Case, user As %String) As Shutter.Store.WarehouseRead
{
    Set dataset = $GET(^Shutter.Config("warehouse", "dataset"))
    Set now = ##class(Shutter.Util.Time).NowUTC()
    If (case.PatientIdAuthority = "") || (case.PatientId = "") {
        Set assessed = {"status": "no_identity", "category": "", "freshness": "unknown", "rows": [], "row_count": 0}
    } Else {
        Set payload = ..Fetch(dataset, case.PatientIdAuthority, case.PatientId, .category)
        If $ISOBJECT(payload) {
            Set assessed = ##class(Shutter.Warehouse.Contract).Assess(payload, dataset, case.PatientIdAuthority, case.PatientId, now, +$GET(^Shutter.Config("warehouse", "maxAgeMinutes"), 360), +$GET(^Shutter.Config("warehouse", "showOlder")), ##class(Shutter.Store.WarehouseRead).LastSeen(dataset))
        } Else {
            Set assessed = {"status": "unavailable", "category": (category), "freshness": "unknown", "rows": [], "row_count": 0}
        }
    }
    Set read = ""
    Set sc = ##class(Shutter.Store.WarehouseRead).Record(case, assessed, dataset, user, now, .read)
    Quit read
}

/// The reader's answer, or "" with a category: unreachable, not_authorised, no_credential or reader_error.
ClassMethod Fetch(dataset As %String, authority As %String, patient As %String, Output category As %String) As %DynamicObject [ Private ]
{
    Set category = "", answer = ""
    Try {
        Set request = ##class(%Net.HttpRequest).%New()
        Set request.Server = $GET(^Shutter.Config("warehouse", "host"), "localhost")
        Set request.Port = +$GET(^Shutter.Config("warehouse", "port"), 52773)
        Set request.Timeout = ..#TIMEOUT, request.OpenTimeout = ..#TIMEOUT
        Set credential = ##class(Ens.Config.Credentials).%OpenId(..#CREDENTIAL)
        If '$ISOBJECT(credential) Set category = "no_credential" Quit
        Set request.Username = credential.Username, request.Password = credential.Password
        Do request.SetParam("dataset", dataset), request.SetParam("authority", authority), request.SetParam("patient", patient)
        Set sc = request.Get(..#READERPATH _ "/history")
        If $$$ISERR(sc) Set category = "unreachable" Quit
        Set status = request.HttpResponse.StatusCode
        If (status = 401) || (status = 403) Set category = "not_authorised" Quit
        If status '= 200 Set category = "reader_error" Quit
        Set answer = ##class(%DynamicObject).%FromJSON(request.HttpResponse.Data)
    } Catch ex {
        Set answer = ""
        If category = "" Set category = "reader_error"
    }
    Quit answer
}

}
