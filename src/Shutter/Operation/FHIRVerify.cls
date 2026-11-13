/// The verifier of a FHIR R4 receiver: after the one update of a case, it reads the receiver's record through FHIR
/// Receiver and says what holds. It sends nothing to the receiver but reads, and it decides nothing itself: the walk
/// fills a context from what was sealed (the plan's binding), what was sent (the one-dispatch fence and the attempt) and
/// what was read now, and <class>Shutter.FHIR.Judge</class> gives the verdict on that context alone.
/// <p>The walk: the case, the plan's binding, the fence row of the binding's approval and the attempt; then one read
/// request of purpose verify, which reads the current Encounter, the Patient, every bound Location once, the instance
/// history and, only when the answer to the update named a version, that version by id. A read request that fails,
/// times out or comes back with an error is a context whose parts all have status 0, which the Judge answers as
/// unknown with another read asked for while the settle window is open. Whatever of the context is missing (no
/// binding, no fence, no attempt) is left out, and the Judge refuses a context that is not whole: nothing is ever
/// verified on a walk that skipped a step.</p>
/// <p>The six outcomes of the Judge are stored under the four words every verification uses (<method>Mapped</method>),
/// with the Judge's own word kept beside it as judge_outcome and the case's reason code as case_code.</p>
Class Shutter.Operation.FHIRVerify Extends Ens.BusinessOperation
{

Parameter INVOCATION = "Queue";

/// The item that reads the receiver.
Property ReaderTarget As %String(MAXLEN = 128) [ InitialExpression = "FHIR Receiver" ];

/// From this many seconds after the update was sent, a read is the last of the settle window: what it does not show
/// is no longer waited for.
Parameter SETTLEFINALSECONDS = 70;

Method OnVerifyRequest(request As Shutter.Msg.VerifyRequest, Output response As Shutter.Msg.VerifyResult) As %Status
{
    Set response = ##class(Shutter.Msg.VerifyResult).%New()
    Set sc = $$$OK
    Try {
        Set sc = ..Walk(request, response)
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// The reads of one walk, through FHIR Receiver. The one seam a test double overrides.
Method ReadParts(read As Shutter.Msg.FHIRRead, Output result As Shutter.Msg.FHIRReadResult) As %Status
{
    Quit ..SendRequestSync(..ReaderTarget, read, .result, 60)
}

/// The walk, the verdict and its record.
Method Walk(request As Shutter.Msg.VerifyRequest, response As Shutter.Msg.VerifyResult) As %Status [ Private ]
{
    Set case = ##class(Shutter.Store.Case).ByCaseId(request.CaseId)
    If '$ISOBJECT(case) {
        // No case to record anything on: the answer is the unknown that needs a person, never a verdict.
        Set detail = {"reason": "context_invalid", "note": ("unknown case " _ request.CaseId)}
        Do detail.%Set("retry", 0, "boolean")
        Set response.Outcome = ..Stamp(detail, "unknown")
        Set response.Error = "Unknown case " _ request.CaseId, response.Summary = response.Error, response.DetailJSON = detail.%ToJSON()
        Quit $$$OK
    }
    Set attempt = ..AttemptOf(case, request.AttemptId)
    Set binding = ##class(Shutter.Store.FHIRBinding).ForPlan(request.PlanId)
    If $ISOBJECT(binding) && (binding.CaseGetObjectId() '= case.%Id()) Set binding = ""
    Set fence = $SELECT($ISOBJECT(binding): ##class(Shutter.Store.FHIRAttempt).ForApproval(binding.ApprovalId), 1: "")
    If $ISOBJECT(fence) && (fence.BindingId '= binding.%Id()) Set fence = ""
    // The fence is written by SQL: a row this job already holds open is read again, so the walk sees the stored one.
    If $ISOBJECT(fence) Do fence.%Reload()

    // The version the answer to the update named, when its ETag names one: only then is a version read by id.
    Set vid = ""
    If $ISOBJECT(fence) && '##class(Shutter.FHIR.Judge).ETagVid(fence.ResponseEtag, .vid) Set vid = ""

    Set ctx = {}
    Do ctx.%Set("settle_final_seconds", +..#SETTLEFINALSECONDS, "number")
    Set bound = []
    If $ISOBJECT(binding) {
        Set b = binding.JudgeBinding()
        Set ctx.binding = b
        Do ctx.%Set("base_body", binding.BaseBody, "string")
        Do ctx.%Set("expected_body", binding.ApprovedBody, "string")
        Set it = b.locations.%GetIterator()
        While it.%GetNext(.i, .l) { Do bound.%Push(l.reference, "string") }
    }
    Set ctx.attempt = ..AttemptContext(attempt, fence)

    // One read request: the current Encounter, the Patient, each bound Location once, the history, the version.
    Set parts = ""
    If $ISOBJECT(binding) {
        Set read = ##class(Shutter.Msg.FHIRRead).%New()
        Set read.CaseId = case.CaseId, read.Purpose = "verify", read.EncounterId = binding.EncounterId
        Set read.PatientRef = b.patient.reference, read.LocationRefsJSON = bound.%ToJSON(), read.Vid = vid
        Set parts = ..Parts(read)
    }
    Do ..ReadContext(ctx, parts, bound, vid)

    Set judged = ##class(Shutter.FHIR.Judge).Judge(ctx, .text, .detail)
    Set outcome = ..Stamp(detail, judged)
    Set sc = ##class(Shutter.Store.Verification).Create(case, attempt, outcome, text, detail, .v)
    If $$$ISERR(sc) Set response.Error = $SYSTEM.Status.GetErrorText(sc)
    Set response.Outcome = outcome, response.Summary = text, response.DetailJSON = detail.%ToJSON()
    If $$$ISOK(sc) && $ISOBJECT($GET(v)) Set response.VerificationId = v.%Id()
    Do case.Note("artifact", "Verification: " _ outcome _ ". " _ text, "system", "verification:" _ response.VerificationId)
    $$$TRACE("FHIR verification for " _ case.CaseId _ ": " _ judged _ " (" _ detail.reason _ "), stored as " _ outcome)
    Quit $$$OK
}

/// The word a verification is stored under for an outcome of the Judge, and the case's reason code with it:
/// <table>
/// <tr><td>verified, verified_continued</td><td>verified</td><td>no code</td></tr>
/// <tr><td>committed_review</td><td>unresolved</td><td>FHIR_COMMITTED_NEEDS_REVIEW</td></tr>
/// <tr><td>unknown, another read asked for</td><td>unresolved</td><td>no code</td></tr>
/// <tr><td>unknown, final</td><td>unresolved</td><td>FHIR_WRITE_OUTCOME_UNKNOWN</td></tr>
/// <tr><td>not_found</td><td>not_committed</td><td>FHIR_WRITE_NOT_FOUND</td></tr>
/// <tr><td>failed</td><td>failed</td><td>FHIR_WRITE_CONTRADICTED</td></tr>
/// </table>
/// A word the Judge does not have is the unknown that is final.
ClassMethod Mapped(judged As %String, retry As %Boolean, Output code As %String) As %String
{
    Set code = $CASE(judged,
        "verified": "",
        "verified_continued": "",
        "committed_review": "FHIR_COMMITTED_NEEDS_REVIEW",
        "unknown": $SELECT(retry: "", 1: "FHIR_WRITE_OUTCOME_UNKNOWN"),
        "not_found": "FHIR_WRITE_NOT_FOUND",
        "failed": "FHIR_WRITE_CONTRADICTED",
        : "FHIR_WRITE_OUTCOME_UNKNOWN")
    Quit $CASE(judged, "verified": "verified", "verified_continued": "verified", "not_found": "not_committed", "failed": "failed", : "unresolved")
}

/// Makes the Judge's detail the detail of a FHIR verification: the kind, the Judge's own word, the disposition, and
/// the FHIR reason code in place of the Judge's. Returns the word the verification is stored under.
ClassMethod Stamp(detail As %DynamicObject, judged As %String) As %String [ Private ]
{
    Set retry = (detail.%GetTypeOf("retry") = "boolean") && detail.retry
    Set outcome = ..Mapped(judged, retry, .code)
    Do detail.%Set("kind", "fhir", "string")
    Do detail.%Set("judge_outcome", judged, "string")
    Do detail.%Set("disposition", "resend", "string")
    Do detail.%Set("case_code", code, "string")
    // The page and the flow read a verdict key as the other receivers' verdict: a FHIR verification has none.
    Do detail.%Remove("verdict")
    Quit outcome
}

/// The attempt row a request names, when it is this case's; else "".
ClassMethod AttemptOf(case As Shutter.Store.Case, id As %String) As Shutter.Store.ExecutionAttempt [ Private ]
{
    If id = "" Quit ""
    Set attempt = ##class(Shutter.Store.ExecutionAttempt).%OpenId(id)
    If '$ISOBJECT(attempt) || (attempt.CaseGetObjectId() '= case.%Id()) Quit ""
    Quit attempt
}

/// The context's attempt: the outcome and status the attempt row records, the answer's ETag and Location as the fence
/// kept them (verbatim, absent when empty), and the seconds since the update was sent. What is not recorded is left
/// out, and the Judge refuses the context.
ClassMethod AttemptContext(attempt As Shutter.Store.ExecutionAttempt, fence As Shutter.Store.FHIRAttempt) As %DynamicObject [ Private ]
{
    Set a = {}
    If $ISOBJECT(attempt) {
        Do a.%Set("outcome", attempt.Outcome, "string")
        Do a.%Set("http_status", +attempt.HttpStatus, "number")
    }
    If $ISOBJECT(fence) {
        If fence.ResponseEtag '= "" Do a.%Set("response_etag", fence.ResponseEtag, "string")
        If fence.ResponseLocation '= "" Do a.%Set("response_location", fence.ResponseLocation, "string")
        Set since = ##class(Shutter.Util.Time).SecondsBetween(fence.SentAt, ##class(Shutter.Util.Time).NowUTC())
        If since '= "" Do a.%Set("seconds_since", +since, "number")
    }
    Quit a
}

/// The parts one read request gave, or "" when the request failed, timed out, answered with an error or carried
/// nothing that can be read.
Method Parts(read As Shutter.Msg.FHIRRead) As %DynamicObject [ Private ]
{
    Set parts = ""
    Try {
        Set sc = ..ReadParts(read, .result)
        If $$$ISERR(sc) || '$ISOBJECT($GET(result)) || (result.Error '= "") || (result.PartsJSON = "") Quit
        Set parts = ##class(%DynamicAbstractObject).%FromJSON(result.PartsJSON)
        If '$ISOBJECT(parts) || 'parts.%IsA("%DynamicObject") Set parts = ""
    } Catch ex {
        Set parts = ""
    }
    Quit parts
}

/// Puts the reads into the context. With parts, each is what the reader carried, and the Location reads are the ones
/// it made, no more and no fewer. With none, every part has status 0: the history, the current Encounter, the Patient,
/// one read of each bound Location, and the version when one was asked for.
ClassMethod ReadContext(ctx As %DynamicObject, parts As %DynamicObject, bound As %DynamicArray, vid As %String) [ Private ]
{
    Set whole = $ISOBJECT(parts)
    Set ctx.history = ..Read($SELECT(whole: parts.%Get("history"), 1: ""))
    Set ctx.current = ..Read($SELECT(whole: parts.%Get("encounter"), 1: ""))
    Set ctx.patient = ..Read($SELECT(whole: parts.%Get("patient"), 1: ""))
    If vid = "" {
        Do ctx.%Set("vread", "", "null")
    } Else {
        Set ctx.vread = ..Read($SELECT(whole: parts.%Get("vread"), 1: ""))
    }
    Set locations = []
    If whole {
        Set list = parts.%Get("locations")
        If $ISOBJECT(list) && list.%IsA("%DynamicArray") {
            Set it = list.%GetIterator()
            While it.%GetNext(.i, .part) {
                Set read = ..Read(part)
                Do read.%Set("reference", $SELECT($ISOBJECT(part) && (part.%GetTypeOf("reference") = "string"): part.reference, 1: ""), "string")
                Do locations.%Push(read)
            }
        }
    } Else {
        Set it = bound.%GetIterator()
        While it.%GetNext(.i, .reference) {
            Set read = ..Read("")
            Do read.%Set("reference", reference, "string")
            Do locations.%Push(read)
        }
    }
    Set ctx.locations = locations
}

/// One part as the Judge reads it: the status that can be trusted, the ETag, the content type and the body. A part
/// that is absent or has no status is a read with no answer.
ClassMethod Read(part) As %DynamicObject [ Private ]
{
    Set read = {}
    Set known = $ISOBJECT(part) && part.%IsA("%DynamicObject")
    Do read.%Set("http_status", $SELECT(known && (part.%GetTypeOf("http_status") = "number"): +part.%Get("http_status"), 1: 0), "number")
    For key = "etag", "content_type", "body" {
        Do read.%Set(key, $SELECT(known && (part.%GetTypeOf(key) = "string"): part.%Get(key), 1: ""), "string")
    }
    Quit read
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="Shutter.Msg.VerifyRequest">
    <Method>OnVerifyRequest</Method>
  </MapItem>
</MapItems>
}

}
