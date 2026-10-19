/// The site profile: the questionnaire's answers (CONTRACTS 6.4), one current row, with the shipped defaults
/// when no profile has been given. Read by the case workflow (the policy path), the gate and the incident.
Class Shutter.Store.SiteProfile Extends (%Persistent, %JSON.Adaptor)
{

Property Name As %String(%JSONFIELDNAME = "name", MAXLEN = 32) [ InitialExpression = "current", Required ];

Index NameIdx On Name [ Unique ];

Property Version As %Integer(%JSONFIELDNAME = "version") [ InitialExpression = 1 ];

/// The profile as JSON (the shape in CONTRACTS 6.4).
Property Json As %String(%JSONFIELDNAME = "profile", MAXLEN = "");

Property Source As %String(%JSONFIELDNAME = "source", MAXLEN = 500);

Property UpdatedAt As %String(%JSONFIELDNAME = "updatedAt", MAXLEN = 30);

Property UpdatedBy As %String(%JSONFIELDNAME = "updatedBy", MAXLEN = 160);

/// The shipped defaults: one receiver (the downstream system, tier 2), keep what is current, no authoritative source,
/// unconditional resends forbidden, automatic single chains for tiers 1 and 2, approvals elsewhere.
ClassMethod Default() As %DynamicObject
{
    Set p = {}
    Set p.version = 0
    Set p.receivers = [{"name": ($PARAMETER("Shutter.Production", "RECEIVER")), "system": "the demo bed-management system", "tier": 2, "applies": "arrival_order", "resend_timestamp": "original", "cancels": false, "api": {"base": "/downstream/api", "state": "/encounters/{encounter}", "receipt": "/receipts/{key}", "capabilities": "/capabilities", "operations": "/operations"}, "features": {"conditional_writes": true, "receipts": true, "history": true, "dry_run": true}}]
    Set p."history_policy" = "current"
    Set p."authoritative_source" = ""
    Set p."unconditional_resend" = "forbidden"
    Set p.policy = {"1": {"single": "automatic", "ordered": "automatic", "interleaved": "board"}, "2": {"single": "automatic", "ordered": "approval", "interleaved": "board"}, "3": {"single": "approval", "ordered": "per_chain", "interleaved": "board"}}
    Set p.approvers = {"role": "Shutter Approvers", "escalation": "the integration team's on-call"}
    Set p.incident = {"threshold": 5, "window_minutes": 10, "quiet_seconds": 60}
    Set p."model_content" = {"free_text": false}
    Set p.feed = {"time_zone": "Europe/London"}
    Quit p
}

/// The current profile as a dynamic object (the stored one, else the defaults), with "version" set.
ClassMethod Current() As %DynamicObject
{
    Set row = ..Row()
    If $ISOBJECT(row) && (row.Json '= "") {
        Set p = ##class(Shutter.Util.Json).Parse(row.Json, .sc)
        If $ISOBJECT(p) Set p.version = row.Version Quit p
    }
    Quit ..Default()
}

ClassMethod Row() As Shutter.Store.SiteProfile
{
    Set id = ""
    &sql(SELECT ID INTO :id FROM Shutter_Store.SiteProfile WHERE Name = 'current')
    If (SQLCODE '= 0) || (id = "") Quit ""
    Quit ..%OpenId(id)
}

/// Store a profile (JSON text) as the current one, with the next version.
ClassMethod Store(json As %String, source As %String = "", user As %String = "", expectedVersion As %String = "", Output currentVersion As %Integer) As %Status
{
    Set currentVersion = 0
    Set p = ##class(Shutter.Util.Json).Parse(json, .sc)
    If '$ISOBJECT(p) || $$$ISERR(sc) Quit $$$ERROR($$$GeneralError, "The profile is not a JSON object")
    Set problem = ..Validate(p)
    If problem '= "" Quit $$$ERROR($$$GeneralError, "The profile is not valid: " _ problem)
    // One writer at a time: the version check (expectedVersion, when given), the increment and the two saves happen
    // under the lock, so two concurrent PUTs cannot both pass the check and both write.
    LOCK +^Shutter.SiteProfile:5
    If '$TEST Quit $$$ERROR($$$GeneralError, "The site profile is being written by someone else; try again")
    Try {
        Set row = ..Row()
        If '$ISOBJECT(row) Set row = ..%New(), row.Version = 0
        If (expectedVersion '= "") && (+expectedVersion '= +row.Version) {
            Set currentVersion = +row.Version
            Set sc = $$$ERROR($$$GeneralError, "stale_version")
            Quit
        }
        TSTART
        Set row.Version = row.Version + 1
        Set row.Json = p.%ToJSON(), row.Source = source, row.UpdatedBy = $EXTRACT(user, 1, 160)
        Set row.UpdatedAt = ##class(Shutter.Util.Time).NowUTC()
        Set sc = row.%Save()
        If $$$ISOK(sc) {
            // Every change is kept, with who made it and from where (CONTRACTS 6.4).
            Set v = ##class(Shutter.Store.SiteProfileVersion).%New()
            Set v.Version = row.Version, v.Json = row.Json, v.Source = source, v.UpdatedAt = row.UpdatedAt, v.UpdatedBy = row.UpdatedBy
            Set sc = v.%Save()
        }
        If $$$ISOK(sc) { TCOMMIT  Kill ^Shutter.Config("feedZone") } Else { TROLLBACK }
        Set currentVersion = +row.Version
    } Catch ex {
        Set sc = ex.AsStatus()
        If $TLEVEL > 0 TROLLBACK
    }
    LOCK -^Shutter.SiteProfile
    Quit sc
}

/// The validator for SQL and tests: "ok", or the problem.
ClassMethod ValidateJSON(json As %String) As %String [ SqlProc ]
{
    Set p = ##class(Shutter.Util.Json).Parse(json, .sc)
    If '$ISOBJECT(p) || $$$ISERR(sc) Quit "the profile is not a JSON object"
    Set problem = ..Validate(p)
    Quit $SELECT(problem = "": "ok", 1: problem)
}

/// What is wrong with a profile, with the field named, or "" when it has the shape of CONTRACTS 6.4.
ClassMethod Validate(p As %DynamicObject) As %String
{
    Set json = "Shutter.Util.Json"
    If '$ISOBJECT(p) Quit "the profile must be a JSON object"
    Set it = p.%GetIterator()
    While it.%GetNext(.key, .v) {
        If '$LISTFIND($LISTBUILD("version", "receivers", "history_policy", "authoritative_source", "unconditional_resend", "policy", "approvers", "incident", "model_content", "teams", "mail", "feed"), key) Return key _ ": unknown field"
    }
    If p.%IsDefined("version") && ((p.%Get("version") '= +p.%Get("version")) || (p.%Get("version") < 0)) Quit "version: must be a whole number"
    Set rcv = p.%Get("receivers")
    If '$ISOBJECT(rcv) || (rcv.%Size() = 0) Quit "receivers: must be a non-empty array"
    Set it = rcv.%GetIterator()
    While it.%GetNext(.i, .r) {
        Set at = "receivers[" _ i _ "]"
        If '$ISOBJECT(r) Return at _ ": must be an object"
        If $CLASSMETHOD(json, "Str", r, "name") = "" Return at _ ".name: required"
        Set tier = r.%Get("tier")
        If (tier '= +tier) || (tier < 1) || (tier > 3) Return at _ ".tier: must be 1, 2 or 3"
        If r.%IsDefined("cancels") && (r.%GetTypeOf("cancels") '= "boolean") Return at _ ".cancels: must be true or false"
        If r.%IsDefined("api") {
            Set api = r.%Get("api")
            If '$ISOBJECT(api) Return at _ ".api: must be an object"
            Set ai = api.%GetIterator()
            While ai.%GetNext(.k, .path) {
                If '$LISTFIND($LISTBUILD("base", "state", "receipt", "capabilities", "operations"), k) Return at _ ".api." _ k _ ": unknown path"
                If api.%GetTypeOf(k) '= "string" Return at _ ".api." _ k _ ": must be a string"
            }
            // Without a state path nothing can be read, and without an operations path nothing can be sent.
            If $CLASSMETHOD(json, "Str", api, "state") = "" Return at _ ".api.state: required when api is given"
            If $CLASSMETHOD(json, "Str", api, "operations") = "" Return at _ ".api.operations: required when api is given"
        }
        If r.%IsDefined("features") {
            Set f = r.%Get("features")
            If '$ISOBJECT(f) Return at _ ".features: must be an object"
            Set fi = f.%GetIterator()
            While fi.%GetNext(.k, .flag) {
                If '$LISTFIND($LISTBUILD("conditional_writes", "receipts", "history", "dry_run"), k) Return at _ ".features." _ k _ ": unknown feature"
                If f.%GetTypeOf(k) '= "boolean" Return at _ ".features." _ k _ ": must be true or false"
            }
        }
    }
    If p.%IsDefined("unconditional_resend") && '$LISTFIND($LISTBUILD("forbidden", "allowed"), p.%Get("unconditional_resend")) Quit "unconditional_resend: must be forbidden or allowed"
    If p.%IsDefined("history_policy") && (p.%GetTypeOf("history_policy") '= "string") Quit "history_policy: must be a string"
    Set pol = p.%Get("policy")
    If '$ISOBJECT(pol) Quit "policy: must be an object with the tiers 1, 2 and 3"
    Set pi = pol.%GetIterator()
    While pi.%GetNext(.tier, .row) {
        If '$LISTFIND($LISTBUILD("1", "2", "3"), tier) Return "policy." _ tier _ ": the tiers are 1, 2 and 3"
        If '$ISOBJECT(row) Return "policy." _ tier _ ": must be an object with single, ordered and interleaved"
        Set ri = row.%GetIterator()
        While ri.%GetNext(.kind, .value) {
            If '$LISTFIND($LISTBUILD("single", "ordered", "interleaved"), kind) Return "policy." _ tier _ "." _ kind _ ": the chain kinds are single, ordered and interleaved"
            If '$LISTFIND($LISTBUILD("automatic", "approval", "per_chain", "board"), value) Return "policy." _ tier _ "." _ kind _ ": must be automatic, approval, per_chain or board"
        }
    }
    If p.%IsDefined("approvers") && '$ISOBJECT(p.%Get("approvers")) Quit "approvers: must be an object"
    // The feed: the time zone of timestamps that carry no offset (T28).
    If p.%IsDefined("feed") {
        Set feed = p.%Get("feed")
        If '$ISOBJECT(feed) Quit "feed: must be an object"
        Set fi = feed.%GetIterator()
        While fi.%GetNext(.k, .v) {
            If '$LISTFIND($LISTBUILD("time_zone"), k) Return "feed." _ k _ ": unknown setting"
            If (feed.%GetTypeOf(k) '= "string") || '$LISTFIND($LISTBUILD("UTC", "Europe/London"), v) && '$MATCH(v, "^[+-](0[0-9]|1[0-4]):[0-5][0-9]$") Return "feed.time_zone: must be UTC, Europe/London or a fixed offset such as +01:00 (up to 14:00)"
        }
    }
    // What may leave IRIS for a model (T27): free text off unless the site says so.
    If p.%IsDefined("model_content") {
        Set mc = p.%Get("model_content")
        If '$ISOBJECT(mc) Quit "model_content: must be an object"
        Set mi = mc.%GetIterator()
        While mi.%GetNext(.k, .flag) {
            If '$LISTFIND($LISTBUILD("free_text"), k) Return "model_content." _ k _ ": unknown setting"
            If mc.%GetTypeOf(k) '= "boolean" Return "model_content." _ k _ ": must be true or false"
        }
    }
    // The teams an escalation can go to, and the mail rules (T29).
    Set domains = ""
    If p.%IsDefined("mail") {
        Set mail = p.%Get("mail")
        If '$ISOBJECT(mail) Quit "mail: must be an object"
        Set mi = mail.%GetIterator()
        While mi.%GetNext(.k, .v) {
            If '$LISTFIND($LISTBUILD("from", "allowed_domains"), k) Return "mail." _ k _ ": unknown setting"
            If (k = "from") && (mail.%GetTypeOf(k) '= "string") Return "mail.from: must be a string"
            If (k = "allowed_domains") {
                If '$ISOBJECT(v) || v.%IsA("%DynamicObject") Return "mail.allowed_domains: must be an array of domains"
                Set di = v.%GetIterator()
                While di.%GetNext(.j, .d) {
                    If (v.%GetTypeOf(j) '= "string") || (d = "") Return "mail.allowed_domains[" _ j _ "]: must be a domain"
                    Set domains = domains _ $LISTBUILD($ZCONVERT(d, "L"))
                }
            }
        }
    }
    If p.%IsDefined("teams") {
        Set teams = p.%Get("teams")
        If '$ISOBJECT(teams) || teams.%IsA("%DynamicObject") Quit "teams: must be an array"
        Set ti = teams.%GetIterator(), ids = ""
        While ti.%GetNext(.i, .t) {
            Set at = "teams[" _ i _ "]"
            If '$ISOBJECT(t) Return at _ ": must be an object"
            Set ki = t.%GetIterator()
            While ki.%GetNext(.k, .v) {
                If '$LISTFIND($LISTBUILD("id", "name", "mailbox", "cc", "receivers"), k) Return at _ "." _ k _ ": unknown field"
            }
            For f = "id", "name", "mailbox" { If ($CLASSMETHOD(json, "Str", t, f) = "") || (t.%GetTypeOf(f) '= "string") Return at _ "." _ f _ ": required" }
            If $LISTFIND(ids, t.%Get("id")) Return at _ ".id: must be unique"
            Set ids = ids _ $LISTBUILD(t.%Get("id"))
            Set problem = ..MailboxProblem(t.%Get("mailbox"), domains)
            If problem '= "" Return at _ ".mailbox: " _ problem
            If t.%IsDefined("cc") {
                Set cc = t.%Get("cc")
                If '$ISOBJECT(cc) || cc.%IsA("%DynamicObject") Return at _ ".cc: must be an array of mailboxes"
                Set ci = cc.%GetIterator()
                While ci.%GetNext(.j, .m) {
                    If cc.%GetTypeOf(j) '= "string" Return at _ ".cc[" _ j _ "]: must be a mailbox"
                    Set problem = ..MailboxProblem(m, domains)
                    If problem '= "" Return at _ ".cc[" _ j _ "]: " _ problem
                }
            }
            If t.%IsDefined("receivers") {
                Set rl = t.%Get("receivers")
                If '$ISOBJECT(rl) || rl.%IsA("%DynamicObject") Return at _ ".receivers: must be an array of receiver names"
                Set ri = rl.%GetIterator()
                While ri.%GetNext(.j, .m) { If (rl.%GetTypeOf(j) '= "string") || (m = "") Return at _ ".receivers[" _ j _ "]: must be a receiver name" }
            }
        }
    }
    If p.%IsDefined("incident") {
        Set inc = p.%Get("incident")
        If '$ISOBJECT(inc) Quit "incident: must be an object"
        Set ii = inc.%GetIterator()
        While ii.%GetNext(.k, .n) {
            If '$LISTFIND($LISTBUILD("threshold", "window_minutes", "quiet_seconds"), k) Return "incident." _ k _ ": unknown setting"
            If (n '= +n) || (n < 0) || ((k '= "quiet_seconds") && (n < 1)) Return "incident." _ k _ ": must be a whole number" _ $SELECT(k = "quiet_seconds": "", 1: " of 1 or more")
        }
    }
    Quit ""
}

/// Seed from knowledge/site/profile.json when the file exists and differs from what is stored.
ClassMethod SeedFromFile(path As %String) As %Status
{
    If '##class(%File).Exists(path) Quit $$$OK
    Set text = ##class(Shutter.Knowledge.Text).ReadFile(path)
    If text = "" Quit $$$OK
    Set p = ##class(Shutter.Util.Json).Parse(text, .sc)
    If '$ISOBJECT(p) || $$$ISERR(sc) Quit $$$ERROR($$$GeneralError, "The seed profile " _ path _ " is not a JSON object")
    Set row = ..Row()
    // The seed fills an empty store and follows its own file; a profile a person saved (another source) is theirs and
    // is never overwritten by a reinstall or a restart.
    If $ISOBJECT(row) && (row.Source '= path) Quit $$$OK
    If $ISOBJECT(row) && (row.Json = p.%ToJSON()) Quit $$$OK
    Quit ..Store(p.%ToJSON(), path)
}

/// The receiver's tier (the production item's name), default 2.
/// A mailbox's problem: not an address, or outside the allowed domains when the profile names them. "" when fine.
/// The problem with a list of addresses a person typed (comma separated) against the profile's mail.allowed_domains:
/// "" when every address is an address inside the allowed domains (or no domains are set), else the first offending
/// address and why.
ClassMethod AddressesProblem(list As %String) As %String
{
    Set domains = "", allowed = ..Mail().%Get("allowed_domains")
    If $ISOBJECT(allowed) {
        Set di = allowed.%GetIterator()
        While di.%GetNext(.j, .d) { If d '= "" Set domains = domains _ $LISTBUILD($ZCONVERT(d, "L")) }
    }
    For i = 1:1:$LENGTH(list, ",") {
        Set a = $ZSTRIP($PIECE(list, ",", i), "<>W")
        Continue:a=""
        Set problem = ..MailboxProblem(a, domains)
        If problem '= "" Quit
    }
    Quit $SELECT($GET(problem) = "": "", 1: a _ ": " _ problem)
}

ClassMethod MailboxProblem(mailbox As %String, domains As %List) As %String [ Private ]
{
    If (mailbox '[ "@") || ($PIECE(mailbox, "@", 2) = "") || ($PIECE(mailbox, "@", 1) = "") Quit "must be an address"
    If $LISTLENGTH(domains) = 0 Quit ""
    Set domain = $ZCONVERT($PIECE(mailbox, "@", 2), "L")
    For i = 1:1:$LISTLENGTH(domains) {
        Set d = $LIST(domains, i)
        If (domain = d) || ($EXTRACT(domain, * - $LENGTH(d), *) = ("." _ d)) Quit
    }
    If (domain = d) || ($EXTRACT(domain, * - $LENGTH(d), *) = ("." _ d)) Quit ""
    Quit "not in the allowed domains"
}

/// The time zone of the feed's timestamps that carry no offset (T28): UTC, Europe/London or a fixed offset. A
/// profile that does not answer the question (one saved before it existed) keeps the old reading, UTC, so nothing
/// moves under an installed site until it answers; the questionnaire's default answer is Europe/London (Default()).
ClassMethod FeedTimeZone() As %String
{
    // Read on the feed's hot path for every timestamp: cached in a global that every store of the profile clears.
    Set cached = $GET(^Shutter.Config("feedZone"))
    If cached '= "" Quit cached
    Set feed = ..Current().%Get("feed")
    Set zone = $SELECT($ISOBJECT(feed): ##class(Shutter.Util.Json).Str(feed, "time_zone"), 1: "")
    If zone = "" Set zone = "UTC"
    Set ^Shutter.Config("feedZone") = zone
    Quit zone
}

/// Whether the site allows OBX and NTE free text to go to a model (T27): off unless the profile says so.
ClassMethod ModelFreeText() As %Boolean
{
    Set mc = ..Current().%Get("model_content")
    Quit $ISOBJECT(mc) && ##class(Shutter.Util.Json).Bool(mc, "free_text", 0)
}

/// The teams an escalation can go to (T29), as stored; an empty array when the profile names none.
ClassMethod Teams() As %DynamicArray
{
    Set teams = ..Current().%Get("teams")
    Quit $SELECT($ISOBJECT(teams) && teams.%IsA("%DynamicArray"): teams, 1: [])
}

/// The mail settings (T29): from and allowed_domains, or an empty object.
ClassMethod Mail() As %DynamicObject
{
    Set mail = ..Current().%Get("mail")
    Quit $SELECT($ISOBJECT(mail) && mail.%IsA("%DynamicObject"): mail, 1: {})
}

ClassMethod TierOf(receiver As %String) As %Integer
{
    Set p = ..Current()
    Set list = p.%Get("receivers")
    If $ISOBJECT(list) {
        Set iter = list.%GetIterator()
        While iter.%GetNext(.i, .r) { If ##class(Shutter.Util.Json).Str(r, "name") = receiver Quit }
        If $ISOBJECT($GET(r)) && (##class(Shutter.Util.Json).Str(r, "name") = receiver) Quit +##class(Shutter.Util.Json).Str(r, "tier", 2)
    }
    Quit 2
}

/// The receiver's entry in the profile (CONTRACTS 6.4), or "" when the profile does not name it.
ClassMethod Receiver(name As %String) As %DynamicObject
{
    Set p = ..Current()
    Set list = p.%Get("receivers")
    If '$ISOBJECT(list) Quit ""
    Set iter = list.%GetIterator()
    While iter.%GetNext(.i, .r) { If $ISOBJECT(r) && (##class(Shutter.Util.Json).Str(r, "name") = name) Return r }
    Quit ""
}

/// The downstream system's paths, used when a receiver's entry gives none: the shape the demo's receiver speaks.
ClassMethod DefaultApi() As %DynamicObject
{
    Quit {"base": "/downstream/api", "state": "/encounters/{encounter}", "receipt": "/receipts/{key}", "capabilities": "/capabilities", "operations": "/operations"}
}

/// One of a receiver's paths (state, receipt, capabilities, operations), with the receiver's base in front and the
/// placeholders {encounter} and {key} filled in, URL-encoded. An empty path (the receiver has no such endpoint)
/// stays empty: the caller then uses what the profile declares instead.
ClassMethod ReceiverPath(name As %String, kind As %String, encounter As %String = "", key As %String = "") As %String
{
    Set r = ..Receiver(name), defaults = ..DefaultApi()
    Set api = $SELECT($ISOBJECT(r) && $ISOBJECT(r.%Get("api")): r.%Get("api"), 1: defaults)
    Set base = $SELECT(api.%IsDefined("base"): ##class(Shutter.Util.Json).Str(api, "base"), 1: ##class(Shutter.Util.Json).Str(defaults, "base"))
    Set path = $SELECT(api.%IsDefined(kind): ##class(Shutter.Util.Json).Str(api, kind), 1: ##class(Shutter.Util.Json).Str(defaults, kind))
    If path = "" Quit ""
    Set path = $REPLACE(path, "{encounter}", $ZCONVERT(encounter, "O", "URL"))
    Set path = $REPLACE(path, "{key}", $ZCONVERT(key, "O", "URL"))
    If $EXTRACT(path, 1) '= "/" Set path = "/" _ path
    Quit base _ path
}

/// What the profile declares the receiver can do (conditional_writes, receipts, history, dry_run), for a receiver
/// with no capabilities endpoint and as the record of what the site believes; every flag true by default.
ClassMethod ReceiverFeatures(name As %String) As %DynamicObject
{
    Set r = ..Receiver(name)
    If $ISOBJECT(r) && $ISOBJECT(r.%Get("features")) Quit r.%Get("features")
    Quit {"conditional_writes": true, "receipts": true, "history": true, "dry_run": true}
}

/// The receiver's description for a person: its system text and base path.
ClassMethod ReceiverLabel(name As %String) As %String
{
    Set r = ..Receiver(name)
    Set system = $SELECT($ISOBJECT(r): ##class(Shutter.Util.Json).Str(r, "system"), 1: "")
    Set base = ##class(Shutter.Util.Json).Str($SELECT($ISOBJECT(r) && $ISOBJECT(r.%Get("api")): r.%Get("api"), 1: ..DefaultApi()), "base", "/downstream/api")
    Quit $SELECT(system = "": name, 1: system) _ " (" _ base _ ")"
}

/// The policy for a tier and a chain kind: automatic, approval, per_chain or board. Tier 3 never
/// answers automatic unless the profile says so explicitly; an unknown pair answers approval.
ClassMethod Policy(tier As %Integer, chainKind As %String = "single") As %String
{
    Set p = ..Current()
    Set table = p.%Get("policy")
    Set row = $SELECT($ISOBJECT(table): table.%Get("" _ tier), 1: "")
    Set value = $SELECT($ISOBJECT(row): ##class(Shutter.Util.Json).Str(row, chainKind), 1: "")
    If '$LISTFIND($LISTBUILD("automatic", "approval", "per_chain", "board"), value) Quit "approval"
    Quit value
}

/// A top-level flag of the profile as a string (history_policy, authoritative_source, unconditional_resend).
ClassMethod Flag(name As %String, default As %String = "") As %String
{
    Quit ##class(Shutter.Util.Json).Str(..Current(), name, default)
}

/// An incident setting: threshold, window_minutes, quiet_seconds.
ClassMethod IncidentSetting(name As %String, default As %Integer) As %Integer
{
    Set inc = ..Current().%Get("incident")
    If '$ISOBJECT(inc) Quit default
    Set v = ##class(Shutter.Util.Json).Str(inc, name)
    Quit $SELECT(v = "": default, 1: +v)
}

Storage Default
{
<Data name="SiteProfileDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Name</Value>
</Value>
<Value name="3">
<Value>Version</Value>
</Value>
<Value name="4">
<Value>Json</Value>
</Value>
<Value name="5">
<Value>Source</Value>
</Value>
<Value name="6">
<Value>UpdatedAt</Value>
</Value>
<Value name="7">
<Value>UpdatedBy</Value>
</Value>
</Data>
<DataLocation>^Shutter.Store.SiteProfileD</DataLocation>
<DefaultData>SiteProfileDefaultData</DefaultData>
<IdLocation>^Shutter.Store.SiteProfileD</IdLocation>
<IndexLocation>^Shutter.Store.SiteProfileI</IndexLocation>
<StreamLocation>^Shutter.Store.SiteProfileS</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
