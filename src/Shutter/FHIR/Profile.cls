/// A FHIR R4 receiver's entry in the site profile: the validator of its fhir block, the readers of the stored block,
/// and the two constants every FHIR part reads here, so that none of them waits for another's class.
///
/// The entry is named after the engine item that failed, as every entry is. Its fhir block holds the path in front of
/// every request, the switch for recovery, the identifier systems of the encounter, the patient and the recovery
/// marker, and the map from the site's ward codes to the server's Location resources. The server, port, TLS and
/// credential are adapter settings of the FHIR items, never of the profile. One FHIR receiver per install in this
/// version.
///
/// Pure: class methods only. SettingsProblem reads what it is given; the readers read the stored profile through
/// Shutter.Store.SiteProfile.
Class Shutter.FHIR.Profile [ Abstract ]
{

/// The FHIR gate's policy version. The gate, the flow, the write and the Doctor all read it here.
Parameter POLICYVERSION = "fhir-2026-11-14.1";

/// The production items of the FHIR route, in the order they are installed.
Parameter ITEMS = "FHIR Receiver,FHIR Out,FHIR Gate,FHIR Verifier";

/// The most wards a location map may hold, and the fewest: a move needs two.
Parameter MAXWARDS = 25;

Parameter MINWARDS = 2;

/// What is wrong with a receiver entry that has a fhir key: "" or the problem as a suffix starting with a dot, to go
/// after "receivers[index]". r is the entry, receivers the profile's whole list and index the entry's place in it.
ClassMethod SettingsProblem(r As %DynamicObject, receivers As %DynamicArray, index As %Integer) As %String
{
    Set f = r.%Get("fhir")
    If (r.%GetTypeOf("fhir") '= "object") || '$ISOBJECT(f) Quit ".fhir: must be an object"
    Set it = f.%GetIterator()
    While it.%GetNext(.k, .v) {
        If '$LISTFIND($LISTBUILD("base", "recovery_enabled", "encounter_identifier", "patient_identifier", "marker", "location_map"), k) Return ".fhir." _ k _ ": unknown setting"
    }
    If (f.%GetTypeOf("base") '= "string") || ($EXTRACT(f.%Get("base"), 1) '= "/") Quit ".fhir.base: must be a path starting with /"
    // Absent reads false: a site turns recovery on by saying so.
    If f.%IsDefined("recovery_enabled") && (f.%GetTypeOf("recovery_enabled") '= "boolean") Quit ".fhir.recovery_enabled: must be true or false"
    Set problem = ..KeysProblem(f, "encounter_identifier", $LISTBUILD("system"))
    If problem '= "" Quit ".fhir" _ problem
    Set problem = ..KeysProblem(f, "patient_identifier", $LISTBUILD("system", "hl7_authority"))
    If problem '= "" Quit ".fhir" _ problem
    Set problem = ..KeysProblem(f, "marker", $LISTBUILD("system"))
    If problem '= "" Quit ".fhir" _ problem
    Set problem = ..MapProblem(f)
    If problem '= "" Quit ".fhir" _ problem
    // Beside a fhir block: one read route and one write route, both the FHIR server's own.
    If r.%IsDefined("api") Quit ".fhir: an entry with a fhir block has no api"
    If r.%IsDefined("features") Quit ".fhir: capability is read from the server, so features is refused"
    If (r.%GetTypeOf("engine_resend") = "boolean") && r.%Get("engine_resend") Quit ".engine_resend: refused beside fhir, one write route per receiver"
    If r.%IsDefined("category") && (r.%Get("category") '= "current_state") Quit ".category: must be current_state beside fhir"
    If (r.%GetTypeOf("strict_answers") = "boolean") && 'r.%Get("strict_answers") Quit ".strict_answers: refused beside fhir"
    If r.%IsDefined("documents") Quit ".documents: refused beside fhir"
    If r.%Get("history_policy") = "correct" Quit ".history_policy: refused beside fhir"
    For k = 0:1:index - 1 {
        Set earlier = receivers.%Get(k)
        If $ISOBJECT(earlier) && earlier.%IsDefined("fhir") Return ".fhir: one FHIR receiver per install in this version"
    }
    Quit ""
}

/// An object of the block that holds only the named keys, each a non-empty string: "" or the problem, starting with
/// the object's own name.
ClassMethod KeysProblem(f As %DynamicObject, name As %String, keys As %List) As %String [ Private ]
{
    Set at = "." _ name
    If f.%GetTypeOf(name) '= "object" Quit at _ "." _ $LIST(keys, 1) _ ": required"
    Set o = f.%Get(name)
    Set it = o.%GetIterator()
    While it.%GetNext(.k, .v) { If '$LISTFIND(keys, k) Return at _ "." _ k _ ": unknown setting" }
    Set ptr = 0
    While $LISTNEXT(keys, ptr, key) { If '..IsText(o, key) Return at _ "." _ key _ ": required" }
    Quit ""
}

/// The location map: 2 to 25 wards, each with its own ward code, its own Location and the Location's identifier.
ClassMethod MapProblem(f As %DynamicObject) As %String [ Private ]
{
    Set whole = ".location_map: must be an array of " _ ..#MINWARDS _ " to " _ ..#MAXWARDS _ " wards"
    If f.%GetTypeOf("location_map") '= "array" Quit whole
    Set map = f.%Get("location_map")
    If (map.%Size() < ..#MINWARDS) || (map.%Size() > ..#MAXWARDS) Quit whole
    For j = 0:1:map.%Size() - 1 { If map.%GetTypeOf(j) '= "object" Return whole }
    For j = 0:1:map.%Size() - 1 {
        Set e = map.%Get(j), at = ".location_map[" _ j _ "]"
        Set it = e.%GetIterator()
        While it.%GetNext(.k, .v) { If '$LISTFIND($LISTBUILD("ward", "location", "identifier"), k) Return at _ "." _ k _ ": unknown setting" }
        If '..IsText(e, "ward") Return at _ ".ward: required"
        If $DATA(wards(e.%Get("ward"))) Return at _ ".ward: must be unique"
        Set wards(e.%Get("ward")) = ""
        If '..IsText(e, "location") Return at _ ".location: required"
        If '$MATCH(e.%Get("location"), "Location/[A-Za-z0-9.\-]{1,64}") Return at _ ".location: must be Location/{id}"
        If $DATA(locations(e.%Get("location"))) Return at _ ".location: must be unique"
        Set locations(e.%Get("location")) = ""
        Set problem = ..KeysProblem(e, "identifier", $LISTBUILD("system", "value"))
        If problem '= "" Return at _ problem
    }
    Quit ""
}

/// Whether a key of an object holds a non-empty string.
ClassMethod IsText(o As %DynamicObject, key As %String) As %Boolean [ Private ]
{
    Quit (o.%GetTypeOf(key) = "string") && (o.%Get(key) '= "")
}

/// The fhir object of the stored profile's entry of that name, or "" when the entry has none or the profile does not
/// name the receiver.
ClassMethod Block(name As %String) As %DynamicObject
{
    Set r = ##class(Shutter.Store.SiteProfile).Receiver(name)
    Quit $SELECT($ISOBJECT(r) && $ISOBJECT(r.%Get("fhir")): r.%Get("fhir"), 1: "")
}

/// Whether the stored entry of that name turns recovery on: recovery_enabled true, and nothing else.
ClassMethod Enabled(name As %String) As %Boolean
{
    Set block = ..Block(name)
    If '$ISOBJECT(block) || (block.%GetTypeOf("recovery_enabled") '= "boolean") Quit 0
    Quit ''block.%Get("recovery_enabled")
}

/// The map entry of a ward code (ward, location, identifier), or "" when the map does not hold the ward.
ClassMethod LocationOf(block As %DynamicObject, ward As %String) As %DynamicObject
{
    Quit ..MapEntry(block, "ward", ward)
}

/// The ward code of a Location reference of the form Location/{id}, or "" when the map does not hold the reference.
ClassMethod WardOf(block As %DynamicObject, reference As %String) As %String
{
    Set e = ..MapEntry(block, "location", reference)
    Quit $SELECT($ISOBJECT(e): e.%Get("ward"), 1: "")
}

/// The first map entry whose key holds exactly that value, or "".
ClassMethod MapEntry(block As %DynamicObject, key As %String, value As %String) As %DynamicObject [ Private ]
{
    If '$ISOBJECT(block) || (value = "") || (block.%GetTypeOf("location_map") '= "array") Quit ""
    Set it = block.%Get("location_map").%GetIterator()
    While it.%GetNext(.j, .e) { If $ISOBJECT(e) && (e.%GetTypeOf(key) = "string") && (e.%Get(key) = value) Return e }
    Quit ""
}

/// The digest of the whole block: what a proposal was built against, so a block changed since then shows.
ClassMethod MappingDigest(block As %DynamicObject) As %String
{
    If '$ISOBJECT(block) Quit ""
    Quit ##class(Shutter.Util.Digest).OfObject(block)
}

}
