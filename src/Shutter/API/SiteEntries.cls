/// The work of the catalogue's and the site's own entries' routes (CONTRACTS 6.8). Shutter.API.Dispatch's route methods
/// check the caller first (its Allow: the resource and, for a change, X-Requested-With) and then call these; the second
/// resource an approval needs on a demo, and a suspension always, is asked here. The actor is always the signed-in user,
/// never a name from the body.
Class Shutter.API.SiteEntries Extends %RegisteredObject
{

/// GET /catalogue: the shipped entries and the active site entries, with the catalogue's version.
ClassMethod Catalogue() As %Status
{
    Set o = {}
    // The version, the generation and the entries read as one: read again while a change landed between them, so the
    // answer never pairs a version with entries of another generation.
    For try = 1:1:3 {
        Set version = ##class(Shutter.Catalogue.Entry).CatalogueVersion(), generation = ##class(Shutter.Catalogue.SiteEntry).Generation()
        Set list = ##class(Shutter.Catalogue.SiteEntry).ActiveList(.problem)
        Quit:((##class(Shutter.Catalogue.Entry).CatalogueVersion() = version) && (##class(Shutter.Catalogue.SiteEntry).Generation() = generation))
        If try = 3 Set problem = $SELECT($GET(problem) '= "": problem, 1: "the site's entries changed while they were read: read them again")
    }
    Set o.version = version
    Set o.shippedVersion = ##class(Shutter.Catalogue.Entry).ShippedVersion()
    Do o.%Set("generation", generation, "number")
    Set o.shipped = ..Shipped()
    Set site = []
    Set it = list.%GetIterator()
    While it.%GetNext(, .m) {
        // As the matcher reads them: the three fields that decide are its own words, never a stored row's.
        Set e = {}
        Set e.id = m.id, e.version = m.version, e.title = m.title, e.origin = "site", e.kind = "stop", e.priority = m.priority
        Set e.scope = m.scope, e.pattern = m.pattern, e.decides = "person"
        Set e.preferred = {"outcome": "escalate", "why": (m.why)}, e.alternatives = []
        Set e.instructions = m.instructions, e.team = m.team, e.prose = m.prose
        Set e.sentence = ##class(Shutter.Catalogue.SiteEntryVersion).Sentence(m)
        Do site.%Push(e)
    }
    Set o.site = site
    If $GET(problem) '= "" Set o.siteError = problem
    Set vocabulary = ##class(Shutter.Catalogue.Vocabulary).Current()
    If $ISOBJECT(vocabulary) Set o.vocabulary = vocabulary
    Quit ##class(Shutter.API.Dispatch).Json(o)
}

/// The shipped entries for GET /catalogue, each with atReceivers: what a match of the entry alone settles on at each
/// receiver of the profile in force, by the matcher's own Settle on that receiver's facts (Matcher.AtReceiver), for this
/// site's guide.
ClassMethod Shipped() As %DynamicArray
{
    Set shipped = ##class(Shutter.Catalogue.Entry).All()
    Set receivers = ##class(Shutter.Store.SiteProfile).ReceiverNames()
    Set it = shipped.%GetIterator()
    While it.%GetNext(, .entry) {
        Set at = [], ri = receivers.%GetIterator()
        While ri.%GetNext(, .name) { Do at.%Push(##class(Shutter.Catalogue.Matcher).AtReceiver(entry, name)) }
        Set entry.atReceivers = at
    }
    Quit shipped
}

/// GET /site-entries: every site entry with its state, and the site's status (the generation, the warnings).
ClassMethod List() As %Status
{
    Set o = {}
    Set o.items = ##class(Shutter.Catalogue.SiteEntry).List()
    Set o.status = ##class(Shutter.Catalogue.SiteEntry).Status()
    Set o.catalogueVersion = ##class(Shutter.Catalogue.Entry).CatalogueVersion()
    // The open cases whose plan was made under the version in force: an approval's dialog says how many will not
    // complete under it (R17) before anyone approves.
    Do o.%Set("waitingPlans", ##class(Shutter.Catalogue.SiteEntry).WaitingPlans(o.catalogueVersion), "number")
    Quit ##class(Shutter.API.Dispatch).Json(o)
}

/// GET /site-entries/{id}: one entry with its versions, proofs and events.
ClassMethod Get(id As %String) As %Status
{
    Set entry = ##class(Shutter.Catalogue.SiteEntry).ById(id)
    If '$ISOBJECT(entry) Quit ##class(Shutter.API.Dispatch).Fail("404 Not Found", "not_found", "No site entry " _ id)
    Quit ##class(Shutter.API.Dispatch).Json(entry.Describe(1))
}

/// POST /site-entries/validate: a body checked against R1 to R5 and R15, with its sentence and the shipped entries its
/// pattern can displace. Stores nothing and reads no case.
ClassMethod Validate() As %Status
{
    Set body = ..BodyOr400()
    If '$ISOBJECT(body) Quit $$$OK
    Do ##class(Shutter.Catalogue.SiteEntryVersion).Normalise(body, ##class(Shutter.Util.Json).Str(body, "id"), .content, .problems, .warnings, 0)
    Set o = {}
    Do o.%Set("valid", problems.%Size() = 0, "boolean")
    Set o.problems = problems, o.warnings = warnings
    Set o.sentence = ##class(Shutter.Catalogue.SiteEntryVersion).Sentence(content)
    Set o.overlap = ##class(Shutter.Catalogue.SiteEntryVersion).Overlap(content.%Get("pattern"))
    Quit ##class(Shutter.API.Dispatch).Json(o)
}

/// POST /site-entries/preview: the body checked as a draft's is, and P1, P2 and P4 run on the stored cases it names, with
/// nothing stored (Shutter.Catalogue.SiteEntryProof.Preview). The public demo's roles may run it (R16).
ClassMethod Preview() As %Status
{
    Set body = ..BodyOr400()
    If '$ISOBJECT(body) Quit $$$OK
    Set:$ISOBJECT($GET(%response)) %response.Timeout = 120
    Set code = ##class(Shutter.Catalogue.SiteEntryProof).Preview(body, .result)
    If code = "not_found" Quit ..Refuse(code, "No site entry " _ ##class(Shutter.Util.Json).Str(body, "id"))
    If code '= "" Quit ..Refuse(code, "The action is activate, retire or resume")
    Quit ##class(Shutter.API.Dispatch).Json(result)
}

/// POST /site-entries: a draft from a body, or from a stored case ({fromCase}). 201 with the entry.
ClassMethod Create() As %Status
{
    Set body = ..BodyOr400()
    If '$ISOBJECT(body) Quit $$$OK
    Set code = ##class(Shutter.Catalogue.SiteEntry).Create(body, ##class(Shutter.API.Dispatch).User(), "api", .entry, .problems, .warnings)
    If code '= "" Quit ..Refuse(code, "", problems)
    Set o = entry.Describe(1)
    Set o.warnings = warnings
    Quit ##class(Shutter.API.Dispatch).Json(o, "201 Created")
}

/// PUT /site-entries/{id}: the draft changed, or a draft begun beside the active version. expectedVersion is the
/// entry's revision as the caller read it, and is required (409 stale_version when it is missing or another).
ClassMethod Change(id As %String) As %Status
{
    Set body = ..BodyOr400()
    If '$ISOBJECT(body) Quit $$$OK
    Set expected = ##class(Shutter.Util.Json).Str(body, "expectedVersion")
    If body.%IsDefined("expectedVersion") Do body.%Remove("expectedVersion")
    Set code = ##class(Shutter.Catalogue.SiteEntry).Change(id, body, expected, ##class(Shutter.API.Dispatch).User(), "api", .entry, .problems, .warnings, .detail)
    If code = "stale_version" {
        Set extra = {}
        Do extra.%Set("currentVersion", +detail, "number")
        Quit ##class(Shutter.API.Dispatch).Fail("409 Conflict", "stale_version", "expectedVersion is missing or not the entry's revision", extra)
    }
    If code '= "" Quit ..Refuse(code, detail, problems)
    Set o = ##class(Shutter.Catalogue.SiteEntry).ById(id).Describe(1)
    Set o.warnings = warnings
    Quit ##class(Shutter.API.Dispatch).Json(o)
}

/// POST /site-entries/{id}/proof: {action?} (activate when none). Runs P1, P2 and P4 and keeps the proof.
ClassMethod Proof(id As %String) As %Status
{
    Set body = ##class(Shutter.API.Dispatch).Body()
    Set:$ISOBJECT($GET(%response)) %response.Timeout = 120
    Set code = ##class(Shutter.Catalogue.SiteEntry).Prove(id, ##class(Shutter.Util.Json).Str(body, "action"), ##class(Shutter.API.Dispatch).User(), "api", .result, .detail)
    If code '= "" Quit ..Refuse(code, detail)
    Quit ##class(Shutter.API.Dispatch).Json(result)
}

/// POST /site-entries/{id}/propose: {action: activate, retire or resume}. 409 no_proof without a passing, current proof.
ClassMethod Propose(id As %String) As %Status
{
    Set body = ##class(Shutter.API.Dispatch).Body()
    // The version and digest the proposer read, always passed: missing or another is digest_mismatch.
    Set code = ##class(Shutter.Catalogue.SiteEntry).Propose(id, ##class(Shutter.Util.Json).Str(body, "action"), ##class(Shutter.API.Dispatch).User(), "api", .entry, .detail, ##class(Shutter.Util.Json).Str(body, "version"), ##class(Shutter.Util.Json).Str(body, "digest"))
    If code '= "" Quit ..Refuse(code, detail)
    Quit ##class(Shutter.API.Dispatch).Json(entry.Describe(1))
}

/// POST /site-entries/{id}/approvals: {action, version, digest, decision, reason, safetyReference?}.
ClassMethod Approve(id As %String) As %Status
{
    // The public demo's roles approve plans, so they hold Shutter_Approve; they change nothing of the site (R16).
    If $GET(^Shutter.Config("demo")) && '##class(Shutter.API.Dispatch).Allow("Shutter_Configure", 1) Quit $$$OK
    Set body = ##class(Shutter.API.Dispatch).Body()
    Set:$ISOBJECT($GET(%response)) %response.Timeout = 120
    Set code = ##class(Shutter.Catalogue.SiteEntry).Decide(id, body, ##class(Shutter.API.Dispatch).User(), "api", .entry, .detail, .extra)
    If code '= "" Quit ..Refuse(code, detail, , extra)
    Set o = ##class(Shutter.Catalogue.SiteEntry).ById(id).Describe(1)
    Set it = extra.%GetIterator()
    While it.%GetNext(.key, .value) { Do o.%Set(key, value) }
    Set o.approver = ##class(Shutter.API.Dispatch).User()
    Quit ##class(Shutter.API.Dispatch).Json(o)
}

/// POST /site-entries/{id}/suspend: {reason}. One person holding both rights switches one entry off at once (R12).
ClassMethod Suspend(id As %String) As %Status
{
    If '##class(Shutter.API.Dispatch).Allow("Shutter_Configure", 1) Quit $$$OK
    Set body = ##class(Shutter.API.Dispatch).Body()
    // The revision the person read, always passed: missing or another is stale_version, as for a PUT.
    Set code = ##class(Shutter.Catalogue.SiteEntry).Suspend(id, ##class(Shutter.Util.Json).Str(body, "reason"), ##class(Shutter.API.Dispatch).User(), "api", .entry, .detail, ##class(Shutter.Util.Json).Str(body, "expectedVersion"))
    If code = "stale_version" {
        Set extra = {}
        Do extra.%Set("currentVersion", +detail, "number")
        Quit ##class(Shutter.API.Dispatch).Fail("409 Conflict", "stale_version", "expectedVersion is missing or not the entry's revision", extra)
    }
    If code '= "" Quit ..Refuse(code, detail)
    Quit ##class(Shutter.API.Dispatch).Json(##class(Shutter.Catalogue.SiteEntry).ById(id).Describe(1))
}

/// The body as an object, or "" after a 400.
ClassMethod BodyOr400() As %DynamicObject [ Private ]
{
    Set text = $SELECT($ISOBJECT(%request.Content): %request.Content.Read($$$MaxStringLength), 1: $GET(%request.Content))
    Set body = ##class(Shutter.Util.Json).Parse(text, .sc)
    If '$ISOBJECT(body) || $$$ISERR(sc) || 'body.%IsA("%Library.DynamicObject") {
        Do ##class(Shutter.API.Dispatch).Fail("400 Bad Request", "bad_request", "The body must be a JSON object")
        Quit ""
    }
    Quit body
}

/// A refusal's reply, by its code.
ClassMethod Refuse(code As %String, detail As %String = "", problems As %DynamicArray = "", extra As %DynamicObject = "") As %Status [ Private ]
{
    Set o = $SELECT($ISOBJECT(extra): extra, 1: {})
    If $ISOBJECT(problems) && (problems.%Size() > 0) {
        Set o.problems = problems
        If detail = "" Set detail = "The entry is not valid (CONTRACTS 6.8): " _ problems.%Get(0).text
    }
    Set status = $CASE(code, "not_found": "404 Not Found", "bad_request": "400 Bad Request", "busy": "503 Service Unavailable", "failed": "500 Internal Server Error", : "409 Conflict")
    If (code = "not_found") && (detail = "") Set detail = "No such site entry"
    If (code = "busy") && (detail = "") Set detail = "The site's entries are being changed by someone else; try again"
    Quit ##class(Shutter.API.Dispatch).Fail(status, $SELECT(code = "failed": "store_failed", 1: code), detail, o)
}

}
