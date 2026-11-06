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
    // A dry run goes only to a receiver whose entry in the site profile declares one (CONTRACTS 6.4; v1.21). The gate offers
    // no resend to a receiver without dry runs; this is the second line, so that a receiver that would write the dry run
    // never gets it. An entry that leaves the flag out declares nothing against it.
    If request.DryRun && '##class(Shutter.Util.Json).Bool(##class(Shutter.Store.SiteProfile).ReceiverFeatures(..%ConfigName), "dry_run", 1) {
        Set response.Outcome = "refused", response.ReasonCode = "dry_run_unsupported"
        Set response.Error = "The receiver's entry in the site profile declares no dry run; nothing was sent"
        $$$TRACE("Rehearsal " _ request.OperationKey _ " refused: the receiver's entry declares no dry run")
        Quit $$$OK
    }
    // The failsafe at the point of the resend (v1.29): a recovery write goes only when no newer message of the encounter is
    // pending in Shutter (received after the case's own, not yet delivered here). The gate blocks it earlier on the
    // evidence; this is the last line, read at the moment of the write.
    If (request.Purpose = "recovery") && 'request.DryRun && (request.CaseId '= "") {
        Set guardCase = ##class(Shutter.Store.Case).ByCaseId(request.CaseId)
        Set pending = $SELECT($ISOBJECT(guardCase): ##class(Shutter.Util.ResendGuard).Pending(guardCase), 1: [])
        If pending.%Size() > 0 {
            Set response.Outcome = "refused", response.ReasonCode = "newer_message_pending"
            Set response.Error = "Not sent: " _ ##class(Shutter.Util.ResendGuard).Describe(pending)
            $$$TRACE("Resend " _ request.OperationKey _ " refused at the connector: " _ response.Error)
            Quit $$$OK
        }
        // The same last line for further messages for the patient, on any visit.
        If $ISOBJECT(guardCase) {
            Set further = ##class(Shutter.Util.FurtherMessages).Find(guardCase)
            Set word = ##class(Shutter.Util.FurtherMessages).Describe(guardCase, further)
            If (word '= "") || ##class(Shutter.Util.FurtherMessages).Unreadable(further) || (##class(Shutter.Util.FurtherMessages).Unread(further) '= "") {
                Set response.Outcome = "refused", response.ReasonCode = "further_movement"
                Set response.Error = "Not sent: " _ $SELECT(word '= "": word, ##class(Shutter.Util.FurtherMessages).Unreadable(further): "the patient identifier could not be read", 1: "further messages could not all be read: " _ ##class(Shutter.Util.FurtherMessages).Unread(further))
                $$$TRACE("Resend " _ request.OperationKey _ " refused at the connector: " _ response.Error)
                Quit $$$OK
            }
        }
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
        Do ..TakeRetryAfter(httpResponse, response)
    }
    Set parsed = ##class(Shutter.Util.Json).Parse(text, .psc)
    If '$ISOBJECT(parsed) || $$$ISERR(psc) Set parsed = {}
    Do ..Classify(response, sc, parsed)
    // A feed message delivered (answered, whatever the answer) releases the cases that waited for it (v1.29).
    If (request.Purpose = "normal") && (request.SourceMessageId '= "") Do ##class(Shutter.Store.Case).ReleaseWaitingOnMessage(request.SourceMessageId, response.Outcome)
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
        Do ..TakeRetryAfter(httpResponse, response)
    }
    Set parsed = ##class(Shutter.Util.Json).Parse(text, .psc)
    If '$ISOBJECT(parsed) || $$$ISERR(psc) Set parsed = {}
    Do ..ClassifyRead(response, sc, parsed, path)
    $$$TRACE("Preflight: " _ response.Outcome _ ", version " _ response.EncounterVersion _ ", HTTP " _ response.HttpStatus)
    Quit $$$OK
}

/// Map what a preflight read got to an outcome. A read that got no answer changes nothing at the receiver, so it is
/// unavailable whether it was refused or timed out; the case reads again and then blocks with nothing dispatched.
ClassMethod ClassifyRead(response As Shutter.Msg.WardResult, sc As %Status, parsed As %DynamicObject, path As %String)
{
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
    } ElseIf +response.HttpStatus = 0 {
        // The connector stores +StatusCode, so a request nobody answered reads 0 here, never empty.
        Set response.Outcome = "unavailable"
        Set response.Error = $SELECT($$$ISERR(sc): $SYSTEM.Status.GetErrorText(sc), 1: "no response")
    } Else {
        Set response.Outcome = "error"
        Set response.Error = "HTTP " _ response.HttpStatus
    }
}

/// The receiver's Retry-After (v1.35) on a 503 or 429: kept on the result in seconds, for the case to honour before its
/// preflight read (CONTRACTS 6.5).
ClassMethod TakeRetryAfter(httpResponse As %Net.HttpResponse, response As Shutter.Msg.WardResult) [ Private ]
{
    Try {
        If (response.HttpStatus '= 503) && (response.HttpStatus '= 429) Quit
        Set seconds = ..RetryAfterOf(httpResponse.GetHeader("Retry-After"))
        If seconds '= "" Set response.RetryAfterSeconds = seconds
    } Catch ex {
    }
}

/// A Retry-After header's value as seconds: the delta-seconds form, 1 to 3600 (longer is clamped; 0 or less means no
/// wait); the HTTP-date form and anything else are ignored ("").
ClassMethod RetryAfterOf(value As %String) As %String
{
    Set v = $ZSTRIP($GET(value), "<>W")
    If (v = "") || (v '? 1.N) Quit ""
    If +v <= 0 Quit ""
    Quit $SELECT(+v > 3600: 3600, 1: +v)
}

/// This item's path of a kind, from its receiver description in the site profile (the item's own name is the
/// receiver's), or the OperationsPath setting when set.
Method Path(kind As %String, encounter As %String = "") As %String
{
    If (kind = "operations") && (..OperationsPath '= "") Quit ..OperationsPath
    Quit ##class(Shutter.Store.SiteProfile).ReceiverPath(..%ConfigName, kind, encounter)
}

/// Map the HTTP status, the adapter's status and the body to an outcome. A write nobody answered is uncertain unless the
/// socket never opened: the receiver may have taken it and may still apply it, so it is never reported as refused.
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
        // No HTTP response at all (the connector stores +StatusCode, so that reads 0, never empty): refused connections
        // never sent anything; anything else is unknown.
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
            // A person reads this: the sentence says what it means, and the adapter's words stay beside it for whoever looks
            // into the connection.
            Set response.Outcome = "uncertain"
            Set response.Error = "The downstream system did not answer; the operation may have been applied (" _ msg _ ")"
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
