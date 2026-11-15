/// What a site set on the items of Shutter's own production (shape A), kept over an upgrade (1.4.8). Loading a newer
/// Shutter re-imports Shutter.Production's class, and compiling it rebuilds the production's definition from the class's
/// XData: until 1.4.8 every pool size, enabled flag, setting and item a site had changed or added there went back to the
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
/// With no record of the last install (one over 1.4.7 or earlier), the capture is compared with the definition this
/// install made: a value that differs is the site's, but the descriptions (DESCRIPTIVE) and a value the earlier release
/// shipped, which the module's capture reads from the class as it was still compiled (Shipped); nothing counts as taken
/// out; and an added item is the site's unless the earlier release shipped it (or, with no compiled class to read, a run
/// by hand after the class was replaced, unless its class is a Shutter one, since it may be one Shutter no longer ships).
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

/// A capture no install has used yet is used by the next one for this many seconds: an upgrade that stopped partway may
/// already have rebuilt the definition, and the capture taken before it is the site's. After that a capture is taken again.
Parameter PENDINGSECONDS = 86400;

/// The module's Invoke, before IPM's Reload phase: the capture (Capture), while the definition is still the site's. Also
/// the first step of Shutter.Setup.InstallStatus, which then keeps the capture the load took. Takes one only on an
/// instance an install has run on (^Shutter.Config("version") is set), in shape A. Never stops a load or an install: a
/// failure is written out, and the upgrade goes on as before 1.4.8.
ClassMethod CaptureStatus() As %Status
{
    Try {
        Quit:..ShapeB()
        Set r = ..Capture(..#PRODUCTION, ..#NODE, $GET(^Shutter.Config("version")) '= "")
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
    Set sc = ..Keep(..#PRODUCTION, node, .out)
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

/// Takes the capture into @node@("before"): the production's definition (Read), with no record of the last install
/// the compiled class's definition under "shipped" (Shipped), and as the node's value $LISTBUILD(seconds, UTC time, job,
/// found). A capture no install has used, younger than PENDINGSECONDS, is kept as it
/// is. On an instance no install has run on (installed 0) nothing is read: what is there is the shipped class freshly
/// compiled, not a site's. Returns "captured", "pending" (one kept), "no definition" or "first install".
ClassMethod Capture(production As %String, node As %String, installed As %Boolean) As %String
{
    Set meta = $GET(@node@("before"))
    If (meta '= "") && ((..Seconds() - $LISTGET(meta, 1)) < ..#PENDINGSECONDS) Quit "pending"
    Kill @node@("before")
    Set found = 0
    If installed {
        Set found = ..Read(production, .def)
        Merge:found @node@("before") = def
        // With no record of the last install, the definition the compiled class holds: before IPM reloads the classes, the
        // earlier release's as shipped, which tells its values from the site's (Learn).
        If found && '($DATA(@node@("left")) \ 10) && ..Shipped(production, .old) Merge @node@("before", "shipped") = old
    }
    Set @node@("before") = $LISTBUILD(..Seconds(), ..Stamp(), $JOB, found)
    Quit $SELECT(found: "captured", installed: "no definition", 1: "first install")
}

/// After the install: what the site changed since the last install learnt from the capture (Learn), the site's values
/// put back on the definition (Apply), the definition saved and written to the class (so a later compile, a restart
/// through Shutter.Setup.RestartProduction included, rebuilds the same definition), the running production updated when
/// anything changed, the record and the definition left kept, and the capture removed. out holds mode ("record", "no
/// record", "nothing captured" or "no production"), changes, and the lists kept, restored, removed and skipped, which name
/// the items, properties and settings but never a setting's value.
ClassMethod Keep(production As %String, node As %String, Output out As %DynamicObject) As %Status
{
    Set sc = $$$OK, out = {"mode": "", "changes": 0, "kept": [], "restored": [], "removed": [], "skipped": []}
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
            Do ..Learn(.before, .left, record, .site, out)
        } Else {
            Set out.mode = "nothing captured"
        }
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
/// record. With no record, the descriptions are not learnt, nor a value the compiled class's definition (before("shipped"),
/// the earlier release's when the module's capture took it) also has; an item that definition has is not taken to be the
/// site's, and with none, nor is an item of a Shutter class (skipped).
ClassMethod Learn(ByRef before, ByRef left, record As %Boolean, ByRef site, out As %DynamicObject)
{
    Set shipped = 'record && ($DATA(before("shipped")) \ 10)
    Kill s, b, d, o
    Merge s = before("p"), b = left("p"), d = site("p")
    Merge:'record o = before("shipped", "p")
    Do ..LearnNode(.s, .b, ..#PRODUCTIONPROPERTIES, record, .d, .o)
    Kill site("p")
    Merge site("p") = d
    Set name = ""
    For {
        Set name = $ORDER(before("i", name), 1, class)
        Quit:name=""
        If $DATA(left("i", name), was) {
            Continue:was '= class
            If $GET(site("i", name, "added")) {
                // The site's own item: its record is the item as it is now.
                Kill site("i", name)
                Merge site("i", name) = before("i", name)
                Set site("i", name, "added") = 1
                Continue
            }
            Kill s, b, d, o
            Merge s = before("i", name), b = left("i", name), d = site("i", name)
            Merge:'record o = before("shipped", "i", name)
            Do ..LearnNode(.s, .b, ..#ITEMPROPERTIES, record, .d, .o)
            Kill site("i", name)
            If $DATA(d) > 1 Merge site("i", name) = d Set site("i", name) = class
            Continue
        }
        If shipped && $DATA(before("shipped", "i", name)) {
            Do out.skipped.%Push(name _ ": not put back: the earlier release shipped it, and this one does not")
            Continue
        }
        If 'record && 'shipped && ($EXTRACT(class, 1, 8) = "Shutter.") {
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

/// One node (the production's, or an item's): s the capture's, b the definition left, d the record, each with ("p",
/// property) and ("s", target, name); the record also has ("x", target, name) for a setting taken out. o, with no record,
/// is the compiled class's node: a value it has too is the earlier release's, not the site's.
ClassMethod LearnNode(ByRef s, ByRef b, list As %String, record As %Boolean, ByRef d, ByRef o) [ Private ]
{
    For k = 1:1:$LENGTH(list, ",") {
        Set p = $PIECE(list, ",", k)
        Continue:'($DATA(s("p", p), v) # 2)
        Continue:'record && $LISTFIND($LISTFROMSTRING(..#DESCRIPTIVE), p)
        If ($DATA(b("p", p), was) # 2) && (was = v) Continue
        If 'record && ($DATA(o("p", p), was) # 2) && (was = v) Continue
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
            If ($DATA(b("s", t, n), was) # 2) && (was = v) Continue
            If 'record && ($DATA(o("s", t, n), was) # 2) && (was = v) Continue
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
        Continue:$PROPERTY(obj, p) = v
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
                Continue:one.Value = v
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

/// The definition the production's compiled class holds (its XData as last compiled), read as Read reads one; 0 when
/// the class has none.
ClassMethod Shipped(production As %String, Output def) As %Boolean
{
    Kill def
    Set sc = ##class(Ens.Util.XML.Reader).ObjectFromXData(.obj, production, "ProductionDefinition", "Ens.Config.Production")
    Quit:$$$ISERR(sc) 0
    Quit:'$ISOBJECT($GET(obj)) 0
    Quit ..Read(obj, .def)
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
        Continue:(name = "") || $DATA(def("i", name))
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

/// One line for the install's output: what Keep put back, removed and left out, or "" when nothing.
ClassMethod Account(out As %DynamicObject) As %String
{
    Set said = ""
    For list = $LISTBUILD("kept", "the site's values put back: "), $LISTBUILD("restored", "the site's items put back: "), $LISTBUILD("removed", "settings the site took out taken out: "), $LISTBUILD("skipped", "not kept: ") {
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
