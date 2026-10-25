/// The connector to the downstream system: one HTTP contract for normal traffic, rehearsals and
/// recovery writes (docs/CONTRACTS.md, section 1). It classifies what the receiver answered and
/// never retries on its own: an uncertain outcome is reported as such, and reconciliation by
/// operation key is the case workflow's job.
Class Shutter.Operation.Ward Extends Ens.BusinessOperation
{

Parameter ADAPTER = "EnsLib.HTTP.OutboundAdapter";

Parameter INVOCATION = "Queue";

Property Adapter As EnsLib.HTTP.OutboundAdapter;

/// The operations endpoint's path on the downstream system.
/// Overrides the operations path of this item's receiver description in the site profile; empty takes the profile's.
Property OperationsPath As %String(MAXLEN = 200);

Parameter SETTINGS = "OperationsPath:Downstream";

Method OnWardOperation(request As Shutter.Msg.WardOperation, Output response As Shutter.Msg.WardResult) As %Status
{
    Set response = ##class(Shutter.Msg.WardResult).%New()
    If request.Purpose = "read" Quit ..Read(request, response)
    // A dry run goes only to a receiver whose entry in the site profile declares one (CONTRACTS 6.4; v1.19). The gate offers
    // no resend to a receiver without dry runs; this is the second line, so that a receiver that would write the dry run
    // never gets it. An entry that leaves the flag out declares nothing against it.
    If request.DryRun && '##class(Shutter.Util.Json).Bool(##class(Shutter.Store.SiteProfile).ReceiverFeatures(..%ConfigName), "dry_run", 1) {
        Set response.Outcome = "refused", response.ReasonCode = "dry_run_unsupported"
        Set response.Error = "The receiver's entry in the site profile declares no dry run; nothing was sent"
        $$$TRACE("Rehearsal " _ request.OperationKey _ " refused: the receiver's entry declares no dry run")
        Quit $$$OK
    }
    Set body = request.ToWardJSON()
    $$$TRACE($SELECT(request.DryRun: "Rehearsal", 1: "Operation") _ " " _ request.OperationKey _ $SELECT(request.ExpectedVersion '= "": ", expected version " _ request.ExpectedVersion, 1: ""))
    Set http = ##class(%Net.HttpRequest).%New()
    Set http.ContentType = "application/json"
    Do http.EntityBody.Write(body.%ToJSON())
    Set start = $ZHOROLOG
    Set sc = ..Adapter.SendFormDataArray(.httpResponse, "POST", http, "", "", ..Path("operations"))
    Set response.DurationMs = (($ZHOROLOG - start) * 1000) \ 1
    Set ..Retry = 0
    Set text = ""
    If $ISOBJECT($GET(httpResponse)) {
        Set response.HttpStatus = +httpResponse.StatusCode
        Set text = ""
        If $ISOBJECT(httpResponse.Data) {
            Do httpResponse.Data.Rewind()
            While 'httpResponse.Data.AtEnd { Set text = text _ httpResponse.Data.Read(32000) }
        }
        Set response.ResponseJSON = text
    }
    Set parsed = ##class(Shutter.Util.Json).Parse(text, .psc)
    If '$ISOBJECT(parsed) || $$$ISERR(psc) Set parsed = {}
    Do ..Classify(request, response, sc, parsed)
    $$$TRACE("Outcome " _ response.Outcome _ $SELECT(response.ReasonCode '= "": " (" _ response.ReasonCode _ ")", 1: "") _ ", HTTP " _ response.HttpStatus _ ", " _ response.DurationMs _ " ms")
    Quit $$$OK
}

/// A preflight read: GET the encounter's current state and version. Outcome read, unknown_encounter,
/// unavailable or error; EncounterVersion carries the version.
Method Read(request As Shutter.Msg.WardOperation, response As Shutter.Msg.WardResult) As %Status
{
    $$$TRACE("Preflight read of encounter " _ request.EncounterId)
    Set http = ##class(%Net.HttpRequest).%New()
    Set start = $ZHOROLOG
    Set path = ..Path("state", request.EncounterId)
    Set sc = ..Adapter.SendFormDataArray(.httpResponse, "GET", http, "", "", path)
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
    If '$ISOBJECT(parsed) || $$$ISERR(psc) Set parsed = {}
    If response.HttpStatus = 200 {
        Set response.Outcome = "read"
        Set response.EncounterVersion = ##class(Shutter.Util.Json).Str(parsed, "version")
        Set response.ReasonCode = ##class(Shutter.Util.Json).Str(parsed, "state")
        Set epoch = ##class(Shutter.Util.Json).Str(parsed, "epoch")
        If epoch '= "" Set response.Epoch = epoch
    } ElseIf (response.HttpStatus = 404) && (##class(Shutter.Util.Json).Str(parsed, "error") = "unknown_encounter") {
        Set response.Outcome = "unknown_encounter"
        Set response.ReasonCode = "unknown_encounter"
    } ElseIf response.HttpStatus = 404 {
        Set response.Outcome = "error"
        Set response.Error = "HTTP 404 from " _ path _ ": not the downstream system's answer for an unknown encounter"
    } ElseIf response.HttpStatus = "" {
        Set response.Outcome = "unavailable"
        Set response.Error = $SELECT($$$ISERR(sc): $SYSTEM.Status.GetErrorText(sc), 1: "no response")
    } Else {
        Set response.Outcome = "error"
        Set response.Error = "HTTP " _ response.HttpStatus
    }
    $$$TRACE("Preflight: " _ response.Outcome _ ", version " _ response.EncounterVersion _ ", HTTP " _ response.HttpStatus)
    Quit $$$OK
}

/// This item's path of a kind, from its receiver description in the site profile (the item's own name is the
/// receiver's), or the OperationsPath setting when set.
Method Path(kind As %String, encounter As %String = "") As %String
{
    If (kind = "operations") && (..OperationsPath '= "") Quit ..OperationsPath
    Quit ##class(Shutter.Store.SiteProfile).ReceiverPath(..%ConfigName, kind, encounter)
}

/// Map the HTTP status, the adapter's status and the body to an outcome.
Method Classify(request As Shutter.Msg.WardOperation, response As Shutter.Msg.WardResult, sc As %Status, parsed As %DynamicObject) [ Private ]
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
    If status = "" {
        // No HTTP response at all: refused connections never sent anything; anything else is unknown.
        Set msg = $SELECT($$$ISERR(sc): $SYSTEM.Status.GetErrorText(sc), 1: "no response")
        Set response.Error = msg
        // The status codes first (A12): 6059 is a socket that never opened, so nothing was sent; the wording of the
        // message is the fallback.
        Set codes = $SELECT($$$ISERR(sc): $SYSTEM.Status.GetErrorCodes(sc), 1: "")
        Set lower = $ZCONVERT(msg, "L")
        If $LISTFIND($LISTFROMSTRING(codes, ","), 6059) {
            Set response.Outcome = "unavailable"
        } ElseIf (lower [ "refused") || (lower [ "unable to connect") || (lower [ "connect failed") || (lower [ "no route") || (lower [ "unable to open tcp/ip socket") {
            Set response.Outcome = "unavailable"
        } Else {
            Set response.Outcome = "uncertain"
        }
        Quit
    }
    If status = 201 { Set response.Outcome = "applied" Quit }
    If status = 200 {
        If ##class(Shutter.Util.Json).Bool(parsed, "rehearsal") {
            Set response.Outcome = $SELECT(##class(Shutter.Util.Json).Bool(parsed, "would_apply"): "would_apply", 1: "would_not_apply")
            Set response.ReasonCode = ##class(Shutter.Util.Json).Str(parsed, "reason")
        } ElseIf ##class(Shutter.Util.Json).Str(parsed, "reason") = "already_committed" {
            Set response.Outcome = "already_committed"
        } Else {
            Set response.Outcome = $SELECT(##class(Shutter.Util.Json).Bool(parsed, "applied"): "applied", 1: "already_committed")
        }
        Quit
    }
    If status = 409 {
        Set response.Outcome = $SELECT(errorCode = "version_conflict": "version_conflict", 1: "refused")
        Quit
    }
    If status = 422 { Set response.Outcome = "refused" Quit }
    If status = 503 { Set response.Outcome = "unavailable" Set response.Error = "The downstream system is unavailable" Quit }
    If status = 504 { Set response.Outcome = "uncertain" Set response.Error = "The downstream system did not answer in time; the operation may have been applied" Quit }
    If (status = 401) || (status = 403) || (status = 404) {
        Set response.Outcome = "error"
        Set response.Error = "HTTP " _ status _ " from the downstream system: " _ $SELECT(status = 404: "endpoint not found", 1: "not authorised")
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
