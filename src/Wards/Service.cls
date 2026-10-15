/// The synthetic ward system's behaviour, behind <class>Wards.API</class>. The contract is docs/CONTRACTS.md,
/// section 1. Each method sets the HTTP status in <var>status</var> and returns the JSON body: an empty string for
/// the 504 that <code>commit_drop_response</code> produces.
Class Wards.Service
{

/// Apply an operation, or rehearse it when <code>dry_run</code> is true (section 1.1). Faults apply to real
/// operations only, never to a rehearsal.
ClassMethod Apply(request As %DynamicObject, Output status As %Integer) As %DynamicObject
{
    Set dryRun = ''request.%Get("dry_run")
    Set key = request.%Get("operation_key")
    If 'dryRun, ..FaultFor(key) = "fail_before_accept" {
        Set status = 503
        Quit {"error": "ward_unavailable"}
    }
    Set problem = ..Validate(request)
    If problem '= "" {
        Quit ..Refuse(dryRun, 422, {"error": "invalid_request", "detail": (problem)}, .status)
    }
    Set digest = ..Digest(..Canonical(request))
    Set given = request.%Get("payload_digest")
    If (given '= ""), (given '= digest) {
        Quit ..Refuse(dryRun, 422, {"error": "payload_digest_mismatch"}, .status)
    }
    Set encounterId = request.%Get("encounter_id")
    Lock +^Wards.Lock(encounterId):10
    If '$TEST {
        Set status = 503
        Quit {"error": "ward_unavailable", "detail": "another operation holds the encounter"}
    }
    Try {
        Set result = ..ApplyLocked(request, key, digest, dryRun, .status)
    } Catch ex {
        Set status = 500
        Set result = {"error": "internal_error", "detail": (ex.DisplayString())}
    }
    Lock -^Wards.Lock(encounterId)
    Quit result
}

/// The checks after the request is valid, then the write, with the encounter locked (section 1.1, order of checks).
ClassMethod ApplyLocked(request As %DynamicObject, key As %String, digest As %String, dryRun As %Boolean, Output status As %Integer) As %DynamicObject [ Private ]
{
    Set encounterId = request.%Get("encounter_id")
    Set event = request.%Get("event")
    Set encounter = ##class(Wards.Encounter).EncounterIdIdxOpen(encounterId)
    // Part of request validity: an encounter never changes its patient
    If $ISOBJECT(encounter) {
        If (encounter.PatientId '= request.%Get("patient_id")) || (encounter.PatientIdAuthority '= request.%Get("patient_id_authority")) {
            Quit ..Refuse(dryRun, 422, {"error": "patient_mismatch", "encounter_id": (encounterId)}, .status)
        }
    }
    // The misleading duplicate error set for this key answers whatever the version, and writes nothing
    If 'dryRun, ..FaultFor(key) = "misleading_duplicate_error", $GET(^Wards.Config("fault", "key")) '= "" {
        Set status = 409
        Quit {"error": "duplicate_message"}
    }
    // A committed receipt for this key answers before any version check
    Set receipt = ##class(Wards.Receipt).OperationKeyIdxOpen(key)
    If $ISOBJECT(receipt) {
        If receipt.PayloadDigest '= digest {
            Quit ..Refuse(dryRun, 409, {"error": "key_reused_with_different_payload", "operation_key": (key)}, .status)
        }
        Set status = 200
        If dryRun {
            Quit {"applied": false, "rehearsal": true, "would_apply": false, "reason": "already_committed", "receipt": (receipt.ToJSON())}
        }
        Set out = {"applied": false, "reason": "already_committed", "receipt": (receipt.ToJSON())}
        Set encounter = ##class(Wards.Encounter).EncounterIdIdxOpen(receipt.EncounterId)
        Do:$ISOBJECT(encounter) out.%Set("encounter", encounter.ToJSON())
        Quit out
    }
    Set current = $SELECT($ISOBJECT(encounter): encounter.Version, 1: 0)
    If '$ISOBJECT(encounter), event '= "admit" {
        Quit ..Refuse(dryRun, 422, {"error": "unknown_encounter", "encounter_id": (encounterId)}, .status)
    }
    Set expected = request.%Get("expected_version")
    If (expected '= ""), (+expected '= current) {
        If 'dryRun, ..FaultFor(key) = "misleading_duplicate_error" {
            Set status = 409
            Quit {"error": "duplicate_message"}
        }
        Quit ..Refuse(dryRun, 409, {"error": "version_conflict", "expected_version": (+expected), "current_version": (current)}, .status)
    }
    If $ISOBJECT(encounter), (encounter.State = "discharged") || (event = "admit") {
        Quit ..Refuse(dryRun, 422, {"error": "invalid_transition", "state": (encounter.State), "event": (event)}, .status)
    }
    Set now = ..Now()
    Set ward = $SELECT((event = "admit") || (event = "transfer"): request.%Get("ward"), 1: "")
    TSTART
    Try {
        If '$ISOBJECT(encounter) {
            Set encounter = ##class(Wards.Encounter).%New()
            Set encounter.EncounterId = encounterId
            Set encounter.PatientId = request.%Get("patient_id")
            Set encounter.PatientIdAuthority = request.%Get("patient_id_authority")
        }
        If event = "admit" {
            Set encounter.State = "admitted", encounter.Ward = ward
        } ElseIf event = "transfer" {
            Set encounter.Ward = ward
        } ElseIf event = "discharge" {
            Set encounter.State = "discharged", encounter.Ward = ""
        }
        Set encounter.Version = current + 1
        Set encounter.UpdatedAt = now
        $$$ThrowOnError(encounter.%Save())
        Set history = ##class(Wards.Event).%New()
        Set history.EncounterId = encounterId, history.VersionAfter = encounter.Version, history.Event = event
        Set history.Ward = ward, history.EventTime = request.%Get("event_time"), history.AppliedAt = now
        Set history.OperationKey = key
        $$$ThrowOnError(history.%Save())
        Set receipt = ##class(Wards.Receipt).%New()
        Set receipt.OperationKey = key, receipt.EncounterId = encounterId, receipt.Event = event, receipt.Ward = ward
        Set receipt.EventTime = history.EventTime, receipt.AppliedAt = now
        Set receipt.VersionBefore = current, receipt.VersionAfter = encounter.Version
        Set receipt.PayloadDigest = digest, receipt.SourceMessageId = request.%Get("source_message_id")
        $$$ThrowOnError(receipt.%Save())
        If dryRun {
            // The rehearsal: everything was validated and written, and is now rolled back
            Set after = encounter.ToJSON()
            TROLLBACK 1
            Set status = 200
            Set result = {"applied": false, "rehearsal": true, "would_apply": true, "encounter_after": (after)}
        } Else {
            TCOMMIT
            Set status = 201
            Set result = {"applied": true, "receipt": (receipt.ToJSON()), "encounter": (encounter.ToJSON())}
        }
    } Catch ex {
        TROLLBACK:$TLEVEL 1
        Set status = 500
        Set result = {"error": "internal_error", "detail": (ex.DisplayString())}
    }
    If 'dryRun, status = 201, ..FaultFor(key) = "commit_drop_response" {
        // Committed, then the response is lost
        Set status = 504
        Quit ""
    }
    Quit result
}

/// A refusal: as itself for a real operation, or for a rehearsal as a result that would not apply.
ClassMethod Refuse(dryRun As %Boolean, httpStatus As %Integer, body As %DynamicObject, Output status As %Integer) As %DynamicObject [ Private ]
{
    If 'dryRun {
        Set status = httpStatus
        Quit body
    }
    Set status = 200
    Set out = {"applied": false, "rehearsal": true, "would_apply": false, "reason": (body.%Get("error"))}
    Set iter = body.%GetIterator()
    While iter.%GetNext(.name, .value) {
        Continue:name="error"
        Do out.%Set(name, value)
    }
    Quit out
}

/// An empty string when the request is valid, otherwise what is wrong with it.
ClassMethod Validate(request As %DynamicObject) As %String
{
    For field = "operation_key", "encounter_id", "patient_id", "patient_id_authority", "event", "event_time", "source_system" {
        If request.%Get(field) = "" {
            Return field _ " is required"
        }
    }
    If $LENGTH(request.%Get("operation_key")) > 255 {
        Return "operation_key is longer than 255 characters"
    }
    Set event = request.%Get("event")
    If '$LISTFIND($LISTBUILD("admit", "transfer", "discharge", "update"), event) {
        Return "event must be admit, transfer, discharge or update"
    }
    If (event = "admit") || (event = "transfer") {
        If request.%Get("ward") = "" {
            Return "ward is required for " _ event
        }
    } ElseIf request.%IsDefined("ward"), request.%GetTypeOf("ward") '= "null" {
        Return "ward must be null for " _ event
    }
    If '$MATCH(request.%Get("event_time"), "\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z") {
        Return "event_time must be ISO 8601 UTC, for example 2026-10-15T09:20:00Z"
    }
    If request.%IsDefined("expected_version"), request.%GetTypeOf("expected_version") '= "null" {
        If '$MATCH(request.%Get("expected_version"), "\d+") {
            Return "expected_version must be a whole number"
        }
    }
    Return ""
}

/// The canonical payload (section 1.6): these keys in this order, strings as given, null for no ward.
ClassMethod Canonical(request As %DynamicObject) As %String
{
    Set canonical = {}
    For field = "operation_key", "encounter_id", "patient_id", "patient_id_authority", "event" {
        Do canonical.%Set(field, request.%Get(field), "string")
    }
    Set ward = request.%Get("ward")
    If ward = "" {
        Do canonical.%Set("ward", "", "null")
    } Else {
        Do canonical.%Set("ward", ward, "string")
    }
    Do canonical.%Set("event_time", request.%Get("event_time"), "string")
    Do canonical.%Set("source_system", request.%Get("source_system"), "string")
    Quit canonical.%ToJSON()
}

/// <code>sha256:</code> and the lower-case hex SHA-256 of the canonical payload's UTF-8 bytes.
ClassMethod Digest(canonical As %String) As %String
{
    Set hash = $SYSTEM.Encryption.SHAHash(256, $ZCONVERT(canonical, "O", "UTF8"))
    Set hex = ""
    For i = 1:1:$LENGTH(hash) {
        Set hex = hex _ $ZCONVERT($EXTRACT("0" _ $ZHEX($ASCII(hash, i)), *-1, *), "L")
    }
    Quit "sha256:" _ hex
}

/// The time now, ISO 8601 UTC with a Z.
ClassMethod Now() As %String
{
    Quit $TRANSLATE($ZDATETIME($ZTIMESTAMP, 3, 1), " ", "T") _ "Z"
}

/// Section 1.2.
ClassMethod GetEncounter(encounterId As %String, Output status As %Integer) As %DynamicObject
{
    Set encounter = ##class(Wards.Encounter).EncounterIdIdxOpen(encounterId)
    If '$ISOBJECT(encounter) {
        Set status = 404
        Quit {"error": "unknown_encounter"}
    }
    Set status = 200
    Quit encounter.ToJSON()
}

/// Section 1.3.
ClassMethod GetReceipt(key As %String, Output status As %Integer) As %DynamicObject
{
    Set receipt = ##class(Wards.Receipt).OperationKeyIdxOpen(key)
    If '$ISOBJECT(receipt) {
        Set status = 404
        Quit {"error": "no_receipt"}
    }
    Set status = 200
    Quit receipt.ToJSON()
}

/// The fault in force for this operation key: one set for this key, or one set for every operation.
ClassMethod FaultFor(key As %String) As %String
{
    Set mode = $GET(^Wards.Config("fault", "mode"), "off")
    Set faultKey = $GET(^Wards.Config("fault", "key"))
    Quit:mode="off" "off"
    Quit:(faultKey'="")&&(faultKey'=key) "off"
    Quit mode
}

/// Section 1.5. One fault at a time: setting one replaces the last.
ClassMethod SetFault(request As %DynamicObject, Output status As %Integer) As %DynamicObject
{
    Set mode = request.%Get("mode")
    If '$LISTFIND($LISTBUILD("off", "fail_before_accept", "commit_drop_response", "misleading_duplicate_error"), mode) {
        Set status = 422
        Quit {"error": "invalid_request", "detail": "mode must be off, fail_before_accept, commit_drop_response or misleading_duplicate_error"}
    }
    Set ^Wards.Config("fault", "mode") = mode
    Set ^Wards.Config("fault", "key") = $SELECT(mode = "off": "", 1: request.%Get("operation_key"))
    Set status = 200
    Quit ..FaultJSON()
}

ClassMethod GetFault(Output status As %Integer) As %DynamicObject
{
    Set status = 200
    Quit ..FaultJSON()
}

ClassMethod FaultJSON() As %DynamicObject [ Private ]
{
    Set out = {"mode": ($GET(^Wards.Config("fault", "mode"), "off"))}
    Set key = $GET(^Wards.Config("fault", "key"))
    If key = "" {
        Do out.%Set("operation_key", "", "null")
    } Else {
        Do out.%Set("operation_key", key)
    }
    Quit out
}

/// Section 1.7: clears encounters, events, receipts and faults, on a demo instance only.
ClassMethod Reset(Output status As %Integer) As %DynamicObject
{
    If '$GET(^Wards.Config("demo")) {
        Set status = 403
        Quit {"error": "not_a_demo_instance"}
    }
    Do ##class(Wards.Receipt).%KillExtent()
    Do ##class(Wards.Event).%KillExtent()
    Do ##class(Wards.Encounter).%KillExtent()
    Kill ^Wards.Config("fault")
    Set status = 200
    Quit {"reset": true}
}

}
