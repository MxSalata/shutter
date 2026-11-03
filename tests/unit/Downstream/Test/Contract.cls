/// The downstream system's contract (docs/CONTRACTS.md, section 1), through <class>Downstream.Service</class>. Each test
/// uses its own encounter, so other data is left alone, and <method>OnAfterAllTests</method> removes what the tests made.
/// Faults are set for the test's own operation key and the previous setting is put back. Don't run these during a demo.
Class Downstream.Test.Contract Extends %UnitTest.TestCase
{

/// Every encounter id these tests create starts with this.
Property Prefix As %String [ InitialExpression = {"ENC-UT-" _ $TRANSLATE($ZTIMESTAMP, ",.", "")} ];

Method Encounter(n As %Integer) As %String
{
    Quit ..Prefix _ "-" _ n
}

/// A request for <var>event</var> on <var>encounter</var>; <var>ward</var> empty for none.
Method Request(encounter As %String, event As %String, ward As %String, time As %String) As %DynamicObject
{
    Set request = {"operation_key": ("PAS^HOSP^MRN-UT^" _ encounter _ "^" _ event _ "^" _ time), "encounter_id": (encounter), "patient_id": "MRN-UT", "patient_id_authority": "HOSP", "event": (event)}
    If ward = "" {
        Do request.%Set("ward", "", "null")
    } Else {
        Do request.%Set("ward", ward)
    }
    Do request.%Set("event_time", time)
    Do request.%Set("source_system", "PAS")
    Do request.%Set("source_message_id", "MSG-UT")
    Quit request
}

Method Admit(encounter As %String) As %DynamicObject
{
    Quit ##class(Downstream.Service).Apply(..Request(encounter, "admit", "WARD-A", "2026-10-15T09:00:00Z"), .status)
}

Method TestAdmitAndTransfer()
{
    Set encounter = ..Encounter(1)
    Set body = ##class(Downstream.Service).Apply(..Request(encounter, "admit", "WARD-A", "2026-10-15T09:00:00Z"), .status)
    Do $$$AssertEquals(status, 201, "the admit applies")
    Do $$$AssertEquals(body.encounter.version, 1, "at version 1")
    Set body = ##class(Downstream.Service).Apply(..Request(encounter, "transfer", "WARD-B", "2026-10-15T09:20:00Z"), .status)
    Do $$$AssertEquals(status, 201, "the transfer applies")
    Do $$$AssertEquals(body.encounter.ward, "WARD-B", "the patient is in Ward B")
    Do $$$AssertEquals(body.receipt."version_before", 1, "the receipt has the version before")
    Do $$$AssertEquals(body.receipt."version_after", 2, "and after")
    Set read = ##class(Downstream.Service).GetEncounter(encounter, .status)
    Do $$$AssertEquals(read.history.%Size(), 2, "the history has two events")
}

Method TestRepeatedKeyReturnsPriorReceipt()
{
    Set encounter = ..Encounter(2)
    Do ..Admit(encounter)
    Set transfer = ..Request(encounter, "transfer", "WARD-B", "2026-10-15T09:20:00Z")
    Set first = ##class(Downstream.Service).Apply(transfer, .status)
    Do $$$AssertEquals(status, 201, "the transfer applies once")
    Do transfer.%Set("source_message_id", "MSG-UT-RESENT")
    Set again = ##class(Downstream.Service).Apply(transfer, .status)
    Do $$$AssertEquals(status, 200, "the same operation from another message answers 200")
    Do $$$AssertEquals(again.reason, "already_committed", "as already committed")
    Do $$$AssertEquals(again.receipt."applied_at", first.receipt."applied_at", "with the earlier receipt")
    Do $$$AssertEquals(again.encounter.version, 2, "and nothing more applied")
}

Method TestChangedPayloadUnderSameKeyRefused()
{
    Set encounter = ..Encounter(3)
    Do ..Admit(encounter)
    Set transfer = ..Request(encounter, "transfer", "WARD-B", "2026-10-15T09:20:00Z")
    Do ##class(Downstream.Service).Apply(transfer, .status)
    Do transfer.%Set("ward", "WARD-D")
    Set body = ##class(Downstream.Service).Apply(transfer, .status)
    Do $$$AssertEquals(status, 409, "a key reused for another payload is refused")
    Do $$$AssertEquals(body.error, "key_reused_with_different_payload", "as key_reused_with_different_payload")
    Set read = ##class(Downstream.Service).GetEncounter(encounter, .status)
    Do $$$AssertEquals(read.ward, "WARD-B", "the patient stays in Ward B")
}

Method TestExpectedVersionMismatchRefused()
{
    Set encounter = ..Encounter(4)
    Do ..Admit(encounter)
    Set transfer = ..Request(encounter, "transfer", "WARD-B", "2026-10-15T09:20:00Z")
    Do transfer.%Set("expected_version", 5)
    Set body = ##class(Downstream.Service).Apply(transfer, .status)
    Do $$$AssertEquals(status, 409, "a stale expected version is refused")
    Do $$$AssertEquals(body.error, "version_conflict", "as version_conflict")
    Do $$$AssertEquals(body."current_version", 1, "naming the current version")
    Do ##class(Downstream.Service).GetReceipt(transfer."operation_key", .status)
    Do $$$AssertEquals(status, 404, "and no receipt was stored")
}

Method TestTransferAfterDischargeRefused()
{
    Set encounter = ..Encounter(5)
    Do ..Admit(encounter)
    Set body = ##class(Downstream.Service).Apply(..Request(encounter, "discharge", "", "2026-10-15T11:00:00Z"), .status)
    Do $$$AssertEquals(status, 201, "the discharge applies")
    Do $$$AssertEquals(body.encounter.state, "discharged", "the encounter is discharged")
    Set body = ##class(Downstream.Service).Apply(..Request(encounter, "transfer", "WARD-B", "2026-10-15T09:20:00Z"), .status)
    Do $$$AssertEquals(status, 422, "a transfer after the discharge is refused")
    Do $$$AssertEquals(body.error, "invalid_transition", "as invalid_transition")
    Do $$$AssertEquals(body.state, "discharged", "naming the state")
}

Method TestDryRunChangesNothing()
{
    Set encounter = ..Encounter(6)
    Do ..Admit(encounter)
    Set transfer = ..Request(encounter, "transfer", "WARD-B", "2026-10-15T09:20:00Z")
    Do transfer.%Set("expected_version", 1)
    Do transfer.%Set("dry_run", 1, "boolean")
    Set body = ##class(Downstream.Service).Apply(transfer, .status)
    Do $$$AssertEquals(status, 200, "a rehearsal answers 200")
    Do $$$AssertTrue(body."would_apply", "it would apply")
    Do $$$AssertEquals(body."encounter_after".ward, "WARD-B", "with the patient in Ward B afterwards")
    Do $$$AssertEquals(body."encounter_before".ward, "WARD-A", "checked against the patient in Ward A")
    Do $$$AssertEquals(body."encounter_before".version, 1, "at version 1")
    Do $$$AssertEquals(body."encounter_before".history.%Size(), 1, "with the admit in its history")
    Do $$$AssertEquals(body.epoch, ##class(Downstream.Service).Epoch(), "in the current epoch")
    Set read = ##class(Downstream.Service).GetEncounter(encounter, .status)
    Do $$$AssertEquals(read.ward, "WARD-A", "but the patient is still in Ward A")
    Do $$$AssertEquals(read.version, 1, "at version 1")
    Do $$$AssertEquals(read.history.%Size(), 1, "with one event")
    Do ##class(Downstream.Service).GetReceipt(transfer."operation_key", .status)
    Do $$$AssertEquals(status, 404, "and no receipt")
}

Method TestDryRunReportsRefusal()
{
    Set encounter = ..Encounter(7)
    Do ..Admit(encounter)
    Set transfer = ..Request(encounter, "transfer", "WARD-B", "2026-10-15T09:20:00Z")
    Do transfer.%Set("expected_version", 3)
    Do transfer.%Set("dry_run", 1, "boolean")
    Set body = ##class(Downstream.Service).Apply(transfer, .status)
    Do $$$AssertEquals(status, 200, "a rehearsal that would fail still answers 200")
    Do $$$AssertTrue('body."would_apply", "it would not apply")
    Do $$$AssertEquals(body.reason, "version_conflict", "because of a version conflict")
    Do $$$AssertEquals(body."encounter_before".version, 1, "and says what it was checked against")
    Do $$$AssertEquals(body.epoch, ##class(Downstream.Service).Epoch(), "in the current epoch")
}

Method TestDryRunOfFirstAdmit()
{
    Set admit = ..Request(..Encounter(19), "admit", "WARD-A", "2026-10-15T09:00:00Z")
    Do admit.%Set("dry_run", 1, "boolean")
    Set body = ##class(Downstream.Service).Apply(admit, .status)
    Do $$$AssertEquals(status, 200, "a rehearsed admit answers 200")
    Do $$$AssertTrue(body."would_apply", "it would apply")
    Do $$$AssertEquals(body."encounter_after".history.%Size(), 1, "with the admit in the history afterwards")
    Do $$$AssertEquals(body.%GetTypeOf("encounter_before"), "null", "and no encounter before it")
}

Method TestUnknownEncounterRefused()
{
    Set body = ##class(Downstream.Service).Apply(..Request(..Encounter(8), "transfer", "WARD-B", "2026-10-15T09:20:00Z"), .status)
    Do $$$AssertEquals(status, 422, "a transfer for an encounter never admitted is refused")
    Do $$$AssertEquals(body.error, "unknown_encounter", "as unknown_encounter")
}

Method TestInvalidRequestRefused()
{
    Set request = ..Request(..Encounter(9), "discharge", "WARD-A", "2026-10-15T11:00:00Z")
    Set body = ##class(Downstream.Service).Apply(request, .status)
    Do $$$AssertEquals(status, 422, "a discharge with a ward is refused")
    Do $$$AssertEquals(body.error, "invalid_request", "as invalid_request")
    Set request = ..Request(..Encounter(9), "admit", "WARD-A", "15/10/2026 09:00")
    Set body = ##class(Downstream.Service).Apply(request, .status)
    Do $$$AssertEquals(body.error, "invalid_request", "and so is a time that isn't ISO 8601 UTC")
}

Method TestFailBeforeAcceptWritesNothing()
{
    Set encounter = ..Encounter(10)
    Do ..Admit(encounter)
    Set transfer = ..Request(encounter, "transfer", "WARD-B", "2026-10-15T09:20:00Z")
    Set saved = ##class(Downstream.Service).GetFault(.ignore)
    Do ##class(Downstream.Service).SetFault({"mode": "fail_before_accept", "operation_key": (transfer."operation_key")}, .ignore)
    Set body = ##class(Downstream.Service).Apply(transfer, .status)
    Do ##class(Downstream.Service).SetFault(saved, .ignore)
    Do $$$AssertEquals(status, 503, "the downstream system is unavailable")
    Do $$$AssertEquals(body.error, "ward_unavailable", "as ward_unavailable")
    Do ##class(Downstream.Service).GetReceipt(transfer."operation_key", .status)
    Do $$$AssertEquals(status, 404, "and nothing was committed")
}

Method TestCommitDropResponseCommits()
{
    Set encounter = ..Encounter(11)
    Do ..Admit(encounter)
    Set transfer = ..Request(encounter, "transfer", "WARD-B", "2026-10-15T09:20:00Z")
    Set saved = ##class(Downstream.Service).GetFault(.ignore)
    Do ##class(Downstream.Service).SetFault({"mode": "commit_drop_response", "operation_key": (transfer."operation_key")}, .ignore)
    Set body = ##class(Downstream.Service).Apply(transfer, .status)
    Do ##class(Downstream.Service).SetFault(saved, .ignore)
    Do $$$AssertEquals(status, 504, "the response is lost")
    Do $$$AssertEquals(body, "", "with no body")
    Do ##class(Downstream.Service).GetReceipt(transfer."operation_key", .status)
    Do $$$AssertEquals(status, 200, "but the operation was committed")
    Set again = ##class(Downstream.Service).Apply(transfer, .status)
    Do $$$AssertEquals(again.reason, "already_committed", "and a retry finds the receipt")
}

Method TestDelayResponseHoldsThenApplies()
{
    Set encounter = ..Encounter(91)
    Do ..Admit(encounter)
    Set transfer = ..Request(encounter, "transfer", "WARD-B", "2026-10-15T09:20:00Z")
    Set saved = ##class(Downstream.Service).GetFault(.ignore)
    Set fault = ##class(Downstream.Service).SetFault({"mode": "delay_response", "operation_key": (transfer."operation_key"), "seconds": 61}, .status)
    Do $$$AssertEquals(status, 422, "a delay over 60 seconds is refused")
    Set fault = ##class(Downstream.Service).SetFault({"mode": "delay_response", "operation_key": (transfer."operation_key"), "seconds": 1}, .ignore)
    Do $$$AssertEquals(fault.seconds, 1, "the delay is reported with the fault")
    Set start = $ZHOROLOG
    Set body = ##class(Downstream.Service).Apply(transfer, .status)
    Set held = $ZHOROLOG - start
    Do ##class(Downstream.Service).SetFault(saved, .ignore)
    Do $$$AssertTrue(held >= 1, "the request is held for the delay")
    Do $$$AssertEquals(status, 201, "then applied and answered as usual")
    Do ##class(Downstream.Service).GetReceipt(transfer."operation_key", .status)
    Do $$$AssertEquals(status, 200, "with a receipt")
}

Method TestMisleadingDuplicateError()
{
    Set encounter = ..Encounter(12)
    Do ..Admit(encounter)
    Set transfer = ..Request(encounter, "transfer", "WARD-B", "2026-10-15T09:20:00Z")
    Do transfer.%Set("expected_version", 7)
    Set saved = ##class(Downstream.Service).GetFault(.ignore)
    Do ##class(Downstream.Service).SetFault({"mode": "misleading_duplicate_error", "operation_key": (transfer."operation_key")}, .ignore)
    Set body = ##class(Downstream.Service).Apply(transfer, .status)
    Do ##class(Downstream.Service).SetFault(saved, .ignore)
    Do $$$AssertEquals(status, 409, "a version mismatch answers 409")
    Do $$$AssertEquals(body.error, "duplicate_message", "with the misleading duplicate_message")
    Set read = ##class(Downstream.Service).GetEncounter(encounter, .status)
    Do $$$AssertEquals(read.version, 1, "and nothing was written")
}

Method TestMisleadingDuplicateWithoutVersion()
{
    Set encounter = ..Encounter(13)
    Do ..Admit(encounter)
    Set transfer = ..Request(encounter, "transfer", "WARD-B", "2026-10-15T09:20:00Z")
    Set saved = ##class(Downstream.Service).GetFault(.ignore)
    Do ##class(Downstream.Service).SetFault({"mode": "misleading_duplicate_error", "operation_key": (transfer."operation_key")}, .ignore)
    Set body = ##class(Downstream.Service).Apply(transfer, .status)
    Do ##class(Downstream.Service).SetFault(saved, .ignore)
    Do $$$AssertEquals(status, 409, "with the fault set for its key, routine traffic with no version answers 409")
    Do $$$AssertEquals(body.error, "duplicate_message", "as duplicate_message")
    Do ##class(Downstream.Service).GetReceipt(transfer."operation_key", .status)
    Do $$$AssertEquals(status, 404, "and no receipt exists")
}

Method TestPatientMismatchRefused()
{
    Set encounter = ..Encounter(14)
    Do ..Admit(encounter)
    Set transfer = ..Request(encounter, "transfer", "WARD-B", "2026-10-15T09:20:00Z")
    Do transfer.%Set("patient_id", "MRN-SOMEONE-ELSE")
    Set body = ##class(Downstream.Service).Apply(transfer, .status)
    Do $$$AssertEquals(status, 422, "a transfer naming another patient is refused")
    Do $$$AssertEquals(body.error, "patient_mismatch", "as patient_mismatch")
    Do $$$AssertEquals(body."encounter_id", encounter, "naming the encounter")
}

Method TestPayloadDigestMismatchRefused()
{
    Set transfer = ..Request(..Encounter(15), "admit", "WARD-A", "2026-10-15T09:00:00Z")
    Do transfer.%Set("payload_digest", "sha256:0000000000000000000000000000000000000000000000000000000000000000")
    Set body = ##class(Downstream.Service).Apply(transfer, .status)
    Do $$$AssertEquals(status, 422, "a digest that differs from the downstream system's is refused")
    Do $$$AssertEquals(body.error, "payload_digest_mismatch", "as payload_digest_mismatch")
    Do transfer.%Set("payload_digest", ##class(Downstream.Service).Digest(##class(Downstream.Service).Canonical(transfer)))
    Set body = ##class(Downstream.Service).Apply(transfer, .status)
    Do $$$AssertEquals(status, 201, "and the right digest is accepted")
}

Method TestCapabilities()
{
    Set caps = ##class(Downstream.Service).GetCapabilities(.status)
    Do $$$AssertEquals(status, 200, "the capability profile answers 200")
    Do $$$AssertTrue(caps.receipts, "receipts are offered")
    Do $$$AssertEquals(caps."receipt_retention", "unbounded", "kept without limit")
    Do $$$AssertEquals(caps.idempotency, "by operation key and payload digest", "idempotent by operation key and digest")
    Do $$$AssertTrue(caps."dry_run", "dry runs are offered")
    Do $$$AssertTrue(caps.epoch >= 1, "the epoch is a positive number")
}

Method TestConditionalWritesOff()
{
    Set encounter = ..Encounter(16)
    Do ..Admit(encounter)
    Set before = ##class(Downstream.Service).ConditionalWrites()
    Do ##class(Downstream.Service).SetCapabilities({"conditional_writes": false}, .ignore)
    Set transfer = ..Request(encounter, "transfer", "WARD-B", "2026-10-15T09:20:00Z")
    Do transfer.%Set("expected_version", 1)
    Set refused = ##class(Downstream.Service).Apply(transfer, .refusedStatus)
    Do transfer.%Set("dry_run", 1, "boolean")
    Set rehearsal = ##class(Downstream.Service).Apply(transfer, .rehearsalStatus)
    Do transfer.%Remove("expected_version")
    Do transfer.%Remove("dry_run")
    Set routine = ##class(Downstream.Service).Apply(transfer, .routineStatus)
    Set restore = {}
    Do restore.%Set("conditional_writes", before, "boolean")
    Do ##class(Downstream.Service).SetCapabilities(restore, .ignore)
    Do $$$AssertEquals(refusedStatus, 422, "with conditional writes off, an expected version is refused")
    Do $$$AssertEquals(refused.error, "unsupported_precondition", "as unsupported_precondition")
    Do $$$AssertEquals(rehearsal.reason, "unsupported_precondition", "and a rehearsal reports why it would not apply")
    Do $$$AssertEquals(routineStatus, 201, "while routine traffic without a version still applies")
}

Method TestEpochInReadsAndReceipts()
{
    Set encounter = ..Encounter(17)
    Set body = ..Admit(encounter)
    Set epoch = ##class(Downstream.Service).Epoch()
    Do $$$AssertEquals(body.receipt.epoch, epoch, "the receipt carries the epoch it was committed in")
    Do $$$AssertEquals(body.encounter.epoch, epoch, "and the encounter read carries the current epoch")
    Do $$$AssertEquals(##class(Downstream.Service).GetCapabilities(.status).epoch, epoch, "as does the capability profile")
}

Method TestReceiptLookupUnavailable()
{
    Set encounter = ..Encounter(18)
    Do ..Admit(encounter)
    Set transfer = ..Request(encounter, "transfer", "WARD-B", "2026-10-15T09:20:00Z")
    Do ##class(Downstream.Service).Apply(transfer, .status)
    Set saved = ##class(Downstream.Service).GetFault(.ignore)
    Do ##class(Downstream.Service).SetFault({"mode": "receipt_lookup_unavailable", "operation_key": (transfer."operation_key")}, .ignore)
    Set body = ##class(Downstream.Service).GetReceipt(transfer."operation_key", .lookupStatus)
    Do ##class(Downstream.Service).SetFault(saved, .ignore)
    Do $$$AssertEquals(lookupStatus, 503, "the receipt lookup is unavailable")
    Do $$$AssertEquals(body.error, "ward_unavailable", "as ward_unavailable")
    Set read = ##class(Downstream.Service).GetEncounter(encounter, .status)
    Do $$$AssertEquals(read.ward, "WARD-B", "while the transfer stands committed")
    Do ##class(Downstream.Service).GetReceipt(transfer."operation_key", .status)
    Do $$$AssertEquals(status, 200, "and the receipt is there again once the fault is off")
}

Method TestLastContractCheckRecorded()
{
    Set saved = $GET(^Downstream.Config("contract_check"))
    Set caps = ##class(Downstream.Service).SetCapabilities({"last_contract_check": {"at": "2026-10-15T15:40:00Z", "result": "a test value"}}, .status)
    If saved = "" { Kill ^Downstream.Config("contract_check") } Else { Set ^Downstream.Config("contract_check") = saved }
    Do $$$AssertEquals(status, 200, "the last contract check is recorded")
    Do $$$AssertEquals(caps."last_contract_check".result, "a test value", "and shown in the profile")
    Set body = ##class(Downstream.Service).SetCapabilities({"conditional_writes": "no"}, .status)
    Do $$$AssertEquals(status, 422, "a switch that isn't true or false is refused")
    Set body = ##class(Downstream.Service).SetCapabilities({"anything_else": true}, .status)
    Do $$$AssertEquals(status, 422, "and so is an unknown field")
}

Method TestCanonicalDigest()
{
    Set transfer = {"operation_key": "PAS^HOSP^MRN1001^ENC-1001^transfer^2026-10-15T09:20:00Z", "encounter_id": "ENC-1001", "patient_id": "MRN1001", "patient_id_authority": "HOSP", "event": "transfer", "ward": "WARD-B", "event_time": "2026-10-15T09:20:00Z", "source_system": "PAS", "source_message_id": "MSG00002", "expected_version": 1}
    Do $$$AssertEquals(##class(Downstream.Service).Digest(##class(Downstream.Service).Canonical(transfer)), "sha256:56896f1ed42d79e0acee7837e6d552282b8837601853405a4b15d60d655fddf0", "the transfer's digest matches the reference value")
    Set discharge = {"operation_key": "PAS^HOSP^MRN1001^ENC-1001^discharge^2026-10-15T11:00:00Z", "encounter_id": "ENC-1001", "patient_id": "MRN1001", "patient_id_authority": "HOSP", "event": "discharge", "ward": null, "event_time": "2026-10-15T11:00:00Z", "source_system": "PAS"}
    Do $$$AssertEquals(##class(Downstream.Service).Digest(##class(Downstream.Service).Canonical(discharge)), "sha256:1e254eda9639a80f72f3d0c0a4762c2611642f597292210b6d03acb468d8f913", "a null ward is part of the canonical form")
}

Method TestResetRefusedOutsideDemo()
{
    Set demo = $GET(^Downstream.Config("demo"))
    Kill ^Downstream.Config("demo")
    Set body = ##class(Downstream.Service).Reset(.status)
    Set:demo'="" ^Downstream.Config("demo") = demo
    Do $$$AssertEquals(status, 403, "a reset is refused unless the instance is a demo")
    Do $$$AssertEquals(body.error, "not_a_demo_instance", "as not_a_demo_instance")
}

/// <var>method</var> <var>path</var> of the web application, called over HTTP on this instance's own web server as the
/// production's client would call it: as the user of the <code>DownstreamAPI</code> credential (downstream-client, which
/// holds Downstream_API and Shutter_DownstreamClient and not Downstream_Admin), with an empty JSON object as the body of
/// a POST. Returns the HTTP status, or "" with the reason in <var>skip</var> when the call could not be made (no
/// credential, as on a site install; no web server port; no answer), so the caller can skip rather than fail.
ClassMethod AsClient(method As %String, path As %String, Output skip As %String) As %String
{
    Set skip = "", status = ""
    Try {
        Set sc = ##class(Ens.Config.Credentials).GetCredentialsObj(.cred, $CLASSNAME(), "Ens.Config.Credentials", "DownstreamAPI")
        If $$$ISERR(sc) || '$ISOBJECT($GET(cred)) Set skip = "the DownstreamAPI credential is not on this instance" Quit
        Do ##class(%RoutineMgr).GetWebServerPort(.port)
        If +$GET(port) = 0 Set skip = "this instance has no web server port" Quit
        Set http = ##class(%Net.HttpRequest).%New()
        Set http.Server = "127.0.0.1", http.Port = port, http.Timeout = 30
        Set http.Username = cred.Username, http.Password = cred.Password
        Set http.ContentType = "application/json"
        If method = "POST" Do http.EntityBody.Write("{}")
        Set sc = http.Send(method, "/downstream/api" _ path)
        If $$$ISERR(sc) || '$ISOBJECT(http.HttpResponse) Set skip = "no answer from the web server: " _ $SYSTEM.Status.GetErrorText(sc) Quit
        Set status = +http.HttpResponse.StatusCode
    } Catch ex {
        Set skip = ex.DisplayString()
    }
    Quit status
}

/// The demo controls (1.5, 1.7, 1.8) refuse the production's client, which holds the web application's resource
/// alone: Downstream_Admin is required, and nothing is changed before the refusal; the client's reads still answer.
Method TestControlsRefuseTheClient()
{
    Set saved = ##class(Downstream.Service).GetFault(.ignore)
    Set epoch = ##class(Downstream.Service).Epoch()
    Set status = ..AsClient("GET", "/faults", .skip)
    If status = "" {
        Do $$$AssertSkipped("the controls are not checked as the client: " _ skip)
        Quit
    }
    Do $$$AssertEquals(status, 200, "the client reads the fault setting with Downstream_API alone")
    For path = "/faults", "/reset", "/capabilities" {
        Do $$$AssertEquals(..AsClient("POST", path, .skip), 403, "POST " _ path _ " refuses the client, which holds Downstream_API alone" _ $SELECT(skip = "": "", 1: ": " _ skip))
    }
    Do $$$AssertEquals(##class(Downstream.Service).Epoch(), epoch, "no reset happened")
    Do $$$AssertEquals(##class(Downstream.Service).GetFault(.ignore).%ToJSON(), saved.%ToJSON(), "and the fault setting stands")
    Do $$$AssertTrue($SYSTEM.Security.Check("Downstream_Admin", "USE"), "the test's own user holds Downstream_Admin, as an administrator does")
}

/// A bed name of this run's own, so a bed held by other data never answers these tests.
Method Bed(n As %Integer) As %String
{
    Quit "B" _ n _ "-" _ $PIECE(..Prefix, "-", 3)
}

/// <method>Request</method> for a placement into <var>bed</var> (empty for a ward-level placement).
Method Place(encounter As %String, event As %String, ward As %String, bed As %String, time As %String) As %DynamicObject
{
    Set request = ..Request(encounter, event, ward, time)
    Do:bed'="" request.%Set("bed", bed)
    Quit request
}

Method TestBedOccupiedRefused()
{
    Set occupant = ..Encounter(20), mover = ..Encounter(21), bed = ..Bed(1)
    Do ##class(Downstream.Service).Apply(..Place(occupant, "admit", "WARD-B", bed, "2026-10-15T08:10:00Z"), .status)
    Do $$$AssertEquals(status, 201, "the first patient is admitted to the bed")
    Do ..Admit(mover)
    Set transfer = ..Place(mover, "transfer", "WARD-B", bed, "2026-10-15T09:20:00Z")
    Set expected = {"error": "bed_occupied", "detail": ("Bed WARD-B/" _ bed _ " is occupied by encounter " _ occupant _ " since 2026-10-15T08:10:00Z"), "ward": "WARD-B", "bed": (bed), "occupant": {"encounter_id": (occupant), "since": "2026-10-15T08:10:00Z", "version": 1}, "operation_key": (transfer."operation_key"), "applied": false}
    Set body = ##class(Downstream.Service).Apply(transfer, .status)
    Do $$$AssertEquals(status, 409, "a transfer into a bed another encounter holds is refused")
    Do $$$AssertEquals(body.%ToJSON(), expected.%ToJSON(), "as bed_occupied, naming the occupant by its encounter only")
    Do transfer.%Set("expected_version", 1)
    Do transfer.%Set("dry_run", 1, "boolean")
    Set rehearsal = ##class(Downstream.Service).Apply(transfer, .status)
    Do $$$AssertEquals(status, 409, "a rehearsal of it is refused the same way")
    Do $$$AssertEquals(rehearsal.%ToJSON(), expected.%ToJSON(), "with the same body")
    Set read = ##class(Downstream.Service).GetEncounter(mover, .status)
    Do $$$AssertEquals(read.version, 1, "the patient's version did not move")
    Do $$$AssertEquals(read.ward, "WARD-A", "the patient is still in Ward A")
    Do $$$AssertEquals(read.history.%Size(), 1, "with only the admit in the history")
    Do ##class(Downstream.Service).GetReceipt(transfer."operation_key", .status)
    Do $$$AssertEquals(status, 404, "and no receipt was stored")
    Set read = ##class(Downstream.Service).GetEncounter(occupant, .status)
    Do $$$AssertEquals(read.bed, bed, "the occupant keeps the bed")
}

Method TestAdmitIntoOccupiedBedRefused()
{
    Set occupant = ..Encounter(22), bed = ..Bed(2)
    Do ##class(Downstream.Service).Apply(..Place(occupant, "admit", "WARD-B", bed, "2026-10-15T08:10:00Z"), .status)
    Do ##class(Downstream.Service).Apply(..Place(occupant, "update", "", "", "2026-10-15T08:30:00Z"), .status)
    Set admit = ..Place(..Encounter(23), "admit", "WARD-B", bed, "2026-10-15T09:00:00Z")
    Set body = ##class(Downstream.Service).Apply(admit, .status)
    Do $$$AssertEquals(status, 409, "an admission into a held bed is refused")
    Do $$$AssertEquals(body.error, "bed_occupied", "as bed_occupied")
    Do $$$AssertEquals(body.occupant.since, "2026-10-15T08:10:00Z", "held since the occupant's admission, whatever updates followed")
    Do $$$AssertEquals(body.occupant.version, 2, "at the occupant's current version")
    Do $$$AssertTrue('body.applied, "nothing applied")
    Do ##class(Downstream.Service).GetEncounter(..Encounter(23), .status)
    Do $$$AssertEquals(status, 404, "and the encounter was never created")
    Do admit.%Set("dry_run", 1, "boolean")
    Set body = ##class(Downstream.Service).Apply(admit, .status)
    Do $$$AssertEquals(status, 409, "a rehearsal of the refused admission is refused too")
    Do $$$AssertEquals(body.error, "bed_occupied", "as bed_occupied")
    Do ##class(Downstream.Service).GetEncounter(..Encounter(23), .status)
    Do $$$AssertEquals(status, 404, "the encounter still does not exist")
    Set read = ##class(Downstream.Service).GetEncounter(occupant, .status)
    Do $$$AssertEquals(read.bed, bed, "the occupant keeps the bed")
    Do $$$AssertEquals(read.version, 2, "at its version")
}

Method TestBedFreedByDischarge()
{
    Set occupant = ..Encounter(24), mover = ..Encounter(25), bed = ..Bed(3)
    Do ##class(Downstream.Service).Apply(..Place(occupant, "admit", "WARD-B", bed, "2026-10-15T08:10:00Z"), .status)
    Set body = ##class(Downstream.Service).Apply(..Place(occupant, "discharge", "", "", "2026-10-15T09:00:00Z"), .status)
    Do $$$AssertEquals(body.encounter.%GetTypeOf("bed"), "null", "a discharge leaves no bed")
    Do ..Admit(mover)
    Set body = ##class(Downstream.Service).Apply(..Place(mover, "transfer", "WARD-B", bed, "2026-10-15T09:20:00Z"), .status)
    Do $$$AssertEquals(status, 201, "the discharged patient's bed takes the next one")
    Set read = ##class(Downstream.Service).GetEncounter(mover, .status)
    Do $$$AssertEquals(read.bed, bed, "the read shows the bed")
    Do $$$AssertEquals(read.history.%Get(1).bed, bed, "as does the transfer's history row")
    Do $$$AssertEquals(read.history.%Get(0).%GetTypeOf("bed"), "null", "and the ward-level admit's row has none")
    Do $$$AssertEquals(body.receipt.bed, bed, "and the receipt")
}

Method TestBedFreedByTransferOut()
{
    Set occupant = ..Encounter(26), mover = ..Encounter(27), bed = ..Bed(4)
    Do ##class(Downstream.Service).Apply(..Place(occupant, "admit", "WARD-B", bed, "2026-10-15T08:10:00Z"), .status)
    Set body = ##class(Downstream.Service).Apply(..Place(occupant, "transfer", "WARD-B", ..Bed(5), "2026-10-15T09:00:00Z"), .status)
    Do $$$AssertEquals(status, 201, "the occupant moves to another bed on the ward")
    Do ##class(Downstream.Service).Apply(..Place(mover, "admit", "WARD-B", bed, "2026-10-15T09:10:00Z"), .status)
    Do $$$AssertEquals(status, 201, "and the bed it left takes an admission")
    Do ##class(Downstream.Service).Apply(..Place(occupant, "transfer", "WARD-C", "", "2026-10-15T09:30:00Z"), .status)
    Set body = ##class(Downstream.Service).Apply(..Place(mover, "transfer", "WARD-B", ..Bed(5), "2026-10-15T09:40:00Z"), .status)
    Do $$$AssertEquals(status, 201, "a transfer to another ward frees the second bed too")
}

Method TestOwnBedIsNoConflict()
{
    Set encounter = ..Encounter(28), bed = ..Bed(6)
    Do ##class(Downstream.Service).Apply(..Place(encounter, "admit", "WARD-B", bed, "2026-10-15T08:10:00Z"), .status)
    Set body = ##class(Downstream.Service).Apply(..Place(encounter, "transfer", "WARD-B", bed, "2026-10-15T09:00:00Z"), .status)
    Do $$$AssertEquals(status, 201, "a transfer into the patient's own bed applies")
    Do $$$AssertEquals(body.encounter.version, 2, "as an applied operation")
}

Method TestWardLevelNeverConflicts()
{
    Set occupant = ..Encounter(29), mover = ..Encounter(30), bed = ..Bed(7)
    Do ##class(Downstream.Service).Apply(..Place(occupant, "admit", "WARD-B", bed, "2026-10-15T08:10:00Z"), .status)
    Do ..Admit(mover)
    Set body = ##class(Downstream.Service).Apply(..Place(mover, "transfer", "WARD-B", "", "2026-10-15T09:20:00Z"), .status)
    Do $$$AssertEquals(status, 201, "a ward-level transfer to the occupant's ward applies")
    Do $$$AssertEquals(body.encounter.%GetTypeOf("bed"), "null", "with no bed")
    Do $$$AssertEquals(body.encounter.history.%Get(1).%GetTypeOf("bed"), "null", "in the history either")
    Set body = ##class(Downstream.Service).Apply(..Place(occupant, "transfer", "WARD-B", "", "2026-10-15T09:30:00Z"), .status)
    Do $$$AssertEquals(status, 201, "the occupant's move to ward level")
    Do ##class(Downstream.Service).Apply(..Place(mover, "transfer", "WARD-B", bed, "2026-10-15T09:40:00Z"), .status)
    Do $$$AssertEquals(status, 201, "frees its bed")
}

Method TestBedOnlyForPlacements()
{
    Set encounter = ..Encounter(31)
    Do ..Admit(encounter)
    Set body = ##class(Downstream.Service).Apply(..Place(encounter, "discharge", "", ..Bed(8), "2026-10-15T11:00:00Z"), .status)
    Do $$$AssertEquals(status, 422, "a discharge naming a bed is refused")
    Do $$$AssertEquals(body.detail, "bed must be null for discharge", "as invalid_request")
}

Method TestBedMustBeABedName()
{
    Set encounter = ..Encounter(32)
    Set admit = ..Request(encounter, "admit", "WARD-B", "2026-10-15T08:10:00Z")
    For type = "number", "boolean", "object", "empty", "long" {
        If type = "number" {
            Do admit.%Set("bed", 2, "number")
        } ElseIf type = "boolean" {
            Do admit.%Set("bed", 0, "boolean")
        } ElseIf type = "object" {
            Do admit.%Set("bed", {"bed": "B2"})
        } ElseIf type = "empty" {
            Do admit.%Set("bed", "")
        } Else {
            Do admit.%Set("bed", $TRANSLATE($JUSTIFY("", 65), " ", "B"))
        }
        Set body = ##class(Downstream.Service).Apply(admit, .status)
        Do $$$AssertEquals(status, 422, "a bed given as " _ type _ " is refused")
        Do $$$AssertEquals(body.error, "invalid_request", "as invalid_request")
    }
    Do ##class(Downstream.Service).GetEncounter(encounter, .status)
    Do $$$AssertEquals(status, 404, "and nothing was admitted")
    Do admit.%Set("bed", $EXTRACT(..Bed(9) _ $TRANSLATE($JUSTIFY("", 64), " ", "B"), 1, 64))
    Do ##class(Downstream.Service).Apply(admit, .status)
    Do $$$AssertEquals(status, 201, "a bed name of 64 characters applies")
}

Method TestSameBedInAnotherWard()
{
    Set occupant = ..Encounter(33), mover = ..Encounter(34), bed = ..Bed(10)
    Do ##class(Downstream.Service).Apply(..Place(occupant, "admit", "WARD-B", bed, "2026-10-15T08:10:00Z"), .status)
    Set body = ##class(Downstream.Service).Apply(..Place(mover, "admit", "WARD-C", bed, "2026-10-15T09:00:00Z"), .status)
    Do $$$AssertEquals(status, 201, "a bed of the same name on another ward is another bed")
    Do $$$AssertEquals(body.encounter.ward, "WARD-C", "the patient is on Ward C")
    Do $$$AssertEquals(body.encounter.bed, bed, "in that ward's bed")
}

Method TestResendNamingAnotherBed()
{
    Set encounter = ..Encounter(35), bed = ..Bed(11)
    Set admit = ..Place(encounter, "admit", "WARD-B", bed, "2026-10-15T08:10:00Z")
    Do ##class(Downstream.Service).Apply(admit, .status)
    Do $$$AssertEquals(status, 201, "the admission applies")
    Do admit.%Set("bed", ..Bed(12))
    Set body = ##class(Downstream.Service).Apply(admit, .status)
    Do $$$AssertEquals(status, 200, "a resend under the committed key naming another bed answers 200")
    Do $$$AssertEquals(body.reason, "already_committed", "as already committed, since the bed is not in the digest")
    Do $$$AssertEquals(body.receipt.bed, bed, "with the receipt's bed, the one committed")
    Do $$$AssertEquals(body.encounter.bed, bed, "and the patient stays in it")
    Do $$$AssertEquals(body.encounter.version, 1, "with nothing more applied")
}

/// Holds the bed's lock in a process of its own until <var>flag</var> is killed, for at most 60 seconds.
ClassMethod HoldBed(ward As %String, bed As %String, flag As %String)
{
    Lock +^Downstream.Lock("bed", ward, bed):5
    Quit:'$TEST
    Set @flag = 2
    For i = 1:1:600 {
        Quit:$GET(@flag)'=2
        Hang 0.1
    }
    Lock -^Downstream.Lock("bed", ward, bed)
    Kill @flag
}

/// Starts <method>HoldBed</method> and waits until it holds the lock; returns the flag that releases it.
Method Hold(ward As %String, bed As %String) As %String
{
    Set flag = $NAME(^IRIS.Temp.DownstreamTest(..Prefix, ward, bed))
    Set @flag = 1
    Job ##class(Downstream.Test.Contract).HoldBed(ward, bed, flag)
    For i = 1:1:50 {
        Quit:$GET(@flag)=2
        Hang 0.1
    }
    Quit flag
}

/// Releases a bed <method>Hold</method> holds, and waits until its process lets go.
Method Release(flag As %String)
{
    Set @flag = 0
    For i = 1:1:50 {
        Quit:'$DATA(@flag)
        Hang 0.1
    }
}

Method TestBedLockWaits()
{
    Set occupant = ..Encounter(36), mover = ..Encounter(37), bed = ..Bed(13)
    Do ##class(Downstream.Service).Apply(..Place(occupant, "admit", "WARD-B", bed, "2026-10-15T08:10:00Z"), .status)
    Do ..Admit(mover)
    Set flag = ..Hold("WARD-B", ..Bed(14))
    Do $$$AssertEquals($GET(@flag), 2, "another process holds the bed")
    Set body = ##class(Downstream.Service).Apply(..Place(mover, "transfer", "WARD-B", ..Bed(14), "2026-10-15T09:00:00Z"), .status)
    Do ..Release(flag)
    Do $$$AssertEquals(status, 503, "a placement into a bed another operation holds waits, then answers 503")
    Do $$$AssertEquals(body.error, "ward_unavailable", "as ward_unavailable")
    // The bed an operation leaves is locked too, so a rehearsal's rolled back write never frees it for another
    Set flag = ..Hold("WARD-B", bed)
    Set body = ##class(Downstream.Service).Apply(..Place(occupant, "transfer", "WARD-C", "", "2026-10-15T09:10:00Z"), .status)
    Do ..Release(flag)
    Do $$$AssertEquals(status, 503, "a transfer out of a bed another operation holds waits, then answers 503")
    Set read = ##class(Downstream.Service).GetEncounter(occupant, .status)
    Do $$$AssertEquals(read.bed, bed, "the occupant keeps the bed")
    Do $$$AssertEquals(read.version, 1, "at its version")
    Do ##class(Downstream.Service).Apply(..Place(mover, "transfer", "WARD-B", ..Bed(14), "2026-10-15T09:00:00Z"), .status)
    Do $$$AssertEquals(status, 201, "once the bed is released the placement applies")
}

Method TestBedNotInDigest()
{
    Set transfer = {"operation_key": "PAS^HOSP^MRN1001^ENC-1001^transfer^2026-10-15T09:20:00Z", "encounter_id": "ENC-1001", "patient_id": "MRN1001", "patient_id_authority": "HOSP", "event": "transfer", "ward": "WARD-B", "bed": "B2", "event_time": "2026-10-15T09:20:00Z", "source_system": "PAS"}
    Do $$$AssertEquals(##class(Downstream.Service).Digest(##class(Downstream.Service).Canonical(transfer)), "sha256:56896f1ed42d79e0acee7837e6d552282b8837601853405a4b15d60d655fddf0", "a bed leaves the canonical payload's digest as it was")
}

Method OnAfterAllTests() As %Status
{
    For table = "Downstream.Receipt", "Downstream.Event", "Downstream.Encounter" {
        Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM " _ table _ " WHERE EncounterId LIKE ?", ..Prefix _ "-%")
    }
    Kill ^IRIS.Temp.DownstreamTest(..Prefix)
    Quit $$$OK
}

}
