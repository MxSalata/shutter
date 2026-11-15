/// The routes of the catalogue and of the site's own entries (CONTRACTS 6.8), called from Shutter.API.Dispatch's map.
/// The actor is always the signed-in user, never a name from the body. Reading needs Shutter_Operate; writing a draft,
/// proving and proposing need Shutter_Configure; approving needs Shutter_Approve (and on a demo instance
/// Shutter_Configure too, since the public demo's roles hold Shutter_Approve and must not activate anything);
/// suspending needs both. Every change carries X-Requested-With.
Class Shutter.API.SiteEntries Extends %RegisteredObject
{

/// GET /catalogue: the shipped entries and the active site entries, with the catalogue's version.
ClassMethod Catalogue() As %Status
{
    If '##class(Shutter.API.Dispatch).Allow() Quit $$$OK
    Set o = {}
    Set o.version = ##class(Shutter.Catalogue.Entry).CatalogueVersion()
    Set o.shippedVersion = ##class(Shutter.Catalogue.Entry).ShippedVersion()
    Do o.%Set("generation", ##class(Shutter.Catalogue.SiteEntry).Generation(), "number")
    Set o.shipped = ##class(Shutter.Catalogue.Entry).All()
    Set site = []
    Set it = ##class(Shutter.Catalogue.SiteEntry).ActiveList(.problem).%GetIterator()
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

/// GET /site-entries: every site entry with its state, and the site's status (the generation, the warnings).
ClassMethod List() As %Status
{
    If '##class(Shutter.API.Dispatch).Allow() Quit $$$OK
    Set o = {}
    Set o.items = ##class(Shutter.Catalogue.SiteEntry).List()
    Set o.status = ##class(Shutter.Catalogue.SiteEntry).Status()
    Set o.catalogueVersion = ##class(Shutter.Catalogue.Entry).CatalogueVersion()
    Quit ##class(Shutter.API.Dispatch).Json(o)
}

/// GET /site-entries/{id}: one entry with its versions, proofs and events.
ClassMethod Get(id As %String) As %Status
{
    If '##class(Shutter.API.Dispatch).Allow() Quit $$$OK
    Set entry = ##class(Shutter.Catalogue.SiteEntry).ById(id)
    If '$ISOBJECT(entry) Quit ##class(Shutter.API.Dispatch).Fail("404 Not Found", "not_found", "No site entry " _ id)
    Quit ##class(Shutter.API.Dispatch).Json(entry.Describe(1))
}

/// POST /site-entries/validate: a body checked against R1 to R5 and R15, with its sentence and the shipped entries its
/// pattern can displace. Stores nothing and reads no case.
ClassMethod Validate() As %Status
{
    If '##class(Shutter.API.Dispatch).Allow("Shutter_Operate", 1) Quit $$$OK
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

/// POST /site-entries: a draft from a body, or from a stored case ({fromCase}). 201 with the entry.
ClassMethod Create() As %Status
{
    If '##class(Shutter.API.Dispatch).Allow("Shutter_Configure", 1) Quit $$$OK
    Set body = ..BodyOr400()
    If '$ISOBJECT(body) Quit $$$OK
    Set code = ##class(Shutter.Catalogue.SiteEntry).Create(body, ##class(Shutter.API.Dispatch).User(), "api", .entry, .problems, .warnings)
    If code '= "" Quit ..Refuse(code, "", problems)
    Set o = entry.Describe(1)
    Set o.warnings = warnings
    Quit ##class(Shutter.API.Dispatch).Json(o, "201 Created")
}

/// PUT /site-entries/{id}: the draft changed, or a draft begun beside the active version. expectedVersion is the
/// entry's revision as the caller read it (409 stale_version).
ClassMethod Change(id As %String) As %Status
{
    If '##class(Shutter.API.Dispatch).Allow("Shutter_Configure", 1) Quit $$$OK
    Set body = ..BodyOr400()
    If '$ISOBJECT(body) Quit $$$OK
    Set expected = ##class(Shutter.Util.Json).Str(body, "expectedVersion")
    If body.%IsDefined("expectedVersion") Do body.%Remove("expectedVersion")
    Set code = ##class(Shutter.Catalogue.SiteEntry).Change(id, body, expected, ##class(Shutter.API.Dispatch).User(), "api", .entry, .problems, .warnings, .detail)
    If code = "stale_version" {
        Set extra = {}
        Do extra.%Set("currentVersion", +detail, "number")
        Quit ##class(Shutter.API.Dispatch).Fail("409 Conflict", "stale_version", "expectedVersion is not the entry's revision", extra)
    }
    If code '= "" Quit ..Refuse(code, detail, problems)
    Set o = ##class(Shutter.Catalogue.SiteEntry).ById(id).Describe(1)
    Set o.warnings = warnings
    Quit ##class(Shutter.API.Dispatch).Json(o)
}

/// POST /site-entries/{id}/proof: {action?} (activate when none). Runs P1, P2 and P4 and keeps the proof.
ClassMethod Proof(id As %String) As %Status
{
    If '##class(Shutter.API.Dispatch).Allow("Shutter_Configure", 1) Quit $$$OK
    Set body = ##class(Shutter.API.Dispatch).Body()
    Set:$ISOBJECT($GET(%response)) %response.Timeout = 120
    Set code = ##class(Shutter.Catalogue.SiteEntry).Prove(id, ##class(Shutter.Util.Json).Str(body, "action"), ##class(Shutter.API.Dispatch).User(), "api", .result, .detail)
    If code '= "" Quit ..Refuse(code, detail)
    Quit ##class(Shutter.API.Dispatch).Json(result)
}

/// POST /site-entries/{id}/propose: {action: activate, retire or resume}. 409 no_proof without a passing, current proof.
ClassMethod Propose(id As %String) As %Status
{
    If '##class(Shutter.API.Dispatch).Allow("Shutter_Configure", 1) Quit $$$OK
    Set body = ##class(Shutter.API.Dispatch).Body()
    Set code = ##class(Shutter.Catalogue.SiteEntry).Propose(id, ##class(Shutter.Util.Json).Str(body, "action"), ##class(Shutter.API.Dispatch).User(), "api", .entry, .detail)
    If code '= "" Quit ..Refuse(code, detail)
    Quit ##class(Shutter.API.Dispatch).Json(entry.Describe(1))
}

/// POST /site-entries/{id}/approvals: {action, version, digest, decision, reason, safetyReference?}.
ClassMethod Approve(id As %String) As %Status
{
    If '##class(Shutter.API.Dispatch).Allow("Shutter_Approve", 1) Quit $$$OK
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
    If '##class(Shutter.API.Dispatch).Allow("Shutter_Approve", 1) Quit $$$OK
    If '##class(Shutter.API.Dispatch).Allow("Shutter_Configure", 1) Quit $$$OK
    Set body = ##class(Shutter.API.Dispatch).Body()
    Set code = ##class(Shutter.Catalogue.SiteEntry).Suspend(id, ##class(Shutter.Util.Json).Str(body, "reason"), ##class(Shutter.API.Dispatch).User(), "api", .entry, .detail)
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
