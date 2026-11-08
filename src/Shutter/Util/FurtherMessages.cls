/// Further messages for the patient, read immediately before a write (CONTRACTS 6.5): any message for this patient that
/// reached the engine after the case's own, or is timed after it, on any visit, in Shutter's namespace and the namespace the
/// case came from, whatever became of it. ResendGuard and the matcher read one visit; this reads the patient. Find gathers
/// the rows and Classify, which is pure so a test runs it without a message store, weighs them:
/// - stops: an in-patient movement on another visit (a clerk may be working round bad history, and Shutter can't say which
///   visit is real, so both are named for a person), a change to the record itself, a cancel or merge of this visit that the
///   receiver did not apply, for an admission outside a chain a discharge the receiver did not apply, and a later A08 on this
///   visit naming another ward or bed than the failed movement's target (an update carries no location, so it moved nobody at
///   the receiver and the older movement only looks current).
/// - shows: anything else about the patient in the ADT feed, such as an out-patient attendance or an emergency department's
///   discharge. It stops nothing and goes on the plan.
/// The site profile's further_messages.in_patient_movement says show to let another visit's movement through, and
/// further_messages.a08_location the same for that A08, for a site that repeats stale locations on full-state A08s. The gate reads
/// the snapshot at the proposal and reads again at dispatch, and the connector reads again at the moment of the write. A person
/// with Shutter_Approve can release a stop that is only another visit's movement, for the rows they read (Release, Released).
/// What this can't see: a change made by hand at the receiver, which is why a lost admission's plan asks for its screen to be
/// checked. A later hold of the feed or of a laboratory route can call Find as it stands.
Class Shutter.Util.FurtherMessages
{

/// How many HL7 headers a read of a namespace takes at a time. It goes on to the last header, or until the site's
/// further_messages.scan_seconds run out, and a read that runs out with headers left is not whole, which blocks a write.
Parameter SCANPAGE = 2000;

/// What is known about the case's patient and further messages: {identifier: read or unreadable, stops: [...], shows: [...],
/// unread: why a namespace could not be read in full, or ""}. Never throws: a read that fails is unread, and blocks a write.
ClassMethod Find(case As Shutter.Store.Case) As %DynamicObject
{
    Set subject = ..Subject(case), rows = [], unread = "", since = ""
    Try {
        Set since = ##class(Shutter.Util.ResendGuard).SinceOf(case)
        If case.PatientId '= "" {
            Do ..Same(case, rows)
            Do ..Indexed(case, rows)
            // The newest headers Shutter's index has not walked yet: it runs a few seconds behind.
            // Read here: the source namespace has the class but not this namespace's profile.
            Set seconds = ##class(Shutter.Store.SiteProfile).FurtherScanSeconds()
            Set more = ..Scan(case, +$GET(^Shutter.Index("hwm"), 0), since, .full, seconds)
            Do ..Add(rows, more)
            If 'full Set unread = ..NotWhole($NAMESPACE, seconds)
            If (case.SourceNamespace '= "") && (case.SourceNamespace '= $NAMESPACE) {
                Set unreadThere = ..ReadSource(case, since, rows, seconds)
                If unreadThere '= "" Set unread = $SELECT(unread '= "": unread _ "; ", 1: "") _ unreadThere
            }
        }
    } Catch ex {
        Set unread = "the check itself failed: " _ $EXTRACT(ex.DisplayString(), 1, 200)
    }
    Quit ..Classify(subject, rows, ##class(Shutter.Store.ChainItem).KindFor(case), since, ##class(Shutter.Store.SiteProfile).FurtherMovement(), unread, ##class(Shutter.Store.SiteProfile).FurtherA08Location())
}

ClassMethod Subject(case As Shutter.Store.Case) As %DynamicObject [ Private ]
{
    Set s = {}
    Set s."encounter_id" = case.EncounterId, s."patient_id" = case.PatientId, s."patient_id_authority" = case.PatientIdAuthority
    Set s.event = case.Event, s."event_time" = case.EventTime, s."operation_key" = case.OperationKey, s."control_id" = case.SourceMessageId
    Set s.ward = case.Ward, s.bed = case.Bed
    Quit s
}

/// The answers for this visit: which of its messages were delivered to this receiver, in Shutter and the source namespace.
ClassMethod Same(case As Shutter.Store.Case, rows As %DynamicArray) [ Private ]
{
    Set json = "Shutter.Util.Json"
    Set deliveries = ##class(Shutter.Index.Timeline).Deliveries(case.EncounterId, case.Receiver, case.SourceNamespace), di = deliveries.%GetIterator()
    While di.%GetNext(, .d) {
        Set r = {}
        Set r.event = $CLASSMETHOD(json, "Str", d, "event"), r."visit_number" = case.EncounterId, r."control_id" = $CLASSMETHOD(json, "Str", d, "source_message_id")
        Set r."event_time" = $CLASSMETHOD(json, "Str", d, "event_time"), r."sent_at" = $CLASSMETHOD(json, "Str", d, "sent_at"), r."operation_key" = $CLASSMETHOD(json, "Str", d, "operation_key")
        Set r.outcome = $CLASSMETHOD(json, "Str", d, "outcome", "unknown"), r.where = "sent to the receiver" _ $SELECT(r.outcome = "unknown": ", no answer yet", 1: ", answered " _ r.outcome)
        Do rows.%Push(r)
    }
}

/// Shutter's index: the patient's rows and any merge that names the patient as its prior record.
ClassMethod Indexed(case As Shutter.Store.Case, rows As %DynamicArray) [ Private ]
{
    Set json = "Shutter.Util.Json"
    Set resetAt = $GET(^Shutter.Config("resetAt"))
    Set low = $SELECT(resetAt = "": "2000-01-01 00:00:00", 1: $TRANSLATE($PIECE(resetAt, "Z", 1), "T", " "))
    Set found = ##class(Shutter.Index.Message).ForPatient(case.PatientId, low), fi = found.%GetIterator()
    While fi.%GetNext(, .r) {
        // The index holds no patient class, and a movement's class decides whether it stops. Nor does it hold a bed, and an
        // A08 on this visit or a movement it may repeat is compared by ward and bed.
        Set word = $CLASSMETHOD(json, "Str", r, "event")
        If $LISTFIND($LISTBUILD("register", "preadmit", "admit", "transfer", "discharge", "cancel_admit", "cancel_transfer", "cancel_discharge"), word) || ((word = "update") && ($CLASSMETHOD(json, "Str", r, "visit_number") = case.EncounterId)) {
            Set body = ##class(EnsLib.HL7.Message).%OpenId($CLASSMETHOD(json, "Str", r, "message_body_id"))
            If $ISOBJECT(body) {
                Set r."patient_class" = ##class(Shutter.Util.OperationKey).Value(body, "PV1", "2")
                Set r.location = ##class(Shutter.Util.OperationKey).Value(body, "PV1", "3.1"), r.bed = ..BedIn(body)
            }
        }
        Set r.where = "received"
        Do rows.%Push(r)
    }
    Set merges = ##class(Shutter.Index.Message).MergesSince(low), mi = merges.%GetIterator()
    While mi.%GetNext(, .r) {
        Set body = ##class(EnsLib.HL7.Message).%OpenId($CLASSMETHOD(json, "Str", r, "message_body_id"))
        Continue:'$ISOBJECT(body)
        Set op = ##class(Shutter.Util.OperationKey).FromHL7(body, .osc)
        Continue:'$ISOBJECT(op)
        Set r."prior_patient_id" = $CLASSMETHOD(json, "Str", op, "prior_patient_id"), r."prior_patient_id_authority" = $CLASSMETHOD(json, "Str", op, "prior_patient_id_authority")
        Set r.where = "received"
        Do rows.%Push(r)
    }
}

/// The namespace the case came from: its HL7 messages since the case's own, which no index of Shutter's covers (INSTALL 3.3).
/// Returns why it could not be read in full, or "".
ClassMethod ReadSource(case As Shutter.Store.Case, since As %String, rows As %DynamicArray, seconds As %Integer) As %String [ Private ]
{
    Set out = ""
    Try {
        // An onboarded namespace maps Shutter.Intake and Shutter.Util only, so the feed's zone is read here, before the move.
        Set ^||Shutter.FeedZone = ##class(Shutter.Store.SiteProfile).FeedTimeZone()
        New $NAMESPACE
        Set $NAMESPACE = case.SourceNamespace
        Set from = since, hid = case.OriginHeaderId, t = ""
        If hid '= "" {
            &sql(SELECT TimeCreated INTO :t FROM Ens.MessageHeader WHERE ID = :hid)
            If (SQLCODE = 0) && (t '= "") Set from = t
        }
        // Header ids only grow, so the walk starts at the case's own and never reads the namespace's history.
        Set more = ..Scan(case, +hid, from, .full, seconds)
        Set mi = more.%GetIterator()
        While mi.%GetNext(, .r) { Set r.namespace = case.SourceNamespace, r.where = "received in " _ case.SourceNamespace Do rows.%Push(r) }
        If 'full Set out = ..NotWhole(case.SourceNamespace, seconds)
    } Catch ex {
        Set out = case.SourceNamespace _ " could not be read: " _ $EXTRACT(ex.DisplayString(), 1, 200)
    }
    Kill ^||Shutter.FeedZone
    Quit out
}

/// The HL7 messages in this namespace after a header id and since a time, read from the messages themselves: only this
/// patient's, by identifier or as a merge's prior record. It pages on to the last header, so a case's age and a busy feed cost
/// time and nothing else; full is 0 when seconds ran out with headers left.
ClassMethod Scan(case As Shutter.Store.Case, afterId As %Integer, since As %String, Output full As %Boolean, seconds As %Integer = "") As %DynamicArray
{
    Set out = [], full = 1, last = +afterId
    Set deadline = $ZHOROLOG + $SELECT(seconds = "": ##class(Shutter.Store.SiteProfile).#SCANSECONDS, 1: seconds)
    Set sql = "SELECT TOP " _ ..#SCANPAGE _ " ID, MessageBodyId, TimeCreated FROM Ens.MessageHeader WHERE MessageBodyClassName = 'EnsLib.HL7.Message' AND ID > ? AND TimeCreated >= ? ORDER BY ID"
    For {
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, sql, last, since), walked = 0
        While rs.%Next() {
            Set walked = walked + 1, last = rs.%Get("ID")
            Set bodyId = rs.%Get("MessageBodyId")
            Continue:$DATA(seen(bodyId))
            Set seen(bodyId) = ""
            Set body = ##class(EnsLib.HL7.Message).%OpenId(bodyId)
            Continue:'$ISOBJECT(body)
            Set id = ##class(Shutter.Util.OperationKey).PatientIdentifier(body, .authority)
            Set trigger = $ZCONVERT(##class(Shutter.Util.OperationKey).Value(body, "MSH", "9.2"), "U"), event = ##class(Shutter.Util.OperationKey).EventForTrigger(trigger)
            Continue:((id '= case.PatientId) && (event '= "merge"))
            Set r = ..RowOf(body, id, authority, trigger, event)
            Set r."ens_header_id" = rs.%Get("ID"), r."sent_at" = rs.%Get("TimeCreated"), r.where = "received"
            Do out.%Push(r)
        }
        Quit:walked<..#SCANPAGE
        If $ZHOROLOG >= deadline Set full = 0 Quit
    }
    Quit out
}

/// Why a read isn't whole, for a person and for the site that can change it.
ClassMethod NotWhole(namespace As %String, seconds As %Integer) As %String
{
    Quit "the read of " _ namespace _ " ran out of its " _ seconds _ " seconds with messages left (further_messages.scan_seconds)"
}

ClassMethod RowOf(body As EnsLib.HL7.Message, id As %String, authority As %String, trigger As %String, event As %String) As %DynamicObject [ Private ]
{
    Set json = "Shutter.Util.Json", r = {}
    Set op = ##class(Shutter.Util.OperationKey).FromHL7(body, .osc)
    Set hasOp = $ISOBJECT(op) && $$$ISOK($GET(osc, 1))
    Set r."patient_id" = id, r."patient_id_authority" = authority
    Set r."message_type" = ##class(Shutter.Util.OperationKey).Value(body, "MSH", "9.1") _ "_" _ trigger
    Set r.event = $SELECT(hasOp: $CLASSMETHOD(json, "Str", op, "event"), event '= "": event, 1: trigger)
    Set r."visit_number" = ##class(Shutter.Util.OperationKey).Value(body, "PV1", "19.1"), r."patient_class" = ##class(Shutter.Util.OperationKey).Value(body, "PV1", "2")
    Set r.location = ##class(Shutter.Util.OperationKey).Value(body, "PV1", "3.1"), r.bed = ..BedIn(body), r."control_id" = ##class(Shutter.Util.OperationKey).Value(body, "MSH", "10")
    Set r."event_time" = $SELECT(hasOp: $CLASSMETHOD(json, "Str", op, "event_time"), 1: ##class(Shutter.Util.Time).FromHL7(##class(Shutter.Util.OperationKey).Value(body, "EVN", "2.1")))
    If hasOp Set r."operation_key" = $CLASSMETHOD(json, "Str", op, "operation_key"), r."prior_patient_id" = $CLASSMETHOD(json, "Str", op, "prior_patient_id"), r."prior_patient_id_authority" = $CLASSMETHOD(json, "Str", op, "prior_patient_id_authority")
    Quit r
}

/// The bed PV1-3 names, as the operation key's reader names it.
ClassMethod BedIn(body As EnsLib.HL7.Message) As %String [ Private ]
{
    Quit ##class(Shutter.Util.OperationKey).BedOf(##class(Shutter.Util.OperationKey).Value(body, "PV1", "3.2"), ##class(Shutter.Util.OperationKey).Value(body, "PV1", "3.3"))
}

ClassMethod Add(rows As %DynamicArray, more As %DynamicArray) [ Private ]
{
    Set mi = more.%GetIterator()
    While mi.%GetNext(, .r) { Do rows.%Push(r) }
}

/// Weighs the rows for a subject {encounter_id, patient_id, patient_id_authority, event, event_time, operation_key,
/// control_id, ward, bed}. A row counts when it is this patient's, by identifier and authority, or a merge that names the patient as its
/// prior record; an authority missing on either side can't tell two patients apart, so the row counts and a person reads it.
/// It must have reached the engine after since, or be timed after the case's event, and not be the case's own message. The
/// first row of a control id and visit wins, so pass the deliveries first: their answers say what the receiver applied.
ClassMethod Classify(subject As %DynamicObject, rows As %DynamicArray, chainKind As %String = "single", since As %String = "", movement As %String = "stop", unread As %String = "", a08 As %String = "stop") As %DynamicObject
{
    Set json = "Shutter.Util.Json", out = {}, stops = [], shows = []
    Set id = $CLASSMETHOD(json, "Str", subject, "patient_id"), authority = $CLASSMETHOD(json, "Str", subject, "patient_id_authority")
    Set visit = $CLASSMETHOD(json, "Str", subject, "encounter_id"), key = $CLASSMETHOD(json, "Str", subject, "operation_key"), own = $CLASSMETHOD(json, "Str", subject, "control_id")
    Set event = $CLASSMETHOD(json, "Str", subject, "event"), eventTime = $CLASSMETHOD(json, "Str", subject, "event_time")
    Set single = (chainKind = "") || (chainKind = "single")
    Set readable = (id '= "") && (id '= "-")
    Set out.identifier = $SELECT(readable: "read", 1: "unreadable")
    If readable && $ISOBJECT(rows) {
        Do ..Places(rows, visit, .places, .moves)
        Set ri = rows.%GetIterator()
        While ri.%GetNext(, .r) {
            Continue:'$ISOBJECT(r)
            Set rowVisit = $CLASSMETHOD(json, "Str", r, "visit_number"), control = $CLASSMETHOD(json, "Str", r, "control_id"), rowKey = $CLASSMETHOD(json, "Str", r, "operation_key")
            Continue:((control '= "") && (control = own))
            Continue:((rowKey '= "") && (rowKey = key))
            If control '= "" {
                Continue:$DATA(seen(control, "v" _ rowVisit))
                Set seen(control, "v" _ rowVisit) = ""
            }
            Continue:'..SamePatient(r, id, authority, rowVisit = visit)
            Set sent = $CLASSMETHOD(json, "Str", r, "sent_at"), time = $CLASSMETHOD(json, "Str", r, "event_time")
            Continue:'((sent ]] since) || (time ]] eventTime))
            Set why = ..Weigh(r, rowVisit = visit, event, single)
            Set place = ""
            If (why = "") && (rowVisit = visit) {
                Set place = ..A08Place(r, .places)
                If ..A08Moved(place, subject, time, .moves) Set why = $SELECT(a08 = "show": "a08_location_shown", 1: "a08_location")
            }
            Continue:(why = "")
            // A pre-admission on file before the case is a date on a waiting list, not a move.
            If (why = "other_visit") && ($CLASSMETHOD(json, "Str", r, "event") = "preadmit") && '(sent ]] since) Set why = "shown"
            Set item = {}
            Set item.why = why, item.event = $CLASSMETHOD(json, "Str", r, "event"), item."message_type" = $CLASSMETHOD(json, "Str", r, "message_type"), item."visit_number" = rowVisit
            Set item."event_time" = time, item."sent_at" = sent, item."control_id" = control, item.location = $CLASSMETHOD(json, "Str", r, "location"), item.where = $CLASSMETHOD(json, "Str", r, "where")
            If $EXTRACT(why, 1, 3) = "a08" Set item.location = $LIST(place, 1), item.bed = $LIST(place, 2), item."message_type" = "ADT_A08"
            If ((why = "other_visit") && (movement = "show")) || (why = "shown") || (why = "a08_location_shown") { Do shows.%Push(item) } Else { Do stops.%Push(item) }
        }
    }
    Set out.stops = stops, out.shows = shows, out.unread = unread
    Quit out
}

/// Where this visit's messages say the patient is, from the rows read from the messages: places(control id) for each A08,
/// since the first row of a control id wins and a delivery's knows no PV1-3, and moves(n) for each movement an A08 may repeat.
ClassMethod Places(rows As %DynamicArray, visit As %String, Output places, Output moves) [ Private ]
{
    Set json = "Shutter.Util.Json", moves = 0, ri = rows.%GetIterator()
    While ri.%GetNext(, .r) {
        Continue:'$ISOBJECT(r)
        Continue:($CLASSMETHOD(json, "Str", r, "visit_number") '= visit)
        Set ward = $CLASSMETHOD(json, "Str", r, "location"), bed = $CLASSMETHOD(json, "Str", r, "bed")
        Continue:((ward = "") && (bed = ""))
        Set type = $CLASSMETHOD(json, "Str", r, "message_type"), control = $CLASSMETHOD(json, "Str", r, "control_id"), word = $CLASSMETHOD(json, "Str", r, "event")
        If (type = "ADT_A08") && (control '= "") Set places(control) = $LISTBUILD(ward, bed)
        If (word = "admit") || (word = "transfer") Set moves($INCREMENT(moves)) = $LISTBUILD(ward, bed, $CLASSMETHOD(json, "Str", r, "event_time"))
    }
}

/// The ward and bed a row's A08 names, as a list, or "" when the row is no A08 or names no location.
ClassMethod A08Place(r As %DynamicObject, ByRef places) As %String [ Private ]
{
    Set json = "Shutter.Util.Json", type = $CLASSMETHOD(json, "Str", r, "message_type"), control = $CLASSMETHOD(json, "Str", r, "control_id")
    If $CLASSMETHOD(json, "Str", r, "event") '= "update" Quit ""
    If (type '= "") && (type '= "ADT_A08") Quit ""
    If (control '= "") && $DATA(places(control)) Quit places(control)
    Set ward = $CLASSMETHOD(json, "Str", r, "location"), bed = $CLASSMETHOD(json, "Str", r, "bed")
    If (type = "") || ((ward = "") && (bed = "")) Quit ""
    Quit $LISTBUILD(ward, bed)
}

/// Whether an A08's place counts as a further movement of the subject's: the subject has a target (a failed admission or
/// transfer), the A08 is not timed before it, it names another ward or bed, and no movement of this visit timed between the
/// two is what it repeats, since that movement is weighed by its own rule. An A08 naming where the patient was before the failed
/// movement counts: Shutter can't tell a move back from a stale location, and the site can choose show.
ClassMethod A08Moved(place As %String, subject As %DynamicObject, time As %String, ByRef moves) As %Boolean [ Private ]
{
    If place = "" Quit 0
    Set json = "Shutter.Util.Json", event = $CLASSMETHOD(json, "Str", subject, "event"), target = $CLASSMETHOD(json, "Str", subject, "ward")
    If ((event '= "admit") && (event '= "transfer")) || (target = "") Quit 0
    Set own = $CLASSMETHOD(json, "Str", subject, "event_time")
    If own ]] time Quit 0
    If '..LocationDiffers($LIST(place, 1), $LIST(place, 2), target, $CLASSMETHOD(json, "Str", subject, "bed")) Quit 0
    For n = 1:1:$GET(moves, 0) {
        Set when = $LIST(moves(n), 3)
        Continue:((own ]] when) || (when ]] time))
        If '..LocationDiffers($LIST(place, 1), $LIST(place, 2), $LIST(moves(n), 1), $LIST(moves(n), 2)) Return 0
    }
    Quit 1
}

/// Whether a message's PV1-3 says another place than a given ward and bed, compared as OperationKey reads them (PV1-3.1, and
/// room-bed by BedOf). A part the message leaves empty says nothing: a ward-level A08 says nothing about the bed. A bed it names
/// differs from another bed, and from no bed.
ClassMethod LocationDiffers(ward As %String, bed As %String, otherWard As %String, otherBed As %String) As %Boolean
{
    Quit ((ward '= "") && (ward '= otherWard)) || ((bed '= "") && (bed '= otherBed))
}

/// Whether a row is this patient's. A row of this visit with no identifier is a delivery, read by the visit.
ClassMethod SamePatient(r As %DynamicObject, id As %String, authority As %String, sameVisit As %Boolean) As %Boolean [ Private ]
{
    Set json = "Shutter.Util.Json"
    Set rowId = $CLASSMETHOD(json, "Str", r, "patient_id"), rowAuth = $CLASSMETHOD(json, "Str", r, "patient_id_authority")
    If (rowId = "") && sameVisit Quit 1
    If (rowId = id) && ((rowAuth = "") || (authority = "") || (rowAuth = authority)) Quit 1
    Set prior = $CLASSMETHOD(json, "Str", r, "prior_patient_id"), priorAuth = $CLASSMETHOD(json, "Str", r, "prior_patient_id_authority")
    Quit (prior '= "") && (prior = id) && ((priorAuth = "") || (authority = "") || (priorAuth = authority))
}

/// Why a row matters: other_visit, record_changed, cancel, merge, discharge (each stops), shown, or "" when it doesn't. An A08
/// on this visit that names another place is weighed apart (A08Moved), since it stops whatever became of it.
ClassMethod Weigh(r As %DynamicObject, sameVisit As %Boolean, caseEvent As %String, single As %Boolean) As %String [ Private ]
{
    Set json = "Shutter.Util.Json"
    Set word = $CLASSMETHOD(json, "Str", r, "event"), type = $CLASSMETHOD(json, "Str", r, "message_type"), outcome = $CLASSMETHOD(json, "Str", r, "outcome")
    Set trigger = $SELECT(type [ "_": $PIECE(type, "_", 2), 1: word)
    // A record deleted, renumbered, or a class changed between out-patient and in-patient.
    Set changes = $LISTFIND($LISTBUILD("A06", "A07", "A23", "A29", "A37", "A44", "A45", "A47", "A49", "A50", "A51"), trigger) > 0
    If sameVisit {
        // What the receiver applied is history: the matcher and the gate's ordering check read it.
        Quit:((outcome = "applied") || (outcome = "already_committed")) ""
        If changes Quit "record_changed"
        If $EXTRACT(word, 1, 7) = "cancel_" Quit "cancel"
        If word = "merge" Quit "merge"
        If (word = "discharge") && (caseEvent = "admit") && single Quit "discharge"
        Quit ""
    }
    If changes Quit "record_changed"
    If word = "merge" Quit "merge"
    Set class = $ZCONVERT($CLASSMETHOD(json, "Str", r, "patient_class"), "U")
    // In-patient moves stop. One that says it is an emergency or out-patient one moves no in-patient; any other class, or none, can't be told from one.
    If $LISTFIND($LISTBUILD("admit", "transfer", "discharge", "cancel_admit", "cancel_transfer", "cancel_discharge"), word) Quit $SELECT($LISTFIND($LISTBUILD("E", "O"), class): "shown", 1: "other_visit")
    If $LISTFIND($LISTBUILD("register", "preadmit"), word) && (class = "I") Quit "other_visit"
    If (type '= "") && ($EXTRACT(type, 1, 4) '= "ADT_") Quit ""
    Quit "shown"
}

ClassMethod Count(found, list As %String) As %Integer
{
    If '$ISOBJECT(found) Quit 0
    Set items = found.%Get(list)
    Quit $SELECT($ISOBJECT(items): items.%Size(), 1: 0)
}

/// Whether the case's patient identifier could not be read.
ClassMethod Unreadable(found) As %Boolean
{
    Quit $ISOBJECT(found) && (##class(Shutter.Util.Json).Str(found, "identifier") = "unreadable")
}

ClassMethod Unread(found) As %String
{
    Quit $SELECT($ISOBJECT(found): ##class(Shutter.Util.Json).Str(found, "unread"), 1: "")
}

/// One sentence for a person about a row, naming the case's own visit beside it.
ClassMethod Line(case As Shutter.Store.Case, item As %DynamicObject) As %String
{
    Set json = "Shutter.Util.Json"
    Set why = $CLASSMETHOD(json, "Str", item, "why"), visit = $CLASSMETHOD(json, "Str", item, "visit_number")
    Set type = $CLASSMETHOD(json, "Str", item, "message_type")
    Set what = ..Word($CLASSMETHOD(json, "Str", item, "event")) _ $SELECT(type '= "": " (" _ type _ ")", 1: "") _ $SELECT(visit '= "": " on visit " _ visit, 1: " with no visit number")
    Set what = what _ " timed " _ $CLASSMETHOD(json, "Str", item, "event_time") _ ", control id " _ $CLASSMETHOD(json, "Str", item, "control_id")
    Set here = "this case's " _ $EXTRACT(..Word(case.Event), 3, *) _ " on visit " _ case.EncounterId
    If $EXTRACT(why, 1, 3) = "a08" {
        Set line = "For patient " _ case.PatientId _ " (" _ case.PatientIdAuthority _ "), a later A08 names another location: " _ what _ " carried " _ ..PlaceWords($CLASSMETHOD(json, "Str", item, "location"), $CLASSMETHOD(json, "Str", item, "bed")) _ ", not " _ ..PlaceWords(case.Ward, case.Bed) _ ", the target of " _ here _ ". Shutter counts it as a further movement"
        Quit line _ $SELECT(why = "a08_location_shown": ". It does not stop the resend: the site's profile shows it (further_messages.a08_location)", 1: "")
    }
    Quit $CASE(why,
        "other_visit": "Another visit for patient " _ case.PatientId _ " (" _ case.PatientIdAuthority _ "): " _ what _ ", beside " _ here _ ". Shutter can't say which visit is right",
        "cancel": "For patient " _ case.PatientId _ " (" _ case.PatientIdAuthority _ "), a cancel the receiver has not applied: " _ what _ ". It may withdraw " _ here,
        "merge": "For patient " _ case.PatientId _ " (" _ case.PatientIdAuthority _ "), a merge the receiver has not applied: " _ what _ ", beside " _ here,
        "discharge": "For patient " _ case.PatientId _ " (" _ case.PatientIdAuthority _ "), a discharge the receiver has not applied: " _ what _ ". Sending " _ here _ " alone would admit a patient who has left",
        "record_changed": "A change to the record of patient " _ case.PatientId _ " (" _ case.PatientIdAuthority _ "): " _ what _ ", beside " _ here,
        : "Also on file for patient " _ case.PatientId _ " (" _ case.PatientIdAuthority _ "): " _ what _ ", beside " _ here _ ". It does not stop the resend")
}

/// A ward and a bed for a person, as the line on an A08 names them.
ClassMethod PlaceWords(ward As %String, bed As %String) As %String
{
    Quit $SELECT(ward '= "": "ward " _ ward, 1: "no ward") _ $SELECT(bed '= "": " bed " _ bed, 1: " with no bed")
}

/// An event word for a person, with its article.
ClassMethod Word(event As %String) As %String [ Private ]
{
    If $EXTRACT(event, 1, 7) = "cancel_" Quit "a cancel of the " _ ##class(Shutter.Operation.Gate).Reversed(event)
    Quit $CASE(event, "admit": "an admission", "transfer": "a transfer", "discharge": "a discharge", "register": "a registration", "preadmit": "a pre-admission", "update": "an update", "merge": "a merge", "person_add": "a new person record", "person_update": "a person update", "": "a message", : "a " _ event)
}

/// What stops the write, for a check's detail or a case's headline: the first row, and how many more.
ClassMethod Describe(case As Shutter.Store.Case, found As %DynamicObject) As %String
{
    If ..Count(found, "stops") = 0 Quit ""
    Set stops = found.%Get("stops")
    Quit ..Line(case, stops.%Get(0)) _ $SELECT(stops.%Size() > 1: ", and " _ (stops.%Size() - 1) _ " more", 1: "")
}

/// Whether a person may release this stop: the identifier read, every namespace read in full, and each row a movement on
/// another visit. Not a cancel, a merge, a discharge or a change to the record: those may withdraw the write itself.
ClassMethod Releasable(found) As %Boolean
{
    Quit ..NotReleasable(found) = ""
}

/// Why a person can't release this stop, for a person, or "" when they can.
ClassMethod NotReleasable(found) As %String
{
    If '$ISOBJECT(found) Quit "Nothing has been read for this patient."
    If ..Unreadable(found) Quit "The patient's identifier could not be read, so what else has happened to them is not known."
    If ..Unread(found) '= "" Quit "Further messages could not all be read: " _ ..Unread(found) _ "."
    If ..Count(found, "stops") = 0 Quit "Nothing stops this write now."
    Set it = found.%Get("stops").%GetIterator()
    While it.%GetNext(, .item) {
        If ##class(Shutter.Util.Json).Str(item, "why") '= "other_visit" Return "One of these isn't only another visit's movement (" _ ##class(Shutter.Util.Json).Str(item, "why") _ "): it may withdraw this write, so it needs correcting by hand."
    }
    Quit ""
}

/// The digest of the rows that stop the write, the same from whichever store a row was read: its visit, control id, event
/// and why. A further message that stops the write changes it.
ClassMethod RowsDigest(found) As %String
{
    If ..Count(found, "stops") = 0 Quit ""
    Set json = "Shutter.Util.Json", it = found.%Get("stops").%GetIterator()
    While it.%GetNext(, .item) {
        Set sorted($CLASSMETHOD(json, "Str", item, "visit_number") _ "|" _ $CLASSMETHOD(json, "Str", item, "control_id") _ "|" _ $CLASSMETHOD(json, "Str", item, "event") _ "|" _ $CLASSMETHOD(json, "Str", item, "why")) = ""
    }
    Set rows = [], key = ""
    For {
        Set key = $ORDER(sorted(key))
        Quit:key=""
        Do rows.%Push(key)
    }
    Quit ##class(Shutter.Util.Digest).OfObject({"rows": (rows)})
}

/// Whether a person's release of this case stands against this read: the same rows, and nothing the release can't cover.
ClassMethod Released(case As Shutter.Store.Case, found) As %Boolean
{
    If case.FurtherReleaseJSON = "" Quit 0
    If '..Releasable(found) Quit 0
    Set release = ##class(Shutter.Util.Json).Parse(case.FurtherReleaseJSON, .psc)
    Quit $ISOBJECT(release) && (##class(Shutter.Util.Json).Str(release, "digest") = ..RowsDigest(found))
}

/// A person with Shutter_Approve releases the stop on the rows they read: refused with a code and words unless a fresh read
/// gives the digest they name. It records who, when and why on the case, and releases nothing else: every other check still
/// runs, and the write still needs its approval.
ClassMethod Release(case As Shutter.Store.Case, digest As %String, reason As %String, user As %String, Output code As %String, Output words As %String) As %Boolean
{
    Set code = "", words = ""
    Set found = ..Find(case), why = ..NotReleasable(found)
    If why '= "" Set code = "not_releasable", words = why Quit 0
    If digest '= ..RowsDigest(found) Set code = "rows_changed", words = "The rows you read are not the rows on file now: read them again." Quit 0
    Set record = {"digest": (digest), "by": (user), "at": (##class(Shutter.Util.Time).NowUTC()), "reason": ($EXTRACT(reason, 1, 2000))}
    Set case.FurtherReleaseJSON = record.%ToJSON()
    Set sc = case.%Save()
    If $$$ISERR(sc) Set code = "not_saved", words = $SYSTEM.Status.GetErrorText(sc) Quit 0
    Do case.Note("approval", user _ " released the stop on further messages, for " _ ..Count(found, "stops") _ " message(s) they read (rows " _ $EXTRACT(digest, 1, 19) _ "): " _ record.reason, user)
    Quit 1
}

/// The lines a resend's plan and approval carry: what is on file for the patient, and for an admission on a receiver's 404
/// that the 404 proves nothing about a record entered by hand.
ClassMethod PlanLines(case As Shutter.Store.Case, summary As %DynamicObject) As %DynamicArray
{
    Set out = []
    If '$ISOBJECT(summary) Quit out
    Set found = summary.%Get("further_messages")
    If ..Count(found, "shows") > 0 {
        Set si = found.%Get("shows").%GetIterator()
        While si.%GetNext(, .item) { Do out.%Push(..Line(case, item)) }
    }
    If (##class(Shutter.Store.SiteProfile).FurtherA08Location() = "show") && (##class(Shutter.Catalogue.Matcher).A08Location(summary, case) = "different") Do out.%Push(##class(Shutter.Catalogue.Matcher).A08Words(summary, case) _ ". It does not stop the resend: the site's profile shows it (further_messages.a08_location). The resend carries no location, so check the receiver's screen")
    If ..AdmissionOnNotFound(case, summary) Do out.%Push("The receiver answers that it has no encounter under this number. That does not prove it holds no record for this patient: has anyone entered them by hand under another number? Check the system's own screen first")
    Quit out
}

/// A failed admission the receiver answers 404 for.
ClassMethod AdmissionOnNotFound(case As Shutter.Store.Case, summary As %DynamicObject) As %Boolean
{
    Quit (case.Event = "admit") && (##class(Shutter.Util.Json).Str(summary, "ward_state_http_status") = 404)
}

}
