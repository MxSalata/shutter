/// The projection of a FHIR R4 receiver's reads into a case's evidence (Shutter.FHIR.Reader), the FHIR branch of the
/// evidence collector, the fhir part of the material view and the fhir item of a snapshot. The reads are the real
/// operation's (Shutter.Operation.FHIRReceiver) against the test FHIR server in process (Shutter.Test.FakeFhir), and
/// the collector is the real one with only its send replaced by a call (Shutter.Test.QuietFHIREvidence). Every reader
/// of an encounter's state on main is given the projection as it stands: the matcher, the material view, the stopped
/// case's card, the workflow's completeness rule, the model view and the case bundle. A test that stores a profile
/// puts the row back as it was; every case, message and header it saved is removed.
Class Shutter.Test.FHIRReader Extends %UnitTest.TestCase
{

Parameter SERVICE = "FHIRFacade.Service";

Parameter RECEIVER = "UT FHIR Reader Out";

Parameter ADTRECEIVER = "UT ADT Reader Out";

Parameter BASE = "/ut-fhir-reader/r4";

Parameter SYS = "urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49";

Parameter MRNSYS = "urn:shutter:demo:mrn";

Parameter MARKER = "urn:shutter:recovery";

Parameter VISIT = "UTFR-V1001";

Parameter MRN = "MRN-UTFR1";

Parameter EVENTTIME = "2026-11-07T10:30:00Z";

Parameter FHIRJSON = "application/fhir+json; charset=UTF-8";

/// A transfer from WARD-A (PV1-6) to WARD-B (PV1-3), no bed, visit UTFR-V1001.
Parameter FHIRMSG = "MSH|^~\&|PAS|HOSP|WARDSYS|HOSP|20261107103000||ADT^A02^ADT_A02|UTFR1|P|2.5.1<CR>EVN|A02|20261107103000||||20261107103000<CR>PID|1||MRN-UTFR1^^^HOSP^MR||TESTER^TILLY||19800101|F<CR>PV1|1|I|WARD-B^^^HOSP|||WARD-A^^^HOSP|||||||||||||UTFR-V1001";

/// The same transfer for the receiver with a plain API, visit UTFR-ADT-V1.
Parameter ADTMSG = "MSH|^~\&|PAS|HOSP|WARDSYS|HOSP|20261107103000||ADT^A02^ADT_A02|UTFRA1|P|2.5.1<CR>EVN|A02|20261107103000||||20261107103000<CR>PID|1||MRN-UTFRA^^^HOSP^MR||TESTER^TOBY||19800101|M<CR>PV1|1|I|WARD-B^^^HOSP|||WARD-A^^^HOSP|||||||||||||UTFR-ADT-V1";

Parameter ADTCASE = "UT-FHIRRD-ADT";

Parameter NOSTATEMENT = "The server's CapabilityStatement could not be read; nothing is assumed about it";

Method OnBeforeOneTest(testname As %String) As %Status
{
    If ..Loaded() Do $CLASSMETHOD(..#SERVICE, "Reset")
    Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
    Do ..Cleanup()
    Quit $$$OK
}

// ---- the projection ----

/// The seed read whole (one Encounter at Ward A, its Patient, both Locations, a history of one version) gives the
/// conditions of the catalogue's entry for a movement that never arrived and is still due, E2: the receipt absent,
/// the encounter admitted, the transition allowed, the patient the case's, no other source at the same time, and
/// conditional writes read from the statement.
Method TestTheProjectionGivesE2ThroughTheMatcher()
{
    Quit:'..Ready()
    Set case = ..Case()
    Set view = ..View(..Parts(case), case)
    Do $$$AssertEquals(..Keys(view), "fhir,ward_state,ward_state_http_status,receipt,receipt_http_status,route,encounter_body", "the projection's keys")
    Do $$$AssertEquals(view."ward_state_http_status" _ " " _ view."receipt_http_status" _ " " _ view.route."capabilities_http_status", "200 404 200", "the Encounter read, no receipt, the statement read")
    Set fhir = view.fhir
    Do $$$AssertEquals(..Keys(fhir), "kind,base,mapping_digest,message,capability,search,encounter,patient,locations,history", "the fhir view's keys, in the design's order")
    Do $$$AssertEquals(fhir.kind _ " " _ fhir.base, "fhir_r4 " _ ..#BASE, "the kind and the base")
    Do $$$AssertEquals(fhir."mapping_digest", ##class(Shutter.FHIR.Profile).MappingDigest(..Entry().fhir), "the mapping digest is the block's")
    Do $$$AssertEquals(fhir.message.%ToJSON(), "{""prior_ward"":""WARD-A"",""target_ward"":""WARD-B"",""event_time"":""" _ ..#EVENTTIME _ """}", "the message's two wards and its time")
    Do $$$AssertEquals(..Keys(fhir.capability), "http_status,software,fhir_version,versioning,interactions,read_history,update_create", "the capability's keys")
    Do $$$AssertEquals(fhir.capability."http_status" _ " " _ fhir.capability.versioning _ " " _ fhir.capability."read_history", "200 versioned-update 1", "the statement as the reader extracted it")
    Do $$$AssertEquals(fhir.search.%ToJSON(), "{""http_status"":200,""matches"":1,""next"":false}", "one match, no further page")
    Set e = fhir.encounter
    Do $$$AssertEquals(..Keys(e), "http_status,id,etag,version_id,etag_usable,status,subject,identifier_ok,subsetted,modifier_extension,narrative,security,body_digest,locations", "the encounter's keys")
    Do $$$AssertEquals(e."http_status" _ " " _ e.id _ " " _ e.etag _ " " _ e."version_id" _ " " _ e."etag_usable" _ " " _ e.status _ " " _ e.subject _ " " _ e."identifier_ok", "200 enc-1 W/""1"" 1 1 in-progress Patient/demo-p1 1", "the Encounter's identifiers, statuses and versions")
    Do $$$AssertEquals(e.%GetTypeOf("version_id") _ " " _ e.subsetted _ e."modifier_extension" _ e.narrative _ e.security, "string 0000", "the version id is a string; nothing stops the representation")
    Do $$$AssertEquals(e."body_digest", ##class(Shutter.FHIR.Plan).BodyDigest(view."encounter_body"), "the digest is the body's, bare hex")
    Do $$$AssertTrue(e."body_digest" ? 64(1N,1L), "64 hex characters: " _ e."body_digest")
    Set want = [{"reference": "Location/ward-a", "ward": "WARD-A", "status": "active", "start": "2026-11-07T09:00:00Z", "start_utc": "2026-11-07T09:00:00Z", "end": ""}]
    Do $$$AssertEquals(e.locations.%ToJSON(), want.%ToJSON(), "every location entry of the body")
    Set want = {"http_status": 200, "reference": "Patient/demo-p1", "etag": "W/\"1\"", "identifier_ok": true, "link": false, "active": true}
    Do $$$AssertEquals(fhir.patient.%ToJSON(), want.%ToJSON(), "the Patient")
    Set want = [{"reference": "Location/ward-a", "ward": "WARD-A", "http_status": 200, "etag": "W/\"1\"", "status": "active", "identifier_ok": true}, {"reference": "Location/ward-b", "ward": "WARD-B", "http_status": 200, "etag": "W/\"1\"", "status": "active", "identifier_ok": true}]
    Do $$$AssertEquals(fhir.locations.%ToJSON(), want.%ToJSON(), "the Locations, in the map's order")
    Do $$$AssertEquals(fhir.history.%ToJSON(), "{""http_status"":200,""next"":false,""entries"":1,""head_version_id"":""1"",""sent_marker_version"":""""}", "the history")
    Do $$$AssertTrue(fhir.%ToJSON() '[ "resourceType", "the fhir view carries no body")
    Do $$$AssertTrue(..Parsed(view."encounter_body").resourceType = "Encounter", "the body travels beside the view, not in it")

    Set ws = view."ward_state"
    Do $$$AssertEquals(..Keys(ws), "encounter_id,fhir_id,patient_id,patient_id_authority,state,ward,version,epoch,history", "the ward state's keys, and no bed")
    Do $$$AssertEquals(ws."encounter_id" _ " " _ ws."fhir_id" _ " " _ ws."patient_id" _ " " _ ws."patient_id_authority" _ " " _ ws.state _ " " _ ws.ward _ " " _ ws.version _ " [" _ ws.epoch _ "]", ..#VISIT _ " enc-1 " _ ..#MRN _ " HOSP admitted WARD-A 1 []", "the ward state")
    Do $$$AssertEquals(ws.%GetTypeOf("version"), "string", "the version is a string, never a number")
    Set want = [{"event": "transfer", "event_time": "2026-11-07T09:00:00Z", "ward": "WARD-A", "operation_key": "fhir^enc-1/ward-a^2026-11-07T09:00:00Z", "applied_at": "2026-11-07T09:00:00Z", "version": ""}]
    Do $$$AssertEquals(ws.history.%ToJSON(), want.%ToJSON(), "one transfer for each mapped entry")
    Do $$$AssertEquals(##class(Shutter.Catalogue.Matcher).HistoryTime(ws.history.%Get(0)), "2026-11-07T09:00:00Z", "the key's last piece is the time the matcher orders by")

    Set summary = ..Summary(case, view)
    Set c = ##class(Shutter.Catalogue.Matcher).Conditions(case, summary)
    Do $$$AssertEquals(c.delivery _ " " _ c."receiver_answer" _ " " _ c.event _ " " _ c.chain, "failed none transfer single", "the failure as the case holds it")
    Do $$$AssertEquals(c.receipt, "absent", "a history read whole with no marker is a receipt absent, never none")
    Do $$$AssertEquals(c."encounter_state" _ " " _ c.transition _ " " _ c."patient_match", "admitted allowed yes", "the encounter is admitted and the patient is the case's")
    Do $$$AssertEquals(c."later_applied" _ " " _ c."simultaneous_sources" _ " " _ c."event_time", "none no plausible", "the entry before the event is neither later nor at the same time")
    Do $$$AssertEquals(c."conditional_writes", "yes", "conditional writes come from the statement's versioning")
    Set match = ##class(Shutter.Catalogue.Matcher).Match(c, ##class(Shutter.Catalogue.Matcher).Facts(summary, case))
    If match.decision = "not_configured" {
        Do $$$LogMessage("this instance has no catalogue, so the match itself was not made")
    } Else {
        Do $$$AssertEquals(match.entry, "E2", "the catalogue answers E2 (" _ match.decision _ ", " _ match.matches.%Size() _ " match)")
        Do $$$AssertEquals(match.outcome, "resend", "whose outcome is the resend")
    }
}

/// No match is a 404 the receiver gave; one match is the Encounter's own status; two are nothing known; a next link
/// is said beside the count.
Method TestZeroOneTwoMatchesAndNext()
{
    Quit:'..Ready()
    // None: a visit the receiver does not hold.
    Set none = ..Case("UTFR-V-NONE")
    Set view = ..View(..Parts(none), none)
    Do $$$AssertEquals(view.fhir.search.%ToJSON(), "{""http_status"":200,""matches"":0,""next"":false}", "no match")
    Do $$$AssertEquals(view."ward_state_http_status", 404, "a trusted search with no match is a 404")
    Do $$$AssertEquals(view."ward_state".kind _ "|" _ view."ward_state".error, "fhir|no Encounter at the receiver carries the visit number", "and the state says why")
    Do $$$AssertEquals(view.fhir.encounter."http_status" _ view.fhir.history."http_status", "00", "nothing else was read")
    Do $$$AssertEquals(##class(Shutter.Catalogue.Matcher).Conditions(none, ..Summary(none, view))."encounter_state", "not_found", "the matcher reads it as not found")

    // One.
    Set case = ..Case()
    Set view = ..View(..Parts(case), case)
    Do $$$AssertEquals(view.fhir.search.matches _ " " _ view."ward_state_http_status", "1 200", "one match")

    // One match with a further page: the count of this page, and the link said.
    Set op = ..Op(.http)
    Set bundle = {"resourceType": "Bundle", "type": "searchset", "link": [{"relation": "self", "url": "x"}, {"relation": "next", "url": "y"}], "entry": [{"resource": (..Enc("enc-1", ..#VISIT)), "search": {"mode": "match"}}]}
    Set http.Canned("GET", ..SearchPath(..#VISIT)) = $LISTBUILD(200, ..#FHIRJSON, "", "", bundle.%ToJSON())
    Set view = ..View(..Parts(case, op), case)
    Do $$$AssertEquals(view.fhir.search.%ToJSON(), "{""http_status"":200,""matches"":1,""next"":true}", "a next link is said")

    // Two Encounters with the visit number.
    Do $CLASSMETHOD(..#SERVICE, "Seed", [(..Enc("enc-2", ..#VISIT))])
    Set view = ..View(..Parts(case), case)
    Do $$$AssertEquals(view.fhir.search.matches _ " " _ view."ward_state_http_status", "2 0", "two matches are no state")
    Do $$$AssertEquals(view."ward_state".error, "the search gave 2 Encounters for the visit number", "and the state says so")
    Do $$$AssertEquals(##class(Shutter.Catalogue.Matcher).Conditions(case, ..Summary(case, view))."encounter_state", "unknown", "the matcher reads it as unknown")
}

/// The ward state of a collected snapshot is read as it stands by the material view, by the card of a stopped case
/// and by the workflow's rule for evidence that is complete.
Method TestWardStateServesEveryReader()
{
    Quit:'..Ready()
    Set case = ..Case()
    Set summary = ..Collect(case)
    Quit:'$ISOBJECT(summary)

    Set m = ##class(Shutter.Store.Snapshot).Material(summary)
    Set ws = m."ward_state"
    Do $$$AssertEquals(ws."http_status" _ " " _ ws.state _ " " _ ws.ward _ " " _ ws.version _ " " _ ws."patient_id" _ " [" _ ws.epoch _ "]", "200 admitted WARD-A 1 " _ ..#MRN _ " []", "the material view of the ward state")
    Do $$$AssertEquals(ws.history.%Size() _ " " _ ws.history.%Get(0).event _ " " _ ws.history.%Get(0)."event_time" _ " " _ ws.history.%Get(0).ward, "1 transfer 2026-11-07T09:00:00Z WARD-A", "with its history")
    Do $$$AssertEquals(m.receipt."http_status" _ " [" _ m.receipt."version_after" _ "]", "404 []", "and of the receipt")
    Do $$$AssertEquals(+m.route."capabilities_http_status", 200, "and of the route")
    Do $$$AssertTrue(m.%IsDefined("fhir"), "with the fhir part beside them")

    Set card = ##class(Shutter.Util.ReceiverCheck).ForCase(case)
    Do $$$AssertEquals(card.receiverEvidence, "read", "the card takes the state as read")
    Do $$$AssertEquals(card.receiverRead.state _ " " _ card.receiverRead.ward _ " [" _ card.receiverRead.bed _ "]", "admitted WARD-A []", "with its state and ward, and no bed")

    Set wf = ##class(Shutter.Test.QuietWorkflow).%New("Case Workflow")
    Do $$$AssertTrue(wf.Complete(summary, case), "evidence with a 404 receipt and a statement read is complete")
    Do summary.%Set("receipt_http_status", 0, "number")
    Do $$$AssertNotTrue(wf.Complete(summary, case), "and is not with a receipt that could not be read")
}

/// An entry within the site's skew of the event time reads as another source's movement at the same time, because
/// its key begins with fhir and never with the case's source; an entry after the event reads as a later transfer.
Method TestAnEntryInsideTheSkewReadsAsAnotherSource()
{
    Quit:'..Ready()
    Set case = ..Case()
    // Two minutes before the event: inside the default 300 seconds.
    Do ..Reseed([{"location": {"reference": "Location/ward-a"}, "status": "completed", "period": {"start": "2026-11-07T09:00:00Z", "end": "2026-11-07T10:28:00Z"}}, {"location": {"reference": "Location/ward-b"}, "status": "active", "period": {"start": "2026-11-07T10:28:00Z"}}])
    Set view = ..View(..Parts(case), case)
    Do $$$AssertEquals(view."ward_state".ward, "WARD-B", "the one open entry is the ward")
    Do $$$AssertEquals(view."ward_state".history.%Get(1)."operation_key", "fhir^enc-1/ward-b^2026-11-07T10:28:00Z", "the key begins with fhir")
    Set summary = ..Summary(case, view)
    Set c = ##class(Shutter.Catalogue.Matcher).Conditions(case, summary)
    Do $$$AssertEquals(c."simultaneous_sources" _ " " _ c."later_applied", "yes none", "another source at the same time, and nothing later")
    Do $$$AssertEquals(##class(Shutter.Catalogue.Matcher).Facts(summary, case)."other_source", "fhir", "named fhir")

    // The same instant written with an offset is the event's own time.
    Do ..Reseed([{"location": {"reference": "Location/ward-b"}, "status": "active", "period": {"start": "2026-11-07T11:30:00+01:00"}}])
    Set view = ..View(..Parts(case), case)
    Do $$$AssertEquals(view."ward_state".history.%Get(0)."event_time", ..#EVENTTIME, "the start is read as UTC")
    Do $$$AssertEquals(##class(Shutter.Catalogue.Matcher).Conditions(case, ..Summary(case, view))."simultaneous_sources", "yes", "the same instant is the same time")

    // An hour after the event: a later transfer.
    Do ..Reseed([{"location": {"reference": "Location/ward-a"}, "status": "completed", "period": {"start": "2026-11-07T09:00:00Z", "end": "2026-11-07T11:30:00Z"}}, {"location": {"reference": "Location/ward-b"}, "status": "active", "period": {"start": "2026-11-07T11:30:00Z"}}])
    Set view = ..View(..Parts(case), case)
    Set c = ##class(Shutter.Catalogue.Matcher).Conditions(case, ..Summary(case, view))
    Do $$$AssertEquals(c."simultaneous_sources" _ " " _ c."later_applied", "no transfer", "an entry after the event is a later transfer")

    // A start that cannot be read is listed with no UTC time and left out of the history; two open entries are no ward.
    Do ..Reseed([{"location": {"reference": "Location/ward-a"}, "status": "active", "period": {"start": "2026-11-07"}}, {"location": {"reference": "Location/ward-c"}, "period": {"start": "2026-11-07T09:30:00Z"}}])
    Set view = ..View(..Parts(case), case)
    Set want = [{"reference": "Location/ward-a", "ward": "WARD-A", "status": "active", "start": "2026-11-07", "start_utc": "", "end": ""}, {"reference": "Location/ward-c", "ward": "", "status": "", "start": "2026-11-07T09:30:00Z", "start_utc": "2026-11-07T09:30:00Z", "end": ""}]
    Do $$$AssertEquals(view.fhir.encounter.locations.%ToJSON(), want.%ToJSON(), "both entries are listed, the unmapped one with no ward")
    Do $$$AssertEquals(view."ward_state".history.%Size() _ " [" _ view."ward_state".ward _ "]", "0 []", "neither is a history entry, and two open entries are no ward")
}

/// The receipt: 404 when the history was read whole and no version carries the marker of a write this case sent;
/// 200 with the version when one does; 0 when the history was not read or has more pages.
Method TestReceipt404And200And0()
{
    Quit:'..Ready()
    Set case = ..Case()
    Set view = ..View(..Parts(case), case, ["0123456789abcdef0123456789abcdef"])
    Do $$$AssertEquals(view."receipt_http_status", 404, "no version carries the marker")
    Do $$$AssertEquals(view.receipt.%ToJSON(), "{""error"":""no_receipt"",""kind"":""fhir"",""note"":""No version in the history read carries the marker of a write this case sent""}", "the 404's body")

    // A second version carrying the marker of the case's write.
    Set marked = ..Enc("enc-1", ..#VISIT)
    Set marked.meta = {"tag": [{"system": (..#MARKER), "code": "0123456789abcdef0123456789abcdef"}]}
    Do $CLASSMETHOD(..#SERVICE, "Seed", [(marked)])
    Set parts = ..Parts(case)
    Set view = ..View(parts, case, ["ffffffffffffffffffffffffffffffff", "0123456789abcdef0123456789abcdef"])
    Do $$$AssertEquals(view.fhir.history.%ToJSON(), "{""http_status"":200,""next"":false,""entries"":2,""head_version_id"":""2"",""sent_marker_version"":""2""}", "the history names the marked version, and its head is the newest")
    Do $$$AssertEquals(view."receipt_http_status", 200, "a marked version is a receipt")
    Set want = {"kind": "fhir", "operation_key": (case.OperationKey), "version_after": "2"}
    Do $$$AssertEquals(view.receipt.%ToJSON(), want.%ToJSON(), "with the case's key and the version")
    Set c = ##class(Shutter.Catalogue.Matcher).Conditions(case, ..Summary(case, view))
    Do $$$AssertEquals(c.receipt, "present", "the matcher reads it as present")

    // The marker of another case's write is no receipt of this one.
    Set view = ..View(parts, case, ["ffffffffffffffffffffffffffffffff"])
    Do $$$AssertEquals(view."receipt_http_status" _ " [" _ view.fhir.history."sent_marker_version" _ "]", "404 []", "another operation id is not this case's")
    Set view = ..View(parts, case, "")
    Do $$$AssertEquals(view."receipt_http_status", 404, "a case that sent nothing has no receipt")

    // The history not read.
    Set op = ..Op(.http)
    Set http.Canned("GET", "Encounter/enc-1/_history") = $LISTBUILD(500, "text/plain", "", "", "boom")
    Set view = ..View(..Parts(case, op), case, ["0123456789abcdef0123456789abcdef"])
    Do $$$AssertEquals(view."receipt_http_status" _ " " _ view.fhir.history."http_status", "0 500", "a history that answered 500 is no receipt either way")
    Do $$$AssertEquals(view.receipt.%ToJSON(), "{""error"":""the history answered HTTP 500"",""kind"":""fhir""}", "and the receipt says why")
    Do $$$AssertEquals(##class(Shutter.Catalogue.Matcher).Conditions(case, ..Summary(case, view)).receipt, "unreadable", "the matcher reads it as unreadable")

    // A history with a further page and no marker on the first: nothing can be said.
    Set op = ..Op(.http)
    Set paged = {"resourceType": "Bundle", "type": "history", "link": [{"relation": "next", "url": "y"}], "entry": [{"resource": (..Enc("enc-1", ..#VISIT)), "request": {"method": "PUT", "url": "Encounter/enc-1"}}]}
    Set http.Canned("GET", "Encounter/enc-1/_history") = $LISTBUILD(200, ..#FHIRJSON, "", "", paged.%ToJSON())
    Set view = ..View(..Parts(case, op), case, ["0123456789abcdef0123456789abcdef"])
    Do $$$AssertEquals(view."receipt_http_status" _ " " _ view.fhir.history."http_status" _ " " _ view.fhir.history.next, "0 200 1", "a paged history is not read whole")
    Do $$$AssertTrue(view.receipt.error [ "more pages", "and the receipt says so: " _ view.receipt.error)

    // A paged history whose first page holds the marked version is a receipt all the same.
    Set paged.entry.%Get(0).resource.meta = {"versionId": "7", "tag": [{"system": (..#MARKER), "code": "0123456789abcdef0123456789abcdef"}]}
    Set http.Canned("GET", "Encounter/enc-1/_history") = $LISTBUILD(200, ..#FHIRJSON, "", "", paged.%ToJSON())
    Set view = ..View(..Parts(case, op), case, ["0123456789abcdef0123456789abcdef"])
    Do $$$AssertEquals(view."receipt_http_status" _ " " _ view.receipt."version_after", "200 7", "the marker on the page read is a receipt")

    // A marked version with no version id: the history cannot say which version was written, so it is not believed.
    Do paged.entry.%Get(0).resource.meta.%Remove("versionId")
    Set http.Canned("GET", "Encounter/enc-1/_history") = $LISTBUILD(200, ..#FHIRJSON, "", "", paged.%ToJSON())
    Set view = ..View(..Parts(case, op), case, ["0123456789abcdef0123456789abcdef"])
    Do $$$AssertEquals(view."receipt_http_status" _ " " _ view.fhir.history."http_status" _ " [" _ view.fhir.history."sent_marker_version" _ "]", "0 0 []", "a marked version with no version id is no receipt and no history")
    Do $$$AssertTrue(view.receipt.error [ "no version id", "and the receipt says why: " _ view.receipt.error)
}

/// The material view of the fhir part holds the versions and digests a decision rests on, and no time and no status
/// of a read: the same evidence read again gives the same digest, a new version of the Encounter another.
Method TestMaterialMovesWithAnEtagAndNotWithATime()
{
    Quit:'..Ready()
    Set case = ..Case()
    Set view = ..View(..Parts(case), case)
    Set m = ##class(Shutter.FHIR.Reader).Material(view.fhir)
    Do $$$AssertEquals(..Keys(m), "encounter_etag,body_digest,patient_etag,location_etags,mapping_digest,history_head,capability", "the material view's keys")
    Do $$$AssertEquals(..Keys(m.capability), "versioning,read_history,update_create,software_name,software_version", "and its capability's")
    Do $$$AssertEquals(m."encounter_etag" _ " " _ m."patient_etag" _ " " _ m."location_etags".%Size() _ " " _ m."location_etags".%Get(0) _ " " _ m."location_etags".%Get(1) _ " " _ m."history_head", "W/""1"" W/""1"" 2 W/""1"" W/""1"" 1", "the ETags verbatim and the history's head")
    Do $$$AssertEquals(m."body_digest" _ " " _ m."mapping_digest", view.fhir.encounter."body_digest" _ " " _ view.fhir."mapping_digest", "the two digests")
    Set summary = ..Summary(case, view)
    Set whole = ##class(Shutter.Store.Snapshot).Material(summary)
    Do $$$AssertEquals(whole.fhir.%ToJSON(), m.%ToJSON(), "the snapshot's material view carries it as fhir")
    Set d1 = ##class(Shutter.Util.Digest).OfObject(whole)

    // Read again: another time of observation, the same evidence.
    Set parts = ..Parts(case)
    Do parts.%Set("observed_at", "2031-01-01T00:00:00Z", "string")
    Set again = ..View(parts, case)
    Set summary2 = ..Summary(case, again)
    Do summary2.%Set("observed_at", "2031-01-01T00:00:05Z", "string")
    Do $$$AssertEquals(##class(Shutter.Util.Digest).OfObject(##class(Shutter.Store.Snapshot).Material(summary2)), d1, "a second read of the same versions gives the same material digest")
    // The statuses of the reads are not in it either.
    Do again.fhir.search.%Set("http_status", 0, "number")
    Do again.fhir.history.%Set("entries", 9, "number")
    Do again.fhir.capability.%Set("fhir_version", "4.0.2", "string")
    Do $$$AssertEquals(##class(Shutter.FHIR.Reader).Material(again.fhir).%ToJSON(), m.%ToJSON(), "nor does a status or a count move it")

    // A summary with no fhir part gets no fhir key.
    Do summary2.%Remove("fhir")
    Do $$$AssertNotTrue(##class(Shutter.Store.Snapshot).Material(summary2).%IsDefined("fhir"), "nothing is added for a summary with no fhir part")

    // A new version of the Encounter.
    Do ..Reseed([{"location": {"reference": "Location/ward-a"}, "status": "active", "period": {"start": "2026-11-07T09:00:00Z"}}])
    Set moved = ..View(..Parts(case), case)
    Set m2 = ##class(Shutter.FHIR.Reader).Material(moved.fhir)
    Do $$$AssertEquals(m2."encounter_etag" _ " " _ m2."history_head", "W/""2"" 2", "the new version's ETag and head")
    Do $$$AssertNotEquals(##class(Shutter.Util.Digest).OfObject(m2), ##class(Shutter.Util.Digest).OfObject(m), "a new ETag moves the fhir part's digest")
    Do $$$AssertNotEquals(##class(Shutter.Util.Digest).OfObject(##class(Shutter.Store.Snapshot).Material(..Summary(case, moved))), d1, "and the snapshot's material digest")

    // A changed mapping moves it too.
    Do $$$AssertStatusOK(..PutReceivers([(..FhirEntry({"marker": {"system": "urn:shutter:other"}}))]), "the entry is changed")
    Set remapped = ..View(..Parts(case), case)
    Do $$$AssertNotEquals(remapped.fhir."mapping_digest", moved.fhir."mapping_digest", "a changed block has another mapping digest")
}

/// The dispatch read makes no search: the search of the view is the sealed one's, and the Encounter's own status
/// decides the state. A search that was made always wins over the sealed one.
Method TestTheDispatchShapeTakesSearchFromTheSealedView()
{
    Quit:'..Ready()
    Set case = ..Case()
    Set evidence = ..Parts(case)
    Set sealed = ..View(evidence, case).fhir
    Set op = ..Op(.http)
    Set dispatch = ..Parts(case, op, "dispatch", "enc-1", "Patient/demo-p1", "[""Location/ward-a"",""Location/ward-b""]")
    Do $$$AssertNotTrue(dispatch.%IsDefined("search"), "a dispatch read has no search part")
    Set view = ##class(Shutter.FHIR.Reader).Project(dispatch, ..Entry(), case, "WARD-A", [], sealed)
    Do $$$AssertEquals(view.fhir.search.%ToJSON(), sealed.search.%ToJSON(), "the search is the sealed view's")
    Do $$$AssertEquals(view."ward_state_http_status" _ " " _ view."ward_state".ward _ " " _ view.fhir.capability."http_status", "200 WARD-A 200", "the Encounter's own status decides, and the statement is this read's")
    Do $$$AssertEquals(view.fhir.encounter."body_digest", sealed.encounter."body_digest", "the same version gives the same bytes")
    Do $$$AssertEquals(view.fhir.locations.%Size(), 2, "the Locations the request named")

    // Without a sealed view a read with no search says nothing of the state.
    Set view = ##class(Shutter.FHIR.Reader).Project(dispatch, ..Entry(), case, "WARD-A", [])
    Do $$$AssertEquals(view."ward_state_http_status" _ " " _ view.fhir.search."http_status", "0 0", "no search and no sealed view is no state")
    Do $$$AssertEquals(view."ward_state".error, "the search for the visit number was not read", "and the state says so")

    // A search that was made wins over the sealed one.
    Set other = ##class(%DynamicAbstractObject).%FromJSON(sealed.%ToJSON())
    Do other.search.%Set("matches", 2, "number")
    Set view = ##class(Shutter.FHIR.Reader).Project(evidence, ..Entry(), case, "WARD-A", [], other)
    Do $$$AssertEquals(view.fhir.search.matches _ " " _ view."ward_state_http_status", "1 200", "a part that is present always wins")

    // The Encounter gone at dispatch: its own status, and no body.
    Set op = ..Op(.http)
    Set http.Canned("GET", "Encounter/enc-1") = $LISTBUILD(404, ..#FHIRJSON, "", "", "{""resourceType"":""OperationOutcome"",""issue"":[{""severity"":""error"",""code"":""not-found""}]}")
    Set view = ##class(Shutter.FHIR.Reader).Project(..Parts(case, op, "dispatch", "enc-1", "Patient/demo-p1", "[""Location/ward-a"",""Location/ward-b""]"), ..Entry(), case, "WARD-A", [], sealed)
    Do $$$AssertEquals(view."ward_state_http_status" _ " [" _ view."encounter_body" _ "]", "404 []", "a 404 the receiver gave is the state's status")
}

/// The route the collector builds for an entry with no API says nothing was declared; the projection's fields
/// replace that with what the statement says, and take the note away.
Method TestRouteIntoReplacesMainsNote()
{
    Quit:'..Ready()
    Set case = ..Case()
    Set collector = ##class(Shutter.Test.QuietFHIREvidence).%New("Shutter Evidence (unit test)")
    Set route = collector.Route(..#RECEIVER, case)
    Do $$$AssertTrue(route.note [ "declares no features", "main's route for an entry with no API: " _ route.note)
    Do $$$AssertEquals(route."capabilities_http_status" _ " " _ route.%IsDefined("kind"), "0 0", "with nothing read and no kind")
    Set view = ..View(..Parts(case), case)
    Do ##class(Shutter.FHIR.Reader).RouteInto(route, view.route)
    Do $$$AssertNotTrue(route.%IsDefined("note"), "the note is gone")
    Do $$$AssertEquals(route.kind _ "|" _ route."capabilities_source" _ "|" _ route."capabilities_http_status", "fhir_r4|read from the server's CapabilityStatement|200", "the kind, the source and the statement's status")
    Do $$$AssertEquals(route.capabilities.%ToJSON(), "{""conditional_writes"":true,""receipts"":false,""history"":true,""dry_run"":false}", "what the statement says")
    Do $$$AssertEquals(route.%GetTypeOf("conditional_writes") _ route."conditional_writes" _ route.receipts _ route.history _ route."dry_run", "boolean1010", "and the four flags beside it")
    Do $$$AssertEquals(route.declared.%ToJSON(), "{""conditional_writes"":false,""receipts"":false,""history"":false,""dry_run"":false}", "nothing is declared")
    Do $$$AssertEquals(route.%GetTypeOf("epoch") _ "[" _ route.epoch _ "]", "string[]", "no epoch")
    Do $$$AssertEquals(route.connector _ "|" _ route.category, ..#RECEIVER _ "|current_state", "main's own fields stay")

    // The statement not read: no capability at all, and the note that says so.
    Set op = ..Op(.http)
    Set http.Canned("GET", "metadata") = $LISTBUILD(200, "text/html", "", "", "<html>Sign in</html>")
    Set view = ..View(..Parts(case, op), case)
    Set route = collector.Route(..#RECEIVER, case)
    Do ##class(Shutter.FHIR.Reader).RouteInto(route, view.route)
    Do $$$AssertEquals(route.note, ..#NOSTATEMENT, "the note of a statement that was not read")
    Do $$$AssertEquals(route."capabilities_http_status" _ " " _ route.%GetTypeOf("capabilities") _ " " _ route.%IsDefined("conditional_writes") _ route.%IsDefined("history"), "0 null 00", "no capability and no flag")
    Do $$$AssertEquals(view.fhir.capability.%ToJSON(), "{""http_status"":0,""software"":{""name"":"""",""version"":""""},""fhir_version"":"""",""versioning"":"""",""interactions"":[],""read_history"":false,""update_create"":false}", "the view's capability is empty")
    Set summary = ..Summary(case, view)
    Do $$$AssertEquals(##class(Shutter.Catalogue.Matcher).Conditions(case, summary)."conditional_writes", "unknown", "the matcher reads conditional writes as unknown")

    // A statement with no versioning promises no conditional write.
    Set op = ..Op(.http)
    Set http.Canned("GET", "metadata") = $LISTBUILD(200, ..#FHIRJSON, "", "", "{""resourceType"":""CapabilityStatement"",""fhirVersion"":""4.0.1"",""rest"":[{""mode"":""server"",""resource"":[{""type"":""Encounter"",""versioning"":""no-version"",""interaction"":[{""code"":""read""},{""code"":""vread""}],""readHistory"":true}]}]}")
    Set view = ..View(..Parts(case, op), case)
    Do $$$AssertEquals(view.route.capabilities.%ToJSON(), "{""conditional_writes"":false,""receipts"":false,""history"":false,""dry_run"":false}", "no versioned update and no history-instance")
}

/// A read that is not a 200 leaves an error object, never a bare string, and the status that can be trusted.
Method TestANot200ReadGivesAnErrorObject()
{
    Quit:'..Ready()
    Set case = ..Case()
    Set op = ..Op(.http)
    Set http.Canned("GET", "Encounter/enc-1") = $LISTBUILD(500, "text/plain", "", "", "boom")
    Set view = ..View(..Parts(case, op), case)
    Do $$$AssertEquals(view."ward_state_http_status", 500, "a 500 passes through as it came")
    Do $$$AssertEquals(view.%GetTypeOf("ward_state") _ " " _ view."ward_state".%ToJSON(), "object {""error"":""the Encounter answered HTTP 500"",""kind"":""fhir""}", "the state is an error object")
    Do $$$AssertEquals(view."encounter_body" _ "|" _ view.fhir.encounter."body_digest" _ "|" _ view.fhir.encounter.etag, "||", "with no body, digest or ETag")
    Do $$$AssertEquals(##class(Shutter.Catalogue.Matcher).Conditions(case, ..Summary(case, view))."encounter_state", "unknown", "the matcher reads it as unknown")

    // A plain 404 is not the receiver's answer.
    Set op = ..Op(.http)
    Set http.Canned("GET", "Encounter/enc-1") = $LISTBUILD(404, "text/html", "", "", "Not Found")
    Set view = ..View(..Parts(case, op), case)
    Do $$$AssertEquals(view."ward_state_http_status", 0, "a plain 404 is nothing known")
    Do $$$AssertTrue(view."ward_state".error [ "HTTP 404 that is not the receiver's answer", "and the state says what came: " _ view."ward_state".error)
    Do $$$AssertEquals(view."ward_state".kind, "fhir", "an error object of this kind")

    // A search that was not read.
    Set op = ..Op(.http)
    Set http.Canned("GET", ..SearchPath(..#VISIT)) = $LISTBUILD(0)
    Set view = ..View(..Parts(case, op), case)
    Do $$$AssertEquals(view."ward_state_http_status" _ " " _ view."receipt_http_status", "0 0", "no search is no state and no receipt")
    Do $$$AssertTrue(view."ward_state".error [ "the search for the visit number", "the state names the search: " _ view."ward_state".error)

    // A Patient that could not be read: the state stands, and names no patient of the case's.
    Set op = ..Op(.http)
    Set http.Canned("GET", "Patient/demo-p1") = $LISTBUILD(503, "text/plain", "", "", "busy")
    Set view = ..View(..Parts(case, op), case)
    Do $$$AssertEquals(view."ward_state_http_status" _ " [" _ view."ward_state"."patient_id" _ "] [" _ view."ward_state"."patient_id_authority" _ "]", "200 [] []", "no patient is named")
    Set want = {"http_status": 503, "reference": "Patient/demo-p1", "etag": "", "identifier_ok": false, "link": false, "active": false}
    Do $$$AssertEquals(view.fhir.patient.%ToJSON(), want.%ToJSON(), "the Patient part says what came")
    Do $$$AssertEquals(##class(Shutter.Catalogue.Matcher).Conditions(case, ..Summary(case, view))."patient_match", "no", "so the matcher finds no match")

    // A case whose authority is not the mapped one gets the receiver's value and no authority.
    Set other = ..Case(, "OTHER")
    Set view = ..View(..Parts(other), other)
    Do $$$AssertEquals(view."ward_state"."patient_id" _ " [" _ view."ward_state"."patient_id_authority" _ "] " _ view.fhir.patient."identifier_ok", ..#MRN _ " [] 1", "the receiver's value, with no authority")
}

/// No read follows a redirect: every request says so itself, so the credential and the trust in the answer stay with
/// the server the item names. A 3xx is carried as it came, and no reader takes it as the receiver read.
Method TestNoReadFollowsARedirect()
{
    Quit:'..Ready()
    Set case = ..Case()
    Set op = ..Op(.http)
    Set http.Canned("GET", "Encounter/enc-1") = $LISTBUILD(302, "text/html", "", "http://other.example/fhir/r4/Encounter/enc-1", "")
    Set parts = ..Parts(case, op)
    Set left = ""
    For i = 1:1:+$GET(http.Requests) {
        If http.Follow(i) '= 0 Set left = left _ $SELECT(left = "": "", 1: " | ") _ $LIST(http.Requests(i), 2)
    }
    Do $$$AssertTrue(+$GET(http.Requests) >= 6, "the reads were made: " _ ..Log(http))
    Do $$$AssertEquals(left, "", "every request tells the connection never to follow a redirect")
    Do $$$AssertEquals(parts.encounter."http_status" _ " [" _ parts.encounter.body _ "]", "302 []", "a 302 is carried as it came, with no body")
    Set view = ..View(parts, case)
    Do $$$AssertEquals(view."ward_state_http_status" _ "|" _ view.fhir.encounter.etag _ "|" _ view."encounter_body", "302||", "and it is no state, no version and no body")
    Do $$$AssertEquals(##class(Shutter.Catalogue.Matcher).Conditions(case, ..Summary(case, view))."encounter_state", "unknown", "the matcher reads it as unknown")
}

// ---- the collector ----

/// The fhir item of a snapshot is the digest, the ETag and the version id of the Encounter read, and nothing else:
/// the body is in no item and not in the summary, and is kept beside the snapshot.
Method TestTheFhirItemHoldsNoBody()
{
    Quit:'..Ready()
    Set case = ..Case()
    Set summary = ..Collect(case)
    Quit:'$ISOBJECT(summary)
    Set snap = case.CurrentSnapshot
    Set items = snap.Items(), kinds = "", found = ""
    Set it = items.%GetIterator()
    While it.%GetNext(.i, .item) {
        Set kinds = kinds _ $SELECT(kinds = "": "", 1: ",") _ item.kind
        If item.kind = "fhir" Set found = item
        Do $$$AssertTrue(item.data.%ToJSON() '[ "resourceType", "item " _ item.kind _ " holds no resource")
    }
    Do $$$AssertEquals(kinds, "operation,error,message,validation,ward_state,receipt,pending_messages,further_messages,fhir,route", "the items, the fhir item before the route")
    Do $$$AssertTrue($ISOBJECT(found), "there is a fhir item")
    Do $$$AssertEquals(found.source _ " " _ ..Keys(found.data), "fhir_api body_digest,etag,version_id", "from the FHIR API, with three fields")
    Set want = {"body_digest": (summary.fhir.encounter."body_digest"), "etag": "W/\"1\"", "version_id": "1"}
    Do $$$AssertEquals(found.data.%ToJSON(), want.%ToJSON(), "the digest, the ETag and the version id of the Encounter read")
    Do $$$AssertTrue(snap.Summary '[ "resourceType", "the summary holds no resource")
    Do $$$AssertTrue(snap.Summary '[ "http://terminology.hl7.org", "nor any of the body's own text")
    Set body = ##class(Shutter.FHIR.Reader).SealedBody(snap)
    Do $$$AssertEquals(..Parsed(body).resourceType _ " " _ ..Parsed(body).id, "Encounter enc-1", "the body is kept beside the snapshot")
    Do $$$AssertEquals(##class(Shutter.FHIR.Plan).BodyDigest(body), summary.fhir.encounter."body_digest", "under the digest the summary names")
    Do $$$AssertEquals(##class(Shutter.Store.FHIRSealedRead).BodyFor(snap.%Id(), summary.fhir.encounter."body_digest"), body, "as the sealed read of this snapshot")
}

/// What a model is shown of the summary has no fhir part and none of the receiver's references.
Method TestTheModelViewLeavesFhirOut()
{
    Quit:'..Ready()
    Set case = ..Case()
    Set summary = ..Collect(case)
    Quit:'$ISOBJECT(summary)
    Do $$$AssertTrue(summary.%IsDefined("fhir"), "the summary has its fhir part")
    Do $$$AssertStatusOK(##class(Shutter.Util.ModelView).Learn(case, summary), "the case's identifiers are learnt")
    Set shown = ##class(Shutter.Util.ModelView).Reduce(case, summary)
    Do $$$AssertNotTrue(shown.%IsDefined("error"), "the model view is made")
    Do $$$AssertNotTrue(shown.%IsDefined("fhir"), "and it has no fhir part")
    Set text = shown.%ToJSON()
    Do $$$AssertTrue((text '[ "Patient/demo-p1") && (text '[ ..#MRN) && (text '[ ..#VISIT) && (text '[ "mapping_digest"), "nor the Patient's reference, the identifiers or the mapping")
    Do $$$AssertEquals(shown."ward_state".state _ " " _ shown."ward_state".ward, "admitted WARD-A", "the ward state is shown as any receiver's")
    // A history key of four pieces would be read as source^authority^patient^encounter, and the Location's id and the
    // start would each get a token: the ward and the time would then be shown as tokens.
    Set row = shown."ward_state".history.%Get(0)
    Do $$$AssertEquals(row.ward _ " " _ row."event_time" _ " " _ row."operation_key", "WARD-A 2026-11-07T09:00:00Z fhir^enc-1/ward-a^2026-11-07T09:00:00Z", "a history entry keeps its ward, its time and its key")
    Do $$$AssertTrue(text '[ "PID-T", "no value of the receiver's is taken for a patient's identifier")
    Do $$$AssertEquals(shown.route.capabilities.%ToJSON(), "{""conditional_writes"":true,""receipts"":false,""history"":true,""dry_run"":false}", "and the route keeps its capabilities")
}

/// An Encounter that names a practitioner: the name is in no snapshot, so neither the redacted bundle nor the
/// unredacted one can carry it.
Method TestTheBundleCarriesNoEncounterText()
{
    Quit:'..Ready()
    Set named = ..Enc("enc-1", ..#VISIT)
    Set named.participant = [{"individual": {"reference": "Practitioner/ut-prac-1", "display": "Dr Quimby Unittest"}}]
    Set named.reasonCode = [{"text": "Fell at home, seen by Dr Quimby Unittest"}]
    Do $CLASSMETHOD(..#SERVICE, "Seed", [(named)])
    Set case = ..Case()
    Set summary = ..Collect(case)
    Quit:'$ISOBJECT(summary)
    Do $$$AssertTrue(##class(Shutter.FHIR.Reader).SealedBody(case.CurrentSnapshot) [ "Quimby", "the Encounter read does name the practitioner")
    Set text = ##class(Shutter.API.CaseBundle).Text(case, "operator", .why)
    Do $$$AssertTrue(text '= "", "a redacted bundle is built: " _ $GET(why))
    Do $$$AssertTrue((text '[ "Quimby") && (text '[ "Practitioner") && (text '[ "Fell at home"), "the redacted bundle has no text of the Encounter")
    Do $$$AssertTrue((text '[ ..#MRN) && (text '[ ..#VISIT), "nor the case's identifiers")
    Set bundle = ##class(%DynamicAbstractObject).%FromJSON(text)
    Do $$$AssertEquals(bundle.evidence.%Size() _ " " _ bundle.evidence.%Get(0).summary.%IsDefined("fhir"), "1 0", "its evidence has the snapshot, with no fhir part")
    Set whole = ##class(Shutter.API.CaseBundle).UnredactedText(case, "approver", "unit test", .why)
    Do $$$AssertTrue(whole '= "", "an unredacted bundle is built: " _ $GET(why))
    Do $$$AssertTrue((whole '[ "Quimby") && (whole '[ "Fell at home"), "and the unredacted bundle has none either, because no snapshot holds the body")
}

/// The collector asks FHIR Receiver once, with GETs only, and seals a snapshot whose summary carries the projection:
/// the catalogue's match is made on it.
Method TestCollectThroughTheReader()
{
    Quit:'..Ready()
    Set case = ..Case()
    Set summary = ..Collect(case, .op, .response)
    Quit:'$ISOBJECT(summary)
    Do $$$AssertEquals(op.Calls, 1, "FHIR Receiver is asked once")
    Do $$$AssertEquals(..Log(op.Reader.Adapter), "GET metadata | GET " _ ..SearchPath(..#VISIT) _ " | GET Encounter/enc-1 | GET Patient/demo-p1 | GET Location/ward-a | GET Location/ward-b | GET Encounter/enc-1/_history", "seven GETs, and nothing else")
    Do $$$AssertEquals(summary."ward_state_http_status" _ " " _ summary."receipt_http_status", "200 404", "the state read and the receipt absent")
    Do $$$AssertEquals(summary."ward_state"."fhir_id" _ " " _ summary."ward_state".ward, "enc-1 WARD-A", "the ward state is the projection")
    Do $$$AssertEquals(summary.receipt.error, "no_receipt", "the receipt is the projection")
    Do $$$AssertEquals(summary.fhir.kind _ " " _ summary.fhir.message."prior_ward" _ " " _ summary.fhir.message."target_ward" _ " " _ summary.fhir.message."event_time", "fhir_r4 WARD-A WARD-B " _ ..#EVENTTIME, "the fhir part, with PV1-6 as the prior ward")
    Do $$$AssertEquals(summary.route.kind _ " " _ summary.route."capabilities_http_status" _ " " _ summary.route.%IsDefined("note") _ " " _ summary.route."conditional_writes", "fhir_r4 200 0 1", "the route is the statement's")
    Do $$$AssertEquals(summary.%GetTypeOf("epoch") _ "[" _ summary.epoch _ "]", "string[]", "no epoch")
    Do $$$AssertEquals(response.ItemCount, 10, "ten observations")
    Set snap = case.CurrentSnapshot
    Do $$$AssertEquals(snap.%Id(), response.SnapshotId, "the case's snapshot is this one")
    Do $$$AssertEquals(snap.MaterialDigest, ##class(Shutter.Util.Digest).OfObject(##class(Shutter.Store.Snapshot).Material(summary)), "its material digest is of the view with the fhir part")
    Set cat = summary.catalogue
    Do $$$AssertEquals(cat.conditions.receipt _ " " _ cat.conditions."encounter_state" _ " " _ cat.conditions."conditional_writes" _ " " _ cat.conditions."patient_match", "absent admitted yes yes", "the conditions the collector matched on")
    If cat.decision = "not_configured" {
        Do $$$LogMessage("this instance has no catalogue, so the match itself was not made")
    } Else {
        Do $$$AssertEquals(cat.entry, "E2", "the catalogue answers E2 on the collected evidence (" _ cat.decision _ ")")
    }

    // A case with no visit number takes the collector's own branch: no read, no fhir part.
    Set none = ..Case("-")
    Set summary = ..Collect(none, .op2)
    Quit:'$ISOBJECT(summary)
    Do $$$AssertEquals(op2.Calls _ " " _ summary.%IsDefined("fhir") _ " " _ summary."ward_state_http_status" _ " " _ summary."receipt_http_status", "0 0 0 -1", "a case that names no encounter is not read")
    Do $$$AssertNotTrue(summary.route.%IsDefined("kind"), "and its route has no kind")
}

/// A call that fails, and an answer that is one error, both give a snapshot with every status 0 and the reason.
Method TestAFailedReadGivesStatusZero()
{
    Quit:'..Ready()
    Set case = ..Case()
    Set summary = ..Collect(case, .op, , "the item FHIR Receiver is not running")
    Quit:'$ISOBJECT(summary)
    Do $$$AssertEquals(+$GET(op.Reader.Adapter.Requests), 0, "no request was made")
    Do $$$AssertEquals(summary."ward_state_http_status" _ " " _ summary."receipt_http_status" _ " " _ summary.route."capabilities_http_status", "0 0 0", "every status is 0")
    Do $$$AssertTrue((summary."ward_state".error [ "the receiver was not read") && (summary."ward_state".error [ "the item FHIR Receiver is not running"), "the state says why: " _ summary."ward_state".error)
    Do $$$AssertEquals(summary."ward_state".kind _ " " _ summary.receipt.kind, "fhir fhir", "error objects of this kind")
    Set f = summary.fhir
    Do $$$AssertEquals(f.capability."http_status" _ f.search."http_status" _ f.encounter."http_status" _ f.patient."http_status" _ f.history."http_status", "00000", "and so is every part of the fhir view")
    Set want = [{"reference": "Location/ward-a", "ward": "WARD-A", "http_status": 0, "etag": "", "status": "", "identifier_ok": false}, {"reference": "Location/ward-b", "ward": "WARD-B", "http_status": 0, "etag": "", "status": "", "identifier_ok": false}]
    Do $$$AssertEquals(f.locations.%ToJSON(), want.%ToJSON(), "every ward of the map stands as not read")
    Do $$$AssertEquals(f.message."prior_ward" _ " " _ f."mapping_digest", "WARD-A " _ ##class(Shutter.FHIR.Profile).MappingDigest(..Entry().fhir), "the message and the mapping are still said")
    Do $$$AssertEquals(summary.route.note _ "|" _ summary.route.kind, ..#NOSTATEMENT _ "|fhir_r4", "the route says the statement was not read")
    Set c = summary.catalogue.conditions
    Do $$$AssertEquals(c."encounter_state" _ " " _ c.receipt _ " " _ c."conditional_writes" _ " " _ c."patient_match", "unknown unreadable unknown unknown", "the matcher reads nothing from it")
    Do $$$AssertEquals(##class(Shutter.FHIR.Reader).SealedBody(case.CurrentSnapshot), "", "and no body is kept")
    Set kinds = "", it = case.CurrentSnapshot.Items().%GetIterator()
    While it.%GetNext(.i, .item) { If item.kind = "fhir" Set kinds = item.data.%ToJSON() }
    Do $$$AssertEquals(kinds, "{""body_digest"":"""",""etag"":"""",""version_id"":""""}", "the fhir item is empty")

    // An answer that is one error and no parts.
    Set summary = ..Collect(case, .op, , , 10)
    Quit:'$ISOBJECT(summary)
    Do $$$AssertEquals(summary."ward_state_http_status" _ " " _ summary."receipt_http_status", "0 0", "an answer too large to carry is nothing read")
    Do $$$AssertTrue(summary."ward_state".error [ "together too large to carry", "and the state carries the reader's reason: " _ summary."ward_state".error)

    // The projection of nothing at all never throws.
    Set view = ##class(Shutter.FHIR.Reader).Project("", "", "", "", "")
    Do $$$AssertEquals(view."ward_state_http_status" _ " " _ view."receipt_http_status" _ " " _ view.fhir.kind _ " [" _ view."encounter_body" _ "]", "0 0 fhir_r4 []", "no parts, no entry and no case give a view of zeros")
}

/// A case of a receiver with a plain API takes none of the FHIR branches: its summary and its items are, byte for
/// byte, what the collector gave before the FHIR receiver existed. XData Adt holds that document as main's code
/// (e1d30b77) gave it for this case, with the times of observation and the header's ids replaced by "*", and the
/// catalogue's answer and the precedents by "*" too: both are pure functions of the rest, and their words change
/// with the knowledge files. The receiver is this test's own entry; the feed's time zone in the document is the
/// installed profile's (Europe/London, as a demo install has it).
Method TestAnAdtSummaryIsByteForByteAsBefore()
{
    Quit:'..Ready()
    Set got = ..AdtDocument(.why, .calls)
    Do $$$AssertTrue(got '= "", "the plain receiver's case is collected" _ $SELECT($GET(why) = "": "", 1: ": " _ why))
    Quit:got=""
    Do $$$AssertEquals(calls, 0, "FHIR Receiver is not asked")
    Set xdata = ##class(%Dictionary.CompiledXData).%OpenId($CLASSNAME() _ "||Adt")
    Set want = ##class(%DynamicAbstractObject).%FromJSON(xdata.Data).%ToJSON()
    Set at = 1
    While ($EXTRACT(got, at) = $EXTRACT(want, at)) && (at <= $LENGTH(want)) { Set at = at + 1 }
    Do $$$AssertTrue(got = want, "the summary and the items are as before" _ $SELECT(got = want: "", 1: "; they differ at character " _ at _ ": got ..." _ $EXTRACT(got, at - 60, at + 60) _ "... for ..." _ $EXTRACT(want, at - 60, at + 60) _ "..."))
    Set doc = ##class(%DynamicAbstractObject).%FromJSON(got)
    Do $$$AssertNotTrue(doc.summary.%IsDefined("fhir") || doc.summary.route.%IsDefined("kind"), "no fhir part and no kind on the route")
}

// ---- helpers ----

ClassMethod Loaded() As %Boolean
{
    Quit ##class(%Dictionary.CompiledClass).%ExistsId(..#SERVICE)
}

/// Whether the test can run: the test FHIR server is loaded. Seeds it and puts this class's receiver in the profile.
Method Ready() As %Boolean
{
    If '..Loaded() {
        Do $$$AssertSkipped("FHIRFacade is not loaded on this instance")
        Quit 0
    }
    Set out = $CLASSMETHOD(..#SERVICE, "Seed", ..SeedResources())
    Do $$$AssertEquals(out.%Get(3).status, 201, "the seed is written")
    Do $$$AssertStatusOK(..PutReceivers([(..FhirEntry())]), "the site profile holds the test's receiver")
    Quit 1
}

/// Two wards, a patient and enc-1 at Ward A for this class's visit.
ClassMethod SeedResources() As %DynamicArray
{
    Set seed = []
    Do seed.%Push({"resourceType": "Location", "id": "ward-a", "identifier": [{"system": "urn:shutter:ward", "value": "WARD-A"}], "status": "active", "name": "Ward A"})
    Do seed.%Push({"resourceType": "Location", "id": "ward-b", "identifier": [{"system": "urn:shutter:ward", "value": "WARD-B"}], "status": "active", "name": "Ward B"})
    Do seed.%Push({"resourceType": "Patient", "id": "demo-p1", "identifier": [{"system": (..#MRNSYS), "value": (..#MRN)}], "active": true})
    Do seed.%Push(..Enc("enc-1", ..#VISIT))
    Quit seed
}

ClassMethod Enc(id As %String, value As %String) As %DynamicObject
{
    Quit {"resourceType": "Encounter", "id": (id), "status": "in-progress", "identifier": [{"system": (..#SYS), "value": (value)}], "class": {"system": "http://terminology.hl7.org/CodeSystem/v3-ActCode", "code": "IMP"}, "subject": {"reference": "Patient/demo-p1"}, "location": [{"location": {"reference": "Location/ward-a"}, "status": "active", "period": {"start": "2026-11-07T09:00:00Z"}}]}
}

/// Writes enc-1 again with other location entries: a new version.
Method Reseed(locations As %DynamicArray)
{
    Set enc = ..Enc("enc-1", ..#VISIT)
    Set enc.location = locations
    Set out = $CLASSMETHOD(..#SERVICE, "Seed", [(enc)])
    Do $$$AssertEquals(out.%Get(0).status, 200, "the Encounter is written again")
}

/// The search FHIR Receiver makes for a visit, as the adapter logs it.
ClassMethod SearchPath(visit As %String) As %String
{
    Quit "Encounter?identifier=" _ ##class(Shutter.Operation.FHIRReceiver).Escape(..#SYS) _ "%7C" _ ##class(Shutter.Operation.FHIRReceiver).Escape(visit)
}

/// FHIR Receiver with the test FHIR server as its adapter.
ClassMethod Op(Output http As Shutter.Test.FakeFhir) As Shutter.Operation.FHIRReceiver
{
    Set op = ##class(Shutter.Operation.FHIRReceiver).%New("FHIR Receiver (unit test)")
    Set http = ##class(Shutter.Test.FakeFhir).%New()
    Set http.Base = ..#BASE
    Set op.Adapter = http
    Quit op
}

/// The parts of one read through the operation.
Method Parts(case As Shutter.Store.Case, op As Shutter.Operation.FHIRReceiver = "", purpose As %String = "evidence", encounterId As %String = "", patientRef As %String = "", refs As %String = "") As %DynamicObject
{
    If '$ISOBJECT(op) Set op = ..Op()
    Set request = ##class(Shutter.Msg.FHIRRead).%New()
    Set request.CaseId = case.CaseId, request.Purpose = purpose, request.EncounterId = encounterId
    Set request.PatientRef = patientRef, request.LocationRefsJSON = refs
    Do $$$AssertStatusOK(op.OnRead(request, .response), "the " _ purpose _ " read is answered")
    Do $$$AssertEquals(response.Error, "", "with parts")
    If response.PartsJSON = "" Quit {}
    Quit ##class(%DynamicAbstractObject).%FromJSON(response.PartsJSON)
}

/// The projection of parts for a case, with the prior ward of this class's message.
Method View(parts As %DynamicObject, case As Shutter.Store.Case, sentIds As %DynamicArray = "") As %DynamicObject
{
    If sentIds = "" Set sentIds = []
    Quit ##class(Shutter.FHIR.Reader).Project(parts, ..Entry(), case, ##class(Shutter.FHIR.Reader).PriorWard(case), sentIds)
}

/// The summary the collector would make of a view, as far as the matcher and the material view read it: the route is
/// the collector's own for the entry, with the view's fields laid over it.
Method Summary(case As Shutter.Store.Case, view As %DynamicObject) As %DynamicObject
{
    Set collector = ##class(Shutter.Test.QuietFHIREvidence).%New("Shutter Evidence (unit test)")
    Set route = collector.Route(case.Receiver, case)
    Do ##class(Shutter.FHIR.Reader).RouteInto(route, view.route)
    Set s = {}
    Set s."case_id" = case.CaseId
    Set s.operation = {"operation_key": (case.OperationKey), "payload_digest": "sha256:ut"}
    Set s.failure = {"kind": (case.FailureKind), "text": "made up"}
    Set s.message = {"message_time": (case.EventTime)}
    Set s."ward_state" = view."ward_state"
    Do s.%Set("ward_state_http_status", view."ward_state_http_status", "number")
    Set s.receipt = view.receipt
    Do s.%Set("receipt_http_status", view."receipt_http_status", "number")
    Set s.timeline = []
    Set s.route = route
    Set s.fhir = view.fhir
    Set s."observed_at" = ##class(Shutter.Util.Time).NowUTC()
    Quit s
}

/// One collection through the real collector with its send replaced by a call; the summary, or "" when it failed.
/// <var>fails</var> makes the call fail with that text; <var>maxTotal</var> makes the reader's answer too large.
Method Collect(case As Shutter.Store.Case, Output op As Shutter.Test.QuietFHIREvidence, Output response As Shutter.Msg.EvidenceResult, fails As %String = "", maxTotal As %Integer = 0) As %DynamicObject
{
    Set op = ##class(Shutter.Test.QuietFHIREvidence).%New("Shutter Evidence (unit test)")
    Set op.SecondParserTarget = "", op.Fails = fails
    Set op.Reader = ..Op()
    If maxTotal > 0 Set op.Reader.MaxTotal = maxTotal
    Set op.Adapter = ##class(Shutter.Test.FakeHttp).%New()
    Set request = ##class(Shutter.Msg.EvidenceRequest).%New()
    Set request.CaseId = case.CaseId
    Do $$$AssertStatusOK(op.OnEvidenceRequest(request, .response), "the evidence ran")
    Do $$$AssertEquals(response.Error, "", "with no error")
    If response.Error '= "" Quit ""
    Do case.%Reload()
    Quit ##class(%DynamicAbstractObject).%FromJSON(response.SummaryJSON)
}

/// A saved case of this class's receiver with its HL7 message behind it.
Method Case(visit As %String = {..#VISIT}, authority As %String = "HOSP") As Shutter.Store.Case
{
    Do $$$AssertStatusOK(..NewMessage($REPLACE(..#FHIRMSG, ..#VISIT, visit), .headerId), "the message is saved")
    Set caseId = "UT-FHIRRD-" _ $JOB _ "-" _ $INCREMENT(^||Shutter.Test.FHIRReader("n"))
    Do $$$AssertStatusOK(..NewCase(caseId, visit, ..#MRN, authority, ..#RECEIVER, headerId, .case), "the case is saved")
    Quit case
}

/// The paths of the requests the adapter saw, in order, each with its verb.
ClassMethod Log(http As Shutter.Test.FakeFhir) As %String
{
    Set out = ""
    For i = 1:1:+$GET(http.Requests) {
        Set out = out _ $SELECT(i > 1: " | ", 1: "") _ $LIST(http.Requests(i), 1) _ " " _ $LIST(http.Requests(i), 2)
    }
    Quit out
}

ClassMethod Parsed(text As %String) As %DynamicObject
{
    If text = "" Quit {}
    Quit ##class(%DynamicAbstractObject).%FromJSON(text)
}

/// The keys of an object, in its order.
ClassMethod Keys(obj As %DynamicObject) As %String
{
    Set out = "", it = obj.%GetIterator()
    While it.%GetNext(.key) { Set out = out _ $SELECT(out = "": "", 1: ",") _ key }
    Quit out
}

/// The entry of this class's FHIR receiver as the stored profile holds it.
ClassMethod Entry() As %DynamicObject
{
    Quit ##class(Shutter.Store.SiteProfile).Receiver(..#RECEIVER)
}

/// This class's FHIR receiver entry, with <var>patch</var> set over its fhir block.
ClassMethod FhirEntry(patch As %DynamicObject = "") As %DynamicObject
{
    Set entry = {"name": (..#RECEIVER), "system": "the ward system (FHIR R4)", "category": "current_state", "tier": 3, "applies": "arrival_order", "resend_timestamp": "original", "cancels": false, "merges": false, "fhir": {"base": (..#BASE), "recovery_enabled": true, "encounter_identifier": {"system": (..#SYS)}, "patient_identifier": {"system": (..#MRNSYS), "hl7_authority": "HOSP"}, "marker": {"system": (..#MARKER)}, "location_map": [{"ward": "WARD-A", "location": "Location/ward-a", "identifier": {"system": "urn:shutter:ward", "value": "WARD-A"}}, {"ward": "WARD-B", "location": "Location/ward-b", "identifier": {"system": "urn:shutter:ward", "value": "WARD-B"}}]}}
    If $ISOBJECT(patch) {
        Set it = patch.%GetIterator()
        While it.%GetNext(.key, .value) { Do entry.fhir.%Set(key, value) }
    }
    Quit entry
}

/// A receiver with a plain API of its own and a capabilities endpoint.
ClassMethod AdtEntry() As %DynamicObject
{
    Quit {"name": (..#ADTRECEIVER), "system": "a unit test's bed system", "category": "current_state", "tier": 2, "applies": "arrival_order", "resend_timestamp": "original", "cancels": false, "merges": false, "api": {"base": "/ut-adt-reader/api", "state": "/encounters/{encounter}", "receipt": "/receipts/{key}", "capabilities": "/capabilities", "operations": "/operations"}, "features": {"conditional_writes": true, "receipts": true, "history": true, "dry_run": true}}
}

/// Puts receivers into the stored profile, each in place of an earlier copy of the same name; every other entry stays.
/// The row as it was before the first call is kept for RestoreProfile.
ClassMethod PutReceivers(entries As %DynamicArray) As %Status
{
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    If '$DATA(^||Shutter.Test.FHIRReader("profile")) {
        Set ^||Shutter.Test.FHIRReader("profile") = $ISOBJECT(row)
        Set ^||Shutter.Test.FHIRReader("profile", "json") = $SELECT($ISOBJECT(row): row.Json, 1: "")
    }
    Set p = ##class(Shutter.Store.SiteProfile).Current()
    Set version = +p.version
    Do p.%Remove("version")
    Set it = entries.%GetIterator()
    While it.%GetNext(.i, .e) { Set names(e.name) = "" }
    Set kept = [], list = p.%Get("receivers")
    If $ISOBJECT(list) {
        Set it = list.%GetIterator()
        While it.%GetNext(.i, .r) { Do:'($ISOBJECT(r)&&(r.%Get("name")'="")&&$DATA(names(r.%Get("name")))) kept.%Push(r) }
    }
    Set it = entries.%GetIterator()
    While it.%GetNext(.i, .e) { Do kept.%Push(e) }
    Do p.%Set("receivers", kept)
    If '$ISOBJECT(row) Set row = ##class(Shutter.Store.SiteProfile).%New(), row.Name = "current", row.Version = version
    Set row.Json = p.%ToJSON()
    Quit row.%Save()
}

ClassMethod RestoreProfile()
{
    Quit:'$DATA(^||Shutter.Test.FHIRReader("profile"), had)
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    If 'had {
        If $ISOBJECT(row) Do ##class(Shutter.Store.SiteProfile).%DeleteId(row.%Id())
    } ElseIf $ISOBJECT(row) {
        Set row.Json = ^||Shutter.Test.FHIRReader("profile", "json")
        Do row.%Save()
    }
    Kill ^||Shutter.Test.FHIRReader("profile")
}

/// Saves an HL7 message with a header in front of it; both are removed by Cleanup.
ClassMethod NewMessage(text As %String, Output headerId As %String) As %Status
{
    Set headerId = ""
    Set msg = ##class(EnsLib.HL7.Message).ImportFromString($REPLACE(text, "<CR>", $CHAR(13)), .sc)
    Quit:$$$ISERR(sc) sc
    Do msg.PokeDocType("2.5.1:ADT_A02")
    Set sc = msg.%Save()
    Quit:$$$ISERR(sc) sc
    Set h = ##class(Ens.MessageHeader).%New()
    Set h.MessageBodyClassName = "EnsLib.HL7.Message", h.MessageBodyId = msg.%Id()
    Set sc = h.%Save()
    If $$$ISERR(sc) Do ##class(EnsLib.HL7.Message).%DeleteId(msg.%Id()) Quit sc
    Set headerId = h.%Id()
    Set ^||Shutter.Test.FHIRReader("hl7", headerId) = msg.%Id()
    Quit $$$OK
}

/// Saves a case of a failed transfer to WARD-B; it is purged by Cleanup.
ClassMethod NewCase(caseId As %String, visit As %String, patient As %String, authority As %String, receiver As %String, headerId As %String, Output case As Shutter.Store.Case) As %Status
{
    Set case = ##class(Shutter.Store.Case).%New()
    Set case.CaseId = caseId
    Set case.Event = "transfer", case.FailureKind = "delivery_failed", case.FailureText = "made up", case.EncounterId = visit
    Set case.PatientId = patient, case.PatientIdAuthority = authority, case.Receiver = receiver, case.State = "collecting", case.Mode = "rules"
    Set case.SourceSystem = "PAS", case.Ward = "WARD-B", case.EventTime = ..#EVENTTIME, case.SourceHeaderId = headerId
    Set case.OperationKey = "PAS^" _ authority _ "^" _ patient _ "^" _ visit _ "^transfer^" _ ..#EVENTTIME
    Set now = ##class(Shutter.Util.Time).NowUTC()
    Set case.OpenedAt = now, case.UpdatedAt = now
    Set sc = case.%Save()
    If $$$ISOK(sc) Set ^||Shutter.Test.FHIRReader("case", case.%Id()) = ""
    Quit sc
}

/// Removes every case, message and header this class saved, puts the profile back and empties the test FHIR server.
ClassMethod Cleanup()
{
    Set id = ""
    For {
        Set id = $ORDER(^||Shutter.Test.FHIRReader("case", id))
        Quit:id=""
        Do ##class(Shutter.Store.Case).PurgeCase(id)
    }
    Set id = ""
    For {
        Set id = $ORDER(^||Shutter.Test.FHIRReader("hl7", id), 1, body)
        Quit:id=""
        Do ##class(Ens.MessageHeader).%DeleteId(id)
        Do ##class(EnsLib.HL7.Message).%DeleteId(body)
    }
    Kill ^||Shutter.Test.FHIRReader("case"), ^||Shutter.Test.FHIRReader("hl7")
    Do ..RestoreProfile()
    If ..Loaded() Do $CLASSMETHOD(..#SERVICE, "Reset")
}

/// The collector's summary and items for a case of the plain receiver, as one JSON text with what changes from run
/// to run replaced by "*": the times of observation, the header's ids, the catalogue's answer and the precedents.
/// "" with <var>why</var> when the collection failed. <var>calls</var> is how often FHIR Receiver was asked. The
/// caller removes what was saved with Cleanup.
ClassMethod AdtDocument(Output why As %String, Output calls As %Integer) As %String
{
    Set why = "", calls = 0
    Set sc = ..PutReceivers([(..AdtEntry())])
    If $$$ISERR(sc) Set why = $SYSTEM.Status.GetErrorText(sc) Quit ""
    Set old = ##class(Shutter.Store.Case).ByCaseId(..#ADTCASE)
    If $ISOBJECT(old) {
        Set oldId = old.%Id()
        Kill old
        Do ##class(Shutter.Store.Case).PurgeCase(oldId)
    }
    Set sc = ..NewMessage(..#ADTMSG, .headerId)
    If $$$ISERR(sc) Set why = $SYSTEM.Status.GetErrorText(sc) Quit ""
    Set sc = ..NewCase(..#ADTCASE, "UTFR-ADT-V1", "MRN-UTFRA", "HOSP", ..#ADTRECEIVER, headerId, .case)
    If $$$ISERR(sc) Set why = $SYSTEM.Status.GetErrorText(sc) Quit ""
    Set op = ##class(Shutter.Test.QuietFHIREvidence).%New("Shutter Evidence (unit test)")
    Set op.SecondParserTarget = ""
    Set http = ##class(Shutter.Test.FakeHttp).%New()
    Set state = {"encounter_id": "UTFR-ADT-V1", "patient_id": "MRN-UTFRA", "patient_id_authority": "HOSP", "state": "admitted", "ward": "WARD-A", "bed": "", "version": 3, "epoch": "ut-epoch-1", "history": [{"event": "admit", "ward": "WARD-A", "event_time": "2026-11-07T08:00:00Z", "applied_at": "2026-11-07T08:00:05Z", "version_after": 1, "operation_key": "PAS^HOSP^MRN-UTFRA^UTFR-ADT-V1^admit^2026-11-07T08:00:00Z"}]}
    Set http.Answers("/encounters/") = $LISTBUILD(200, state.%ToJSON())
    Set http.Answers("/receipts/") = $LISTBUILD(404, "{""error"":""no_receipt""}")
    Set http.Answers("/capabilities") = $LISTBUILD(200, "{""conditional_writes"":true,""receipts"":true,""history"":true,""dry_run"":true,""epoch"":""ut-epoch-1""}")
    Set op.Adapter = http
    Set request = ##class(Shutter.Msg.EvidenceRequest).%New()
    Set request.CaseId = case.CaseId
    Set sc = op.OnEvidenceRequest(request, .response)
    If $$$ISERR(sc) Set why = $SYSTEM.Status.GetErrorText(sc) Quit ""
    If response.Error '= "" Set why = response.Error Quit ""
    Set calls = op.Calls
    Set summary = ##class(%DynamicAbstractObject).%FromJSON(response.SummaryJSON)
    For key = "catalogue", "precedents" {
        If summary.%IsDefined(key) Do summary.%Set(key, "*", "string")
    }
    Set doc = {}
    Set doc.summary = summary
    Set items = [], snap = ##class(Shutter.Store.Snapshot).%OpenId(response.SnapshotId)
    Set it = snap.Items().%GetIterator()
    While it.%GetNext(.i, .item) {
        Do items.%Push({"kind": (item.kind), "source": (item.source), "data": (item.data)})
    }
    Set doc.items = items
    Do ..Normalise(doc)
    Quit doc.%ToJSON()
}

/// Replaces what changes from run to run by "*", at any depth.
ClassMethod Normalise(node As %DynamicAbstractObject)
{
    Set volatile = $LISTBUILD("observed_at", "fresh_until", "received_at", "ens_session_id", "source_header_id")
    Set isObject = node.%IsA("%Library.DynamicObject")
    Set it = node.%GetIterator()
    While it.%GetNext(.key, .value) {
        If $ISOBJECT(value) {
            Do ..Normalise(value)
        } ElseIf isObject && $LISTFIND(volatile, key) {
            Do node.%Set(key, "*", "string")
        }
    }
}

/// The plain receiver's document as main's code gave it: see TestAnAdtSummaryIsByteForByteAsBefore.
XData Adt [ MimeType = application/json ]
{
{
 "summary": {
  "case_id": "UT-FHIRRD-ADT",
  "scenario": "",
  "operation": {
   "operation_key": "PAS^HOSP^MRN-UTFRA^UTFR-ADT-V1^transfer^2026-11-07T10:30:00Z",
   "encounter_id": "UTFR-ADT-V1",
   "patient_id": "MRN-UTFRA",
   "patient_id_authority": "HOSP",
   "event": "transfer",
   "ward": "WARD-B",
   "bed": null,
   "event_time": "2026-11-07T10:30:00Z",
   "source_system": "PAS",
   "source_message_id": "",
   "payload_digest": "sha256:68cb8268d1f3a7662b13d4d50bab909ccea1094ba90569301c18fd96c8f6cda1"
  },
  "failure": {
   "kind": "delivery_failed",
   "text": "made up",
   "ens_session_id": "*",
   "source_header_id": "*"
  },
  "message": {
   "message_control_id": "UTFRA1",
   "message_type": "ADT^A02",
   "sending_application": "PAS",
   "sending_facility": "HOSP",
   "receiving_application": "WARDSYS",
   "received_at": "*",
   "message_time": "2026-11-07T10:30:00Z",
   "hl7_version": "2.5.1",
   "message_version": "2.5.1",
   "event_recorded": "2026-11-07T10:30:00Z",
   "event_occurred": "2026-11-07T10:30:00Z",
   "event_time_had_offset": false,
   "patient_identifier": "MRN-UTFRA^^^HOSP^MR",
   "patient_name": "TESTER, TOBY",
   "patient_class": "I",
   "death_recorded": "no",
   "assigned_location": "WARD-B^^^HOSP",
   "visit_number": "UTFR-ADT-V1",
   "admit_time": "",
   "times_without_offset": 3,
   "times_with_offset": 0,
   "feed_time_zone": "Europe/London",
   "notes": [],
   "segment_count": 4,
   "doc_type": "2.5.1:ADT_A02"
  },
  "validation": {
   "parsed": true,
   "doc_type": "2.5.1:ADT_A02",
   "schema_category": "2.5.1",
   "spec": "dm",
   "schema_known": true,
   "note": "Structural validation against the 2.5.1 schema (document type and segment structure); profile rules are the conformance review's job",
   "message_version": "2.5.1",
   "route_category": "2.5.1",
   "route_standard": "2.5.1",
   "version_agrees": true
  },
  "ward_state": {
   "encounter_id": "UTFR-ADT-V1",
   "patient_id": "MRN-UTFRA",
   "patient_id_authority": "HOSP",
   "state": "admitted",
   "ward": "WARD-A",
   "bed": "",
   "version": 3,
   "epoch": "ut-epoch-1",
   "history": [
    {
     "event": "admit",
     "ward": "WARD-A",
     "event_time": "2026-11-07T08:00:00Z",
     "applied_at": "2026-11-07T08:00:05Z",
     "version_after": 1,
     "operation_key": "PAS^HOSP^MRN-UTFRA^UTFR-ADT-V1^admit^2026-11-07T08:00:00Z"
    }
   ]
  },
  "ward_state_http_status": 200,
  "receipt": {
   "error": "no_receipt"
  },
  "receipt_http_status": 404,
  "timeline": [],
  "later_events": 0,
  "pending_messages": [],
  "further_messages": {
   "identifier": "read",
   "stops": [],
   "shows": [],
   "unread": ""
  },
  "route": {
   "feed": "ADT In -> ADT to Downstream -> UT ADT Reader Out",
   "connector": "UT ADT Reader Out",
   "receiver": "a unit test's bed system (/ut-adt-reader/api)",
   "tier": 2,
   "category": "current_state",
   "history_policy": "current",
   "capabilities_source": "read from /ut-adt-reader/api/capabilities",
   "declared": {
    "conditional_writes": true,
    "receipts": true,
    "history": true,
    "dry_run": true
   },
   "capabilities_http_status": 200,
   "capabilities": {
    "conditional_writes": true,
    "receipts": true,
    "history": true,
    "dry_run": true,
    "epoch": "ut-epoch-1"
   },
   "conditional_writes": true,
   "receipts": true,
   "history": true,
   "dry_run": true,
   "epoch": "ut-epoch-1"
  },
  "epoch": "ut-epoch-1",
  "observed_at": "*",
  "incident": {},
  "catalogue": "*",
  "precedents": "*",
  "fresh_until": "*"
 },
 "items": [
  {
   "kind": "operation",
   "source": "production",
   "data": {
    "operation_key": "PAS^HOSP^MRN-UTFRA^UTFR-ADT-V1^transfer^2026-11-07T10:30:00Z",
    "encounter_id": "UTFR-ADT-V1",
    "patient_id": "MRN-UTFRA",
    "patient_id_authority": "HOSP",
    "event": "transfer",
    "ward": "WARD-B",
    "bed": null,
    "event_time": "2026-11-07T10:30:00Z",
    "source_system": "PAS",
    "source_message_id": "",
    "payload_digest": "sha256:68cb8268d1f3a7662b13d4d50bab909ccea1094ba90569301c18fd96c8f6cda1"
   }
  },
  {
   "kind": "error",
   "source": "production",
   "data": {
    "kind": "delivery_failed",
    "text": "made up",
    "ens_session_id": "*",
    "source_header_id": "*"
   }
  },
  {
   "kind": "message",
   "source": "message_store",
   "data": {
    "message_control_id": "UTFRA1",
    "message_type": "ADT^A02",
    "sending_application": "PAS",
    "sending_facility": "HOSP",
    "receiving_application": "WARDSYS",
    "received_at": "*",
    "message_time": "2026-11-07T10:30:00Z",
    "hl7_version": "2.5.1",
    "message_version": "2.5.1",
    "event_recorded": "2026-11-07T10:30:00Z",
    "event_occurred": "2026-11-07T10:30:00Z",
    "event_time_had_offset": false,
    "patient_identifier": "MRN-UTFRA^^^HOSP^MR",
    "patient_name": "TESTER, TOBY",
    "patient_class": "I",
    "death_recorded": "no",
    "assigned_location": "WARD-B^^^HOSP",
    "visit_number": "UTFR-ADT-V1",
    "admit_time": "",
    "times_without_offset": 3,
    "times_with_offset": 0,
    "feed_time_zone": "Europe/London",
    "notes": [],
    "segment_count": 4,
    "doc_type": "2.5.1:ADT_A02"
   }
  },
  {
   "kind": "validation",
   "source": "validator",
   "data": {
    "parsed": true,
    "doc_type": "2.5.1:ADT_A02",
    "schema_category": "2.5.1",
    "spec": "dm",
    "schema_known": true,
    "note": "Structural validation against the 2.5.1 schema (document type and segment structure); profile rules are the conformance review's job",
    "message_version": "2.5.1",
    "route_category": "2.5.1",
    "route_standard": "2.5.1",
    "version_agrees": true
   }
  },
  {
   "kind": "ward_state",
   "source": "ward_api",
   "data": {
    "http_status": 200,
    "body": {
     "encounter_id": "UTFR-ADT-V1",
     "patient_id": "MRN-UTFRA",
     "patient_id_authority": "HOSP",
     "state": "admitted",
     "ward": "WARD-A",
     "bed": "",
     "version": 3,
     "epoch": "ut-epoch-1",
     "history": [
      {
       "event": "admit",
       "ward": "WARD-A",
       "event_time": "2026-11-07T08:00:00Z",
       "applied_at": "2026-11-07T08:00:05Z",
       "version_after": 1,
       "operation_key": "PAS^HOSP^MRN-UTFRA^UTFR-ADT-V1^admit^2026-11-07T08:00:00Z"
      }
     ]
    }
   }
  },
  {
   "kind": "receipt",
   "source": "ward_api",
   "data": {
    "http_status": 404,
    "body": {
     "error": "no_receipt"
    }
   }
  },
  {
   "kind": "pending_messages",
   "source": "message_store",
   "data": {
    "items": [],
    "count": 0
   }
  },
  {
   "kind": "further_messages",
   "source": "message_store",
   "data": {
    "identifier": "read",
    "stops": [],
    "shows": [],
    "unread": ""
   }
  },
  {
   "kind": "route",
   "source": "ward_api",
   "data": {
    "feed": "ADT In -> ADT to Downstream -> UT ADT Reader Out",
    "connector": "UT ADT Reader Out",
    "receiver": "a unit test's bed system (/ut-adt-reader/api)",
    "tier": 2,
    "category": "current_state",
    "history_policy": "current",
    "capabilities_source": "read from /ut-adt-reader/api/capabilities",
    "declared": {
     "conditional_writes": true,
     "receipts": true,
     "history": true,
     "dry_run": true
    },
    "capabilities_http_status": 200,
    "capabilities": {
     "conditional_writes": true,
     "receipts": true,
     "history": true,
     "dry_run": true,
     "epoch": "ut-epoch-1"
    },
    "conditional_writes": true,
    "receipts": true,
    "history": true,
    "dry_run": true,
    "epoch": "ut-epoch-1"
   }
  }
 ]
}
}

}
