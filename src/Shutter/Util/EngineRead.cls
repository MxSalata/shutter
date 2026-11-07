/// What the integration engine shows about a delivery, read in the source namespace: a header's log rows, the header a
/// delivery went on, whose hands a message is in, the other copies of it, how far back the log reaches, and one setting
/// of one item. These are reads only: nothing here takes a lock, opens a connection or writes. It judges no words and
/// calls nothing that does: a caller reads with this class and judges what it read with Shutter.Util.EngineWords.
///
/// Every read answers a %DynamicObject and never throws, and a read that failed says so ("unknown" or "unreadable", with
/// its reason in why), so a failure can never look like "nothing there". Read the answer by comparing the word
/// (r.answer = "yes"), since these are strings.
///
/// Called from a production job or a terminal in Shutter's namespace, which may switch namespace. Shutter's REST process
/// cannot: there every read here answers unknown or unreadable. The class is not assumed to be mapped into the other
/// namespace: while switched, the methods here call only stock classes, and each of their own methods runs back in the
/// caller's namespace.
Class Shutter.Util.EngineRead Extends %RegisteredObject
{

/// What an empty ReplyCodeActions means on the stock HL7 operation: the engine's own default, as the class documents it.
Parameter STOCKREPLYCODEACTIONS = ":?R=RF,:?E=S,:~=S,:?A=C,:*=S,:I?=W,:T?=C";

/// The rows Shutter.Util.EngineWords.Attempts takes for one header: the event log's Error and Alert rows (types 2 and 6)
/// of the header's session that name the header in MessageId, oldest first, and any such row of the session with no
/// MessageId whose ConfigName is the header's target or whose text names it (the row can't be placed, so a judge must not
/// ignore it).
/// { "answer": "ok", "rows": [ { "id", "type", "text", "messageId", "configName", "timeLogged" } ] }, the list empty only
/// when the log was read and holds no such row; { "answer": "unknown", "why" } with no list at all when anything failed.
ClassMethod LogRows(ns As %String, headerId As %String) As %DynamicObject
{
    Set out = {"answer": "unknown"}
    If '..One(ns, "SELECT SessionId, TargetConfigName FROM Ens.MessageHeader WHERE ID = ?", "SessionId,TargetConfigName", .header, .why, headerId) {
        Set out.why = why
        Quit out
    }
    If header.SessionId = "" {
        Set out.why = "header " _ headerId _ " has no session"
        Quit out
    }
    If '..Query(ns, "SELECT ID, Type, Text, MessageId, ConfigName, TimeLogged FROM Ens_Util.Log WHERE SessionId = ? AND Type IN (2, 6) ORDER BY ID", "ID,Type,Text,MessageId,ConfigName,TimeLogged", .rows, .why, header.SessionId) {
        Set out.why = why
        Quit out
    }
    Quit ..LogRowsOf(rows, headerId, header.TargetConfigName)
}

/// LogRows' choice among a session's rows, on its own so a table can test it.
ClassMethod LogRowsOf(rows As %DynamicArray, headerId As %String, item As %String) As %DynamicObject
{
    Set kept = []
    Set iter = rows.%GetIterator()
    While iter.%GetNext(.i, .row) {
        Set named = +row.MessageId
        Continue:named&&(named'=+headerId)
        If 'named Continue:(item="")
        If 'named Continue:(row.ConfigName'=item)&&(row.Text'[item)
        Do kept.%Push({"id": (row.ID), "type": (+row.Type), "text": (row.Text), "messageId": ($SELECT(named: named, 1: "")), "configName": (row.ConfigName), "timeLogged": (row.TimeLogged)})
    }
    Quit {"answer": "ok", "rows": (kept)}
}

/// The header the delivery to the item went on, starting from the case's origin header. The origin itself when it was
/// sent to the item. Otherwise, in the origin's session, the newest original to the item: Resent 0 or empty, and a
/// Description that does not start "Resent " (a clone can read Resent 0). Two such headers with one body are the same
/// message and the newest wins; with different bodies the session sent several messages and it can't be said which.
/// { "answer": "found", "headerId", "via": "origin"|"session" } or { "answer": "unreadable", "why" }.
ClassMethod DeliveryHeader(ns As %String, originId As %String, item As %String) As %DynamicObject
{
    If item = "" Quit {"answer": "unreadable", "why": "no item"}
    If '..One(ns, "SELECT SessionId, TargetConfigName FROM Ens.MessageHeader WHERE ID = ?", "SessionId,TargetConfigName", .origin, .why, originId) {
        Quit {"answer": "unreadable", "why": (why)}
    }
    If origin.TargetConfigName = item Quit {"answer": "found", "headerId": (originId), "via": "origin"}
    If origin.SessionId = "" Quit {"answer": "unreadable", "why": ("header " _ originId _ " has no session")}
    If '..Query(ns, "SELECT ID, MessageBodyClassName, MessageBodyId, Resent, Description FROM Ens.MessageHeader WHERE SessionId = ? AND TargetConfigName = ? ORDER BY ID DESC", "ID,MessageBodyClassName,MessageBodyId,Resent,Description", .rows, .why, origin.SessionId, item) {
        Quit {"answer": "unreadable", "why": (why)}
    }
    Quit ..ChooseDelivery(rows, item, origin.SessionId)
}

/// DeliveryHeader's choice among a session's headers to the item, newest first, on its own so a table can test it.
ClassMethod ChooseDelivery(rows As %DynamicArray, item As %String, session As %String) As %DynamicObject
{
    Set first = "", body = ""
    Set iter = rows.%GetIterator()
    While iter.%GetNext(.i, .row) {
        Continue:+row.Resent'=0
        Continue:$EXTRACT(row.Description, 1, 7)="Resent "
        Set thisBody = row.MessageBodyClassName _ "|" _ row.MessageBodyId
        If first = "" {
            Set first = row.ID, body = thisBody
        } ElseIf thisBody '= body {
            Set several = row.ID
            Quit
        }
    }
    If $DATA(several) Quit {"answer": "unreadable", "why": ("session " _ session _ " sent " _ item _ " more than one message (headers " _ several _ " and " _ first _ ")")}
    If first = "" Quit {"answer": "unreadable", "why": ("session " _ session _ " has no original header to " _ item)}
    Quit {"answer": "found", "headerId": (first), "via": "session"}
}

/// Whose hands the message is in, four answers:
/// engine: the header reads Queued or Delivered, or the item is retrying, or the header is the item's head message (or its
/// active message), or the item is disabled, since then a message sits queued until someone enables it;
/// delivered: Completed, with completedAt (the header's TimeProcessed, else the stock audit row's time);
/// settled: Error or Suspended;
/// unreadable: any failed read, a header that isn't to this item, the item not in a running production, or a status this
/// table doesn't name (Created, Discarded, Aborted, Deferred).
/// What delivered means for a resend is the caller's, by the case's route. The item's state is read first, so a Completed
/// or Error header at a retrying item reads engine, with its own status and time still given.
/// { "answer", "why", "headerStatus", "completedAt", "itemStatus", "adapterState", "enabled", "queue", "headHeaderId",
/// "activeMessage", "carriedBy": [ "status"|"retry"|"head"|"active"|"disabled" ] }. An empty activeMessage means unknown.
ClassMethod Custody(ns As %String, item As %String, headerId As %String) As %DynamicObject
{
    Set out = {"answer": "unreadable", "why": "", "headerStatus": "", "completedAt": "", "itemStatus": "", "adapterState": "", "enabled": "", "queue": "", "headHeaderId": "", "activeMessage": "", "carriedBy": []}
    If '..One(ns, "SELECT Status, TargetConfigName, TimeCreated, TimeProcessed FROM Ens.MessageHeader WHERE ID = ?", "Status,TargetConfigName,TimeCreated,TimeProcessed", .header, .why, headerId) {
        Set out.why = why
        Quit out
    }
    If header.TargetConfigName '= item {
        Set out.why = "header " _ headerId _ " is to " _ header.TargetConfigName _ ", not " _ item
        Quit out
    }
    Set word = ..StatusWord(header.Status)
    Set out.headerStatus = word
    If word = "Completed" {
        Set out.completedAt = header.TimeProcessed
        If out.completedAt = "" Set out.completedAt = ..AuditTime(ns, headerId, header.TimeCreated)
    }
    Set state = ..ItemState(ns, item)
    Set out.itemStatus = state.status, out.adapterState = state.adapterState, out.enabled = state.enabled, out.queue = state.queue
    Set out.headHeaderId = state.headHeaderId, out.activeMessage = state.activeMessage
    If state.answer '= "ok" {
        Set out.why = state.why
        Quit out
    }
    Set judged = ..CustodyAnswer(word, state.status, state.enabled, (state.headHeaderId = headerId), (state.activeMessage = headerId))
    Set out.answer = judged.answer, out.why = judged.why, out.carriedBy = judged.carriedBy
    Quit out
}

/// Custody's table: the header's status word, the item's Status, whether the item is enabled, and whether the header is
/// its head and its active message. Separate so that a table can test it without an instance.
ClassMethod CustodyAnswer(word As %String, itemStatus As %String, enabled As %Boolean, isHead As %Boolean, isActive As %Boolean) As %DynamicObject
{
    Set carried = []
    If (word = "Queued") || (word = "Delivered") Do carried.%Push("status")
    If $ZCONVERT(itemStatus, "L") = "retry" Do carried.%Push("retry")
    If isHead Do carried.%Push("head")
    If isActive Do carried.%Push("active")
    If 'enabled Do carried.%Push("disabled")
    If carried.%Size() Quit {"answer": "engine", "why": "", "carriedBy": (carried)}
    If word = "Completed" Quit {"answer": "delivered", "why": "", "carriedBy": (carried)}
    If (word = "Error") || (word = "Suspended") Quit {"answer": "settled", "why": "", "carriedBy": (carried)}
    Quit {"answer": "unreadable", "why": ("the header reads " _ $SELECT(word '= "": word, 1: "no status")), "carriedBy": (carried)}
}

/// One item as the engine shows it, for Custody and for a poll. answer "ok" when the production runs and every field that
/// says what the item is doing was read; otherwise "unknown", with why and whatever was read before it failed.
/// { "answer", "why", "production", "productionState", "inProduction", "enabled", "status", "adapterState", "queue",
/// "lastActivity", "headHeaderId", "activeMessage" }. productionState is "running", "not running" or empty when even that
/// could not be read. headHeaderId is the oldest header to the item reading Delivered, by
/// SQL; activeMessage is what the job list shows, a check on it, and empty means unknown rather than none.
ClassMethod ItemState(ns As %String, item As %String) As %DynamicObject
{
    Set out = {"answer": "unknown", "why": "", "production": "", "productionState": "", "inProduction": "", "enabled": "", "status": "", "adapterState": "", "queue": "", "lastActivity": "", "headHeaderId": "", "activeMessage": ""}
    If (ns = "") || (item = "") {
        Set out.why = "no namespace or no item"
        Quit out
    }
    Do ..ReadItem(ns, item, out)
    Quit out
}

/// ItemState's reads, in the item's namespace. Only stock classes while switched.
ClassMethod ReadItem(ns As %String, item As %String, out As %DynamicObject) [ Private ]
{
    Try {
        New $NAMESPACE
        Set $NAMESPACE = ns
        // Whether it runs, from IsProductionRunning, which only reads. Not GetProductionStatus or the status query that calls
        // it: they take the runtime lock, waiting up to 10 s for the production's own start, stop or update, and inside a
        // caller's transaction they keep it until the commit, in a namespace that isn't Shutter's.
        Set running = ""
        If '##class(Ens.Director).IsProductionRunning(.running) {
            Set out.productionState = "not running"
            Set out.why = "no production is running in " _ ns
            Quit
        }
        Set out.production = running, out.productionState = "running"
        // Enabled, from the configuration: a disabled item may have no host row. A missing item is an error here.
        Set sc = $$$OK
        Set enabled = ##class(Ens.Director).IsItemEnabled(item, .sc)
        If $$$ISERR(sc) {
            Set out.inProduction = $SELECT($SYSTEM.Status.GetErrorCodes(sc) [ "ErrConfigItemNotFound": 0, 1: "")
            Set out.why = $SYSTEM.Status.GetErrorText(sc)
            Quit
        }
        Set out.inProduction = 1, out.enabled = $SELECT(+enabled > 0: 1, 1: 0)
        // Status and connection, from the engine's own monitor.
        Set st = ##class(%SQL.Statement).%New()
        Set sc = st.%PrepareClassQuery("Ens.Util.Statistics", "EnumerateHostStatus")
        If $$$ISERR(sc) {
            Set out.why = $SYSTEM.Status.GetErrorText(sc)
            Quit
        }
        Set rs = st.%Execute()
        If rs.%SQLCODE < 0 {
            Set out.why = "the host status can't be read: SQLCODE " _ rs.%SQLCODE _ " " _ rs.%Message
            Quit
        }
        Set found = 0
        While rs.%Next(.sc) {
            Continue:rs.%Get("Name")'=item
            Set found = 1
            Set out.status = rs.%Get("Status"), out.adapterState = rs.%Get("AdapterState"), out.lastActivity = rs.%Get("LastActivity")
            Quit
        }
        If $$$ISERR($GET(sc, 1)) {
            Set out.why = $SYSTEM.Status.GetErrorText(sc)
            Quit
        }
        Set out.queue = ##class(Ens.Queue).GetCount(item)
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP 1 ID FROM Ens.MessageHeader WHERE TargetConfigName = ? AND Status = 3 ORDER BY ID", item)
        If rs.%SQLCODE < 0 {
            Set out.why = "the head message can't be read: SQLCODE " _ rs.%SQLCODE _ " " _ rs.%Message
            Quit
        }
        If rs.%Next() Set out.headHeaderId = rs.%Get("ID")
        If rs.%SQLCODE < 0 {
            Set out.why = "the head message can't be read: SQLCODE " _ rs.%SQLCODE _ " " _ rs.%Message
            Quit
        }
        Set st = ##class(%SQL.Statement).%New()
        If $$$ISOK(st.%PrepareClassQuery("Ens.Job", "Enumerate")) {
            Set rs = st.%Execute()
            While rs.%Next() {
                Continue:rs.%Get("ConfigName")'=item
                Continue:rs.%Get("ActiveMessage")=""
                Set out.activeMessage = rs.%Get("ActiveMessage")
                Quit
            }
        }
        If 'found && out.enabled {
            Set out.why = "the engine shows no status for " _ item
            Quit
        }
        Set out.answer = "ok"
    } Catch ex {
        Set out.answer = "unknown", out.why = ex.DisplayString()
    }
}

/// Every other header in this header's session with the same body and the same target: a stock resend is such a copy
/// (Resent 1, 2, ..., Description "Resent <id>"), and it is the only record of one.
/// { "answer": "ok", "rows": [ { "headerId", "status", "resent", "description", "timeCreated", "at", "atSource" } ] } or
/// { "answer": "unknown", "why" } with no list. at is the stock audit row's time (atSource "audit"), else the copy's own
/// creation time (atSource "header").
ClassMethod Siblings(ns As %String, headerId As %String) As %DynamicObject
{
    Set out = {"answer": "unknown"}
    If '..One(ns, "SELECT SessionId, TargetConfigName, MessageBodyId, MessageBodyClassName, TimeCreated FROM Ens.MessageHeader WHERE ID = ?", "SessionId,TargetConfigName,MessageBodyId,MessageBodyClassName,TimeCreated", .header, .why, headerId) {
        Set out.why = why
        Quit out
    }
    If header.SessionId = "" {
        Set out.why = "header " _ headerId _ " has no session"
        Quit out
    }
    If '..Query(ns, "SELECT ID, Status, Resent, Description, TimeCreated FROM Ens.MessageHeader WHERE SessionId = ? AND TargetConfigName = ? AND MessageBodyId = ? AND MessageBodyClassName = ? AND ID <> ? ORDER BY ID", "ID,Status,Resent,Description,TimeCreated", .rows, .why, header.SessionId, header.TargetConfigName, header.MessageBodyId, header.MessageBodyClassName, headerId) {
        Set out.why = why
        Quit out
    }
    Set kept = []
    Set iter = rows.%GetIterator()
    While iter.%GetNext(.i, .row) {
        Set at = ..AuditTime(ns, row.ID, row.TimeCreated)
        Do kept.%Push({"headerId": (row.ID), "status": (..StatusWord(row.Status)), "resent": (+row.Resent), "description": (row.Description), "timeCreated": (row.TimeCreated), "at": ($SELECT(at '= "": at, 1: row.TimeCreated)), "atSource": ($SELECT(at '= "": "audit", 1: "header"))})
    }
    Quit {"answer": "ok", "rows": (kept)}
}

/// Whether the event log reaches back past this header's creation: "yes" when the oldest surviving row in the namespace,
/// of any type and any item, is older than the header. An age purge takes the oldest rows first, so this detects one. It
/// does not prove the header's history complete: an old row elsewhere says nothing of this header's own rows. "no" also
/// for a log with no rows at all; "unknown" for a failed read.
/// { "answer": "yes"|"no"|"unknown", "why", "oldestLogged", "headerCreated" }.
ClassMethod LogReachesBack(ns As %String, headerId As %String) As %DynamicObject
{
    Set out = {"answer": "unknown", "why": "", "oldestLogged": "", "headerCreated": ""}
    If '..One(ns, "SELECT TimeCreated FROM Ens.MessageHeader WHERE ID = ?", "TimeCreated", .header, .why, headerId) {
        Set out.why = why
        Quit out
    }
    Set out.headerCreated = header.TimeCreated
    If '..Query(ns, "SELECT TOP 1 TimeLogged FROM Ens_Util.Log ORDER BY ID", "TimeLogged", .rows, .why) {
        Set out.why = why
        Quit out
    }
    Set oldest = $SELECT(rows.%Size(): rows.%Get(0).TimeLogged, 1: "")
    Set out.oldestLogged = oldest
    Set out.answer = ..ReachesBack(oldest, header.TimeCreated)
    If out.answer = "unknown" Set out.why = "the header has no creation time"
    Quit out
}

/// LogReachesBack's comparison of two UTC times in the store's form.
ClassMethod ReachesBack(oldest As %String, created As %String) As %String
{
    If created = "" Quit "unknown"
    If oldest = "" Quit "no"
    Quit $SELECT(created ] oldest: "yes", 1: "no")
}

/// One setting of one item, the one home of the rule for what an unanswered setting means. isStock is
/// Shutter.Util.EngineScope.IsStockTcp's answer for the item: yes, base, no or unreadable.
/// source item: the item, or a system default setting for it, sets the value. source class_default: the item doesn't set
/// it and isStock is yes: the value is the engine's own resolved value, or on the exact "No Setting" error, which is what
/// the engine answers for a setting not offered on the class or its adapter at all, the compiled property's literal
/// initial value. source unknown: anything else, including a setting not set on a class that isn't the stock operation,
/// since there the default is that class's own.
/// { "source", "value", "why" }. An empty ReplyCodeActions on the stock operation answers the engine's default string.
/// Host and adapter settings are both read: GetReply and Port live on the adapter. Reads the configuration, not the running
/// job, so a change not yet applied to the running production already shows.
ClassMethod ItemSetting(ns As %String, item As %String, setting As %String, isStock As %String) As %DynamicObject
{
    Do ..ReadSetting(ns, item, setting, .read, .value, .why, .compiled)
    Quit ..SettingAnswer(setting, read, value, why, isStock, .compiled)
}

/// ItemSetting's table. read says what the engine answered: "item" (set on the item or a default setting), "unset" (it
/// resolved a value the item doesn't set), "nosetting" (the exact error) or "error". compiled is the compiled property's
/// initial expression, undefined when the class has no such property.
ClassMethod SettingAnswer(setting As %String, read As %String, value As %String, why As %String, isStock As %String, ByRef compiled As %String) As %DynamicObject
{
    If read = "error" Quit {"source": "unknown", "value": "", "why": (why)}
    If read = "item" Quit {"source": "item", "value": (..Effective(setting, value, isStock)), "why": ""}
    If isStock '= "yes" Quit {"source": "unknown", "value": "", "why": ("the item does not set " _ setting _ " and its class is not the stock operation (" _ $SELECT(isStock '= "": isStock, 1: "not read") _ ")")}
    If read = "unset" Quit {"source": "class_default", "value": (..Effective(setting, value, isStock)), "why": ""}
    If read '= "nosetting" Quit {"source": "unknown", "value": "", "why": (why)}
    If '$DATA(compiled) Quit {"source": "unknown", "value": "", "why": ("no setting or property " _ setting)}
    If '..Literal(compiled, .literal) Quit {"source": "unknown", "value": "", "why": ("the class default of " _ setting _ " is not a plain value")}
    Quit {"source": "class_default", "value": (..Effective(setting, literal, isStock)), "why": ""}
}

/// Whether the error text is the engine's exact answer for a setting it doesn't offer. Stock's own wording, including its
/// unbalanced quote after the item's name; anything else about the same setting is some other failure.
ClassMethod IsNoSetting(text As %String, setting As %String, item As %String) As %Boolean
{
    Set start = "ERROR <Ens>ErrGeneral: No Setting '" _ setting _ "' found for config item '" _ item _ " in Production '"
    Quit ($EXTRACT(text, 1, $LENGTH(start)) = start) && ($EXTRACT(text, *) = "'")
}

/// ItemSetting's reads, in the item's namespace. Only stock classes while switched. read is item, unset, nosetting or error.
ClassMethod ReadSetting(ns As %String, item As %String, setting As %String, Output read As %String, Output value As %String, Output why As %String, Output compiled As %String) [ Private ]
{
    Set read = "error", value = "", why = ""
    Kill compiled
    Try {
        If (ns = "") || (item = "") || (setting = "") {
            Set why = "no namespace, item or setting"
            Quit
        }
        New $NAMESPACE
        Set $NAMESPACE = ns
        Set production = ##class(Ens.Director).GetActiveProductionName()
        If production = "" {
            Set why = "no current production in " _ ns
            Quit
        }
        Set target = "", none = 0
        For type = "Host", "Adapter" {
            Set sc = $$$OK
            Set answer = ##class(Ens.Director).GetItemSettingValue(item, type, setting, .sc)
            If $$$ISOK(sc) {
                Set target = type, value = answer
                Quit
            }
            Set text = $SYSTEM.Status.GetErrorText(sc)
            // The check on the words is inline: this method's own class may not exist in this namespace.
            Set start = "ERROR <Ens>ErrGeneral: No Setting '" _ setting _ "' found for config item '" _ item _ " in Production '"
            If $EXTRACT(text, 1, $LENGTH(start)) '= start {
                Set why = text
                Quit
            }
            Set none = none + 1
        }
        Quit:why'=""
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ClassName, Enabled, Settings FROM Ens_Config.Item WHERE Production = ? AND Name = ?", production, item)
        If rs.%SQLCODE < 0 {
            Set why = "the item can't be read: SQLCODE " _ rs.%SQLCODE _ " " _ rs.%Message
            Quit
        }
        Set class = "", list = "", best = -1
        While rs.%Next() {
            Set rank = +rs.%Get("Enabled")
            If rank > best Set best = rank, class = rs.%Get("ClassName"), list = rs.%Get("Settings")
        }
        If class = "" {
            Set why = "item " _ item _ " is not in " _ production
            Quit
        }
        If target = "" {
            // Neither the class nor its adapter offers it. What the compiled class says, if it has the property at all.
            Set adapter = $PARAMETER(class, "ADAPTER")
            Set property = ##class(%Dictionary.CompiledProperty).%OpenId(class _ "||" _ setting)
            If '$ISOBJECT(property) && (adapter '= "") Set property = ##class(%Dictionary.CompiledProperty).%OpenId(adapter _ "||" _ setting)
            If $ISOBJECT(property) Set compiled = property.InitialExpression
            Set read = "nosetting", why = "No Setting " _ setting _ " on " _ item
            Quit
        }
        // Whether the item itself sets it, in the same form the engine reads its list, or a default setting does.
        Set read = "unset"
        If $LISTVALID(list) {
            For i = 1:1:$LISTLENGTH(list) {
                Set one = $LISTGET($LIST(list, i))
                If ($LISTGET(one, 1) = setting) && ($LISTGET(one, 2) = target) && $LISTDATA(one, 3) Set read = "item" Quit
            }
        }
        If read = "unset" {
            Set adapter = $PARAMETER(class, "ADAPTER")
            If ##class(Ens.Config.DefaultSettings).%GetSetting(production, item, $SELECT(target = "Host": class, 1: adapter), target, setting, .site) {
                Set read = "item"
            }
        }
    } Catch ex {
        Set read = "error", value = "", why = ex.DisplayString()
    }
}

/// An initial expression that is a plain number or a quoted string, as its value. Any other expression is code, which is not run.
ClassMethod Literal(expression As %String, Output value As %String) As %Boolean
{
    Set value = ""
    If expression = "" Quit 1
    If $MATCH(expression, "-?[0-9]+(\.[0-9]+)?") Set value = +expression Quit 1
    If $MATCH(expression, """([^""]|"""")*""") {
        Set value = $REPLACE($EXTRACT(expression, 2, *-1), """""", """")
        Quit 1
    }
    Quit 0
}

/// A setting's value as the stock operation applies it: there an empty ReplyCodeActions means the engine's default.
ClassMethod Effective(setting As %String, value As %String, isStock As %String) As %String
{
    If (setting = "ReplyCodeActions") && (value = "") && (isStock = "yes") Quit ..#STOCKREPLYCODEACTIONS
    Quit value
}

/// A header's stored status as its word: Created, Queued, Delivered, Discarded, Suspended, Deferred, Aborted, Error or
/// Completed, from the stock enumeration; empty when the status isn't one of them.
ClassMethod StatusWord(status As %String) As %String
{
    If status = "" Quit ""
    Try {
        Set word = ##class(Ens.DataType.MessageStatus).LogicalToDisplay(status)
    } Catch ex {
        Set word = ""
    }
    Quit word
}

/// The stock audit row's time for the resend that made this header, in UTC, from the moment the header was made; empty
/// when the audit can't be read, holds no such row, or hasn't been written yet (the audit is buffered). Read in the
/// audit's own namespace, where a production job may go and a REST process may not.
ClassMethod AuditTime(ns As %String, headerId As %String, created As %String) As %String
{
    If (headerId = "") || (created = "") Quit ""
    If '..Query("%SYS", "SELECT TOP 50 UTCTimeStamp, EventData FROM %SYS.Audit WHERE UTCTimeStamp >= ? AND EventSource = '%Ensemble' AND EventType = '%Message' AND Event = 'Resend' AND Namespace = ? ORDER BY UTCTimeStamp", "UTCTimeStamp,EventData", .rows, .why, $EXTRACT(created, 1, 19), ns) Quit ""
    Set at = ""
    Set iter = rows.%GetIterator()
    While iter.%GetNext(.i, .row) {
        If ..AuditNames(row.EventData, headerId) {
            Set at = row.UTCTimeStamp
            Quit
        }
    }
    Quit at
}

/// Whether an audit row's data names this as the new header: "Message identification: MessageHeaderId = 36, ...".
ClassMethod AuditNames(data As %String, headerId As %String) As %Boolean
{
    Quit data [ ("MessageHeaderId = " _ headerId _ ",")
}

/// One row of a query, or 0 with why: a header that isn't there is a failed read here, not an empty answer.
ClassMethod One(ns As %String, sql As %String, columns As %String, Output row As %DynamicObject, Output why As %String, args...) As %Boolean [ Private ]
{
    Set row = ""
    Quit:'..Query(ns, sql, columns, .rows, .why, args...) 0
    If 'rows.%Size() {
        Set why = "no such row in " _ ns _ ": " _ $GET(args(1))
        Quit 0
    }
    Set row = rows.%Get(0)
    Quit 1
}

/// Runs one query in the namespace, with the columns named, into a list of objects. 1 only when the whole result was read;
/// 0 with why on a namespace it can't enter, a failed statement or a failure part way through: so an error is never
/// mistaken for no rows. Only stock classes while switched.
ClassMethod Query(ns As %String, sql As %String, columns As %String, Output rows As %DynamicArray, Output why As %String, args...) As %Boolean [ Private ]
{
    Set rows = [], why = "", ok = 0
    Try {
        If ns = "" {
            Set why = "no namespace"
            Quit
        }
        New $NAMESPACE
        Set $NAMESPACE = ns
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, sql, args...)
        If rs.%SQLCODE < 0 {
            Set why = "SQLCODE " _ rs.%SQLCODE _ " " _ rs.%Message
            Quit
        }
        Set sc = $$$OK
        Set count = $LENGTH(columns, ",")
        While rs.%Next(.sc) {
            Set row = {}
            For c = 1:1:count {
                Set name = $PIECE(columns, ",", c)
                Do row.%Set(name, rs.%Get(name))
            }
            Do rows.%Push(row)
        }
        If $$$ISERR(sc) {
            Set why = $SYSTEM.Status.GetErrorText(sc)
            Quit
        }
        If rs.%SQLCODE < 0 {
            Set why = "SQLCODE " _ rs.%SQLCODE _ " " _ rs.%Message
            Quit
        }
        Set ok = 1
    } Catch ex {
        Set why = ex.DisplayString(), ok = 0
    }
    Set:'ok rows = ""
    Quit ok
}

}
