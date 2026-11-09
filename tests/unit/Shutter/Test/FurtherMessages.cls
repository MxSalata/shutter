/// Further messages for the patient (Shutter.Util.FurtherMessages; CONTRACTS 6.5), on rows alone where it can be: what stops a
/// write, what only shows on its plan, and what is no business of this patient's. Then the two reads, on real rows.
Class Shutter.Test.FurtherMessages Extends %UnitTest.TestCase
{

Parameter SINCE = "2026-10-26 10:59:31.000";

Parameter LATER = "2026-10-26 11:00:00.000";

Parameter OLDER = "2026-10-26 10:00:00.000";

ClassMethod Subject(event As %String = "transfer") As %DynamicObject
{
    Quit {"encounter_id": "ENC-1", "patient_id": "MRN1", "patient_id_authority": "HOSP", "event": (event), "event_time": "2026-10-15T08:20:00Z", "operation_key": "k-own", "control_id": "M-OWN"}
}

/// One other-visit row for MRN1 at HOSP, changed by a patch, received after the case's own.
ClassMethod Row(patch As %DynamicObject = "") As %DynamicObject
{
    Set r = {"event": "admit", "message_type": "ADT_A01", "visit_number": "ENC-2", "patient_id": "MRN1", "patient_id_authority": "HOSP", "control_id": "M-2", "event_time": "2026-10-15T08:30:00Z", "sent_at": (..#LATER)}
    If $ISOBJECT(patch) {
        Set pi = patch.%GetIterator()
        While pi.%GetNext(.k, .v) { Do r.%Set(k, v) }
    }
    Quit r
}

Method Weigh(rows As %DynamicArray, event As %String = "transfer", chain As %String = "single", movement As %String = "stop") As %DynamicObject
{
    Quit ##class(Shutter.Util.FurtherMessages).Classify(..Subject(event), rows, chain, ..#SINCE, movement)
}

Method AssertStops(patch As %DynamicObject, why As %String, what As %String)
{
    Set found = ..Weigh([(..Row(patch))])
    Do $$$AssertEquals(found.stops.%Size(), 1, what _ " stops")
    If found.stops.%Size() Do $$$AssertEquals(found.stops.%Get(0).why, why, what _ " stops as " _ why)
}

Method AssertShows(patch As %DynamicObject, what As %String)
{
    Set found = ..Weigh([(..Row(patch))])
    Do $$$AssertEquals(found.stops.%Size(), 0, what _ " does not stop")
    Do $$$AssertEquals(found.shows.%Size(), 1, what _ " shows on the plan")
}

Method AssertNothing(patch As %DynamicObject, what As %String)
{
    Set found = ..Weigh([(..Row(patch))])
    Do $$$AssertEquals(found.stops.%Size() + found.shows.%Size(), 0, what _ " is not a further message for this patient")
}

/// An in-patient movement on another visit stops, whatever became of it; an out-patient attendance shows.
Method TestAnotherVisit()
{
    Do ..AssertStops({}, "other_visit", "a new admission")
    Do ..AssertStops({"event": "transfer", "message_type": "ADT_A02"}, "other_visit", "a new ward stay")
    Do ..AssertStops({"event": "discharge", "message_type": "ADT_A03"}, "other_visit", "an unexpected discharge")
    Do ..AssertStops({"event": "cancel_admit", "message_type": "ADT_A11"}, "other_visit", "a cancelled admission")
    Do ..AssertStops({"outcome": "applied"}, "other_visit", "an admission the receiver applied")
    Do ..AssertStops({"outcome": "unknown"}, "other_visit", "an admission still queued")
    Do ..AssertStops({"event": "register", "message_type": "ADT_A04", "patient_class": "I"}, "other_visit", "an A04 with in-patient class and no bed")
    Do ..AssertStops({"event": "preadmit", "message_type": "ADT_A05", "patient_class": "I"}, "other_visit", "an in-patient pre-admission")
    Do ..AssertShows({"event": "register", "message_type": "ADT_A04", "patient_class": "O"}, "an out-patient A04")
    Do ..AssertShows({"event": "register", "message_type": "ADT_A04", "patient_class": "E"}, "an emergency attendance")
    Do ..AssertShows({"event": "update", "message_type": "ADT_A08"}, "an update on another visit")
    Do ..AssertShows({"event": "person_update", "message_type": "ADT_A31", "visit_number": ""}, "a person update with no visit")
    Do ..AssertNothing({"event": "R01", "message_type": "ORU_R01"}, "a result")
}

/// In-patient moves stop: a movement that says it is an emergency or out-patient one moves no in-patient, so it shows. Any other
/// class, or none, can't be told from an in-patient move, and stops.
Method TestAnotherVisitsClass()
{
    Do ..AssertShows({"event": "discharge", "message_type": "ADT_A03", "patient_class": "E"}, "an emergency department's discharge")
    Do ..AssertShows({"event": "discharge", "message_type": "ADT_A03", "patient_class": "O"}, "an out-patient discharge")
    Do ..AssertShows({"event": "admit", "message_type": "ADT_A01", "patient_class": "E"}, "an emergency attendance sent as an admission")
    Do ..AssertShows({"event": "transfer", "message_type": "ADT_A02", "patient_class": "o"}, "an out-patient move, in small letters")
    Do ..AssertShows({"event": "cancel_discharge", "message_type": "ADT_A13", "patient_class": "E"}, "a cancelled emergency discharge")
    Do ..AssertStops({"event": "discharge", "message_type": "ADT_A03", "patient_class": "I"}, "other_visit", "an in-patient discharge")
    Do ..AssertStops({"event": "transfer", "message_type": "ADT_A02", "patient_class": "I"}, "other_visit", "an in-patient move")
    Do ..AssertStops({"event": "discharge", "message_type": "ADT_A03", "patient_class": ""}, "other_visit", "a discharge with no class")
    Do ..AssertStops({"event": "admit", "message_type": "ADT_A01", "patient_class": "U"}, "other_visit", "an admission of unknown class")
    Do ..AssertStops({"event": "update", "message_type": "ADT_A06", "patient_class": "E"}, "record_changed", "a class change, whatever the class it names")
}

/// A pre-admission on file before the case is a date on a waiting list, not a move: it shows. One that reached the engine after
/// the case's own message may be a real new stay, and stops.
Method TestAWaitingListDate()
{
    Do ..AssertShows({"event": "preadmit", "message_type": "ADT_A05", "patient_class": "I", "sent_at": (..#OLDER), "event_time": "2026-10-15T09:00:00Z"}, "a pre-admission received before the case and dated after it")
    Do ..AssertStops({"event": "preadmit", "message_type": "ADT_A05", "patient_class": "I", "sent_at": (..#LATER), "event_time": "2026-10-15T09:00:00Z"}, "other_visit", "a pre-admission received after the case")
    Do ..AssertStops({"event": "admit", "message_type": "ADT_A01", "sent_at": (..#OLDER), "event_time": "2026-10-15T09:00:00Z"}, "other_visit", "an admission received before the case and timed after it")
}

/// The index's rows carry no patient class, so the read takes it from the message itself: what the feed sent decides, as it does
/// for the rows a scan reads.
Method TestAnIndexedMovementIsReadWithItsClass()
{
    Set case = ##class(Shutter.Store.Case).%New()
    Set case.CaseId = "UT-FURTHER-CLASS", case.EncounterId = "ENC-UT-CLASS", case.Event = "transfer", case.PatientId = "MRN-UT-CLASS", case.PatientIdAuthority = "HOSP"
    Set case.EventTime = "2026-10-15T08:20:00Z", case.OperationKey = "k-class", case.SourceMessageId = "M-OWN-CLASS", case.OpenedAt = "2026-10-26T10:59:31Z"
    // Find reads the stored profile: this test is about the class, so the site's choice is pinned to stop and put back.
    Set saved = ..PinMovement("stop")
    For class = "E", "I" {
        Set body = ##class(EnsLib.HL7.Message).ImportFromString("MSH|^~\&|PAS|HOSP|DOWNSTREAM|HOSP|20261015093000||ADT^A03^ADT_A03|M-UT-CLASS|P|2.5.1" _ $CHAR(13) _ "EVN|A03|20261015093000" _ $CHAR(13) _ "PID|1||MRN-UT-CLASS^^^HOSP^MR" _ $CHAR(13) _ "PV1|1|" _ class _ "|ED^^^HOSP||||||||||||||||ENC-UT-OTHER", .sc)
        Do $$$AssertStatusOK(sc, "the message reads")
        Do $$$AssertStatusOK(body.%Save(), "and is stored")
        Set row = ##class(Shutter.Index.Message).%New()
        Set row.DocId = body.%Id(), row.PatientId = "MRN-UT-CLASS", row.PatientIdAuthority = "HOSP", row.VisitNumber = "ENC-UT-OTHER", row.Event = "discharge", row.MessageType = "ADT_A03"
        Set row.ControlId = "M-UT-CLASS", row.EventTime = "2026-10-15T09:30:00Z", row.TimeCreated = "2099-01-01 00:00:00"
        Do $$$AssertStatusOK(row.%Save(), "the index's row is saved")
        Set found = ##class(Shutter.Util.FurtherMessages).Find(case)
        Do $$$AssertEquals(found.stops.%Size(), $SELECT(class = "I": 1, 1: 0), "a discharge of class " _ class _ " on another visit: stops or not")
        Do $$$AssertEquals(found.shows.%Size(), $SELECT(class = "I": 0, 1: 1), "and shows or not")
        Do ##class(Shutter.Index.Message).%DeleteId(row.%Id())
        Do ##class(EnsLib.HL7.Message).%DeleteId(body.%Id())
    }
    Do ..UnpinMovement(saved)
}

/// Stores the site profile with further_messages.in_patient_movement set to the given word, keeping its version, and
/// returns what to put back: the stored row's text, or "" when there was no row.
Method PinMovement(word As %String) As %String
{
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    Set saved = $SELECT($ISOBJECT(row): row.Json, 1: "")
    Set p = ##class(Shutter.Store.SiteProfile).Current()
    Set version = +p.version
    Do p.%Remove("version")
    If '$ISOBJECT(p.%Get("further_messages")) Set p."further_messages" = {}
    Set p."further_messages"."in_patient_movement" = word
    If '$ISOBJECT(row) Set row = ##class(Shutter.Store.SiteProfile).%New(), row.Version = version
    Set row.Json = p.%ToJSON()
    Do $$$AssertStatusOK(row.%Save(), "the site profile says " _ word _ " for the test")
    Quit saved
}

Method UnpinMovement(saved As %String)
{
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    Quit:'$ISOBJECT(row)
    If saved = "" Do ##class(Shutter.Store.SiteProfile).%DeleteId(row.%Id()) Quit
    Set row.Json = saved
    Do row.%Save()
}

/// What is the case's own, or older than it on both counts, doesn't count.
Method TestNotFurther()
{
    Do ..AssertNothing({"control_id": "M-OWN"}, "the case's own message")
    Do ..AssertNothing({"operation_key": "k-own", "control_id": "M-X"}, "the case's own operation under another control id")
    Do ..AssertNothing({"sent_at": (..#OLDER), "event_time": "2026-10-15T07:00:00Z"}, "an earlier stay")
    Do ..AssertStops({"sent_at": (..#OLDER), "event_time": "2026-10-15T09:00:00Z"}, "other_visit", "a movement received earlier and timed later")
    Do ..AssertStops({"sent_at": (..#LATER), "event_time": "2026-10-15T07:00:00Z"}, "other_visit", "a movement received later and timed earlier")
}

/// The identifier's authority is respected, and an identifier that can't be read says so.
Method TestIdentity()
{
    Do ..AssertNothing({"patient_id": "MRN2"}, "another patient")
    Do ..AssertNothing({"patient_id_authority": "OTHER"}, "the same number from another authority")
    Do ..AssertStops({"patient_id_authority": ""}, "other_visit", "a row with no authority, which can't be told apart")
    Set s = ..Subject(), s."patient_id_authority" = ""
    Do $$$AssertEquals(##class(Shutter.Util.FurtherMessages).Classify(s, [(..Row())], "single", ..#SINCE).stops.%Size(), 1, "a case with no authority counts the row too")
    Set s = ..Subject(), s."patient_id" = ""
    Set found = ##class(Shutter.Util.FurtherMessages).Classify(s, [(..Row({"patient_id": ""}))], "single", ..#SINCE)
    Do $$$AssertEquals(found.identifier, "unreadable", "no identifier is unreadable, and blocks a write")
    Do $$$AssertEquals(found.stops.%Size(), 0, "and matches nothing")
    Set s = ..Subject(), s."patient_id" = "-"
    Do $$$AssertTrue(##class(Shutter.Util.FurtherMessages).Unreadable(##class(Shutter.Util.FurtherMessages).Classify(s, [], "single", ..#SINCE)), "a dash is unreadable too")
}

/// A merge stops for the patient on either side of it, and not for anyone else.
Method TestMerges()
{
    Do ..AssertStops({"event": "merge", "message_type": "ADT_A40", "visit_number": ""}, "merge", "a merge into this patient")
    Do ..AssertStops({"event": "merge", "message_type": "ADT_A40", "visit_number": "", "patient_id": "MRN9", "prior_patient_id": "MRN1", "prior_patient_id_authority": "HOSP"}, "merge", "a merge of this patient into another")
    Do ..AssertNothing({"event": "merge", "message_type": "ADT_A40", "visit_number": "", "patient_id": "MRN9", "prior_patient_id": "MRN1", "prior_patient_id_authority": "OTHER"}, "a merge of the same number from another authority")
    Do ..AssertNothing({"event": "merge", "message_type": "ADT_A40", "visit_number": "", "patient_id": "MRN9", "prior_patient_id": "MRN8"}, "a merge of two other patients")
}

/// A record deleted or renumbered stops, on any visit or none.
Method TestRecordChanged()
{
    Do ..AssertStops({"event": "A29", "message_type": "ADT_A29", "visit_number": ""}, "record_changed", "a person deleted, with no visit")
    Do ..AssertStops({"event": "A29", "message_type": "ADT_A29", "visit_number": "ENC-1"}, "record_changed", "a person deleted, naming this visit")
    Do ..AssertStops({"event": "A50", "message_type": "ADT_A50"}, "record_changed", "a visit renumbered")
    Do ..AssertStops({"event": "update", "message_type": "ADT_A06"}, "record_changed", "an out-patient made an in-patient")
}

/// On this visit only what the receiver did not apply and can't be waited for stops: the guard and the matcher read the rest.
Method TestSameVisit()
{
    For word = "cancel_admit", "cancel_transfer", "cancel_discharge" {
        Do ..AssertStops({"event": (word), "visit_number": "ENC-1", "message_type": ""}, "cancel", "a " _ word _ " with no answer")
        Do ..AssertStops({"event": (word), "visit_number": "ENC-1", "outcome": "unavailable"}, "cancel", "a " _ word _ " that failed")
        Do ..AssertNothing({"event": (word), "visit_number": "ENC-1", "outcome": "applied"}, "a " _ word _ " the receiver applied, which the ordering check reads,")
    }
    Do ..AssertStops({"event": "merge", "visit_number": "ENC-1", "outcome": "unknown"}, "merge", "a merge the receiver has not applied")
    Do ..AssertNothing({"event": "transfer", "visit_number": "ENC-1", "outcome": "unknown"}, "a later transfer of this visit, which the guard reads,")
    Do ..AssertNothing({"event": "update", "visit_number": "ENC-1"}, "a later update of this visit")
    Do ..AssertNothing({"event": "discharge", "visit_number": "ENC-1", "outcome": "unavailable"}, "a failed discharge behind a transfer")
}

/// A failed admission and a failed discharge: alone, the admission puts someone on a closed unit. A chain sends them in order.
Method TestDayCase()
{
    Set discharge = ..Row({"event": "discharge", "visit_number": "ENC-1", "outcome": "unavailable"})
    Set found = ..Weigh([(discharge)], "admit")
    Do $$$AssertEquals(found.stops.%Size(), 1, "a failed admission with a failed discharge stops")
    Do $$$AssertEquals(found.stops.%Get(0).why, "discharge", "named as the discharge")
    Do $$$AssertEquals(..Weigh([(discharge)], "admit", "ordered").stops.%Size(), 0, "an ordered chain sends both, in order")
    Do $$$AssertEquals(..Weigh([(discharge)], "admit", "").stops.%Size(), 1, "no chain counts as single")
    Do $$$AssertEquals(..Weigh([(..Row({"event": "discharge", "visit_number": "ENC-1", "outcome": "applied"}))], "admit").stops.%Size(), 0, "a discharge the receiver applied is the ordering check's")
}

/// The first row of a control id and visit wins: a delivery's answer beats the index's row of the same message.
Method TestDeliveryAnswersForTheIndex()
{
    Set delivered = ..Row({"event": "cancel_transfer", "visit_number": "ENC-1", "control_id": "M-9", "outcome": "applied"})
    Set indexed = ..Row({"event": "cancel_transfer", "visit_number": "ENC-1", "control_id": "M-9"})
    Do $$$AssertEquals(..Weigh([(delivered), (indexed)]).stops.%Size(), 0, "applied, so the index's copy is not a stop")
    Do $$$AssertEquals(..Weigh([(indexed)]).stops.%Size(), 1, "with no delivery it is")
}

/// A site may let another visit's movement through: it then shows. What the receiver never applied on this visit still stops.
Method TestTheSiteChooses()
{
    Set found = ..Weigh([(..Row())], "transfer", "single", "show")
    Do $$$AssertEquals(found.stops.%Size(), 0, "with show, another visit's movement does not stop")
    Do $$$AssertEquals(found.shows.%Size(), 1, "and it is on the plan")
    Set found = ..Weigh([(..Row({"event": "cancel_transfer", "visit_number": "ENC-1"}))], "transfer", "single", "show")
    Do $$$AssertEquals(found.stops.%Size(), 1, "a withdrawn move on this visit still stops")
}

/// The failed movement of the rows below: a transfer to WARD-B bed BAY2-04.
ClassMethod A08Subject(event As %String = "transfer") As %DynamicObject
{
    Set s = ..Subject(event)
    Set s.ward = "WARD-B", s.bed = "BAY2-04"
    Quit s
}

/// A later A08 on this visit, as the index or the message store reads it, timed after the failed movement.
ClassMethod A08Row(patch As %DynamicObject = "") As %DynamicObject
{
    Set r = {"event": "update", "message_type": "ADT_A08", "visit_number": "ENC-1", "control_id": "M-A08", "location": "WARD-B", "bed": "BAY2-09"}
    If $ISOBJECT(patch) {
        Set pi = patch.%GetIterator()
        While pi.%GetNext(.k, .v) { Do r.%Set(k, v) }
    }
    Quit ..Row(r)
}

Method WeighA08(rows As %DynamicArray, subject As %DynamicObject = "", a08 As %String = "stop") As %DynamicObject
{
    Quit ##class(Shutter.Util.FurtherMessages).Classify($SELECT($ISOBJECT(subject): subject, 1: ..A08Subject()), rows, "single", ..#SINCE, "stop", "", a08)
}

Method AssertA08Stops(rows As %DynamicArray, what As %String)
{
    Set found = ..WeighA08(rows)
    Do $$$AssertEquals(found.stops.%Size(), 1, what _ " stops")
    If found.stops.%Size() Do $$$AssertEquals(found.stops.%Get(0).why, "a08_location", what _ " stops as a08_location")
}

Method AssertA08Passes(rows As %DynamicArray, what As %String)
{
    Set found = ..WeighA08(rows)
    Do $$$AssertEquals(found.stops.%Size(), 0, what _ " does not stop")
    Do $$$AssertEquals(found.shows.%Size(), 0, what _ " is not on the plan")
}

/// A later A08 on this visit naming another ward or bed than the failed movement's target is a further movement.
Method TestALaterA08NamingAnotherPlace()
{
    Do ..AssertA08Stops([(..A08Row())], "another bed")
    Do ..AssertA08Stops([(..A08Row({"location": "WARD-C", "bed": "BAY2-04"}))], "another ward")
    Do ..AssertA08Stops([(..A08Row({"outcome": "applied"}))], "another bed the receiver answered as applied")
    Do ..AssertA08Stops([(..A08Row({"location": "WARD-C", "bed": ""}))], "another ward with no bed")
    Set moved = ..A08Subject(), moved.bed = ""
    Set found = ..WeighA08([(..A08Row({"bed": "BAY2-04"}))], moved)
    Do $$$AssertEquals(found.stops.%Size(), 1, "a bed named where the failed movement went to ward level")
    Set found = ..WeighA08([(..A08Row())], ..A08Subject("admit"))
    Do $$$AssertEquals(found.stops.%Size(), 1, "a failed admission has a target too")
}

/// What doesn't count: the target repeated, no location, an A08 older than the movement, an A08 that says only the ward.
Method TestALaterA08ThatDoesNotStop()
{
    Do ..AssertA08Passes([(..A08Row({"bed": "BAY2-04"}))], "the target repeated")
    Do ..AssertA08Passes([(..A08Row({"location": "", "bed": ""}))], "no location")
    Set bare = ..A08Row(), r = bare.%Remove("location"), r = bare.%Remove("bed")
    Do ..AssertA08Passes([(bare)], "no location fields")
    Do ..AssertA08Passes([(..A08Row({"bed": ""}))], "the ward repeated, no bed named")
    Do ..AssertA08Passes([(..A08Row({"event_time": "2026-10-15T08:10:00Z"}))], "an A08 timed before the failed movement, however late it came")
    // A06 and A07 map to update too, and this check is about A08: what they change is weighed as before.
    Do ..AssertA08Passes([(..A08Row({"message_type": "ADT_A06", "outcome": "applied"}))], "an A06 the receiver applied")
    // A failed discharge or update has no target to differ from.
    Do $$$AssertEquals(..WeighA08([(..A08Row())], ..Subject("discharge")).stops.%Size(), 0, "a failed discharge has no target")
    Do $$$AssertEquals(..WeighA08([(..A08Row())], ..Subject("update")).stops.%Size(), 0, "nor has a failed update")
}

/// A delivery row comes first and knows nothing of PV1-3: the message's own row, later in the list, says where.
Method TestAnA08DeliveryIsReadWithItsMessage()
{
    Set delivery = {"event": "update", "visit_number": "ENC-1", "control_id": "M-A08", "operation_key": "k-a08", "event_time": "2026-10-15T08:30:00Z", "sent_at": (..#LATER), "outcome": "applied", "where": "sent to the receiver, answered applied"}
    Set found = ..WeighA08([(delivery), (..A08Row())])
    Do $$$AssertEquals(found.stops.%Size(), 1, "the delivery and its message are one row, and it stops")
    If found.stops.%Size() {
        Set item = found.stops.%Get(0)
        Do $$$AssertEquals(item.location, "WARD-B", "with the message's ward")
        Do $$$AssertEquals(item.bed, "BAY2-09", "and bed")
        Do $$$AssertEquals(item."message_type", "ADT_A08", "and its type")
        Do $$$AssertEquals(item.where, "sent to the receiver, answered applied", "and the delivery's answer")
    }
    Do ..AssertA08Passes([(delivery), (..A08Row({"bed": "BAY2-04"}))], "a delivery of an A08 repeating the target")
    Do ..AssertA08Passes([(delivery)], "a delivery with no message read")
}

/// An A08 repeating a later movement's target is that movement's echo: the movement is weighed by its own rule.
Method TestALaterA08RepeatingALaterMovement()
{
    Set move = ..Row({"event": "transfer", "message_type": "ADT_A02", "visit_number": "ENC-1", "control_id": "M-A02", "location": "WARD-C", "bed": "BAY1-07", "event_time": "2026-10-15T08:25:00Z"})
    Do ..AssertA08Passes([(move), (..A08Row({"location": "WARD-C", "bed": "BAY1-07"}))], "the later transfer's own place")
    Do ..AssertA08Stops([(move), (..A08Row({"location": "WARD-C", "bed": "BAY1-09"}))], "another bed than the later transfer's")
    Set late = ..Row({"event": "transfer", "message_type": "ADT_A02", "visit_number": "ENC-1", "control_id": "M-A02", "location": "WARD-C", "bed": "BAY1-07", "event_time": "2026-10-15T08:40:00Z"})
    Do ..AssertA08Stops([(late), (..A08Row({"location": "WARD-C", "bed": "BAY1-07"}))], "a transfer timed after the A08 explains nothing")
    Set before = ..Row({"event": "admit", "message_type": "ADT_A01", "visit_number": "ENC-1", "control_id": "M-A01", "location": "WARD-A", "bed": "BAY1-01", "event_time": "2026-10-15T08:00:00Z"})
    Do ..AssertA08Stops([(before), (..A08Row({"location": "WARD-A", "bed": "BAY1-01"}))], "an A08 naming where the patient was before the failed movement")
    Set other = ..Row({"event": "transfer", "message_type": "ADT_A02", "visit_number": "ENC-2", "control_id": "M-A02", "location": "WARD-C", "bed": "BAY1-07", "event_time": "2026-10-15T08:25:00Z"})
    Set found = ..WeighA08([(other), (..A08Row({"location": "WARD-C", "bed": "BAY1-07"}))])
    Do $$$AssertTrue(..HasWhy(found, "a08_location"), "a transfer on another visit explains nothing")
}

ClassMethod HasWhy(found As %DynamicObject, why As %String) As %Boolean
{
    Set it = found.stops.%GetIterator()
    While it.%GetNext(, .item) { If item.why = why Return 1 }
    Quit 0
}

/// A later A08 on another visit follows the existing rule, whatever it names.
Method TestALaterA08OnAnotherVisit()
{
    Set found = ..WeighA08([(..A08Row({"visit_number": "ENC-2"}))])
    Do $$$AssertEquals(found.stops.%Size(), 0, "it does not stop")
    Do $$$AssertEquals(found.shows.%Size(), 1, "it shows on the plan")
    If found.shows.%Size() Do $$$AssertEquals(found.shows.%Get(0).why, "shown", "as any other message on file")
}

/// The site's further_messages.a08_location: show puts it on the plan and lets it through.
Method TestALaterA08TheSiteShows()
{
    Set found = ..WeighA08([(..A08Row())], "", "show")
    Do $$$AssertEquals(found.stops.%Size(), 0, "with show it does not stop")
    Do $$$AssertEquals(found.shows.%Size(), 1, "it is on the plan")
    If found.shows.%Size() Do $$$AssertEquals(found.shows.%Get(0).why, "a08_location_shown", "as an A08's location")
    Set case = ..LineCase()
    Set line = ##class(Shutter.Util.FurtherMessages).Line(case, found.shows.%Get(0))
    Do $$$AssertTrue(line [ "does not stop the resend", "the plan says so: " _ line)
    Do $$$AssertTrue(line [ "further_messages.a08_location", "and names the setting: " _ line)
    Set found = ..WeighA08([(..A08Row({"bed": "BAY2-04"}))], "", "show")
    Do $$$AssertEquals(found.shows.%Size(), 0, "the target repeated isn't on the plan either")
    // A cancel on this visit stops whichever the setting says.
    Set found = ..WeighA08([(..A08Row()), (..Row({"event": "cancel_transfer", "message_type": "ADT_A12", "visit_number": "ENC-1", "control_id": "M-C"}))], "", "show")
    Do $$$AssertEquals(found.stops.%Size(), 1, "a withdrawn move still stops")
}

ClassMethod LineCase() As Shutter.Store.Case
{
    Set case = ##class(Shutter.Store.Case).%New()
    Set case.PatientId = "MRN1", case.PatientIdAuthority = "HOSP", case.EncounterId = "ENC-1", case.Event = "transfer", case.Ward = "WARD-B", case.Bed = "BAY2-04"
    Quit case
}

/// The words name the patient, the A08 and both places, and a person can't release it as another visit's movement.
Method TestALaterA08InWords()
{
    Set found = ..WeighA08([(..A08Row())])
    Set line = ##class(Shutter.Util.FurtherMessages).Describe(..LineCase(), found)
    For word = "MRN1", "ADT_A08", "M-A08", "ward WARD-B bed BAY2-09", "ward WARD-B bed BAY2-04", "further movement" {
        Do $$$AssertTrue(line [ word, "the line says " _ word _ ": " _ line)
    }
    Do $$$AssertTrue(##class(Shutter.Util.FurtherMessages).NotReleasable(found) [ "a08_location", "it isn't another visit's movement, so it can't be released here")
    Do $$$AssertTrue(##class(Shutter.Util.FurtherMessages).RowsDigest(found) '= "", "it has a digest as any stop has")
}

/// The two reads give the place: a message read from the store carries its ward and its room and bed, as OperationKey reads them.
Method TestAnA08ReadFromTheStoreCarriesItsPlace()
{
    Set case = ##class(Shutter.Store.Case).%New()
    Set case.PatientId = "MRN-UT-A08", case.PatientIdAuthority = "HOSP", case.EncounterId = "ENC-UT-A08", case.Event = "transfer"
    Set low = $ZDATETIME($ZTIMESTAMP, 3, 1, 3)
    Set mine = ..NewMessage("MSH|^~\&|PAS|HOSP|DOWNSTREAM|HOSP|20261015093000||ADT^A08^ADT_A01|M-UT-A08|P|2.5.1" _ $CHAR(13) _ "EVN|A08|20261015093000" _ $CHAR(13) _ "PID|1||MRN-UT-A08^^^HOSP^MR||SYNTH^A08" _ $CHAR(13) _ "PV1|1|I|WARD-B^BAY2^09^HOSP||||||||||||||||ENC-UT-A08", .h1, .h2)
    Set rows = ##class(Shutter.Util.FurtherMessages).Scan(case, h1 - 1, low, .full)
    Do $$$AssertEquals(rows.%Size(), 1, "the A08 is read")
    If rows.%Size() {
        Do $$$AssertEquals(rows.%Get(0).location, "WARD-B", "PV1-3.1 is the ward")
        Do $$$AssertEquals(rows.%Get(0).bed, "BAY2-09", "room and bed as OperationKey reads them")
    }
    Do ##class(Ens.MessageHeader).%DeleteId(h1), ##class(Ens.MessageHeader).%DeleteId(h2)
    Do ##class(EnsLib.HL7.Message).%DeleteId(mine)
}

/// A person is told both visits, and what is on file. A follower's plan gets none of another patient's.
Method TestWords()
{
    Set case = ##class(Shutter.Store.Case).%New()
    Set case.EncounterId = "ENC-1", case.Event = "transfer", case.PatientId = "MRN1", case.PatientIdAuthority = "HOSP"
    Set found = ..Weigh([(..Row()), (..Row({"control_id": "M-3", "visit_number": "ENC-3"}))])
    Set text = ##class(Shutter.Util.FurtherMessages).Describe(case, found)
    Do $$$AssertTrue(text [ "visit ENC-2", "names the other visit: " _ text)
    Do $$$AssertTrue(text [ "visit ENC-1", "names this visit")
    Do $$$AssertTrue(text [ "MRN1 (HOSP)", "names exactly which patient to review")
    Do $$$AssertTrue(text [ "an admission", "in words a person reads")
    Do $$$AssertTrue(text [ "and 1 more", "counts the rest")
    Do $$$AssertEquals(##class(Shutter.Util.FurtherMessages).Describe(case, ..Weigh([])), "", "nothing to describe")
    Set summary = {"further_messages": (..Weigh([(..Row({"event": "register", "message_type": "ADT_A04", "patient_class": "O"}))])), "ward_state_http_status": 200}
    Set lines = ##class(Shutter.Util.FurtherMessages).PlanLines(case, summary)
    Do $$$AssertEquals(lines.%Size(), 1, "one line on the plan")
    Do $$$AssertTrue(lines.%Get(0) [ "ENC-2", "naming the out-patient visit: " _ lines.%Get(0))
    Do $$$AssertTrue(lines.%Get(0) [ "does not stop", "and saying what it does")
}

/// A lost admission's plan asks about a record entered by hand; a found encounter's does not.
Method TestAdmissionOnNotFound()
{
    Set case = ##class(Shutter.Store.Case).%New()
    Set case.EncounterId = "ENC-1", case.Event = "admit"
    Set lines = ##class(Shutter.Util.FurtherMessages).PlanLines(case, {"ward_state_http_status": 404})
    Do $$$AssertEquals(lines.%Size(), 1, "a line about hand entry")
    Do $$$AssertTrue(lines.%Get(0) [ "by hand", "asks: " _ lines.%Get(0))
    Do $$$AssertTrue(lines.%Get(0) [ "own screen", "and says where to look")
    Do $$$AssertEquals(##class(Shutter.Util.FurtherMessages).PlanLines(case, {"ward_state_http_status": 200}).%Size(), 0, "not when the receiver knows it")
    Set case.Event = "transfer"
    Do $$$AssertEquals(##class(Shutter.Util.FurtherMessages).PlanLines(case, {"ward_state_http_status": 404}).%Size(), 0, "not for a transfer, which blocks anyway")
}

/// The index's patient read, on real rows. An empty time would match nothing, so the read always passes one.
Method TestForPatient()
{
    Set row = ##class(Shutter.Index.Message).%New()
    Set row.DocId = "UT-FURTHER-1", row.PatientId = "MRN-UT-FURTHER", row.PatientIdAuthority = "HOSP", row.VisitNumber = "ENC-UT-2", row.Event = "admit", row.MessageType = "ADT_A01"
    Set row.ControlId = "M-UT", row.EventTime = "2026-10-15T08:30:00Z", row.TimeCreated = ..#LATER
    Set sc = row.%Save()
    Do $$$AssertStatusOK(sc, "a row saved")
    Set found = ##class(Shutter.Index.Message).ForPatient("MRN-UT-FURTHER", ..#SINCE)
    Do $$$AssertEquals(found.%Size(), 1, "the patient's row")
    Do $$$AssertEquals(found.%Get(0)."visit_number", "ENC-UT-2", "with its visit")
    Do $$$AssertEquals(##class(Shutter.Index.Message).ForPatient("MRN-UT-FURTHER", "2030-01-01 00:00:00").%Size(), 0, "not when older than the time")
    Do $$$AssertEquals(##class(Shutter.Index.Message).ForPatient("", ..#SINCE).%Size(), 0, "an empty identifier has no rows")
    Do $$$AssertEquals(##class(Shutter.Index.Message).ForPatient("-", ..#SINCE).%Size(), 0, "nor a dash")
    Do ##class(Shutter.Index.Message).%DeleteId(row.%Id())
}

/// The read of a namespace's messages, which covers what no index does: only this patient's, once per body, and a merge naming
/// them. More headers than one read walks is not a whole read.
Method TestScan()
{
    Set case = ##class(Shutter.Store.Case).%New()
    Set case.PatientId = "MRN-UT-SCAN", case.PatientIdAuthority = "HOSP", case.EncounterId = "ENC-UT-1", case.Event = "transfer"
    Set low = $ZDATETIME($ZTIMESTAMP, 3, 1, 3), first = 0
    Set mine = ..NewMessage("MSH|^~\&|PAS|HOSP|DOWNSTREAM|HOSP|20261015093000||ADT^A01^ADT_A01|M-UT-SCAN1|P|2.5.1" _ $CHAR(13) _ "EVN|A01|20261015093000" _ $CHAR(13) _ "PID|1||MRN-UT-SCAN^^^HOSP^MR" _ $CHAR(13) _ "PV1|1|I|WARD-C^BAY1^07^HOSP||||||||||||||||ENC-UT-2", .h1, .h2)
    Set other = ..NewMessage("MSH|^~\&|PAS|HOSP|DOWNSTREAM|HOSP|20261015093000||ADT^A01^ADT_A01|M-UT-SCAN2|P|2.5.1" _ $CHAR(13) _ "EVN|A01|20261015093000" _ $CHAR(13) _ "PID|1||MRN-UT-ELSE^^^HOSP^MR" _ $CHAR(13) _ "PV1|1|I|WARD-C^BAY1^08^HOSP||||||||||||||||ENC-UT-3", .h3, .h4)
    Set rows = ##class(Shutter.Util.FurtherMessages).Scan(case, h1 - 1, low, .full)
    Do $$$AssertEquals(full, 1, "the read is whole")
    Do $$$AssertEquals(rows.%Size(), 1, "this patient's one message, though two headers carry it")
    If rows.%Size() {
        Set r = rows.%Get(0)
        Do $$$AssertEquals(r."visit_number", "ENC-UT-2", "with its visit")
        Do $$$AssertEquals(r.event, "admit", "and its event")
        Do $$$AssertEquals(r."patient_class", "I", "and its patient class")
        Do $$$AssertEquals(r."control_id", "M-UT-SCAN1", "and its control id")
    }
    For h = h1, h2, h3, h4 { Do ##class(Ens.MessageHeader).%DeleteId(h) }
    Do ##class(EnsLib.HL7.Message).%DeleteId(mine), ##class(EnsLib.HL7.Message).%DeleteId(other)
}

/// A busy feed: more headers than one page after the case's own, all another patient's, and this patient's message behind them.
/// The read walks on to the end and finds it. Only a read that runs out of time with headers left is not whole.
Method TestScanWalksPastABusyFeed()
{
    Set case = ##class(Shutter.Store.Case).%New()
    Set case.PatientId = "MRN-UT-BUSY", case.PatientIdAuthority = "HOSP", case.EncounterId = "ENC-UT-1", case.Event = "transfer"
    Set low = $ZDATETIME($ZTIMESTAMP, 3, 1, 3)
    Set other = ..NewMessage("MSH|^~\&|PAS|HOSP|DOWNSTREAM|HOSP|20261015093000||ADT^A01^ADT_A01|M-UT-BUSY1|P|2.5.1" _ $CHAR(13) _ "EVN|A01|20261015093000" _ $CHAR(13) _ "PID|1||MRN-UT-ELSE^^^HOSP^MR" _ $CHAR(13) _ "PV1|1|I|WARD-C^BAY1^08^HOSP||||||||||||||||ENC-UT-3", .h1, .h2)
    Set more = ##class(Shutter.Util.FurtherMessages).#SCANPAGE + 100
    For i = 1:1:more {
        Set h = ##class(Ens.MessageHeader).%New()
        Set h.MessageBodyClassName = "EnsLib.HL7.Message", h.MessageBodyId = other, h.SourceConfigName = "UT", h.TargetConfigName = "UT", h.TimeCreated = low
        Do h.%Save()
        Set made(h.%Id()) = ""
    }
    Set mine = ..NewMessage("MSH|^~\&|PAS|HOSP|DOWNSTREAM|HOSP|20261015093000||ADT^A01^ADT_A01|M-UT-BUSY2|P|2.5.1" _ $CHAR(13) _ "EVN|A01|20261015093000" _ $CHAR(13) _ "PID|1||MRN-UT-BUSY^^^HOSP^MR" _ $CHAR(13) _ "PV1|1|I|WARD-C^BAY1^07^HOSP||||||||||||||||ENC-UT-2", .h3, .h4)
    Set rows = ##class(Shutter.Util.FurtherMessages).Scan(case, h1 - 1, low, .full, 30)
    Do $$$AssertEquals(full, 1, "a read with the time for it is whole, past one page")
    Do $$$AssertEquals(rows.%Size(), 1, "and finds the patient's message behind the others")
    Set rows = ##class(Shutter.Util.FurtherMessages).Scan(case, h1 - 1, low, .full, 0)
    Do $$$AssertEquals(full, 0, "a read out of time with headers left is not whole")
    Do $$$AssertEquals(rows.%Size(), 0, "and has not reached the message")
    Set words = ##class(Shutter.Util.FurtherMessages).NotWhole("HOSPITAL", 30)
    Do $$$AssertTrue(words [ "HOSPITAL", "the words name the namespace: " _ words)
    Do $$$AssertTrue(words [ "further_messages.scan_seconds", "and the setting a site can change: " _ words)
    Set h = ""
    For { Set h = $ORDER(made(h)) Quit:h=""  Do ##class(Ens.MessageHeader).%DeleteId(h) }
    For h = h1, h2, h3, h4 { Do ##class(Ens.MessageHeader).%DeleteId(h) }
    Do ##class(EnsLib.HL7.Message).%DeleteId(mine), ##class(EnsLib.HL7.Message).%DeleteId(other)
}

/// A stored message with two headers, as an inbound item and a router leave it.
Method NewMessage(text As %String, Output h1 As %String, Output h2 As %String) As %String
{
    Set body = ##class(EnsLib.HL7.Message).ImportFromString(text, .sc)
    Do $$$AssertStatusOK(sc, "the message reads")
    Do body.%Save()
    For i = 1, 2 {
        Set h = ##class(Ens.MessageHeader).%New()
        Set h.MessageBodyClassName = "EnsLib.HL7.Message", h.MessageBodyId = body.%Id(), h.SourceConfigName = "UT", h.TargetConfigName = "UT", h.TimeCreated = $ZDATETIME($ZTIMESTAMP, 3, 1, 3)
        Do h.%Save()
        If i = 1 { Set h1 = h.%Id() } Else { Set h2 = h.%Id() }
    }
    Quit body.%Id()
}

}
