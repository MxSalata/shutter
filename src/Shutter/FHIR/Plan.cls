/// The plan builder for a FHIR R4 receiver: from the Encounter as it was read (the sealed body) to the exact body of the
/// one update Shutter proposes, a ward-level location change of the shape append_active_complete_previous, and the
/// check that the two bodies differ only where that change may touch them.
///
/// Pure: class methods only, no storage, no globals, no network and no clock. Build never throws; every refusal is a
/// reason code and a detail object. The ordering of the move against the event time (FHIR_LATER_MOVE_AT_RECEIVER)
/// and meta.security (FHIR_RESTRICTED) are rows of the FHIR gate, not of this class.
///
/// Diff bounds where two bodies differ and the shape of what changed there, never what it changed to: it has no view,
/// marker or event time, so any mapped-looking target, any marker of the right shape and any end are in bounds. What
/// is sent must be bound to Build's own output, not to a body that passed Diff.
///
/// The comparison (Same) is the defined resource comparison: two JSON values are the same when they have the same
/// JSON type; objects have the same key set, in any order, and the same value under each key; arrays have the same
/// length and the same value at each index; strings are equal character for character; numbers are equal when their
/// JSON text is equal (1.50 and 1.5 differ); true, false and null equal only themselves. A difference is named by its
/// JSON pointer (/location/0/period/end).
Class Shutter.FHIR.Plan [ Abstract ]
{

/// A literal reference to a Location: the type, a slash and a FHIR id.
Parameter LITERALLOCATION = "^Location/[A-Za-z0-9.\-]{1,64}$";

/// A FHIR dateTime to the second, with optional fractions and a required zone.
Parameter EVENTTIME = "^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])T([01][0-9]|2[0-3]):[0-5][0-9]:([0-5][0-9]|60)(\.[0-9]+)?(Z|[+-]((0[0-9]|1[0-3]):[0-5][0-9]|14:00))$";

/// The marker's code: the operation id, 32 lower-case hex characters.
Parameter MARKERCODE = "^[0-9a-f]{32}$";

/// Builds the outbound body. Returns "" with <var>body</var> set to the exact text to send (its UTF-8 encoding is the
/// bytes on the wire), or a reason code with <var>body</var> empty.
/// <ul>
/// <li><var>encounterBody</var>: the sealed read, as characters (UTF-8 already decoded).</li>
/// <li><var>view</var>: {"prior_location", "target_location", "location_map": [{"ward", "bed", "location",
/// "checked_identifier"}]}, built by the gate from the profile and the message. Only its shape is trusted.</li>
/// <li><var>eventTime</var>: the FHIR dateTime to write as the end of the old entry and the start of the new one.</li>
/// <li><var>marker</var>: {"system", "code"}, the code 32 lower-case hex characters.</li>
/// </ul>
/// <var>detail</var> is {"completed_index", "appended_index", "marker_index", "paths"} on success, and
/// {"reason", "path"} (with "error" for a caught error) on refusal.
ClassMethod Build(encounterBody As %String, view As %DynamicObject, eventTime As %String, marker As %DynamicObject, Output body As %String, Output detail As %DynamicObject) As %String
{
    Set body = "", detail = {}
    Try {
        Set code = ..Apply(encounterBody, view, eventTime, marker, .body, .detail)
    } Catch err {
        Set code = "FHIR_SHAPE_UNSUPPORTED", detail = {"reason": "error", "error": (err.DisplayString())}
    }
    Set:code'="" body = ""
    Quit code
}

/// The touched paths between two bodies, each named once at the shallowest level where the two differ (an appended
/// array element is one path). Returns "" when they are exactly the paths of one location change and one marker, with
/// the touched values of that shape; otherwise FHIR_DIFF_OUT_OF_BOUNDS, with <var>paths</var> naming every touched
/// path ("" for a body that does not parse as a JSON object).
/// <p>The allowed set, from <var>before</var>: on its one open location entry i, /location/i/status and
/// /location/i/period/end (or /location/i/period when the entry had no period); /location/n, n the old length; and the
/// marker as /meta/tag/k (k the old tag count), /meta/tag when meta had no tag, or /meta when the body had no meta.</p>
ClassMethod Diff(before As %String, after As %String, Output paths As %DynamicArray) As %String
{
    Set paths = [], code = "FHIR_DIFF_OUT_OF_BOUNDS"
    Try {
        Set b = ..Parse(before), a = ..Parse(after)
        If ('$ISOBJECT(b)) || ('$ISOBJECT(a)) {
            Do paths.%Push("")
            Quit
        }
        Do ..Walk([(b)], 0, [(a)], 0, "", paths, 0)
        Set:..InBounds(b, a, paths) code = ""
    } Catch err {
        Set paths = [""], code = "FHIR_DIFF_OUT_OF_BOUNDS"
    }
    Quit code
}

/// Lower-case hex SHA-256 of the UTF-8 encoding of the body: what the binding and the connector both digest.
ClassMethod BodyDigest(body As %String) As %String
{
    Set hash = $SYSTEM.Encryption.SHAHash(256, $ZCONVERT(body, "O", "UTF8"))
    Quit $ZCONVERT(##class(%xsd.hexBinary).LogicalToXSD(hash), "L")
}

/// Build's rules in order; the first failure wins.
ClassMethod Apply(encounterBody As %String, view As %DynamicObject, eventTime As %String, marker As %DynamicObject, Output body As %String, Output detail As %DynamicObject) As %String [ Private ]
{
    Set body = "", detail = {}

    // The inputs: the caller's, so a bad one is a shape this builder cannot apply.
    Set path = ..ViewProblem(view)
    Quit:path'="" ..Refuse("FHIR_SHAPE_UNSUPPORTED", "view", path, .detail)
    If ('$DATA(eventTime)) || ($ISOBJECT(eventTime)) || ('$MATCH(eventTime, ..#EVENTTIME)) {
        Quit ..Refuse("FHIR_SHAPE_UNSUPPORTED", "event_time", "", .detail)
    }
    Quit:'..MarkerShape(marker) ..Refuse("FHIR_SHAPE_UNSUPPORTED", "marker", "", .detail)

    // 1. An Encounter with an id.
    Set enc = ..Parse(encounterBody)
    Quit:'$ISOBJECT(enc) ..Refuse("FHIR_SHAPE_UNSUPPORTED", "not_json", "", .detail)
    Quit:'enc.%IsA("%Library.DynamicObject") ..Refuse("FHIR_SHAPE_UNSUPPORTED", "not_encounter", "", .detail)
    If (enc.%GetTypeOf("resourceType") '= "string") || (enc.resourceType '= "Encounter") {
        Quit ..Refuse("FHIR_SHAPE_UNSUPPORTED", "not_encounter", "/resourceType", .detail)
    }
    If (enc.%GetTypeOf("id") '= "string") || (enc.id = "") {
        Quit ..Refuse("FHIR_SHAPE_UNSUPPORTED", "no_id", "/id", .detail)
    }

    // 2. The round-trip guard: the platform must give back the text it was given (bar whitespace outside strings), or
    // the outbound body would change bytes this plan does not mean to touch.
    Set given = ..Compact(encounterBody), again = enc.%ToJSON()
    If given '= again {
        Set at = 1
        While ($EXTRACT(given, at) = $EXTRACT(again, at)) && (at <= $LENGTH(given)) { Set at = at + 1 }
        Do ..Refuse("FHIR_SHAPE_UNSUPPORTED", "body_not_lossless", "", .detail)
        Set detail.offset = at
        Quit "FHIR_SHAPE_UNSUPPORTED"
    }

    // 3. A subsetted representation, before anything that reads meta.versionId. SUBSETTED is a reserved code with one
    // meaning, so it is a stop under any system (R4's v3-ObservationValue, STU3's URI for it, or none).
    Set meta = $SELECT(enc.%GetTypeOf("meta") = "object": enc.meta, 1: "")
    If $ISOBJECT(meta) && (meta.%GetTypeOf("tag") = "array") {
        For j = 0:1:meta.tag.%Size() - 1 {
            Continue:meta.tag.%GetTypeOf(j)'="object"
            Set tag = meta.tag.%Get(j)
            Quit:(tag.%GetTypeOf("code")="string")&&(tag.code="SUBSETTED")
            Kill tag
        }
        Quit:$DATA(tag) ..Refuse("FHIR_REPRESENTATION_PARTIAL", "subsetted", "/meta/tag/" _ j, .detail)
    }

    // 4. A modifierExtension anywhere.
    Set path = ..FindKey(enc, "modifierExtension", "")
    Quit:path'="" ..Refuse("FHIR_MODIFIER_EXTENSION", "modifier_extension", path, .detail)
    // implicitRules is a modifier element of every resource: a body read under rules Shutter does not know is not rewritten.
    Quit:enc.%GetTypeOf("implicitRules")'="unassigned" ..Refuse("FHIR_MODIFIER_EXTENSION", "implicit_rules", "/implicitRules", .detail)

    // 5. A narrative: the move would leave it describing the old location.
    Quit:enc.%GetTypeOf("text")'="unassigned" ..Refuse("FHIR_NARRATIVE_PRESENT", "narrative", "/text", .detail)

    // 6. Only an encounter in progress moves.
    If (enc.%GetTypeOf("status") '= "string") || (enc.status '= "in-progress") {
        Quit ..Refuse("FHIR_STATUS_NOT_IN_PROGRESS", "status", "/status", .detail)
    }

    // 7. Ward level only, and the target in the map.
    Set map = view."location_map", target = view."target_location", mapped = 0
    For j = 0:1:map.%Size() - 1 {
        Set entry = map.%Get(j)
        If (entry.%GetTypeOf("bed") '= "unassigned") && (entry.%GetTypeOf("bed") '= "null") {
            Quit
        }
        Set:entry.location=target mapped = 1
        Kill entry
    }
    Quit:$DATA(entry) ..Refuse("FHIR_BED_MOVE_UNSUPPORTED", "bed", "/location_map/" _ j _ "/bed", .detail)
    Quit:'mapped ..Refuse("FHIR_LOCATION_UNMAPPED", "target", "/target_location", .detail)

    // 8. Exactly one open entry, and every open entry a literal reference in the map. A pending entry (a planned move,
    // a held place) is a stop: moving the patient past it is for a person to decide.
    Set type = enc.%GetTypeOf("location")
    If (type '= "unassigned") && (type '= "array") {
        Quit ..Refuse("FHIR_SHAPE_UNSUPPORTED", "location", "/location", .detail)
    }
    Set locations = $SELECT(type = "array": enc.location, 1: []), n = locations.%Size()
    Set open = "", count = 0, problem = "", path = ""
    For i = 0:1:n - 1 {
        Set state = ..EntryState(locations, i)
        If state = "" {
            Set problem = "location_entry", path = "/location/" _ i
            Quit
        }
        If state = "pending" {
            Set problem = "pending_entry", path = "/location/" _ i
            Quit
        }
        Continue:state'="open"
        Set ref = ..OpenReference(locations.%Get(i))
        If (ref = "") || ('..InMap(map, ref)) {
            Set problem = "open_entry_unmapped", path = "/location/" _ i
            Quit
        }
        Set count = count + 1, open = i
    }
    Quit:problem'="" ..Refuse("FHIR_SHAPE_UNSUPPORTED", problem, path, .detail)
    If count '= 1 {
        Do ..Refuse("FHIR_SHAPE_UNSUPPORTED", "open_entries", "/location", .detail)
        Set detail."open_entries" = count
        Quit "FHIR_SHAPE_UNSUPPORTED"
    }

    // An extension on the open entry's own status (FHIR's _status) would come to describe "completed".
    If locations.%Get(open).%GetTypeOf("_status") '= "unassigned" {
        Quit ..Refuse("FHIR_SHAPE_UNSUPPORTED", "status_extension", "/location/" _ open _ "/_status", .detail)
    }

    // 9. The receiver's active location is the message's prior one, and the target is somewhere else.
    Set current = locations.%Get(open).location.reference
    Quit:current'=view."prior_location" ..Refuse("FHIR_PRIOR_LOCATION_DIFFERS", "prior", "/location/" _ open, .detail)
    Quit:target=current ..Refuse("FHIR_ALREADY_THERE", "already_there", "/location/" _ open, .detail)

    // 10. The marker: meta and its tags readable, and this exact pair not already there (a reused code). Other tags,
    // other codes under the same system included, are kept as data.
    Set type = enc.%GetTypeOf("meta")
    Quit:(type'="unassigned")&&(type'="object") ..Refuse("FHIR_SHAPE_UNSUPPORTED", "meta", "/meta", .detail)
    If type = "object" {
        Set type = meta.%GetTypeOf("tag")
        Quit:(type'="unassigned")&&(type'="array") ..Refuse("FHIR_SHAPE_UNSUPPORTED", "meta_tag", "/meta/tag", .detail)
        If type = "array" {
            For j = 0:1:meta.tag.%Size() - 1 {
                Continue:meta.tag.%GetTypeOf(j)'="object"
                Set tag = meta.tag.%Get(j)
                Quit:(tag.%GetTypeOf("system")="string")&&(tag.%GetTypeOf("code")="string")&&(tag.system=marker.system)&&(tag.code=marker.code)
                Kill tag
            }
            Quit:$DATA(tag) ..Refuse("FHIR_SHAPE_UNSUPPORTED", "marker_present", "/meta/tag/" _ j, .detail)
        }
    }

    // 11. Apply: complete the open entry, append the new one, add the marker. meta.versionId and meta.lastUpdated stay
    // as read; nothing else is touched.
    Set entry = locations.%Get(open)
    Do entry.%Set("status", "completed")
    If entry.%GetTypeOf("period") = "object" {
        Do entry.period.%Set("end", eventTime)
    } Else {
        Do entry.%Set("period", {"end": (eventTime)})
    }
    Do locations.%Push({"location": {"reference": (target)}, "status": "active", "period": {"start": (eventTime)}})
    Set tag = {"system": (marker.system), "code": (marker.code)}
    If '$ISOBJECT(meta) {
        Do enc.%Set("meta", {"tag": [(tag)]})
        Set k = 0
    } ElseIf meta.%GetTypeOf("tag") = "array" {
        Set k = meta.tag.%Size()
        Do meta.tag.%Push(tag)
    } Else {
        Do meta.%Set("tag", [(tag)])
        Set k = 0
    }
    Set text = enc.%ToJSON()

    // 12. The self-check: a builder bug, never expected.
    Set code = ..Diff(encounterBody, text, .paths)
    If code '= "" {
        Do ..Refuse(code, "self_check", "", .detail)
        Set detail.paths = paths
        Quit code
    }
    Set body = text
    Set detail = {"completed_index": (open), "appended_index": (n), "marker_index": (k), "paths": (paths)}
    Quit ""
}

/// Sets the refusal's detail and returns its code.
ClassMethod Refuse(code As %String, reason As %String, path As %String, Output detail As %DynamicObject) As %String [ Private ]
{
    Set detail = {"reason": (reason), "path": (path)}
    Quit code
}

/// The view's first shape problem, as a pointer into it ("" when it has the shape Build reads). Every map entry must
/// name a literal Location reference.
ClassMethod ViewProblem(view) As %String [ Private ]
{
    Quit:'$ISOBJECT(view) "/"
    Quit:'view.%IsA("%Library.DynamicObject") "/"
    Quit:view.%GetTypeOf("prior_location")'="string" "/prior_location"
    Quit:view.%GetTypeOf("target_location")'="string" "/target_location"
    // An empty one is a message with no location (PV1-6 or PV1-3 absent), not a receiver whose location differs.
    Quit:view."prior_location"="" "/prior_location"
    Quit:view."target_location"="" "/target_location"
    Quit:view.%GetTypeOf("location_map")'="array" "/location_map"
    Set map = view."location_map", problem = ""
    For j = 0:1:map.%Size() - 1 {
        If map.%GetTypeOf(j) '= "object" {
            Set problem = "/location_map/" _ j
            Quit
        }
        Set entry = map.%Get(j)
        If (entry.%GetTypeOf("location") '= "string") || ('$MATCH(entry.location, ..#LITERALLOCATION)) {
            Set problem = "/location_map/" _ j _ "/location"
            Quit
        }
    }
    Quit problem
}

/// True when the marker is exactly {"system": a non-empty string, "code": 32 lower-case hex}.
ClassMethod MarkerShape(marker) As %Boolean [ Private ]
{
    Quit:'$ISOBJECT(marker) 0
    Quit:'marker.%IsA("%Library.DynamicObject") 0
    Quit:(marker.%GetTypeOf("system")'="string")||(marker.%GetTypeOf("code")'="string") 0
    Quit:marker.%Size()'=2 0
    Quit:marker.system="" 0
    Quit $MATCH(marker.code, ..#MARKERCODE)
}

/// "open", "closed", "pending", or "" for an entry this builder cannot read. An entry is open when its status is
/// active or absent and it has no period.end; closed when it has an end and its status is active or absent, or its
/// status is completed; pending for any other status (planned, reserved, or one R4 does not define), end or not.
ClassMethod EntryState(locations As %DynamicArray, i As %Integer) As %String [ Private ]
{
    Quit:locations.%GetTypeOf(i)'="object" ""
    Set entry = locations.%Get(i)
    Set status = entry.%GetTypeOf("status"), period = entry.%GetTypeOf("period")
    Quit:(status'="unassigned")&&(status'="string") ""
    Quit:(period'="unassigned")&&(period'="object") ""
    Set end = $SELECT(period = "object": entry.period.%GetTypeOf("end"), 1: "unassigned")
    Quit:(end'="unassigned")&&(end'="string") ""
    If status = "string" {
        Quit:entry.status="completed" "closed"
        Quit:entry.status'="active" "pending"
    }
    Quit $SELECT(end '= "unassigned": "closed", 1: "open")
}

/// The entry's location.reference when it is a literal Location reference, else "".
ClassMethod OpenReference(entry As %DynamicObject) As %String [ Private ]
{
    Quit:entry.%GetTypeOf("location")'="object" ""
    Quit:entry.location.%GetTypeOf("reference")'="string" ""
    Set ref = entry.location.reference
    Quit $SELECT($MATCH(ref, ..#LITERALLOCATION): ref, 1: "")
}

/// True when a map entry's location is the reference, character for character.
ClassMethod InMap(map As %DynamicArray, ref As %String) As %Boolean [ Private ]
{
    Set found = 0
    For j = 0:1:map.%Size() - 1 {
        If map.%Get(j).location = ref {
            Set found = 1
            Quit
        }
    }
    Quit found
}

/// The first path, in document order, of an object key named <var>name</var> at any depth, or "".
ClassMethod FindKey(value As %DynamicAbstractObject, name As %String, path As %String) As %String [ Private ]
{
    Set found = "", isObject = value.%IsA("%Library.DynamicObject")
    If isObject {
        Set iter = value.%GetIterator()
        While iter.%GetNext(.key) {
            Set here = path _ "/" _ ..Token(key)
            If key = name {
                Set found = here
                Quit
            }
            Set type = value.%GetTypeOf(key)
            If (type = "object") || (type = "array") {
                Set found = ..FindKey(value.%Get(key), name, here)
                Quit:found'=""
            }
        }
    } Else {
        For i = 0:1:value.%Size() - 1 {
            Set type = value.%GetTypeOf(i)
            Continue:(type'="object")&&(type'="array")
            Set found = ..FindKey(value.%Get(i), name, path _ "/" _ i)
            Quit:found'=""
        }
    }
    Quit found
}

/// The parsed JSON object or array, or "" when the text is not JSON.
ClassMethod Parse(text) As %DynamicAbstractObject [ Private ]
{
    Quit:$ISOBJECT($GET(text)) ""
    Quit:$GET(text)="" ""
    Try {
        Set value = ##class(%DynamicAbstractObject).%FromJSON(text)
    } Catch {
        Set value = ""
    }
    Quit value
}

/// The text with JSON's insignificant whitespace (space, tab, line feed, carriage return outside strings) removed.
ClassMethod Compact(text As %String) As %String [ Private ]
{
    Set out = "", inString = 0, i = 1, n = $LENGTH(text)
    While i <= n {
        Set c = $EXTRACT(text, i)
        If inString {
            If c = "\" {
                Set out = out _ $EXTRACT(text, i, i + 1), i = i + 2
                Continue
            }
            Set:c="""" inString = 0
            Set out = out _ c, i = i + 1
            Continue
        }
        Set:c="""" inString = 1
        Set:(c'=" ")&&(c'=$CHAR(9))&&(c'=$CHAR(10))&&(c'=$CHAR(13)) out = out _ c
        Set i = i + 1
    }
    Quit out
}

/// A JSON pointer reference token: "~" as "~0" and "/" as "~1".
ClassMethod Token(key As %String) As %String [ Private ]
{
    Quit $REPLACE($REPLACE(key, "~", "~0"), "/", "~1")
}

/// The defined comparison of two JSON values (objects or arrays): true when they are the same, else false with
/// <var>path</var> the first difference.
ClassMethod Same(a As %DynamicAbstractObject, b As %DynamicAbstractObject, Output path As %String) As %Boolean [ Private ]
{
    Set paths = []
    Set same = ..Walk([(a)], 0, [(b)], 0, "", paths, 1)
    Set path = $SELECT(paths.%Size(): paths.%Get(0), 1: "")
    Quit same
}

/// Compares the member <var>ka</var> of <var>ca</var> with the member <var>kb</var> of <var>cb</var> under the defined
/// comparison, pushing onto <var>paths</var> each shallowest path where they differ (only the first when
/// <var>first</var> is true). Returns true when they are the same.
ClassMethod Walk(ca As %DynamicAbstractObject, ka, cb As %DynamicAbstractObject, kb, path As %String, paths As %DynamicArray, first As %Boolean) As %Boolean [ Private ]
{
    Set ta = ca.%GetTypeOf(ka), tb = cb.%GetTypeOf(kb)
    If ta '= tb {
        Do paths.%Push(path)
        Quit 0
    }
    If ta = "object" {
        Set oa = ca.%Get(ka), ob = cb.%Get(kb), same = 1
        Set iter = oa.%GetIterator()
        While iter.%GetNext(.key) {
            If '..Walk(oa, key, ob, key, path _ "/" _ ..Token(key), paths, first) {
                Set same = 0
                Quit:first
            }
        }
        Quit:'same&&first 0
        Set iter = ob.%GetIterator()
        While iter.%GetNext(.key) {
            Continue:oa.%GetTypeOf(key)'="unassigned"
            Do paths.%Push(path _ "/" _ ..Token(key))
            Set same = 0
            Quit:first
        }
        Quit same
    }
    If ta = "array" {
        Set aa = ca.%Get(ka), ab = cb.%Get(kb), same = 1
        Set na = aa.%Size(), nb = ab.%Size(), common = $SELECT(na < nb: na, 1: nb)
        For i = 0:1:common - 1 {
            If '..Walk(aa, i, ab, i, path _ "/" _ i, paths, first) {
                Set same = 0
                Quit:first
            }
        }
        Quit:'same&&first 0
        For i = common:1:$SELECT(na > nb: na, 1: nb) - 1 {
            Do paths.%Push(path _ "/" _ i)
            Set same = 0
            Quit:first
        }
        Quit same
    }
    If ta = "number" {
        Set same = (ca.%Get(ka, , "json") = cb.%Get(kb, , "json"))
    } ElseIf (ta = "null") || (ta = "unassigned") {
        Set same = 1
    } Else {
        // Strings and booleans: ObjectScript's = compares text, so "1" and "1.0" differ.
        Set same = (ca.%Get(ka) = cb.%Get(kb))
    }
    Do:'same paths.%Push(path)
    Quit same
}

/// True when the touched <var>paths</var> are exactly the allowed set that <var>before</var> gives, and the touched
/// values in <var>after</var> have the shape of the change: the old entry completed with an end, one new active entry
/// starting at that end, and one marker tag.
ClassMethod InBounds(before As %DynamicAbstractObject, after As %DynamicAbstractObject, paths As %DynamicArray) As %Boolean [ Private ]
{
    Quit:'before.%IsA("%Library.DynamicObject") 0
    Quit:'after.%IsA("%Library.DynamicObject") 0
    Quit:before.%GetTypeOf("location")'="array" 0
    Set locations = before.location, n = locations.%Size(), open = "", count = 0, state = "closed"
    For i = 0:1:n - 1 {
        Set state = ..EntryState(locations, i)
        Quit:state=""
        Set:state="open" open = i, count = count + 1
    }
    Quit:state="" 0
    Quit:count'=1 0

    // The allowed set.
    Set periodAbsent = (locations.%Get(open).%GetTypeOf("period") = "unassigned")
    Set allowed("/location/" _ open _ "/status") = ""
    Set allowed("/location/" _ open _ $SELECT(periodAbsent: "/period", 1: "/period/end")) = ""
    Set allowed("/location/" _ n) = ""
    Set type = before.%GetTypeOf("meta")
    If type = "unassigned" {
        Set markerPath = "/meta"
    } ElseIf type '= "object" {
        Quit 0
    } ElseIf before.meta.%GetTypeOf("tag") = "unassigned" {
        Set markerPath = "/meta/tag"
    } ElseIf before.meta.%GetTypeOf("tag") = "array" {
        Set markerPath = "/meta/tag/" _ before.meta.tag.%Size()
    } Else {
        Quit 0
    }
    Set allowed(markerPath) = ""

    // Exactly that set: no other path, none missing, none twice.
    Set touched = 0, ok = 1
    For j = 0:1:paths.%Size() - 1 {
        Set p = paths.%Get(j)
        If ('$DATA(allowed(p))) || ($DATA(seen(p))) {
            Set ok = 0
            Quit
        }
        Set seen(p) = "", touched = touched + 1
    }
    Quit:'ok 0
    Quit:touched'=4 0

    // The values on those paths.
    Quit:after.%GetTypeOf("location")'="array" 0
    Quit:after.location.%GetTypeOf(open)'="object" 0
    Set done = after.location.%Get(open)
    Quit:(done.%GetTypeOf("status")'="string")||(done.status'="completed") 0
    Quit:done.%GetTypeOf("period")'="object" 0
    Quit:done.period.%GetTypeOf("end")'="string" 0
    Quit:periodAbsent&&(done.period.%Size()'=1) 0
    Set end = done.period.end
    Quit:after.location.%GetTypeOf(n)'="object" 0
    Set added = after.location.%Get(n)
    Quit:'..ExactKeys(added, "location,status,period") 0
    Quit:(added.%GetTypeOf("location")'="object")||('..ExactKeys(added.location, "reference")) 0
    Quit:(added.location.%GetTypeOf("reference")'="string")||('$MATCH(added.location.reference, ..#LITERALLOCATION)) 0
    Quit:(added.%GetTypeOf("status")'="string")||(added.status'="active") 0
    Quit:(added.%GetTypeOf("period")'="object")||('..ExactKeys(added.period, "start")) 0
    Quit:(added.period.%GetTypeOf("start")'="string")||(added.period.start'=end) 0
    Quit:after.%GetTypeOf("meta")'="object" 0
    If markerPath = "/meta" {
        Quit:'..ExactKeys(after.meta, "tag") 0
    }
    Quit:after.meta.%GetTypeOf("tag")'="array" 0
    Set tags = after.meta.tag
    Quit:(markerPath'["/meta/tag/")&&(tags.%Size()'=1) 0
    Set k = tags.%Size() - 1
    Quit:tags.%GetTypeOf(k)'="object" 0
    Set tag = tags.%Get(k)
    Quit:'..ExactKeys(tag, "system,code") 0
    Quit:(tag.%GetTypeOf("system")'="string")||(tag.%GetTypeOf("code")'="string") 0
    Quit:(tag.system="")||('$MATCH(tag.code, ..#MARKERCODE)) 0
    Quit 1
}

/// True when the object has exactly the comma-separated keys, in any order.
ClassMethod ExactKeys(obj As %DynamicObject, keys As %String) As %Boolean [ Private ]
{
    Quit:'$ISOBJECT(obj) 0
    Quit:'obj.%IsA("%Library.DynamicObject") 0
    Quit:obj.%Size()'=$LENGTH(keys, ",") 0
    Set ok = 1
    For j = 1:1:$LENGTH(keys, ",") {
        If obj.%GetTypeOf($PIECE(keys, ",", j)) = "unassigned" {
            Set ok = 0
            Quit
        }
    }
    Quit ok
}

}
