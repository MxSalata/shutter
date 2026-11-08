/// Further messages for the patient, read immediately before a write (CONTRACTS 6.5): any message for this patient that
/// reached the engine after the case's own, or is timed after it, on any visit, in Shutter's namespace and the namespace the
/// case came from, whatever became of it. ResendGuard and the matcher read one visit; this reads the patient. Find gathers
/// the rows and Classify, which is pure so a test runs it without a message store, weighs them:
/// - stops: an in-patient movement on another visit (a clerk may be working round bad history, and Shutter can't say which
///   visit is real, so both are named for a person), a change to the record itself, a cancel or merge of this visit that the
///   receiver did not apply, and for an admission outside a chain a discharge the receiver did not apply.
/// - shows: anything else about the patient in the ADT feed, such as an out-patient attendance or an emergency department's
///   discharge. It stops nothing and goes on the plan.
/// The site profile's further_messages.in_patient_movement says show to let another visit's movement through. The gate reads
/// the snapshot at the proposal and reads again at dispatch, and the connector reads again at the moment of the write.
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
    Quit ..Classify(subject, rows, ##class(Shutter.Store.ChainItem).KindFor(case), since, ##class(Shutter.Store.SiteProfile).FurtherMovement(), unread)
}

ClassMethod Subject(case As Shutter.Store.Case) As %DynamicObject [ Private ]
{
    Set s = {}
    Set s."encounter_id" = case.EncounterId, s."patient_id" = case.PatientId, s."patient_id_authority" = case.PatientIdAuthority
    Set s.event = case.Event, s."event_time" = case.EventTime, s."operation_key" = case.OperationKey, s."control_id" = case.SourceMessageId
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
        // The index holds no patient class, and a movement's class decides whether it stops.
        If $LISTFIND($LISTBUILD("register", "preadmit", "admit", "transfer", "discharge", "cancel_admit", "cancel_transfer", "cancel_discharge"), $CLASSMETHOD(json, "Str", r, "event")) {
            Set body = ##class(EnsLib.HL7.Message).%OpenId($CLASSMETHOD(json, "Str", r, "message_body_id"))
            If $ISOBJECT(body) Set r."patient_class" = ##class(Shutter.Util.OperationKey).Value(body, "PV1", "2")
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
    Set r.location = ##class(Shutter.Util.OperationKey).Value(body, "PV1", "3.1"), r."control_id" = ##class(Shutter.Util.OperationKey).Value(body, "MSH", "10")
    Set r."event_time" = $SELECT(hasOp: $CLASSMETHOD(json, "Str", op, "event_time"), 1: ##class(Shutter.Util.Time).FromHL7(##class(Shutter.Util.OperationKey).Value(body, "EVN", "2.1")))
    If hasOp Set r."operation_key" = $CLASSMETHOD(json, "Str", op, "operation_key"), r."prior_patient_id" = $CLASSMETHOD(json, "Str", op, "prior_patient_id"), r."prior_patient_id_authority" = $CLASSMETHOD(json, "Str", op, "prior_patient_id_authority")
    Quit r
}

ClassMethod Add(rows As %DynamicArray, more As %DynamicArray) [ Private ]
{
    Set mi = more.%GetIterator()
    While mi.%GetNext(, .r) { Do rows.%Push(r) }
}

/// Weighs the rows for a subject {encounter_id, patient_id, patient_id_authority, event, event_time, operation_key,
/// control_id}. A row counts when it is this patient's, by identifier and authority, or a merge that names the patient as its
/// prior record; an authority missing on either side can't tell two patients apart, so the row counts and a person reads it.
/// It must have reached the engine after since, or be timed after the case's event, and not be the case's own message. The
/// first row of a control id and visit wins, so pass the deliveries first: their answers say what the receiver applied.
ClassMethod Classify(subject As %DynamicObject, rows As %DynamicArray, chainKind As %String = "single", since As %String = "", movement As %String = "stop", unread As %String = "") As %DynamicObject
{
    Set json = "Shutter.Util.Json", out = {}, stops = [], shows = []
    Set id = $CLASSMETHOD(json, "Str", subject, "patient_id"), authority = $CLASSMETHOD(json, "Str", subject, "patient_id_authority")
    Set visit = $CLASSMETHOD(json, "Str", subject, "encounter_id"), key = $CLASSMETHOD(json, "Str", subject, "operation_key"), own = $CLASSMETHOD(json, "Str", subject, "control_id")
    Set event = $CLASSMETHOD(json, "Str", subject, "event"), eventTime = $CLASSMETHOD(json, "Str", subject, "event_time")
    Set single = (chainKind = "") || (chainKind = "single")
    Set readable = (id '= "") && (id '= "-")
    Set out.identifier = $SELECT(readable: "read", 1: "unreadable")
    If readable && $ISOBJECT(rows) {
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
            Continue:(why = "")
            // A pre-admission on file before the case is a date on a waiting list, not a move.
            If (why = "other_visit") && ($CLASSMETHOD(json, "Str", r, "event") = "preadmit") && '(sent ]] since) Set why = "shown"
            Set item = {}
            Set item.why = why, item.event = $CLASSMETHOD(json, "Str", r, "event"), item."message_type" = $CLASSMETHOD(json, "Str", r, "message_type"), item."visit_number" = rowVisit
            Set item."event_time" = time, item."sent_at" = sent, item."control_id" = control, item.location = $CLASSMETHOD(json, "Str", r, "location"), item.where = $CLASSMETHOD(json, "Str", r, "where")
            If ((why = "other_visit") && (movement = "show")) || (why = "shown") { Do shows.%Push(item) } Else { Do stops.%Push(item) }
        }
    }
    Set out.stops = stops, out.shows = shows, out.unread = unread
    Quit out
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

/// Why a row matters: other_visit, record_changed, cancel, merge, discharge (each stops), shown, or "" when it doesn't.
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
    Quit $CASE(why,
        "other_visit": "Another visit for patient " _ case.PatientId _ " (" _ case.PatientIdAuthority _ "): " _ what _ ", beside " _ here _ ". Shutter can't say which visit is right",
        "cancel": "For patient " _ case.PatientId _ " (" _ case.PatientIdAuthority _ "), a cancel the receiver has not applied: " _ what _ ". It may withdraw " _ here,
        "merge": "For patient " _ case.PatientId _ " (" _ case.PatientIdAuthority _ "), a merge the receiver has not applied: " _ what _ ", beside " _ here,
        "discharge": "For patient " _ case.PatientId _ " (" _ case.PatientIdAuthority _ "), a discharge the receiver has not applied: " _ what _ ". Sending " _ here _ " alone would admit a patient who has left",
        "record_changed": "A change to the record of patient " _ case.PatientId _ " (" _ case.PatientIdAuthority _ "): " _ what _ ", beside " _ here,
        : "Also on file for patient " _ case.PatientId _ " (" _ case.PatientIdAuthority _ "): " _ what _ ", beside " _ here _ ". It does not stop the resend")
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
    If ..AdmissionOnNotFound(case, summary) Do out.%Push("The receiver answers that it has no encounter under this number. That does not prove it holds no record for this patient: has anyone entered them by hand under another number? Check the system's own screen first")
    Quit out
}

/// A failed admission the receiver answers 404 for.
ClassMethod AdmissionOnNotFound(case As Shutter.Store.Case, summary As %DynamicObject) As %Boolean
{
    Quit (case.Event = "admit") && (##class(Shutter.Util.Json).Str(summary, "ward_state_http_status") = 404)
}

}
