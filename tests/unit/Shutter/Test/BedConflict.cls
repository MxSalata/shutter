/// The occupied bed (Shutter.Util.BedConflict; CONTRACTS 6.1, v1.28): who holds a refused bed and whether they are leaving,
/// from the refusal, the occupant's encounter as read and the feed's deliveries, with no receiver.
Class Shutter.Test.BedConflict Extends %UnitTest.TestCase
{

ClassMethod Refusal() As %DynamicObject
{
    Quit {"error": "bed_occupied", "detail": "Bed WARD-B/B2 is occupied by encounter ENC-1231 since 2026-10-15T08:10:00Z", "ward": "WARD-B", "bed": "B2", "occupant": {"encounter_id": "ENC-1231", "since": "2026-10-15T08:10:00Z", "version": 3}, "operation_key": "PAS^HOSP^MRN1^ENC-1^transfer^2026-10-15T08:20:00Z", "applied": false}
}

ClassMethod InBed() As %DynamicObject
{
    Quit {"encounter_id": "ENC-1231", "state": "admitted", "ward": "WARD-B", "bed": "B2", "version": 3, "history": [{"event": "admit", "ward": "WARD-B", "bed": "B2", "event_time": "2026-10-15T08:10:00Z", "operation_key": "k-admit"}]}
}

/// The evidence stores the section as a snapshot item of its own kind (found on core: a kind outside the list fails the
/// evidence, and the case with it).
Method TestSnapshotItemKind()
{
    Do $$$AssertStatusOK(##class(Shutter.Store.SnapshotItem).KindIsValid("bed_conflict"), "bed_conflict is a snapshot item kind")
    Do $$$AssertStatusNotOK(##class(Shutter.Store.SnapshotItem).KindIsValid("no_such_kind"), "an unknown kind is refused")
}

Method TestNoOccupantOrNoRead()
{
    Set out = ##class(Shutter.Util.BedConflict).Build({"error": "bed_occupied", "ward": "WARD-B", "bed": "B2"}, "WARD-B", "B2", "", 0, [])
    Do $$$AssertEquals(out.status, "unknown", "no occupant named: unknown")
    Do $$$AssertEquals(out.%GetTypeOf("occupant"), "null", "no occupant")
    Do $$$AssertEquals(out.ward _ "/" _ out.bed, "WARD-B/B2", "the bed from the refusal")
    Set out = ##class(Shutter.Util.BedConflict).Build(..Refusal(), "WARD-B", "B2", {}, 404, [])
    Do $$$AssertEquals(out.status, "unknown", "the occupant could not be read: unknown")
    Do $$$AssertEquals(out.occupant."encounter_id", "ENC-1231", "the occupant is still named")
    Do $$$AssertEquals(out.occupant."read_http_status", 404, "with the read's status")
    Do $$$AssertEquals(out.since, "2026-10-15T08:10:00Z", "and since when")
    Set out = ##class(Shutter.Util.BedConflict).Build("", "WARD-C", "", "", 0, [])
    Do $$$AssertEquals(out.status, "unknown", "no refusal body at all: unknown")
    Do $$$AssertEquals(out.ward, "WARD-C", "the ward from the case")
}

Method TestOccupantLeft()
{
    Set read = {"encounter_id": "ENC-1231", "state": "discharged", "ward": "WARD-B", "bed": "B2", "version": 4, "history": [{"event": "admit", "ward": "WARD-B", "bed": "B2", "event_time": "2026-10-15T08:10:00Z"}, {"event": "discharge", "ward": "WARD-B", "bed": "B2", "event_time": "2026-10-15T09:00:00Z", "operation_key": "k-dis"}]}
    Set out = ##class(Shutter.Util.BedConflict).Build(..Refusal(), "WARD-B", "B2", read, 200, [])
    Do $$$AssertEquals(out.status, "occupant_left", "a discharged occupant has left")
    Do $$$AssertEquals(out."occupant_movement".event, "discharge", "the movement is the history's discharge")
    Do $$$AssertEquals(out."occupant_movement".delivery, "applied", "applied")
    Do $$$AssertEquals(out.occupant.version, 4, "the version as read")
    Set read = {"encounter_id": "ENC-1231", "state": "admitted", "ward": "WARD-C", "bed": "C1", "version": 4, "history": [{"event": "transfer", "ward": "WARD-C", "bed": "C1", "event_time": "2026-10-15T08:50:00Z", "operation_key": "k-tr"}]}
    Set out = ##class(Shutter.Util.BedConflict).Build(..Refusal(), "WARD-B", "B2", read, 200, [])
    Do $$$AssertEquals(out.status, "occupant_left", "an occupant in another ward has left")
    Do $$$AssertEquals(out."occupant_movement"."operation_key", "k-tr", "with the transfer that moved them")
    Set read = {"encounter_id": "ENC-1231", "state": "admitted", "ward": "WARD-B", "bed": "B4", "version": 4, "history": []}
    Set out = ##class(Shutter.Util.BedConflict).Build(..Refusal(), "WARD-B", "B2", read, 200, [])
    Do $$$AssertEquals(out.status, "occupant_left", "another bed of the same ward: left")
    Do $$$AssertEquals(out.%GetTypeOf("occupant_movement"), "null", "with no movement the history shows")
    Set read = {"encounter_id": "ENC-1231", "state": "admitted", "ward": "WARD-B", "bed": null, "version": 4, "history": []}
    Set out = ##class(Shutter.Util.BedConflict).Build(..Refusal(), "WARD-B", "B2", read, 200, [])
    Do $$$AssertEquals(out.status, "occupant_left", "a ward-level placement now: not in the bed")
}

/// A refusal without the ward and bed: the case's own placement words are not compared with the read, so a different
/// spelling of the same bed is no departure; with no movement out known the status is unknown, which blocks.
Method TestRefusalWithoutBed()
{
    Set bare = {"error": "bed_occupied", "occupant": {"encounter_id": "ENC-OCC", "since": "2026-10-15T08:00:00Z"}}
    Set read = {"state": "admitted", "ward": "WARD-B", "bed": "BAY2-02", "version": 3}
    Set out = ##class(Shutter.Util.BedConflict).Build(bare, "WARD-B", "02", read, 200, [])
    Do $$$AssertEquals(out.status, "unknown", "no ward or bed in the refusal: unknown, not occupant_left (" _ out.note _ ")")
    Do $$$AssertEquals(out.ward _ "|" _ out.bed, "WARD-B|02", "the case's placement is still shown")
    Set moving = [{"event": "transfer", "ward": "WARD-C", "bed": "", "event_time": "2026-10-15T08:20:00Z", "operation_key": "k", "delivery": "failed", "outcome": "unavailable", "case_id": "C-1"}]
    Set out = ##class(Shutter.Util.BedConflict).Build(bare, "WARD-B", "02", read, 200, moving)
    Do $$$AssertEquals(out.status, "occupant_leaving", "a movement out sent and not applied still reads as leaving")
    Set gone = {"state": "admitted", "ward": "WARD-C", "bed": "C1", "version": 4}
    Set out = ##class(Shutter.Util.BedConflict).Build(bare, "WARD-B", "02", gone, 200, [])
    Do $$$AssertEquals(out.status, "unknown", "elsewhere by the case's words only: still unknown, since the refusal named no bed")
    Set out = ##class(Shutter.Util.BedConflict).Build({"error": "bed_occupied", "ward": "WARD-B", "bed": "BAY2-02", "occupant": {"encounter_id": "ENC-OCC"}}, "WARD-B", "02", gone, 200, [])
    Do $$$AssertEquals(out.status, "occupant_left", "with the refusal's own bed named, elsewhere is a departure")
    Set discharged = {"state": "discharged", "ward": "", "bed": "", "version": 5}
    Set out = ##class(Shutter.Util.BedConflict).Build(bare, "WARD-B", "02", discharged, 200, [])
    Do $$$AssertEquals(out.status, "occupant_left", "a discharge is a departure whatever the refusal named")
}

Method TestOccupantLeavingOrStaying()
{
    Set out = ##class(Shutter.Util.BedConflict).Build(..Refusal(), "WARD-B", "B2", ..InBed(), 200, [])
    Do $$$AssertEquals(out.status, "occupant_staying", "in the bed with no movement out: staying")
    Do $$$AssertEquals(out.%GetTypeOf("occupant_movement"), "null", "no movement")
    Set deliveries = [{"event": "admit", "ward": "WARD-B", "event_time": "2026-10-15T08:10:00Z", "outcome": "applied", "operation_key": "k-admit"}, {"event": "transfer", "ward": "WARD-C", "bed": "C1", "event_time": "2026-10-15T08:15:00Z", "outcome": "unavailable", "operation_key": "k-out", "case_id": "C-000041"}]
    Set out = ##class(Shutter.Util.BedConflict).Build(..Refusal(), "WARD-B", "B2", ..InBed(), 200, deliveries)
    Do $$$AssertEquals(out.status, "occupant_leaving", "a failed transfer out after since: leaving")
    Do $$$AssertEquals(out."occupant_movement".delivery, "failed", "failed")
    Do $$$AssertEquals(out."occupant_movement".outcome, "unavailable", "with the connector's word")
    Do $$$AssertEquals(out."occupant_movement"."case_id", "C-000041", "and the case about it")
    Do $$$AssertEquals(out."occupant_movement".ward, "WARD-C", "to the other ward")
    Do $$$AssertTrue(out.note [ "C-000041", "the note names the case: " _ out.note)
    Set deliveries = [{"event": "transfer", "ward": "WARD-C", "event_time": "2026-10-15T08:15:00Z", "outcome": "unknown", "operation_key": "k-out"}]
    Set out = ##class(Shutter.Util.BedConflict).Build(..Refusal(), "WARD-B", "B2", ..InBed(), 200, deliveries)
    Do $$$AssertEquals(out."occupant_movement".delivery, "pending", "no answer yet: pending")
    Do $$$AssertNotTrue(out."occupant_movement".%IsDefined("case_id"), "no case yet")
    Set deliveries = [{"event": "discharge", "ward": "WARD-B", "event_time": "2026-10-15T08:30:00Z", "outcome": "uncertain", "operation_key": "k-dis"}]
    Set out = ##class(Shutter.Util.BedConflict).Build(..Refusal(), "WARD-B", "B2", ..InBed(), 200, deliveries)
    Do $$$AssertEquals(out.status _ "/" _ out."occupant_movement".delivery, "occupant_leaving/uncertain", "an uncertain discharge: leaving, uncertain")
    // A movement before since, or an update, is not a movement out.
    Set deliveries = [{"event": "transfer", "ward": "WARD-A", "event_time": "2026-10-15T07:00:00Z", "outcome": "refused", "operation_key": "k-old"}, {"event": "update", "ward": "WARD-B", "event_time": "2026-10-15T08:40:00Z", "outcome": "refused", "operation_key": "k-upd"}]
    Set out = ##class(Shutter.Util.BedConflict).Build(..Refusal(), "WARD-B", "B2", ..InBed(), 200, deliveries)
    Do $$$AssertEquals(out.status, "occupant_staying", "an older transfer and a failed update do not count")
}

}
