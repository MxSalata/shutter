/// The demo hospital's own connector to the ward system (the demo bed-management system): the POST of a ward
/// operation to the operations endpoint and the classification of the answer, as Shutter.Operation.Ward does for
/// normal traffic, without the preflight read and without a site profile: the path is this item's setting. It never
/// retries on its own and never turns an outcome into a failed message; the feed process reads the outcome.
Class Hospital.Operation.DownstreamOut Extends Ens.BusinessOperation
{

Parameter ADAPTER = "EnsLib.HTTP.OutboundAdapter";

Parameter INVOCATION = "Queue";

Property Adapter As EnsLib.HTTP.OutboundAdapter;

/// The operations endpoint's path on the ward system.
Property OperationsPath As %String(MAXLEN = 200) [ InitialExpression = "/downstream/api/operations" ];

Parameter SETTINGS = "OperationsPath:Ward";

Method OnWardOperation(request As Shutter.Msg.WardOperation, Output response As Shutter.Msg.WardResult) As %Status
{
    Set response = ##class(Shutter.Msg.WardResult).%New()
    If request.Purpose = "read" {
        Set response.Outcome = "error", response.Error = "The hospital's connector sends operations only; it has no preflight read"
        Quit $$$OK
    }
    Set body = request.ToWardJSON()
    $$$TRACE("Operation " _ request.OperationKey)
    Set http = ##class(%Net.HttpRequest).%New()
    Set http.ContentType = "application/json"
    Do http.EntityBody.Write(body.%ToJSON())
    Set start = $ZHOROLOG
    Set sc = ..Adapter.SendFormDataArray(.httpResponse, "POST", http, "", "", ..OperationsPath)
    Set response.DurationMs = (($ZHOROLOG - start) * 1000) \ 1
    Set ..Retry = 0
    Set text = ""
    If $ISOBJECT($GET(httpResponse)) {
        Set response.HttpStatus = +httpResponse.StatusCode
        If $ISOBJECT(httpResponse.Data) {
            Do httpResponse.Data.Rewind()
            While 'httpResponse.Data.AtEnd { Set text = text _ httpResponse.Data.Read(32000) }
        }
        Set response.ResponseJSON = text
    }
    Set parsed = ##class(Shutter.Util.Json).Parse(text, .psc)
    If '$ISOBJECT(parsed) || $$$ISERR(psc) || 'parsed.%IsA("%DynamicObject") Set parsed = {}
    Do ..Classify(response, sc, parsed)
    // A delivery the ward system could not take or did not answer is an alert as well as a failed result, as a real
    // connector's would be: the production's Ens.Alert item (Shutter's alert intake, CONTRACTS 11) hears of it too.
    If (response.Outcome = "unavailable") || (response.Outcome = "uncertain") {
        Set alert = ##class(Ens.AlertRequest).%New()
        Set alert.AlertText = "Delivery " _ response.Outcome _ " for " _ request.OperationKey _ ": " _ $SELECT(response.Error '= "": response.Error, 1: "HTTP " _ response.HttpStatus)
        Set alert.SourceConfigName = ..%ConfigName, alert.SessionId = ..%SessionId
        Do ..SendAlert(alert)
    }
    $$$TRACE("Outcome " _ response.Outcome _ $SELECT(response.ReasonCode '= "": " (" _ response.ReasonCode _ ")", 1: "") _ ", HTTP " _ response.HttpStatus _ ", " _ response.DurationMs _ " ms")
    Quit $$$OK
}

/// Map the HTTP status, the adapter's status and the body to an outcome: the same reading of the ward system's
/// answers as Shutter's connector, copied so that this namespace needs no Shutter.Operation package.
ClassMethod Classify(response As Shutter.Msg.WardResult, sc As %Status, parsed As %DynamicObject)
{
    Set status = response.HttpStatus
    Set errorCode = ##class(Shutter.Util.Json).Str(parsed, "error")
    Set response.ReasonCode = errorCode
    If $ISOBJECT(parsed.%Get("receipt")) Set response.ReceiptJSON = parsed.%Get("receipt").%ToJSON()
    Set enc = parsed.%Get("encounter")
    If $ISOBJECT(enc) Set response.EncounterVersion = ##class(Shutter.Util.Json).Str(enc, "version")
    Set before = parsed.%Get("encounter_before"), after = parsed.%Get("encounter_after")
    If $ISOBJECT(before) Set response.EncounterVersion = ##class(Shutter.Util.Json).Str(before, "version")
    If $ISOBJECT(after) {
        Set response.VersionAfter = ##class(Shutter.Util.Json).Str(after, "version")
        If '$ISOBJECT(before) && '$ISOBJECT(enc) Set response.EncounterVersion = response.VersionAfter - 1
    }
    If ##class(Shutter.Util.Json).Str(parsed, "current_version") '= "" Set response.EncounterVersion = parsed.%Get("current_version")
    Set epoch = ##class(Shutter.Util.Json).Str(parsed, "epoch")
    If (epoch = "") && $ISOBJECT(enc) Set epoch = ##class(Shutter.Util.Json).Str(enc, "epoch")
    If (epoch = "") && $ISOBJECT(before) Set epoch = ##class(Shutter.Util.Json).Str(before, "epoch")
    If (epoch = "") && $ISOBJECT(parsed.%Get("receipt")) Set epoch = ##class(Shutter.Util.Json).Str(parsed.%Get("receipt"), "epoch")
    If epoch '= "" Set response.Epoch = epoch
    If +status = 0 {
        // No HTTP response at all (this item stores +StatusCode, so that reads 0, never empty): a refused connection never
        // sent anything; anything else is unknown.
        Set msg = $SELECT($$$ISERR(sc): $SYSTEM.Status.GetErrorText(sc), 1: "no response")
        Set response.Error = msg
        // The status codes first: 6059 is a socket that never opened, so nothing was sent; the wording of the
        // message is the fallback.
        Set codes = $SELECT($$$ISERR(sc): $SYSTEM.Status.GetErrorCodes(sc), 1: "")
        Set lower = $ZCONVERT(msg, "L")
        If $LISTFIND($LISTFROMSTRING(codes, ","), 6059) {
            Set response.Outcome = "unavailable"
        } ElseIf (lower [ "refused") || (lower [ "unable to connect") || (lower [ "connect failed") || (lower [ "no route") || (lower [ "unable to open tcp/ip socket") {
            Set response.Outcome = "unavailable"
        } Else {
            // A person reads this: the sentence says what it means, and the adapter's words stay beside it for whoever looks
            // into the connection.
            Set response.Outcome = "uncertain"
            Set response.Error = "The ward system did not answer; the operation may have been applied (" _ msg _ ")"
        }
        Quit
    }
    If status = 201 { Set response.Outcome = "applied" Quit }
    If status = 200 {
        If ##class(Shutter.Util.Json).Bool(parsed, "rehearsal") {
            Set response.Outcome = $SELECT(##class(Shutter.Util.Json).Bool(parsed, "would_apply"): "would_apply", 1: "would_not_apply")
            Set response.ReasonCode = ##class(Shutter.Util.Json).Str(parsed, "reason")
        } ElseIf ##class(Shutter.Util.Json).Bool(parsed, "applied") && (##class(Shutter.Util.Json).Str(parsed, "reason") '= "already_committed") {
            Set response.Outcome = "applied"
        } ElseIf '$ISOBJECT(parsed.%Get("receipt")) {
            Set response.Outcome = "uncertain"
            Set response.Error = "HTTP 200 with no receipt and no sign it was applied; the operation may or may not have been applied"
        } Else {
            Set response.Outcome = "already_committed"
        }
        Quit
    }
    If status = 409 {
        Set response.Outcome = $SELECT(errorCode = "version_conflict": "version_conflict", 1: "refused")
        Quit
    }
    If status = 422 { Set response.Outcome = "refused" Quit }
    If status = 503 { Set response.Outcome = "unavailable" Set response.Error = "The ward system is unavailable" Quit }
    If status = 504 { Set response.Outcome = "uncertain" Set response.Error = "The ward system did not answer in time; the operation may have been applied" Quit }
    If (status = 401) || (status = 403) || (status = 404) {
        Set response.Outcome = "error"
        Set response.Error = "HTTP " _ status _ " from the ward system: " _ $SELECT(status = 404: "endpoint not found", 1: "not authorised")
        Quit
    }
    Set response.Outcome = $SELECT(status >= 500: "uncertain", 1: "error")
    Set response.Error = "HTTP " _ status _ $SELECT($$$ISERR(sc): ": " _ $SYSTEM.Status.GetErrorText(sc), 1: "")
    Quit
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="Shutter.Msg.WardOperation">
    <Method>OnWardOperation</Method>
  </MapItem>
</MapItems>
}

}
