/// The engine's reads (Shutter.Util.EngineRead): each choice as a table with no instance behind it, then each read on real rows in
/// this namespace, and what each answers where it can't read. A live retrying operation is played on the onboarding rig, not here.
Class Shutter.Test.EngineRead Extends %UnitTest.TestCase
{

/// An item of Shutter's own production that holds no traffic while the tests run, to read a live item's state and settings.
Parameter ITEM = "Gate";

Property Headers As %List;

Property Logs As %List;

Property Bodies As %List;

Method OnAfterAllTests() As %Status
{
    For i = 1:1:$LISTLENGTH(..Headers) {
        Do ##class(Ens.MessageHeader).%DeleteId($LIST(..Headers, i))
    }
    For i = 1:1:$LISTLENGTH(..Logs) {
        Do ##class(Ens.Util.Log).%DeleteId($LIST(..Logs, i))
    }
    For i = 1:1:$LISTLENGTH(..Bodies) {
        Do ##class(EnsLib.HL7.Message).%DeleteId($LIST(..Bodies, i))
    }
    Quit $$$OK
}

/// A session number no real session has.
ClassMethod Session() As %Integer
{
    Quit 900000000000 + $INCREMENT(^CacheTempShutterEngineRead)
}

Method Body() As %String
{
    Set msg = ##class(EnsLib.HL7.Message).ImportFromString("MSH|^~\&|OCS|HOSP|APP|HOSP|20261105000000||ORM^O01|C" _ $RANDOM(1000000) _ "|P|2.5.1" _ $CHAR(13))
    Do msg.%Save()
    Set ..Bodies = ..Bodies _ $LISTBUILD(msg.%Id())
    Quit msg.%Id()
}

/// A header, saved, with the status as the stock enumeration stores it.
Method Header(session As %Integer, target As %String, body As %String, resent As %Integer = 0, description As %String = "", word As %String = "Error", processed As %String = "") As %String
{
    Set h = ##class(Ens.MessageHeader).%New()
    Set h.SessionId = session, h.SourceConfigName = "UT Source", h.TargetConfigName = target
    Set h.MessageBodyClassName = "EnsLib.HL7.Message", h.MessageBodyId = body
    Set h.Resent = resent, h.Description = description
    Set h.Status = ##class(Ens.DataType.MessageStatus).DisplayToLogical(word), h.TimeCreated = $ZDATETIME($ZTIMESTAMP, 3, 1, 3)
    Set:processed'="" h.TimeProcessed = processed
    Do h.%Save()
    Set ..Headers = ..Headers _ $LISTBUILD(h.%Id())
    Quit h.%Id()
}

/// A row of the event log, saved.
Method Log(session As %Integer, message As %String, type As %Integer, text As %String, config As %String = "UT Out") As %String
{
    Set l = ##class(Ens.Util.Log).%New()
    Set l.SessionId = session, l.MessageId = message, l.Type = type, l.Text = text, l.ConfigName = config
    Set l.TimeLogged = $ZDATETIME($ZTIMESTAMP, 3, 1, 3), l.SourceClass = "UT", l.SourceMethod = "UT"
    Do l.%Save()
    Set ..Logs = ..Logs _ $LISTBUILD(l.%Id())
    Quit l.%Id()
}

/// A row as Query gives it, for a table.
ClassMethod Row(id, type, text, message, config) As %DynamicObject
{
    Quit {"ID": (id), "Type": (type), "Text": (text), "MessageId": (message), "ConfigName": (config), "TimeLogged": "2026-11-07 01:00:00.000"}
}

ClassMethod Ids(answer As %DynamicObject) As %String
{
    Set out = ""
    Set iter = answer.rows.%GetIterator()
    While iter.%GetNext(.i, .r) { Set out = out _ $SELECT(out '= "": ",", 1: "") _ r.id }
    Quit out
}

Method TestLogRowsKeepsTheHeadersOwnRowsAndAnyItCantPlace()
{
    Set er = "Shutter.Util.EngineRead"
    Set rows = [(..Row(1, 2, "ErrOutConnectExpired", 17, "LIMS Out")), (..Row(2, 6, "ErrOutConnectExpired (alert request ID=9)", "17", "LIMS Out")), (..Row(3, 2, "another message's", 18, "LIMS Out"))]
    Do rows.%Push(..Row(4, 2, "no message, this item's job", "", "LIMS Out"))
    Do rows.%Push(..Row(5, 2, "no message, words naming LIMS Out", 0, "Path Router"))
    Do rows.%Push(..Row(6, 2, "no message, another item's", "", "Path Router"))
    Set got = $CLASSMETHOD(er, "LogRowsOf", rows, 17, "LIMS Out")
    Do $$$AssertEquals(got.answer, "ok", "a read")
    Do $$$AssertEquals(..Ids(got), "1,2,4,5", "its own rows, and those with no message that name its item")
    Do $$$AssertEquals(got.rows.%Get(0).type, 2, "the type as a number")
    Do $$$AssertEquals(got.rows.%Get(2).messageId, "", "a row with no message says so")
    Do $$$AssertEquals(got.rows.%Get(3).messageId, "", "a message id of 0 is no message")
    Set none = $CLASSMETHOD(er, "LogRowsOf", [], 17, "LIMS Out")
    Do $$$AssertEquals(none.answer _ "|" _ none.rows.%Size(), "ok|0", "read and empty is ok with an empty list")
}

Method TestChooseDelivery()
{
    Set er = "Shutter.Util.EngineRead", item = "LIMS Out"
    Set a = {"ID": 30, "MessageBodyClassName": "EnsLib.HL7.Message", "MessageBodyId": 7, "Resent": 0, "Description": ""}
    Set got = $CLASSMETHOD(er, "ChooseDelivery", [(a)], item, 1)
    Do $$$AssertEquals(got.answer _ "|" _ got.headerId _ "|" _ got.via, "found|30|session", "an original at Resent 0")
    Set got = $CLASSMETHOD(er, "ChooseDelivery", [{"ID": 30, "MessageBodyClassName": "EnsLib.HL7.Message", "MessageBodyId": 7, "Resent": "", "Description": ""}], item, 1)
    Do $$$AssertEquals(got.headerId, 30, "Resent empty is an original")
    Set clone1 = {"ID": 31, "MessageBodyClassName": "EnsLib.HL7.Message", "MessageBodyId": 7, "Resent": 1, "Description": "Resent 30"}
    Set got = $CLASSMETHOD(er, "ChooseDelivery", [(clone1), (a)], item, 1)
    Do $$$AssertEquals(got.headerId, 30, "a clone at Resent 1 is skipped")
    Set clone0 = {"ID": 32, "MessageBodyClassName": "EnsLib.HL7.Message", "MessageBodyId": 7, "Resent": 0, "Description": "Resent 30"}
    Set got = $CLASSMETHOD(er, "ChooseDelivery", [(clone0), (clone1), (a)], item, 1)
    Do $$$AssertEquals(got.headerId, 30, "a clone at Resent 0 with its description is skipped")
    Set got = $CLASSMETHOD(er, "ChooseDelivery", [{"ID": 33, "MessageBodyClassName": "EnsLib.HL7.Message", "MessageBodyId": 7, "Resent": 0, "Description": "Resending today"}], item, 1)
    Do $$$AssertEquals(got.headerId, 33, "a description that only starts alike is no clone's")
}

Method TestChooseDeliveryTwoBodiesAndNone()
{
    Set er = "Shutter.Util.EngineRead", item = "LIMS Out"
    Set a = {"ID": 30, "MessageBodyClassName": "EnsLib.HL7.Message", "MessageBodyId": 7, "Resent": 0, "Description": ""}
    Set same = {"ID": 34, "MessageBodyClassName": "EnsLib.HL7.Message", "MessageBodyId": 7, "Resent": 0, "Description": ""}
    Set got = $CLASSMETHOD(er, "ChooseDelivery", [(same), (a)], item, 1)
    Do $$$AssertEquals(got.answer _ "|" _ got.headerId, "found|34", "two with one body: the newest")
    Set other = {"ID": 35, "MessageBodyClassName": "EnsLib.HL7.Message", "MessageBodyId": 8, "Resent": 0, "Description": ""}
    Set got = $CLASSMETHOD(er, "ChooseDelivery", [(other), (a)], item, 1)
    Do $$$AssertEquals(got.answer, "unreadable", "two with different bodies")
    Do $$$AssertTrue(got.why [ "more than one message", "and says why")
    Set got = $CLASSMETHOD(er, "ChooseDelivery", [], item, 1)
    Do $$$AssertEquals(got.answer, "unreadable", "none")
    Set got = $CLASSMETHOD(er, "ChooseDelivery", [{"ID": 31, "MessageBodyClassName": "EnsLib.HL7.Message", "MessageBodyId": 7, "Resent": 1, "Description": "Resent 30"}], item, 1)
    Do $$$AssertEquals(got.answer, "unreadable", "only clones")
}

Method TestCustodyTable()
{
    Set er = "Shutter.Util.EngineRead"
    // word, item status, enabled, head, active, answer, carried by
    For row = $LB("Queued", "OK", 1, 0, 0, "engine", "status"), $LB("Delivered", "Retry", 1, 1, 1, "engine", "status,retry,head,active"), $LB("Completed", "OK", 1, 0, 0, "delivered", ""), $LB("Completed", "Retry", 1, 0, 0, "engine", "retry"), $LB("Error", "OK", 1, 0, 0, "settled", ""), $LB("Error", "Error", 1, 0, 0, "settled", ""), $LB("Error", "Retry", 1, 0, 0, "engine", "retry"), $LB("Suspended", "OK", 1, 0, 0, "settled", ""), $LB("Suspended", "Disabled", 0, 0, 0, "engine", "disabled"), $LB("Completed", "Disabled", 0, 0, 0, "engine", "disabled"), $LB("Error", "OK", 1, 1, 0, "engine", "head"), $LB("Error", "OK", 1, 0, 1, "engine", "active"), $LB("Discarded", "OK", 1, 0, 0, "unreadable", ""), $LB("Aborted", "OK", 1, 0, 0, "unreadable", ""), $LB("Deferred", "OK", 1, 0, 0, "unreadable", ""), $LB("Created", "OK", 1, 0, 0, "unreadable", ""), $LB("", "OK", 1, 0, 0, "unreadable", "") {
        Set got = $CLASSMETHOD(er, "CustodyAnswer", $LIST(row, 1), $LIST(row, 2), $LIST(row, 3), $LIST(row, 4), $LIST(row, 5))
        Set carried = ""
        Set iter = got.carriedBy.%GetIterator()
        While iter.%GetNext(.i, .c) { Set carried = carried _ $SELECT(carried '= "": ",", 1: "") _ c }
        Do $$$AssertEquals(got.answer _ "|" _ carried, $LIST(row, 6) _ "|" _ $LIST(row, 7), $LIST(row, 1) _ " at " _ $LIST(row, 2) _ ", enabled " _ $LIST(row, 3) _ ", head " _ $LIST(row, 4) _ ", active " _ $LIST(row, 5))
    }
}

Method TestReachesBackTable()
{
    Set er = "Shutter.Util.EngineRead"
    Do $$$AssertEquals($CLASSMETHOD(er, "ReachesBack", "2026-11-07 01:00:00.100", "2026-11-07 01:00:00.200"), "yes", "the oldest row is older")
    Do $$$AssertEquals($CLASSMETHOD(er, "ReachesBack", "2026-11-07 01:00:00", "2026-11-07 01:00:00.200"), "yes", "the oldest row has no fraction")
    Do $$$AssertEquals($CLASSMETHOD(er, "ReachesBack", "2026-11-07 01:00:00.300", "2026-11-07 01:00:00.200"), "no", "the oldest row is newer: purged")
    Do $$$AssertEquals($CLASSMETHOD(er, "ReachesBack", "2026-11-07 01:00:00.200", "2026-11-07 01:00:00.200"), "no", "the same instant is not older")
    Do $$$AssertEquals($CLASSMETHOD(er, "ReachesBack", "", "2026-11-07 01:00:00.200"), "no", "no rows at all")
    Do $$$AssertEquals($CLASSMETHOD(er, "ReachesBack", "2026-11-07 01:00:00.100", ""), "unknown", "no creation time")
}

Method TestSettingTable()
{
    Set er = "Shutter.Util.EngineRead", stock = $PARAMETER(er, "STOCKREPLYCODEACTIONS")
    Set got = $CLASSMETHOD(er, "SettingAnswer", "FailureTimeout", "item", 0, "", "yes")
    Do $$$AssertEquals(got.source _ "|" _ got.value, "item|0", "a value read: item")
    Set got = $CLASSMETHOD(er, "SettingAnswer", "FailureTimeout", "item", 0, "", "base")
    Do $$$AssertEquals(got.source _ "|" _ got.value, "item|0", "a value the item sets is the item's, whatever the class")
    Set expr = "-1"
    Set got = $CLASSMETHOD(er, "SettingAnswer", "FailureTimeout", "nosetting", "", "", "yes", expr)
    Do $$$AssertEquals(got.source _ "|" _ got.value, "class_default|-1", "the exact error with yes: the compiled value")
    For stockAnswer = "no", "base", "unreadable", "" {
        Set got = $CLASSMETHOD(er, "SettingAnswer", "FailureTimeout", "nosetting", "", "", stockAnswer, expr)
        Do $$$AssertEquals(got.source _ "|" _ got.value, "unknown|", "the exact error with '" _ stockAnswer _ "'")
    }
    Set got = $CLASSMETHOD(er, "SettingAnswer", "FailureTimeout", "error", "", "ERROR <Ens>ErrConfigItemNotFound: gone", "yes", expr)
    Do $$$AssertEquals(got.source _ "|" _ got.why, "unknown|ERROR <Ens>ErrConfigItemNotFound: gone", "another error")
    Set got = $CLASSMETHOD(er, "SettingAnswer", "Nonsense", "nosetting", "", "", "yes")
    Do $$$AssertEquals(got.source, "unknown", "the exact error, and no such property on the class")
    Set code = "..%calcFailover()"
    Set got = $CLASSMETHOD(er, "SettingAnswer", "canFailover", "nosetting", "", "", "yes", code)
    Do $$$AssertEquals(got.source, "unknown", "the exact error, and a default that is code: not run")
    Set got = $CLASSMETHOD(er, "SettingAnswer", "DefCharEncoding", "unset", "latin1", "", "yes")
    Do $$$AssertEquals(got.source _ "|" _ got.value, "class_default|latin1", "resolved and not set, on the stock class")
    For stockAnswer = "no", "base", "unreadable" {
        Set got = $CLASSMETHOD(er, "SettingAnswer", "DefCharEncoding", "unset", "latin1", "", stockAnswer)
        Do $$$AssertEquals(got.source _ "|" _ got.value, "unknown|", "resolved and not set, " _ stockAnswer _ ": that class's default is its own")
    }
    Set got = $CLASSMETHOD(er, "SettingAnswer", "ReplyCodeActions", "unset", "", "", "yes")
    Do $$$AssertEquals(got.source _ "|" _ got.value, "class_default|" _ stock, "empty on the stock class means the engine's default")
    Set got = $CLASSMETHOD(er, "SettingAnswer", "ReplyCodeActions", "item", "", "", "yes")
    Do $$$AssertEquals(got.source _ "|" _ got.value, "item|" _ stock, "set to empty on the stock class, the same")
    Set got = $CLASSMETHOD(er, "SettingAnswer", "ReplyCodeActions", "item", "", "", "base")
    Do $$$AssertEquals(got.source _ "|" _ got.value, "item|", "set to empty at a class of its own: not assumed")
    Set got = $CLASSMETHOD(er, "SettingAnswer", "ReplyCodeActions", "item", ":?E=C", "", "yes")
    Do $$$AssertEquals(got.value, ":?E=C", "a site's string stands")
}

Method TestNoSettingIsExact()
{
    Set er = "Shutter.Util.EngineRead"
    Set text = "ERROR <Ens>ErrGeneral: No Setting 'Port' found for config item 'LIMS Out in Production 'OnbPath.Production'"
    Do $$$AssertTrue($CLASSMETHOD(er, "IsNoSetting", text, "Port", "LIMS Out"), "the engine's words")
    Do $$$AssertNotTrue($CLASSMETHOD(er, "IsNoSetting", text, "Host", "LIMS Out"), "about another setting")
    Do $$$AssertNotTrue($CLASSMETHOD(er, "IsNoSetting", text, "Port", "Results Out"), "about another item")
    Do $$$AssertNotTrue($CLASSMETHOD(er, "IsNoSetting", "ERROR <Ens>ErrConfigItemNotFound: Item X not found in Production Y", "Port", "X"), "another error")
    Do $$$AssertNotTrue($CLASSMETHOD(er, "IsNoSetting", "No Setting 'Port' found for config item 'LIMS Out in Production 'P'", "Port", "LIMS Out"), "with no code")
    Do $$$AssertNotTrue($CLASSMETHOD(er, "IsNoSetting", "", "Port", "LIMS Out"), "nothing")
}

Method TestLiteral()
{
    Set er = "Shutter.Util.EngineRead"
    Do $$$AssertTrue($CLASSMETHOD(er, "Literal", "-1", .v) && (v = -1), "a number")
    Do $$$AssertTrue($CLASSMETHOD(er, "Literal", """latin1""", .v) && (v = "latin1"), "a string")
    Do $$$AssertTrue($CLASSMETHOD(er, "Literal", """""", .v) && (v = ""), "an empty string")
    Do $$$AssertTrue($CLASSMETHOD(er, "Literal", """a""""b""", .v) && (v = "a""b"), "a doubled quote")
    Do $$$AssertNotTrue($CLASSMETHOD(er, "Literal", "$$$HL7DefSeparators", .v), "a macro")
    Do $$$AssertNotTrue($CLASSMETHOD(er, "Literal", "..%calcFailover()", .v), "a call")
    Do $$$AssertNotTrue($CLASSMETHOD(er, "Literal", """a""_$H", .v), "a string with code after it")
}

Method TestAuditNames()
{
    Set er = "Shutter.Util.EngineRead"
    Set data = "Message identification: MessageHeaderId = 36, MessageBodyClassName = EnsLib.HL7.Message, MessageBodyId = 8, SessionId = 31, HL7 ControlId = G1"
    Do $$$AssertTrue($CLASSMETHOD(er, "AuditNames", data, 36), "the new header")
    Do $$$AssertNotTrue($CLASSMETHOD(er, "AuditNames", data, 3), "not a number that starts the same")
    Do $$$AssertNotTrue($CLASSMETHOD(er, "AuditNames", data, 8), "not the body")
    Do $$$AssertNotTrue($CLASSMETHOD(er, "AuditNames", data, 31), "not the session")
}

/// The words, and the number the head message's query stands on, as the stock enumeration has them.
Method TestStatusWords()
{
    Set er = "Shutter.Util.EngineRead"
    Do $$$AssertEquals($CLASSMETHOD(er, "StatusWord", ##class(Ens.DataType.MessageStatus).DisplayToLogical("Delivered")), "Delivered", "a word back")
    Do $$$AssertEquals(##class(Ens.DataType.MessageStatus).DisplayToLogical("Delivered"), 3, "Delivered is the 3 the head message's query reads")
    Do $$$AssertEquals($CLASSMETHOD(er, "StatusWord", ""), "", "nothing")
}

Method TestLogRowsOnRealRows()
{
    Set er = "Shutter.Util.EngineRead", ns = $NAMESPACE, s = ..Session(), body = ..Body()
    Set h = ..Header(s, "UT Out", body)
    Set other = ..Header(s, "UT Out", ..Body())
    Set got = $CLASSMETHOD(er, "LogRows", ns, h)
    Do $$$AssertEquals(got.answer _ "|" _ got.rows.%Size(), "ok|0", "a header with no rows yet: read, and empty")
    Set a = ..Log(s, h, 2, "ERROR <Ens>ErrOutConnectExpired: TCP Connect timeout period (5) expired for 127.0.0.1:7202")
    Set b = ..Log(s, h, 6, "ERROR <Ens>ErrOutConnectExpired: TCP Connect timeout period (5) expired for 127.0.0.1:7202 (alert request ID=126)")
    Set c = ..Log(s, other, 2, "the other message's")
    Do ..Log(s, h, 4, "an Info row")
    Do ..Log(s, h, 3, "a Warning row")
    Set d = ..Log(s, "", 2, "no message, on this item", "UT Out")
    Do ..Log(s + 1, h, 2, "another session's")
    Set got = $CLASSMETHOD(er, "LogRows", ns, h)
    Do $$$AssertEquals(..Ids(got), a _ "," _ b _ "," _ d, "Error and Alert rows of the session and header, and the one that can't be placed, oldest first")
    Do $$$AssertEquals(got.rows.%Get(1).type, 6, "an Alert row is type 6")
    Do $$$AssertEquals(got.rows.%Get(0).messageId, h, "names the header")
    Do $$$AssertTrue(got.rows.%Get(0).text [ "ErrOutConnectExpired", "with its whole words")
    Set got = $CLASSMETHOD(er, "LogRows", ns, 999999999999)
    Do $$$AssertEquals(got.answer, "unknown", "no such header")
    Do $$$AssertNotTrue(got.%IsDefined("rows"), "and no list")
}

Method TestDeliveryHeaderOnRealRows()
{
    Set er = "Shutter.Util.EngineRead", ns = $NAMESPACE
    // The routed shape: the service's header is the origin, the operation's the next in its session.
    Set s = ..Session(), body = ..Body()
    Set origin = ..Header(s, "UT Router", body, 0, "", "Completed")
    Set delivery = ..Header(s, "UT Out", body)
    Set got = $CLASSMETHOD(er, "DeliveryHeader", ns, origin, "UT Out")
    Do $$$AssertEquals(got.answer _ "|" _ got.headerId _ "|" _ got.via, "found|" _ delivery _ "|session", "routed: origin to the router, delivery to the operation")
    // The one-message shape: the origin was sent to the item.
    Set got = $CLASSMETHOD(er, "DeliveryHeader", ns, delivery, "UT Out")
    Do $$$AssertEquals(got.answer _ "|" _ got.headerId _ "|" _ got.via, "found|" _ delivery _ "|origin", "the origin itself")
    // Clones beside the original.
    Do ..Header(s, "UT Out", body, 1, "Resent " _ delivery)
    Do ..Header(s, "UT Out", body, 0, "Resent " _ delivery)
    Set got = $CLASSMETHOD(er, "DeliveryHeader", ns, origin, "UT Out")
    Do $$$AssertEquals(got.headerId, delivery, "clones at Resent 1, and at Resent 0 with the description, are skipped")
    // A splitting route: two messages to one item.
    Set split = ..Session()
    Set first = ..Header(split, "UT Router", ..Body(), 0, "", "Completed")
    Do ..Header(split, "UT Out", ..Body())
    Do ..Header(split, "UT Out", ..Body())
    Set got = $CLASSMETHOD(er, "DeliveryHeader", ns, first, "UT Out")
    Do $$$AssertEquals(got.answer, "unreadable", "two candidates with different bodies")
    // A hold's header is not a delivery.
    Set held = ..Session()
    Set first = ..Header(held, "UT Router", ..Body(), 0, "", "Completed")
    Do ..Header(held, "UT Hold UT Out", ..Body(), 0, "", "Completed")
    Set got = $CLASSMETHOD(er, "DeliveryHeader", ns, first, "UT Out")
    Do $$$AssertEquals(got.answer, "unreadable", "a header to another item is no candidate")
    Set got = $CLASSMETHOD(er, "DeliveryHeader", ns, 999999999999, "UT Out")
    Do $$$AssertEquals(got.answer, "unreadable", "no such origin")
    Set got = $CLASSMETHOD(er, "DeliveryHeader", ns, first, "")
    Do $$$AssertEquals(got.answer, "unreadable", "no item")
}

Method TestSiblingsOnRealRows()
{
    Set er = "Shutter.Util.EngineRead", ns = $NAMESPACE, s = ..Session(), body = ..Body()
    Set a = ..Header(s, "UT Out", body)
    Set got = $CLASSMETHOD(er, "Siblings", ns, a)
    Do $$$AssertEquals(got.answer _ "|" _ got.rows.%Size(), "ok|0", "alone: read, and empty")
    Set clone = ..Header(s, "UT Out", body, 1, "Resent " _ a, "Completed")
    Do ..Header(s, "UT Other", body)
    Do ..Header(s, "UT Out", ..Body())
    Do ..Header(..Session(), "UT Out", body)
    Set got = $CLASSMETHOD(er, "Siblings", ns, a)
    Do $$$AssertEquals(got.rows.%Size(), 1, "the same session, body and target only")
    Set row = got.rows.%Get(0)
    Do $$$AssertEquals(row.headerId _ "|" _ row.status _ "|" _ row.resent, clone _ "|Completed|1", "its id, status word and count")
    Do $$$AssertEquals(row.atSource, "header", "with no audit row, the copy's own creation time")
    Do $$$AssertEquals(row.at, row.timeCreated, "which it says")
    Set got = $CLASSMETHOD(er, "Siblings", ns, clone)
    Do $$$AssertEquals(got.rows.%Get(0).headerId, a, "the original is the clone's sibling")
    Set got = $CLASSMETHOD(er, "Siblings", ns, 999999999999)
    Do $$$AssertEquals(got.answer, "unknown", "no such header")
    Do $$$AssertNotTrue(got.%IsDefined("rows"), "and no list")
}

Method TestLogReachesBackOnRealRows()
{
    Set er = "Shutter.Util.EngineRead", ns = $NAMESPACE, s = ..Session()
    Do ..Log(s, "", 4, "an older row, so the log is not empty")
    Hang 0.01
    Set h = ..Header(s, "UT Out", ..Body())
    Set got = $CLASSMETHOD(er, "LogReachesBack", ns, h)
    Do $$$AssertEquals(got.answer, "yes", "the namespace's log is older than this header, " _ got.oldestLogged _ " against " _ got.headerCreated)
    Set got = $CLASSMETHOD(er, "LogReachesBack", ns, 999999999999)
    Do $$$AssertEquals(got.answer, "unknown", "no such header")
}

/// Custody on real headers at a live item. Skipped when Shutter's production isn't running here.
Method TestCustodyOnRealRows()
{
    Set er = "Shutter.Util.EngineRead", ns = $NAMESPACE, item = ..#ITEM
    Set state = $CLASSMETHOD(er, "ItemState", ns, item)
    If state.answer '= "ok" {
        Do $$$AssertSkipped("no running production with the item " _ item _ ": " _ state.why)
        Quit
    }
    Do $$$AssertEquals(state.enabled, 1, "the item is enabled")
    Do $$$AssertEquals(state.productionState, "running", "in a running production")
    Set s = ..Session()
    For row = $LB("Queued", "engine"), $LB("Delivered", "engine"), $LB("Error", "settled"), $LB("Suspended", "settled"), $LB("Discarded", "unreadable"), $LB("Aborted", "unreadable"), $LB("Deferred", "unreadable"), $LB("Created", "unreadable") {
        Set h = ..Header(s, item, ..Body(), 0, "", $LIST(row, 1))
        Set got = $CLASSMETHOD(er, "Custody", ns, item, h)
        Do $$$AssertEquals(got.answer _ "|" _ got.headerStatus, $LIST(row, 2) _ "|" _ $LIST(row, 1), $LIST(row, 1) _ ": " _ got.why)
        // Out of the way, or the next row's item has a head message of this test's.
        Do ##class(Ens.MessageHeader).%DeleteId(h)
    }
    Set when = "2026-11-07 01:02:03.456"
    Set h = ..Header(s, item, ..Body(), 0, "", "Completed", when)
    Set got = $CLASSMETHOD(er, "Custody", ns, item, h)
    Do $$$AssertEquals(got.answer _ "|" _ got.completedAt, "delivered|" _ when, "Completed, with its completion time")
    Set got = $CLASSMETHOD(er, "Custody", ns, "UT Another Item", h)
    Do $$$AssertEquals(got.answer, "unreadable", "a header to another item")
    Do $$$AssertTrue(got.why [ item, "and says whose it is")
    Set h = ..Header(s, "UT Not In The Production", ..Body())
    Set got = $CLASSMETHOD(er, "Custody", ns, "UT Not In The Production", h)
    Do $$$AssertEquals(got.answer, "unreadable", "an item not in the production")
    Set got = $CLASSMETHOD(er, "Custody", ns, item, 999999999999)
    Do $$$AssertEquals(got.answer, "unreadable", "no such header")
}

/// ItemSetting on a live item that isn't the stock operation, the class default on the same class taken as if it were.
Method TestItemSettingLive()
{
    Set er = "Shutter.Util.EngineRead", ns = $NAMESPACE, item = ..#ITEM
    If $CLASSMETHOD(er, "ItemState", ns, item).answer '= "ok" {
        Do $$$AssertSkipped("no running production with the item " _ item)
        Quit
    }
    Set got = $CLASSMETHOD(er, "ItemSetting", ns, item, "FailureTimeout", "no")
    Do $$$AssertEquals(got.source, "unknown", "not set on the item, class not the stock one: " _ got.why)
    Set got = $CLASSMETHOD(er, "ItemSetting", ns, item, "FailureTimeout", "yes")
    Do $$$AssertEquals(got.source, "class_default", "not set on the item, the class taken as the stock one")
    Do $$$AssertTrue(got.value '= "", "its value: " _ got.value)
    // Retry is a property and not a setting: the engine's exact error.
    Set got = $CLASSMETHOD(er, "ItemSetting", ns, item, "Retry", "yes")
    Do $$$AssertEquals(got.source _ "|" _ got.value, "class_default|0", "the exact error with yes: the compiled value")
    For stock = "no", "base", "unreadable" {
        Set got = $CLASSMETHOD(er, "ItemSetting", ns, item, "Retry", stock)
        Do $$$AssertEquals(got.source _ "|" _ got.value, "unknown|", "the exact error with " _ stock)
    }
    Set got = $CLASSMETHOD(er, "ItemSetting", ns, item, "NoSuchSettingAnywhere", "yes")
    Do $$$AssertEquals(got.source, "unknown", "no setting and no property")
    Set got = $CLASSMETHOD(er, "ItemSetting", ns, "UT Not In The Production", "FailureTimeout", "yes")
    Do $$$AssertEquals(got.source, "unknown", "an item not in the production")
    Do $$$AssertTrue(got.why [ "ErrConfigItemNotFound", "another error, given: " _ got.why)
}

/// A namespace that isn't there, and one with no engine tables. A failure answers unknown or unreadable, never a list.
Method TestAReadThatFails()
{
    Set er = "Shutter.Util.EngineRead"
    For ns = "NOSUCHNAMESPACE", "%SYS", "" {
        Set got = $CLASSMETHOD(er, "LogRows", ns, 1)
        Do $$$AssertEquals(got.answer, "unknown", "LogRows in '" _ ns _ "': " _ got.why)
        Do $$$AssertNotTrue(got.%IsDefined("rows"), "with no list")
        Do $$$AssertTrue(got.why '= "", "and a reason")
        Set got = $CLASSMETHOD(er, "DeliveryHeader", ns, 1, "UT Out")
        Do $$$AssertEquals(got.answer, "unreadable", "DeliveryHeader in '" _ ns _ "'")
        Set got = $CLASSMETHOD(er, "Custody", ns, "UT Out", 1)
        Do $$$AssertEquals(got.answer, "unreadable", "Custody in '" _ ns _ "'")
        Set got = $CLASSMETHOD(er, "ItemState", ns, "UT Out")
        Do $$$AssertEquals(got.answer, "unknown", "ItemState in '" _ ns _ "'")
        Set got = $CLASSMETHOD(er, "Siblings", ns, 1)
        Do $$$AssertEquals(got.answer, "unknown", "Siblings in '" _ ns _ "'")
        Do $$$AssertNotTrue(got.%IsDefined("rows"), "with no list")
        Set got = $CLASSMETHOD(er, "LogReachesBack", ns, 1)
        Do $$$AssertEquals(got.answer, "unknown", "LogReachesBack in '" _ ns _ "'")
        Set got = $CLASSMETHOD(er, "ItemSetting", ns, "UT Out", "FailureTimeout", "yes")
        Do $$$AssertEquals(got.source, "unknown", "ItemSetting in '" _ ns _ "'")
    }
}

}
