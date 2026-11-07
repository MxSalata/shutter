/// The drafted cancel-and-replay sequence for a history correction (CONTRACTS 10): the second route of the steps in
/// Shutter.Util.HistoryCorrection, when the receiver's own records procedure is not used. A person may send it; Shutter sends
/// nothing, and nothing here writes to a receiver. k later movements make 2k + 1 messages: k cancels, newest first, then the
/// failed movement, then the later movements, oldest first. Stored messages are replayed exactly as IRIS gives them back; a
/// cancel is built by a fixed table from the message it cancels, with placeholders for what only the sender can know. Any
/// doubt draws no sequence and says why.
///
/// Sequence gives the structure, which goes on the plan: no message text, because the plan is sent, reduced, to a model.
/// Read gives the text, for an approver on the case page, and checks again first. Gather reads the live store; Decide and
/// Draft read only what they are given, so a test runs them with no message store.
Class Shutter.Util.HistoryDraft Extends %RegisteredObject
{

/// The structure for the plan. forPeople 0 keeps out of the reason an identifier the model view could not tokenise (another
/// encounter's number). An error draws no sequence, never an empty one.
ClassMethod Sequence(case As Shutter.Store.Case, summary As %DynamicObject, entry As %String, forPeople As %Boolean = 0, facts As %DynamicObject = "") As %DynamicObject
{
    Try {
        If '$ISOBJECT(facts) Set facts = ..Gather(case)
        Set out = ..Decide(case, summary, entry, facts, forPeople)
    } Catch ex {
        Set out = ..Stop(..Blank(summary, ""), "body_unreadable", "No sequence: the draft could not be built, so nothing can be replayed from it; reinvestigate.")
        If case.%Id() '= "" Do case.Note("error", "The correction draft could not be built: " _ ex.DisplayString(), "system")
    }
    Quit out
}

/// What the check needs from the live store, in memory only: this object holds message text and is never stored or sent.
/// {has_entry, cancels, resend_timestamp, caught_up, merge_case, pending: [], patient_rows: [], bodies: {key: {text,
/// control_id, ens_header_id}}}.
ClassMethod Gather(case As Shutter.Store.Case) As %DynamicObject
{
    Set facts = {}, profile = "Shutter.Store.SiteProfile"
    Set entry = $CLASSMETHOD(profile, "Receiver", case.Receiver)
    Do facts.%Set("has_entry", $ISOBJECT(entry), "boolean")
    Do facts.%Set("cancels", $CLASSMETHOD(profile, "ReceiverFlag", case.Receiver, "cancels"), "boolean")
    Set facts."resend_timestamp" = ##class(Shutter.Util.Json).Str(entry, "resend_timestamp")
    Set caught = 0
    Try { Set caught = ##class(Shutter.Util.Json).Bool(##class(Shutter.Index.Indexer).Status(), "caught_up", 0) } Catch { Set caught = 0 }
    Do facts.%Set("caught_up", caught, "boolean")
    Set facts.pending = ##class(Shutter.Util.ResendGuard).Pending(case)
    Set resetAt = $GET(^Shutter.Config("resetAt"))
    Set since = $SELECT(resetAt = "": "2000-01-01 00:00:00", 1: $TRANSLATE($PIECE(resetAt, "Z", 1), "T", " "))
    Set rows = ##class(Shutter.Index.Message).ForPatient(case.PatientId, case.PatientIdAuthority, since)
    Set facts."patient_rows" = rows
    // The index keeps one identifier per message, so a message under another of the failed message's identifiers is asked for too.
    Set failedText = "", ri = rows.%GetIterator()
    While (failedText = "") && ri.%GetNext(, .r) { Set:(r."operation_key" = case.OperationKey) failedText = ..StoredText(r."message_body_id") }
    Set others = ..Identifiers(failedText), oi = others.%GetIterator()
    While oi.%GetNext(, .o) {
        Continue:((o.id = case.PatientId) && (o.authority = case.PatientIdAuthority))
        Set more = ##class(Shutter.Index.Message).ForPatient(o.id, o.authority, since), mi = more.%GetIterator()
        While mi.%GetNext(, .r) { Do rows.%Push(r) }
    }
    // A merge case that names this patient as its prior side: the survivor's messages carry the other number.
    Set merged = ..NamedAsPrior(case.PatientId), oi = others.%GetIterator()
    While oi.%GetNext(, .o) { Set:..NamedAsPrior(o.id) merged = 1 }
    Do facts.%Set("merge_case", merged, "boolean")
    Set bodies = {}, ri = rows.%GetIterator()
    While ri.%GetNext(, .r) {
        Set key = r."operation_key"
        Continue:((key = "") || (r."visit_number" '= case.EncounterId) || bodies.%IsDefined(key))
        Do bodies.%Set(key, {"text": (..StoredText(r."message_body_id")), "control_id": (r."control_id"), "ens_header_id": (r."ens_header_id")})
    }
    Set facts.bodies = bodies
    Quit facts
}

/// Every identifier in a message's PID-3, as [{id, authority}], by the message's own separators. A repetition with no number
/// is none.
ClassMethod Identifiers(text As %String) As %DynamicArray
{
    Set out = [], field = ..Field(text, "PID", 3)
    Set comp = $EXTRACT(text, 5), rep = $EXTRACT(text, 6), sub = $EXTRACT(text, 8)
    If field = "" Quit out
    For i = 1:1:$LENGTH(field, rep) {
        Set one = $PIECE(field, rep, i), id = $PIECE(one, comp, 1)
        Continue:(id = "")
        Do out.%Push({"id": (id), "authority": ($PIECE($PIECE(one, comp, 4), sub, 1))})
    }
    Quit out
}

/// Whether a merge case names this number as its prior side.
ClassMethod NamedAsPrior(pid As %String) As %Boolean [ Private ]
{
    If pid = "" Quit 0
    Set found = ""
    &sql(SELECT TOP 1 ID INTO :found FROM Shutter_Store."Case" WHERE PriorPatientId = :pid)
    Quit (SQLCODE = 0) && (found '= "")
}

/// The stored message as IRIS gives it back, or "" when it cannot be read.
ClassMethod StoredText(docId As %String) As %String
{
    If docId = "" Quit ""
    Set text = ""
    Try {
        Set msg = ##class(EnsLib.HL7.Message).%OpenId(docId)
        If $ISOBJECT(msg) {
            Set text = msg.OutputToString(, , .osc)
            If $$$ISERR(osc) || (text = "") Set text = msg.RawContent
        }
    } Catch ex {
        Set text = ""
    }
    Quit text
}

/// The structure: every reason in the order CONTRACTS 10 lists them, the first that holds decides.
ClassMethod Decide(case As Shutter.Store.Case, summary As %DynamicObject, entry As %String, facts As %DynamicObject, forPeople As %Boolean = 0) As %DynamicObject
{
    Set json = "Shutter.Util.Json", out = ..Blank(summary, facts)
    If entry = "E5" Quit ..Stop(out, "not_e1_e6", "No sequence: this correction spans other cases' messages (E5), so it isn't drafted; each case is corrected in turn by hand.")
    If ((entry '= "E1") && (entry '= "E6")) || (case.Event '= "transfer") Quit ..Stop(out, "not_e1_e6", "No sequence: only a single overtaken transfer (E1) or a discharge after it (E6) is drafted.")
    If '$CLASSMETHOD(json, "Bool", facts, "has_entry", 0) Quit ..Stop(out, "cancels_false", "No sequence: the site profile has no entry for this receiver, so the cancel-and-replay route isn't available here; its own records procedure is the route.")
    If '$CLASSMETHOD(json, "Bool", facts, "cancels", 0) Quit ..Stop(out, "cancels_false", "No sequence: the receiver's entry says it takes no cancels (cancels: false), so the cancel-and-replay route isn't available here; its own records procedure is the route.")
    If (case.PatientId = "") || (case.PatientIdAuthority = "") || (case.EncounterId = "") || (case.EncounterId = "-") Quit ..Stop(out, "identifier_unreadable", "No sequence: the patient's identifier or its authority couldn't be read, so further messages for this patient can't be checked.")
    Set rows = facts.%Get("patient_rows")
    If '$ISOBJECT(rows) Set rows = []
    Set merged = (case.PriorPatientId '= "") || $CLASSMETHOD(json, "Bool", facts, "merge_case", 0)
    Set ri = rows.%GetIterator()
    While ri.%GetNext(, .r) { Set:($CLASSMETHOD(json, "Str", r, "event") = "merge") merged = 1 }
    If merged Quit ..Stop(out, "merge_seen", "No sequence: a merge touches this patient, so which messages are theirs can't be settled by machine.")
    If (case.SourceNamespace '= "") && (case.SourceNamespace '= $NAMESPACE) Quit ..Stop(out, "forwarded_case", "No sequence: this case was forwarded from another namespace, whose feed isn't indexed here, so further messages for this patient can't be ruled out.")
    // Not yet, not no: the index catches up in seconds, and every read decides again.
    If '$CLASSMETHOD(json, "Bool", facts, "caught_up", 0) Quit ..Stop(out, "feed_not_indexed", "No sequence yet: the index hadn't caught up with the feed when this was checked, so further messages for this patient can't be ruled out yet. Every read checks again.")
    Set pending = facts.%Get("pending")
    If $ISOBJECT(pending) && (pending.%Size() > 0) {
        Set p = pending.%Get(0)
        Quit ..Stop(out, "pending_message", "No sequence: a message for this encounter is still pending at the receiver (" _ $CLASSMETHOD(json, "Str", p, "event", "message") _ ", " _ $CLASSMETHOD(json, "Str", p, "event_time", "no time") _ ", header " _ $CLASSMETHOD(json, "Str", p, "ens_header_id", "unknown") _ "); wait for it and reinvestigate.")
    }

    // The later movements by operation key alone: two rows of one key are one movement, and two keys are two movements however
    // alike they look. Which of them come from the feed and which from the receiver's history is the check further down.
    Set failedTime = ..Norm(case.EventTime), later = ##class(Shutter.Catalogue.Matcher).Later(summary, case, "single")
    Set li = later.%GetIterator(), spanEnd = failedTime, noKey = 0, updates = 0, other = 0
    While li.%GetNext(, .e) {
        Set key = e."operation_key", word = e.word
        Continue:((key '= "") && (key = case.OperationKey))
        If key '= "" Set acc(key) = 1
        If word = "update" { Set updates = updates + 1, updates(updates) = e Continue }
        If (word '= "transfer") && (word '= "discharge") { Set other = other + 1 Continue }
        If key = "" { Set noKey = 1 Continue }
        If '$DATA(m(key)) Set m(key) = e, m(key, "delivered") = 1
        Set m(key, e.from) = 1
        If 'e.delivered Set m(key, "delivered") = 0
        If 'e.plausible Set m(key, "doubt") = 1
        Set gap = ..Gap(spanEnd, e."event_time")
        If (gap '= "") && (gap > 0) Set spanEnd = ..Norm(e."event_time")
    }

    // The patient-level check: a message of this patient, on any encounter, that the movements above don't account for.
    Set observed = $CLASSMETHOD(json, "Str", summary, "observed_at"), failedSent = "", ri = rows.%GetIterator()
    While ri.%GetNext(, .r) { If ($CLASSMETHOD(json, "Str", r, "operation_key") = case.OperationKey) && (failedSent = "") Set failedSent = $CLASSMETHOD(json, "Str", r, "sent_at") }
    If failedSent = "" Try { Set failedSent = ##class(Shutter.Util.ResendGuard).SinceOf(case) } Catch { Set failedSent = "" }
    Set leftAlone = [], ri = rows.%GetIterator()
    While ri.%GetNext(, .r) {
        Set key = $CLASSMETHOD(json, "Str", r, "operation_key"), control = $CLASSMETHOD(json, "Str", r, "control_id")
        Set visit = $CLASSMETHOD(json, "Str", r, "visit_number"), event = $CLASSMETHOD(json, "Str", r, "event")
        Set t = $CLASSMETHOD(json, "Str", r, "event_time"), sent = $CLASSMETHOD(json, "Str", r, "sent_at")
        Set accounted = (key '= "") && ((key = case.OperationKey) || $DATA(acc(key)))
        Set hit = 0
        If accounted {
            // A second message under an accounted key is not the message accounted for.
            If (control '= "") && $DATA(control(key)) && (control(key) '= control) Set hit = 1
            If control '= "" Set control(key) = control
        } ElseIf (visit = case.EncounterId) && (event = "update") && ..InSpan(t, failedTime, spanEnd) && '..AtOrAfter(sent, observed) {
            // An update inside the span is history already accounted for: the cancels don't touch it.
            Do ..LeftAlone(leftAlone, event, t, key)
        } ElseIf ..Norm(t) = "" {
            Set hit = 1
        } Else {
            Set gap = ..Gap(failedTime, t)
            If (gap '= "") && (gap >= 0) Set hit = 1
            If (sent '= "") && (failedSent '= "") && (..Gap(failedSent, sent) > 0) Set hit = 1
            If ..AtOrAfter(sent, observed) Set hit = 1
        }
        If hit Quit
    }
    If $GET(hit) {
        Set where = $SELECT((visit = case.EncounterId) || forPeople: "encounter " _ visit, 1: "another encounter")
        Quit ..Stop(out, "further_message", "No sequence: a further message for this patient was found: " _ $SELECT(event '= "": event, 1: "a message") _ " on " _ where _ " at " _ $SELECT(t '= "": t, 1: "an unreadable time") _ " (header " _ $CLASSMETHOD(json, "Str", r, "ens_header_id", "unknown") _ "), after the movements this draft covers. A person reads it first.")
    }
    // An update the snapshot holds: left alone inside the span, a further message after it.
    For u = 1:1:updates {
        Set e = updates(u)
        If ..InSpan(e."event_time", failedTime, spanEnd) {
            Do ..LeftAlone(leftAlone, e.event, e."event_time", e."operation_key")
        } Else {
            Return ..Stop(out, "further_message", "No sequence: a further message for this patient was found: " _ e.event _ " on encounter " _ case.EncounterId _ " at " _ e."event_time" _ " (header unknown), after the movements this draft covers. A person reads it first.")
        }
    }

    Set key = "" For { Set key = $ORDER(m(key)) Quit:key=""
        Set e = m(key), open = ""
        If $CLASSMETHOD(json, "Str", e, "case_id") '= "" {
            Set itsCase = ##class(Shutter.Store.Case).ByCaseId(e."case_id")
            If $ISOBJECT(itsCase) && 'itsCase.IsClosed() Set open = itsCase.State
        }
        If 'm(key, "delivered") || (open '= "") {
            Return ..Stop(out, "later_undelivered", "No sequence: the later movement to " _ e.ward _ " at " _ e."event_time" _ " hasn't reached the receiver" _ $SELECT($CLASSMETHOD(json, "Str", e, "case_id") '= "": " (its case " _ e."case_id" _ " is " _ $SELECT(open '= "": open, 1: "not closed") _ ")", 1: "") _ "; wait for it.")
        }
    }
    If other Quit ..Stop(out, "later_not_movement", "No sequence: a later admission, merge or cancel is in the history, which this draft can't undo.")
    If noKey Quit ..Stop(out, "history_mismatch", "No sequence: the receiver holds a movement with no operation key, so these messages can't be matched to it.")
    Set key = "" For { Set key = $ORDER(m(key)) Quit:key=""
        If '$DATA(m(key, "timeline")) || '$DATA(m(key, "history")) {
            Set e = m(key)
            Return ..Stop(out, "history_mismatch", "No sequence: the receiver holds a movement the feed didn't send, or lacks one it did (" _ e.event _ " at " _ e."event_time" _ "), so these messages can't undo it.")
        }
    }
    If '$DATA(m) Quit ..Stop(out, "k_zero", "No sequence: no later movement was found, which contradicts the outcome; reinvestigate.")

    // In time order, by seconds, never as text; two movements in one second have no order to draw.
    If failedTime = "" Quit ..Stop(out, "time_in_doubt", "No sequence: a time in this history is in doubt (the failed movement's), so the order can't be drawn.")
    Set key = "" For { Set key = $ORDER(m(key)) Quit:key=""
        Set e = m(key), gap = ..Gap(failedTime, e."event_time")
        If $DATA(m(key, "doubt")) || (gap = "") || (gap <= 0) || $DATA(sorted(gap)) {
            Return ..Stop(out, "time_in_doubt", "No sequence: a time in this history is in doubt (" _ e.event _ " at " _ e."event_time" _ "), so the order can't be drawn.")
        }
        Set sorted(gap) = key
    }

    // The first cancel reaches only what is current, so the receiver's own placement must be the last movement of its history.
    Set e = m(sorted($ORDER(sorted(""), -1))), held = summary.%Get("ward_state")
    Set expected = $SELECT(e.word = "discharge": "discharged", 1: e.ward)
    Set current = $SELECT($CLASSMETHOD(json, "Str", held, "state") = "discharged": "discharged", 1: $CLASSMETHOD(json, "Str", held, "ward"))
    If current '= expected Quit ..Stop(out, "history_mismatch", "No sequence: the receiver's current placement (" _ $SELECT(current '= "": current, 1: "none given") _ ") isn't the last movement in its history (" _ expected _ "), so the first cancel would not reach what is current.")

    Set bodies = facts.%Get("bodies")
    Set failedKey = case.OperationKey, failedBody = ..Body(bodies, failedKey)
    If failedBody = "" Quit ..Stop(out, "body_unreadable", "No sequence: the stored message " _ case.SourceMessageId _ " can't be read (purged, or on another instance), so nothing can be replayed from it.")
    Set k = 0, gap = "" For { Set gap = $ORDER(sorted(gap)) Quit:gap=""
        Set k = k + 1, keyOf(k) = sorted(gap)
    }
    For i = 1:1:k {
        Set e = m(keyOf(i))
        If ..Body(bodies, keyOf(i)) = "" Return ..Stop(out, "body_unreadable", "No sequence: the stored message for the " _ e.event _ " at " _ e."event_time" _ " can't be read (purged, or on another instance), so nothing can be replayed from it.")
    }
    For i = 1:1:k {
        If (m(keyOf(i)).word = "transfer") && (..Field(..Body(bodies, keyOf(i)), "PV1", 6) = "") Return ..Stop(out, "pv1_6_empty", "No sequence: the message to be cancelled names no prior location (PV1-6), and Shutter guesses none.")
    }
    Set zbe = ..HasSegment(failedBody, "ZBE")
    For i = 1:1:k { Set:..HasSegment(..Body(bodies, keyOf(i)), "ZBE") zbe = 1 }
    If zbe Quit ..Stop(out, "zbe_present", "No sequence: this feed uses IHE movement ids (ZBE), which this draft can't fill.")
    // A replay above ASCII can be resent from the message store; a cancel isn't in the store, so it has no such route.
    For i = 1:1:k {
        Set trigger = $SELECT(m(keyOf(i)).word = "discharge": "A13", 1: "A12")
        If ..NonAscii(..CancelText(trigger, ..Body(bodies, keyOf(i)))) Return ..Stop(out, "cancel_non_ascii", "No sequence: what a cancel copies from the message it cancels holds a character above ASCII, the patient's name perhaps. The copy here may not match the bytes sent and a cancel can't be resent from the message store, so none is drawn.")
    }
    If $CLASSMETHOD(json, "Str", summary, "receipt_http_status") = 200 Quit ..Stop(out, "receipt_present", "No sequence: the receiver holds a receipt for the failed key, so it may have applied it after all; reinvestigate.")

    // The places: by the source, the failed ward and then each later one; by what this receiver holds, the place before and
    // then each later one. A cancel goes back one place on each.
    Set before = ..PlaceBefore(summary, failedTime, .earlier)
    Set bySource(0) = case.Ward, byReceiver(0) = $SELECT(before '= "": before, 1: "not known")
    For i = 1:1:k {
        Set e = m(keyOf(i))
        Set place = $SELECT(e.word = "discharge": "discharged", 1: e.ward), bySource(i) = place, byReceiver(i) = place
    }
    Set steps = [], n = 0
    For i = k:-1:1 {
        Set key = keyOf(i), e = m(key), n = n + 1, id = bodies.%Get(key)
        Set cancels = {"event": (e.event), "ward": (e.ward), "event_time": (e."event_time"), "operation_key": (key), "source_message_id": (id."control_id"), "ens_header_id": (id."ens_header_id")}
        Set step = {"n": (n), "kind": "cancel", "trigger": ($SELECT(e.word = "discharge": "A13", 1: "A12")), "cancels": (cancels), "after": {"by_source": (bySource(i - 1)), "by_receiver": (byReceiver(i - 1))}}
        Do step.%Set("non_ascii", 0, "boolean")
        Do steps.%Push(step)
    }
    Set id = bodies.%Get(failedKey), n = n + 1
    Do steps.%Push(..Replay(n, "transfer", case.Ward, case.EventTime, failedKey, id, bySource(0)))
    For i = 1:1:k {
        Set key = keyOf(i), e = m(key), n = n + 1
        Do steps.%Push(..Replay(n, e.word, e.ward, e."event_time", key, bodies.%Get(key), bySource(i)))
    }
    Do out.%Set("drawn", 1, "boolean")
    Set out.k = k, out.count = n, out.steps = steps, out."left_alone" = leftAlone
    Set history = []
    For i = 1:1:earlier { Do history.%Push(earlier(i)) }
    Do history.%Push(case.Ward)
    For i = 1:1:k { Set e = m(keyOf(i)) If e.word '= "discharge" Do history.%Push(e.ward) }
    Set out.end = {"ward": (bySource(k)), "history": (history)}
    Quit out
}

/// The text: the structure again, on the live store, with the message text for an approver. A sequence no longer drawn
/// answers with its reason alone.
ClassMethod Draft(case As Shutter.Store.Case, summary As %DynamicObject, entry As %String, facts As %DynamicObject = "") As %DynamicObject
{
    If '$ISOBJECT(facts) Set facts = ..Gather(case)
    Set seq = ..Sequence(case, summary, entry, 1, facts)
    Set out = {"caseId": (case.CaseId), "reason_code": (seq."reason_code"), "reason": (seq.reason)}
    Do out.%Set("drawn", seq.drawn, "boolean")
    Set out.header = [], out.messages = [], out."cannot_know" = [], out."left_alone" = [], out.never = [], out."checked_at" = seq."checked_at", out.digest = ""
    Quit:'seq.drawn out
    Set receiver = case.Receiver, bodies = facts.%Get("bodies"), joined = "", states = ""
    Set si = seq.steps.%GetIterator()
    While si.%GetNext(, .s) {
        If s.n <= (2 * seq.k) Set states = states _ $SELECT(states = "": "", 1: "; ") _ "after message " _ s.n _ ": by the source " _ s.after."by_source" _ ", by what this receiver holds " _ s.after."by_receiver"
        Set row = {"n": (s.n), "kind": (s.kind), "trigger": (s.trigger)}
        Set row.after = "After it, by the source: " _ s.after."by_source" _ ". By what this receiver holds: " _ s.after."by_receiver" _ "."
        If s.kind = "cancel" {
            Set c = s.cancels, source = ..Body(bodies, c."operation_key")
            Set row.label = "New: cancels the " _ $SELECT(s.trigger = "A13": "discharge", 1: "transfer to " _ c.ward) _ " at " _ ..OwnTime(source) _ ". Shutter's table, not a source message."
            Set row.text = ..CancelText(s.trigger, source)
            Set row."body_digest" = ""
        } Else {
            Set source = ..Body(bodies, s."operation_key")
            Set row.label = "Replay, unchanged: control id " _ s."source_message_id" _ ", event " _ ..OwnTime(source) _ ", " _ s.event _ $SELECT(s.ward '= "": " to " _ s.ward, 1: "") _ ". Digest of the stored text " _ s."body_digest" _ "."
            Set row."body_digest" = s."body_digest"
            If s."non_ascii" { Do row.%Set("text", "", "null") } Else { Set row.text = source }
        }
        Set row.withheld = $SELECT(s."non_ascii": "Don't paste this message: resend it from the message store (control id " _ s."source_message_id" _ "), because the copy here may not match the bytes sent.", 1: "")
        Do out.messages.%Push(row)
        Set joined = joined _ row.label _ $CHAR(10) _ $CLASSMETHOD("Shutter.Util.Json", "Str", row, "text") _ $CHAR(10)
    }
    Set out.digest = ##class(Shutter.Util.Digest).SHA256Hex(joined)
    Set out.header = [
        "Draft. Shutter has sent none of this and will send none of it.",
        ("Drawn from the snapshot taken at " _ seq."observed_at" _ " with " _ receiver _ " at version " _ seq."receiver_version" _ ". If the version has moved, throw this away and reinvestigate."),
        "Approval: step 4 above. Who approved, and when, goes on the case.",
        ("Send to " _ receiver _ " only, straight to its own interface: never through the inbound service or the router, or every other receiver on the feed gets these too."),
        ("Before the first message, and again before each one: check " _ receiver _ "'s own screen for this patient, and reload this case. A change made by hand at the receiver is invisible to Shutter, and this block is redrawn on every read."),
        ("Pause the feed to " _ receiver _ " first. In a stock production that means stopping the whole operation item, so every other message for that receiver queues while this runs; a new movement for this patient in the middle breaks the sequence."),
        ("While this runs the receiver shows the wrong place " _ (2 * seq.k) _ " times: " _ states _ "."),
        "If the receiver stops at any step, go forward from where it stopped, as the states above say. Never try to reverse a cancel.",
        "Message text is read on this page by an approver, and each read is recorded on the case. The email for this case carries none of it."
    ]
    Set first = seq.steps.%Get(seq.k - 1), missingWard = case.Ward
    Do out."cannot_know".%Push({"what": "Whether the receiver takes cancels", "why": ("Taking cancels is a profile answer, here " _ $SELECT(seq."cancels_flag": "true", 1: "false") _ "; the profile can be wrong."), "does": "Shows the flag."})
    Do out."cannot_know".%Push({"what": "The right PV1-3 for the cancel", "why": ("The receiver never held " _ missingWard _ ", so one that checks the prior location may refuse or disagree."), "does": ("Shows both: " _ first.after."by_source" _ " by the source, " _ first.after."by_receiver" _ " by what this receiver holds. The source's is used, because HL7 has PV1-3 show the location before the original transfer.")})
    Do out."cannot_know".%Push({"what": "Duplicate handling", "why": "A receiver may refuse a replayed control id or operation key as already seen.", "does": "Names it. A new control id would be a person's edit at send, never Shutter's."})
    Do out."cannot_know".%Push({"what": "Fresh timestamps", "why": ("The profile's resend_timestamp says whether the receiver needs a fresh MSH-7; here it says " _ $SELECT(seq."resend_timestamp" '= "": seq."resend_timestamp", 1: "nothing") _ "."), "does": "Shows the flag. If fresh, a person changes it at send, and the digest then won't match."})
    Do out."cannot_know".%Push({"what": "What hangs off the later movement", "why": "A cancel deletes it; notes, charges or orders attached there are the receiver's business.", "does": "Names the question for the receiver's team."})
    Do out."cannot_know".%Push({"what": "Whether the beds are still free", "why": "A bed in this history may hold someone now; a bed taken stops the sequence half way.", "does": "Says check before starting."})
    Do out."cannot_know".%Push({"what": "Who else is fed by this receiver", "why": "Its subscribers see the patient move back and forward.", "does": "Names it."})
    Do out."cannot_know".%Push({"what": "Whether anything newer has happened", "why": "A draft is a reading at one moment.", "does": "The version line, and the redraw on every read."})
    Do out."cannot_know".%Push({"what": "A message under another identifier", "why": "Further messages are looked for under every identifier in the failed message's PID-3. A message the index keeps under an identifier the failed message doesn't hold can't be matched, and Shutter doesn't match on a name or a date of birth, because a different patient must not match.", "does": "Says so here. The line about checking the receiver's own screen covers it."})
    Do out."cannot_know".%Push({"what": "A change made by hand at the receiver", "why": "It is invisible over HL7, and a message on a route the index doesn't cover is invisible too.", "does": "The line about checking the receiver's own screen."})
    Do out."cannot_know".%Push({"what": "What the source's time meant", "why": "Operation keys are in UTC, and the source's own text may be in local time.", "does": "Shows the source's own text, never a converted time."})
    Set li = seq."left_alone".%GetIterator()
    While li.%GetNext(, .l) { Do out."left_alone".%Push("A demographic update (" _ l."event_time" _ ") sits between these movements; the cancels don't touch it, and it stays in the receiver's record.") }
    Set out.never = [
        "Never edit a value in a source message or show one as edited.",
        "Never guess a time, control id or location.",
        "Never treat one cancel as enough when there is more than one later movement, or send a cancel against a movement that isn't current at that step.",
        "Never use Z99, an A08 as a location fix, or a resend of the original on its own.",
        "Never put message text in the plan, the email or any agent's context.",
        "Never call this verified: the case is closed by hand, as step 8 says."
    ]
    Quit out
}

/// GET /cases/{id}/correction-draft: the draft, redrawn now, and each read of a drawn one recorded on the case with who read
/// it. The event names no message text.
ClassMethod Read(case As Shutter.Store.Case, user As %String, summary As %DynamicObject, entry As %String, facts As %DynamicObject = "") As %DynamicObject
{
    Set out = ..Draft(case, summary, entry, facts)
    If out.drawn Do case.Note("note", "Correction draft read by " _ user _ ": " _ out.messages.%Size() _ " messages, digest " _ out.digest, user)
    Quit out
}

/// The email's one line, for the plan's correction_steps; "" for a plan from before the sequence.
ClassMethod EmailLine(correction As %DynamicObject) As %String
{
    Set seq = $SELECT($ISOBJECT(correction): correction.%Get("sequence"), 1: "")
    If '$ISOBJECT(seq) Quit ""
    If seq.%Get("drawn") Quit "A drafted sequence of " _ seq.count _ " messages is on the case, for an approver to read on the case page; this email carries none of it."
    If seq.%Get("reason_code") = "feed_not_indexed" Quit "No message sequence has been drafted yet: the index hadn't caught up with the feed when the plan was made. An approver can read it on the case page, which checks again on every read; this email carries none of it."
    Set reason = seq.reason
    If $EXTRACT(reason, 1, 13) = "No sequence: " Set reason = $EXTRACT(reason, 14, *)
    If $EXTRACT(reason, *) = "." Set reason = $EXTRACT(reason, 1, * - 1)
    Quit "No message sequence was drafted: " _ reason _ "."
}

// ---- building blocks ----

ClassMethod Blank(summary As %DynamicObject, facts As %DynamicObject) As %DynamicObject [ Private ]
{
    Set json = "Shutter.Util.Json", out = {}
    Do out.%Set("drawn", 0, "boolean")
    Set out."reason_code" = "", out.reason = "", out.k = 0, out.count = 0
    Set ward = $SELECT($ISOBJECT(summary): summary.%Get("ward_state"), 1: "")
    Set out."receiver_version" = $CLASSMETHOD(json, "Str", ward, "version") _ "", out."observed_at" = $CLASSMETHOD(json, "Str", summary, "observed_at")
    If $ISOBJECT(facts) && $CLASSMETHOD(json, "Bool", facts, "has_entry", 0) {
        Do out.%Set("cancels_flag", $CLASSMETHOD(json, "Bool", facts, "cancels", 0), "boolean")
    } Else {
        Do out.%Set("cancels_flag", "", "null")
    }
    Set out."resend_timestamp" = $CLASSMETHOD(json, "Str", facts, "resend_timestamp")
    Set out.steps = [], out."left_alone" = [], out.end = {}, out."checked_at" = ##class(Shutter.Util.Time).NowUTC()
    Quit out
}

ClassMethod Stop(out As %DynamicObject, code As %String, line As %String) As %DynamicObject [ Private ]
{
    Set out."reason_code" = code, out.reason = line
    Do out.%Set("drawn", 0, "boolean")
    Set out.steps = [], out.k = 0, out.count = 0
    Quit out
}

ClassMethod Replay(n As %Integer, word As %String, ward As %String, time As %String, key As %String, id As %DynamicObject, place As %String) As %DynamicObject [ Private ]
{
    Set text = id.text
    Set step = {"n": (n), "kind": "replay", "trigger": ($SELECT(word = "discharge": "A03", 1: "A02")), "event": (word), "ward": (ward), "event_time": (time), "operation_key": (key), "source_message_id": (id."control_id"), "ens_header_id": (id."ens_header_id"), "body_digest": (##class(Shutter.Util.Digest).SHA256Hex(text))}
    Do step.%Set("non_ascii", ..NonAscii(text), "boolean")
    Set step.after = {"by_source": (place), "by_receiver": (place)}
    Quit step
}

ClassMethod LeftAlone(list As %DynamicArray, event As %String, time As %String, key As %String) [ Private ]
{
    Set li = list.%GetIterator()
    While li.%GetNext(, .l) { If (key '= "") && (l."operation_key" = key) Return }
    Do list.%Push({"event": (event), "event_time": (time), "operation_key": (key)})
}

ClassMethod Body(bodies As %DynamicObject, key As %String) As %String [ Private ]
{
    If '$ISOBJECT(bodies) || (key = "") Quit ""
    Set id = bodies.%Get(key)
    Quit $SELECT($ISOBJECT(id): ##class(Shutter.Util.Json).Str(id, "text"), 1: "")
}

/// The earlier places in the receiver's history, oldest first, and the last of them: where the patient was before the
/// failed movement by what this receiver holds.
ClassMethod PlaceBefore(summary As %DynamicObject, failedTime As %String, Output earlier) As %String [ Private ]
{
    Set earlier = 0, json = "Shutter.Util.Json"
    Set ward = summary.%Get("ward_state"), history = $SELECT($ISOBJECT(ward): ward.%Get("history"), 1: "")
    Quit:'$ISOBJECT(history) ""
    Set hi = history.%GetIterator(), n = 0
    While hi.%GetNext(, .h) {
        Set w = $CLASSMETHOD(json, "Str", h, "ward"), gap = ..Gap($CLASSMETHOD(json, "Str", h, "event_time"), failedTime)
        Continue:((w = "") || (gap = "") || (gap <= 0))
        Set n = n + 1, byGap(-gap, n) = w
    }
    Set g = "" For { Set g = $ORDER(byGap(g)) Quit:g=""  Set i = "" For { Set i = $ORDER(byGap(g, i), 1, w) Quit:i=""  Set earlier = earlier + 1, earlier(earlier) = w } }
    Quit $SELECT(earlier > 0: earlier(earlier), 1: "")
}

/// An A12 or an A13 by the fixed table: copied from the message it cancels, or a placeholder a person fills. Nothing is
/// computed from a time and no location is guessed.
ClassMethod CancelText(trigger As %String, source As %String) As %String
{
    Set fs = $EXTRACT(source, 4), encoding = $PIECE(source, fs, 2), comp = $EXTRACT(encoding, 1)
    If comp = "" Set comp = "^"
    // ADT_A12 has its own structure in HL7 2.5.1; an A13 uses ADT_A01's.
    Set type = "ADT" _ comp _ trigger _ comp _ $SELECT(trigger = "A13": "ADT_A01", 1: "ADT_A12")
    Set msh = "MSH" _ fs _ encoding
    For i = 3:1:6 { Set msh = msh _ fs _ ..Field(source, "MSH", i) }
    Set msh = msh _ fs _ "[SENDER: time sent]" _ fs _ fs _ type _ fs _ "[SENDER: new control id]" _ fs _ ..Field(source, "MSH", 11) _ fs _ ..Field(source, "MSH", 12)
    Set evn = "EVN" _ fs _ trigger _ fs _ "[SENDER: time recorded]" _ fs _ fs _ fs _ fs _ "[SITE: event time for a cancel]"
    Set pid = ..Segment(source, "PID")
    Set pv1("1") = ..Field(source, "PV1", 1), pv1("2") = ..Field(source, "PV1", 2), pv1("19") = ..Field(source, "PV1", 19), pv1("44") = ..Field(source, "PV1", 44)
    If trigger = "A13" {
        Set pv1("3") = ..Field(source, "PV1", 3), pv1("6") = "", pv1("45") = ""
    } Else {
        Set pv1("3") = ..Field(source, "PV1", 6), pv1("6") = ..Field(source, "PV1", 3), pv1("45") = ..Field(source, "PV1", 45)
    }
    Set last = $SELECT(pv1("45") '= "": 45, 1: 44), seg = "PV1"
    For i = 1:1:last { Set seg = seg _ fs _ $GET(pv1(i)) }
    Set cr = $CHAR(13)
    Quit msh _ cr _ evn _ cr _ pid _ cr _ seg _ cr
}

/// The source's own text for the event's time: EVN-6, else EVN-2, else MSH-7, never converted.
ClassMethod OwnTime(text As %String) As %String
{
    Set t = ..Field(text, "EVN", 6)
    If t = "" Set t = ..Field(text, "EVN", 2)
    If t = "" Set t = ..Field(text, "MSH", 7)
    Quit t
}

ClassMethod Segment(text As %String, name As %String) As %String [ Private ]
{
    For i = 1:1:$LENGTH(text, $CHAR(13)) {
        Set seg = $ZSTRIP($PIECE(text, $CHAR(13), i), "<", $CHAR(10))
        If $EXTRACT(seg, 1, 3) = name Quit
        Set seg = ""
    }
    Quit seg
}

/// A segment's field by its HL7 number, raw. In MSH the separator is field 1, so its pieces number one higher.
ClassMethod Field(text As %String, name As %String, n As %Integer) As %String
{
    Set seg = ..Segment(text, name)
    If seg = "" Quit ""
    Quit $PIECE(seg, $EXTRACT(text, 4), $SELECT(name = "MSH": n, 1: n + 1))
}

ClassMethod HasSegment(text As %String, name As %String) As %Boolean
{
    Quit ..Segment(text, name) '= ""
}

ClassMethod NonAscii(text As %String) As %Boolean
{
    For i = 1:1:$LENGTH(text) { If $ASCII(text, i) > 127 Return 1 }
    Quit 0
}

/// A time as ISO UTC, whichever form it came in (an offset, an HL7 time, fractional seconds), or "" when it is no time.
ClassMethod Norm(t As %String) As %String
{
    Set t = $ZSTRIP(t, "<>W")
    If t = "" Quit ""
    If $MATCH(t, "[0-9]{8,14}(\.[0-9]+)?([+-][0-9]{4})?") Quit ##class(Shutter.Util.Time).FromHL7(t)
    If $MATCH(t, "[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?[+-][0-9]{2}:?[0-9]{2}") {
        Set digits = $TRANSLATE($EXTRACT(t, 1, 19), "-: T", ""), offset = $TRANSLATE($EXTRACT(t, *-5, *), ":", "")
        If $LENGTH(offset) = 6 Set offset = $EXTRACT(offset, 2, 6)
        Quit ##class(Shutter.Util.Time).FromHL7(digits _ offset)
    }
    If ##class(Shutter.Util.Time).SecondsBetween(t, t) = "" Quit ""
    Quit t
}

/// Seconds from a to b, whichever form they came in, or "" when either is no time. Never a comparison of text.
ClassMethod Gap(a As %String, b As %String) As %String
{
    Quit ##class(Shutter.Util.Time).SecondsBetween(..Norm(a), ..Norm(b))
}

ClassMethod InSpan(t As %String, from As %String, to As %String) As %Boolean [ Private ]
{
    Set a = ..Gap(from, t), b = ..Gap(t, to)
    Quit (a '= "") && (b '= "") && (a >= 0) && (b >= 0)
}

/// Whether a is at or after b; 0 when either is no time.
ClassMethod AtOrAfter(a As %String, b As %String) As %Boolean [ Private ]
{
    Set gap = ..Gap(b, a)
    Quit (gap '= "") && (gap >= 0)
}

}
