/// The FHIR verifier's decision: after one version-aware update (PUT Encounter/{id} with If-Match), what the receiver's
/// record shows, as a pure function of what was read. Judge reads no global, no clock and no network, and never throws:
/// the walk that fills the context, the settle window's timer and the case's words are the verifier's (FHIRVerify), as
/// Shutter.Operation.Verify calls its own Judge.
/// <p>The rules, in the order they are applied (the first that applies decides):
/// <ol>
/// <li>The context must be whole and consistent (Context below), else unknown context_invalid.</li>
/// <li>A 201 on the PUT is failed update_created: an update that created a resource contradicts the read it was
/// conditional on.</li>
/// <li>The instance history must be a whole history Bundle with no next link, every entry a version entry (a resource
/// with a meta.versionId string, request PUT or POST) or a delete entry (request DELETE, no resource), no version id
/// twice. Entries are taken in the order returned (newest first on IRIS for Health); version ids are compared as strings
/// and never parsed, ordered or counted; response.status, response.lastModified and meta.lastUpdated are never read.</li>
/// <li>The base (the version the write was conditional on) must be in the history, with the body that was sealed.</li>
/// <li>Shutter's version V is the earliest version newer than the base carrying the exact marker pair (the profile's
/// marker system and the binding's operation id, case-sensitive). The base, or anything older, carrying it is failed.
/// With no marked version: the same location change without the marker is unknown (never Shutter's credit); an applied
/// answer whose version is not there is failed; a delete after the base, a head that is still the base, or a read
/// inside the settle window is unknown; only then, final, is it "no committed version found".</li>
/// <li>V's immediate predecessor in the returned list must be the base itself: a delete there is unknown, any other
/// version there is failed (a lost update).</li>
/// <li>V must be the approved body: equal to the expected body once meta.versionId and meta.lastUpdated are set aside
/// (and nothing else: server_owned_fields is empty on IRIS), its location change the one shape built from the base,
/// its subject and identifier the binding's (case-sensitive); the vread, the response ETag and the response Location
/// must name V. A version that commits after a 412 or a refusal is failed.</li>
/// <li>V is committed. The current resource decides whether the case resolves: V itself (verified), a supported
/// continuation of it (verified_continued: a later move to a mapped ward, or a plain finish, with Shutter's entry kept
/// and completed after its own start, one open entry, no overlapping periods), or anything else (committed_review). The
/// marker is never looked for on the current version: on IRIS the next writer's PUT replaces meta.tag. The Patient and
/// every bound Location are read again and must still be the case's.</li>
/// </ol>
/// Outcomes: verified, verified_continued, committed_review, not_found, unknown, failed. detail carries reason (one code),
/// committed_version, current_version, base_version, head_version, path, retry (another read inside the settle window
/// could change the answer) and case_code (WRITE_NOT_COMMITTED for not_found, WRITE_OUTCOME_UNKNOWN for unknown).
Class Shutter.FHIR.Judge [ Abstract ]
{

/// The outcomes Judge returns.
Parameter OUTCOMES = "verified,verified_continued,committed_review,not_found,unknown,failed";

/// The verdict on a context (see Context for its shape). Returns the outcome; text is the sentence for the case, detail
/// the record of what decided it.
ClassMethod Judge(ctx As %DynamicObject, Output text As %String, Output detail As %DynamicObject) As %String
{
    Set text = "", detail = ..NewDetail(), outcome = "unknown"
    Try {
        Set outcome = ..Decide(ctx, detail)
        Set text = ..Words(outcome, detail)
    } Catch err {
        Set detail = ..NewDetail(), outcome = "unknown"
        Set detail.reason = "context_invalid", detail.note = "the context could not be judged: " _ err.DisplayString()
        Set text = ..Words(outcome, detail)
    }
    Set detail."case_code" = $CASE(outcome, "not_found": "WRITE_NOT_COMMITTED", "unknown": "WRITE_OUTCOME_UNKNOWN", : "")
    Quit outcome
}

/// The context Judge reads, every body a raw string as the receiver sent it:
/// <pre>
/// {"binding": {"expected_etag": "W/\"6\"", "base_version_id": "6", "operation_id": "<32 lower-case hex>",
///              "marker_system": "urn:shutter:recovery", "encounter_id": "enc-1",
///              "encounter_identifier": {"system": "...", "value": "V1001"},
///              "patient": {"reference": "Patient/demo-p1", "identifier": {"system": "...", "value": "..."}},
///              "prior_location": "Location/ward-a", "target_location": "Location/ward-b",
///              "locations": [{"reference": "Location/ward-b", "checked_identifier": "WARD-B"}, ...],
///              "event_time": "2026-11-08T09:00:00Z", "server_owned_fields": []},
///  "base_body": "...", "expected_body": "...",
///  "attempt": {"outcome": "applied|uncertain|version_conflict|refused|error", "http_status": 200,
///              "response_etag": "W/\"7\"", "response_location": "...", "seconds_since": 0},
///  "settle_final_seconds": 70,
///  "vread": {"http_status": 200, "etag": "W/\"7\"", "content_type": "...", "body": "..."} or null,
///  "history": {"http_status": 200, "content_type": "...", "body": "..."},
///  "current": {"http_status": 200, "etag": "...", "content_type": "...", "body": "..."},
///  "patient": {"http_status": 200, "body": "..."},
///  "locations": [{"reference": "Location/ward-b", "http_status": 200, "body": "..."}]}
/// </pre>
/// expected_body is the approved outbound text (Shutter.FHIR.Plan's Build of base_body). "Final" means
/// attempt.seconds_since is at least settle_final_seconds: the last read of the settle window.
ClassMethod Decide(ctx As %DynamicObject, detail As %DynamicObject) As %String
{
    // 1. The context.
    Set why = ..ContextProblem(ctx, .base, .expected)
    If why '= "" Set detail.note = why Quit ..Out(detail, "unknown", "context_invalid")
    Set b = ctx.binding, attempt = ctx.attempt
    Set baseVid = b."base_version_id", detail."base_version" = baseVid
    Set final = (attempt."seconds_since" >= ctx."settle_final_seconds")
    Set aOutcome = attempt.outcome
    Set retag = ..Str(attempt, "response_etag"), usable = (retag '= "") && ..ETagVid(retag, .rvid)
    If 'usable Set rvid = ""
    Set sof = b."server_owned_fields"

    // 2. A 201 on the PUT.
    If attempt."http_status" = 201 Quit ..Out(detail, "failed", "update_created")

    // 3. The history.
    Set why = ..HistoryProblem(ctx.history, b."encounter_id", .kinds, .vids, .resources, .reason)
    If why '= "" {
        Set detail.note = why
        Quit ..Out(detail, "unknown", reason, $SELECT(reason = "history_unavailable": 'final, 1: 0))
    }
    Set n = kinds
    Set detail."head_version" = $SELECT(n > 0: $GET(vids(1)), 1: "")

    // 4. The base in the history, with the body that was sealed.
    Set bi = 0
    For i = 1:1:n { If (kinds(i) = "version") && (vids(i) = baseVid) Set bi = i Quit }
    If bi = 0 Quit ..Out(detail, "unknown", "base_not_in_history")
    Set path = ..FirstDiff(resources(bi), base)
    If path '= "" Set detail.path = path Quit ..Out(detail, "unknown", "base_differs")

    // 5. The marker: newer than the base (before it in the list), and never on the base or anything older.
    For i = bi:1:n {
        If (kinds(i) = "version") && (..MarkerCount(resources(i), b) > 0) Set detail.path = "/history/" _ (i - 1) Return ..Out(detail, "failed", "marker_on_base")
    }
    Set vi = 0
    For i = 1:1:(bi - 1) { If (kinds(i) = "version") && (..MarkerCount(resources(i), b) > 0) Set vi = i }

    // 6. No marked version newer than the base.
    If vi = 0 {
        Set wantLoc = ..Member(expected, "location")
        For i = 1:1:(bi - 1) {
            If (kinds(i) = "version") && (..FirstDiff(..Member(resources(i), "location"), wantLoc) = "") Set detail."committed_version" = "", detail.path = "/history/" _ (i - 1) Return ..Out(detail, "unknown", "projection_without_marker")
        }
        If (retag '= "") && 'usable Quit ..Out(detail, "unknown", "etag_not_version")
        If (aOutcome = "applied") && usable {
            If bi > 1 Set detail.note = "the answer named version """ _ rvid _ """" Quit ..Out(detail, "failed", "applied_version_absent")
            Quit ..Out(detail, "unknown", "head_is_base", 'final)
        }
        For i = 1:1:(bi - 1) { If kinds(i) = "delete" Return ..Out(detail, "unknown", "history_delete_between") }
        If bi = 1 Quit ..Out(detail, "unknown", "head_is_base", 'final)
        If 'final Quit ..Out(detail, "unknown", "settling", 1)
        If aOutcome = "applied" Quit ..Out(detail, "unknown", "etag_not_version")
        Quit ..Out(detail, "not_found", "no_committed_version")
    }

    // 7. V, the earliest marked version, and its immediate predecessor.
    Set vid = vids(vi), vres = resources(vi), detail."committed_version" = vid
    If kinds(vi + 1) = "delete" Quit ..Out(detail, "unknown", "history_delete_between")
    If (vi + 1) '= bi Set detail.note = "the version before it is """ _ vids(vi + 1) _ """" Quit ..Out(detail, "failed", "introducing_predecessor_not_base")

    // 8a. The vread, the response ETag and the response Location name V.
    Set vread = ctx.%Get("vread")
    If $ISOBJECT(vread) {
        If (vread."http_status" '= 200) || '..MediaOK(..Str(vread, "content_type")) || '..ParseResource(..Str(vread, "body"), "Encounter", b."encounter_id", .vbody) Quit ..Out(detail, "unknown", "vread_unavailable", 'final)
        If '..ETagVid(..Str(vread, "etag"), .vreadVid) || (vreadVid '= ..VersionId(vbody)) || (vreadVid '= vid) Quit ..Out(detail, "unknown", "etag_not_version")
        Set path = ..FirstDiff(vbody, vres)
        If path '= "" Set detail.path = path Quit ..Out(detail, "unknown", "vread_differs")
    }
    If (retag '= "") && ('usable || (rvid '= vid)) Quit ..Out(detail, "unknown", "etag_not_version")
    Set loc = ..Str(attempt, "response_location")
    If (loc '= "") && '..LocationNames(loc, vid) Quit ..Out(detail, "unknown", "location_header_differs")

    // 8b. V is the approved body, with meta.versionId and meta.lastUpdated set aside.
    Set diffs = ..Diffs(..Strip(vres, 0, 0, sof), ..Strip(expected, 0, 0, sof))
    If diffs.%Size() > 0 {
        Set first = diffs.%Get(0), detail.path = first
        Set iter = diffs.%GetIterator()
        While iter.%GetNext(.k, .p) {
            If ..Under(p, "/location") Set detail.path = p Return ..Out(detail, "failed", "introducing_not_projection")
        }
        If ..MarkerCount(vres, b) > 1 Set detail.path = "/meta/tag" Quit ..Out(detail, "failed", "introducing_not_projection")
        Quit ..Out(detail, "unknown", "field_differs")
    }
    // 8c. Independently of expected_body: V is the base with the one location shape applied and the marker added.
    Set path = ..FirstDiff(..Strip(vres, 1, 1, sof, b), ..Strip(base, 1, 0, sof))
    If path '= "" Set detail.path = path Quit ..Out(detail, "failed", "introducing_not_projection")
    Set path = ..ShapeProblem(base, vres, b)
    If path '= "" Set detail.path = path Quit ..Out(detail, "failed", "introducing_not_projection")
    // 8d. V's identity.
    Set path = ..IdentityProblem(vres, b)
    If path '= "" Set detail.path = path Quit ..Out(detail, "unknown", "identity_differs")
    // 8e. A version that commits after the receiver said it refused.
    If (aOutcome = "version_conflict") || (aOutcome = "refused") || (aOutcome = "error") Quit ..Out(detail, "failed", "conflict_but_committed")

    // 9. V is committed: the current record decides whether the case resolves.
    Set cur = ctx.current
    If cur."http_status" = 410 {
        If ..ParseResource(..Str(cur, "body"), "OperationOutcome", "", .oo) Quit ..Out(detail, "committed_review", "current_deleted")
        Quit ..Out(detail, "committed_review", "current_unreadable", 'final)
    }
    If (cur."http_status" '= 200) || '..MediaOK(..Str(cur, "content_type")) || '..ParseResource(..Str(cur, "body"), "Encounter", b."encounter_id", .cbody) Quit ..Out(detail, "committed_review", "current_unreadable", 'final)
    If '..ETagVid(..Str(cur, "etag"), .cvid) || (cvid '= ..VersionId(cbody)) Quit ..Out(detail, "committed_review", "current_unreadable", 'final)
    Set detail."current_version" = cvid
    If cvid = vid {
        // V is current only when the history agrees: V is its head, with V's body.
        If vi '= 1 Quit ..Out(detail, "committed_review", "current_not_in_history", 'final)
        Set path = ..FirstDiff(cbody, vres)
        If path '= "" Set detail.path = path Quit ..Out(detail, "committed_review", "current_not_in_history", 'final)
        Set result = "verified", reason = "committed_current"
    } Else {
        // The current version must be the history's head, newer than V, with the head's body.
        If (vi = 1) || (kinds(1) '= "version") || (vids(1) '= cvid) Quit ..Out(detail, "committed_review", "current_not_in_history", 'final)
        Set path = ..FirstDiff(cbody, resources(1))
        If path '= "" Set detail.path = path Quit ..Out(detail, "committed_review", "current_not_in_history", 'final)
        For i = 1:1:(vi - 1) { If kinds(i) = "delete" Return ..Out(detail, "committed_review", "history_delete_between") }
        Set why = ..Continuation(cbody, b, .path)
        If why '= "" Set detail.path = path Quit ..Out(detail, "committed_review", why)
        Set result = "verified_continued", reason = "committed_continued"
    }
    // 9d. The current identity, the Patient and the bound Locations, read again.
    Set path = ..IdentityProblem(cbody, b)
    If path '= "" Set detail.path = path Quit ..Out(detail, "committed_review", "identity_differs")
    Set why = ..PatientProblem(ctx.patient, b, .unread)
    If why '= "" Set detail.note = why Quit ..Out(detail, "committed_review", "patient_changed", unread && 'final)
    Set why = ..LocationsProblem(ctx.locations, b, .unread)
    If why '= "" Set detail.note = why Quit ..Out(detail, "committed_review", "location_changed", unread && 'final)
    Quit ..Out(detail, result, reason)
}

/// Sets the outcome's reason and retry on detail, and returns the outcome.
ClassMethod Out(detail As %DynamicObject, outcome As %String, reason As %String, retry As %Boolean = 0) As %String [ Private ]
{
    Set detail.reason = reason
    Do detail.%Set("retry", ''retry, "boolean")
    Quit outcome
}

ClassMethod NewDetail() As %DynamicObject [ Private ]
{
    Set d = {"reason": "", "committed_version": "", "current_version": "", "base_version": "", "head_version": "", "path": "", "case_code": ""}
    Do d.%Set("retry", 0, "boolean")
    Quit d
}

/// "" when the context is whole and consistent, else what is wrong. Returns the parsed base and expected bodies.
ClassMethod ContextProblem(ctx As %DynamicObject, Output base As %DynamicObject, Output expected As %DynamicObject) As %String [ Private ]
{
    Set base = "", expected = ""
    If '$ISOBJECT(ctx) || 'ctx.%IsA("%DynamicObject") Quit "no context"
    Set b = ctx.%Get("binding")
    If '..IsObject(b) Quit "no binding"
    For key = "expected_etag", "base_version_id", "operation_id", "marker_system", "encounter_id", "prior_location", "target_location", "event_time" {
        If ..Str(b, key) = "" Return "the binding has no " _ key
    }
    If '$MATCH(b."operation_id", "[0-9a-f]{32}") Quit "the operation id is not 32 lower-case hex"
    If '..Instant(b."event_time", .t) Quit "the event time is not a FHIR instant with a time and an offset"
    If '..IdentifierShape(b.%Get("encounter_identifier")) Quit "the binding's encounter identifier is incomplete"
    Set p = b.%Get("patient")
    If '..IsObject(p) || (..Str(p, "reference") = "") || '..IdentifierShape(p.%Get("identifier")) Quit "the binding's patient is incomplete"
    Set locs = b.%Get("locations")
    If '..IsArray(locs) Quit "the binding has no locations"
    Set iter = locs.%GetIterator()
    While iter.%GetNext(.i, .l) {
        If '..IsObject(l) || (..Str(l, "reference") = "") || (..Str(l, "checked_identifier") = "") Return "a bound location is incomplete"
    }
    Set sof = b.%Get("server_owned_fields")
    If '..IsArray(sof) Quit "the binding has no server_owned_fields"
    Set iter = sof.%GetIterator()
    While iter.%GetNext(.i, .f) {
        If sof.%GetTypeOf(i) '= "string" Return "a server-owned field is not a path"
        If '..OwnedFieldAllowed(f) Return "the server-owned field " _ f _ " may never be ignored"
    }
    If '..ParseResource(..Str(ctx, "base_body"), "Encounter", b."encounter_id", .base) Quit "the base body is not the bound Encounter"
    If '..ParseResource(..Str(ctx, "expected_body"), "Encounter", b."encounter_id", .expected) Quit "the expected body is not the bound Encounter"
    If ..VersionId(base) '= b."base_version_id" Quit "the base body's meta.versionId is not the binding's base version"
    If b."expected_etag" '= ("W/""" _ b."base_version_id" _ """") Quit "the expected ETag is not the base version's"
    If ..MarkerCount(expected, b) '= 1 Quit "the expected body does not carry the marker once"
    Set a = ctx.%Get("attempt")
    If '..IsObject(a) Quit "no attempt"
    If '$LISTFIND($LISTBUILD("applied", "uncertain", "version_conflict", "refused", "error"), ..Str(a, "outcome")) Quit "the attempt's outcome is not one the connector records"
    If a.%GetTypeOf("http_status") '= "number" Quit "the attempt has no HTTP status"
    If a.%GetTypeOf("seconds_since") '= "number" Quit "the attempt has no age"
    For key = "response_etag", "response_location" {
        Set type = a.%GetTypeOf(key)
        If (type '= "unassigned") && (type '= "null") && (type '= "string") Return "the attempt's " _ key _ " is not a string"
    }
    If (a.outcome = "applied") && (..Str(a, "response_etag") = "") Quit "an applied attempt without its answer's ETag"
    If ctx.%GetTypeOf("settle_final_seconds") '= "number" Quit "no settle window"
    For key = "history", "current", "patient" {
        Set r = ctx.%Get(key)
        If '..IsObject(r) || (r.%GetTypeOf("http_status") '= "number") Return "no " _ key _ " read"
    }
    Set type = ctx.%GetTypeOf("vread")
    If (type '= "unassigned") && (type '= "null") && ((type '= "object") || (ctx.vread.%GetTypeOf("http_status") '= "number")) Quit "the vread is not a read"
    If '..IsArray(ctx.%Get("locations")) Quit "no location reads"
    Quit ""
}

/// Whether a server-owned field may be set aside in the comparisons: never the clinical paths, the identity, the
/// marker's container or a modifier extension (design 2.8).
ClassMethod OwnedFieldAllowed(field As %String) As %Boolean [ Private ]
{
    Set f = $ZSTRIP($TRANSLATE(field, "/", "."), "<>", ".")
    If (f = "") || ($ZCONVERT(f, "L") [ "modifierextension") Quit 0
    Set root = $PIECE(f, ".", 1)
    If $LISTFIND($LISTBUILD("resourceType", "id", "subject", "identifier", "status", "location", "text"), root) Quit 0
    If (f = "meta") || ($PIECE(f, ".", 1, 2) = "meta.security") || ($PIECE(f, ".", 1, 2) = "meta.tag") || ($PIECE(f, ".", 1, 2) = "meta.versionId") Quit 0
    Quit 1
}

/// "" when the history read is a whole history Bundle of the Encounter, else what is wrong, with reason set to the
/// code. kinds(i) is "version" or "delete" for the i-th entry in the order returned (kinds itself is the count),
/// vids(i) the version id of a version entry, resources(i) its resource.
ClassMethod HistoryProblem(read As %DynamicObject, id As %String, Output kinds, Output vids, Output resources, Output reason As %String) As %String [ Private ]
{
    Kill kinds, vids, resources
    Set kinds = 0, reason = "history_unavailable"
    If read."http_status" '= 200 Quit "the history answered " _ read."http_status"
    If '..MediaOK(..Str(read, "content_type")) Quit "the history's content type is not FHIR JSON"
    If '..ParseResource(..Str(read, "body"), "Bundle", "", .bundle) Quit "the history is not a Bundle"
    If ..Str(bundle, "type") '= "history" Quit "the Bundle is not a history"
    Set links = bundle.%Get("link")
    If ..IsArray(links) {
        Set iter = links.%GetIterator()
        While iter.%GetNext(.i, .l) {
            If ..IsObject(l) && (..Str(l, "relation") = "next") Set reason = "history_paged" Return "the history is paged"
        }
    }
    Set type = bundle.%GetTypeOf("entry")
    If type = "unassigned" Quit ""
    If type '= "array" Quit "the history's entries are not a list"
    Set reason = "history_entry_unreadable"
    Set iter = bundle.entry.%GetIterator()
    While iter.%GetNext(.i, .e) {
        Set kinds = kinds + 1
        If '..IsObject(e) Return "entry " _ i _ " is not an object"
        Set req = e.%Get("request"), method = $SELECT(..IsObject(req): ..Str(req, "method"), 1: "")
        Set rtype = e.%GetTypeOf("resource")
        If (method = "DELETE") && ((rtype = "unassigned") || (rtype = "null")) {
            Set kinds(kinds) = "delete", vids(kinds) = "", resources(kinds) = ""
            Continue
        }
        If ((method '= "PUT") && (method '= "POST")) || (rtype '= "object") Return "entry " _ i _ " is neither a version nor a delete"
        Set res = e.resource
        If (..Str(res, "resourceType") '= "Encounter") || (..Str(res, "id") '= id) Return "entry " _ i _ " is not this Encounter"
        Set vid = ..VersionId(res)
        If vid = "" Return "entry " _ i _ " has no version id"
        If $DATA(seen(vid)) Return "version """ _ vid _ """ is in the history twice"
        Set seen(vid) = "", kinds(kinds) = "version", vids(kinds) = vid, resources(kinds) = res
    }
    Set reason = ""
    Quit ""
}

/// "" when the current version W is a supported continuation of Shutter's move, else the reason, with path naming the
/// entry. Shutter's entry is the location entry with the target reference and the event time as its start, as V wrote
/// it. The checks, in the order their reasons are given: the entry is there; it is not completed at or before its own
/// start; the Encounter is not entered in error; the prior location is not open again; no two open entries and no
/// overlapping periods from Shutter's start on; and the rest is a shape this rule knows (in-progress with one open entry,
/// Shutter's or a later one at a mapped location other than the prior; or finished with every entry completed; every
/// reference literal and every time an instant with an offset).
ClassMethod Continuation(w As %DynamicObject, b As %DynamicObject, Output path As %String) As %String [ Private ]
{
    Set path = "/location", target = b."target_location", prior = b."prior_location", event = b."event_time"
    Set bad = "", status = ..Str(w, "status"), type = w.%GetTypeOf("location")
    If (type = "unassigned") || (type = "null") Quit "entry_gone"
    If type '= "array" Quit "unfamiliar_shape"
    Do ..Instant(event, .sStart)
    // Read every entry: reference, status, start and end.
    Set n = 0, s = 0, opens = 0
    Set iter = w.location.%GetIterator()
    While iter.%GetNext(.i, .x) {
        Set n = n + 1, ent(n, "path") = "/location/" _ i
        Set ent(n, "open") = 0, ent(n, "start") = "", ent(n, "end") = ""
        If '..IsObject(x) Set:bad="" bad = ent(n, "path") Continue
        Set l = x.%Get("location"), ref = $SELECT(..IsObject(l): ..Str(l, "reference"), 1: "")
        Set ent(n, "ref") = ref
        If '..Literal(ref) Set:bad="" bad = ent(n, "path")
        Set est = x.%GetTypeOf("status"), st = ..Str(x, "status")
        If (est '= "unassigned") && '$LISTFIND($LISTBUILD("active", "completed"), st) Set:bad="" bad = ent(n, "path")
        Set per = x.%Get("period"), start = "", end = ""
        If ..IsObject(per) Set start = ..Str(per, "start"), end = ..Str(per, "end")
        If (start = "") || '..Instant(start, .ss) { Set:bad="" bad = ent(n, "path") } Else { Set ent(n, "start") = ss }
        If end '= "" { If '..Instant(end, .se) { Set:bad="" bad = ent(n, "path") } Else { Set ent(n, "end") = se } }
        Set isOpen = ((st = "active") || (est = "unassigned")) && (end = "")
        If (st = "completed") && (end = "") Set:bad="" bad = ent(n, "path")
        Set ent(n, "open") = isOpen, opens = opens + isOpen
        If (ref = target) && (start = event) {
            If s Set:bad="" bad = ent(n, "path")
            Set s = n
        }
    }
    If 's Quit "entry_gone"
    Set path = ent(s, "path")
    If 'ent(s, "open") && (ent(s, "end") '= "") && (ent(s, "end") <= sStart) Quit "entry_closed_at_own_start"
    If status = "entered-in-error" Set path = "/status" Quit "entered_in_error"
    For j = 1:1:n { If ent(j, "open") && (ent(j, "ref") = prior) Set path = ent(j, "path") Return "prior_active_again" }
    If opens > 1 Set path = "/location" Quit "overlapping_periods"
    // Overlaps from Shutter's start on: any pair with a member that is Shutter's entry or starts at or after it.
    For j = 1:1:n {
        Continue:(ent(j, "start") = "")
        For k = (j + 1):1:n {
            Continue:(ent(k, "start") = "")
            Continue:'((j = s) || (k = s) || (ent(j, "start") >= sStart) || (ent(k, "start") >= sStart))
            If ..Overlap(ent(j, "start"), ent(j, "end"), ent(k, "start"), ent(k, "end")) Set path = ent(k, "path") Return "overlapping_periods"
        }
    }
    If bad '= "" Set path = bad Quit "unfamiliar_shape"
    If status = "finished" {
        If opens > 0 Quit "unfamiliar_shape"
        Quit ""
    }
    If status '= "in-progress" Set path = "/status" Quit "unfamiliar_shape"
    If opens = 0 Set path = "/location" Quit "unfamiliar_shape"
    If ent(s, "open") Quit ""
    // Shutter's entry is completed after its own start; the one open entry is a later move to a mapped location.
    For j = 1:1:n {
        Continue:'ent(j, "open")
        Set path = ent(j, "path")
        If '..Mapped(ent(j, "ref"), b) Return "unfamiliar_shape"
        If ent(j, "start") < sStart Return "overlapping_periods"
    }
    Quit ""
}

/// Whether two periods overlap (an end of "" is open); touching ends do not.
ClassMethod Overlap(s1, e1, s2, e2) As %Boolean [ Private ]
{
    Set aEndsFirst = (e1 '= "") && (e1 <= s2)
    Set bEndsFirst = (e2 '= "") && (e2 <= s1)
    Quit '(aEndsFirst || bEndsFirst)
}

/// Whether a reference is one of the bound Locations (or the prior).
ClassMethod Mapped(ref As %String, b As %DynamicObject) As %Boolean [ Private ]
{
    If ref = b."prior_location" Quit 1
    Set iter = b.locations.%GetIterator()
    While iter.%GetNext(.i, .l) { If l.reference = ref Return 1 }
    Quit 0
}

/// "" when V's location array is the base's with the one shape applied (the open entry at the prior location completed
/// at the event time, one entry appended at the target, active from the event time), else the path that is not.
ClassMethod ShapeProblem(base As %DynamicObject, v As %DynamicObject, b As %DynamicObject) As %String [ Private ]
{
    Set bl = base.%Get("location"), vl = v.%Get("location")
    If '..IsArray(bl) || '..IsArray(vl) Quit "/location"
    Set n = bl.%Size()
    If vl.%Size() '= (n + 1) Quit "/location"
    Set event = b."event_time", opens = 0
    For j = 0:1:(n - 1) {
        Set be = bl.%Get(j), ve = vl.%Get(j)
        If ..IsObject(be) && ..IsPriorOpen(be, b."prior_location") {
            Set opens = opens + 1
            If (..Str(ve, "status") '= "completed") || '..IsObject(ve.%Get("period")) || (..Str(ve.period, "end") '= event) Return "/location/" _ j
            Set copy = ..Copy(ve)
            If be.%GetTypeOf("status") = "unassigned" { Do copy.%Remove("status") } Else { Set copy.status = be.status }
            Do copy.period.%Remove("end")
            If (copy.period.%Size() = 0) && (be.%GetTypeOf("period") = "unassigned") Do copy.%Remove("period")
            If ..FirstDiff(copy, be) '= "" Return "/location/" _ j
        } ElseIf ..FirstDiff(ve, be) '= "" {
            Return "/location/" _ j
        }
    }
    If opens '= 1 Quit "/location"
    Set want = {"location": {"reference": (b."target_location")}, "status": "active", "period": {"start": (event)}}
    If ..FirstDiff(vl.%Get(n), want) '= "" Quit "/location/" _ n
    Quit ""
}

/// Whether a location entry is open (status active or absent, no period.end) at the prior location.
ClassMethod IsPriorOpen(e As %DynamicObject, prior As %String) As %Boolean [ Private ]
{
    Set l = e.%Get("location")
    If '..IsObject(l) || (..Str(l, "reference") '= prior) Quit 0
    Set st = e.%GetTypeOf("status")
    If (st '= "unassigned") && (..Str(e, "status") '= "active") Quit 0
    Set per = e.%Get("period")
    If ..IsObject(per) && (per.%GetTypeOf("end") '= "unassigned") Quit 0
    Quit 1
}

/// "" when an Encounter's subject is the bound Patient and its identifier[] holds the bound identifier exactly
/// (case-sensitive, no other value under the same system), else the path that differs.
ClassMethod IdentityProblem(enc As %DynamicObject, b As %DynamicObject) As %String [ Private ]
{
    Set subj = enc.%Get("subject")
    If '..IsObject(subj) || (..Str(subj, "reference") '= b.patient.reference) Quit "/subject"
    If '..HoldsIdentifier(enc.%Get("identifier"), b."encounter_identifier") Quit "/identifier"
    Quit ""
}

/// Whether an identifier[] holds the wanted {system, value} exactly, and no other value under that system.
ClassMethod HoldsIdentifier(ids, want As %DynamicObject) As %Boolean [ Private ]
{
    If '..IsArray(ids) Quit 0
    Set found = 0, other = 0
    Set iter = ids.%GetIterator()
    While iter.%GetNext(.i, .id) {
        Continue:'..IsObject(id)
        Continue:(..Str(id, "system") '= want.system)
        If ..Str(id, "value") = want.value { Set found = 1 } Else { Set other = 1 }
    }
    Quit found && 'other
}

/// "" when the Patient read again is the bound one (its identifier exact, no link, not inactive), else what is wrong;
/// unread is set when it could not be read at all.
ClassMethod PatientProblem(read As %DynamicObject, b As %DynamicObject, Output unread As %Boolean) As %String [ Private ]
{
    Set unread = 1
    If read."http_status" '= 200 Quit "the Patient answered " _ read."http_status"
    Set ref = b.patient.reference
    If '..ParseResource(..Str(read, "body"), "Patient", $PIECE(ref, "/", 2), .p) || ($PIECE(ref, "/", 1) '= "Patient") Quit "the Patient read is not the bound Patient"
    Set unread = 0
    If '..HoldsIdentifier(p.%Get("identifier"), b.patient.identifier) Quit "the Patient's identifier is not the case's"
    Set links = p.%Get("link")
    If (p.%GetTypeOf("link") '= "unassigned") && ('..IsArray(links) || (links.%Size() > 0)) Quit "the Patient has a link"
    If (p.%GetTypeOf("active") = "boolean") && 'p.active Quit "the Patient is inactive"
    If (p.%GetTypeOf("active") '= "unassigned") && (p.%GetTypeOf("active") '= "boolean") Quit "the Patient's active flag is unreadable"
    Quit ""
}

/// "" when every bound Location read again is the mapped one (active, an identifier value equal to the checked one,
/// case-sensitive), else what is wrong; unread is set when one could not be read at all.
ClassMethod LocationsProblem(reads As %DynamicArray, b As %DynamicObject, Output unread As %Boolean) As %String [ Private ]
{
    Set unread = 0
    Set iter = b.locations.%GetIterator()
    While iter.%GetNext(.i, .want) {
        Set ref = want.reference, read = ""
        Set it2 = reads.%GetIterator()
        While it2.%GetNext(.j, .r) { If ..IsObject(r) && (..Str(r, "reference") = ref) Set read = r Quit }
        If '$ISOBJECT(read) || (read.%GetTypeOf("http_status") '= "number") || (read."http_status" '= 200) Set unread = 1 Return ref _ " was not read"
        If ($PIECE(ref, "/", 1) '= "Location") || '..ParseResource(..Str(read, "body"), "Location", $PIECE(ref, "/", 2), .loc) Set unread = 1 Return ref _ " is not the bound Location"
        If ..Str(loc, "status") '= "active" Return ref _ " is not active"
        Set found = 0, ids = loc.%Get("identifier")
        If ..IsArray(ids) {
            Set it3 = ids.%GetIterator()
            While it3.%GetNext(.k, .id) { If ..IsObject(id) && (..Str(id, "value") = want."checked_identifier") Set found = 1 }
        }
        If 'found Return ref _ " no longer carries the identifier " _ want."checked_identifier"
    }
    Quit ""
}

/// A copy of a body with meta.versionId and meta.lastUpdated removed, the server-owned fields removed, and when asked
/// the location array and one instance of the marker. An emptied meta.tag or meta is removed too, on both sides alike.
ClassMethod Strip(body As %DynamicObject, dropLocation As %Boolean, dropMarker As %Boolean, owned As %DynamicArray, b As %DynamicObject = "") As %DynamicObject [ Private ]
{
    Set c = ..Copy(body)
    If dropLocation Do c.%Remove("location")
    Set iter = owned.%GetIterator()
    While iter.%GetNext(.i, .f) { Do ..RemovePath(c, f) }
    Set meta = c.%Get("meta")
    If ..IsObject(meta) {
        Do meta.%Remove("versionId"), meta.%Remove("lastUpdated")
        Set tags = meta.%Get("tag")
        If dropMarker && ..IsArray(tags) {
            Set out = [], removed = 0
            Set it2 = tags.%GetIterator()
            While it2.%GetNext(.j, .t) {
                If 'removed && ..IsMarker(t, b) { Set removed = 1 } Else { Do out.%Push(t) }
            }
            Do meta.%Set("tag", out)
            Set tags = out
        }
        If ..IsArray(tags) && (tags.%Size() = 0) Do meta.%Remove("tag")
        If meta.%Size() = 0 Do c.%Remove("meta")
    }
    Quit c
}

/// Removes a dotted (or slashed) path from an object, if present.
ClassMethod RemovePath(obj As %DynamicObject, path As %String) [ Private ]
{
    Set p = $ZSTRIP($TRANSLATE(path, "/", "."), "<>", "."), node = obj
    For i = 1:1:($LENGTH(p, ".") - 1) {
        Set node = node.%Get($PIECE(p, ".", i))
        Quit:'..IsObject(node)
    }
    If ..IsObject(node) Do node.%Remove($PIECE(p, ".", $LENGTH(p, ".")))
}

/// How many meta.tag elements of a body are the exact marker.
ClassMethod MarkerCount(body As %DynamicObject, b As %DynamicObject) As %Integer [ Private ]
{
    Set meta = body.%Get("meta"), count = 0
    If '..IsObject(meta) Quit 0
    Set tags = meta.%Get("tag")
    If '..IsArray(tags) Quit 0
    Set iter = tags.%GetIterator()
    While iter.%GetNext(.i, .t) { Set:..IsMarker(t, b) count = count + 1 }
    Quit count
}

/// Whether a tag is the exact marker pair: the binding's marker system and operation id, as strings, case-sensitive.
ClassMethod IsMarker(tag, b As %DynamicObject) As %Boolean [ Private ]
{
    If '..IsObject(tag) || '$ISOBJECT(b) Quit 0
    Quit (tag.%GetTypeOf("system") = "string") && (tag.system = b."marker_system") && (tag.%GetTypeOf("code") = "string") && (tag.code = b."operation_id")
}

/// The version id of an ETag: defined only for exactly W/"..." (a capital W, no space, no quote inside).
ClassMethod ETagVid(etag As %String, Output vid As %String) As %Boolean
{
    Set vid = ""
    If ($EXTRACT(etag, 1, 3) '= "W/""") || ($EXTRACT(etag, *) '= """") || ($LENGTH(etag) < 5) Quit 0
    Set inner = $EXTRACT(etag, 4, * - 1)
    If inner [ """" Quit 0
    Set vid = inner
    Quit 1
}

/// Whether a Location header names version vid: its text after the last "_history/" is exactly vid.
ClassMethod LocationNames(loc As %String, vid As %String) As %Boolean [ Private ]
{
    If loc '[ "_history/" Quit 0
    Quit $PIECE(loc, "_history/", $LENGTH(loc, "_history/")) = vid
}

/// A FHIR instant with a time and an offset (YYYY-MM-DDThh:mm:ss[.fff](Z|+hh:mm|-hh:mm)) as seconds in UTC from the
/// start of the internal day count, so two instants compare as numbers. These are times, never version ids.
ClassMethod Instant(text As %String, Output seconds) As %Boolean
{
    Set seconds = ""
    If '$MATCH(text, "\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,9})?(Z|[+-]\d{2}:\d{2})") Quit 0
    Set day = $ZDATEH($EXTRACT(text, 1, 10), 3, , , , , , , -1)
    If day < 0 Quit 0
    Set h = +$EXTRACT(text, 12, 13), m = +$EXTRACT(text, 15, 16), s = +$EXTRACT(text, 18, 19)
    If (h > 23) || (m > 59) || (s > 59) Quit 0
    Set rest = $EXTRACT(text, 20, *), frac = 0
    If $EXTRACT(rest) = "." Set digits = $PIECE($EXTRACT(rest, 2, *), "Z", 1), digits = $PIECE($PIECE(digits, "+", 1), "-", 1), frac = +("0." _ digits), rest = $EXTRACT(rest, $LENGTH(digits) + 2, *)
    Set offset = 0
    If rest '= "Z" {
        Set oh = +$EXTRACT(rest, 2, 3), om = +$EXTRACT(rest, 5, 6)
        If (oh > 14) || (om > 59) Quit 0
        Set offset = (oh * 3600 + (om * 60)) * $SELECT($EXTRACT(rest) = "-": -1, 1: 1)
    }
    Set seconds = (day * 86400) + (h * 3600) + (m * 60) + s + frac - offset
    Quit 1
}

/// The JSON pointer paths where two values differ (objects key by key, whatever their order; arrays element by element;
/// scalars by type and value). An empty array means the same.
ClassMethod Diffs(a, b, path As %String = "", out As %DynamicArray = "") As %DynamicArray
{
    If '$ISOBJECT(out) Set out = []
    If '$ISOBJECT(a) || '$ISOBJECT(b) {
        If '$ISOBJECT(a) && '$ISOBJECT(b) && (a = b) Quit out
        Do out.%Push($SELECT(path = "": "/", 1: path))
        Quit out
    }
    Set aArr = a.%IsA("%DynamicArray"), bArr = b.%IsA("%DynamicArray")
    If aArr '= bArr Do out.%Push($SELECT(path = "": "/", 1: path)) Quit out
    If aArr {
        Set n = $SELECT(a.%Size() > b.%Size(): a.%Size(), 1: b.%Size())
        For i = 0:1:(n - 1) { Do ..DiffMember(a, b, i, path _ "/" _ i, out) }
        Quit out
    }
    Set iter = a.%GetIterator()
    While iter.%GetNext(.k, .v) { Do ..DiffMember(a, b, k, path _ "/" _ ..Escape(k), out) }
    Set iter = b.%GetIterator()
    While iter.%GetNext(.k, .v) { Do:(a.%GetTypeOf(k) = "unassigned") out.%Push(path _ "/" _ ..Escape(k)) }
    Quit out
}

/// Compares one member of two containers.
ClassMethod DiffMember(a, b, key, path As %String, out As %DynamicArray) [ Private ]
{
    Set ta = a.%GetTypeOf(key), tb = b.%GetTypeOf(key)
    If ta '= tb Do out.%Push(path) Quit
    If (ta = "object") || (ta = "array") Do ..Diffs(a.%Get(key), b.%Get(key), path, out) Quit
    If ta = "unassigned" Quit
    If ta = "null" Quit
    If a.%Get(key) '= b.%Get(key) Do out.%Push(path)
}

/// The first path where two values differ, or "" when they are the same.
ClassMethod FirstDiff(a, b) As %String [ Private ]
{
    Set d = ..Diffs(a, b)
    Quit $SELECT(d.%Size() > 0: d.%Get(0), 1: "")
}

ClassMethod Escape(key As %String) As %String [ Private ]
{
    Quit $REPLACE($REPLACE(key, "~", "~0"), "/", "~1")
}

/// Whether a JSON pointer is the given one or below it.
ClassMethod Under(path As %String, root As %String) As %Boolean [ Private ]
{
    Quit (path = root) || ($EXTRACT(path, 1, $LENGTH(root) + 1) = (root _ "/"))
}

/// Parses a body that must be a resource of the given type (and id, when one is given). Never throws.
ClassMethod ParseResource(text As %String, type As %String, id As %String, Output obj) As %Boolean [ Private ]
{
    Set obj = ""
    If text = "" Quit 0
    Try { Set obj = ##class(%DynamicAbstractObject).%FromJSON(text) } Catch { Set obj = "" }
    If '..IsObject(obj) Set obj = "" Quit 0
    If ..Str(obj, "resourceType") '= type Set obj = "" Quit 0
    If (id '= "") && (..Str(obj, "id") '= id) Set obj = "" Quit 0
    Quit 1
}

/// Whether a content type is FHIR JSON (or plain JSON), compared without case and parameters.
ClassMethod MediaOK(type As %String) As %Boolean [ Private ]
{
    Set t = $ZCONVERT($ZSTRIP($PIECE(type, ";", 1), "<>W"), "L")
    Quit (t = "application/fhir+json") || (t = "application/json")
}

/// A resource's meta.versionId when it is a non-empty string, else "".
ClassMethod VersionId(res As %DynamicObject) As %String [ Private ]
{
    Set meta = res.%Get("meta")
    If '..IsObject(meta) || (meta.%GetTypeOf("versionId") '= "string") Quit ""
    Quit meta.versionId
}

/// Whether a reference is literal: Location/{id}, the id as FHIR defines it.
ClassMethod Literal(ref As %String) As %Boolean [ Private ]
{
    Quit $MATCH(ref, "Location/[A-Za-z0-9\-.]{1,64}")
}

ClassMethod IdentifierShape(id) As %Boolean [ Private ]
{
    Quit ..IsObject(id) && (..Str(id, "system") '= "") && (..Str(id, "value") '= "")
}

/// A member's value when it is a string, else "".
ClassMethod Str(obj, key As %String) As %String [ Private ]
{
    If '..IsObject(obj) || (obj.%GetTypeOf(key) '= "string") Quit ""
    Quit obj.%Get(key)
}

/// A member's value, or "" when absent.
ClassMethod Member(obj, key As %String) [ Private ]
{
    If '..IsObject(obj) Quit ""
    Quit obj.%Get(key)
}

ClassMethod IsObject(x) As %Boolean [ Private ]
{
    Quit $ISOBJECT(x) && x.%IsA("%DynamicObject")
}

ClassMethod IsArray(x) As %Boolean [ Private ]
{
    Quit $ISOBJECT(x) && x.%IsA("%DynamicArray")
}

ClassMethod Copy(obj As %DynamicAbstractObject) As %DynamicAbstractObject [ Private ]
{
    Quit ##class(%DynamicAbstractObject).%FromJSON(obj.%ToJSON())
}

/// The sentence for the case. Version ids are quoted strings, never counts.
ClassMethod Words(outcome As %String, detail As %DynamicObject) As %String
{
    Set v = """" _ detail."committed_version" _ """", w = """" _ detail."current_version" _ """", base = """" _ detail."base_version" _ """"
    Set reason = detail.reason
    If outcome = "verified" Quit "Verified in Encounter version " _ v _ ": the approved location update is present, carrying Shutter's marker; no other field changed from version " _ base _ ", the version the write was conditional on."
    If outcome = "verified_continued" Quit "Verified in Encounter version " _ v _ ": the approved location update is present, carrying Shutter's marker. The current resource is version " _ w _ "; a later change followed."
    If outcome = "not_found" Quit "No version of this update was found in the history the receiver returned, from version """ _ detail."head_version" _ """ back to the base " _ base _ "; the receiver's history is not a proof that none was committed."
    If outcome = "committed_review" {
        Set why = $CASE(reason,
            "current_deleted": "the Encounter has since been deleted",
            "current_unreadable": "the current resource could not be read as the receiver's answer",
            "current_not_in_history": "the current read does not agree with the history the receiver returned",
            "history_delete_between": "the history shows a delete after that version",
            "entry_gone": "the current version " _ w _ " no longer shows the move",
            "entry_closed_at_own_start": "the current version " _ w _ " closes the move at or before its own start",
            "entered_in_error": "the current version " _ w _ " marks the Encounter entered in error",
            "prior_active_again": "the current version " _ w _ " shows the prior location active again",
            "overlapping_periods": "the current version " _ w _ " has overlapping or several open location entries",
            "unfamiliar_shape": "the current version " _ w _ " has a shape this check does not judge",
            "identity_differs": "the current version's subject or identifier is not the case's",
            "patient_changed": "the Patient read again is no longer the case's patient as it was",
            "location_changed": "a mapped Location read again is no longer the one checked, or is not active",
            : "it cannot be judged")
        Quit "The approved update is present in version " _ v _ ". The current record needs review: " _ why _ ". A person checks at the receiver."
    }
    If outcome = "failed" {
        Set why = $CASE(reason,
            "update_created": "the update created a resource instead of updating the one read",
            "marker_on_base": "the version the write was conditional on, or an older one, already carries this operation's marker",
            "applied_version_absent": "the receiver answered with a version that its history does not show as this update",
            "introducing_predecessor_not_base": "the version carrying the marker, " _ v _ ", does not follow the base " _ base _ " directly, so another version was overwritten",
            "introducing_not_projection": "the version carrying the marker, " _ v _ ", is not the approved change",
            "conflict_but_committed": "the receiver refused the update, yet version " _ v _ " carries it",
            : "the record contradicts itself")
        Quit "The receiver's record contradicts the update: " _ why _ ". A person checks at the receiver."
    }
    Set why = $CASE(reason,
        "context_invalid": "what was read is incomplete or inconsistent",
        "history_unavailable": "the Encounter's history could not be read",
        "history_paged": "the Encounter's history came in pages",
        "history_entry_unreadable": "an entry in the Encounter's history could not be read",
        "base_not_in_history": "the history does not show the base version " _ base,
        "base_differs": "the history's version " _ base _ " is not the body that was read",
        "history_delete_between": "the history shows a delete after the base version " _ base,
        "projection_without_marker": "a version shows the same location change without Shutter's marker, so it cannot be told from another writer's",
        "head_is_base": "the history still ends at the base version " _ base _ ", and the update may yet land",
        "settling": "no version of it is in the history yet, and the settle window is still open",
        "vread_unavailable": "the version the receiver named could not be read back",
        "vread_differs": "the version read back is not the one in the history",
        "etag_not_version": "the ETag does not name the version read",
        "location_header_differs": "the answer's Location names another version",
        "field_differs": "version " _ v _ " differs from the approved body at " _ detail.path,
        "identity_differs": "version " _ v _ " does not carry the case's subject and identifier",
        : "it cannot be established")
    Quit "The update's outcome is unknown: " _ why _ ". Shutter will not repeat it until its committed history can be established."
}

}
