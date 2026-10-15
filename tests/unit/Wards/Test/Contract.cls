/// The ward system's contract (docs/CONTRACTS.md, section 1), through <class>Wards.Service</class>. Each test uses its
/// own encounter, so other data is left alone, and <method>OnAfterAllTests</method> removes what the tests made.
/// Faults are set for the test's own operation key and the previous setting is put back. Don't run these during a demo.
Class Wards.Test.Contract Extends %UnitTest.TestCase
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
    Quit ##class(Wards.Service).Apply(..Request(encounter, "admit", "WARD-A", "2026-10-15T09:00:00Z"), .status)
}

Method TestAdmitAndTransfer()
{
    Set encounter = ..Encounter(1)
    Set body = ##class(Wards.Service).Apply(..Request(encounter, "admit", "WARD-A", "2026-10-15T09:00:00Z"), .status)
    Do $$$AssertEquals(status, 201, "the admit applies")
    Do $$$AssertEquals(body.encounter.version, 1, "at version 1")
    Set body = ##class(Wards.Service).Apply(..Request(encounter, "transfer", "WARD-B", "2026-10-15T09:20:00Z"), .status)
    Do $$$AssertEquals(status, 201, "the transfer applies")
    Do $$$AssertEquals(body.encounter.ward, "WARD-B", "the patient is in Ward B")
    Do $$$AssertEquals(body.receipt."version_before", 1, "the receipt has the version before")
    Do $$$AssertEquals(body.receipt."version_after", 2, "and after")
    Set read = ##class(Wards.Service).GetEncounter(encounter, .status)
    Do $$$AssertEquals(read.history.%Size(), 2, "the history has two events")
}

Method TestRepeatedKeyReturnsPriorReceipt()
{
    Set encounter = ..Encounter(2)
    Do ..Admit(encounter)
    Set transfer = ..Request(encounter, "transfer", "WARD-B", "2026-10-15T09:20:00Z")
    Set first = ##class(Wards.Service).Apply(transfer, .status)
    Do $$$AssertEquals(status, 201, "the transfer applies once")
    Do transfer.%Set("source_message_id", "MSG-UT-RESENT")
    Set again = ##class(Wards.Service).Apply(transfer, .status)
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
    Do ##class(Wards.Service).Apply(transfer, .status)
    Do transfer.%Set("ward", "WARD-D")
    Set body = ##class(Wards.Service).Apply(transfer, .status)
    Do $$$AssertEquals(status, 409, "a key reused for another payload is refused")
    Do $$$AssertEquals(body.error, "key_reused_with_different_payload", "as key_reused_with_different_payload")
    Set read = ##class(Wards.Service).GetEncounter(encounter, .status)
    Do $$$AssertEquals(read.ward, "WARD-B", "the patient stays in Ward B")
}

Method TestExpectedVersionMismatchRefused()
{
    Set encounter = ..Encounter(4)
    Do ..Admit(encounter)
    Set transfer = ..Request(encounter, "transfer", "WARD-B", "2026-10-15T09:20:00Z")
    Do transfer.%Set("expected_version", 5)
    Set body = ##class(Wards.Service).Apply(transfer, .status)
    Do $$$AssertEquals(status, 409, "a stale expected version is refused")
    Do $$$AssertEquals(body.error, "version_conflict", "as version_conflict")
    Do $$$AssertEquals(body."current_version", 1, "naming the current version")
    Do ##class(Wards.Service).GetReceipt(transfer."operation_key", .status)
    Do $$$AssertEquals(status, 404, "and no receipt was stored")
}

Method TestTransferAfterDischargeRefused()
{
    Set encounter = ..Encounter(5)
    Do ..Admit(encounter)
    Set body = ##class(Wards.Service).Apply(..Request(encounter, "discharge", "", "2026-10-15T11:00:00Z"), .status)
    Do $$$AssertEquals(status, 201, "the discharge applies")
    Do $$$AssertEquals(body.encounter.state, "discharged", "the encounter is discharged")
    Set body = ##class(Wards.Service).Apply(..Request(encounter, "transfer", "WARD-B", "2026-10-15T09:20:00Z"), .status)
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
    Set body = ##class(Wards.Service).Apply(transfer, .status)
    Do $$$AssertEquals(status, 200, "a rehearsal answers 200")
    Do $$$AssertTrue(body."would_apply", "it would apply")
    Do $$$AssertEquals(body."encounter_after".ward, "WARD-B", "with the patient in Ward B afterwards")
    Set read = ##class(Wards.Service).GetEncounter(encounter, .status)
    Do $$$AssertEquals(read.ward, "WARD-A", "but the patient is still in Ward A")
    Do $$$AssertEquals(read.version, 1, "at version 1")
    Do $$$AssertEquals(read.history.%Size(), 1, "with one event")
    Do ##class(Wards.Service).GetReceipt(transfer."operation_key", .status)
    Do $$$AssertEquals(status, 404, "and no receipt")
}

Method TestDryRunReportsRefusal()
{
    Set encounter = ..Encounter(7)
    Do ..Admit(encounter)
    Set transfer = ..Request(encounter, "transfer", "WARD-B", "2026-10-15T09:20:00Z")
    Do transfer.%Set("expected_version", 3)
    Do transfer.%Set("dry_run", 1, "boolean")
    Set body = ##class(Wards.Service).Apply(transfer, .status)
    Do $$$AssertEquals(status, 200, "a rehearsal that would fail still answers 200")
    Do $$$AssertTrue('body."would_apply", "it would not apply")
    Do $$$AssertEquals(body.reason, "version_conflict", "because of a version conflict")
}

Method TestUnknownEncounterRefused()
{
    Set body = ##class(Wards.Service).Apply(..Request(..Encounter(8), "transfer", "WARD-B", "2026-10-15T09:20:00Z"), .status)
    Do $$$AssertEquals(status, 422, "a transfer for an encounter never admitted is refused")
    Do $$$AssertEquals(body.error, "unknown_encounter", "as unknown_encounter")
}

Method TestInvalidRequestRefused()
{
    Set request = ..Request(..Encounter(9), "discharge", "WARD-A", "2026-10-15T11:00:00Z")
    Set body = ##class(Wards.Service).Apply(request, .status)
    Do $$$AssertEquals(status, 422, "a discharge with a ward is refused")
    Do $$$AssertEquals(body.error, "invalid_request", "as invalid_request")
    Set request = ..Request(..Encounter(9), "admit", "WARD-A", "15/10/2026 09:00")
    Set body = ##class(Wards.Service).Apply(request, .status)
    Do $$$AssertEquals(body.error, "invalid_request", "and so is a time that isn't ISO 8601 UTC")
}

Method TestFailBeforeAcceptWritesNothing()
{
    Set encounter = ..Encounter(10)
    Do ..Admit(encounter)
    Set transfer = ..Request(encounter, "transfer", "WARD-B", "2026-10-15T09:20:00Z")
    Set saved = ##class(Wards.Service).GetFault(.ignore)
    Do ##class(Wards.Service).SetFault({"mode": "fail_before_accept", "operation_key": (transfer."operation_key")}, .ignore)
    Set body = ##class(Wards.Service).Apply(transfer, .status)
    Do ##class(Wards.Service).SetFault(saved, .ignore)
    Do $$$AssertEquals(status, 503, "the ward is unavailable")
    Do $$$AssertEquals(body.error, "ward_unavailable", "as ward_unavailable")
    Do ##class(Wards.Service).GetReceipt(transfer."operation_key", .status)
    Do $$$AssertEquals(status, 404, "and nothing was committed")
}

Method TestCommitDropResponseCommits()
{
    Set encounter = ..Encounter(11)
    Do ..Admit(encounter)
    Set transfer = ..Request(encounter, "transfer", "WARD-B", "2026-10-15T09:20:00Z")
    Set saved = ##class(Wards.Service).GetFault(.ignore)
    Do ##class(Wards.Service).SetFault({"mode": "commit_drop_response", "operation_key": (transfer."operation_key")}, .ignore)
    Set body = ##class(Wards.Service).Apply(transfer, .status)
    Do ##class(Wards.Service).SetFault(saved, .ignore)
    Do $$$AssertEquals(status, 504, "the response is lost")
    Do $$$AssertEquals(body, "", "with no body")
    Do ##class(Wards.Service).GetReceipt(transfer."operation_key", .status)
    Do $$$AssertEquals(status, 200, "but the operation was committed")
    Set again = ##class(Wards.Service).Apply(transfer, .status)
    Do $$$AssertEquals(again.reason, "already_committed", "and a retry finds the receipt")
}

Method TestMisleadingDuplicateError()
{
    Set encounter = ..Encounter(12)
    Do ..Admit(encounter)
    Set transfer = ..Request(encounter, "transfer", "WARD-B", "2026-10-15T09:20:00Z")
    Do transfer.%Set("expected_version", 7)
    Set saved = ##class(Wards.Service).GetFault(.ignore)
    Do ##class(Wards.Service).SetFault({"mode": "misleading_duplicate_error", "operation_key": (transfer."operation_key")}, .ignore)
    Set body = ##class(Wards.Service).Apply(transfer, .status)
    Do ##class(Wards.Service).SetFault(saved, .ignore)
    Do $$$AssertEquals(status, 409, "a version mismatch answers 409")
    Do $$$AssertEquals(body.error, "duplicate_message", "with the misleading duplicate_message")
    Set read = ##class(Wards.Service).GetEncounter(encounter, .status)
    Do $$$AssertEquals(read.version, 1, "and nothing was written")
}

Method TestMisleadingDuplicateWithoutVersion()
{
    Set encounter = ..Encounter(13)
    Do ..Admit(encounter)
    Set transfer = ..Request(encounter, "transfer", "WARD-B", "2026-10-15T09:20:00Z")
    Set saved = ##class(Wards.Service).GetFault(.ignore)
    Do ##class(Wards.Service).SetFault({"mode": "misleading_duplicate_error", "operation_key": (transfer."operation_key")}, .ignore)
    Set body = ##class(Wards.Service).Apply(transfer, .status)
    Do ##class(Wards.Service).SetFault(saved, .ignore)
    Do $$$AssertEquals(status, 409, "with the fault set for its key, routine traffic with no version answers 409")
    Do $$$AssertEquals(body.error, "duplicate_message", "as duplicate_message")
    Do ##class(Wards.Service).GetReceipt(transfer."operation_key", .status)
    Do $$$AssertEquals(status, 404, "and no receipt exists")
}

Method TestPatientMismatchRefused()
{
    Set encounter = ..Encounter(14)
    Do ..Admit(encounter)
    Set transfer = ..Request(encounter, "transfer", "WARD-B", "2026-10-15T09:20:00Z")
    Do transfer.%Set("patient_id", "MRN-SOMEONE-ELSE")
    Set body = ##class(Wards.Service).Apply(transfer, .status)
    Do $$$AssertEquals(status, 422, "a transfer naming another patient is refused")
    Do $$$AssertEquals(body.error, "patient_mismatch", "as patient_mismatch")
    Do $$$AssertEquals(body."encounter_id", encounter, "naming the encounter")
}

Method TestPayloadDigestMismatchRefused()
{
    Set transfer = ..Request(..Encounter(15), "admit", "WARD-A", "2026-10-15T09:00:00Z")
    Do transfer.%Set("payload_digest", "sha256:0000000000000000000000000000000000000000000000000000000000000000")
    Set body = ##class(Wards.Service).Apply(transfer, .status)
    Do $$$AssertEquals(status, 422, "a digest that differs from the ward's is refused")
    Do $$$AssertEquals(body.error, "payload_digest_mismatch", "as payload_digest_mismatch")
    Do transfer.%Set("payload_digest", ##class(Wards.Service).Digest(##class(Wards.Service).Canonical(transfer)))
    Set body = ##class(Wards.Service).Apply(transfer, .status)
    Do $$$AssertEquals(status, 201, "and the right digest is accepted")
}

Method TestCanonicalDigest()
{
    Set transfer = {"operation_key": "PAS^HOSP^MRN1001^ENC-1001^transfer^2026-10-15T09:20:00Z", "encounter_id": "ENC-1001", "patient_id": "MRN1001", "patient_id_authority": "HOSP", "event": "transfer", "ward": "WARD-B", "event_time": "2026-10-15T09:20:00Z", "source_system": "PAS", "source_message_id": "MSG00002", "expected_version": 1}
    Do $$$AssertEquals(##class(Wards.Service).Digest(##class(Wards.Service).Canonical(transfer)), "sha256:56896f1ed42d79e0acee7837e6d552282b8837601853405a4b15d60d655fddf0", "the transfer's digest matches the reference value")
    Set discharge = {"operation_key": "PAS^HOSP^MRN1001^ENC-1001^discharge^2026-10-15T11:00:00Z", "encounter_id": "ENC-1001", "patient_id": "MRN1001", "patient_id_authority": "HOSP", "event": "discharge", "ward": null, "event_time": "2026-10-15T11:00:00Z", "source_system": "PAS"}
    Do $$$AssertEquals(##class(Wards.Service).Digest(##class(Wards.Service).Canonical(discharge)), "sha256:1e254eda9639a80f72f3d0c0a4762c2611642f597292210b6d03acb468d8f913", "a null ward is part of the canonical form")
}

Method TestResetRefusedOutsideDemo()
{
    Set demo = $GET(^Wards.Config("demo"))
    Kill ^Wards.Config("demo")
    Set body = ##class(Wards.Service).Reset(.status)
    Set:demo'="" ^Wards.Config("demo") = demo
    Do $$$AssertEquals(status, 403, "a reset is refused unless the instance is a demo")
    Do $$$AssertEquals(body.error, "not_a_demo_instance", "as not_a_demo_instance")
}

Method OnAfterAllTests() As %Status
{
    For table = "Wards.Receipt", "Wards.Event", "Wards.Encounter" {
        Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM " _ table _ " WHERE EncounterId LIKE ?", ..Prefix _ "-%")
    }
    Quit $$$OK
}

}
