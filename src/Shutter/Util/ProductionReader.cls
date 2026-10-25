/// Reads one production, in its own namespace, for the production review (docs/CONTRACTS.md, section 13): its items
/// with the settings their definition sets, the system default settings, the class defaults of the settings the review
/// checks, the event log's errors and the message headers' failures over a window, the queues, the rule log's errors
/// and the message purge task, as plain data in a %DynamicObject. It lives in Shutter.Util because that package is
/// mapped into the watched namespace; the checks (Shutter.Review) run back in Shutter's own namespace on what it returns.
/// It reads only: no lock is taken (the production is opened with concurrency 0 and its state comes from the
/// ProductionStatus query, never from a Set method of Ens.Director), and a failure to read becomes data.error and a
/// failed status, never an exception. Inside the other namespace only Ens, %SQL, %Dictionary and %SYS classes are called,
/// so the read does not depend on what else is mapped there.
Class Shutter.Util.ProductionReader Extends %RegisteredObject
{

/// The properties whose class defaults (InitialExpression) are read for every item class and adapter class present.
Parameter PROPERTIES = "FailureTimeout,RetryInterval,ReplyCodeActions,AlertOnError,AlertGroups,QueueCountAlert,QueueWaitAlert,InactivityTimeout,ArchiveIO,Framing,NoFailWhileDisconnected,ResponseTimeout,IPAddress,Port";

/// The most groups the error and header queries return.
Parameter TOPGROUPS = 50;

/// The production's data. windowFrom is an ISO UTC time (2026-10-18T09:00:00Z): errors, failed headers and rule errors
/// from then on. Returns a failed status, with data.error set, when the namespace or the production cannot be read; the
/// other blocks are then empty.
ClassMethod Read(namespace As %String, production As %String, windowFrom As %String, Output data As %DynamicObject) As %Status
{
    Set data = ..Empty(namespace, production)
    Set sc = ..Collect(namespace, production, windowFrom, data)
    If $$$ISERR(sc) {
        If data.error = "" Set data.error = $SYSTEM.Status.GetErrorText(sc)
        Quit sc
    }
    // The message store writes times in the ODBC form, UTC; the review speaks ISO.
    Set iter = data.logErrors.%GetIterator()
    While iter.%GetNext(.i, .g) {
        Set g.latestAt = ..Iso(g.latestAt)
    }
    Set iter = data.headerErrors.%GetIterator()
    While iter.%GetNext(.i, .g) {
        Set g.latestAt = ..Iso(g.latestAt)
    }
    Set iter = data.queues.%GetIterator()
    While iter.%GetNext(.i, .q) {
        Set q.created = ..Iso(q.created)
    }
    Do ..MergeLogGroups(data)
    Set psc = ..PurgeTask(namespace, .task)
    If $$$ISOK(psc) && $ISOBJECT(task) {
        Set data.purgeTask = task
    } Else {
        Set data.purgeTaskError = $SELECT($$$ISERR(psc): $SYSTEM.Status.GetErrorText(psc), 1: "the purge task could not be read")
    }
    Try {
        Set data.host = $SYSTEM.INetInfo.LocalHostName()
    } Catch ex {
        Set data.host = ""
    }
    Quit $$$OK
}

/// The productions defined in a namespace with their states: [{production, state}], state in lower case (running,
/// stopped, suspended, troubled). Empty when the namespace does not exist or cannot be read.
ClassMethod Productions(namespace As %String) As %DynamicArray
{
    Set out = []
    Try {
        If '##class(%SYS.Namespace).Exists(namespace) Quit
        New $NAMESPACE
        Set $NAMESPACE = namespace
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT Production, Status, StatusEnum FROM Ens_Config.Production_ProductionStatus()")
        While rs.%Next() {
            Set p = {}
            Set p.production = rs.%Get("Production")
            Set p.state = $ZCONVERT(rs.%Get("Status"), "L")
            Do out.%Push(p)
        }
    } Catch ex {
    }
    Quit out
}

/// A production's state in its namespace: running, stopped, suspended, troubled, or "another production running" when
/// it is stopped while another production of the namespace runs; "" when the namespace or the production is not there.
ClassMethod State(namespace As %String, production As %String) As %String
{
    Quit ..StateIn(..Productions(namespace), production)
}

/// A production's state from a Productions() list (see State).
ClassMethod StateIn(productions As %DynamicArray, production As %String) As %String
{
    Set state = "", other = 0
    Set iter = productions.%GetIterator()
    While iter.%GetNext(.i, .p) {
        If p.production = production {
            Set state = p.state
        } ElseIf p.state = "running" {
            Set other = 1
        }
    }
    If (state '= "") && (state '= "running") && other Set state = "another production running"
    Quit state
}

/// An error text's signature: the text before its first colon, and before a hash that is not an error number (a
/// process's instance number, "Terminating BP ADT to Downstream # due to error"), stripped and clipped to 120. The
/// demo's "ERROR <Ens>ErrBPTerminated: Terminating BP ADT to Downstream # due to error: ..." gives
/// "ERROR <Ens>ErrBPTerminated"; "ERROR #5001: Delivery unavailable" keeps its number, "ERROR #5001".
ClassMethod Signature(text As %String) As %String
{
    Set s = $PIECE(text, ":", 1)
    Set p = $FIND(s, "#")
    While p > 0 {
        If $EXTRACT(s, p) ?1N {
            Set p = $FIND(s, "#", p)
        } Else {
            Set s = $EXTRACT(s, 1, p - 2)
            Set p = 0
        }
    }
    Quit $EXTRACT($ZSTRIP(s, "<>W"), 1, 120)
}

/// An ODBC timestamp (2026-10-25 07:45:45.133, UTC) as ISO UTC to the second; "" stays "".
ClassMethod Iso(odbc As %String) As %String
{
    If odbc = "" Quit ""
    If $EXTRACT(odbc, *) = "Z" Quit odbc
    Quit $TRANSLATE($PIECE(odbc, ".", 1), " ", "T") _ "Z"
}

/// The empty shape, so that a caller can rely on every block being there.
ClassMethod Empty(namespace As %String, production As %String) As %DynamicObject [ Private ]
{
    Set data = {}
    Set data.namespace = namespace
    Set data.production = production
    Set data.productionState = ""
    Set data.items = []
    Set data.defaultSettings = []
    Set data.classDefaults = {}
    Do data.%Set("alertItemPresent", 0, "boolean")
    Set data.logErrors = []
    Set data.headerErrors = []
    Set data.queues = []
    Set data.ruleErrors = []
    Do data.%Set("purgeTask", "", "null")
    Set data.host = ""
    Set data.readAt = ##class(Shutter.Util.Time).NowUTC()
    Set data.error = ""
    Quit data
}

/// The reads in the production's namespace. Everything here runs after the switch, so it calls only classes every
/// interoperability namespace has.
ClassMethod Collect(namespace As %String, production As %String, windowFrom As %String, data As %DynamicObject) As %Status [ Private ]
{
    Set sc = $$$OK
    Try {
        If '##class(%SYS.Namespace).Exists(namespace) {
            Set data.error = "the namespace " _ namespace _ " does not exist"
            Set sc = $$$ERROR($$$GeneralError, data.error)
            Quit
        }
        New $NAMESPACE
        Set $NAMESPACE = namespace
        Set odbcFrom = $TRANSLATE($PIECE(windowFrom, "Z", 1), "T", " ")
        Set top = +..#TOPGROUPS
        // The production and its items, with the settings the definition sets (the overrides; the rest come from the
        // default settings and the class defaults below).
        Set prod = ##class(Ens.Config.Production).%OpenId(production, 0, .osc)
        If '$ISOBJECT(prod) {
            Set data.error = "the production " _ production _ " is not defined in the namespace " _ namespace
            Set sc = $$$ERROR($$$GeneralError, data.error)
            Quit
        }
        Set items = [], classes = "", alert = 0
        For i = 1:1:prod.Items.Count() {
            Set item = prod.Items.GetAt(i)
            Set o = {}
            Set o.name = item.Name
            Set o.className = item.ClassName
            Set adapter = ""
            Try {
                Set adapter = item.AdapterClassName()
            } Catch inner {
                Set adapter = ""
            }
            Set o.adapterClassName = adapter
            Set bt = ""
            Try {
                Set bt = item.BusinessType()
            } Catch inner {
                Set bt = ""
            }
            Set o.businessType = $CASE(bt, 1: "service", 2: "process", 3: "operation", : $ZCONVERT(bt, "L"))
            Do o.%Set("enabled", ''item.Enabled, "boolean")
            Set o.poolSize = +item.PoolSize
            Set o.category = item.Category
            Set groups = ""
            Try {
                Set groups = item.AlertGroups
            } Catch inner {
                Set groups = ""
            }
            Set o.alertGroups = groups
            Set o.comment = item.Comment
            Set settings = []
            For j = 1:1:item.Settings.Count() {
                Set st = item.Settings.GetAt(j)
                Set s = {}
                Set s.name = st.Name
                Set s.target = st.Target
                Set s.value = st.Value
                Do settings.%Push(s)
            }
            Set o.settings = settings
            Do items.%Push(o)
            If (item.ClassName = "Ens.Alert") || (item.Name = "Ens.Alert") Set alert = 1
            If 'alert && (item.ClassName '= "") && ##class(%Dictionary.CompiledClass).%ExistsId(item.ClassName) {
                Try {
                    If $CLASSMETHOD(item.ClassName, "%Extends", "Ens.Alert") Set alert = 1
                } Catch inner {
                }
            }
            If (item.ClassName '= "") && '$LISTFIND(classes, item.ClassName) Set classes = classes _ $LISTBUILD(item.ClassName)
            If (adapter '= "") && '$LISTFIND(classes, adapter) Set classes = classes _ $LISTBUILD(adapter)
        }
        Set data.items = items
        Do data.%Set("alertItemPresent", alert, "boolean")
        // The class defaults: the InitialExpression of each checked property, for every item and adapter class present.
        // The dictionary lists inherited properties under the class, and quotes string values.
        Set names = ""
        For k = 1:1:$LENGTH(..#PROPERTIES, ",") {
            Set names = names _ $SELECT(names = "": "", 1: ", ") _ "'" _ $PIECE(..#PROPERTIES, ",", k) _ "'"
        }
        Set defaults = {}
        For k = 1:1:$LISTLENGTH(classes) {
            Set class = $LIST(classes, k)
            Set d = {}
            Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT Name, InitialExpression FROM %Dictionary.CompiledProperty WHERE parent = ? AND Name IN (" _ names _ ")", class)
            While rs.%Next() {
                Set v = rs.%Get("InitialExpression")
                If ($LENGTH(v) >= 2) && ($EXTRACT(v, 1) = """") && ($EXTRACT(v, *) = """") Set v = $REPLACE($EXTRACT(v, 2, * - 1), """""", """")
                Do d.%Set(rs.%Get("Name"), v)
            }
            Do defaults.%Set(class, d)
        }
        Set data.classDefaults = defaults
        // The system default settings for the production (and the rows for every production).
        Set ds = []
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ProductionName, ItemName, HostClassName, SettingName, SettingValue FROM Ens_Config.DefaultSettings WHERE ProductionName = ? OR ProductionName = '*' ORDER BY ID", production)
        While rs.%Next() {
            Set r = {}
            Set r.productionName = rs.%Get("ProductionName")
            Set r.itemName = rs.%Get("ItemName")
            Set r.hostClassName = rs.%Get("HostClassName")
            Set r.settingName = rs.%Get("SettingName")
            Set r.settingValue = rs.%Get("SettingValue")
            Do ds.%Push(r)
        }
        Set data.defaultSettings = ds
        // The state, from the status query (no production lock).
        Set state = "unknown", other = 0
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT Production, Status, StatusEnum FROM Ens_Config.Production_ProductionStatus()")
        While rs.%Next() {
            If rs.%Get("Production") = production {
                Set state = $ZCONVERT(rs.%Get("Status"), "L")
            } ElseIf +rs.%Get("StatusEnum") = 1 {
                Set other = 1
            }
        }
        If (state '= "running") && other Set state = "another production running"
        Set data.productionState = state
        // The event log's errors in the window, grouped by item, source and the text before its first colon; the latest
        // text of each group as the example. GROUP BY on these columns would return upper case, hence %EXACT.
        Set logs = []
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP " _ top _ " %EXACT(ConfigName) AS ConfigName, %EXACT(SourceClass) AS SourceClass, %EXACT(SourceMethod) AS SourceMethod, $EXTRACT($PIECE(Text, ':', 1), 1, 120) AS Sig, COUNT(*) AS N, MAX(ID) AS LatestId, MAX(TimeLogged) AS LatestAt, MAX(MessageId) AS LatestMessageId FROM Ens_Util.Log WHERE Type = 2 AND TimeLogged >= ? GROUP BY %EXACT(ConfigName), %EXACT(SourceClass), %EXACT(SourceMethod), $EXTRACT($PIECE(Text, ':', 1), 1, 120) ORDER BY N DESC", odbcFrom)
        While rs.%Next() {
            Set g = {}
            Set g.configName = rs.%Get("ConfigName")
            Set g.sourceClass = rs.%Get("SourceClass")
            Set g.sourceMethod = rs.%Get("SourceMethod")
            Set g.signature = rs.%Get("Sig")
            Set g.count = +rs.%Get("N")
            Set g.latestId = rs.%Get("LatestId")
            Set g.latestAt = rs.%Get("LatestAt")
            Set g.latestMessageId = rs.%Get("LatestMessageId")
            Set g.exampleText = ""
            Set row = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT Text FROM Ens_Util.Log WHERE ID = ?", g.latestId)
            If row.%Next() Set g.exampleText = $EXTRACT(row.%Get("Text"), 1, 500)
            Do logs.%Push(g)
        }
        Set data.logErrors = logs
        // The headers that ended suspended (5), aborted (7) or in error (8) in the window, by target, source and status.
        Set hdrs = []
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP " _ top _ " %EXACT(TargetConfigName) AS Target, %EXACT(SourceConfigName) AS Source, Status, COUNT(*) AS N, MAX(ID) AS LatestId, MAX(TimeCreated) AS LatestAt FROM Ens.MessageHeader WHERE Status IN (5, 7, 8) AND TimeCreated >= ? GROUP BY %EXACT(TargetConfigName), %EXACT(SourceConfigName), Status ORDER BY N DESC", odbcFrom)
        While rs.%Next() {
            Set h = {}
            Set h.target = rs.%Get("Target")
            Set h.source = rs.%Get("Source")
            Set h.status = +rs.%Get("Status")
            Set h.count = +rs.%Get("N")
            Set h.latestId = rs.%Get("LatestId")
            Set h.latestAt = rs.%Get("LatestAt")
            Do hdrs.%Push(h)
        }
        Set data.headerErrors = hdrs
        // The queues of the running production (none when it is stopped). Count is a reserved word.
        Set queues = []
        Try {
            Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT Name, ""Count"", Created FROM Ens.Queue_Enumerate()")
            While rs.%Next() {
                Set q = {}
                Set q.name = rs.%Get("Name")
                Set q.count = +rs.%Get("Count")
                Set q.created = rs.%Get("Created")
                Do queues.%Push(q)
            }
        } Catch inner {
        }
        Set data.queues = queues
        // The rule log's errors in the window, by rule; the latest message of each as the example.
        Set rules = []
        Try {
            Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP " _ top _ " %EXACT(RuleName) AS RuleName, %EXACT(RuleSet) AS RuleSet, COUNT(*) AS N, MAX(ID) AS LatestId FROM Ens_Rule.Log WHERE IsError = 1 AND TimeExecuted >= ? GROUP BY %EXACT(RuleName), %EXACT(RuleSet) ORDER BY N DESC", odbcFrom)
            While rs.%Next() {
                Set r = {}
                Set r.ruleName = rs.%Get("RuleName")
                Set r.ruleSet = rs.%Get("RuleSet")
                Set r.count = +rs.%Get("N")
                Set r.latestId = rs.%Get("LatestId")
                Set r.errorMsg = ""
                Set row = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ErrorMsg FROM Ens_Rule.Log WHERE ID = ?", r.latestId)
                If row.%Next() Set r.errorMsg = $EXTRACT(row.%Get("ErrorMsg"), 1, 300)
                Do rules.%Push(r)
            }
        } Catch inner {
        }
        Set data.ruleErrors = rules
    } Catch ex {
        Set data.error = ex.DisplayString()
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// The log groups merged by item and refined signature (Signature): the SQL groups by the text before the first colon,
/// and the hash rule can make two of those one. Counts add up; the latest row's id, time and text stand for the group.
ClassMethod MergeLogGroups(data As %DynamicObject) [ Private ]
{
    Kill groups, order
    Set n = 0
    Set iter = data.logErrors.%GetIterator()
    While iter.%GetNext(.i, .g) {
        Set g.signature = ..Signature(g.signature)
        Set key = g.configName _ "|" _ g.signature
        If '$DATA(groups(key)) {
            Set n = n + 1, groups(key) = g, order(n) = key
            Continue
        }
        Set kept = groups(key)
        Set kept.count = kept.count + g.count
        If +g.latestId > +kept.latestId {
            Set kept.latestId = g.latestId
            Set kept.latestAt = g.latestAt
            Set kept.latestMessageId = g.latestMessageId
            Set kept.exampleText = g.exampleText
            Set kept.sourceClass = g.sourceClass
            Set kept.sourceMethod = g.sourceMethod
        }
    }
    Set out = []
    For k = 1:1:n {
        Do out.%Push(groups(order(k)))
    }
    Set data.logErrors = out
}

/// The message purge task of a namespace, read in %SYS: {present, suspended, daysToKeep, bodiesToo, keepIntegrity,
/// typesToPurge, lastFinished}. A failed status (no access to %SYS) leaves task "".
ClassMethod PurgeTask(namespace As %String, Output task As %DynamicObject) As %Status [ Private ]
{
    Set task = {}
    Do task.%Set("present", 0, "boolean")
    Do task.%Set("suspended", 0, "boolean")
    Do task.%Set("daysToKeep", "", "null")
    Do task.%Set("bodiesToo", "", "null")
    Do task.%Set("keepIntegrity", "", "null")
    Set task.typesToPurge = ""
    Set task.lastFinished = ""
    Set sc = $$$OK
    Try {
        New $NAMESPACE
        Set $NAMESPACE = "%SYS"
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM %SYS.Task WHERE TaskClass = 'Ens.Util.Tasks.Purge' AND NameSpace = ? ORDER BY ID", $ZCONVERT(namespace, "U"))
        While rs.%Next() {
            Set t = ##class(%SYS.Task).%OpenId(rs.%Get("ID"), 0)
            Continue:'$ISOBJECT(t)
            Do task.%Set("present", 1, "boolean")
            Do task.%Set("suspended", (+t.Suspended > 0), "boolean")
            If $LISTVALID(t.Settings) {
                For i = 1:2:$LISTLENGTH(t.Settings) {
                    Set name = $LISTGET(t.Settings, i), value = $LISTGET(t.Settings, i + 1)
                    If name = "NumberOfDaysToKeep" Set task.daysToKeep = +value
                    If name = "BodiesToo" Do task.%Set("bodiesToo", ''value, "boolean")
                    If name = "KeepIntegrity" Do task.%Set("keepIntegrity", ''value, "boolean")
                    If name = "TypesToPurge" Set task.typesToPurge = value
                }
            }
            // LastFinished is a $HOROLOG value in local time; 0 when the task never finished.
            Set last = t.LastFinished
            If $MATCH(last, "^[0-9]+,[0-9]+(\.[0-9]+)?$") {
                Set h = last
                Try {
                    Set h = $SYSTEM.Util.LocalWithZTIMEZONEtoUTC(last)
                } Catch inner {
                    Set h = last
                }
                Set task.lastFinished = $ZDATE(+h, 3) _ "T" _ $ZTIME($PIECE(h, ",", 2) \ 1, 1) _ "Z"
            }
            // The first task of the class for the namespace is the one the review reports.
            Quit
        }
    } Catch ex {
        Set sc = ex.AsStatus()
        Set task = ""
    }
    Quit sc
}

}
