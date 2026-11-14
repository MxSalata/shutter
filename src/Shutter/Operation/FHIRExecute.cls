/// The writer of a FHIR R4 receiver: at most one version-aware update of one Encounter for one approval. It trusts
/// nothing of the gate's moment, because a request can wait in this item's queue across a disabled item or a
/// production stop: it opens the case, the binding, the approval, the plan and the dispatch decision again, and
/// refuses unless each still holds. The order of what follows is the promise:
/// <ol>
/// <li>the checks above, which send nothing;</li>
/// <li>the connector's two last lines (a newer message pending, further messages for the patient);</li>
/// <li>the fence (<class>Shutter.Store.FHIRAttempt</class>): one row per approval, and a row already sent is never
/// sent again;</li>
/// <li>the admission (<class>Shutter.Util.RecoveryControl</class>): shadow mode and the stop refuse here;</li>
/// <li>its own read of the Encounter through its own adapter, which must give the ETag and the body the approval
/// rests on;</li>
/// <li>the fence row goes from unsent to sent, before the socket;</li>
/// <li>one PUT with If-Match, the approved body as UTF-8 bytes;</li>
/// <li>the answer is classified and recorded, and the permit of the admission is finished on every path.</li>
/// </ol>
/// A refusal is an answer, never an error status. Nothing retries, and no request follows a redirect. The server,
/// port, TLS and credential are this item's adapter settings; the path in front of every request is the fhir block's
/// base of the case's own receiver.
Class Shutter.Operation.FHIRExecute Extends Ens.BusinessOperation
{

Parameter ADAPTER = "EnsLib.HTTP.OutboundAdapter";

Parameter INVOCATION = "Queue";

Property Adapter As EnsLib.HTTP.OutboundAdapter;

/// A dispatch decision older than this many seconds is stale.
Parameter DECISIONAGE = 120;

/// A body of more characters than this is not read as the receiver's answer.
Parameter MAXBODY = 1000000;

/// True once this request took its fence row from unsent to sent.
Property Marked As %Boolean [ InitialExpression = 0, Internal ];

Method OnWrite(request As Shutter.Msg.FHIRWrite, Output response As Shutter.Msg.FHIRWriteResult) As %Status
{
    Set response = ##class(Shutter.Msg.FHIRWriteResult).%New()
    Set response.Outcome = "refused", response.Sent = 0, response.HttpStatus = 0
    Set permit = "", ..Marked = 0
    Try {
        Do ..Write(request, response, .permit)
    } Catch ex {
        Do ..Failed(request, response, ex.DisplayString())
    }
    // Step 8's last line, on every path that was admitted: a permit left admitted latches the stop for the whole
    // deployment (Shutter.Util.RecoveryControl, ReconcileLocked).
    If $ISOBJECT(permit) {
        Set adapter = ##class(Shutter.Msg.WardResult).%New()
        Set adapter.Outcome = response.Outcome, adapter.HttpStatus = response.HttpStatus
        Do ##class(Shutter.Util.RecoveryControl).Finish(permit, adapter)
    }
    Set ..Retry = 0
    $$$TRACE("FHIR update for case " _ request.CaseId _ ": " _ response.Outcome _ ", HTTP " _ response.HttpStatus _ ", " _ $SELECT(response.Sent: "sent", 1: "nothing sent") _ $SELECT(response.ReasonCode '= "": " (" _ response.ReasonCode _ ")", 1: ""))
    Quit $$$OK
}

/// The eight steps. It fills <var>response</var> and returns; <var>permit</var> is the admission's, for OnWrite to
/// finish.
Method Write(request As Shutter.Msg.FHIRWrite, response As Shutter.Msg.FHIRWriteResult, Output permit As Shutter.Store.DispatchPermit) [ Private ]
{
    Set permit = ""

    // ---- 1. What the request names, opened again ----
    Set case = $SELECT(request.CaseId = "": "", 1: ##class(Shutter.Store.Case).ByCaseId(request.CaseId))
    If '$ISOBJECT(case) Do ..Refuse(response, "fhir_binding_missing", "the request names no case that exists") Return
    Set binding = $SELECT(request.BindingId = "": "", 1: ##class(Shutter.Store.FHIRBinding).%OpenId(request.BindingId))
    If '$ISOBJECT(binding) Do ..Refuse(response, "fhir_binding_missing", "the request names no sealed binding") Return
    If binding.CaseGetObjectId() '= case.%Id() Do ..Refuse(response, "fhir_binding_missing", "the binding is another case's") Return
    If (request.ApprovalId = "") || (binding.ApprovalId '= request.ApprovalId) Do ..Refuse(response, "fhir_binding_missing", "the binding is not tied to the request's approval") Return

    // A fence row of this binding that is already sent is answered as what it is, before the checks of the moment:
    // a request that comes a second time after a restart would otherwise read as refused for a stale decision,
    // which says "not applied" of an update that may have landed.
    Set spent = ##class(Shutter.Store.FHIRAttempt).ForApproval(request.ApprovalId)
    If $ISOBJECT(spent) && (spent.State = "sent") && (spent.BindingId = binding.%Id()) Do ..Again(spent, response) Return
    Set spent = ""

    Set approval = ##class(Shutter.Store.Approval).%OpenId(request.ApprovalId)
    If '$ISOBJECT(approval) || (approval.CaseGetObjectId() '= case.%Id()) Do ..Refuse(response, "fhir_binding_missing", "the approval is not this case's") Return
    Set plan = case.CurrentPlan
    If '$ISOBJECT(plan) || (binding.PlanId '= plan.%Id()) || ((request.PlanId '= "") && (request.PlanId '= plan.%Id())) Do ..Refuse(response, "fhir_binding_missing", "the binding's plan is not the case's current plan") Return
    If (##class(Shutter.Store.SiteProfile).ReceiverKind(case.Receiver) '= "fhir_r4") || '##class(Shutter.FHIR.Profile).Enabled(case.Receiver) {
        Do ..Refuse(response, "fhir_recovery_disabled", "the receiver's entry in the site profile does not turn FHIR recovery on")
        Return
    }
    // A FHIR update goes only on a person's approval of this one case. Asked before the approval's validity, so
    // that a policy's or an incident's approval is named as what it is.
    If (approval.Approver = "policy") || (approval.IncidentPlanDigest '= "") Do ..Refuse(response, "fhir_approval_not_personal", "the approval came from a policy or an incident, not from a person for this case") Return
    Set void = approval.InvalidReason(plan, case.CurrentSnapshot, ##class(Shutter.FHIR.Profile).#POLICYVERSION, "", "")
    If void '= "" Do ..Refuse(response, "fhir_approval_void", "the approval no longer authorises this update (" _ void _ ")") Return
    Set stale = ..DecisionProblem(request.DecisionId, case, plan)
    If stale '= "" Do ..Refuse(response, "fhir_dispatch_stale", stale) Return
    If ##class(Shutter.FHIR.Plan).BodyDigest(binding.ApprovedBody) '= binding.ApprovedBodyDigest Do ..Refuse(response, "fhir_body_changed", "the stored body no longer has the digest that was approved") Return

    // ---- 2. The connector's two last lines, as Shutter.Operation.Ward has them before its POST (Ward.cls,
    // OnWardOperation, "The failsafe at the point of the resend" and "The same last line for further messages"),
    // copied: read at the moment of the write ----
    Set pending = ##class(Shutter.Util.ResendGuard).Pending(case)
    If pending.%Size() > 0 Do ..Refuse(response, "newer_message_pending", ##class(Shutter.Util.ResendGuard).Describe(pending)) Return
    Set further = ##class(Shutter.Util.FurtherMessages).Find(case)
    Set word = ##class(Shutter.Util.FurtherMessages).Describe(case, further)
    If word = "" Set word = ##class(Shutter.Util.FurtherNew).Describe(case, further, ##class(Shutter.Util.FurtherNew).Prior(case))
    // A person read these very rows and released the stop; this read gives the same ones.
    If ##class(Shutter.Util.FurtherMessages).Released(case, further) Set word = ""
    If (word '= "") || ##class(Shutter.Util.FurtherMessages).Unreadable(further) || (##class(Shutter.Util.FurtherMessages).Unread(further) '= "") {
        Do ..Refuse(response, "further_movement", $SELECT(word '= "": word, ##class(Shutter.Util.FurtherMessages).Unreadable(further): "the patient identifier could not be read", 1: "further messages could not all be read: " _ ##class(Shutter.Util.FurtherMessages).Unread(further)))
        Return
    }

    // ---- 3. The fence ----
    Set sc = ##class(Shutter.Store.FHIRAttempt).Open(case, binding, .fence, .created)
    If $$$ISERR(sc) || '$ISOBJECT($GET(fence)) Do ..Refuse(response, "fhir_binding_missing", "the approval's fence row could not be opened: " _ $SYSTEM.Status.GetErrorText(sc)) Return
    If fence.State = "sent" Do ..Again(fence, response) Return

    // ---- 4. The admission ----
    If '##class(Shutter.Util.RecoveryControl).Admit("recovery", case.CaseId, case.Receiver, plan.OperationKey, "sha256:" _ binding.ApprovedBodyDigest, .permit, .code, .text) {
        Set response.Outcome = "refused", response.Sent = 0, response.ReasonCode = $EXTRACT(code, 1, 64), response.Error = $EXTRACT(text, 1, 2000)
        Return
    }

    // ---- 5. Its own read: the checks read through FHIR Receiver and the update leaves through this item, each
    // with its own server settings, so this item reads what it is about to change ----
    Set id = binding.EncounterId
    If '##class(Shutter.Operation.FHIRReceiver).IsId(id) Do ..Refuse(response, "fhir_endpoint_differs", "the binding names no Encounter id that can be asked for") Return
    Set path = ..Base(case.Receiver) _ "/Encounter/" _ id
    Set part = ..Read(path, id)
    If part."http_status" '= 200 {
        Do ..Refuse(response, "fhir_endpoint_differs", "this item's own read of the Encounter is not the receiver's answer (" _ $SELECT(part.error '= "": part.error, 1: "HTTP " _ part."http_status") _ ")")
        Return
    }
    If part.etag '= binding.ExpectedEtag Do ..Refuse(response, "fhir_endpoint_differs", "this item's own read gives the Encounter at " _ $SELECT(part.etag = "": "no ETag", 1: "ETag " _ part.etag) _ ", not at the version that was approved") Return
    If ##class(Shutter.FHIR.Plan).BodyDigest(part.body) '= ##class(Shutter.FHIR.Plan).BodyDigest(binding.BaseBody) Do ..Refuse(response, "fhir_endpoint_differs", "this item's own read gives another body than the one the approval rests on, under the same ETag") Return

    // ---- 6. Unsent to sent, once, before the socket ----
    If 'fence.MarkSent() {
        If fence.State '= "sent" Throw ##class(%Exception.General).%New("FenceNotMarked", "5001", , "The fence row could not be marked as sent")
        Do ..Again(fence, response)
        Return
    }
    Set ..Marked = 1
    // From here the truth is "may have been applied" until an answer says otherwise.
    Set response.Outcome = "uncertain", response.Sent = 1, response.Error = "The update was handed to the connection and no answer is recorded; it may have been applied"

    // ---- 7. One request ----
    Set http = ..Request(binding)
    Set sc = $$$OK, answer = ""
    Try {
        Set sc = ..Adapter.SendFormDataArray(.answer, "PUT", http, "", "", path)
    } Catch ex {
        Set sc = ex.AsStatus(), answer = ""
    }
    Set ..Retry = 0

    // ---- 8. Classify and record ----
    Set status = 0, etag = "", location = "", contentType = "", body = ""
    If $ISOBJECT($GET(answer)) {
        Set status = +answer.StatusCode, etag = answer.GetHeader("ETag"), location = answer.GetHeader("Location")
        Set contentType = answer.GetHeader("Content-Type")
        If contentType = "" Set contentType = answer.ContentType
        Set body = ..Text(..Bytes(answer, .over))
    }
    Set outcome = ..Classify(sc, status, etag, location, contentType, body, id, .reason, .diagnostics)
    // An ETag or a Location longer than its column is recorded as empty: a cut one would read as another version.
    Set response.Outcome = outcome, response.HttpStatus = status, response.Sent = (outcome '= "error")
    Set response.ResponseEtag = $SELECT($LENGTH(etag) > 200: "", 1: etag), response.ResponseLocation = $SELECT($LENGTH(location) > 500: "", 1: location)
    Set response.ReasonCode = reason, response.Diagnostics = $EXTRACT(diagnostics, 1, 400)
    Set response.Error = ..Words(outcome, status, diagnostics)
    Set sc = fence.Answer(status, outcome, etag, location, diagnostics)
    If $$$ISERR(sc) Do ##class(Ens.Util.Log).LogWarning($CLASSNAME(), "OnWrite", "The answer to the update of case " _ case.CaseId _ " could not be recorded on its fence row: " _ $SYSTEM.Status.GetErrorText(sc))
}

/// What became of the update, from the adapter's status and the answer. The default is uncertain: an answer nobody
/// named may be an update that landed, and is never reported as not applied.
/// <ul>
/// <li>No response, and the error says the connection never opened: error. No response otherwise: uncertain.</li>
/// <li>200 with an ETag that names a version, a body that is empty or this Encounter at that version, and a Location
/// that is absent or names that version: applied. Any other 200: uncertain. Its content type is never read.</li>
/// <li>201: applied with an ETag that names a version, else uncertain; the reason is update_created either way.</li>
/// <li>Any other 2xx, any 3xx: uncertain.</li>
/// <li>412, 409: version_conflict.</li>
/// <li>405: refused, with the reason invalid_if_match when the body is an OperationOutcome.</li>
/// <li>400, 404, 410, 422 with a FHIR JSON OperationOutcome: refused, with the first issue's diagnostics. A 404
/// without one: uncertain, credentials_or_proxy.</li>
/// <li>401, 403: refused, credentials. Any other 4xx: refused.</li>
/// <li>Any 5xx and any answer no line names: uncertain.</li>
/// </ul>
ClassMethod Classify(sc As %Status, status As %Integer, etag As %String, location As %String, contentType As %String, body As %String, encounterId As %String, Output reason As %String, Output diagnostics As %String) As %String
{
    Set reason = "", diagnostics = "", status = +$GET(status)
    If status = 0 {
        // The status codes first: 6059 is a socket that never opened, so nothing was sent; the wording of the
        // message is the fallback (as Shutter.Operation.Ward's Classify reads it).
        Set msg = $SELECT($$$ISERR(sc): $SYSTEM.Status.GetErrorText(sc), 1: "no response")
        Set diagnostics = $EXTRACT(msg, 1, 300)
        Set codes = $SELECT($$$ISERR(sc): $SYSTEM.Status.GetErrorCodes(sc), 1: "")
        Set lower = $ZCONVERT(msg, "L")
        If $LISTFIND($LISTFROMSTRING(codes, ","), 6059) Quit "error"
        If (lower [ "refused") || (lower [ "unable to connect") || (lower [ "connect failed") || (lower [ "no route") || (lower [ "unable to open tcp/ip socket") Quit "error"
        Quit "uncertain"
    }
    If status = 200 {
        Set diagnostics = ..NotTheUpdate(etag, location, body, encounterId)
        Quit $SELECT(diagnostics = "": "applied", 1: "uncertain")
    }
    If status = 201 {
        Set reason = "update_created"
        If ##class(Shutter.FHIR.Judge).ETagVid(etag, .vid) Quit "applied"
        Set diagnostics = "HTTP 201 with no ETag that names a version"
        Quit "uncertain"
    }
    If (status >= 200) && (status < 400) {
        Set diagnostics = "HTTP " _ status _ " is not an answer to an update"
        Quit "uncertain"
    }
    Set outcome = ..IsOutcome(contentType, body, .issue)
    If (status = 412) || (status = 409) {
        Set diagnostics = issue
        Quit "version_conflict"
    }
    If status = 405 {
        If outcome Set reason = "invalid_if_match", diagnostics = issue
        Quit "refused"
    }
    If (status = 400) || (status = 404) || (status = 410) || (status = 422) {
        If outcome Set diagnostics = issue Quit "refused"
        If status = 404 {
            Set reason = "credentials_or_proxy", diagnostics = "HTTP 404 that is not the receiver's answer (as the endpoint answers a missing or refused login)"
            Quit "uncertain"
        }
        Quit "refused"
    }
    If (status = 401) || (status = 403) {
        Set reason = "credentials"
        Quit "refused"
    }
    If (status >= 400) && (status < 500) Quit "refused"
    Set diagnostics = "HTTP " _ status
    Quit "uncertain"
}

/// The request of step 7, as it is handed to the adapter: If-Match on the binding's ETag byte for byte, and the
/// approved body as its UTF-8 bytes, written raw so that they are not translated a second time.
ClassMethod Request(binding As Shutter.Store.FHIRBinding) As %Net.HttpRequest
{
    Set http = ##class(%Net.HttpRequest).%New()
    Set http.ReadRawMode = 1, http.WriteRawMode = 1
    // Said, not left to the connection: the update never follows a redirect.
    Set http.FollowRedirect = 0
    Set http.ContentType = "application/fhir+json"
    Do http.SetHeader("If-Match", binding.ExpectedEtag)
    Do http.SetHeader("Accept", "application/fhir+json")
    Do http.SetHeader("Prefer", "return=minimal")
    $$$ThrowOnError(http.EntityBody.Write($ZCONVERT(binding.ApprovedBody, "O", "UTF8")))
    Quit http
}

/// Why a 200 does not show the update as applied, or "" when it does.
ClassMethod NotTheUpdate(etag As %String, location As %String, body As %String, encounterId As %String) As %String [ Private ]
{
    If '##class(Shutter.FHIR.Judge).ETagVid(etag, .vid) Quit "HTTP 200 with no ETag that names a version"
    If body '= "" {
        Set b = ##class(Shutter.FHIR.Trust).Parsed(body)
        If '$ISOBJECT(b) || (b.%GetTypeOf("resourceType") '= "string") || (b.resourceType '= "Encounter") || (b.%GetTypeOf("id") '= "string") || (b.id '= encounterId) Quit "HTTP 200 whose body is not this Encounter"
        Set meta = b.%Get("meta")
        If '$ISOBJECT(meta) || 'meta.%IsA("%DynamicObject") || (meta.%GetTypeOf("versionId") '= "string") || (meta.versionId '= vid) Quit "HTTP 200 whose body is not the version its ETag names"
    }
    If (location '= "") && ((location '[ "_history/") || ($PIECE(location, "_history/", $LENGTH(location, "_history/")) '= vid)) Quit "HTTP 200 whose Location names another version than its ETag"
    Quit ""
}

/// Whether an answer's body is a FHIR JSON OperationOutcome; <var>issue</var> is its first issue's diagnostics, to
/// 300 characters.
ClassMethod IsOutcome(contentType As %String, body As %String, Output issue As %String) As %Boolean [ Private ]
{
    Set issue = ""
    If '##class(Shutter.FHIR.Trust).MediaOK(contentType) Quit 0
    Set b = ##class(Shutter.FHIR.Trust).Parsed(body)
    If '$ISOBJECT(b) || (b.%GetTypeOf("resourceType") '= "string") || (b.resourceType '= "OperationOutcome") Quit 0
    Set issues = b.%Get("issue")
    If $ISOBJECT(issues) && issues.%IsA("%DynamicArray") && (issues.%Size() > 0) {
        Set first = issues.%Get(0)
        If $ISOBJECT(first) && first.%IsA("%DynamicObject") && (first.%GetTypeOf("diagnostics") = "string") Set issue = $EXTRACT(first.diagnostics, 1, 300)
    }
    Quit 1
}

/// Why the request's decision does not let the update go, or "": it must be this case's and this plan's dispatch
/// decision, a pass, and no older than DECISIONAGE seconds.
ClassMethod DecisionProblem(decisionId As %String, case As Shutter.Store.Case, plan As Shutter.Store.Plan) As %String [ Private ]
{
    Set decision = $SELECT(decisionId = "": "", 1: ##class(Shutter.Store.GateDecision).%OpenId(decisionId))
    If '$ISOBJECT(decision) Quit "the request names no dispatch decision"
    If (decision.CaseGetObjectId() '= case.%Id()) || (decision.PlanGetObjectId() '= plan.%Id()) Quit "the decision is not this case's and this plan's"
    If (decision.Stage '= "dispatch") || (decision.Outcome '= "pass") Quit "the decision is not a pass at dispatch"
    Set age = ##class(Shutter.Util.Time).SecondsBetween(decision.At, ##class(Shutter.Util.Time).NowUTC())
    If (age = "") || (age > ..#DECISIONAGE) Quit "the dispatch decision is " _ $SELECT(age = "": "of no readable time", 1: age _ " seconds old") _ ", and it holds for " _ ..#DECISIONAGE
    Quit ""
}

/// The answer for a fence row that is already sent: nothing is sent, and the row is answered as what it is, an
/// update that may have landed. With no answer recorded that is uncertain; with one, the recorded outcome, status,
/// ETag and Location again.
ClassMethod Again(fence As Shutter.Store.FHIRAttempt, response As Shutter.Msg.FHIRWriteResult) [ Private ]
{
    Set response.ReasonCode = "fhir_already_sent"
    If (fence.AnsweredAt = "") || (fence.Outcome = "") {
        Set response.Outcome = "uncertain", response.Sent = 1, response.HttpStatus = 0
        Set response.Error = "This approval's update was already sent at " _ fence.SentAt _ " and no answer is recorded, so it may have been applied. Nothing was sent again"
        Quit
    }
    Set response.Outcome = fence.Outcome, response.HttpStatus = +fence.HttpStatus, response.Sent = (fence.Outcome '= "error")
    Set response.ResponseEtag = fence.ResponseEtag, response.ResponseLocation = fence.ResponseLocation, response.Diagnostics = fence.Diagnostics
    Set response.Error = "This approval's update was already sent at " _ fence.SentAt _ "; its recorded answer is given again and nothing was sent again"
}

/// A refusal before anything was sent.
ClassMethod Refuse(response As Shutter.Msg.FHIRWriteResult, code As %String, why As %String) [ Private ]
{
    Set response.Outcome = "refused", response.Sent = 0, response.HttpStatus = 0
    Set response.ReasonCode = code, response.Error = $EXTRACT("Not sent: " _ why, 1, 2000)
}

/// Something failed inside this item. The fence row decides what that means: sent is an update that may have
/// landed, anything else is nothing sent.
Method Failed(request As Shutter.Msg.FHIRWrite, response As Shutter.Msg.FHIRWriteResult, text As %String) [ Private ]
{
    Set row = ""
    Try {
        Set row = ##class(Shutter.Store.FHIRAttempt).ForApproval(request.ApprovalId)
        If $ISOBJECT(row) Do row.%Reload()
    } Catch ex {
        Set row = ""
    }
    If $ISOBJECT(row) && (row.State = "sent") {
        If ..Marked && (row.AnsweredAt = "") {
            Try {
                Do row.Answer(0, "uncertain", "", "", "FHIR Out failed after the update was marked as sent: " _ text)
            } Catch ex {
            }
        }
        Do ..Again(row, response)
        If ..Marked Set response.ReasonCode = "fhir_item_error"
    } Else {
        Set response.Outcome = "error", response.Sent = 0, response.HttpStatus = 0, response.ReasonCode = "fhir_item_error"
    }
    Set response.Error = $EXTRACT("FHIR Out failed: " _ text, 1, 2000)
    Do ##class(Ens.Util.Log).LogWarning($CLASSNAME(), "OnWrite", "The update of case " _ request.CaseId _ " failed inside FHIR Out (" _ response.Outcome _ "): " _ text)
}

/// The sentence a person reads beside an outcome.
ClassMethod Words(outcome As %String, status As %Integer, diagnostics As %String) As %String [ Private ]
{
    Set tail = $SELECT(diagnostics '= "": ": " _ diagnostics, 1: "")
    If outcome = "applied" Quit ""
    If outcome = "version_conflict" Quit $EXTRACT("The receiver refused the update because the Encounter is no longer at the version it was conditional on (HTTP " _ status _ ")" _ tail, 1, 2000)
    If outcome = "refused" Quit $EXTRACT("The receiver refused the update (HTTP " _ status _ ")" _ tail, 1, 2000)
    If outcome = "error" Quit $EXTRACT("The connection to the receiver never opened, so nothing was sent" _ tail, 1, 2000)
    Quit $EXTRACT("What became of the update is not known" _ $SELECT(status: " (HTTP " _ status _ ")", 1: "") _ tail _ ". It may have been applied, and it is not sent again", 1, 2000)
}

/// The path in front of every request: the base of the receiver's fhir block, with no slash at its end.
ClassMethod Base(receiver As %String) As %String [ Private ]
{
    Set block = ##class(Shutter.FHIR.Profile).Block(receiver)
    Set base = $SELECT($ISOBJECT(block) && (block.%GetTypeOf("base") = "string"): block.%Get("base"), 1: "")
    While $EXTRACT(base, *) = "/" {
        Set base = $EXTRACT(base, 1, * - 1)
    }
    Quit base
}

/// This item's own GET of the Encounter, as a part judged by Shutter.FHIR.Trust: read as bytes and decoded here, as
/// FHIR Receiver reads, so that one version read through either item gives the same characters.
Method Read(path As %String, id As %String) As %DynamicObject [ Private ]
{
    Set part = {"http_status": 0, "raw_status": 0, "etag": "", "location": "", "content_type": "", "body": "", "error": ""}
    Set http = ##class(%Net.HttpRequest).%New()
    Set http.ReadRawMode = 1
    // A redirect is never followed: the credential would go with it to another host, and that host's answer would
    // stand as this item's own read.
    Set http.FollowRedirect = 0
    Do http.SetHeader("Accept", "application/fhir+json")
    Set sc = $$$OK, answer = ""
    Try {
        Set sc = ..Adapter.SendFormDataArray(.answer, "GET", http, "", "", path)
    } Catch ex {
        Set sc = ex.AsStatus(), answer = ""
    }
    Set ..Retry = 0
    If '$ISOBJECT($GET(answer)) {
        Do part.%Set("error", $EXTRACT("no answer" _ $SELECT($$$ISERR(sc): ": " _ $SYSTEM.Status.GetErrorText(sc), 1: ""), 1, 400), "string")
        Quit part
    }
    Set raw = +answer.StatusCode
    Do part.%Set("raw_status", raw, "number")
    Do part.%Set("http_status", raw, "number")
    Do part.%Set("etag", answer.GetHeader("ETag"), "string")
    Do part.%Set("location", answer.GetHeader("Location"), "string")
    Set contentType = answer.GetHeader("Content-Type")
    If contentType = "" Set contentType = answer.ContentType
    Do part.%Set("content_type", contentType, "string")
    Set bytes = ..Bytes(answer, .over)
    Set charset = ##class(Shutter.Operation.FHIRReceiver).Charset(contentType)
    If over {
        Do ##class(Shutter.FHIR.Trust).Fail(part, "the answer's body is over " _ ..#MAXBODY _ " characters")
    } ElseIf (charset '= "") && (charset '= "utf-8") && (charset '= "utf8") {
        Do ##class(Shutter.FHIR.Trust).Fail(part, "the answer's charset is not UTF-8")
    } Else {
        Set text = $ZCONVERT(bytes, "I", "UTF8")
        If $ZCONVERT(text, "O", "UTF8") '= bytes {
            Do ##class(Shutter.FHIR.Trust).Fail(part, "the answer's body is not UTF-8")
        } ElseIf $LENGTH(text) > ..#MAXBODY {
            Do ##class(Shutter.FHIR.Trust).Fail(part, "the answer's body is over " _ ..#MAXBODY _ " characters")
        } Else {
            Do part.%Set("body", text, "string")
        }
    }
    Do ##class(Shutter.FHIR.Trust).Part("encounter", part, "Encounter", id)
    Quit part
}

/// An answer's body as the bytes that came, up to three bytes for each character of MAXBODY; <var>over</var> says
/// there were more, and then what is returned is only the start.
ClassMethod Bytes(answer As %Net.HttpResponse, Output over As %Boolean) As %String [ Private ]
{
    // Three bytes are the most one character takes here, so more bytes than that are more characters than the limit.
    Set limit = 3 * ..#MAXBODY
    If limit > 3600000 Set limit = 3600000
    Set bytes = "", over = 0
    If $ISOBJECT(answer.Data) {
        Do answer.Data.Rewind()
        While 'answer.Data.AtEnd {
            Set chunk = answer.Data.Read(32000)
            If ($LENGTH(bytes) + $LENGTH(chunk)) > limit Set over = 1 Quit
            Set bytes = bytes _ chunk
        }
    } ElseIf $LENGTH(answer.Data) > limit {
        Set over = 1
    } Else {
        Set bytes = answer.Data
    }
    Quit bytes
}

/// Bytes as characters when they are UTF-8, and as they came when they are not.
ClassMethod Text(bytes As %String) As %String [ Private ]
{
    If bytes = "" Quit ""
    Set text = $ZCONVERT(bytes, "I", "UTF8")
    Quit $SELECT($ZCONVERT(text, "O", "UTF8") = bytes: text, 1: bytes)
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="Shutter.Msg.FHIRWrite">
    <Method>OnWrite</Method>
  </MapItem>
</MapItems>
}

}
