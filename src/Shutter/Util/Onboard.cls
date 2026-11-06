/// Onboarding a hospital's namespace (docs/INSTALL.md section 9; CONTRACTS 11.1, v1.42): Plan reads a namespace and lists
/// what is there and exactly what onboarding would do, changing nothing; Apply carries out that list and only that list, so
/// a second run has nothing to do; Credential stores the forwarder's sign-in; Test sends one marked failure through the
/// namespace's forwarder settings; Remove takes off what Apply added; Watched is the Doctor's view. Nothing here stops a
/// production: a running one is updated (Ens.Director.UpdateProduction), a stopped one is left for the site to start. What
/// Apply did is kept in ^Shutter.Config("onboard", namespace, ...), which is what Remove undoes.
/// Read and the two methods that switch into the namespace call only Ens, %SQL, %Dictionary and %SYS classes while they
/// are there: before the mapping, no Shutter class resolves in that namespace, and this one's other methods are among them.
Class Shutter.Util.Onboard
{

/// The packages a watched namespace needs: the forwarder and the alert intake, and the helpers they call.
Parameter PACKAGES = "Shutter.Intake,Shutter.Util";

Parameter CREDENTIAL = "ShutterIntake";

Parameter FORWARDER = "Shutter Forwarder";

Parameter ALERTITEM = "Ens.Alert";

Parameter SITEALERTS = "Site Alerts";

Parameter TESTREASON = "onboarding_test";

Parameter TESTRECEIVER = "Onboarding test";

/// The options a caller passes, as an object: a JSON string, or empty. Anything else sets refused to the whole answer to
/// give, so a slip in the options never runs on the defaults.
ClassMethod Options(json As %String = "", Output refused As %String) As %DynamicObject
{
    Set refused = ""
    If (json = "") || (json = $CHAR(0)) Quit {}
    Try { Set o = ##class(%DynamicObject).%FromJSON(json) } Catch ex { Set o = "" }
    If $ISOBJECT(o) && o.%IsA("%DynamicObject") Quit o
    Set refused = {"ok": false, "error": "The options are not a JSON object, so nothing was read or changed. Check for curly or single quotes and a missing brace"}.%ToJSON()
    Quit {}
}

/// A namespace's name as Shutter keeps it, or "" when an SQL caller passed nothing.
ClassMethod NS(ns As %String) As %String
{
    Quit $ZCONVERT($ZSTRIP($TRANSLATE($GET(ns), $CHAR(0)), "<>W"), "U")
}

/// What a namespace holds, read there: {exists, interoperability, productions, production, state, items, categories,
/// classes, credentials, forwarder, alert, last_forward, error}. A namespace that cannot be read gives error, not an exception.
ClassMethod Read(ns As %String, production As %String = "", credential As %String = "") As %DynamicObject
{
    Set out = {"namespace": (ns), "productions": [], "production": "", "state": "", "items": [], "categories": {}, "classes": {}, "error": ""}
    Do out.%Set("exists", 0, "boolean"), out.%Set("interoperability", 0, "boolean")
    If credential = "" Set credential = ..#CREDENTIAL
    Set out."credential_name" = credential, out."credential_user" = ""
    Do out.%Set("credential", 0, "boolean"), out.%Set("forwarder", "", "null"), out.%Set("alert", "", "null"), out.%Set("last_forward", "", "null")
    If ns = "" Set out.error = "No namespace was named" Quit out
    If '##class(%SYS.Namespace).Exists(ns) Set out.error = "No namespace " _ ns _ " on this instance" Quit out
    Do out.%Set("exists", 1, "boolean")
    New $NAMESPACE
    Try {
        Set $NAMESPACE = ns
        If '##class(%EnsembleMgr).IsEnsembleNamespace(ns) Set out.error = "Interoperability is not enabled in " _ ns Quit
        Do out.%Set("interoperability", 1, "boolean")
        Set sc = ##class(Ens.Director).GetProductionStatus(.running, .state)
        Set out.state = $CASE($GET(state), 1: "running", 2: "stopped", 3: "suspended", 4: "troubled", 5: "network stopped", : "none")
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT Name FROM Ens_Config.Production ORDER BY Name")
        Set count = 0, only = ""
        While rs.%Next() { Do out.productions.%Push(rs.%Get("Name")) Set count = count + 1, only = rs.%Get("Name") }
        Set chosen = $SELECT(production '= "": production, ($GET(state) = 1) || ($GET(state) = 3) || ($GET(state) = 4): $GET(running), count = 1: only, 1: "")
        If chosen = "" Set out.error = $SELECT(count = 0: "No production in " _ ns, 1: "Several productions in " _ ns _ " and none running: name one (\""production\"": \""...\"")") Quit
        Set out.production = chosen
        // The running production may not be the one asked for: that one is then only a definition.
        If $GET(running) '= chosen Set out.state = "stopped"
        Set prod = ##class(Ens.Config.Production).%OpenId(chosen, 0)
        If '$ISOBJECT(prod) Set out.error = "No production " _ chosen _ " in " _ ns Quit
        For i = 1:1:prod.Items.Count() {
            Set item = prod.Items.GetAt(i)
            Kill s
            For j = 1:1:item.Settings.Count() { Set one = item.Settings.GetAt(j), s(one.Name) = one.Value }
            Set cls = item.ClassName, exists = ##class(%Dictionary.CompiledClass).%ExistsId(cls), kind = "other"
            If exists {
                Set kind = $SELECT($CLASSMETHOD(cls, "%Extends", "EnsLib.HL7.Service.Standard"): "hl7_service", $CLASSMETHOD(cls, "%Extends", "EnsLib.HL7.MsgRouter.RoutingEngine"): "router", $CLASSMETHOD(cls, "%Extends", "EnsLib.HL7.Operation.Standard"): "hl7_operation", $CLASSMETHOD(cls, "%Extends", "Ens.BusinessOperation"): "operation", $CLASSMETHOD(cls, "%Extends", "Ens.BusinessProcess"): "process", 1: "other")
            }
            Set r = {"name": (item.Name), "class": (cls), "kind": (kind)}
            Do r.%Set("enabled", ''item.Enabled, "boolean"), r.%Set("class_found", ''exists, "boolean")
            // A category setting can be "2.5.1", "+Local" or "2.5.1,ADT_A01=Local:ADT_A01": every category it names.
            Set value = $GET(s("MessageSchemaCategory")), cats = []
            If value = "" {
                Set dsc = ##class(Ens.Config.DefaultSettings).%GetSetting(chosen, item.Name, cls, "Host", "MessageSchemaCategory", .value)
                If 'dsc Set value = ""
            }
            For k = 1:1:$LENGTH(value, ",") {
                Set part = $PIECE(value, ",", k), part = $PIECE(part, "=", $LENGTH(part, "=")), part = $PIECE($ZSTRIP(part, "<>W", "+-"), ":", 1)
                Set part = $ZSTRIP(part, "<>W")
                If $EXTRACT(part) = "+" Set part = $EXTRACT(part, 2, *)
                If part '= "" Do cats.%Push(part)
            }
            Set r.categories = cats
            Set alertOn = $GET(s("AlertOnError"))
            If alertOn = "" {
                Set dsc = ##class(Ens.Config.DefaultSettings).%GetSetting(chosen, item.Name, cls, "Host", "AlertOnError", .alertOn)
                If 'dsc Set alertOn = ""
            }
            Do r.%Set("alert_on_error", ''alertOn, "boolean")
            // The value that applies: the item's own, else the default settings, else the class's.
            Set timeout = $GET(s("FailureTimeout"))
            If timeout = "" {
                Set dsc = ##class(Ens.Config.DefaultSettings).%GetSetting(chosen, item.Name, cls, "Host", "FailureTimeout", .timeout)
                If 'dsc Set timeout = ""
            }
            If (timeout = "") && exists {
                Set compiled = ##class(%Dictionary.CompiledProperty).%OpenId(cls _ "||FailureTimeout", 0)
                If $ISOBJECT(compiled) Set timeout = $TRANSLATE(compiled.InitialExpression, $CHAR(34))
            }
            Set r."failure_timeout" = timeout
            // An HL7 operation's acknowledgement settings, the value that applies, by the same order; an empty ReplyCodeActions is the engine's default.
            If kind = "hl7_operation" {
                Set actions = $GET(s("ReplyCodeActions")), from = "item"
                If actions = "" {
                    Set from = "default_settings"
                    Set dsc = ##class(Ens.Config.DefaultSettings).%GetSetting(chosen, item.Name, cls, "Host", "ReplyCodeActions", .actions)
                    If 'dsc Set actions = "", from = "class"
                }
                If actions = "" {
                    Set from = "class"
                    Set compiled = ##class(%Dictionary.CompiledProperty).%OpenId(cls _ "||ReplyCodeActions", 0)
                    If $ISOBJECT(compiled) Set actions = $TRANSLATE(compiled.InitialExpression, $CHAR(34))
                }
                Set r."reply_code_actions" = actions, r."reply_code_actions_from" = from
                Set adapter = $PARAMETER(cls, "ADAPTER")
                Do r.%Set("get_reply", "", "null")
                If (adapter '= "") && ##class(%Dictionary.CompiledProperty).%ExistsId(adapter _ "||GetReply") {
                    Set reply = $GET(s("GetReply"))
                    If reply = "" {
                        Set dsc = ##class(Ens.Config.DefaultSettings).%GetSetting(chosen, item.Name, cls, "Adapter", "GetReply", .reply)
                        If 'dsc Set reply = ""
                    }
                    If reply = "" Set reply = $TRANSLATE(##class(%Dictionary.CompiledProperty).%OpenId(adapter _ "||GetReply", 0).InitialExpression, $CHAR(34))
                    Do r.%Set("get_reply", ''reply, "boolean")
                }
            }
            If cls = "Shutter.Intake.Forwarder" {
                Set f = {"item": (item.Name), "server": ($GET(s("HTTPServer"))), "port": ($GET(s("HTTPPort"))), "ssl": ($GET(s("SSLConfig"))), "credential": ($GET(s("Credentials"))), "path": ($GET(s("IntakePath"), "/api/shutter/intake")), "prefix": ($GET(s("ReceiverPrefix")))}
                Do f.%Set("enabled", ''item.Enabled, "boolean")
                Set out.forwarder = f
            }
            If item.Name = "Ens.Alert" {
                Set a = {"item": (item.Name), "class": (cls), "pass_to": ($GET(s("PassTo"))), "receivers": ($GET(s("Receivers"))), "forwarder_target": ($GET(s("ForwarderTarget"), "Shutter Forwarder"))}
                Do a.%Set("is_shutter", cls = "Shutter.Intake.AlertProcess", "boolean")
                Set out.alert = a
                Set out."alert_items" = out.%Get("alert_items") + 1
            }
            Do out.items.%Push(r)
        }
        // What each service's category is here: loaded, standard, on what base.
        Set rs = ##class(%ResultSet).%New("EnsLib.HL7.Schema:TypeCategories")
        If rs.Execute() {
            While rs.Next() {
                Set c = {"base": (rs.Get("Base"))}
                Do c.%Set("standard", ''rs.Get("IsStandard"), "boolean")
                Do out.categories.%Set(rs.Get("Category"), c)
            }
        }
        For cls = "Shutter.Intake.Forwarder", "Shutter.Intake.AlertProcess", "Shutter.Intake.Forward", "Shutter.Util.Json", "Shutter.Util.Time", "Shutter.Util.Schemas" {
            Do out.classes.%Set(cls, ##class(%Dictionary.CompiledClass).%ExistsId(cls), "boolean")
        }
        Set cred = ##class(Ens.Config.Credentials).%OpenId(credential, 0)
        If $ISOBJECT(cred) { Do out.%Set("credential", 1, "boolean") Set out."credential_user" = cred.Username }
        // The last forward and how it ended, through the header table's own indexes.
        If $ISOBJECT(out.forwarder) {
            Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP 1 ID, TimeCreated FROM Ens.MessageHeader WHERE TargetConfigName = ? ORDER BY ID DESC", out.forwarder.item)
            If rs.%Next() {
                Set last = {"at": (rs.%Get("TimeCreated")), "header": (rs.%Get("ID")), "error": ""}
                Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP 1 MessageBodyId FROM Ens.MessageHeader WHERE SourceConfigName = ? AND MessageBodyClassName = 'Shutter.Intake.Forwarded' ORDER BY ID DESC", out.forwarder.item)
                If rs.%Next() && ##class(%Dictionary.CompiledClass).%ExistsId("Shutter.Intake.Forwarded") {
                    Set reply = $CLASSMETHOD("Shutter.Intake.Forwarded", "%OpenId", rs.%Get("MessageBodyId"))
                    If $ISOBJECT(reply) Set last.error = reply.Error, last."case" = reply.CaseId
                }
                Set out."last_forward" = last
            }
            // Refused forwards over three days, since the last forward alone is overwritten by the next good one.
            Try {
                Set since = $ZDATETIME($ZTIMESTAMP - 3, 3, 1)
                Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT COUNT(*) AS N, MAX(h.TimeCreated) AS T FROM Ens.MessageHeader h, Shutter_Intake.Forwarded f WHERE h.SourceConfigName = ? AND h.MessageBodyClassName = 'Shutter.Intake.Forwarded' AND f.ID = h.MessageBodyId AND f.Error IS NOT NULL AND f.Error <> '' AND h.TimeCreated >= ?", out.forwarder.item, since)
                If rs.%Next() Set out."refused_72h" = +rs.%Get("N"), out."last_refused" = rs.%Get("T")
            } Catch ex2 {
            }
        }
        // Default settings keyed to the name Ens.Alert stay with that name when the site's own item is renamed.
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT COUNT(*) AS N FROM Ens_Config.DefaultSettings WHERE ItemName = 'Ens.Alert' AND ProductionName IN (?, '*')", chosen)
        If rs.%Next() Set out."alert_default_settings" = +rs.%Get("N")
    } Catch ex {
        Set out.error = "Could not read " _ ns _ ": " _ ex.DisplayString()
    }
    Quit out
}

/// The packages already mapped into a namespace, {package: database}; {} with a caller that may not read %SYS.
ClassMethod Mappings(ns As %String, Output readable As %Boolean) As %DynamicObject
{
    Set out = {}, packages = ..#PACKAGES, readable = 1
    New $NAMESPACE
    Try {
        Set $NAMESPACE = "%SYS"
        For i = 1:1:$LENGTH(packages, ",") {
            Set pkg = $PIECE(packages, ",", i)
            If ##class(Config.MapPackages).Exists(ns, pkg, .obj) Do out.%Set(pkg, obj.Database)
        }
    } Catch ex {
        Set readable = 0
    }
    Quit out
}

/// The database holding this namespace's code, which the mappings point at.
ClassMethod CodeDatabase(ns As %String) As %String
{
    Set db = ""
    New $NAMESPACE
    Try {
        Set $NAMESPACE = "%SYS"
        If ##class(Config.Namespaces).Get(ns, .p) = 1 Set db = $GET(p("Routines"))
    } Catch ex {
    }
    Quit db
}

/// The port this instance's web server answers on, for the forwarder's default: 52773 when it cannot be read.
ClassMethod WebPort() As %Integer
{
    Set port = ""
    New $NAMESPACE
    Try {
        Set $NAMESPACE = "%SYS"
        If ##class(Config.Startup).Get(.p) = 1 Set port = $GET(p("WebServerPort"))
    } Catch ex {
    }
    Quit $SELECT(+port > 0: +port, 1: 52773)
}

/// The namespaces onboarded here, as a list.
ClassMethod Onboarded() As %List
{
    Set out = "", ns = ""
    For { Set ns = $ORDER(^Shutter.Config("onboard", ns)) Quit:ns=""  Set out = out _ $LISTBUILD(ns) }
    Quit out
}

/// The receiver name a namespace's operation is reported under: the item's own, or with the namespace in front when the
/// name is taken. Two namespaces' items of one name are two systems: one name would pool their cases and their incidents,
/// and give both one profile entry.
ClassMethod TakenElsewhere(ns As %String, item As %String) As %Boolean
{
    Set other = ""
    For {
        Set other = $ORDER(^Shutter.Config("onboard", other)) Quit:other=""
        Continue:other=ns
        If $DATA(^Shutter.Config("onboard", other, "receivers", item)) Quit
    }
    If other '= "" Quit 1
    If ..WrittenByHand(item) Quit 1
    Set entry = ##class(Shutter.Store.SiteProfile).Receiver(item)
    If '$ISOBJECT(entry) Quit 0
    Set from = ##class(Shutter.Util.Json).Str(entry, "namespace")
    Quit (from '= "") && (from '= ns)
}

/// Whether a person wrote this name into the profile with an API and said for no namespace. Shutter can write to it, and
/// nothing says it is this namespace's system, so an item of that name stays apart until the entry names the namespace.
ClassMethod WrittenByHand(item As %String) As %Boolean
{
    Set entry = ##class(Shutter.Store.SiteProfile).Receiver(item)
    Quit $ISOBJECT(entry) && $ISOBJECT(entry.%Get("api")) && (##class(Shutter.Util.Json).Str(entry, "namespace") = "")
}

/// Whether another namespace onboarded here already reports a receiver under this very name.
ClassMethod ReportedElsewhere(ns As %String, reported As %String) As %Boolean
{
    Set other = "", found = 0
    For {
        Set other = $ORDER(^Shutter.Config("onboard", other)) Quit:other=""
        Continue:other=ns
        Set item = ""
        For { Set item = $ORDER(^Shutter.Config("onboard", other, "receivers", item), 1, name) Quit:item=""  If name = reported Set found = 1 Quit }
        Quit:found
    }
    Quit found
}

/// One plain line on what a completed message proves at an HL7 operation, from the settings that apply (measured on a stock TCP
/// operation; docs/INSTALL.md 9.9): getReply is 1, 0, or "" when the adapter has no such setting.
ClassMethod CompletedProves(getReply As %String, actions As %String) As %String
{
    If getReply = "" Quit "Not on the TCP adapter, so GetReply does not apply, and Shutter has measured nothing here: send a test message and see what comes back before relying on a completed message"
    If 'getReply Quit "Nothing is awaited: a completed message proves only that it was written to the connection. ReplyCodeActions is never read, so even a NACK reads as complete"
    Set sweep = "Shutter.Review.Sweep"
    Set aa = $CLASSMETHOD(sweep, "ReplyAction", actions, "AA"), ca = $CLASSMETHOD(sweep, "ReplyAction", actions, "CA")
    Set bad = ""
    For code = "AE", "AR", "CE", "CR" {
        Set action = $CLASSMETHOD(sweep, "ReplyAction", actions, code)
        If $CLASSMETHOD(sweep, "IsLenient", action) Set bad = bad _ $SELECT(bad = "": "", 1: ", ") _ code _ "=" _ action
    }
    If bad '= "" Quit "A reply is awaited, but a negative code also counts as complete here (" _ bad _ "): a completed message does not prove the receiver accepted it"
    Set aaOk = $CLASSMETHOD(sweep, "IsLenient", aa), caOk = $CLASSMETHOD(sweep, "IsLenient", ca)
    If aaOk && caOk Quit "A reply is awaited, and any positive code counts as complete, so an accept or commit ACK reads the same as an application ACK: a completed message proves the receiver's listener answered, not that its application processed the message"
    If aaOk Quit "A reply is awaited, and only AA completes (CA=" _ ca _ "): a completed message proves the receiver answered AA, which is an application ACK only if its engine does not answer AA on receipt, so ask"
    Quit "A reply is awaited, and neither AA nor CA completes here (AA=" _ aa _ ", CA=" _ ca _ "): read these settings before relying on them"
}

/// The plan for a namespace, changing nothing: what is there, what is wired already, and in actions exactly what Apply
/// would do, one entry each; todo is what only a person can do. Options: production, shutter_host, shutter_port, ssl_config,
/// credential, receivers (a comma-separated list in place of the namespace's HL7 operations), alert_on_error (true: turn
/// AlertOnError on for the receivers that lack it).
ClassMethod Plan(ns As %String, options As %DynamicObject = "") As %DynamicObject
{
    Set ns = ..NS(ns)
    If '$ISOBJECT(options) Set options = {}
    Set json = "Shutter.Util.Json", schemas = "Shutter.Util.Schemas"
    Set credential = $CLASSMETHOD(json, "Str", options, "credential", ..#CREDENTIAL)
    Set read = ..Read(ns, $CLASSMETHOD(json, "Str", options, "production"), credential)
    Set plan = {"namespace": (ns), "shutter_namespace": ($NAMESPACE), "production": (read.production), "production_state": (read.state), "productions": (read.productions), "services": [], "routers": [], "operations": [], "other_operations": [], "schemas": [], "wired": {}, "actions": [], "todo": [], "warnings": [], "error": (read.error)}
    Do plan.%Set("onboarded", $DATA(^Shutter.Config("onboard", ns)) > 0, "boolean")
    If ns = $NAMESPACE Set plan.error = ns _ " is Shutter's own namespace: it has nothing to onboard"
    Quit:plan.error'="" plan
    // 1. The items, by what they are.
    Set forwarder = read.forwarder, alert = read.alert, wanted = $CLASSMETHOD(json, "Str", options, "receivers")
    Set categories = "", it = read.items.%GetIterator(), listed = "", siteAlertsTaken = 0
    While it.%GetNext(, .item) {
        If item.name = ..#SITEALERTS Set siteAlertsTaken = 1
        If (item.kind = "hl7_service") {
            Do plan.services.%Push({"name": (item.name), "class": (item.class), "categories": (item.categories)})
            Set ci = item.categories.%GetIterator()
            While ci.%GetNext(, .cat) { If '$LISTFIND(categories, cat) Set categories = categories _ $LISTBUILD(cat), used(cat) = item.name }
        } ElseIf item.kind = "router" {
            Do plan.routers.%Push({"name": (item.name), "class": (item.class)})
        } ElseIf (item.class = "Shutter.Intake.Forwarder") || (item.class = "Shutter.Intake.AlertProcess") || (item.name = "Ens.Alert") {
            // Wired below.
        } ElseIf $SELECT(wanted '= "": $LISTFIND($LISTFROMSTRING($ZSTRIP(wanted, "*W")), $ZSTRIP(item.name, "*W")) > 0, 1: item.kind = "hl7_operation") {
            Set listed = listed _ $LISTBUILD(item.name), op(item.name) = item
        } ElseIf (item.kind = "operation") || (item.kind = "hl7_operation") {
            Do plan."other_operations".%Push({"name": (item.name), "class": (item.class)})
        }
    }
    // A name in the option that matches no item is said, not dropped in silence.
    For i = 1:1:$LENGTH(wanted, ",") {
        Set one = $ZSTRIP($PIECE(wanted, ",", i), "<>W")
        If (one '= "") && '$LISTFIND($LISTFROMSTRING($ZSTRIP($LISTTOSTRING(listed, ","), "*W")), $ZSTRIP(one, "*W")) Do plan.warnings.%Push("The option receivers names " _ one _ ", and no item in " _ read.production _ " can be chosen by that name: it is left out. Check the spelling")
    }
    // 2. The names they will be reported under. A namespace wired already keeps the names it has, none included: its teams,
    // its profile entries and its open cases use them, and another namespace coming on later must not rename them.
    Set prefix = $SELECT($ISOBJECT(forwarder): forwarder.prefix, 1: "")
    If '$ISOBJECT(forwarder) {
        For i = 1:1:$LISTLENGTH(listed) {
            Set one = $LIST(listed, i)
            If ..TakenElsewhere(ns, one) && (prefix = "") Set prefix = ns
            If ..WrittenByHand(one) Do plan.warnings.%Push("The site profile's " _ one _ " has an API and names no namespace, so it may be another system: this namespace's " _ one _ " is reported as " _ ##class(Shutter.Intake.Forwarder).ReportedReceiver(one, ns) _ ", a draft that nothing is written to. If they are one system, add ""namespace"": """ _ ns _ """ to that entry before the apply: once applied, the name stays until the namespace is taken off")
        }
    }
    Set plan."receiver_prefix" = prefix
    Set noAlert = ""
    For i = 1:1:$LISTLENGTH(listed) {
        Set name = $LIST(listed, i), item = op(name), reported = ##class(Shutter.Intake.Forwarder).ReportedReceiver(name, prefix)
        Set entry = ##class(Shutter.Store.SiteProfile).Receiver(reported)
        Set o = {"name": (name), "class": (item.class), "reported_as": (reported)}
        Do o.%Set("alert_on_error", item."alert_on_error", "boolean"), o.%Set("in_profile", $ISOBJECT(entry), "boolean")
        If $ISOBJECT(entry) {
            Do o.%Set("has_api", $ISOBJECT(entry.%Get("api")), "boolean")
            Do o.%Set("draft", ##class(Shutter.Util.Json).Bool(entry, "draft", 0), "boolean")
        }
        If item.kind = "hl7_operation" {
            Do o.%Set("get_reply", item."get_reply", $SELECT(item."get_reply" = "": "null", 1: "boolean"))
            Set actions = item."reply_code_actions", o."reply_code_actions_from" = item."reply_code_actions_from"
            If actions = "" Set actions = ##class(Shutter.Review.Checks).#DOCUMENTEDREPLYCODEACTIONS, o."reply_code_actions_from" = "engine_default"
            Set o."reply_code_actions" = actions
            Set o.proves = ..CompletedProves(item."get_reply", actions)
        } Else {
            Do o.%Set("get_reply", "", "null")
            Set o."reply_code_actions" = "", o."reply_code_actions_from" = ""
            Set o.proves = "A connector of the site's own: what completes here is its code's choice, so read it"
        }
        Do plan.operations.%Push(o)
        If $ISOBJECT(forwarder) && ..WrittenByHand(reported) && $DATA(^Shutter.Config("onboard", ns, "items", forwarder.item)) && '$DATA(^Shutter.Config("onboard", ns, "receivers", name)) Do plan.warnings.%Push("The site profile's " _ reported _ " has an API and names no namespace, and this namespace's " _ name _ " would report under that name, so its failures could be written there. Take the namespace off and apply it again to give it a prefix, or add ""namespace"": """ _ ns _ """ to that entry if they are one system")
        If $ISOBJECT(forwarder) && ..ReportedElsewhere(ns, reported) Do plan.warnings.%Push(name _ " is reported under the name another namespace's receiver has, so their cases and their profile entry would be pooled. Rename the item in one of them")
        If 'item."alert_on_error" Set noAlert = noAlert _ $LISTBUILD(name)
        If item."failure_timeout" = "-1" Do plan.warnings.%Push(name _ " retries forever (FailureTimeout -1, whether set on the item or the class's default): a case opens on its first failure, even a short outage, and stays open, and the engine goes on and delivers when the system returns. Check the message trace before anyone corrects by hand")
    }
    // 3. What is wired already.
    Set mapped = ..Mappings(ns), classes = read.classes
    Set wired = plan.wired
    Set wired.mappings = mapped, wired.classes = classes
    Do wired.%Set("forwarder", forwarder, $SELECT($ISOBJECT(forwarder): "", 1: "null")), wired.%Set("alert", alert, $SELECT($ISOBJECT(alert): "", 1: "null")), wired.%Set("last_forward", read."last_forward", $SELECT($ISOBJECT(read."last_forward"): "", 1: "null"))
    Do wired.%Set("credential", read.credential, "boolean")
    Set wired."credential_name" = read."credential_name", wired."credential_user" = read."credential_user"
    // 4. The actions, in the order Apply runs them.
    Set actions = plan.actions
    // The classes: what is reachable already (a mapping, or the files loaded by hand) needs nothing.
    Set reach = classes.%Get("Shutter.Intake.Forwarder") && classes.%Get("Shutter.Intake.AlertProcess") && classes.%Get("Shutter.Util.Json") && classes.%Get("Shutter.Util.Time")
    Set db = ..CodeDatabase($NAMESPACE)
    If 'reach {
        Set packages = ..#PACKAGES
        For i = 1:1:$LENGTH(packages, ",") {
            Set pkg = $PIECE(packages, ",", i)
            If mapped.%Get(pkg) = "" Do actions.%Push({"do": "map_package", "package": (pkg), "database": (db), "says": ("Map the package " _ pkg _ " into " _ ns _ " from the database " _ db)})
        }
    }
    // The schemas: each non-standard category the services name goes into Shutter's namespace, under its own name unless
    // that name holds something else.
    For i = 1:1:$LISTLENGTH(categories) {
        Set cat = $LIST(categories, i), here = read.categories.%Get(cat)
        Set s = {"category": (cat), "named_by": (used(cat))}
        Do s.%Set("in_namespace", $ISOBJECT(here), "boolean")
        Set standard = $ISOBJECT(here) && here.standard
        Do s.%Set("standard", standard, "boolean")
        Set alias = $CLASSMETHOD(schemas, "Alias", ns, cat)
        Do s.%Set("in_shutter", $CLASSMETHOD(schemas, "Known", $SELECT(alias '= "": alias, 1: cat)), "boolean")
        Set s."shutter_name" = $SELECT(alias '= "": alias, 1: cat)
        If '$ISOBJECT(here) {
            Do plan.warnings.%Push("The category " _ cat _ ", named by " _ used(cat) _ ", is not loaded in " _ ns _ " itself, so its messages are read by position there: import it in that namespace first")
        } ElseIf 'standard {
            Set how = $CLASSMETHOD(schemas, "ImportNeeded", ns, cat, .as)
            Set s.action = how
            If how = "import" {
                Do actions.%Push({"do": "import_schema", "category": (cat), "as": (cat), "says": ("Import the schema " _ cat _ " from " _ ns _ " into " _ $NAMESPACE)})
            } ElseIf how = "import_as" {
                Do actions.%Push({"do": "import_schema", "category": (cat), "as": (as), "says": ("Import the schema " _ cat _ " from " _ ns _ " into " _ $NAMESPACE _ " as " _ as _ ": a category of that name is loaded there with other contents, and importing over it would replace it")})
                Set s."shutter_name" = as
            }
        }
        Do plan.schemas.%Push(s)
    }
    Set forwarderName = $SELECT($ISOBJECT(forwarder): forwarder.item, 1: ..#FORWARDER)
    If '$ISOBJECT(forwarder) && (listed = "") && (wanted '= "") {
        // A forwarder fixes the names its receivers report under, so it waits until the option has chosen them.
        Do plan.warnings.%Push("The option receivers chose no item in " _ read.production _ ", so this plan adds no forwarder. Correct the option and plan again")
    } ElseIf '$ISOBJECT(forwarder) {
        Set host = $CLASSMETHOD(json, "Str", options, "shutter_host", "127.0.0.1"), port = $CLASSMETHOD(json, "Str", options, "shutter_port", ..WebPort())
        Set ssl = $CLASSMETHOD(json, "Str", options, "ssl_config")
        If (ssl = "") && '$LISTFIND($LISTBUILD("127.0.0.1", "localhost", "::1"), $ZCONVERT(host, "L")) Do plan.warnings.%Push("With no ssl_config the forwarder sends its sign-in to " _ host _ " in clear: name an SSL configuration")
        Do actions.%Push({"do": "add_forwarder", "item": (forwarderName), "server": (host), "port": (port), "ssl": (ssl), "credential": (credential), "prefix": (prefix), "says": ("Add the item " _ forwarderName _ " (Shutter.Intake.Forwarder) to " _ read.production _ ", posting to " _ host _ ":" _ port _ " with the credential " _ credential _ $SELECT(prefix '= "": ", reporting its receivers as """ _ prefix _ " <item>""", 1: ""))})
    }
    // The alert intake, with the site's own consumer kept as PassTo.
    Set receivers = $LISTTOSTRING(listed, ",")
    If +read.%Get("alert_items") > 1 {
        Do plan.warnings.%Push("Two items are named Ens.Alert in " _ read.production _ ": the engine uses one and ignores the other. Rename one before onboarding: this plan adds no alert intake")
    } ElseIf (listed = "") && ('$ISOBJECT(alert) || 'alert."is_shutter") {
        // An empty Receivers means every item, which nobody here chose.
        Do plan.warnings.%Push("No item in " _ read.production _ " was chosen as a receiver, and an alert intake with an empty list would take every item's alerts: this plan adds none. Name the connectors in the option receivers")
    } ElseIf siteAlertsTaken && $ISOBJECT(alert) && 'alert."is_shutter" {
        Do plan.warnings.%Push("An item is named " _ ..#SITEALERTS _ " in " _ read.production _ ", the name the site's Ens.Alert would take: rename it before onboarding. This plan adds no alert intake")
    } ElseIf '$ISOBJECT(alert) {
        Do actions.%Push({"do": "add_alert_intake", "receivers": (receivers), "pass_to": "", "target": (forwarderName), "says": ("Add the item Ens.Alert (Shutter.Intake.AlertProcess) with the receivers " _ receivers)})
    } ElseIf 'alert."is_shutter" {
        If +read.%Get("alert_default_settings") > 0 Do plan.warnings.%Push("System default settings are keyed to the item name Ens.Alert: they will reach Shutter's item and not the site's renamed one, so move them to " _ ..#SITEALERTS)
        Do actions.%Push({"do": "rename_alert", "class": (alert.class), "to": (..#SITEALERTS), "says": ("Rename the site's own Ens.Alert (" _ alert.class _ ") to " _ ..#SITEALERTS _ ", where every alert is still passed first")})
        Do actions.%Push({"do": "add_alert_intake", "receivers": (receivers), "pass_to": (..#SITEALERTS), "target": (forwarderName), "says": ("Add the item Ens.Alert (Shutter.Intake.AlertProcess), passing every alert to " _ ..#SITEALERTS _ ", with the receivers " _ receivers)})
    } Else {
        // A receiver added since: the list grows, it never shrinks.
        Set have = alert.receivers, more = ""
        For i = 1:1:$LISTLENGTH(listed) { If '$LISTFIND($LISTFROMSTRING($ZSTRIP(have, "*W")), $ZSTRIP($LIST(listed, i), "*W")) Set more = more _ $LISTBUILD($LIST(listed, i)) }
        If (have '= "") && (more '= "") {
            Set grown = have _ "," _ $LISTTOSTRING(more, ",")
            Do actions.%Push({"do": "set_alert_receivers", "receivers": (grown), "says": ("Add " _ $LISTTOSTRING(more, ", ") _ " to the alert intake's Receivers")})
        }
    }
    // AlertOnError: the alert intake hears only what raises an alert. Changing a site's item is its choice.
    If noAlert '= "" {
        If $CLASSMETHOD(json, "Bool", options, "alert_on_error", 0) {
            For i = 1:1:$LISTLENGTH(noAlert) Do actions.%Push({"do": "set_alert_on_error", "item": ($LIST(noAlert, i)), "says": ("Turn AlertOnError on for " _ $LIST(noAlert, i) _ "; that item restarts when the production is updated")})
        } Else {
            Do plan.todo.%Push("These receivers raise no alert on an error, so the alert intake hears nothing from them: " _ $LISTTOSTRING(noAlert, ", ") _ ". Turn AlertOnError on in the Management Portal, or pass {""alert_on_error"": true} to the apply")
        }
    }
    // The profile's drafts: no API and every feature false, so nothing can be resent.
    For i = 1:1:plan.operations.%Size() {
        Set o = plan.operations.%Get(i - 1)
        If 'o."in_profile" Do actions.%Push({"do": "draft_receiver", "name": (o."reported_as"), "item": (o.name), "says": ("Draft a site profile entry for " _ o."reported_as" _ ": tier 3, no API, every feature false, so its failures escalate and nothing is resent until a person fills it in")})
    }
    If 'read.credential Do plan.todo.%Push("No credential " _ credential _ " in " _ ns _ ": run Do ##class(Shutter.Setup).OnboardCredential(""" _ ns _ """) in a terminal, as a user who may manage security; it asks for the password and never prints it")
    For i = 1:1:plan.operations.%Size() {
        Set o = plan.operations.%Get(i - 1)
        If 'o."in_profile" || (o."in_profile" && ##class(Shutter.Util.Json).Bool(##class(Shutter.Store.SiteProfile).Receiver(o."reported_as"), "draft", 0)) {
            Do plan.todo.%Push("Review the draft receiver " _ o."reported_as" _ " in the site profile: its system, its category, its tier and its team; give it an API only if it has one")
        }
    }
    If (read.state = "stopped") Do plan.warnings.%Push("The production " _ read.production _ " is stopped: the definition changes, and the items start when the site starts it")
    Quit plan
}

/// Carries out a namespace's plan, action by action, and answers what changed and what a person still has to do. Run again,
/// it has nothing to do. Needs a user who may change the instance's configuration (%Admin_Manage).
ClassMethod Apply(ns As %String, options As %DynamicObject = "") As %DynamicObject
{
    Set ns = ..NS(ns)
    If '$ISOBJECT(options) Set options = {}
    Set out = {"namespace": (ns), "changed": [], "unchanged": "", "todo": [], "warnings": [], "error": ""}
    Do out.%Set("ok", 0, "boolean")
    If '$SYSTEM.Security.Check("%Admin_Manage", "USE") Set out.error = "Onboarding changes the instance's configuration: it needs a user holding %Admin_Manage" Quit out
    Set plan = ..Plan(ns, options)
    Set out.production = plan.production, out.todo = plan.todo, out.warnings = plan.warnings
    If plan.error '= "" Set out.error = plan.error Quit out
    Try {
        Set sc = $$$OK, productionActions = []
        Set ai = plan.actions.%GetIterator()
        While ai.%GetNext(, .a) {
            If a.do = "map_package" {
                Set sc = ..MapPackage(ns, a.package, a.database)
                Quit:$$$ISERR(sc)
                Set ^Shutter.Config("onboard", ns, "mappings", a.package) = a.database
                Do out.changed.%Push(a.says)
            } ElseIf a.do = "import_schema" {
                Set sc = ##class(Shutter.Util.Schemas).ImportFrom(ns, a.category, a.as)
                Quit:$$$ISERR(sc)
                Set ^Shutter.Config("onboard", ns, "schemas", a.category) = a.as
                Do out.changed.%Push(a.says)
            } ElseIf a.do '= "draft_receiver" {
                Do productionActions.%Push(a)
            }
        }
        If $$$ISERR(sc) Set out.error = $SYSTEM.Status.GetErrorText(sc) Quit
        If productionActions.%Size() > 0 {
            Set sc = ..EditProduction(ns, plan.production, productionActions, .done, .saved)
            // A definition saved and a production that did not take it (an item slow to stop) is still ours to take off.
            If $$$ISERR(sc) && 'saved Set out.error = $SYSTEM.Status.GetErrorText(sc) Quit
            If $$$ISERR(sc) {
                Set out.error = "The definition of " _ plan.production _ " is saved, but the running production did not take it: " _ $SYSTEM.Status.GetErrorText(sc) _ ". Update it in the Management Portal (Production Configuration, Update)"
                Set done = 0
            }
            Set di = productionActions.%GetIterator()
            While di.%GetNext(, .a) {
                Do out.changed.%Push(a.says)
                If a.do = "add_forwarder" Set ^Shutter.Config("onboard", ns, "items", a.item) = "added"
                If a.do = "add_alert_intake" Set ^Shutter.Config("onboard", ns, "items", ..#ALERTITEM) = "added"
                If a.do = "rename_alert" Set ^Shutter.Config("onboard", ns, "renamed") = a.to
                If a.do = "set_alert_on_error" Set ^Shutter.Config("onboard", ns, "alertOnError", a.item) = 1
            }
            Do out.changed.%Push($SELECT(done: "Updated the running production " _ plan.production _ ": it was not stopped", 1: "The production " _ plan.production _ " has not taken this yet: the site updates or starts it"))
        }
        // The profile, last: one save for all the drafts.
        Set draft = ..DraftReceivers(ns, plan, .count, .psc)
        If $$$ISERR(psc) Set out.error = $SYSTEM.Status.GetErrorText(psc) Quit
        If count > 0 {
            Set di = plan.actions.%GetIterator()
            While di.%GetNext(, .a) { If a.do = "draft_receiver" Do out.changed.%Push(a.says) }
        }
        Set oi = plan.operations.%GetIterator()
        While oi.%GetNext(, .o) { Set ^Shutter.Config("onboard", ns, "receivers", o.name) = o."reported_as" }
        Set ^Shutter.Config("onboard", ns) = plan.production
        Set ^Shutter.Config("onboard", ns, "credential") = ##class(Shutter.Util.Json).Str(options, "credential", ..#CREDENTIAL)
        If '$DATA(^Shutter.Config("onboard", ns, "at")) Set ^Shutter.Config("onboard", ns, "at") = ##class(Shutter.Util.Time).NowUTC()
        Set ^Shutter.Config("onboard", ns, "by") = $USERNAME
        // The Doctor's credential cache names the namespaces it checks.
        Kill ^Shutter.Health("credentials")
        Do out.%Set("ok", out.error = "", "boolean")
        If out.changed.%Size() = 0 Set out.unchanged = "Nothing to do: " _ ns _ " is wired as the plan wants"
    } Catch ex {
        Set out.error = ex.DisplayString()
    }
    Quit out
}

/// One package mapped into a namespace, from this namespace's code database.
ClassMethod MapPackage(ns As %String, package As %String, database As %String) As %Status
{
    Set sc = $$$OK
    New $NAMESPACE
    Try {
        Set $NAMESPACE = "%SYS"
        If ##class(Config.MapPackages).Exists(ns, package) Quit
        Set p("Database") = database
        Set sc = ##class(Config.MapPackages).Create(ns, package, .p)
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// The production edits, as one save: the definition and its class, then the running production takes them. done says
/// whether a running production was updated. It runs in the namespace and calls no Shutter class there.
ClassMethod EditProduction(ns As %String, production As %String, actions As %DynamicArray, Output done As %Boolean, Output saved As %Boolean) As %Status
{
    Set sc = $$$OK, done = 0, saved = 0
    New $NAMESPACE
    Try {
        Set $NAMESPACE = ns
        Set prod = ##class(Ens.Config.Production).%OpenId(production)
        If '$ISOBJECT(prod) Set sc = $$$ERROR($$$GeneralError, "No production " _ production _ " in " _ ns) Quit
        Set ai = actions.%GetIterator()
        While ai.%GetNext(, .a) {
            If a.do = "add_forwarder" {
                Set new = ##class(Ens.Config.Item).%New()
                Set new.Name = a.item, new.ClassName = "Shutter.Intake.Forwarder", new.PoolSize = 1, new.Enabled = 1, new.Production = prod
                Set new.Comment = "Hands a failed delivery to Shutter"
                For set = $LISTBUILD("Adapter", "HTTPServer", a.server), $LISTBUILD("Adapter", "HTTPPort", a.port), $LISTBUILD("Adapter", "Credentials", a.credential), $LISTBUILD("Adapter", "SSLConfig", a.ssl), $LISTBUILD("Adapter", "ResponseTimeout", "15"), $LISTBUILD("Adapter", "ConnectTimeout", "5"), $LISTBUILD("Host", "FailureTimeout", "0"), $LISTBUILD("Host", "ReceiverPrefix", a.prefix) {
                    Continue:($LIST(set, 3) = "")
                    Set s = ##class(Ens.Config.Setting).%New(), s.Target = $LIST(set, 1), s.Name = $LIST(set, 2), s.Value = $LIST(set, 3)
                    Do new.Settings.Insert(s)
                }
                Do prod.Items.Insert(new)
            } ElseIf a.do = "add_alert_intake" {
                Set new = ##class(Ens.Config.Item).%New()
                Set new.Name = "Ens.Alert", new.ClassName = "Shutter.Intake.AlertProcess", new.PoolSize = 1, new.Enabled = 1, new.Production = prod
                Set new.Comment = "Hands the alerted failures of the receivers to Shutter; every alert is passed on first"
                For set = $LISTBUILD("Host", "ForwarderTarget", a.target), $LISTBUILD("Host", "PassTo", a."pass_to"), $LISTBUILD("Host", "Receivers", a.receivers) {
                    Continue:($LIST(set, 3) = "")
                    Set s = ##class(Ens.Config.Setting).%New(), s.Target = $LIST(set, 1), s.Name = $LIST(set, 2), s.Value = $LIST(set, 3)
                    Do new.Settings.Insert(s)
                }
                Do prod.Items.Insert(new)
            } Else {
                // The edits of an item the production has.
                Set name = $CASE(a.do, "rename_alert": "Ens.Alert", "set_alert_receivers": "Ens.Alert", : a.item), found = ""
                For i = 1:1:prod.Items.Count() { If prod.Items.GetAt(i).Name = name Set found = prod.Items.GetAt(i) Quit }
                If '$ISOBJECT(found) Set sc = $$$ERROR($$$GeneralError, "No item " _ name _ " in " _ production) Quit
                If a.do = "rename_alert" {
                    Set found.Name = a.to
                } Else {
                    Set settingName = $CASE(a.do, "set_alert_receivers": "Receivers", "set_alert_on_error": "AlertOnError")
                    Set value = $CASE(a.do, "set_alert_receivers": a.receivers, "set_alert_on_error": "1")
                    Set one = ""
                    For j = 1:1:found.Settings.Count() { If found.Settings.GetAt(j).Name = settingName Set one = found.Settings.GetAt(j) Quit }
                    If '$ISOBJECT(one) { Set one = ##class(Ens.Config.Setting).%New(), one.Target = "Host", one.Name = settingName Do found.Settings.Insert(one) }
                    Set one.Value = value
                }
            }
        }
        Quit:$$$ISERR(sc)
        Set sc = prod.%Save() Quit:$$$ISERR(sc)
        Set sc = prod.SaveToClass() Quit:$$$ISERR(sc)
        Set saved = 1
        Set sc = ##class(Ens.Director).GetProductionStatus(.running, .state) Quit:$$$ISERR(sc)
        If ($GET(running) = production) && ($GET(state) = 1) {
            Set sc = ##class(Ens.Director).UpdateProduction(30, 0)
            Set done = 1
        }
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// The drafts of a plan written to the site profile, in one save under the name "onboarding" (a new version of the profile,
/// as every change is): each entry has no API and every feature false, so the gate blocks any write and its failures
/// escalate, and it says draft until a person saves it without that. An entry that exists is never touched.
ClassMethod DraftReceivers(ns As %String, plan As %DynamicObject, Output count As %Integer, Output sc As %Status) As %Boolean
{
    Set count = 0, sc = $$$OK
    Set profile = ##class(Shutter.Store.SiteProfile).Current()
    Set list = profile.%Get("receivers")
    If '$ISOBJECT(list) Set list = [], profile.receivers = list
    Set ai = plan.actions.%GetIterator()
    While ai.%GetNext(, .a) {
        Continue:a.do'="draft_receiver"
        Continue:$ISOBJECT(##class(Shutter.Store.SiteProfile).Receiver(a.name))
        Set entry = {"name": (a.name), "system": (a.item _ " in " _ ns _ ": draft, a person fills this in"), "tier": 3, "applies": "arrival_order", "resend_timestamp": "original", "cancels": false, "merges": false, "features": {"conditional_writes": false, "receipts": false, "history": false, "dry_run": false}, "draft": true, "namespace": (ns), "item": (a.item)}
        Do list.%Push(entry)
        Set count = count + 1
        Set ^Shutter.Config("onboard", ns, "drafted", a.name) = a.item
    }
    If count = 0 Quit 0
    Set sc = ##class(Shutter.Store.SiteProfile).Store(profile.%ToJSON(), "onboarding", "onboarding " _ ns)
    Quit $$$ISOK(sc)
}

/// The forwarder's sign-in for a namespace: a user holding Shutter_Forwarder (made when it does not exist; one that exists
/// must already sign in with this password and hold the role) and, in that namespace, the credential naming it. Prints
/// nothing; the answer never carries the password. Needs a user who may manage security.
ClassMethod Credential(ns As %String, user As %String = "shutter-fwd", password As %String, credential As %String = "") As %DynamicObject
{
    Set ns = ..NS(ns), out = {"namespace": (ns), "user": (user), "error": ""}
    Do out.%Set("ok", 0, "boolean")
    If credential = "" Set credential = ..#CREDENTIAL
    Set out.credential = credential
    If password = "" Set out.error = "No password given" Quit out
    If '##class(%SYS.Namespace).Exists(ns) Set out.error = "No namespace " _ ns Quit out
    Try {
        Set sc = ..EnsureForwarderUser(user, password, .made)
        If $$$ISERR(sc) Set out.error = $SYSTEM.Status.GetErrorText(sc) Quit
        If 'made && '##class(Shutter.Setup).TryLogin(user, password, .reason) Set out.error = "The user " _ user _ " exists and does not sign in with that password (" _ reason _ "): nothing was stored" Quit
        Do out.%Set("user_created", ''made, "boolean")
        Set sc = ..StoreCredential(ns, credential, user, password)
        If $$$ISERR(sc) Set out.error = $SYSTEM.Status.GetErrorText(sc) Quit
        // Kept apart from the namespace's record: a removal without {"credential": true} and a later apply leave both in place.
        If made Set ^Shutter.Config("onboardMade", "user", user) = 1
        Set ^Shutter.Config("onboardMade", "credential", ns) = credential
        Kill ^Shutter.Health("credentials")
        Do out.%Set("ok", 1, "boolean")
    } Catch ex {
        Set out.error = ex.DisplayString()
    }
    Quit out
}

ClassMethod EnsureForwarderUser(user As %String, password As %String, Output made As %Boolean) As %Status
{
    Set sc = $$$OK, made = 0
    New $NAMESPACE
    Try {
        Set $NAMESPACE = "%SYS"
        If ##class(Security.Users).Exists(user) {
            Set sc = ##class(Security.Users).Get(user, .props) Quit:$$$ISERR(sc)
            If '$LISTFIND($LISTFROMSTRING($GET(props("Roles"))), "Shutter_Forwarder") Set sc = $$$ERROR($$$GeneralError, "The user " _ user _ " exists and does not hold Shutter_Forwarder: add the role, or name another user")
            Quit
        }
        Set sc = ##class(Security.Users).Create(user, "Shutter_Forwarder", password, "Shutter's forwarder", "", "", "", 0, 1)
        If $$$ISOK(sc) {
            Set made = 1
            // A service sign-in: an expired password would turn every forward into a refused one, with no case.
            Set props("PasswordNeverExpires") = 1
            Set sc = ##class(Security.Users).Modify(user, .props)
        }
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

ClassMethod StoreCredential(ns As %String, credential As %String, user As %String, password As %String) As %Status
{
    Set sc = $$$OK
    New $NAMESPACE
    Try {
        Set $NAMESPACE = ns
        Set sc = ##class(Ens.Config.Credentials).SetCredential(credential, user, password, 1)
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// What an answer from the intake means, for the person running the test.
ClassMethod TestAdvice(status As %String, credential As %String = "", user As %String = "", caseId As %String = "") As %String
{
    If (status = 202) && (caseId '= "") Quit ""
    If status = 202 Quit "HTTP 202 with no case id, so something other than Shutter's intake answered: check the forwarder's HTTPServer, HTTPPort and IntakePath, and any proxy in between"
    If status = 404 Quit "HTTP 404: IRIS answers a sign-in it refuses this way on a REST application. Check the password of " _ user _ " and the credential " _ credential _ ", or that the address is this instance's"
    If status = 401 Quit "HTTP 401: the credential " _ credential _ " did not sign in as " _ user
    If status = 403 Quit "HTTP 403: " _ user _ " signed in but does not hold Shutter_Forwarder"
    If status = 503 Quit "HTTP 503: Shutter's production is not running, so the failure was not taken. Start Shutter.Production"
    If status = 413 Quit "HTTP 413: the message is over 2 MB"
    If status = "" Quit "No answer: check the forwarder's HTTPServer and HTTPPort, and that Shutter's web server answers from this namespace's host"
    Quit "HTTP " _ status _ " from Shutter"
}

/// The test forward for a namespace: a made-up ORU, with no patient in it and marked as a test, posted with that namespace's
/// forwarder settings and stored credential to Shutter's intake, as the forwarder would post it. An ORU has no mapped
/// operation, so its case escalates with no model and nothing to send, and the receiver named is one no profile lists.
/// Answers {ok, case, http_status, advice}. It proves the address, the password and the role on day one.
ClassMethod Test(ns As %String) As %DynamicObject
{
    Set ns = ..NS(ns), out = {"namespace": (ns), "case": "", "http_status": "", "advice": "", "error": ""}
    Do out.%Set("ok", 0, "boolean")
    Try {
        Set credential = $GET(^Shutter.Config("onboard", ns, "credential"), ..#CREDENTIAL)
        Set read = ..Read(ns, $GET(^Shutter.Config("onboard", ns)), credential)
        If read.error '= "" Set out.error = read.error Quit
        Set f = read.forwarder
        If '$ISOBJECT(f) Set out.error = "No forwarder in " _ read.production _ ": run the apply first" Quit
        Set credential = $SELECT(f.credential '= "": f.credential, 1: credential)
        If '##class(Shutter.Setup).StoredCredential(ns, credential, .user, .password) Set out.error = "No credential " _ credential _ " in " _ ns _ ": run OnboardCredential first" Quit
        Set out.production = read.production, out."production_state" = read.state
        Set stamp = $TRANSLATE(##class(Shutter.Util.Time).NowUTC(), "-:TZ."), control = "TEST" _ $EXTRACT(stamp, 1, 14)
        Set cr = $CHAR(13)
        Set text = "MSH|^~\&|SHUTTER-TEST|" _ ns _ "|SHUTTER|" _ ns _ "|" _ $EXTRACT(stamp, 1, 14) _ "||ORU^R01^ORU_R01|" _ control _ "|T|2.5.1" _ cr
        Set text = text _ "PID|1||TEST-ONBOARDING^^^TEST^MR||ONBOARDING^TEST||19000101|U" _ cr
        Set text = text _ "OBR|1|||TEST^Onboarding test^L" _ cr
        Set text = text _ "OBX|1|TX|TEST^Onboarding test^L||An onboarding test. There is no patient.||||||F" _ cr
        Set body = {"source": {"namespace": (ns), "production": (read.production), "route": (..#TESTRECEIVER), "header_id": ""}, "receiver": (..#TESTRECEIVER), "failure": {"kind": "unmappable", "outcome": "", "reason_code": (..#TESTREASON), "text": ("ONBOARDING TEST from " _ ns _ ", production " _ read.production _ ": not a real failure, and there is no patient. Nothing was sent to any receiver. Mark this case handled.")}, "message": (text), "schema_category": "2.5.1"}
        Set http = ##class(%Net.HttpRequest).%New()
        Set http.Server = f.server, http.Port = f.port, http.Timeout = 30
        If f.ssl '= "" Set http.Https = 1, http.SSLConfiguration = f.ssl
        Set http.Username = user, http.Password = password
        Set http.ContentType = "application/json"
        Do http.SetHeader("X-Requested-With", "Shutter")
        Do http.EntityBody.Write(body.%ToJSON())
        Set sc = http.Post(f.path)
        Set status = "", answer = ""
        If $$$ISOK(sc) && $ISOBJECT(http.HttpResponse) {
            Set status = +http.HttpResponse.StatusCode
            If $ISOBJECT(http.HttpResponse.Data) { Do http.HttpResponse.Data.Rewind() Set answer = http.HttpResponse.Data.Read(4000) } Else { Set answer = http.HttpResponse.Data }
        }
        Set out."http_status" = status
        Set caseId = $SELECT(status = 202: ##class(Shutter.Intake.Forwarder).CaseIdIn(answer), 1: "")
        Set out.advice = ..TestAdvice(status, credential, user, caseId)
        If (status = 202) && (caseId = "") {
            Set out.error = out.advice
        } ElseIf status = 202 {
            Set out.case = caseId
            Do out.%Set("ok", 1, "boolean")
            Set ^Shutter.Config("onboard", ns, "lastTest") = $LISTBUILD(##class(Shutter.Util.Time).NowUTC(), out.case)
        } ElseIf status = "" {
            Set out.error = $SYSTEM.Status.GetErrorText(sc)
        } Else {
            Set out.error = $EXTRACT(answer, 1, 500)
        }
    } Catch ex {
        Set out.error = ex.DisplayString()
    }
    Quit out
}

/// Takes a namespace back off: the items Apply added go, a renamed Ens.Alert gets its name back, AlertOnError goes back,
/// the drafts still marked draft leave the profile, and the running production is updated, never stopped. Stays, and the
/// answer says so: the cases (a record), the schemas in Shutter (cases read by them), entries a person edited, and the
/// credential and the user unless {"credential": true}. That takes this namespace's credential, and the user only when the
/// credential step made it and no other namespace onboarded here signs in with it, so the last one's removal takes it and
/// no earlier one breaks a neighbour. A mapping goes only when no message of Shutter's classes is left
/// in that namespace, since the site's purge must be able to open them, unless {"unmap": true}.
ClassMethod Remove(ns As %String, options As %DynamicObject = "") As %DynamicObject
{
    Set ns = ..NS(ns)
    If '$ISOBJECT(options) Set options = {}
    Set out = {"namespace": (ns), "removed": [], "kept": [], "error": ""}
    Do out.%Set("ok", 0, "boolean")
    If '$SYSTEM.Security.Check("%Admin_Manage", "USE") Set out.error = "Taking a namespace off changes the instance's configuration: it needs a user holding %Admin_Manage" Quit out
    // A mapping left behind by an earlier removal (below) can still go.
    If '$DATA(^Shutter.Config("onboard", ns)) && $DATA(^Shutter.Config("onboardKept", ns)) {
        Merge ^Shutter.Config("onboard", ns, "mappings") = ^Shutter.Config("onboardKept", ns, "mappings")
        Set ^Shutter.Config("onboard", ns, "remap") = 1
        Kill ^Shutter.Config("onboardKept", ns)
    }
    // A namespace taken off earlier may still hold the credential it was told to keep.
    If '$DATA(^Shutter.Config("onboard", ns)) && ##class(Shutter.Util.Json).Bool(options, "credential", 0) && ($GET(^Shutter.Config("onboardMade", "credential", ns)) '= "") {
        Do ..TakeCredential(ns, out)
        Do out.%Set("ok", 1, "boolean")
        Quit out
    }
    If '$DATA(^Shutter.Config("onboard", ns)) Set out.error = ns _ " was not onboarded here: nothing to take off" Quit out
    Try {
        Set production = $GET(^Shutter.Config("onboard", ns))
        Set items = [], item = ""
        For { Set item = $ORDER(^Shutter.Config("onboard", ns, "items", item)) Quit:item=""  Do items.%Push(item) }
        Set renamed = $GET(^Shutter.Config("onboard", ns, "renamed"))
        Set alerts = [], item = ""
        For { Set item = $ORDER(^Shutter.Config("onboard", ns, "alertOnError", item)) Quit:item=""  Do alerts.%Push(item) }
        Set sc = ..UneditProduction(ns, production, items, renamed, alerts, .done, .messages)
        If $$$ISERR(sc) Set out.error = $SYSTEM.Status.GetErrorText(sc) Quit
        Set di = items.%GetIterator()
        While di.%GetNext(, .name) { Do out.removed.%Push("The item " _ name _ " of " _ production) }
        If renamed '= "" Do out.removed.%Push("The name " _ renamed _ ": the site's item is Ens.Alert again")
        Set di = alerts.%GetIterator()
        While di.%GetNext(, .name) { Do out.removed.%Push("AlertOnError on " _ name) }
        If production '= "" Do out.removed.%Push($SELECT(done: "Updated the running production " _ production _ ": it was not stopped", 1: "The production " _ production _ " is not running; its definition changed"))
        // The drafts nobody has filled in.
        Set profile = ##class(Shutter.Store.SiteProfile).Current(), list = profile.%Get("receivers"), keep = [], dropped = 0
        If $ISOBJECT(list) {
            Set li = list.%GetIterator()
            While li.%GetNext(, .r) {
                Set name = ##class(Shutter.Util.Json).Str(r, "name")
                If $DATA(^Shutter.Config("onboard", ns, "drafted", name)) && ##class(Shutter.Util.Json).Bool(r, "draft", 0) {
                    Set dropped = dropped + 1
                    Do out.removed.%Push("The draft receiver " _ name _ " in the site profile")
                    Continue
                }
                If ##class(Shutter.Util.Json).Str(r, "namespace") = ns Do out.kept.%Push("The receiver " _ name _ " in the site profile: a person edited it")
                Do keep.%Push(r)
            }
            If dropped > 0 && (keep.%Size() > 0) {
                Set profile.receivers = keep
                Set psc = ##class(Shutter.Store.SiteProfile).Store(profile.%ToJSON(), "onboarding", "taken off " _ ns)
                If $$$ISERR(psc) Set out.error = $SYSTEM.Status.GetErrorText(psc) Quit
            }
        }
        // The mappings.
        Set pkg = ""
        For {
            Set pkg = $ORDER(^Shutter.Config("onboard", ns, "mappings", pkg)) Quit:pkg=""
            If (messages = 0) || ##class(Shutter.Util.Json).Bool(options, "unmap", 0) {
                Set sc = ..UnmapPackage(ns, pkg)
                If $$$ISERR(sc) Do out.kept.%Push("The mapping of " _ pkg _ ": " _ $SYSTEM.Status.GetErrorText(sc)) Continue
                Do out.removed.%Push("The mapping of " _ pkg _ $SELECT(messages > 0: ", with " _ messages _ " messages of Shutter's classes still in " _ ns _ ", which were not purged first as advised", 1: ""))
            } Else {
                Do out.kept.%Push("The mapping of " _ pkg _ ": " _ messages _ " messages of Shutter's classes are still in " _ ns _ ", and its purge must open them. Pass {""unmap"": true} after they are purged")
            }
        }
        If ##class(Shutter.Util.Json).Bool(options, "credential", 0) {
            Do ..TakeCredential(ns, out)
        } Else {
            Do out.kept.%Push("The credential and the user, unless {""credential"": true}")
        }
        Do out.kept.%Push("Shutter's cases from " _ ns _ " and the schemas imported from it")
        // Forget the receivers' names, so another namespace may take them; keep the mappings' record if they stayed.
        Merge kept = ^Shutter.Config("onboard", ns, "mappings")
        If (messages = 0) || ##class(Shutter.Util.Json).Bool(options, "unmap", 0) Kill kept
        Kill ^Shutter.Config("onboard", ns)
        Set ^Shutter.Config("onboardRemoved", ns) = $ZDATETIME($ZTIMESTAMP, 3, 1)
        Kill ^Shutter.Health("credentials")
        If $DATA(kept) Merge ^Shutter.Config("onboardKept", ns, "mappings") = kept
        Do out.%Set("ok", 1, "boolean")
    } Catch ex {
        Set out.error = ex.DisplayString()
    }
    Quit out
}

/// Takes the credential the credential step stored in a namespace, then its user unless that user is still needed or was
/// not the step's to take. Says each in the answer's removed or kept.
ClassMethod TakeCredential(ns As %String, out As %DynamicObject)
{
    Set credential = $GET(^Shutter.Config("onboardMade", "credential", ns))
    If credential = "" Do out.kept.%Push("No credential: the credential step stored none in " _ ns) Quit
    Set user = ..CredentialUser(ns, credential)
    Set sc = ..DropCredential(ns, credential)
    If $$$ISERR(sc) Do out.kept.%Push("The credential " _ credential _ " in " _ ns _ ": " _ $SYSTEM.Status.GetErrorText(sc)) Quit
    Kill ^Shutter.Config("onboardMade", "credential", ns)
    Do out.removed.%Push("The credential " _ credential _ " in " _ ns)
    Quit:(user = "")||'..UserExists(user)
    Set holders = "", other = ""
    For {
        Set other = $ORDER(^Shutter.Config("onboard", other)) Quit:other=""
        Continue:other=ns
        If ..CredentialUser(other, $GET(^Shutter.Config("onboard", other, "credential"), ..#CREDENTIAL)) = user Set holders = holders _ $LISTBUILD(other)
    }
    If holders '= "" Do out.kept.%Push("The user " _ user _ ": " _ $LISTTOSTRING(holders, ", ") _ " still signs in with it. It goes with the last of them to come off with {""credential"": true}") Quit
    If '$DATA(^Shutter.Config("onboardMade", "user", user)) Do out.kept.%Push("The user " _ user _ ": it was there before the credential step, so it is yours to remove") Quit
    Set sc = ..DropUser(user)
    If $$$ISERR(sc) Do out.kept.%Push("The user " _ user _ ": " _ $SYSTEM.Status.GetErrorText(sc)) Quit
    Kill ^Shutter.Config("onboardMade", "user", user)
    Do out.removed.%Push("The user " _ user)
    Set other = ""
    For {
        Set other = $ORDER(^Shutter.Config("onboardMade", "credential", other)) Quit:other=""
        Do out.kept.%Push("The credential " _ $GET(^Shutter.Config("onboardMade", "credential", other)) _ " in " _ other _ ", from an earlier removal, names that user no more: pass {""credential"": true} for " _ other)
    }
}

ClassMethod UserExists(user As %String) As %Boolean
{
    New $NAMESPACE
    Set $NAMESPACE = "%SYS"
    Quit ##class(Security.Users).Exists(user)
}

/// The user a stored credential names in a namespace, or "".
ClassMethod CredentialUser(ns As %String, credential As %String) As %String
{
    Set user = ""
    New $NAMESPACE
    Try {
        Set $NAMESPACE = ns
        Set cred = ##class(Ens.Config.Credentials).%OpenId(credential, 0)
        If $ISOBJECT(cred) Set user = cred.Username
    } Catch ex {
        Set user = ""
    }
    Quit user
}

/// The reverse of EditProduction. messages counts the Shutter bodies left in the namespace.
ClassMethod UneditProduction(ns As %String, production As %String, items As %DynamicArray, renamed As %String, alerts As %DynamicArray, Output done As %Boolean, Output messages As %Integer) As %Status
{
    Set sc = $$$OK, done = 0, messages = 0
    New $NAMESPACE
    Try {
        Set $NAMESPACE = ns
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT COUNT(*) AS N FROM Ens.MessageHeader WHERE MessageBodyClassName IN ('Shutter.Intake.Forward', 'Shutter.Intake.Forwarded')")
        If rs.%Next() Set messages = +rs.%Get("N")
        // Only a mapping is left to take: an earlier removal took the items.
        Quit:production=""
        Set prod = ##class(Ens.Config.Production).%OpenId(production)
        If '$ISOBJECT(prod) Set sc = $$$ERROR($$$GeneralError, "No production " _ production _ " in " _ ns) Quit
        Set di = items.%GetIterator()
        While di.%GetNext(, .name) {
            For i = prod.Items.Count():-1:1 {
                Set item = prod.Items.GetAt(i)
                If (item.Name = name) && ($EXTRACT(item.ClassName, 1, 15) = "Shutter.Intake.") {
                    Do prod.Items.RemoveAt(i)
                    Set id = item.%Id()
                    If id '= "" Do ##class(Ens.Config.Item).%DeleteId(id)
                }
            }
        }
        If renamed '= "" {
            For i = 1:1:prod.Items.Count() { If prod.Items.GetAt(i).Name = renamed Set prod.Items.GetAt(i).Name = "Ens.Alert" Quit }
        }
        Set di = alerts.%GetIterator()
        While di.%GetNext(, .name) {
            For i = 1:1:prod.Items.Count() {
                Set item = prod.Items.GetAt(i)
                Continue:item.Name'=name
                For j = item.Settings.Count():-1:1 { If item.Settings.GetAt(j).Name = "AlertOnError" Do item.Settings.RemoveAt(j) }
            }
        }
        Set sc = prod.%Save() Quit:$$$ISERR(sc)
        Set sc = prod.SaveToClass() Quit:$$$ISERR(sc)
        Set sc = ##class(Ens.Director).GetProductionStatus(.running, .state) Quit:$$$ISERR(sc)
        If ($GET(running) = production) && ($GET(state) = 1) {
            Set sc = ##class(Ens.Director).UpdateProduction(30, 0)
            Set done = 1
        }
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

ClassMethod UnmapPackage(ns As %String, package As %String) As %Status
{
    Set sc = $$$OK
    New $NAMESPACE
    Try {
        Set $NAMESPACE = "%SYS"
        If ##class(Config.MapPackages).Exists(ns, package) Set sc = ##class(Config.MapPackages).Delete(ns, package)
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

ClassMethod DropCredential(ns As %String, credential As %String) As %Status
{
    Set sc = $$$OK
    New $NAMESPACE
    Try {
        Set $NAMESPACE = ns
        Set sc = ##class(Ens.Config.Credentials).%DeleteId(credential)
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

ClassMethod DropUser(user As %String) As %Status
{
    Set sc = $$$OK
    New $NAMESPACE
    Try {
        Set $NAMESPACE = "%SYS"
        Set sc = ##class(Security.Users).Delete(user)
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// A receiver with an API needs a connector item of its name in Shutter's production (CaseWorkflow.WardTargetFor sends it
/// there). This adds one and records it, so a load or an upgrade, which rewrites Shutter.Production from the package,
/// puts it back (RestoreReceiverItems). The item and the two readers call one server: Evidence Collector and Verifier
/// take this server when they have none other, and the answer warns when a second receiver names another.
ClassMethod ReceiverItem(name As %String, host As %String = "", port As %String = "", credential As %String = "DownstreamAPI", ssl As %String = "") As %DynamicObject
{
    Set out = {"receiver": (name), "warnings": [], "error": ""}
    Do out.%Set("ok", 0, "boolean")
    Try {
        Set name = $ZSTRIP($TRANSLATE($GET(name), $CHAR(0)), "<>W"), host = $TRANSLATE($GET(host), $CHAR(0)), port = $TRANSLATE($GET(port), $CHAR(0)), credential = $TRANSLATE($GET(credential), $CHAR(0)), ssl = $TRANSLATE($GET(ssl), $CHAR(0))
        If host = "" Set host = "127.0.0.1"
        If port = "" Set port = ..WebPort()
        If credential = "" Set credential = "DownstreamAPI"
        If name = "" Set out.error = "No receiver named" Quit
        Set entry = ##class(Shutter.Store.SiteProfile).Receiver(name)
        If '$ISOBJECT(entry) || '$ISOBJECT(entry.%Get("api")) Set out.error = "The site profile has no API for " _ name _ ": a receiver with no API has no connector" Quit
        Set differs = ..ItemDiffers(name, host, port, credential, ssl, .now)
        If differs Set out.error = name _ "'s connector item calls " _ now _ ", and this call names " _ host _ ":" _ port _ " (credential " _ credential _ ", SSL " _ ssl _ "). Nothing was changed. To move it, change the item in the production, then make this call again with the same values, so that an upgrade keeps them" Quit
        Set other = "", first = $ORDER(^Shutter.Config("receiverItems", ""))
        If (first '= "") && (first '= name) {
            Set was = ^Shutter.Config("receiverItems", first)
            If ($LIST(was, 1) '= host) || (+$LIST(was, 2) '= +port) Do out.warnings.%Push("Evidence Collector and Verifier read one server, " _ $LIST(was, 1) _ ":" _ $LIST(was, 2) _ " (" _ first _ "): this receiver's state and receipts cannot be read on another until that changes, so its writes stay blocked")
        }
        // The readers' record follows a correction only when this is the one receiver: with others, it would strand them.
        Set old = $GET(^Shutter.Config("receiverItems", name))
        Set moved = (old '= "") && (first = name) && (($LIST(old, 1) '= host) || (+$LIST(old, 2) '= +port))
        Set only = (first = name) && ($ORDER(^Shutter.Config("receiverItems", name)) = "")
        If moved Do out.warnings.%Push("Evidence Collector and Verifier read " _ $LIST(old, 1) _ ":" _ $LIST(old, 2) _ $SELECT(only: " until their settings change or the next load", 1: ": this receiver's writes stay blocked until they read the same server"))
        If (first = "") || (moved && only) Set ^Shutter.Config("downstreamHost") = host, ^Shutter.Config("downstreamPort") = port
        Set ^Shutter.Config("receiverItems", name) = $LISTBUILD(host, port, credential, ssl)
        Set sc = ..RestoreReceiverItems(.added)
        If $$$ISERR(sc) Set out.error = $SYSTEM.Status.GetErrorText(sc) Quit
        Set out.added = added
        Do out.%Set("credential", ##class(Ens.Config.Credentials).%ExistsId(credential), "boolean")
        If 'out.credential Do out.warnings.%Push("No credential " _ credential _ " in " _ $NAMESPACE _ ": set it (Ens.Config.Credentials.SetCredential), or the receiver cannot be read")
        Do out.%Set("ok", 1, "boolean")
    } Catch ex {
        Set out.error = ex.DisplayString()
    }
    Quit out
}

/// Whether Shutter's production already has an item of this name with other settings: a call that names them would change
/// nothing now and the item at the next load. now says what the item calls.
ClassMethod ItemDiffers(name As %String, host As %String, port As %String, credential As %String, ssl As %String, Output now As %String) As %Boolean
{
    Set now = "", differs = 0
    Set prod = ##class(Ens.Config.Production).%OpenId(##class(Shutter.Setup).ProductionName(), 0)
    Quit:'$ISOBJECT(prod) 0
    For i = 1:1:prod.Items.Count() {
        Set item = prod.Items.GetAt(i)
        Continue:item.Name'=name
        For j = 1:1:item.Settings.Count() { Set one = item.Settings.GetAt(j), s(one.Name) = one.Value }
        Set now = $GET(s("HTTPServer")) _ ":" _ $GET(s("HTTPPort")) _ " (credential " _ $GET(s("Credentials")) _ ", SSL " _ $GET(s("SSLConfig")) _ ")"
        Set differs = ($GET(s("HTTPServer")) '= host) || (+$GET(s("HTTPPort")) '= +port) || ($GET(s("Credentials")) '= credential) || ($GET(s("SSLConfig")) '= ssl)
        Quit
    }
    Quit differs
}

/// The recorded connector items put in Shutter's production when it lacks them. The install runs this on a site install.
ClassMethod RestoreReceiverItems(Output added As %Integer) As %Status
{
    Set sc = $$$OK, added = 0
    Try {
        Quit:$DATA(^Shutter.Config("receiverItems"))=0
        Set production = ##class(Shutter.Setup).ProductionName()
        Set prod = ##class(Ens.Config.Production).%OpenId(production)
        If '$ISOBJECT(prod) Set sc = $$$ERROR($$$GeneralError, "No production " _ production) Quit
        For i = 1:1:prod.Items.Count() Set have(prod.Items.GetAt(i).Name) = 1
        Set name = ""
        For {
            Set name = $ORDER(^Shutter.Config("receiverItems", name), 1, was) Quit:name=""
            Continue:$DATA(have(name))
            Set new = ##class(Ens.Config.Item).%New()
            Set new.Name = name, new.ClassName = "Shutter.Operation.Ward", new.PoolSize = 1, new.Enabled = 1, new.Production = prod
            For set = $LISTBUILD("Adapter", "HTTPServer", $LIST(was, 1)), $LISTBUILD("Adapter", "HTTPPort", $LIST(was, 2)), $LISTBUILD("Adapter", "Credentials", $LIST(was, 3)), $LISTBUILD("Adapter", "SSLConfig", $LIST(was, 4)), $LISTBUILD("Adapter", "ResponseTimeout", "15"), $LISTBUILD("Adapter", "ConnectTimeout", "5"), $LISTBUILD("Host", "FailureTimeout", "0") {
                Continue:($LIST(set, 3) = "")
                Set s = ##class(Ens.Config.Setting).%New(), s.Target = $LIST(set, 1), s.Name = $LIST(set, 2), s.Value = $LIST(set, 3)
                Do new.Settings.Insert(s)
            }
            Do prod.Items.Insert(new)
            Set added = added + 1
        }
        Quit:added=0
        Set sc = prod.%Save() Quit:$$$ISERR(sc)
        Set sc = prod.SaveToClass() Quit:$$$ISERR(sc)
        Set sc = ##class(Ens.Director).GetProductionStatus(.running, .state) Quit:$$$ISERR(sc)
        If ($GET(running) = production) && ($GET(state) = 1) Set sc = ##class(Ens.Director).UpdateProduction(30, 0)
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// The receivers the profile gives an API whose connector item is missing from Shutter's production: each such case would
/// fail with "not registered to run". The demo's receivers are its own and are left out.
ClassMethod ReceiversWithoutItem() As %DynamicArray
{
    Set out = []
    Try {
        If $GET(^Shutter.Config("demo"), 1) Quit
        Set prod = ##class(Ens.Config.Production).%OpenId(##class(Shutter.Setup).ProductionName(), 0)
        Quit:'$ISOBJECT(prod)
        For i = 1:1:prod.Items.Count() Set have(prod.Items.GetAt(i).Name) = 1
        Set list = ##class(Shutter.Store.SiteProfile).Current().%Get("receivers")
        Quit:'$ISOBJECT(list)
        Set li = list.%GetIterator()
        While li.%GetNext(, .r) {
            Continue:'$ISOBJECT(r)
            Set name = ##class(Shutter.Util.Json).Str(r, "name")
            If $ISOBJECT(r.%Get("api")) && '$DATA(have(name)) Do out.%Push(name)
        }
    } Catch ex {
    }
    Quit out
}

/// The namespaces Shutter watches: those onboarded here, and those a case names as its source. Each with its state and its
/// problems in words, for the Doctor. {namespace, onboarded, exists, production, production_state, forwarder,
/// alert_intake, pass_to, classes, credential, last_forward, last_forward_error, last_case, schemas_missing, problems, ok}.
ClassMethod Watched() As %DynamicArray
{
    Set out = []
    Set ns = ""
    For { Set ns = $ORDER(^Shutter.Config("onboard", ns)) Quit:ns=""  Set seen(ns) = 1 }
    Try {
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT DISTINCT %EXACT(SourceNamespace) AS N FROM Shutter_Store.""Case"" WHERE SourceNamespace IS NOT NULL AND SourceNamespace <> ''")
        While rs.%Next() { Set seen(rs.%Get("N")) = $GET(seen(rs.%Get("N")), 0) }
    } Catch ex {
    }
    Set ns = ""
    For {
        Set ns = $ORDER(seen(ns)) Quit:ns=""
        Set read = ..Read(ns, $GET(^Shutter.Config("onboard", ns)), $GET(^Shutter.Config("onboard", ns, "credential")))
        Set w = {"namespace": (ns), "production": (read.production), "production_state": (read.state), "problems": []}
        Do w.%Set("onboarded", seen(ns) = 1, "boolean"), w.%Set("exists", read.exists, "boolean")
        Set f = read.forwarder, a = read.alert
        Do w.%Set("forwarder", $ISOBJECT(f), "boolean")
        Do w.%Set("alert_intake", $ISOBJECT(a) && a."is_shutter", "boolean")
        Set w."pass_to" = $SELECT($ISOBJECT(a): a."pass_to", 1: "")
        Do w.%Set("classes", read.classes.%Get("Shutter.Intake.Forwarder") && read.classes.%Get("Shutter.Util.Json") && read.classes.%Get("Shutter.Util.Time"), "boolean")
        Do w.%Set("credential", read.credential, "boolean")
        Set last = read."last_forward"
        Set w."last_forward" = $SELECT($ISOBJECT(last): last.at, 1: "")
        Set w."last_forward_error" = $SELECT($ISOBJECT(last): last.error, 1: "")
        Set w."refused_72h" = read."refused_72h", w."last_refused" = read."last_refused"
        Set caseId = "", opened = ""
        &sql(SELECT TOP 1 CaseId, OpenedAt INTO :caseId, :opened FROM Shutter_Store."Case" WHERE SourceNamespace = :ns ORDER BY ID DESC)
        If SQLCODE '= 0 Set caseId = "", opened = ""
        Set w."last_case" = caseId, w."last_case_at" = opened
        // The categories its services name that Shutter cannot read.
        Set missing = [], it = read.items.%GetIterator()
        While it.%GetNext(, .item) {
            Continue:item.kind'="hl7_service"
            Set ci = item.categories.%GetIterator()
            While ci.%GetNext(, .cat) {
                Set local = ##class(Shutter.Util.Schemas).LocalName(ns, cat)
                If '##class(Shutter.Util.Schemas).Known(local) && '$DATA(said(ns, cat)) { Set said(ns, cat) = 1 Do missing.%Push(cat) }
            }
        }
        Set w."schemas_missing" = missing
        // HL7 operations added since the last apply: their failures reach the site's consumer and open no case.
        Set unwatched = []
        If $ISOBJECT(a) && a."is_shutter" && (a.receivers '= "") {
            Set it = read.items.%GetIterator()
            While it.%GetNext(, .item) {
                If (item.kind = "hl7_operation") && '##class(Shutter.Intake.AlertProcess).Takes(item.name, a.receivers) Do unwatched.%Push(item.name)
            }
        }
        Set w."operations_unwatched" = unwatched
        Do w.%Set("removed", (seen(ns) '= 1) && $DATA(^Shutter.Config("onboardRemoved", ns)), "boolean")
        If read.error '= "" Do w.problems.%Push(read.error)
        If w.removed {
            // Taken off on purpose: its cases stay, and nothing about it is a problem now.
        } ElseIf read.exists && (read.error = "") {
            If 'w.forwarder Do w.problems.%Push("No forwarder item in " _ read.production)
            If 'w.classes Do w.problems.%Push("The forwarder's classes do not all resolve in " _ ns)
            If w.forwarder && 'w.credential Do w.problems.%Push("No credential " _ read."credential_name" _ " in " _ ns)
            If read.state '= "running" Do w.problems.%Push("The production " _ read.production _ " is " _ read.state)
            If missing.%Size() > 0 Do w.problems.%Push("Schemas missing in Shutter: " _ missing.%ToJSON())
            If w."last_forward_error" '= "" Do w.problems.%Push("The last forward was refused: " _ $EXTRACT(w."last_forward_error", 1, 200))
            If w."refused_72h" > 0 Do w.problems.%Push(w."refused_72h" _ " forwards refused in the last 72 hours, the last at " _ w."last_refused" _ ": those failures have no case. Search the event log for: Shutter did not take")
            If unwatched.%Size() > 0 Do w.problems.%Push("HL7 operations the alert intake does not hear, so their failures open no case: " _ unwatched.%ToJSON() _ ". Run the plan and the apply again")
        }
        Do w.%Set("ok", w.problems.%Size() = 0, "boolean")
        Do out.%Push(w)
    }
    Quit out
}

}
