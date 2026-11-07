/// Which item a case's receiver names and whether that item has the stock HL7 TCP operation's delivery semantics
/// (Shutter.Util.EngineScope). A production definition here is data: read from a class's XData into memory, or saved
/// under a made-up name for the test and deleted after it.
Class Shutter.Test.EngineScope Extends %UnitTest.TestCase
{

Parameter SCOPE = "Shutter.Util.EngineScope";

Parameter SAVED = "Shutter.Test.ScopeProduction";

Property Headers As %List;

/// The items the oracle's laboratory production opens with, as tests/e2e/pathology_site/OraLab.Production.cls has them.
XData OraLabItems [ MimeType = application/xml ]
{
<Production Name="OraLab.Production" TestingEnabled="false" LogGeneralTraceEvents="false">
  <ActorPoolSize>1</ActorPoolSize>
  <Item Name="Larkspur In" ClassName="EnsLib.HL7.Service.TCPService" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="Port">7501</Setting>
    <Setting Target="Host" Name="TargetConfigNames">Larkspur Out</Setting>
  </Item>
  <Item Name="Larkspur Out" ClassName="EnsLib.HL7.Operation.TCPOperation" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="IPAddress">127.0.0.1</Setting>
    <Setting Target="Adapter" Name="Port">7401</Setting>
    <Setting Target="Host" Name="FailureTimeout">-1</Setting>
  </Item>
  <Item Name="Quillon O4 Out" ClassName="EnsLib.HL7.Operation.TCPOperation" PoolSize="1" Enabled="true">
    <Setting Target="Host" Name="FailureTimeout">0</Setting>
  </Item>
</Production>
}

/// One item per answer, the prefixed name's item and names that fit twice.
XData ScopeItems [ MimeType = application/xml ]
{
<Production Name="Shutter.Test.ScopeProduction" TestingEnabled="false" LogGeneralTraceEvents="false">
  <ActorPoolSize>1</ActorPoolSize>
  <Item Name="Stock" ClassName="EnsLib.HL7.Operation.TCPOperation" PoolSize="1" Enabled="true"/>
  <Item Name="Plain Sub" ClassName="Shutter.Test.ScopeTcpPlain" PoolSize="1" Enabled="true"/>
  <Item Name="Own Reply" ClassName="Shutter.Test.ScopeTcpReply" PoolSize="1" Enabled="true"/>
  <Item Name="Own Timeout" ClassName="Shutter.Test.ScopeTcpTimeout" PoolSize="1" Enabled="true"/>
  <Item Name="Own Adapter" ClassName="Shutter.Test.ScopeTcpAdapter" PoolSize="1" Enabled="true"/>
  <Item Name="Http Out" ClassName="Hospital.Operation.DownstreamOut" PoolSize="1" Enabled="true"/>
  <Item Name="Ward Out" ClassName="Shutter.Operation.Ward" PoolSize="1" Enabled="true"/>
  <Item Name="Gone" ClassName="Shutter.Test.ScopeNoSuchClass" PoolSize="1" Enabled="true"/>
  <Item Name="Fan One" ClassName="EnsLib.HL7.Operation.TCPOperation" PoolSize="1" Enabled="true"/>
  <Item Name="Twin Out" ClassName="EnsLib.HL7.Operation.TCPOperation" PoolSize="1" Enabled="true"/>
  <Item Name="PRE Twin Out" ClassName="EnsLib.HL7.Operation.TCPOperation" PoolSize="1" Enabled="true"/>
  <Item Name="Off Only" ClassName="EnsLib.HL7.Operation.TCPOperation" PoolSize="1" Enabled="false"/>
  <Item Name="Pair" ClassName="EnsLib.HL7.Operation.TCPOperation" PoolSize="1" Enabled="false"/>
  <Item Name="Pair" ClassName="Shutter.Operation.Ward" PoolSize="1" Enabled="true"/>
  <Item Name="Both On" ClassName="EnsLib.HL7.Operation.TCPOperation" PoolSize="1" Enabled="true"/>
  <Item Name="Both On" ClassName="Shutter.Operation.Ward" PoolSize="1" Enabled="true"/>
  <Item Name="Both Off" ClassName="EnsLib.HL7.Operation.TCPOperation" PoolSize="1" Enabled="false"/>
  <Item Name="Both Off" ClassName="Shutter.Operation.Ward" PoolSize="1" Enabled="false"/>
</Production>
}

Method OnBeforeOneTest(testname As %String) As %Status
{
    Do ##class(Ens.Config.Production).%DeleteId(..#SAVED)
    Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
    Do ##class(Ens.Config.Production).%DeleteId(..#SAVED)
    For i = 1:1:$LISTLENGTH(..Headers) Do ##class(Ens.MessageHeader).%DeleteId($LIST(..Headers, i))
    Set ..Headers = ""
    Quit $$$OK
}

/// A production definition held in memory, from a class's XData block.
Method Production(class As %String, xdata As %String) As Ens.Config.Production
{
    Set block = ##class(%Dictionary.CompiledXData).%OpenId(class _ "||" _ xdata, 0)
    Do $$$AssertTrue($ISOBJECT(block), class _ " has " _ xdata)
    Set reader = ##class(%XML.Reader).%New()
    Do $$$AssertStatusOK(reader.OpenStream(block.Data), xdata _ " opens")
    Do reader.Correlate("Production", "Ens.Config.Production")
    Set production = ""
    Do reader.Next(.production, .sc)
    Do $$$AssertTrue($ISOBJECT(production), xdata _ " reads as a production")
    Quit production
}

Method Scope() As Ens.Config.Production
{
    Quit ..Production($CLASSNAME(), "ScopeItems")
}

Method Header(target As %String, type As %Integer) As %String
{
    Set header = ##class(Ens.MessageHeader).%New()
    Set header.SessionId = 1, header.SourceConfigName = "Scope In", header.TargetConfigName = target
    Set header.TargetBusinessType = type
    Do $$$AssertStatusOK(header.%Save(), "the header saves")
    Set ..Headers = ..Headers _ $LISTBUILD(header.%Id())
    Quit header.%Id()
}

Method Case(receiver As %String, origin As %String = "", production As %String = "") As Shutter.Store.Case
{
    Set case = ##class(Shutter.Store.Case).%New()
    Set case.Receiver = receiver, case.OriginHeaderId = origin, case.SourceProduction = production, case.SourceNamespace = $NAMESPACE
    Quit case
}

/// ItemOf's last three steps as a table.
Method TestItemFromADefinition()
{
    Set s = ..#SCOPE, p = ..Scope()
    Do $$$AssertEquals($CLASSMETHOD(s, "ItemFrom", p, "Stock", "Ward Out"), "Stock", "a watch block's item comes before the receiver's name")
    Do $$$AssertEquals($CLASSMETHOD(s, "ItemFrom", p, "No Such", "Stock"), "unreadable", "a watch block's item the production doesn't hold is unreadable")
    Do $$$AssertEquals($CLASSMETHOD(s, "ItemFrom", p, "", "Stock"), "Stock", "a bare receiver name")
    Do $$$AssertEquals($CLASSMETHOD(s, "ItemFrom", p, "", "FANOUT Fan One"), "Fan One", "a prefixed name")
    Do $$$AssertEquals($CLASSMETHOD(s, "ItemFrom", p, "", "PRE Twin Out"), "unreadable", "a name fitting two items")
    Do $$$AssertEquals($CLASSMETHOD(s, "ItemFrom", p, "", "Nobody Here"), "unreadable", "a name fitting nothing")
    Do $$$AssertEquals($CLASSMETHOD(s, "ItemFrom", p, "", "Nobody"), "unreadable", "one word fitting nothing")
    Do $$$AssertEquals($CLASSMETHOD(s, "ItemFrom", p, "", ""), "unreadable", "no receiver")
    Do $$$AssertEquals($CLASSMETHOD(s, "ItemFrom", "", "", "Stock"), "unreadable", "no definition")
    Do $$$AssertEquals($CLASSMETHOD(s, "ItemFrom", "", "Stock", "Stock"), "unreadable", "no definition, with a watch block")
}

Method TestWatchItem()
{
    Set s = ..#SCOPE
    Do $$$AssertEquals($CLASSMETHOD(s, "WatchItem", ""), "", "the profile doesn't name the receiver")
    Do $$$AssertEquals($CLASSMETHOD(s, "WatchItem", {"name": "A"}), "", "no watch block")
    Do $$$AssertEquals($CLASSMETHOD(s, "WatchItem", {"watch": {}}), "", "a watch block naming no item")
    Do $$$AssertEquals($CLASSMETHOD(s, "WatchItem", {"watch": "A"}), "", "a watch that isn't a block")
    Do $$$AssertEquals($CLASSMETHOD(s, "WatchItem", {"watch": {"item": "A Out"}}), "A Out", "its item")
}

/// ItemOf itself, in this namespace, from a case: the header comes first, then the saved definition.
Method TestItemOfFromACase()
{
    Set s = ..#SCOPE, ns = $NAMESPACE, saved = ..#SAVED
    Do $$$AssertStatusOK(..Scope().%Save(), "the definition saves")
    Set toOperation = ..Header("Header Target", 3)
    Set toProcess = ..Header("A Router", 2)
    Do $$$AssertEquals($CLASSMETHOD(s, "ItemOf", ns, ..Case("Stock", toOperation, saved)), "Header Target", "an origin header to an operation comes first")
    Do $$$AssertEquals($CLASSMETHOD(s, "ItemOf", ns, ..Case("Stock", toOperation, "No.Such.Production")), "Header Target", "and needs no definition")
    Do $$$AssertEquals($CLASSMETHOD(s, "ItemOf", ns, ..Case("Stock", toProcess, saved)), "Stock", "an origin header to a process falls through to the name")
    Do $$$AssertEquals($CLASSMETHOD(s, "ItemOf", ns, ..Case("Stock", "99999999", saved)), "Stock", "a purged origin header falls through")
    Do $$$AssertEquals($CLASSMETHOD(s, "ItemOf", ns, ..Case("FANOUT Fan One", "", saved)), "Fan One", "a prefixed name against the saved definition")
    Do $$$AssertEquals($CLASSMETHOD(s, "ItemOf", ns, ..Case("PRE Twin Out", "", saved)), "unreadable", "a name fitting two items")
    Do $$$AssertEquals($CLASSMETHOD(s, "ItemOf", ns, ..Case("Nobody Here", "", saved)), "unreadable", "nothing fitting")
    Do $$$AssertEquals($CLASSMETHOD(s, "ItemOf", ns, ..Case("Stock", "", "No.Such.Production")), "unreadable", "a source production that isn't there")
    Do $$$AssertEquals($CLASSMETHOD(s, "ItemOf", "SHUTTERNOSUCHNS", ..Case("Stock", toOperation, saved)), "unreadable", "a namespace that can't be entered")
    Do $$$AssertEquals($CLASSMETHOD(s, "ItemOf", "", ..Case("Stock", "", saved)), "unreadable", "no namespace")
    Do $$$AssertEquals($CLASSMETHOD(s, "ItemOf", ns, ""), "unreadable", "no case")
}

/// A watch block in the stored profile reaches ItemOf. The row is written directly: what a profile may hold is the
/// profile's own validator's business, and tested there.
Method TestItemOfFromAWatchBlock()
{
    Set sp = "Shutter.Store.SiteProfile", s = ..#SCOPE, saved = ..#SAVED
    Do $$$AssertStatusOK(..Scope().%Save(), "the definition saves")
    Set row = $CLASSMETHOD(sp, "Row"), had = $ISOBJECT(row)
    If 'had {
        Do $$$AssertStatusOK($CLASSMETHOD(sp, "Store", $CLASSMETHOD(sp, "Default").%ToJSON(), "test", "test", "", .v), "a profile to change")
        Set row = $CLASSMETHOD(sp, "Row")
    }
    Set before = row.Json
    Set p = {}.%FromJSON(before)
    If '$ISOBJECT(p.receivers) Set p.receivers = []
    Do p.receivers.%Push({"name": "Scope Receiver", "watch": {"item": "Plain Sub"}})
    Set row.Json = p.%ToJSON()
    Do $$$AssertStatusOK(row.%Save(), "the watch block is stored")
    Set answer = $CLASSMETHOD(s, "ItemOf", $NAMESPACE, ..Case("Scope Receiver", "", saved))
    Set row.Json = before
    Do $$$AssertStatusOK(row.%Save(), "the profile is put back")
    Do $$$AssertEquals(answer, "Plain Sub", "the receiver's watch.item")
}

/// All four answers from the class, on what this build has compiled.
Method TestClassAnswers()
{
    Set s = ..#SCOPE
    Do $$$AssertEquals($CLASSMETHOD(s, "ClassAnswer", "EnsLib.HL7.Operation.TCPOperation"), "yes", "the stock class")
    Do $$$AssertEquals($CLASSMETHOD(s, "ClassAnswer", "Shutter.Test.ScopeTcpPlain"), "yes", "a subclass adding nothing relevant")
    Do $$$AssertEquals($CLASSMETHOD(s, "ClassAnswer", "Shutter.Test.ScopeTcpReply"), "base", "a subclass with its own OnGetReplyAction")
    Do $$$AssertEquals($CLASSMETHOD(s, "ClassAnswer", "Shutter.Test.ScopeTcpTimeout"), "base", "a subclass changing FailureTimeout's default")
    Do $$$AssertEquals($CLASSMETHOD(s, "ClassAnswer", "Shutter.Test.ScopeTcpAdapter"), "base", "a subclass on another adapter")
    Do $$$AssertEquals($CLASSMETHOD(s, "ClassAnswer", "Hospital.Operation.DownstreamOut"), "no", "the demo's HTTP operation, S19's target")
    Do $$$AssertEquals($CLASSMETHOD(s, "ClassAnswer", "Shutter.Operation.Ward"), "no", "Shutter's own operation")
    Do $$$AssertEquals($CLASSMETHOD(s, "ClassAnswer", "EnsLib.HL7.Service.TCPService"), "no", "a stock service")
    Do $$$AssertEquals($CLASSMETHOD(s, "ClassAnswer", "Shutter.Test.ScopeNoSuchClass"), "unreadable", "a class that isn't there")
    Do $$$AssertEquals($CLASSMETHOD(s, "ClassAnswer", ""), "unreadable", "no class")
}

/// A class with a definition and nothing compiled reads as unreadable, even though it says what it extends.
Method TestClassDefinedAndNotCompiled()
{
    Set name = "Shutter.Test.ScopeNotCompiled"
    Do ##class(%Dictionary.ClassDefinition).%DeleteId(name)
    Set def = ##class(%Dictionary.ClassDefinition).%New()
    Set def.Name = name, def.Super = "EnsLib.HL7.Operation.TCPOperation"
    Do $$$AssertStatusOK(def.%Save(), "the definition saves")
    Set answer = $CLASSMETHOD(..#SCOPE, "ClassAnswer", name)
    Do ##class(%Dictionary.ClassDefinition).%DeleteId(name)
    Do $$$AssertEquals(answer, "unreadable", "not compiled")
}

/// Every item of a definition, as a table.
Method TestAnswersFromADefinition()
{
    Set s = ..#SCOPE, p = ..Scope()
    For row = $LISTBUILD("Stock", "yes"), $LISTBUILD("Plain Sub", "yes"), $LISTBUILD("Own Reply", "base"), $LISTBUILD("Own Timeout", "base"), $LISTBUILD("Own Adapter", "base"), $LISTBUILD("Http Out", "no"), $LISTBUILD("Ward Out", "no"), $LISTBUILD("Gone", "unreadable"), $LISTBUILD("No Such Item", "unreadable"), $LISTBUILD("", "unreadable"), $LISTBUILD("Off Only", "yes"), $LISTBUILD("Pair", "no"), $LISTBUILD("Both On", "unreadable"), $LISTBUILD("Both Off", "unreadable") {
        Do $$$AssertEquals($CLASSMETHOD(s, "AnswerIn", p, $LIST(row, 1)), $LIST(row, 2), "item '" _ $LIST(row, 1) _ "'")
    }
    Do $$$AssertEquals($CLASSMETHOD(s, "AnswerIn", "", "Stock"), "unreadable", "no definition")
}

/// Only a running production's definition counts.
Method TestProductionStates()
{
    Set s = ..#SCOPE, saved = ..#SAVED
    Do $$$AssertStatusOK(..Scope().%Save(), "the definition saves")
    Do $$$AssertEquals($CLASSMETHOD(s, "AnswerFor", saved, 1, "Stock"), "yes", "running")
    Do $$$AssertEquals($CLASSMETHOD(s, "AnswerFor", saved, 1, "Http Out"), "no", "running, another class")
    For state = 2, 3, 4, 5, 6, "" {
        Do $$$AssertEquals($CLASSMETHOD(s, "AnswerFor", saved, state, "Stock"), "unreadable", "state '" _ state _ "'")
    }
    Do $$$AssertEquals($CLASSMETHOD(s, "AnswerFor", "No.Such.Production", 1, "Stock"), "unreadable", "a missing production")
    Do $$$AssertEquals($CLASSMETHOD(s, "AnswerFor", "", 2, "Stock"), "unreadable", "no production has run")
}

Method TestNothingToRead()
{
    Set s = ..#SCOPE
    Do $$$AssertEquals($CLASSMETHOD(s, "IsStockTcp", "SHUTTERNOSUCHNS", "Stock"), "unreadable", "a namespace that can't be entered")
    Do $$$AssertEquals($CLASSMETHOD(s, "IsStockTcp", "", "Stock"), "unreadable", "no namespace")
    Do $$$AssertEquals($CLASSMETHOD(s, "IsStockTcp", $NAMESPACE, ""), "unreadable", "no item")
    Do $$$AssertEquals($CLASSMETHOD(s, "IsStockTcp", $NAMESPACE, "unreadable"), "unreadable", "ItemOf's unreadable passed on")
    Do $$$AssertEquals($CLASSMETHOD(s, "IsStockTcp", $NAMESPACE, "Shutter Test No Such Item"), "unreadable", "an item the namespace's production doesn't hold")
}

/// The demo's own production, as data: S19's target reads no, so the gate's check never runs there.
Method TestTheDemoHospital()
{
    Set s = ..#SCOPE, p = ..Production("Hospital.Production", "ProductionDefinition")
    Do $$$AssertEquals($CLASSMETHOD(s, "ItemFrom", p, "", "Downstream Out"), "Downstream Out", "S19's receiver is an item")
    Do $$$AssertEquals($CLASSMETHOD(s, "AnswerIn", p, "Downstream Out"), "no", "S19's shape: an HTTP operation")
    Do $$$AssertEquals($CLASSMETHOD(s, "AnswerIn", p, "PAS In"), "no", "a service")
    Do $$$AssertEquals($CLASSMETHOD(s, "AnswerIn", p, "PAS to Downstream"), "no", "a process")
    Do $$$AssertEquals($CLASSMETHOD(s, "ItemFrom", p, "", "Not In Hospital"), "unreadable", "a receiver the hospital doesn't have")
}

/// The oracle's laboratory production, as data: stock TCP operations read yes.
Method TestTheLaboratoryRig()
{
    Set s = ..#SCOPE, p = ..Production($CLASSNAME(), "OraLabItems")
    Do $$$AssertEquals($CLASSMETHOD(s, "ItemFrom", p, "", "Larkspur Out"), "Larkspur Out", "a receiver named as its item")
    Do $$$AssertEquals($CLASSMETHOD(s, "ItemFrom", p, "", "LAB Quillon O4 Out"), "Quillon O4 Out", "with a prefix")
    Do $$$AssertEquals($CLASSMETHOD(s, "AnswerIn", p, "Larkspur Out"), "yes", "a retrying stock operation")
    Do $$$AssertEquals($CLASSMETHOD(s, "AnswerIn", p, "Quillon O4 Out"), "yes", "a no-retry stock operation")
    Do $$$AssertEquals($CLASSMETHOD(s, "AnswerIn", p, "Larkspur In"), "no", "its service")
}

/// IsStockTcp itself, on what this instance is running. A stock USER runs Shutter's own production, whose ward item is
/// no; where nothing runs the answer is unreadable.
Method TestThisInstance()
{
    Set s = ..#SCOPE, name = "", state = ""
    Do ##class(Ens.Director).GetProductionStatus(.name, .state)
    If (state = 1) && (name = "Shutter.Production") {
        Do $$$AssertEquals($CLASSMETHOD(s, "IsStockTcp", $NAMESPACE, "Downstream Out"), "no", "Shutter's ward item, running")
    } ElseIf state '= 1 {
        Do $$$AssertEquals($CLASSMETHOD(s, "IsStockTcp", $NAMESPACE, "Downstream Out"), "unreadable", "nothing running")
    } Else {
        Do $$$LogMessage("a site's production runs here: " _ name)
    }
}

}
