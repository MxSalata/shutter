/// Shutter.Util.SiteItems on a scratch production that never runs. An upgrade is played as IPM plays it: the capture, then
/// the class's XData replaced by a newer release's and compiled (which rebuilds the definition from it), then Keep. The
/// site's pool size, enabled flag, settings, a setting it took out and the items it added must stand, while the newer
/// release's item, setting and changed value arrive; and with no record of the earlier install, the narrower rule holds.
/// The scratch production's class and definition and the test's own global go after each test: nothing of Shutter's own
/// production or of ^Shutter.Config is touched.
Class Shutter.Test.SiteItems Extends %UnitTest.TestCase
{

Parameter PRODUCTION = "ShutterTest.SiteItems";

Parameter NODE = "^ShutterTest.SiteItems";

Parameter CLASS = "Shutter.Util.SiteItems";

Method OnBeforeOneTest() As %Status
{
    Do ..RemoveProduction()
    Set node = ..#NODE
    Kill @node
    Quit $$$OK
}

Method OnAfterOneTest() As %Status
{
    Do ..RemoveProduction()
    Set node = ..#NODE
    Kill @node
    Quit $$$OK
}

/// An upgrade with a record of the earlier install: everything the site set stands, everything new arrives, and a later
/// compile, a second install of the same release, a second load and the site's own reversal all come out right.
Method TestUpgradeKeepsTheSitesValues()
{
    Set c = ..#CLASS, prod = ..#PRODUCTION, node = ..#NODE
    Do $$$AssertStatusOK(..WriteClass(..Earlier()), "the earlier release's production compiles")
    Do $$$AssertEquals($CLASSMETHOD(c, "Capture", prod, node, 0), "first install", "a first install captures nothing")
    Do $$$AssertStatusOK($CLASSMETHOD(c, "Keep", prod, node, .out), "the first install keeps")
    Do $$$AssertEquals(out.mode _ "/" _ out.changes, "nothing captured/0", "with nothing to put back")
    Do $$$AssertEquals($DATA(@node@("left")) \ 10, 1, "and records the definition it left")

    Do $$$AssertStatusOK(..SiteEdits(), "the site's own edits save")
    Do $$$AssertEquals($CLASSMETHOD(c, "Capture", prod, node, 1), "captured", "the upgrade captures the site's definition")
    Do $$$AssertStatusOK(..WriteClass(..Newer()), "the newer release's class compiles")
    Do $$$AssertEquals(..Prop("UT Watch", "PoolSize"), 1, "the compile rebuilt the definition: the shipped pool size again (the fault)")
    Do $$$AssertStatusOK($CLASSMETHOD(c, "Keep", prod, node, .out), "the upgrade keeps")
    Do $$$AssertEquals(out.mode, "record", "against the record of the earlier install")
    Do ..SiteKept("after the upgrade")
    Do ..NewArrived("after the upgrade")
    Do $$$AssertEquals(..Value("UT Watch", "Host", "AlertOnError"), "(none)", "the setting the site took out stays out")
    Do $$$AssertEquals(..Prop("UT Gate", "Comment"), "Our gate", "the site's own comment stands")
    Do $$$AssertEquals(..Value("UT Gate", "Host", "FailureTimeout"), 30, "the release's changed value arrives where the site set none")
    Do $$$AssertEquals(..Count("UT Site Own"), 1, "the item of a Shutter class the site added is put back too")
    Do $$$AssertEquals($DATA(@node@("before")), 0, "the capture is used up")
    Set said = $CLASSMETHOD(c, "Account", out)
    Do $$$AssertTrue(said [ "UT Watch: PoolSize 3", "the account names the pool size put back: " _ said)
    Do $$$AssertTrue((said '[ "/tmp/ut-site-out/") && (said '[ "E=W") && (said '[ "Our gate"), "and never a setting's value or a text")

    Do $$$AssertStatusOK($SYSTEM.OBJ.Compile(prod, "ck-d"), "the class compiles again, as a production restart through Shutter does")
    Do ..SiteKept("after the class compiled again: the class holds the definition")

    Do $$$AssertEquals($CLASSMETHOD(c, "Capture", prod, node, 1), "captured", "the same release installed again captures")
    Do $$$AssertStatusOK($CLASSMETHOD(c, "Keep", prod, node, .out), "and keeps")
    Do $$$AssertEquals(out.changes, 0, "changing nothing")
    Do ..SiteKept("after the same release installed again")

    Do $$$AssertEquals($CLASSMETHOD(c, "Capture", prod, node, 1), "captured", "loaded again")
    Do $$$AssertStatusOK(..WriteClass(..Newer()), "the class is the package's again")
    Do $$$AssertEquals(..Prop("UT Watch", "PoolSize"), 1, "which reads the shipped pool size")
    Do $$$AssertStatusOK($CLASSMETHOD(c, "Keep", prod, node, .out), "and keeps")
    Do ..SiteKept("after a second load, with no new edit: from the record")
    Do ..NewArrived("after a second load")

    Set p = ##class(Ens.Config.Production).%OpenId(prod)
    Set w = ..Item(p, "UT Watch"), w.PoolSize = 1
    For i = p.Items.Count():-1:1 {
        Continue:p.Items.GetAt(i).Name'="UT Site Out"
        Set id = p.Items.GetAt(i).%Id()
        Do p.Items.RemoveAt(i)
        Do:id'="" ##class(Ens.Config.Item).%DeleteId(id)
    }
    Do $$$AssertStatusOK(p.%Save(), "the site sets the pool size back to Shutter's and deletes its own item")
    Kill p, w
    Do $$$AssertEquals($CLASSMETHOD(c, "Capture", prod, node, 1), "captured", "the next upgrade captures")
    Do $$$AssertStatusOK(..WriteClass(..Newer()), "the class is the package's again")
    Do $$$AssertStatusOK($CLASSMETHOD(c, "Keep", prod, node, .out), "and keeps")
    Do $$$AssertEquals(..Prop("UT Watch", "PoolSize"), 1, "the site's later choice stands")
    Do $$$AssertEquals(..Count("UT Site Out"), 0, "the item it deleted stays deleted")
    Do $$$AssertEquals($DATA(@node@("site", "i", "UT Site Out")), 0, "and leaves the record")
    Do $$$AssertEquals(..Prop("UT Gate", "Enabled"), 0, "while its other values stand")
}

/// An upgrade over an install that left no record (1.4.8 and earlier): every value that differs is the site's, but the
/// descriptions; nothing counts as taken out; an added item of a Shutter class is left out.
Method TestUpgradeWithNoRecord()
{
    Set c = ..#CLASS, prod = ..#PRODUCTION, node = ..#NODE
    Do $$$AssertStatusOK(..WriteClass(..Earlier()), "the earlier release's production compiles")
    Do $$$AssertStatusOK(..SiteEdits(), "the site's own edits save")
    Do $$$AssertEquals($CLASSMETHOD(c, "Capture", prod, node, 1), "captured", "the upgrade captures")
    Do $$$AssertStatusOK(..WriteClass(..Newer()), "the newer release's class compiles")
    Do $$$AssertStatusOK($CLASSMETHOD(c, "Keep", prod, node, .out), "the upgrade keeps")
    Do $$$AssertEquals(out.mode, "no record", "with no record of the earlier install")
    Do ..SiteKept("with no record", 0)
    Do ..NewArrived("with no record")
    Do $$$AssertEquals(..Prop("UT Gate", "Comment"), "The gate, newer text", "the release's own description stands")
    Do $$$AssertEquals(..Value("UT Gate", "Host", "FailureTimeout"), 0, "a value that differs is taken to be the site's, a change of the release's included")
    Do $$$AssertEquals(..Value("UT Watch", "Host", "AlertOnError"), 1, "nothing counts as taken out")
    Do $$$AssertEquals(..Count("UT Site Own"), 0, "the added item of a Shutter class is left out")
    Do $$$AssertTrue($CLASSMETHOD(c, "Account", out) [ "UT Site Own: not put back", "and the account says so")
    Do $$$AssertEquals($DATA(@node@("left")) \ 10, 1, "the install leaves a record for the next one")
}

/// When a capture is taken, kept or skipped.
Method TestCapture()
{
    Set c = ..#CLASS, prod = ..#PRODUCTION, node = ..#NODE
    Do $$$AssertStatusOK(..WriteClass(..Earlier()), "the production compiles")
    Set now = $CLASSMETHOD(c, "Seconds")
    Set @node@("before") = $LISTBUILD(now - 60, "earlier", 1, 0)
    Do $$$AssertEquals($CLASSMETHOD(c, "Capture", prod, node, 1), "pending", "a capture younger than a day, which no install used, is kept")
    Do $$$AssertEquals($LIST(@node@("before"), 2), "earlier", "as it was")
    Set @node@("before") = $LISTBUILD(now - 90000, "earlier", 1, 0)
    Do $$$AssertEquals($CLASSMETHOD(c, "Capture", prod, node, 1), "captured", "one older than a day is taken again")
    Do $$$AssertEquals($LIST(@node@("before"), 3) _ "/" _ $LIST(@node@("before"), 4), $JOB _ "/1", "by this job, with the definition")
    Do $$$AssertEquals(@node@("before", "i", "UT Watch", "p", "PoolSize"), 1, "which it holds")
    Kill @node
    Do $$$AssertEquals($CLASSMETHOD(c, "Capture", prod, node, 0), "first install", "no install has run: nothing is read")
    Do $$$AssertEquals($DATA(@node@("before")), 1, "only the note that nothing was")
    Kill @node
    Do $$$AssertEquals($CLASSMETHOD(c, "Capture", "ShutterTest.NoSuchProduction", node, 1), "no definition", "no production: nothing to read")
    Do $$$AssertStatusOK($CLASSMETHOD(c, "Keep", "ShutterTest.NoSuchProduction", node, .out), "Keep with no production")
    Do $$$AssertEquals(out.mode, "no production", "does nothing")
    Do $$$AssertEquals($DATA(@node@("before")), 0, "but use up the capture")
}

/// Read's shape.
Method TestRead()
{
    Set c = ..#CLASS
    Do $$$AssertStatusOK(..WriteClass(..Earlier()), "the production compiles")
    Do $$$AssertTrue($CLASSMETHOD(c, "Read", ..#PRODUCTION, .def), "the definition reads")
    Do $$$AssertEquals($GET(def("i", "UT Watch")), "Shutter.Operation.ReceiverWatch", "an item's class")
    Do $$$AssertEquals($GET(def("i", "UT Watch", "p", "PoolSize")), 1, "its pool size")
    Do $$$AssertEquals($GET(def("i", "UT Gate", "p", "LogTraceEvents")), 1, "a flag")
    Do $$$AssertEquals($GET(def("i", "UT Watch", "s", "Adapter", "CallInterval")), 5, "an adapter setting")
    Do $$$AssertEquals($GET(def("p", "p", "ActorPoolSize")), 1, "the production's own property")
    Do $$$AssertNotTrue($CLASSMETHOD(c, "Read", "ShutterTest.NoSuchProduction", .def), "no production reads as none")
    Do $$$AssertEquals($DATA(def), 0, "and leaves nothing")
}

/// The site's values, as SiteEdits made them. withDescriptions 0: the comment is not among them (no record).
Method SiteKept(when As %String, withDescriptions As %Boolean = 1)
{
    Do $$$AssertEquals(..Prop("UT Watch", "PoolSize"), 3, "the site's pool size, " _ when)
    Do $$$AssertEquals(..Value("UT Watch", "Adapter", "CallInterval"), 9, "its adapter setting, " _ when)
    Do $$$AssertEquals(..Prop("UT Gate", "Enabled"), 0, "the item it switched off, " _ when)
    Do $$$AssertEquals(..Value("UT Gate", "Host", "ReplyCodeActions"), "E=W", "the setting it added, " _ when)
    Do $$$AssertEquals(..ProductionProp("ActorPoolSize"), 2, "the production's actor pool, " _ when)
    Do $$$AssertEquals(..Count("UT Site Out"), 1, "the item it added, once, " _ when)
    Do $$$AssertEquals(..Prop("UT Site Out", "ClassName") _ "|" _ ..Value("UT Site Out", "Adapter", "FilePath"), "EnsLib.File.PassthroughOperation|/tmp/ut-site-out/", "with its class and settings, " _ when)
    Do:withDescriptions $$$AssertEquals(..Prop("UT Gate", "Comment"), "Our gate", "its comment, " _ when)
}

/// What the newer release adds.
Method NewArrived(when As %String)
{
    Do $$$AssertEquals(..Count("UT New"), 1, "the release's new item, " _ when)
    Do $$$AssertEquals(..Prop("UT New", "ClassName") _ "|" _ ..Prop("UT New", "PoolSize"), "Shutter.Operation.Verify|1", "as the release ships it, " _ when)
    Do $$$AssertEquals(..Value("UT Watch", "Host", "AlertGracePeriod"), 4, "the release's new setting on an item the site changed, " _ when)
}

/// A site's own edits: on the definition alone (saved, not written to the class), the watch's pool size 3 and its
/// AlertOnError taken out, the gate switched off with a setting added and its comment changed, the production's actor
/// pool 2, and two items added, one of a system class and one of a Shutter class; then, as the Production Configuration
/// page saves (Ens.Production.ApplySettings: the definition and the class's XData), the watch's call interval 9.
Method SiteEdits() As %Status
{
    Set p = ##class(Ens.Config.Production).%OpenId(..#PRODUCTION)
    Quit:'$ISOBJECT(p) $$$ERROR($$$GeneralError, "no scratch production")
    Set p.ActorPoolSize = 2
    Set w = ..Item(p, "UT Watch"), w.PoolSize = 3
    For j = w.Settings.Count():-1:1 {
        If w.Settings.GetAt(j).Name = "AlertOnError" Do w.Settings.RemoveAt(j)
    }
    Set g = ..Item(p, "UT Gate"), g.Enabled = 0, g.Comment = "Our gate"
    Do g.Settings.Insert(..Setting("Host", "ReplyCodeActions", "E=W"))
    For row = $LISTBUILD("UT Site Out", "EnsLib.File.PassthroughOperation", 1), $LISTBUILD("UT Site Own", "Shutter.Operation.Verify", 0) {
        Set i = ##class(Ens.Config.Item).%New()
        Set i.Name = $LIST(row, 1), i.ClassName = $LIST(row, 2), i.PoolSize = 1, i.Enabled = $LIST(row, 3), i.Production = p
        Do:$LIST(row, 3) i.Settings.Insert(..Setting("Adapter", "FilePath", "/tmp/ut-site-out/"))
        Do p.Items.Insert(i)
    }
    Set sc = p.%Save()
    Kill p, w, g, i
    Quit:$$$ISERR(sc) sc
    Set set("UT Watch", "Adapter", "CallInterval") = 9
    Quit ##class(Ens.Production).ApplySettings(..#PRODUCTION, .set)
}

Method Setting(target As %String, name As %String, value As %String) As Ens.Config.Setting
{
    Set s = ##class(Ens.Config.Setting).%New()
    Set s.Target = target, s.Name = name, s.Value = value
    Quit s
}

/// The earlier release's definition.
Method Earlier() As %String
{
    Quit "<Production Name="""_..#PRODUCTION_""" TestingEnabled=""true"" LogGeneralTraceEvents=""false"">"
        _ "<Description>Scratch production for Shutter.Test.SiteItems</Description><ActorPoolSize>1</ActorPoolSize>"
        _ "<Item Name=""UT Watch"" Category=""Recovery"" ClassName=""Shutter.Operation.ReceiverWatch"" PoolSize=""1"" Enabled=""true"" Foreground=""false"" Comment=""The watch, as shipped"" LogTraceEvents=""false"" Schedule="""">"
        _ "<Setting Target=""Adapter"" Name=""CallInterval"">5</Setting><Setting Target=""Host"" Name=""AlertOnError"">1</Setting></Item>"
        _ "<Item Name=""UT Gate"" Category=""Recovery"" ClassName=""Shutter.Operation.Gate"" PoolSize=""1"" Enabled=""true"" Foreground=""false"" Comment=""The gate, as shipped"" LogTraceEvents=""true"" Schedule="""">"
        _ "<Setting Target=""Host"" Name=""FailureTimeout"">0</Setting></Item>"
        _ "</Production>"
}

/// The newer release's: a setting new on the watch, the gate's failure timeout and comment changed, an item new.
Method Newer() As %String
{
    Quit "<Production Name="""_..#PRODUCTION_""" TestingEnabled=""true"" LogGeneralTraceEvents=""false"">"
        _ "<Description>Scratch production for Shutter.Test.SiteItems</Description><ActorPoolSize>1</ActorPoolSize>"
        _ "<Item Name=""UT Watch"" Category=""Recovery"" ClassName=""Shutter.Operation.ReceiverWatch"" PoolSize=""1"" Enabled=""true"" Foreground=""false"" Comment=""The watch, as shipped"" LogTraceEvents=""false"" Schedule="""">"
        _ "<Setting Target=""Adapter"" Name=""CallInterval"">5</Setting><Setting Target=""Host"" Name=""AlertOnError"">1</Setting><Setting Target=""Host"" Name=""AlertGracePeriod"">4</Setting></Item>"
        _ "<Item Name=""UT Gate"" Category=""Recovery"" ClassName=""Shutter.Operation.Gate"" PoolSize=""1"" Enabled=""true"" Foreground=""false"" Comment=""The gate, newer text"" LogTraceEvents=""true"" Schedule="""">"
        _ "<Setting Target=""Host"" Name=""FailureTimeout"">30</Setting></Item>"
        _ "<Item Name=""UT New"" Category=""Recovery"" ClassName=""Shutter.Operation.Verify"" PoolSize=""1"" Enabled=""true"" Foreground=""false"" Comment=""New in this release"" LogTraceEvents=""false"" Schedule=""""></Item>"
        _ "</Production>"
}

/// The scratch class with this definition in its XData, compiled: the engine's projection rebuilds the definition from
/// it, as when IPM reloads and compiles Shutter.Production.
Method WriteClass(xml As %String) As %Status
{
    Set name = ..#PRODUCTION
    Set cd = ##class(%Dictionary.ClassDefinition).%OpenId(name)
    If '$ISOBJECT(cd) Set cd = ##class(%Dictionary.ClassDefinition).%New(name), cd.Super = "Ens.Production"
    Set k = cd.XDatas.FindObjectId(name _ "||ProductionDefinition")
    Do:k'="" cd.XDatas.RemoveAt(k)
    Set x = ##class(%Dictionary.XDataDefinition).%New()
    Set x.Name = "ProductionDefinition", x.parent = cd
    Do x.Data.Write(xml)
    Set sc = cd.%Save()
    Kill cd, x
    Quit:$$$ISERR(sc) sc
    Quit $SYSTEM.OBJ.Compile(name, "ck-d")
}

Method RemoveProduction()
{
    Set p = ##class(Ens.Config.Production).%OpenId(..#PRODUCTION)
    If $ISOBJECT(p) {
        For i = p.Items.Count():-1:1 {
            Set id = p.Items.GetAt(i).%Id()
            Do p.Items.RemoveAt(i)
            Do:id'="" ##class(Ens.Config.Item).%DeleteId(id)
        }
        Kill p
        Do ##class(Ens.Config.Production).%DeleteId(..#PRODUCTION)
    }
    If ##class(%Dictionary.ClassDefinition).%ExistsId(..#PRODUCTION) Do $SYSTEM.OBJ.Delete(..#PRODUCTION, "-d")
}

Method Item(p As Ens.Config.Production, name As %String) As Ens.Config.Item
{
    For i = 1:1:p.Items.Count() { If p.Items.GetAt(i).Name = name Return p.Items.GetAt(i) }
    Quit ""
}

/// An item's property, or "(no item)".
Method Prop(name As %String, property As %String) As %String
{
    Set p = ##class(Ens.Config.Production).%OpenId(..#PRODUCTION, 0)
    Quit:'$ISOBJECT(p) "(no production)"
    Set item = ..Item(p, name)
    Quit:'$ISOBJECT(item) "(no item)"
    Quit $PROPERTY(item, property)
}

Method ProductionProp(property As %String) As %String
{
    Set p = ##class(Ens.Config.Production).%OpenId(..#PRODUCTION, 0)
    Quit:'$ISOBJECT(p) "(no production)"
    Quit $PROPERTY(p, property)
}

/// An item's setting, or "(none)".
Method Value(name As %String, target As %String, setting As %String) As %String
{
    Set p = ##class(Ens.Config.Production).%OpenId(..#PRODUCTION, 0)
    Quit:'$ISOBJECT(p) "(no production)"
    Set item = ..Item(p, name)
    Quit:'$ISOBJECT(item) "(no item)"
    For j = 1:1:item.Settings.Count() {
        Set s = item.Settings.GetAt(j)
        Return:((s.Target = target) && (s.Name = setting)) s.Value
    }
    Quit "(none)"
}

/// How many items of that name the definition has.
Method Count(name As %String) As %Integer
{
    Set p = ##class(Ens.Config.Production).%OpenId(..#PRODUCTION, 0), n = 0
    Quit:'$ISOBJECT(p) 0
    For i = 1:1:p.Items.Count() Set:p.Items.GetAt(i).Name=name n = n + 1
    Quit n
}

}
