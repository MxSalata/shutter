/// The failsafe at the point of the resend (Shutter.Util.ResendGuard; CONTRACTS 6.5, v1.29), on rows alone: what counts as a
/// message pending ahead of a resend, and what does not.
Class Shutter.Test.ResendGuard Extends %UnitTest.TestCase
{

Parameter KEY = "PAS^HOSP^MRN1^ENC-1^transfer^2026-10-15T08:20:00Z";

Parameter SINCE = "2026-10-26 10:59:31.000";

Method TestClassify()
{
    Set deliveries = [
        {"event": "admit", "operation_key": "k-admit", "source_message_id": "M1", "sent_at": "2026-10-26 10:58:00.000", "outcome": "applied"},
        {"event": "transfer", "operation_key": (..#KEY), "source_message_id": "M2", "sent_at": "2026-10-26 10:59:31.000", "outcome": "unavailable"},
        {"event": "transfer", "operation_key": "k-later", "source_message_id": "M3", "event_time": "2026-10-15T08:45:00Z", "sent_at": "2026-10-26 10:59:40.000", "outcome": "unknown", "ens_header_id": "77"},
        {"event": "discharge", "operation_key": "k-done", "source_message_id": "M4", "sent_at": "2026-10-26 10:59:50.000", "outcome": "refused"},
        {"event": "update", "operation_key": "k-old", "source_message_id": "M0", "sent_at": "2026-10-26 10:50:00.000", "outcome": "unknown"}]
    Set indexed = [
        {"event": "transfer", "operation_key": "k-later", "control_id": "M3", "sent_at": "2026-10-26 10:59:40.000"},
        {"event": "update", "operation_key": "k-unrouted", "control_id": "M5", "event_time": "2026-10-15T08:50:00Z", "sent_at": "2026-10-26 10:59:55.000"},
        {"event": "transfer", "operation_key": (..#KEY), "control_id": "M2", "sent_at": "2026-10-26 10:59:31.000"},
        {"event": "admit", "operation_key": "k-admit", "control_id": "M1", "sent_at": "2026-10-26 10:58:00.000"}]
    Set pending = ##class(Shutter.Util.ResendGuard).Classify(deliveries, indexed, ..#KEY, ..#SINCE, "Downstream Out")
    Do $$$AssertEquals(pending.%Size(), 2, "two messages are pending: the queued transfer and the unrouted update")
    Do $$$AssertEquals(pending.%Get(0)."control_id", "M3", "the queued delivery first")
    Do $$$AssertEquals(pending.%Get(0).where, "queued for the receiver, no answer yet", "named as queued")
    Do $$$AssertEquals(pending.%Get(0)."ens_header_id", "77", "with its header")
    Do $$$AssertEquals(pending.%Get(0).receiver, "Downstream Out", "and the receiver")
    Do $$$AssertEquals(pending.%Get(1)."control_id", "M5", "the index-only message second")
    Do $$$AssertEquals(pending.%Get(1).where, "received, not yet delivered to the receiver", "named as not yet delivered")
    Set text = ##class(Shutter.Util.ResendGuard).Describe(pending)
    Do $$$AssertTrue((text [ "M3") && (text [ "1 more"), "the description names the first and counts the rest: " _ text)
    Do $$$AssertEquals(##class(Shutter.Util.ResendGuard).Describe([]), "", "nothing to describe")
}

Method TestNothingPending()
{
    Set deliveries = [{"event": "transfer", "operation_key": (..#KEY), "source_message_id": "M2", "sent_at": "2026-10-26 10:59:31.000", "outcome": "unavailable"}, {"event": "transfer", "operation_key": "k-later", "source_message_id": "M3", "sent_at": "2026-10-26 10:59:40.000", "outcome": "applied"}]
    Set indexed = [{"event": "transfer", "operation_key": "k-later", "control_id": "M3", "sent_at": "2026-10-26 10:59:40.000"}]
    Do $$$AssertEquals(##class(Shutter.Util.ResendGuard).Classify(deliveries, indexed, ..#KEY, ..#SINCE).%Size(), 0, "an answered later delivery is history, not pending")
    Do $$$AssertEquals(##class(Shutter.Util.ResendGuard).Classify([], [], ..#KEY, ..#SINCE).%Size(), 0, "no rows, nothing pending")
    Do $$$AssertEquals(##class(Shutter.Util.ResendGuard).Classify("", "", ..#KEY, ..#SINCE).%Size(), 0, "no lists at all")
    Set pending = ##class(Shutter.Util.ResendGuard).Classify([{"event": "update", "operation_key": "k-x", "source_message_id": "M9", "sent_at": "2026-10-26 10:59:40.000", "outcome": "unknown"}], [], ..#KEY, "")
    Do $$$AssertEquals(pending.%Size(), 1, "with no since, every unanswered delivery counts")
}

}
