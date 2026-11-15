/// What a site set on the items of Shutter's own production (shape A), kept over an upgrade (1.4.9). Loading a newer
/// Shutter re-imports Shutter.Production's class, and compiling it rebuilds the production's definition from the class's
/// XData: until 1.4.9 every pool size, enabled flag, setting and item a site had changed or added there went back to the
/// shipped ones (found on 14 Nov 2026: Receiver Watch's pool size 3 read 1 after an upgrade of 1.4.7).
///
/// An install keeps a record of the site's own values (the "site" node: the properties and settings the site changed,
/// the settings it took out, and the items it added, whole) and of the definition it left (the "left" node). Each
/// install:
/// - takes the capture, the definition as it is before the install changes anything (Capture): the module's Invoke takes
///   it before IPM reloads the classes (module.xml loads this class first for that), and Shutter.Setup.InstallStatus takes
///   it at its start when the install is run by hand (a rebuilt container);
/// - learns what the site changed since the last install, the capture against the definition that install left (Learn);
/// - puts the site's values back on the definition the install made (Apply), after the install's own changes (the demo's
///   items off on a site's install, the Second Parser following its jar, the receivers' and the FHIR items put back), so
///   new items, new settings and changed defaults arrive and the site's values stand.
/// What the install sets itself is never taken for the site's (InstallOwns): the demo items' enabled flags when the demo
/// flag changes, or, with no record, when the capture holds what the earlier install set; the Second Parser's flag with no
/// record; and the four server settings of the FHIR items and of the receivers' connector items, which their own records
/// set at every install.
/// With no record of the last install (one over 1.4.8 or earlier), the capture is compared with the definition this
/// install made: every value that differs is the site's, but the descriptions (DESCRIPTIVE), nothing counts as taken out,
/// and an added item of a Shutter class is left out, since it may be one Shutter no longer ships. (The class as last
/// compiled tells nothing of the earlier release: a save in the Production Configuration page rewrites its XData too.)
/// Shape B (Shutter's items in a site's own production) needs none of this: that production's class is the site's.
/// The class uses only the system's classes, so the module can load it before its other classes.
Class Shutter.Util.SiteItems [ Abstract ]
{

Parameter PRODUCTION = "Shutter.Production";

/// Where the capture ("before"), the record of the site's values ("site"), the definition the last install left ("left")
/// and the last install's account ("last", JSON) are kept.
Parameter NODE = "^Shutter.Config(""siteItems"")";

/// The item properties kept (Ens.Config.Item's attributes but its name and class).
Parameter ITEMPROPERTIES = "PoolSize,Enabled,Foreground,DisableErrorTraps,LogTraceEvents,Schedule,Comment,Category";

/// The production's own properties kept.
Parameter PRODUCTIONPROPERTIES = "ActorPoolSize,TestingEnabled,LogGeneralTraceEvents,Description";

/// The descriptions, which Shutter rewrites from release to release: with no record of the last install, a different
/// text is taken to be Shutter's older one, and the new definition's stands.
Parameter DESCRIPTIVE = "Comment,Category,Description";

/// A capture no install has used yet stands until an install uses it, however old: a load that stopped partway may
/// already have rebuilt the definition from the package, and a capture taken then would read the package's values as the
/// site's. One older than this many seconds is named in the account, since an item changed after it has its value from it.
Parameter PENDINGSECONDS = 86400;

/// The module's Invoke, before IPM's Reload phase: the capture (Capture), while the definition is still the site's. Also
/// the first step of Shutter.Setup.InstallStatus, which then keeps the capture the load took. Takes one only on an
/// instance an install has run on (^Shutter.Config("version") is set), in shape A. Never stops a load or an install: a
/// failure is written out, and the upgrade goes on as it did before.
ClassMethod CaptureStatus() As %Status
{
    Try {
        Quit:..ShapeB()
        Set r = ..Capture(..#PRODUCTION, ..#NODE, $GET(^Shutter.Config("version")) '= "", $GET(^Shutter.Config("demo")))
        If r = "captured" Write !, "Shutter: the settings of Shutter.Production's items are noted, to be kept over the install", !
    } Catch ex {
        Write !, "Shutter: the settings of Shutter.Production's items could not be noted (", ex.DisplayString(), "); check them after the install", !
    }
    Quit $$$OK
}

/// The last step of Shutter.Setup.InstallStatus in shape A (Keep): writes what it put back, removed or left out, and
/// keeps that account as JSON in ^Shutter.Config("siteItems", "last").
ClassMethod KeepStatus() As %Status
{
    Quit:..ShapeB() $$$OK
    Set node = ..#NODE
    Merge receivers = ^Shutter.Config("receiverItems")
    Do ..InstallOwns(.owned, $LISTGET($GET(@node@("before")), 5), $GET(^Shutter.Config("demo"), 1), $DATA(^Shutter.Config("fhirItems")) > 0, .receivers)
    Set sc = ..Keep(..#PRODUCTION, node, .out, .owned)
    Quit:$$$ISERR(sc) sc
    Set @node@("last") = out.%ToJSON()
    Set said = ..Account(out)
    If said '= "" Write !, "Shutter: on Shutter.Production, ", said, !
    Quit $$$OK
}

/// Whether Shutter's items are in a site's own production (shape B, ^Shutter.Config("production")).
ClassMethod ShapeB() As %Boolean [ CodeMode = expression ]
{
$GET(^Shutter.Config("production")) '= ""
}

/// What the install itself sets on Shutter.Production, and so not the site's to keep (owned, for Keep): owned("i", item)
/// is the item's class the rules hold for ("" for any), owned("i", item, "p", property) and owned("i", item, "s", target,
/// setting) a rule: $LISTBUILD("always"), never learnt and dropped from the record; $LISTBUILD("no record"), not learnt
/// with no record; $LISTBUILD("was", value), with no record, a capture holding value is the earlier install's.
/// - The demo items' Enabled (Shutter.Setup DEMOITEMS: off on a site's install, as shipped on a demo's). When the demo
///   flag changes in this install (demoBefore, the stored flag the capture found, against demoNow) the install's value
///   stands, "always"; otherwise "was" the earlier install's, on for a demo and off for a site.
/// - The Second Parser's Enabled, which follows its jar (Shutter.Setup SyncSecondParser): with no record the earlier
///   install's jar is unknown, so "no record".
/// - The four server settings of the FHIR items that call the server, while the FHIR record is there (fhir), and of each
///   receiver's connector item (receivers, ^Shutter.Config("receiverItems")): the install writes them from those records
///   (Shutter.FHIR.Install RestoreItems, Shutter.Util.Onboard RestoreReceiverItems), which stay the one place they are
///   set, so "always".
ClassMethod InstallOwns(Output owned, demoBefore As %String, demoNow As %Boolean, fhir As %Boolean, ByRef receivers)
{
    Kill owned
    If demoBefore = "" Set demoBefore = 1
    Set rule = $SELECT((''demoBefore) '= (''demoNow): $LISTBUILD("always"), 1: $LISTBUILD("was", ''demoBefore))
    Set names = $PARAMETER("Shutter.Setup", "DEMOITEMS")
    For k = 1:1:$LENGTH(names, ",") {
        Set name = $PIECE(names, ",", k)
        Continue:name=""
        Set owned("i", name) = "", owned("i", name, "p", "Enabled") = rule
    }
    Set name = $PARAMETER("Shutter.Util.SecondParser", "ITEM")
    Set:name'="" owned("i", name) = "", owned("i", name, "p", "Enabled") = $LISTBUILD("no record")
    Set endpoint = "HTTPServer,HTTPPort,Credentials,SSLConfig"
    If fhir {
        Set names = $PARAMETER("Shutter.FHIR.Profile", "ITEMS"), endpoint = $PARAMETER("Shutter.FHIR.Install", "ENDPOINT")
        For k = 1:1:$LENGTH(names, ",") {
            Set name = $PIECE(names, ",", k)
            Continue:(name = "")||'$CLASSMETHOD("Shutter.FHIR.Install", "CallsTheServer", name)
            Set owned("i", name) = $CLASSMETHOD("Shutter.FHIR.Install", "ItemClass", name)
            For j = 1:1:$LENGTH(endpoint, ",") Set owned("i", name, "s", "Adapter", $PIECE(endpoint, ",", j)) = $LISTBUILD("always")
        }
    }
    Set endpoint = "HTTPServer,HTTPPort,Credentials,SSLConfig", name = ""
    For {
        Set name = $ORDER(receivers(name))
        Quit:name=""
        Set owned("i", name) = "Shutter.Operation.Ward"
        For j = 1:1:$LENGTH(endpoint, ",") Set owned("i", name, "s", "Adapter", $PIECE(endpoint, ",", j)) = $LISTBUILD("always")
    }
}

/// Takes the capture into @node@("before"): the production's definition (Read), and as the node's value
/// $LISTBUILD(seconds, UTC time, job, found, demo), demo being the stored demo flag of the earlier install. A capture no
/// install has used is kept as it is, however old (PENDINGSECONDS). On an instance no install has run on (installed 0)
/// nothing is read: what is there is the shipped class freshly compiled, not a site's. Returns "captured", "pending" (one
/// kept), "no definition" or "first install".
ClassMethod Capture(production As %String, node As %String, installed As %Boolean, demo As %String = "") As %String
{
    If $GET(@node@("before")) '= "" Quit "pending"
    Kill @node@("before")
    Set found = 0
    If installed {
        Set found = ..Read(production, .def)
        Merge:found @node@("before") = def
    }
    Set @node@("before") = $LISTBUILD(..Seconds(), ..Stamp(), $JOB, found, demo)
    Quit $SELECT(found: "captured", installed: "no definition", 1: "first install")
}

/// After the install: what the site changed since the last install learnt from the capture (Learn), what the install
/// itself owns dropped from the record (owned, from InstallOwns; Forget), the site's values put back on the definition
/// (Apply), the definition saved and written to the class (so a later compile, a restart through
/// Shutter.Setup.RestartProduction included, rebuilds the same definition), the running production updated when anything
/// changed, the record and the definition left kept, and the capture removed. out holds mode ("record", "no record",
/// "nothing captured" or "no production"), changes, and the lists kept, restored, removed, skipped and warnings, which name
/// the items, properties and settings but never a setting's value.
ClassMethod Keep(production As %String, node As %String, Output out As %DynamicObject, ByRef owned) As %Status
{
    Set sc = $$$OK, out = {"mode": "", "changes": 0, "kept": [], "restored": [], "removed": [], "skipped": [], "warnings": []}
    Try {
        Set prod = ##class(Ens.Config.Production).%OpenId(production)
        If '$ISOBJECT(prod) Kill @node@("before") Set out.mode = "no production" Quit
        Merge site = @node@("site")
        Set meta = $GET(@node@("before")), record = ($DATA(@node@("left")) \ 10)
        If (meta '= "") && $LISTGET(meta, 4) {
            Merge before = @node@("before")
            If record {
                Merge left = @node@("left")
            } Else {
                Do ..Read(prod, .left)
            }
            Set out.mode = $SELECT(record: "record", 1: "no record")
            If (..Seconds() - $LISTGET(meta, 1)) > ..#PENDINGSECONDS Do out.warnings.%Push("the items' settings were noted at " _ $LISTGET(meta, 2) _ " by a load that stopped partway: an item changed since then has the value it had then")
            Do ..Learn(.before, .left, record, .site, out, .owned)
        } Else {
            Set out.mode = "nothing captured"
        }
        Do ..Forget(.site, .owned, out)
        Set changes = ..Apply(prod, .site, out)
        If changes Set sc = prod.%Save() Quit:$$$ISERR(sc)
        Set sc = prod.SaveToClass() Quit:$$$ISERR(sc)
        Do ..Read(prod, .now)
        Kill @node@("left"), @node@("site")
        Merge @node@("left") = now, @node@("site") = site
        Set @node@("left") = $LISTBUILD(..Seconds(), ..Stamp(), $GET(^Shutter.Config("version")))
        Kill @node@("before")
        Set out.changes = changes
        // An image build starts no production; elsewhere a running production takes the change at once.
        If changes && ($SYSTEM.Util.GetEnviron("SHUTTER_BUILD") '= "1") {
            Set sc = ##class(Ens.Director).GetProductionStatus(.running, .state) Quit:$$$ISERR(sc)
            If ($GET(running) = production) && ($GET(state) = 1) Set sc = ##class(Ens.Director).UpdateProduction()
        }
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// Adds to site, the record of the site's own values, what the capture (before) has and left, the definition the last
/// install left (record 1) or this install made (record 0), has not: a property or setting changed or added, a setting
/// taken out (record 1 only), an item added (whole, with "added" 1). An item the site added and then deleted leaves the
/// record. With no record, the descriptions are not learnt, and an added item of a Shutter class is left out (skipped).
/// What the install owns (owned, InstallOwns) is not learnt.
ClassMethod Learn(ByRef before, ByRef left, record As %Boolean, ByRef site, out As %DynamicObject, ByRef owned)
{
    Kill s, b, d, o
    Merge s = before("p"), b = left("p"), d = site("p")
    Do ..LearnNode(.s, .b, ..#PRODUCTIONPROPERTIES, record, .d, .o)
    Kill site("p")
    Merge site("p") = d
    Set name = ""
    For {
        Set name = $ORDER(before("i", name), 1, class)
        Quit:name=""
        If $DATA(left("i", name), was) {
            If was '= class {
                Do out.skipped.%Push(name _ ": its class was " _ was _ ", so what was set for " _ class _ " is not learnt")
                Continue
            }
            If $GET(site("i", name, "added")) {
                // The site's own item: its record is the item as it is now.
                Kill site("i", name)
                Merge site("i", name) = before("i", name)
                Set site("i", name, "added") = 1
                Continue
            }
            Kill s, b, d, o
            Merge s = before("i", name), b = left("i", name), d = site("i", name)
            Do ..Rules(.owned, name, class, .o)
            Do ..LearnNode(.s, .b, ..#ITEMPROPERTIES, record, .d, .o)
            Kill site("i", name)
            If $DATA(d) > 1 Merge site("i", name) = d Set site("i", name) = class
            Continue
        }
        If 'record && ($EXTRACT(class, 1, 8) = "Shutter.") {
            Do out.skipped.%Push(name _ ": not put back: with no record of the earlier install, an item of a Shutter class may be one Shutter no longer ships")
            Continue
        }
        Kill site("i", name)
        Merge site("i", name) = before("i", name)
        Set site("i", name, "added") = 1
    }
    Set name = ""
    For {
        Set name = $ORDER(left("i", name))
        Quit:name=""
        If '$DATA(before("i", name)) && $GET(site("i", name, "added")) Kill site("i", name)
    }
}

/// The rules of owned that hold for one item of this class, in o.
ClassMethod Rules(ByRef owned, name As %String, class As %String, Output o) [ Private ]
{
    Kill o
    Quit:'$DATA(owned("i", name), cls)
    Quit:(cls '= "")&&(cls '= class)
    Merge o = owned("i", name)
}

/// Whether a value the capture holds is the install's under its rule (InstallOwns), and so not the site's.
ClassMethod Installs(rule As %String, record As %Boolean, value As %String) As %Boolean [ Private ]
{
    Quit:rule="" 0
    Set kind = $LISTGET(rule, 1)
    Quit:kind="always" 1
    Quit:record 0
    Quit (kind = "no record") || ((kind = "was") && ($LISTGET(rule, 2) = value))
}

/// Drops from site what the install owns outright ("always" in owned): a recorded value of it, of an item the site
/// changed or added, goes, and the account says so. An item record left with nothing goes too.
ClassMethod Forget(ByRef site, ByRef owned, out As %DynamicObject)
{
    Set name = ""
    For {
        Set name = $ORDER(owned("i", name))
        Quit:name=""
        Continue:'$DATA(site("i", name), class)
        Do ..Rules(.owned, name, class, .o)
        Set p = ""
        For {
            Set p = $ORDER(o("p", p), 1, rule)
            Quit:p=""
            Continue:($LISTGET(rule, 1) '= "always")||'$DATA(site("i", name, "p", p))
            Kill site("i", name, "p", p)
            Do out.skipped.%Push(name _ ": " _ p _ " is the install's")
        }
        Set t = ""
        For {
            Set t = $ORDER(o("s", t))
            Quit:t=""
            Set n = ""
            For {
                Set n = $ORDER(o("s", t, n), 1, rule)
                Quit:n=""
                Continue:($LISTGET(rule, 1) '= "always")
                Continue:'$DATA(site("i", name, "s", t, n))&&'$DATA(site("i", name, "x", t, n))
                Kill site("i", name, "s", t, n), site("i", name, "x", t, n)
                Do out.skipped.%Push(name _ ": " _ t _ " setting " _ n _ " is the install's")
            }
        }
        If '$GET(site("i", name, "added")) && ($ORDER(site("i", name, "")) = "") Kill site("i", name)
    }
}

/// One node (the production's, or an item's): s the capture's, b the definition left, d the record, each with ("p",
/// property) and ("s", target, name); the record also has ("x", target, name) for a setting taken out.
/// o holds the rules of what the install owns on this node (Rules).
ClassMethod LearnNode(ByRef s, ByRef b, list As %String, record As %Boolean, ByRef d, ByRef o) [ Private ]
{
    For k = 1:1:$LENGTH(list, ",") {
        Set p = $PIECE(list, ",", k)
        Continue:'($DATA(s("p", p), v) # 2)
        Continue:('record && $LISTFIND($LISTFROMSTRING(..#DESCRIPTIVE), p))
        Continue:..Installs($GET(o("p", p)), record, v)
        If ($DATA(b("p", p), was) # 2) && (was = v) Continue
        Set d("p", p) = v
    }
    Set t = ""
    For {
        Set t = $ORDER(s("s", t))
        Quit:t=""
        Set n = ""
        For {
            Set n = $ORDER(s("s", t, n), 1, v)
            Quit:n=""
            Continue:..Installs($GET(o("s", t, n)), record, v)
            If ($DATA(b("s", t, n), was) # 2) && (was = v) Continue
            Set d("s", t, n) = v
            Kill d("x", t, n)
        }
    }
    Quit:'record
    Set t = ""
    For {
        Set t = $ORDER(b("s", t))
        Quit:t=""
        Set n = ""
        For {
            Set n = $ORDER(b("s", t, n))
            Quit:n=""
            Continue:$DATA(s("s", t, n))
            Continue:..Installs($GET(o("s", t, n)), record, "")
            Set d("x", t, n) = ""
            Kill d("s", t, n)
        }
    }
}

/// Puts the record of the site's values (site) on the definition (prod): each property and setting, each setting taken
/// out, each added item the definition lacks (when its class is compiled here). A record for an item the definition no
/// longer has, or has with another class, is dropped from site. Returns the number of changes; out says what each was.
ClassMethod Apply(prod As %RegisteredObject, ByRef site, out As %DynamicObject) As %Integer
{
    Kill d
    Merge d = site("p")
    Set changes = ..ApplyNode(prod, .d, ..#PRODUCTIONPROPERTIES, "the production", out)
    For i = 1:1:prod.Items.Count() {
        Set item = prod.Items.GetAt(i)
        If $ISOBJECT(item) && (item.Name '= "") && '$DATA(at(item.Name)) Set at(item.Name) = i
    }
    Set name = ""
    For {
        Set name = $ORDER(site("i", name), 1, class)
        Quit:name=""
        Kill d
        Merge d = site("i", name)
        If $DATA(at(name)) {
            Set item = prod.Items.GetAt(at(name))
            If item.ClassName '= class {
                Do out.skipped.%Push(name _ ": its class is now " _ item.ClassName _ ", so what was set for " _ class _ " is left out")
                Kill site("i", name)
                Continue
            }
            Set changes = changes + ..ApplyNode(item, .d, ..#ITEMPROPERTIES, name, out)
            Continue
        }
        If '$GET(d("added")) {
            Do out.skipped.%Push(name _ ": no longer in Shutter's production")
            Kill site("i", name)
            Continue
        }
        If '##class(%Dictionary.CompiledClass).%ExistsId(class) {
            Do out.skipped.%Push(name _ ": not put back: its class " _ class _ " is not compiled here")
            Continue
        }
        Set item = ##class(Ens.Config.Item).%New()
        Set item.Name = name, item.ClassName = class, item.Production = prod
        Do ..ApplyNode(item, .d, ..#ITEMPROPERTIES, name)
        Do prod.Items.Insert(item)
        Set changes = changes + 1
        Do out.restored.%Push(name)
    }
    Quit changes
}

/// One node of the record (d) on one object, the production or an item. out, when given, says what changed: names, and
/// the values of properties but descriptions, never a setting's value.
ClassMethod ApplyNode(obj As %RegisteredObject, ByRef d, list As %String, label As %String, out As %DynamicObject = "") As %Integer [ Private ]
{
    Set changes = 0
    For k = 1:1:$LENGTH(list, ",") {
        Set p = $PIECE(list, ",", k)
        Continue:'($DATA(d("p", p), v) # 2)
        Continue:($PROPERTY(obj, p) = v)
        Set $PROPERTY(obj, p) = v, changes = changes + 1
        Do:$ISOBJECT(out) out.kept.%Push(label _ ": " _ p _ " " _ $SELECT($LISTFIND($LISTFROMSTRING(..#DESCRIPTIVE), p): "(its text)", 1: v))
    }
    Set settings = obj.Settings
    For j = 1:1:settings.Count() {
        Set one = settings.GetAt(j)
        If $ISOBJECT(one) && (one.Name '= "") Set at(..TargetKey(one.Target), one.Name) = j
    }
    Set t = ""
    For {
        Set t = $ORDER(d("s", t))
        Quit:t=""
        Set n = ""
        For {
            Set n = $ORDER(d("s", t, n), 1, v)
            Quit:n=""
            If $DATA(at(t, n)) {
                Set one = settings.GetAt(at(t, n))
                Continue:(one.Value = v)
                Set one.Value = v
            } Else {
                Set one = ##class(Ens.Config.Setting).%New()
                Set one.Target = $SELECT(t = "-": "", 1: t), one.Name = n, one.Value = v
                Do settings.Insert(one)
            }
            Set changes = changes + 1
            Do:$ISOBJECT(out) out.kept.%Push(label _ ": " _ $SELECT(t = "-": "", 1: t _ " ") _ "setting " _ n)
        }
    }
    Set t = ""
    For {
        Set t = $ORDER(d("x", t))
        Quit:t=""
        Set n = ""
        For {
            Set n = $ORDER(d("x", t, n))
            Quit:n=""
            Set:$DATA(at(t, n)) gone(at(t, n)) = $SELECT(t = "-": "", 1: t _ " ") _ "setting " _ n
        }
    }
    Set j = ""
    For {
        Set j = $ORDER(gone(j), -1, what)
        Quit:j=""
        Do settings.RemoveAt(j)
        Set changes = changes + 1
        Do:$ISOBJECT(out) out.removed.%Push(label _ ": " _ what)
    }
    Quit changes
}

/// A production's definition (an Ens.Config.Production, or the name of a saved one) as an array: def("p", "p", property)
/// and def("p", "s", target, name) for the production; def("i", item) = its class, def("i", item, "p", property) and
/// def("i", item, "s", target, name) for each item. A blank target is "-". An item name that repeats is read once.
/// Returns whether there was a definition.
ClassMethod Read(production, Output def) As %Boolean
{
    Kill def
    Set prod = $SELECT($ISOBJECT(production): production, 1: ##class(Ens.Config.Production).%OpenId(production, 0))
    Quit:'$ISOBJECT(prod) 0
    Set list = ..#PRODUCTIONPROPERTIES
    For k = 1:1:$LENGTH(list, ",") Set p = $PIECE(list, ",", k), def("p", "p", p) = $PROPERTY(prod, p)
    Do ..ReadSettings(prod.Settings, .s)
    Merge def("p", "s") = s
    Set list = ..#ITEMPROPERTIES
    For i = 1:1:prod.Items.Count() {
        Set item = prod.Items.GetAt(i)
        Continue:'$ISOBJECT(item)
        Set name = item.Name
        Continue:((name = "") || $DATA(def("i", name)))
        Set def("i", name) = item.ClassName
        For k = 1:1:$LENGTH(list, ",") Set p = $PIECE(list, ",", k), def("i", name, "p", p) = $PROPERTY(item, p)
        Do ..ReadSettings(item.Settings, .s)
        Merge def("i", name, "s") = s
    }
    Quit 1
}

ClassMethod ReadSettings(list As %RegisteredObject, Output s) [ Private ]
{
    Kill s
    For j = 1:1:list.Count() {
        Set one = list.GetAt(j)
        Continue:'$ISOBJECT(one)
        Continue:one.Name=""
        Set s(..TargetKey(one.Target), one.Name) = one.Value
    }
}

ClassMethod TargetKey(target As %String) As %String [ CodeMode = expression, Private ]
{
$SELECT(target = "": "-", 1: target)
}

/// One line for the install's output: what Keep put back, removed and left out, and what to check, or "" when nothing.
ClassMethod Account(out As %DynamicObject) As %String
{
    Set said = ""
    For list = $LISTBUILD("kept", "the site's values put back: "), $LISTBUILD("restored", "the site's items put back: "), $LISTBUILD("removed", "settings the site took out taken out: "), $LISTBUILD("skipped", "not kept: "), $LISTBUILD("warnings", "to check: ") {
        Set a = out.%Get($LIST(list, 1)), text = ""
        Continue:'$ISOBJECT(a)
        Set last = a.%Size() - 1
        Continue:last<0
        For k = 0:1:last Set text = text _ $SELECT(text = "": "", 1: "; ") _ a.%Get(k)
        Set said = said _ $SELECT(said = "": "", 1: ". ") _ $LIST(list, 2) _ text
    }
    Quit said
}

ClassMethod Seconds() As %Integer [ CodeMode = expression ]
{
$PIECE($ZTIMESTAMP, ",") * 86400 + $PIECE($ZTIMESTAMP, ",", 2) \ 1
}

ClassMethod Stamp() As %String [ CodeMode = expression ]
{
$ZDATETIME($ZTIMESTAMP, 3, 1) _ " UTC"
}

}
