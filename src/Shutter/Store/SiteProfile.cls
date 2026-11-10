/// The site profile: the questionnaire's answers (CONTRACTS 6.4), one current row, with the shipped defaults
/// when no profile has been given. Read by the case workflow (the policy path), the gate and the incident.
Class Shutter.Store.SiteProfile Extends (%Persistent, %JSON.Adaptor)
{

/// How long a read of a namespace's messages takes at most at a write, when the profile doesn't say (further_messages.scan_seconds).
Parameter SCANSECONDS = 30;

Property Name As %String(%JSONFIELDNAME = "name", MAXLEN = 32) [ InitialExpression = "current", Required ];

Index NameIdx On Name [ Unique ];

Property Version As %Integer(%JSONFIELDNAME = "version") [ InitialExpression = 1 ];

/// The profile as JSON (the shape in CONTRACTS 6.4).
Property Json As %String(%JSONFIELDNAME = "profile", MAXLEN = "");

Property Source As %String(%JSONFIELDNAME = "source", MAXLEN = 500);

Property UpdatedAt As %String(%JSONFIELDNAME = "updatedAt", MAXLEN = 30);

Property UpdatedBy As %String(%JSONFIELDNAME = "updatedBy", MAXLEN = 160);

/// The shipped defaults: one receiver (the downstream system, tier 2, taking neither cancels nor merges), keep what is
/// current, no authoritative source, unconditional resends forbidden, merges forbidden (they go to the PAS team, T31),
/// a person's approval for every single and ordered chain at every tier (v1.1.0, 8 Nov 2026: "approval on every tier by
/// default"; the board for interleaved chains, whose plan a person then approves), and an operator may close a case by hand.
/// The demo keeps the earlier table as its own, labelled setting (Shutter.Setup.DemoProfilePolicy). Another visit's
/// in-patient movement shows on the plan rather than stopping the write (v1.47, 8 Nov 2026: "Relax it by default"); a site
/// that wants the stop says further_messages.in_patient_movement: stop, and the demo keeps the stop it had.
ClassMethod Default() As %DynamicObject
{
    Set p = {}
    Set p.version = 0
    Set p.receivers = [{"name": ($PARAMETER("Shutter.Production", "RECEIVER")), "system": "the demo bed-management system", "category": "current_state", "tier": 2, "applies": "arrival_order", "resend_timestamp": "original", "cancels": false, "merges": false, "api": {"base": "/downstream/api", "state": "/encounters/{encounter}", "receipt": "/receipts/{key}", "capabilities": "/capabilities", "operations": "/operations"}, "features": {"conditional_writes": true, "receipts": true, "history": true, "dry_run": true}}]
    Set p."authoritative_source" = ""
    Set p."unconditional_resend" = "forbidden"
    Set p.merges = "forbidden"
    Set p.policy = ..ShippedPolicy()
    Set p.approvers = {"role": "Shutter Approvers", "escalation": "the integration team's on-call", "close_needs_approver": false}
    Set p.incident = {"threshold": 5, "window_minutes": 10, "quiet_seconds": 60}
    Set p."model_content" = {"free_text": false}
    Set p.feed = {"time_zone": "Europe/London", "prevent_failures": false}
    Set p."further_messages" = {"in_patient_movement": "show", "a08_location": "stop", "admission_not_found": "person", "scan_seconds": (..#SCANSECONDS)}
    Quit p
}

/// The current profile as a dynamic object (the stored one, else the defaults), with "version" set.
/// The shipped release policy (v1.1.0): approval at every tier for single and ordered chains, the board for interleaved
/// ones. A site that wants a tier released by policy says so in its own profile.
ClassMethod ShippedPolicy() As %DynamicObject
{
    Quit {"1": {"single": "approval", "ordered": "approval", "interleaved": "board"}, "2": {"single": "approval", "ordered": "approval", "interleaved": "board"}, "3": {"single": "approval", "ordered": "approval", "interleaved": "board"}}
}

/// The demo's release policy, the shipped table until v1.1.0, kept as the demo's own, labelled setting: tiers 1 and 2 released by policy for single chains and tier 1 for ordered ones, so the demo's scenarios show
/// a resend the policy releases; approvals elsewhere, the board for interleaved chains. The live hospital then makes tier 2
/// single an approval too (Shutter.Setup.LiveProfilePolicy). Applied by a demo install only, and marked in the profile's
/// source, so the Site profile page says whose answers they are.
ClassMethod DemoPolicy() As %DynamicObject
{
    Quit {"1": {"single": "automatic", "ordered": "automatic", "interleaved": "board"}, "2": {"single": "automatic", "ordered": "approval", "interleaved": "board"}, "3": {"single": "approval", "ordered": "per_chain", "interleaved": "board"}}
}

ClassMethod Current() As %DynamicObject
{
    Set row = ..Row()
    If $ISOBJECT(row) && (row.Json '= "") {
        Set p = ##class(Shutter.Util.Json).Parse(row.Json, .sc)
        If $ISOBJECT(p) Set p.version = row.Version Quit p
    }
    Quit $SELECT(..DemoInstall(): ..Default(), 1: ..ForSite(..Default()))
}

/// Whether this instance is the demo. Every install sets the flag before it seeds; a namespace with no flag has had no
/// install, and keeps the shipped defaults.
ClassMethod DemoInstall() As %Boolean
{
    Quit ''$GET(^Shutter.Config("demo"), 1)
}

/// What a non-demo install starts from: the seed or the defaults with the demo's receivers taken out and no automatic
/// release, so nothing is written with no person until the site says so in its own profile. A site item that happened
/// to share a demo receiver's name would otherwise be written to by policy. A profile needs a receiver, so a list left
/// empty gets one draft to fill in, and a draft is never written to. Changes p and returns it.
ClassMethod ForSite(p As %DynamicObject) As %DynamicObject
{
    Set demoNames = $LISTBUILD($PARAMETER("Shutter.Production", "RECEIVER"), "Records Out")
    Set json = "Shutter.Util.Json"
    Set keep = [], list = p.%Get("receivers")
    If $ISOBJECT(list) {
        Set it = list.%GetIterator()
        While it.%GetNext(, .r) {
            If '$LISTFIND(demoNames, $CLASSMETHOD(json, "Str", r, "name")) Do keep.%Push(r)
        }
    }
    If keep.%Size() = 0 Do keep.%Push({"name": "Your first receiver", "system": "a placeholder: rename it to the production item that delivers to your system, and fill it in", "tier": 3, "applies": "arrival_order", "resend_timestamp": "original", "cancels": false, "merges": false, "features": {"conditional_writes": false, "receipts": false, "history": false, "dry_run": false}, "draft": true})
    Set p.receivers = keep
    Set teams = p.%Get("teams")
    If $ISOBJECT(teams) {
        Set it = teams.%GetIterator()
        While it.%GetNext(, .team) {
            Set names = team.%Get("receivers")
            Continue:'$ISOBJECT(names)
            Set kept = [], ni = names.%GetIterator()
            While ni.%GetNext(, .name) {
                If '$LISTFIND(demoNames, name) Do kept.%Push(name)
            }
            Set team.receivers = kept
        }
    }
    Set policy = p.%Get("policy")
    If $ISOBJECT(policy) {
        Set it = policy.%GetIterator()
        While it.%GetNext(.tier, .row) {
            Continue:'$ISOBJECT(row)
            Set ri = row.%GetIterator()
            While ri.%GetNext(.kind, .value) {
                If value = "automatic" Do row.%Set(kind, "approval")
            }
        }
    }
    Quit p
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
        Set oldMode = ##class(Shutter.Util.RecoveryControl).ModeOfJson(row.Json), newMode = ##class(Shutter.Util.RecoveryControl).ModeOfProfile(p)
        Set sc = ..WriteRow(row, p.%ToJSON(), source, user, row.Version + 1)
        If $$$ISOK(sc) && (oldMode '= newMode) Do ##class(Shutter.Util.RecoveryControl).NoteModeChange(oldMode, newMode, user)
        Set currentVersion = +row.Version
    } Catch ex {
        Set sc = ex.AsStatus()
        If $TLEVEL > 0 TROLLBACK
    }
    LOCK -^Shutter.SiteProfile
    Quit sc
}

/// The row and its history entry saved together at the given version, then the cached readings cleared. Called under the lock.
ClassMethod WriteRow(row As Shutter.Store.SiteProfile, json As %String, source As %String, user As %String, version As %Integer) As %Status [ Private ]
{
    TSTART
    Set row.Version = version
    Set row.Json = json, row.Source = source, row.UpdatedBy = $EXTRACT(user, 1, 160)
    Set row.UpdatedAt = ##class(Shutter.Util.Time).NowUTC()
    Set sc = row.%Save()
    If $$$ISOK(sc) {
        // Every change is kept, with who made it and from where (CONTRACTS 6.4).
        Set v = ##class(Shutter.Store.SiteProfileVersion).%New()
        Set v.Version = row.Version, v.Json = row.Json, v.Source = source, v.UpdatedAt = row.UpdatedAt, v.UpdatedBy = row.UpdatedBy
        Set sc = v.%Save()
    }
    If $$$ISOK(sc) { TCOMMIT  Kill ^Shutter.Config("feedZone"), ^Shutter.Config("preventFailures")  Do ..SyncWatchedFeed() } Else { TROLLBACK }
    Quit sc
}

/// The stop an upgrade to 1.2.0 keeps, written without Validate (Shutter.Setup.KeepStopOnUpgrade, when Store refuses a profile
/// stored before today's checks): the stored profile with further_messages.in_patient_movement: stop and nothing else changed,
/// as a new version, after both the row's and the history's last, whose source is the row's with KEPTSTOP. A profile that
/// names the setting is left alone. It takes the lock when it can and writes when it cannot, so an upgraded site never ends
/// on show. Returns a status; currentVersion is the row's version afterwards.
ClassMethod StoreKeptStop(user As %String = "", Output currentVersion As %Integer) As %Status
{
    Set currentVersion = 0, sc = $$$OK
    LOCK +^Shutter.SiteProfile:5
    Set locked = $TEST
    Try {
        Set row = ..Row()
        Quit:('$ISOBJECT(row) || (row.Json = ""))
        Set currentVersion = +row.Version
        Set p = ##class(Shutter.Util.Json).Parse(row.Json, .sc)
        If '$ISOBJECT(p) || $$$ISERR(sc) Set sc = $$$ERROR($$$GeneralError, "The stored profile is not a JSON object") Quit
        Set fm = p.%Get("further_messages")
        Quit:($ISOBJECT(fm) && 'fm.%IsA("%Library.DynamicArray") && fm.%IsDefined("in_patient_movement"))
        If '$ISOBJECT(fm) || fm.%IsA("%Library.DynamicArray") Set fm = {} Do p.%Set("further_messages", fm)
        Set fm."in_patient_movement" = "stop"
        Set last = 0
        &sql(SELECT MAX(Version) INTO :last FROM Shutter_Store.SiteProfileVersion)
        Set next = $SELECT(+last > +row.Version: +last, 1: +row.Version) + 1
        Set sc = ..WriteRow(row, p.%ToJSON(), $EXTRACT(row.Source _ ..#KEPTSTOP, 1, 500), user, next)
        Set currentVersion = +row.Version
    } Catch ex {
        Set sc = ex.AsStatus()
        If $TLEVEL > 0 TROLLBACK
    }
    LOCK:locked -^Shutter.SiteProfile
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
        If '$LISTFIND($LISTBUILD("version", "receivers", "history_policy", "authoritative_source", "unconditional_resend", "merges", "policy", "approvers", "incident", "model_content", "teams", "mail", "feed", "further_messages", "recovery", "notifications", "reminders", "failure_census"), key) Return key _ ": unknown field"
    }
    If p.%IsDefined("version") && ((p.%Get("version") '= +p.%Get("version")) || (p.%Get("version") < 0)) Quit "version: must be a whole number"
    Set problem = ..RecoveryProblem(p)
    If problem '= "" Quit problem
    Set census = ##class(Shutter.Util.FailureCensus).ProfileProblem(p)
    If census '= "" Quit census
    Set rcv = p.%Get("receivers")
    If '$ISOBJECT(rcv) || (rcv.%Size() = 0) Quit "receivers: must be a non-empty array"
    Set it = rcv.%GetIterator()
    While it.%GetNext(.i, .r) {
        Set at = "receivers[" _ i _ "]"
        If '$ISOBJECT(r) Return at _ ": must be an object"
        If $CLASSMETHOD(json, "Str", r, "name") = "" Return at _ ".name: required"
        // Every reader takes the first entry of a name, so a second one would silently count for nothing.
        If $DATA(receiverNames($CLASSMETHOD(json, "Str", r, "name"))) Return at _ ".name: must be unique"
        Set receiverNames($CLASSMETHOD(json, "Str", r, "name")) = ""
        Set tier = r.%Get("tier")
        If (tier '= +tier) || (tier < 1) || (tier > 3) Return at _ ".tier: must be 1, 2 or 3"
        // The receiver's category (v1.23) and its own history policy, which the category derives when absent.
        If r.%IsDefined("category") && '$LISTFIND($LISTBUILD("current_state", "history_of_record", "orders_results"), r.%Get("category")) Return at _ ".category: must be current_state, history_of_record or orders_results"
        If r.%IsDefined("history_policy") && '$LISTFIND($LISTBUILD("current", "correct"), r.%Get("history_policy")) Return at _ ".history_policy: must be current or correct"
        If r.%IsDefined("strict_answers") && (r.%GetTypeOf("strict_answers") '= "boolean") Return at _ ".strict_answers: must be true or false"
        // A demo receiver's namespace (v1.25): where the scenario runner resets it and sets its faults.
        If r.%IsDefined("demo") {
            Set demo = r.%Get("demo")
            If '$ISOBJECT(demo) || demo.%IsA("%Library.DynamicArray") Return at _ ".demo: must be an object"
            If demo.%IsDefined("namespace") && (demo.%GetTypeOf("namespace") '= "string") Return at _ ".demo.namespace: must be a string"
        }
        If r.%IsDefined("cancels") && (r.%GetTypeOf("cancels") '= "boolean") Return at _ ".cancels: must be true or false"
        // A receiver's document profile (11.2), off when absent.
        If r.%IsDefined("documents") { Set dp = ##class(Shutter.Util.DocumentCase).SettingsProblem(r.%Get("documents")) If dp '= "" Return at _ ".documents" _ dp }
        // The site's one line on where to look (Shutter.Util.ReceiverCheck): a hint for a person, never read by the core.
        If r.%IsDefined("manual_check") {
            Set problem = ##class(Shutter.Util.ReceiverCheck).ManualCheckProblem(r.%Get("manual_check"))
            If problem '= "" Return at _ ".manual_check." _ problem
        }
        // Whether the receiver takes merges (T31); false when absent, and a merge still needs the site's merges: allowed.
        If r.%IsDefined("merges") && (r.%GetTypeOf("merges") '= "boolean") Return at _ ".merges: must be true or false"
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
    // Merges (T31): forbidden when absent; allowed lets a merge go to a receiver whose entry takes them.
    If p.%IsDefined("merges") && '$LISTFIND($LISTBUILD("forbidden", "allowed"), p.%Get("merges")) Quit "merges: must be forbidden or allowed"
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
    // Who approves what: the role and escalation texts stay on record; close_needs_approver is the two-person rule for
    // closing a case by hand, off unless the site says so. Every key is named, so a misspelt switch cannot pass as off.
    If p.%IsDefined("approvers") {
        Set approvers = p.%Get("approvers")
        If '$ISOBJECT(approvers) || approvers.%IsA("%DynamicArray") Quit "approvers: must be an object"
        Set ai = approvers.%GetIterator()
        While ai.%GetNext(.k, .v) {
            If '$LISTFIND($LISTBUILD("role", "escalation", "close_needs_approver"), k) Return "approvers." _ k _ ": unknown setting"
            If (k = "close_needs_approver") && (approvers.%GetTypeOf(k) '= "boolean") Return "approvers.close_needs_approver: must be true or false"
            If (k '= "close_needs_approver") && (approvers.%GetTypeOf(k) '= "string") Return "approvers." _ k _ ": must be a string"
        }
    }
    // The feed: the time zone of timestamps that carry no offset (T28).
    If p.%IsDefined("feed") {
        Set feed = p.%Get("feed")
        If '$ISOBJECT(feed) Quit "feed: must be an object"
        Set fi = feed.%GetIterator()
        While fi.%GetNext(.k, .v) {
            If '$LISTFIND($LISTBUILD("time_zone", "prevent_failures", "source_skew_seconds", "prove_origin"), k) Return "feed." _ k _ ": unknown setting"
            // How far apart two source systems' events still count as simultaneous, in whole seconds.
            If k = "source_skew_seconds" {
                If (feed.%GetTypeOf(k) '= "number") || (v '= (v \ 1)) || (v < 0) || (v > 3600) Return "feed.source_skew_seconds: must be a whole number of seconds from 0 to 3600"
                Continue
            }
            // An automatic release needs a proved source (CONTRACTS 11): true or false.
            If k = "prove_origin" {
                If feed.%GetTypeOf(k) '= "boolean" Return "feed.prove_origin: must be true or false"
                Continue
            }
            // Hold a message whose schema is not loaded here (v1.34, "prevent failures"): true or false.
            If k = "prevent_failures" {
                If feed.%GetTypeOf(k) '= "boolean" Return "feed.prevent_failures: must be true or false"
                Continue
            }
            // UTC, Europe/London and a fixed offset by Shutter's own rules; any other IANA zone when Embedded Python's zoneinfo knows it (v1.30).
            Set zoneOk = (feed.%GetTypeOf(k) = "string") && ($LISTFIND($LISTBUILD("UTC", "Europe/London"), v) || $MATCH(v, "^[+-](0[0-9]|1[0-4]):[0-5][0-9]$") || ##class(Shutter.Util.Time).PythonZoneKnown(v))
            If 'zoneOk Return "feed.time_zone: must be UTC, Europe/London, a fixed offset such as +01:00 (up to 14:00), or an IANA zone name this IRIS knows (for example Europe/Paris)"
        }
    }
    // How rigid a site wants the check for further messages: a safe stop unless it says otherwise.
    If p.%IsDefined("further_messages") {
        Set fm = p.%Get("further_messages")
        If '$ISOBJECT(fm) || fm.%IsA("%Library.DynamicArray") Quit "further_messages: must be an object"
        Set fi = fm.%GetIterator()
        While fi.%GetNext(.k, .v) {
            If k = "in_patient_movement" {
                If '$LISTFIND($LISTBUILD("stop", "show"), v) Return "further_messages.in_patient_movement: must be stop or show"
            } ElseIf k = "a08_location" {
                If '$LISTFIND($LISTBUILD("stop", "show"), v) Return "further_messages.a08_location: must be stop or show"
            } ElseIf k = "admission_not_found" {
                If '$LISTFIND($LISTBUILD("person", "policy"), v) Return "further_messages.admission_not_found: must be person or policy"
            } ElseIf k = "scan_seconds" {
                If (fm.%GetTypeOf(k) '= "number") || (v '= (v \ 1)) || (v < 1) || (v > 600) Return "further_messages.scan_seconds: must be a whole number of seconds from 1 to 600"
            } Else {
                Return "further_messages." _ k _ ": unknown setting"
            }
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
    // The teams an escalation can go to, and the mail rules (T29, CONTRACTS 10): the sender and every mailbox are bare
    // addresses (Shutter.Util.Mail), and a mailbox needs a domain in mail.allowed_domains, so a profile that names a
    // team while the list is empty or absent is refused.
    Set domains = ""
    If p.%IsDefined("mail") {
        Set mail = p.%Get("mail")
        If '$ISOBJECT(mail) Quit "mail: must be an object"
        Set mi = mail.%GetIterator()
        While mi.%GetNext(.k, .v) {
            If '$LISTFIND($LISTBUILD("from", "allowed_domains"), k) Return "mail." _ k _ ": unknown setting"
            If (k = "from") {
                If mail.%GetTypeOf(k) '= "string" Return "mail.from: must be a string"
                If v '= "" {
                    Set problem = ##class(Shutter.Util.Mail).ShapeProblem(v)
                    If problem '= "" Return "mail.from: " _ problem
                }
            }
            If (k = "allowed_domains") {
                If '$ISOBJECT(v) || v.%IsA("%DynamicObject") Return "mail.allowed_domains: must be an array of domains"
                Set di = v.%GetIterator()
                While di.%GetNext(.j, .d) {
                    If (v.%GetTypeOf(j) '= "string") || (d = "") Return "mail.allowed_domains[" _ j _ "]: must be a domain"
                    Set problem = ##class(Shutter.Util.Mail).DomainProblem(d)
                    If problem '= "" Return "mail.allowed_domains[" _ j _ "]: " _ problem
                }
                Set domains = ##class(Shutter.Util.Mail).Domains(v)
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
                If '$LISTFIND($LISTBUILD("id", "name", "mailbox", "cc", "receivers", "sources"), k) Return at _ "." _ k _ ": unknown field"
            }
            For f = "id", "name", "mailbox" { If ($CLASSMETHOD(json, "Str", t, f) = "") || (t.%GetTypeOf(f) '= "string") Return at _ "." _ f _ ": required" }
            If $LISTFIND(ids, t.%Get("id")) Return at _ ".id: must be unique"
            Set ids = ids _ $LISTBUILD(t.%Get("id"))
            Set problem = ##class(Shutter.Util.Mail).AddressProblem(t.%Get("mailbox"), domains)
            If problem '= "" Return at _ ".mailbox: " _ problem
            If t.%IsDefined("cc") {
                Set cc = t.%Get("cc")
                If '$ISOBJECT(cc) || cc.%IsA("%DynamicObject") Return at _ ".cc: must be an array of mailboxes"
                Set ci = cc.%GetIterator()
                While ci.%GetNext(.j, .m) {
                    If cc.%GetTypeOf(j) '= "string" Return at _ ".cc[" _ j _ "]: must be a mailbox"
                    Set problem = ##class(Shutter.Util.Mail).AddressProblem(m, domains)
                    If problem '= "" Return at _ ".cc[" _ j _ "]: " _ problem
                }
            }
            If t.%IsDefined("receivers") {
                Set rl = t.%Get("receivers")
                If '$ISOBJECT(rl) || rl.%IsA("%DynamicObject") Return at _ ".receivers: must be an array of receiver names"
                Set ri = rl.%GetIterator()
                While ri.%GetNext(.j, .m) { If (rl.%GetTypeOf(j) '= "string") || (m = "") Return at _ ".receivers[" _ j _ "]: must be a receiver name" }
            }
            // The sending applications (MSH-3) whose merges the team decides (T31), such as PAS.
            If t.%IsDefined("sources") {
                Set sl = t.%Get("sources")
                If '$ISOBJECT(sl) || sl.%IsA("%DynamicObject") Return at _ ".sources: must be an array of sending applications"
                Set si = sl.%GetIterator()
                While si.%GetNext(.j, .m) { If (sl.%GetTypeOf(j) '= "string") || (m = "") Return at _ ".sources[" _ j _ "]: must be a sending application (MSH-3)" }
            }
        }
    }
    // What a receiver's outage needs (CONTRACTS 6.4). After the mail rules, because a receiver's mail.to needs their domains.
    Set it = rcv.%GetIterator()
    While it.%GetNext(.i, .r) {
        Set problem = ..ReceiverWatchProblem(r, "receivers[" _ i _ "]", domains)
        If problem '= "" Return problem
    }
    // The reminder for cases left open: off unless it says so, and its officer's address goes by the mail rules above.
    If p.%IsDefined("reminders") {
        Set problem = ##class(Shutter.Util.CaseReminder).ProfileProblem(p.%Get("reminders"), domains)
        If problem '= "" Quit problem
    }
    If p.%IsDefined("incident") {
        Set inc = p.%Get("incident")
        If '$ISOBJECT(inc) Quit "incident: must be an object"
        Set ii = inc.%GetIterator()
        While ii.%GetNext(.k, .n) {
            If '$LISTFIND($LISTBUILD("threshold", "window_minutes", "quiet_seconds", "max_intake_seconds"), k) Return "incident." _ k _ ": unknown setting"
            Set zero = (k = "quiet_seconds") || (k = "max_intake_seconds")
            If (n '= +n) || (n < 0) || ('zero && (n < 1)) Return "incident." _ k _ ": must be a whole number" _ $SELECT(zero: "", 1: " of 1 or more")
        }
    }
    Quit ""
}

/// What is wrong with the keys of one receiver's entry that describe its outages, with the field named, or "". Each key
/// is checked only when present, so an entry with none of them validates as it always did. r has passed Validate's first
/// loop, so its category is valid or absent, and absent reads as current_state (ReceiverCategory).
ClassMethod ReceiverWatchProblem(r As %DynamicObject, at As %String, domains As %List) As %String
{
    Set category = $SELECT(r.%IsDefined("category"): r.%Get("category"), 1: "current_state")
    If r.%IsDefined("watch") {
        If r.%GetTypeOf("watch") '= "object" Quit at _ ".watch: must be an object"
        Set w = r.%Get("watch")
        Set wi = w.%GetIterator()
        While wi.%GetNext(.k, .v) { If '$LISTFIND($LISTBUILD("namespace", "item"), k) Return at _ ".watch." _ k _ ": unknown setting" }
        For f = "namespace", "item" { If (w.%GetTypeOf(f) '= "string") || (w.%Get(f) = "") Return at _ ".watch." _ f _ ": required" }
    }
    For f = "runbook", "call" { If r.%IsDefined(f) && (r.%GetTypeOf(f) '= "string") Return at _ "." _ f _ ": must be a string" }
    If r.%IsDefined("approvers") {
        If r.%GetTypeOf("approvers") '= "array" Quit at _ ".approvers: must be an array of names"
        Set list = r.%Get("approvers")
        Set ai = list.%GetIterator()
        While ai.%GetNext(.j, .m) { If (list.%GetTypeOf(j) '= "string") || (m = "") Return at _ ".approvers[" _ j _ "]: must be a name" }
    }
    // What a Completed header proves at this receiver is the site's word, on any category.
    If r.%IsDefined("ack_level") && ((r.%GetTypeOf("ack_level") '= "string") || '$LISTFIND($LISTBUILD("connection", "commit", "application"), r.%Get("ack_level"))) Quit at _ ".ack_level: must be connection, commit or application"
    If r.%IsDefined("duplicates") {
        If r.%GetTypeOf("duplicates") '= "object" Quit at _ ".duplicates: must be an object"
        Set d = r.%Get("duplicates")
        Set di = d.%GetIterator()
        While di.%GetNext(.k, .v) { If '$LISTFIND($LISTBUILD("behaviour", "code", "phrase", "refers_to"), k) Return at _ ".duplicates." _ k _ ": unknown setting" }
        If d.%IsDefined("behaviour") && ((d.%GetTypeOf("behaviour") '= "string") || '$LISTFIND($LISTBUILD("refuses", "files_twice", "unknown"), d.%Get("behaviour"))) Quit at _ ".duplicates.behaviour: must be refuses, files_twice or unknown"
        For f = "code", "phrase" { If d.%IsDefined(f) && (d.%GetTypeOf(f) '= "string") Return at _ ".duplicates." _ f _ ": must be a string" }
        If d.%IsDefined("refers_to") && ((d.%GetTypeOf("refers_to") '= "string") || '$LISTFIND($LISTBUILD("message", "order", "result", "unknown"), d.%Get("refers_to"))) Quit at _ ".duplicates.refers_to: must be message, order, result or unknown"
        // A refusal is matched by field, so a declared refusal with neither field could never be recognised.
        If (d.%Get("behaviour") = "refuses") && (d.%Get("code") = "") && (d.%Get("phrase") = "") Quit at _ ".duplicates.behaviour: refuses needs a code or a phrase"
    }
    If r.%IsDefined("engine_resend") {
        If r.%GetTypeOf("engine_resend") '= "boolean" Quit at _ ".engine_resend: must be true or false"
        If r.%Get("engine_resend") {
            If (category '= "orders_results") && (r.%Get("ack_level") '= "application") Quit at _ ".engine_resend: needs ack_level application on a current_state or history_of_record receiver"
            // The engine sends the stored body as it stands. fresh is the questionnaire's word for a rewritten MSH-7.
            If $LISTFIND($LISTBUILD("rewritten", "fresh"), r.%Get("resend_timestamp")) Quit at _ ".engine_resend: refused beside resend_timestamp rewritten, since the stored message goes out unchanged"
        }
    }
    If r.%IsDefined("hold") {
        If r.%GetTypeOf("hold") '= "object" Quit at _ ".hold: must be an object"
        If category = "orders_results" Quit at _ ".hold: is for ADT receivers only, not orders_results"
        Set h = r.%Get("hold")
        Set hi = h.%GetIterator()
        While hi.%GetNext(.k, .v) { If k '= "minutes" Return at _ ".hold." _ k _ ": unknown setting" }
        If h.%IsDefined("minutes") {
            Set n = h.%Get("minutes")
            If (h.%GetTypeOf("minutes") '= "number") || (n '= (n \ 1)) || (n < 1) || (n > 60) Quit at _ ".hold.minutes: must be a whole number from 1 to 60"
        }
    }
    If r.%IsDefined("mail") {
        If r.%GetTypeOf("mail") '= "object" Quit at _ ".mail: must be an object"
        Set mail = r.%Get("mail")
        Set mi = mail.%GetIterator()
        While mi.%GetNext(.k, .v) { If '$LISTFIND($LISTBUILD("to", "on"), k) Return at _ ".mail." _ k _ ": unknown setting" }
        Set to = mail.%Get("to")
        If (mail.%GetTypeOf("to") '= "array") || (to.%Size() = 0) Quit at _ ".mail.to: must be an array of one or more addresses"
        Set ti = to.%GetIterator()
        While ti.%GetNext(.j, .m) {
            If to.%GetTypeOf(j) '= "string" Return at _ ".mail.to[" _ j _ "]: must be an address"
            Set problem = ##class(Shutter.Util.Mail).AddressProblem(m, domains)
            If problem '= "" Return at _ ".mail.to[" _ j _ "]: " _ problem
        }
        Set on = mail.%Get("on")
        If (mail.%GetTypeOf("on") '= "array") || (on.%Size() = 0) Quit at _ ".mail.on: must be an array of one or more of open, needs_person and closed"
        Set oi = on.%GetIterator()
        While oi.%GetNext(.j, .m) { If (on.%GetTypeOf(j) '= "string") || '$LISTFIND($LISTBUILD("open", "needs_person", "closed"), m) Return at _ ".mail.on[" _ j _ "]: must be open, needs_person or closed" }
    }
    For f = "resend_approval_minutes", "settle_minutes", "window_minutes" {
        If r.%IsDefined(f) {
            Set n = r.%Get(f)
            If (r.%GetTypeOf(f) '= "number") || (n '= (n \ 1)) || (n < 1) Return at _ "." _ f _ ": must be a whole number of 1 or more"
        }
    }
    Quit ""
}

/// recovery.mode and notifications.shadow_delivery, the only keys under those fields. Each may be left out.
ClassMethod RecoveryProblem(p As %DynamicObject) As %String [ Private ]
{
    If p.%IsDefined("recovery") {
        Set r = p.%Get("recovery")
        If '$ISOBJECT(r) || 'r.%IsA("%DynamicObject") Return "recovery: must be an object"
        Set it = r.%GetIterator()
        While it.%GetNext(.key) { If key '= "mode" Return "recovery." _ key _ ": unknown field" }
        If r.%IsDefined("mode") && '$LISTFIND($LISTBUILD("shadow", "enabled"), r.%Get("mode")) Return "recovery.mode: must be shadow or enabled"
    }
    If p.%IsDefined("notifications") {
        Set n = p.%Get("notifications")
        If '$ISOBJECT(n) || 'n.%IsA("%DynamicObject") Return "notifications: must be an object"
        Set it = n.%GetIterator()
        While it.%GetNext(.key) { If key '= "shadow_delivery" Return "notifications." _ key _ ": unknown field" }
        If n.%IsDefined("shadow_delivery") && '$LISTFIND($LISTBUILD("disabled", "enabled"), n.%Get("shadow_delivery")) Return "notifications.shadow_delivery: must be disabled or enabled"
    }
    Quit ""
}

/// The entries of the receivers the site asks Shutter to watch: those with a watch block, none on a profile without one.
ClassMethod WatchedReceivers() As %DynamicArray
{
    Set out = []
    Set list = ..Current().%Get("receivers")
    If '$ISOBJECT(list) Quit out
    Set iter = list.%GetIterator()
    While iter.%GetNext(.i, .r) { If $ISOBJECT(r) && r.%IsDefined("watch") Do out.%Push(r) }
    Quit out
}

/// The acknowledgement level the site declares for a receiver: connection when it declares none or isn't named.
ClassMethod ReceiverAckLevel(name As %String) As %String
{
    Set r = ..Receiver(name)
    Set level = $SELECT($ISOBJECT(r): ##class(Shutter.Util.Json).Str(r, "ack_level"), 1: "")
    Quit $SELECT(level = "": "connection", 1: level)
}

/// What the site declares a receiver does with a duplicate, always with behaviour and refers_to: unknown when it doesn't say.
ClassMethod ReceiverDuplicates(name As %String) As %DynamicObject
{
    Set out = {"behaviour": "unknown", "refers_to": "unknown"}
    Set r = ..Receiver(name)
    Set d = $SELECT($ISOBJECT(r): r.%Get("duplicates"), 1: "")
    If '$ISOBJECT(d) Quit out
    Set iter = d.%GetIterator()
    While iter.%GetNext(.k, .v) { Do out.%Set(k, v) }
    Quit out
}

/// A receiver's minutes: resend_approval_minutes (15), settle_minutes (10) or window_minutes (5), its own figure when it gives one.
ClassMethod ReceiverMinutes(name As %String, setting As %String) As %Integer
{
    Set fallback = $CASE(setting, "resend_approval_minutes": 15, "settle_minutes": 10, "window_minutes": 5)
    Set r = ..Receiver(name)
    If $ISOBJECT(r) && (r.%GetTypeOf(setting) = "number") Quit +r.%Get(setting)
    Quit fallback
}

/// The minutes of a receiver's hold, 10 when its block doesn't say; 0 with no block, and always on orders_results.
ClassMethod ReceiverHoldMinutes(name As %String) As %Integer
{
    Set r = ..Receiver(name)
    If '$ISOBJECT(r) || (r.%GetTypeOf("hold") '= "object") || (..ReceiverCategory(name) = "orders_results") Quit 0
    Set h = r.%Get("hold")
    Quit $SELECT(h.%GetTypeOf("minutes") = "number": +h.%Get("minutes"), 1: 10)
}

/// What a profile's source gains when an upgrade to 1.2.0 wrote the stop a site had (Shutter.Setup.KeepStopOnUpgrade).
Parameter KEPTSTOP = " (kept stop on upgrade to 1.2.0)";

/// Seed from knowledge/site/profile.json when the file exists and differs from what is stored. A seed's profile that kept
/// its stop on the upgrade to 1.2.0 (the seed's path with KEPTSTOP) still follows the seed, with the stop kept.
ClassMethod SeedFromFile(path As %String) As %Status
{
    If '##class(%File).Exists(path) Quit $$$OK
    Set text = ##class(Shutter.Knowledge.Text).ReadFile(path)
    If text = "" Quit $$$OK
    Set p = ##class(Shutter.Util.Json).Parse(text, .sc)
    If '$ISOBJECT(p) || $$$ISERR(sc) Quit $$$ERROR($$$GeneralError, "The seed profile " _ path _ " is not a JSON object")
    If '..DemoInstall() Set p = ..ForSite(p)
    Set row = ..Row()
    // The file is the same for a site and the demo and says nothing of recovery, which a site's install reads as shadow.
    // The demo seeds enabled explicitly (CONTRACTS 18), and so do the demo's marked forms: the live hospital's, the demo's own
    // policy (Shutter.Setup.DemoProfilePolicy) and both together, which an upgrade from 1.1.0 finds stored with no recovery.
    If '..SiteInstall() {
        Do p.%Set("recovery", {"mode": "enabled"})
        Set marked = $LISTBUILD(path _ " (live hospital)", path _ " (demo)", path _ " (demo) (live hospital)")
        If $ISOBJECT(row) && $LISTFIND(marked, row.Source) && (##class(Shutter.Util.RecoveryControl).ModeOfJson(row.Json) '= "enabled") {
            Set live = ##class(Shutter.Util.Json).Parse(row.Json, .lsc)
            If $ISOBJECT(live) Do live.%Set("recovery", {"mode": "enabled"}) Quit ..Store(live.%ToJSON(), row.Source, "install")
        }
    }
    // The seed fills an empty store and follows its own file; a profile a person saved (another source) is theirs and
    // is never overwritten by a reinstall or a restart.
    Set kept = path _ ..#KEPTSTOP
    If $ISOBJECT(row) && (row.Source '= path) && (row.Source '= kept) Quit $$$OK
    Set source = path
    If $ISOBJECT(row) && (row.Source = kept) {
        Set source = kept, fm = p.%Get("further_messages")
        If '$ISOBJECT(fm) || fm.%IsA("%Library.DynamicArray") Set fm = {} Do p.%Set("further_messages", fm)
        Set fm."in_patient_movement" = "stop"
    }
    If $ISOBJECT(row) && (row.Json = p.%ToJSON()) Quit $$$OK
    Quit ..Store(p.%ToJSON(), source)
}

/// The site's allowed mail domains (mail.allowed_domains) as a $LIST, lowercased; an empty list when the profile names
/// none, which allows no address (Shutter.Util.Mail).
ClassMethod AllowedDomains() As %List
{
    Quit ##class(Shutter.Util.Mail).Domains(..Mail().%Get("allowed_domains"))
}

/// The problem with a list of addresses a person typed (comma separated) against the profile's mail.allowed_domains:
/// "" when every address is one bare address inside the allowed domains, else the first offending address and why.
ClassMethod AddressesProblem(list As %String) As %String
{
    Quit ##class(Shutter.Util.Mail).AddressesProblem(list, ..AllowedDomains())
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
    Try { Set ^Shutter.Config("feedZone") = zone } Catch ex { }
    Quit zone
}

/// How far apart, in seconds, two source systems' events for an encounter still count as simultaneous (catalogue E7):
/// feed.source_skew_seconds, or 300 when the profile doesn't say, the five minutes the time checks already allow a clock.
/// A site that trusts its clocks can narrow it; 0 keeps the exact second.
ClassMethod SourceSkewSeconds() As %Integer
{
    Set feed = ..Current().%Get("feed")
    If $ISOBJECT(feed) && (feed.%GetTypeOf("source_skew_seconds") = "number") Quit +feed.%Get("source_skew_seconds")
    Quit 300
}

/// What a further in-patient movement for the patient on another visit does to a write: stop, or show. A profile that doesn't
/// say reads show on a site's install (the default since v1.47) and stop on a demo instance, whoever saved its profile, so the
/// demo keeps its stop (CONTRACTS 6.5).
ClassMethod FurtherMovement() As %String
{
    Quit ..FurtherSetting("in_patient_movement", $SELECT(+$GET(^Shutter.Config("demo")): "stop", 1: "show"))
}

/// What a failed or later A08 naming another ward or bed does to a write: stop (the default) or show, for a site that repeats
/// stale locations on full-state A08s.
ClassMethod FurtherA08Location() As %String
{
    Quit ..FurtherSetting("a08_location", "stop")
}

/// Who releases a failed admission the receiver answers 404 for: person (the default) or policy, the tier's own.
ClassMethod AdmissionNotFound() As %String
{
    Quit ..FurtherSetting("admission_not_found", "person")
}

/// How long one read of a namespace's messages may take at a write, before it counts as not whole and blocks the write:
/// further_messages.scan_seconds, or the default when the profile doesn't say.
ClassMethod FurtherScanSeconds(profile As %DynamicObject = "") As %Integer
{
    If '$ISOBJECT(profile) Set profile = ..Current()
    Set fm = profile.%Get("further_messages")
    If $ISOBJECT(fm) && (fm.%GetTypeOf("scan_seconds") = "number") Quit +fm.%Get("scan_seconds")
    Quit ..#SCANSECONDS
}

ClassMethod FurtherSetting(name As %String, default As %String) As %String [ Private ]
{
    Set fm = ..Current().%Get("further_messages")
    Quit $SELECT($ISOBJECT(fm): ##class(Shutter.Util.Json).Str(fm, name, default), 1: default)
}

/// Whether the site holds a message whose HL7 schema category is not loaded here instead of delivering what was read by
/// position (v1.34, "prevent failures"; CONTRACTS 6.4 and 12): off unless the profile says feed.prevent_failures: true.
/// Read on the feed's hot path for every message, so cached as the zone is; every store of the profile clears the cache.
ClassMethod PreventFailures() As %Boolean
{
    Set cached = $GET(^Shutter.Config("preventFailures"))
    If cached '= "" Quit +cached
    Set feed = ..Current().%Get("feed")
    Set on = $ISOBJECT(feed) && (feed.%GetTypeOf("prevent_failures") = "boolean") && feed.%Get("prevent_failures")
    // GET /health reaches this for anyone through the Doctor, and a caller who cannot write answered <PROTECT> here whenever
    // the cache was empty: on a fresh install with no demo, and after every save of the profile. The answer needs no cache.
    Try { Set ^Shutter.Config("preventFailures") = ''on } Catch ex { }
    Quit ''on
}

/// Whether an automatic release needs the case's source proved (Shutter.Operation.Origin; CONTRACTS 6.4 and 11): yes unless the profile
/// says feed.prove_origin: false, for a forwarder on another instance. The profile given, else the current one.
ClassMethod ProveOrigin(profile As %DynamicObject = "") As %Boolean
{
    If '$ISOBJECT(profile) Set profile = ..Current()
    Set feed = profile.%Get("feed")
    If $ISOBJECT(feed) && (feed.%GetTypeOf("prove_origin") = "boolean") Quit ''feed.%Get("prove_origin")
    Quit 1
}

/// The demo hospital follows the setting (CONTRACTS 11): when a hospital namespace is recorded here, its PAS In takes
/// structural validation and the bad-message handler, or loses them, as the profile says (Hospital.Setup.PreventFailures).
/// A real site's integration team does that step itself (INSTALL.md, section 5). Never fails the store.
ClassMethod SyncWatchedFeed()
{
    Try {
        Set ns = $GET(^Shutter.Config("hospitalNamespace"))
        Quit:ns=""
        Set on = ..PreventFailures()
        New $NAMESPACE
        Set $NAMESPACE = ns
        If ##class(%Dictionary.CompiledClass).%ExistsId("Hospital.Setup") Do $CLASSMETHOD("Hospital.Setup", "PreventFailures", on)
    } Catch ex {
    }
}

/// Whether the site allows OBX and NTE free text to go to a model (T27): off unless the profile says so.
ClassMethod ModelFreeText() As %Boolean
{
    Set mc = ..Current().%Get("model_content")
    Quit $ISOBJECT(mc) && ##class(Shutter.Util.Json).Bool(mc, "free_text", 0)
}

/// Whether closing a case by hand (POST /cases/{id}/close) needs an approver, the two-person rule some trusts keep:
/// off unless the profile's approvers.close_needs_approver is true, so an operator who escalated a case closes it too.
ClassMethod CloseNeedsApprover() As %Boolean
{
    Set approvers = ..Current().%Get("approvers")
    Quit $ISOBJECT(approvers) && approvers.%IsA("%DynamicObject") && (approvers.%GetTypeOf("close_needs_approver") = "boolean") && approvers.%Get("close_needs_approver")
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

/// The receiver's tier (the production item's name), default 2.
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

/// A boolean of the receiver's entry (cancels, merges): false when the profile does not name the receiver or the
/// entry does not answer.
ClassMethod ReceiverFlag(name As %String, flag As %String) As %Boolean
{
    Set r = ..Receiver(name)
    If '$ISOBJECT(r) Quit 0
    Quit ##class(Shutter.Util.Json).Bool(r, flag, 0)
}

/// Whether the site lets a merge (ADT^A40) go to a receiver at all (T31): only when the profile says merges: allowed.
/// Absent, or anything else, is forbidden, and the receiver's own entry must take merges too (ReceiverFlag).
ClassMethod MergesAllowed() As %Boolean
{
    Quit ..Flag("merges", "forbidden") = "allowed"
}

/// The downstream system's paths, used when a receiver's entry gives none: the shape the demo's receiver speaks.
ClassMethod DefaultApi() As %DynamicObject
{
    Quit {"base": "/downstream/api", "state": "/encounters/{encounter}", "receipt": "/receipts/{key}", "capabilities": "/capabilities", "operations": "/operations"}
}

/// Whether this is a site's install, not the demo: a receiver a site's profile does not name is unknown there, never the
/// demo's (v1.42).
ClassMethod SiteInstall() As %Boolean
{
    Quit $GET(^Shutter.Config("demo"), 1) = 0
}

/// Declared features and no api: a receiver with no API of its own, such as a plain MLLP system. It has no paths: falling back
/// to the defaults would read the demo receiver in its place and believe its capabilities over the declared ones. An entry
/// with neither reads as a profile from before v1.8 does, on the defaults.
ClassMethod HasNoApi(entry) As %Boolean [ Private ]
{
    If '$ISOBJECT(entry) || $ISOBJECT(entry.%Get("api")) Quit 0
    // An orders and results receiver (a LIMS, order communications) has no receiver API Shutter reads: one the site gave no
    // api is never read at the demo receiver's address, and its label names no address.
    Quit $ISOBJECT(entry.%Get("features")) || (entry.%Get("category") = "orders_results")
}

/// One of a receiver's paths (state, receipt, capabilities, operations), with the receiver's base in front and the
/// placeholders {encounter} and {key} filled in, URL-encoded. An empty path (the receiver has no such endpoint)
/// stays empty: the caller then uses what the profile declares instead.
ClassMethod ReceiverPath(name As %String, kind As %String, encounter As %String = "", key As %String = "") As %String
{
    Set r = ..Receiver(name), defaults = ..DefaultApi()
    If ..HasNoApi(r) Quit ""
    // A site's receiver the profile does not name (v1.42) has no API: the defaults are the demo receiver's.
    If '$ISOBJECT(r) && ..SiteInstall() Quit ""
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
    If '$ISOBJECT(r) && ..SiteInstall() Quit {"conditional_writes": false, "receipts": false, "history": false, "dry_run": false}
    Quit {"conditional_writes": true, "receipts": true, "history": true, "dry_run": true}
}

/// Whether Shutter checks a receiver's answers against the contract (CONTRACTS 6.4), the default: a read counts only with the
/// kind's own field or error, a 200 is a delivery only with its receipt or applied, and a receipt or history entry must hold
/// the operation's own digest, ward and bed to close a case. A site whose receiver answers another way, and whose answers it
/// has looked at, sets strict_answers false on its entry: the answers are then read on their status alone. Such a site's
/// gateway page or corrected message can read as delivered or committed.
ClassMethod StrictAnswers(name As %String) As %Boolean
{
    Set r = ..Receiver(name)
    If '$ISOBJECT(r) || (r.%GetTypeOf("strict_answers") '= "boolean") Quit 1
    Quit ''r.%Get("strict_answers")
}

/// The receiver's category (CONTRACTS 6.4, v1.23): current_state (a bed manager or whiteboard, where only the present
/// placement matters), history_of_record (a PAS, EPR or warehouse, whose movement history must be complete) or
/// orders_results (order communications or a LIMS, whose cases go to a person with no resend from the case). current_state
/// when the entry names none or the profile does not name the receiver, which is what every profile written before v1.23
/// meant.
ClassMethod ReceiverCategory(name As %String) As %String
{
    Set r = ..Receiver(name)
    Set category = $SELECT($ISOBJECT(r): ##class(Shutter.Util.Json).Str(r, "category"), 1: "")
    If '$LISTFIND($LISTBUILD("current_state", "history_of_record", "orders_results"), category) Quit "current_state"
    Quit category
}

/// The receiver's history policy, current or correct (v1.23): the entry's own history_policy when it has one, else
/// derived from its category (history_of_record keeps the history straight: correct; the others: current), else, for
/// an entry with neither, the profile's site-wide history_policy (deprecated since v1.23), else current.
ClassMethod ReceiverHistoryPolicy(name As %String) As %String
{
    Set r = ..Receiver(name)
    Set own = $SELECT($ISOBJECT(r): ##class(Shutter.Util.Json).Str(r, "history_policy"), 1: "")
    If $LISTFIND($LISTBUILD("current", "correct"), own) Quit own
    If $ISOBJECT(r) && (##class(Shutter.Util.Json).Str(r, "category") '= "") Quit $SELECT(..ReceiverCategory(name) = "history_of_record": "correct", 1: "current")
    Quit $SELECT(..Flag("history_policy", "current") = "correct": "correct", 1: "current")
}

/// The namespace a demo receiver runs in (its entry's demo.namespace, v1.25), or this namespace: where the scenario
/// runner resets the receiver and sets its faults.
ClassMethod ReceiverNamespace(name As %String) As %String
{
    Set r = ..Receiver(name)
    Set demo = $SELECT($ISOBJECT(r): r.%Get("demo"), 1: "")
    Set ns = $SELECT($ISOBJECT(demo): ##class(Shutter.Util.Json).Str(demo, "namespace"), 1: "")
    Quit $SELECT(ns = "": $NAMESPACE, 1: $ZCONVERT(ns, "U"))
}

/// The names of the receivers the profile lists, in order.
ClassMethod ReceiverNames() As %DynamicArray
{
    Set out = [], list = ..Current().%Get("receivers")
    If '$ISOBJECT(list) Quit out
    Set iter = list.%GetIterator()
    While iter.%GetNext(.i, .r) { Set n = $SELECT($ISOBJECT(r): ##class(Shutter.Util.Json).Str(r, "name"), 1: "") If n '= "" Do out.%Push(n) }
    Quit out
}

/// The receiver's description for a person: its display name and base path.
ClassMethod ReceiverLabel(name As %String) As %String
{
    Set r = ..Receiver(name)
    Set system = ..DisplayName(r, name)
    If ..HasNoApi(r) Quit system
    Set base = ##class(Shutter.Util.Json).Str($SELECT($ISOBJECT(r) && $ISOBJECT(r.%Get("api")): r.%Get("api"), 1: ..DefaultApi()), "base", "/downstream/api")
    Quit system _ " (" _ base _ ")"
}

/// The words the onboarding puts after a drafted receiver's item and namespace in its system text, until a person fills it in.
Parameter DRAFTSYSTEM = ": draft, a person fills this in";

/// The name a person reads for a receiver entry: its system text as written; for a draft whose system is still the
/// onboarding's placeholder (or empty), the item and namespace it was drafted from; else the receiver's name.
ClassMethod DisplayName(entry, name As %String = "") As %String
{
    Set json = "Shutter.Util.Json"
    If '$ISOBJECT(entry) Quit name
    If name = "" Set name = $CLASSMETHOD(json, "Str", entry, "name")
    Set system = $CLASSMETHOD(json, "Str", entry, "system")
    If ..IsDraft(entry) {
        Set note = ..#DRAFTSYSTEM
        If (system '= "") && ($EXTRACT(system, *-$LENGTH(note)+1, *) '= note) Quit system
        Set item = $CLASSMETHOD(json, "Str", entry, "item"), ns = $CLASSMETHOD(json, "Str", entry, "namespace")
        If item = "" {
            Set item = $SELECT(system '= "": $EXTRACT(system, 1, *-$LENGTH(note)), 1: name)
        } ElseIf ns '= "" {
            Set item = item _ " in " _ ns
        }
        Quit $SELECT(item '= "": item, 1: name)
    }
    Quit $SELECT(system = "": name, 1: system)
}

/// Whether a receiver entry is a draft the onboarding made: declared with no API, every feature false, until a person
/// fills in its details and saves it without draft.
ClassMethod IsDraft(entry) As %Boolean
{
    Quit $ISOBJECT(entry) && ##class(Shutter.Util.Json).Bool(entry, "draft", 0)
}

/// For a receiver whose entry is still a draft, what the gate and the email say instead of an unreadable receiver: it was
/// declared with no API and a person fills in its details. Empty for any other receiver.
ClassMethod DraftDetail(name As %String) As %String
{
    Set r = ..Receiver(name)
    If '..IsDraft(r) Quit ""
    Quit "The receiver " _ ..DisplayName(r, name) _ " was declared with no API when its namespace was onboarded, so there is nothing to read; a person fills in its details"
}

/// The next action for a receiver whose entry is still a draft.
ClassMethod DraftNextAction(name As %String) As %String
{
    Quit "Fill in the receiver's entry in the site profile (what the system is, its category and tier, and its API if it has one), save it without draft, then reinvestigate the case. Nothing is sent meanwhile."
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

/// A top-level flag of the profile as a string (history_policy, authoritative_source, unconditional_resend, merges).
ClassMethod Flag(name As %String, default As %String = "") As %String
{
    Quit ##class(Shutter.Util.Json).Str(..Current(), name, default)
}

/// An incident setting: threshold, window_minutes, quiet_seconds, max_intake_seconds.
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
