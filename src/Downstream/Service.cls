/// The downstream system's behaviour, behind <class>Downstream.API</class>. The contract is docs/CONTRACTS.md,
/// section 1. Each method sets the HTTP status in <var>status</var> and returns the JSON body: an empty string for
/// the 504 that <code>commit_drop_response</code> produces.
Class Downstream.Service
{

/// Apply an operation, or rehearse it when <code>dry_run</code> is true (section 1.1). Faults apply to real
/// operations only, never to a rehearsal.
ClassMethod Apply(request As %DynamicObject, Output status As %Integer) As %DynamicObject
{
    Set dryRun = ''request.%Get("dry_run")
    Set key = request.%Get("operation_key")
    Set encounterId = request.%Get("encounter_id")
    If 'dryRun, ..FaultFor(key) = "fail_before_accept" {
        Set status = 503
        Quit {"error": "ward_unavailable"}
    }
    // A slow receiver (v1.32): the request is held, then applied and answered as usual, so a sender whose timeout is
    // shorter gives up on an operation the receiver still applies, and the next message waits behind it
    If 'dryRun, ..FaultFor(key) = "delay_response" Hang +$GET(^Downstream.Config("fault", "seconds"), 12)
    Set problem = ..Validate(request)
    If problem '= "" {
        Quit ..Refuse(dryRun, 422, {"error": "invalid_request", "detail": (problem)}, .status, encounterId)
    }
    Set digest = ..Digest(..Canonical(request))
    Set given = request.%Get("payload_digest")
    If (given '= ""), (given '= digest) {
        Quit ..Refuse(dryRun, 422, {"error": "payload_digest_mismatch"}, .status, encounterId)
    }
    If '..ConditionalWrites(), request.%IsDefined("expected_version"), request.%GetTypeOf("expected_version") '= "null" {
        Quit ..Refuse(dryRun, 422, {"error": "unsupported_precondition"}, .status, encounterId)
    }
    Lock +^Downstream.Lock(encounterId):10
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
    Lock -^Downstream.Lock(encounterId)
    Quit result
}

/// The checks after the request is valid, then the write, with the encounter locked (section 1.1, order of checks).
ClassMethod ApplyLocked(request As %DynamicObject, key As %String, digest As %String, dryRun As %Boolean, Output status As %Integer) As %DynamicObject [ Private ]
{
    Set encounterId = request.%Get("encounter_id")
    Set event = request.%Get("event")
    Set encounter = ##class(Downstream.Encounter).EncounterIdIdxOpen(encounterId)
    // Part of request validity: an encounter never changes its patient
    If $ISOBJECT(encounter) {
        If (encounter.PatientId '= request.%Get("patient_id")) || (encounter.PatientIdAuthority '= request.%Get("patient_id_authority")) {
            Quit ..Refuse(dryRun, 422, {"error": "patient_mismatch", "encounter_id": (encounterId)}, .status, encounterId)
        }
    }
    // The misleading duplicate error set for this key answers whatever the version, and writes nothing
    If 'dryRun, ..FaultFor(key) = "misleading_duplicate_error", $GET(^Downstream.Config("fault", "key")) '= "" {
        Set status = 409
        Quit {"error": "duplicate_message"}
    }
    // A committed receipt for this key answers before any version check
    Set receipt = ##class(Downstream.Receipt).OperationKeyIdxOpen(key)
    If $ISOBJECT(receipt) {
        If receipt.PayloadDigest '= digest {
            Quit ..Refuse(dryRun, 409, {"error": "key_reused_with_different_payload", "operation_key": (key)}, .status, encounterId)
        }
        Set status = 200
        If dryRun {
            Quit ..Rehearsed({"applied": false, "rehearsal": true, "would_apply": false, "reason": "already_committed", "receipt": (receipt.ToJSON())}, ..EncounterJSON(encounterId))
        }
        Set out = {"applied": false, "reason": "already_committed", "receipt": (receipt.ToJSON())}
        Set encounter = ##class(Downstream.Encounter).EncounterIdIdxOpen(receipt.EncounterId)
        Do:$ISOBJECT(encounter) out.%Set("encounter", encounter.ToJSON())
        Quit out
    }
    Set current = $SELECT($ISOBJECT(encounter): encounter.Version, 1: 0)
    If '$ISOBJECT(encounter), event '= "admit" {
        Quit ..Refuse(dryRun, 422, {"error": "unknown_encounter", "encounter_id": (encounterId)}, .status, encounterId)
    }
    Set expected = request.%Get("expected_version")
    If (expected '= ""), (+expected '= current) {
        If 'dryRun, ..FaultFor(key) = "misleading_duplicate_error" {
            Set status = 409
            Quit {"error": "duplicate_message"}
        }
        Quit ..Refuse(dryRun, 409, {"error": "version_conflict", "expected_version": (+expected), "current_version": (current)}, .status, encounterId)
    }
    If $ISOBJECT(encounter), (encounter.State = "discharged") || (event = "admit") {
        Quit ..Refuse(dryRun, 422, {"error": "invalid_transition", "state": (encounter.State), "event": (event)}, .status, encounterId)
    }
    Set now = ..Now()
    Set ward = $SELECT((event = "admit") || (event = "transfer"): request.%Get("ward"), 1: "")
    Set bed = $SELECT((event = "admit") || (event = "transfer"): request.%Get("bed"), 1: "")
    // The beds this operation takes or frees are locked until the write is committed or rolled back, the one it
    // leaves too: a rehearsal's write is visible to other processes until its rollback (section 1.1)
    Set beds = ..Beds(encounter, event, ward, bed)
    For i = 1:1:$LISTLENGTH(beds) {
        Lock +^Downstream.Lock("bed", $LIST($LIST(beds, i), 1), $LIST($LIST(beds, i), 2)):10
        If '$TEST {
            Do ..Unlock(beds, i - 1)
            Set status = 503
            Return {"error": "ward_unavailable", "detail": "another operation holds the bed"}
        }
    }
    Try {
        Set result = ..Place(request, encounter, key, digest, dryRun, current, ward, bed, now, .status)
    } Catch ex {
        TROLLBACK:$TLEVEL 1
        Set status = 500
        Set result = {"error": "internal_error", "detail": (ex.DisplayString())}
    }
    Do ..Unlock(beds)
    If 'dryRun, status = 201, ..FaultFor(key) = "commit_drop_response" {
        // Committed, then the response is lost
        Set status = 504
        Quit ""
    }
    Quit result
}

/// The beds an operation on <var>encounter</var> takes or frees, as a list of (ward, bed) in collation order, so two
/// operations always lock them in the same order: the bed it is placed in, and the bed it leaves.
ClassMethod Beds(encounter As Downstream.Encounter, event As %String, ward As %String, bed As %String) As %List [ Private ]
{
    Set:bed'="" touched(ward, bed) = ""
    If $ISOBJECT(encounter), (event = "transfer") || (event = "discharge"), encounter.Bed '= "" {
        Set touched(encounter.Ward, encounter.Bed) = ""
    }
    Set beds = "", w = ""
    For {
        Set w = $ORDER(touched(w))
        Quit:w=""
        Set b = ""
        For {
            Set b = $ORDER(touched(w, b))
            Quit:b=""
            Set beds = beds _ $LISTBUILD($LISTBUILD(w, b))
        }
    }
    Quit beds
}

/// Releases the first <var>count</var> of <var>beds</var>' locks, all of them by default.
ClassMethod Unlock(beds As %List, count As %Integer = -1) [ Private ]
{
    Set:count<0 count = $LISTLENGTH(beds)
    For i = 1:1:count {
        Lock -^Downstream.Lock("bed", $LIST($LIST(beds, i), 1), $LIST($LIST(beds, i), 2))
    }
}

/// The bed check, then the write, with the encounter and its beds locked.
ClassMethod Place(request As %DynamicObject, encounter As Downstream.Encounter, key As %String, digest As %String, dryRun As %Boolean, current As %Integer, ward As %String, bed As %String, now As %String, Output status As %Integer) As %DynamicObject [ Private ]
{
    Set encounterId = request.%Get("encounter_id")
    Set event = request.%Get("event")
    If bed '= "" {
        // A bed held by another open encounter refuses the placement, in a rehearsal too (section 1.1)
        Set occupied = ..Occupied(ward, bed, encounterId, key)
        If $ISOBJECT(occupied) {
            Set status = 409
            Quit occupied
        }
    }
    // What a rehearsal is checked against, read before anything changes
    Set before = $SELECT(dryRun: ..EncounterJSON(encounterId), 1: "")
    TSTART
    Try {
        If '$ISOBJECT(encounter) {
            Set encounter = ##class(Downstream.Encounter).%New()
            Set encounter.EncounterId = encounterId
            Set encounter.PatientId = request.%Get("patient_id")
            Set encounter.PatientIdAuthority = request.%Get("patient_id_authority")
        }
        If event = "admit" {
            Set encounter.State = "admitted", encounter.Ward = ward, encounter.Bed = bed
        } ElseIf event = "transfer" {
            Set encounter.Ward = ward, encounter.Bed = bed
        } ElseIf event = "discharge" {
            Set encounter.State = "discharged", encounter.Ward = "", encounter.Bed = ""
        }
        Set encounter.Version = current + 1
        Set encounter.UpdatedAt = now
        $$$ThrowOnError(encounter.%Save())
        Set history = ##class(Downstream.Event).%New()
        Set history.EncounterId = encounterId, history.VersionAfter = encounter.Version, history.Event = event
        Set history.Ward = ward, history.Bed = bed, history.EventTime = request.%Get("event_time"), history.AppliedAt = now
        Set history.OperationKey = key
        $$$ThrowOnError(history.%Save())
        Set receipt = ##class(Downstream.Receipt).%New()
        Set receipt.OperationKey = key, receipt.EncounterId = encounterId, receipt.Event = event, receipt.Ward = ward, receipt.Bed = bed
        Set receipt.EventTime = history.EventTime, receipt.AppliedAt = now
        Set receipt.VersionBefore = current, receipt.VersionAfter = encounter.Version
        Set receipt.PayloadDigest = digest, receipt.SourceMessageId = request.%Get("source_message_id")
        Set receipt.Epoch = ..Epoch()
        $$$ThrowOnError(receipt.%Save())
        If dryRun {
            // The rehearsal: everything was validated and written, and is now rolled back
            Set after = encounter.ToJSON()
            TROLLBACK 1
            Set status = 200
            Set result = ..Rehearsed({"applied": false, "rehearsal": true, "would_apply": true}, before, after)
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
    Quit result
}

/// The 409 <code>bed_occupied</code> answer when another admitted encounter holds <var>bed</var> in <var>ward</var>,
/// otherwise an empty string. The encounter itself never conflicts with its own bed. The occupant is named by its
/// encounter id only, never by patient identifiers.
ClassMethod Occupied(ward As %String, bed As %String, encounterId As %String, key As %String) As %DynamicObject [ Private ]
{
    // The index WardBedIdx, read directly: the API's users have no SQL privileges
    Set id = ""
    For {
        Set id = $ORDER(^Downstream.EncounterI("WardBedIdx", ward, bed, id))
        Quit:id=""
        Set occupant = ##class(Downstream.Encounter).%OpenId(id)
        Continue:'$ISOBJECT(occupant)
        Continue:(occupant.EncounterId=encounterId)||(occupant.State'="admitted")||(occupant.Ward'=ward)||(occupant.Bed'=bed)
        Set since = ..BedSince(occupant)
        Set holder = {"encounter_id": (occupant.EncounterId), "since": (since)}
        Do holder.%Set("version", occupant.Version, "number")
        Return {"error": "bed_occupied", "detail": ("Bed " _ ward _ "/" _ bed _ " is occupied by encounter " _ occupant.EncounterId _ " since " _ since), "ward": (ward), "bed": (bed), "occupant": (holder), "operation_key": (key), "applied": false}
    }
    Quit ""
}

/// The event time of the placement that put <var>encounter</var> in its current bed: the oldest of the admissions and
/// transfers into that bed since it last held another place (an update moves nothing).
ClassMethod BedSince(encounter As Downstream.Encounter) As %String [ Private ]
{
    Set since = encounter.UpdatedAt
    For version = encounter.Version:-1:1 {
        Set event = ##class(Downstream.Event).EncounterVersionIdxOpen(encounter.EncounterId, version)
        Quit:'$ISOBJECT(event)
        Continue:event.Event="update"
        Quit:(event.Ward'=encounter.Ward)||(event.Bed'=encounter.Bed)
        Set since = event.EventTime
    }
    Quit since
}

/// A refusal: as itself for a real operation, or for a rehearsal as a result that would not apply.
ClassMethod Refuse(dryRun As %Boolean, httpStatus As %Integer, body As %DynamicObject, Output status As %Integer, encounterId As %String = "") As %DynamicObject [ Private ]
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
    Quit ..Rehearsed(out, ..EncounterJSON(encounterId))
}

/// A rehearsal's result with what it was checked against: the encounter before it (null when the downstream system has
/// never seen it), the encounter as it would be when it would apply, and the epoch.
ClassMethod Rehearsed(out As %DynamicObject, before As %DynamicObject = "", after As %DynamicObject = "") As %DynamicObject [ Private ]
{
    If $ISOBJECT(before) {
        Do out.%Set("encounter_before", before)
    } Else {
        Do out.%Set("encounter_before", "", "null")
    }
    Do:$ISOBJECT(after) out.%Set("encounter_after", after)
    Do out.%Set("epoch", ..Epoch(), "number")
    Quit out
}

/// The encounter as the API returns it, or an empty string when the downstream system has never seen it.
ClassMethod EncounterJSON(encounterId) As %DynamicObject [ Private ]
{
    Quit:$ISOBJECT(encounterId)||(encounterId="") ""
    Set encounter = ##class(Downstream.Encounter).EncounterIdIdxOpen(encounterId)
    Quit $SELECT($ISOBJECT(encounter): encounter.ToJSON(), 1: "")
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
    // A bed is optional, and only for a placement (section 1.1)
    If request.%IsDefined("bed"), request.%GetTypeOf("bed") '= "null" {
        If (event '= "admit") && (event '= "transfer") {
            Return "bed must be null for " _ event
        }
        If (request.%GetTypeOf("bed") '= "string") || (request.%Get("bed") = "") || ($LENGTH(request.%Get("bed")) > 64) {
            Return "bed must be null or a bed name of 1 to 64 characters"
        }
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

/// The canonical payload (section 1.6): these keys in this order, strings as given, null for no ward. The bed is not
/// part of it, so a ward-level operation's digest is what it was before beds.
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
    Set encounter = ##class(Downstream.Encounter).EncounterIdIdxOpen(encounterId)
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
    If ..FaultFor(key) = "receipt_lookup_unavailable" {
        Set status = 503
        Quit {"error": "ward_unavailable"}
    }
    Set receipt = ##class(Downstream.Receipt).OperationKeyIdxOpen(key)
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
    Set mode = $GET(^Downstream.Config("fault", "mode"), "off")
    Set faultKey = $GET(^Downstream.Config("fault", "key"))
    Quit:mode="off" "off"
    Quit:(faultKey'="")&&(faultKey'=key) "off"
    Quit mode
}

/// Section 1.5. One fault at a time: setting one replaces the last.
ClassMethod SetFault(request As %DynamicObject, Output status As %Integer) As %DynamicObject
{
    Set mode = request.%Get("mode")
    If '$LISTFIND($LISTBUILD("off", "fail_before_accept", "commit_drop_response", "misleading_duplicate_error", "receipt_lookup_unavailable", "delay_response"), mode) {
        Set status = 422
        Quit {"error": "invalid_request", "detail": "mode must be off, fail_before_accept, commit_drop_response, misleading_duplicate_error, receipt_lookup_unavailable or delay_response"}
    }
    // delay_response holds each real operation for seconds (1 to 60, 12 when not given)
    Set seconds = request.%Get("seconds")
    If mode = "delay_response", seconds '= "", (seconds '= +seconds) || (seconds \ 1 '= seconds) || (seconds < 1) || (seconds > 60) {
        Set status = 422
        Quit {"error": "invalid_request", "detail": "seconds must be a whole number from 1 to 60"}
    }
    Set ^Downstream.Config("fault", "mode") = mode
    Set ^Downstream.Config("fault", "key") = $SELECT(mode = "off": "", 1: request.%Get("operation_key"))
    If mode = "delay_response" { Set ^Downstream.Config("fault", "seconds") = $SELECT(seconds = "": 12, 1: +seconds) } Else { Kill ^Downstream.Config("fault", "seconds") }
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
    Set out = {"mode": ($GET(^Downstream.Config("fault", "mode"), "off"))}
    If $DATA(^Downstream.Config("fault", "seconds")) Set out.seconds = +^Downstream.Config("fault", "seconds")
    Set key = $GET(^Downstream.Config("fault", "key"))
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
    If '$GET(^Downstream.Config("demo")) {
        Set status = 403
        Quit {"error": "not_a_demo_instance"}
    }
    Do ##class(Downstream.Receipt).%KillExtent()
    Do ##class(Downstream.Event).%KillExtent()
    Do ##class(Downstream.Encounter).%KillExtent()
    Kill ^Downstream.Config("fault")
    Kill ^Downstream.Config("capabilities", "conditional_writes")
    Set ^Downstream.Config("epoch") = ..Epoch() + 1
    Set status = 200
    Quit {"reset": true, "epoch": (..Epoch())}
}

/// The downstream system's epoch: it increases at every reset, so versions from different epochs never compare.
ClassMethod Epoch() As %Integer
{
    Quit +$GET(^Downstream.Config("epoch"), 1)
}

/// Whether the downstream system takes conditional writes (<code>expected_version</code>). On by default; a demo
/// can switch it off, and a reset switches it back on.
ClassMethod ConditionalWrites() As %Boolean
{
    Quit ''$GET(^Downstream.Config("capabilities", "conditional_writes"), 1)
}

/// What the downstream system guarantees (CONTRACTS 1.8): the capability profile behind the connector passport.
ClassMethod Capabilities() As %DynamicObject
{
    Set out = {}
    Do out.%Set("conditional_writes", ..ConditionalWrites(), "boolean")
    Do out.%Set("receipts", 1, "boolean")
    Do out.%Set("receipt_retention", "unbounded")
    Do out.%Set("history", 1, "boolean")
    Do out.%Set("idempotency", "by operation key and payload digest")
    Do out.%Set("dry_run", 1, "boolean")
    Do out.%Set("epoch", ..Epoch(), "number")
    Set check = $GET(^Downstream.Config("contract_check"))
    If check = "" {
        Do out.%Set("last_contract_check", "", "null")
    } Else {
        Do out.%Set("last_contract_check", {"at": ($LISTGET(check, 1)), "result": ($LISTGET(check, 2))})
    }
    Quit out
}

ClassMethod GetCapabilities(Output status As %Integer) As %DynamicObject
{
    Set status = 200
    Quit ..Capabilities()
}

/// The demo switch for conditional writes (CONTRACTS 1.8, demo instances only), and the record of the last contract
/// check, which the test tools write.
/// Accepts <code>conditional_writes</code> (a boolean) and <code>last_contract_check</code> (<code>at</code>,
/// <code>result</code>); anything else is refused.
ClassMethod SetCapabilities(request As %DynamicObject, Output status As %Integer) As %DynamicObject
{
    If '$GET(^Downstream.Config("demo")) {
        Set status = 403
        Quit {"error": "not_a_demo_instance"}
    }
    Set iter = request.%GetIterator()
    While iter.%GetNext(.name, .value) {
        If '$LISTFIND($LISTBUILD("conditional_writes", "last_contract_check"), name) {
            Set status = 422
            Return {"error": "invalid_request", "detail": ("unknown capability field " _ name)}
        }
    }
    If request.%IsDefined("conditional_writes"), request.%GetTypeOf("conditional_writes") '= "boolean" {
        Set status = 422
        Quit {"error": "invalid_request", "detail": "conditional_writes must be true or false"}
    }
    If request.%IsDefined("last_contract_check") {
        Set check = request."last_contract_check"
        If (request.%GetTypeOf("last_contract_check") '= "object") || (check.at = "") || (check.result = "") {
            Set status = 422
            Quit {"error": "invalid_request", "detail": "last_contract_check needs at and result"}
        }
    }
    // Everything is checked first, so a refused request changes nothing
    If request.%IsDefined("conditional_writes") {
        Set ^Downstream.Config("capabilities", "conditional_writes") = request."conditional_writes"
    }
    If request.%IsDefined("last_contract_check") {
        Set ^Downstream.Config("contract_check") = $LISTBUILD(check.at, check.result)
    }
    Set status = 200
    Quit ..Capabilities()
}

}
