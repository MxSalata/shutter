/// One incident per receiver: a receiver's outage, opened by the Receiver Watch. Every property the routes' JSON names lives
/// here, so a later writer fills a field the schema already holds, and ToJSON answers every field from the first moment: empty
/// lists, nothing computed, null where nothing has filled it. A row that is not closed holds ActiveReceiver, whose unique index
/// means one such row per receiver, whichever job gets there first.
Class Shutter.Store.Outage Extends %Persistent
{

/// Exact, as the profile's names are: two receivers that differ only in case are two rows.
Property Receiver As %String(COLLATION = "EXACT", MAXLEN = 128) [ Required ];

Index ReceiverIdx On Receiver;

/// The receiver's name while this row is not closed, empty after: what makes "one row per receiver" a fact of the store.
Property ActiveReceiver As %String(COLLATION = "EXACT", MAXLEN = 128);

Index ActiveIdx On ActiveReceiver [ Unique ];

Property Namespace As %String(MAXLEN = 64);

Property Item As %String(MAXLEN = 128);

Property State As %String(MAXLEN = 16, VALUELIST = ",open,draining,closing,offered,sending,needs_person,paused,closed") [ InitialExpression = "open" ];

Index StateIdx On State;

/// What the engine shows now; it can change between polls.
Property Kind As %String(MAXLEN = 16, VALUELIST = ",down,refusing,not_answering,cant_tell");

Property OpenedAt As %String(MAXLEN = 30);

Property DrainedAt As %String(MAXLEN = 30);

Property ClosedAt As %String(MAXLEN = 30);

Property CloseReason As %String(MAXLEN = 1000);

Property ClosedBy As %String(MAXLEN = 128);

/// The site's lines, as they read when the outage opened. The profile sets no length on them, so neither does this.
Property Runbook As %String(MAXLEN = "");

Property CallLine As %String(MAXLEN = "");

/// JSON: who may approve here.
Property Approvers As %String(MAXLEN = "");

Property PausedUntil As %String(MAXLEN = 30);

Property PausedBy As %String(MAXLEN = 128);

Property OverdueAt As %String(MAXLEN = 30);

Property WindowFrom As %String(MAXLEN = 30);

Property WindowTo As %String(MAXLEN = 30);

Property SettledCompleted As %Integer [ InitialExpression = 0 ];

Property SettledSuspended As %Integer [ InitialExpression = 0 ];

Property SettledError As %Integer [ InitialExpression = 0 ];

Property SettledOther As %Integer [ InitialExpression = 0 ];

/// JSON arrays, each [ { "at", "kind", "text" } ] for Alerts, [ Row ] for the four lists, [ { "caseId", "reason", "owner" } ]
/// for OpenCases. PutList writes them and ToJSON reads them.
Property Alerts As %Stream.GlobalCharacter;

Property ListQueued As %Stream.GlobalCharacter;

Property ListOffered As %Stream.GlobalCharacter;

Property ListReached As %Stream.GlobalCharacter;

Property ListRefused As %Stream.GlobalCharacter;

Property OpenCases As %Stream.GlobalCharacter;

/// Moves on every change of state: a stale copy changes nothing.
Property Version As %Integer [ InitialExpression = 1 ];

Property SetDigest As %String(MAXLEN = 128);

Property SetComputedAt As %String(MAXLEN = 30);

Property SetPolicyVersion As %String(MAXLEN = 64);

Property SetStatus As %String(MAXLEN = 16, VALUELIST = ",computed,not_computed,withheld") [ InitialExpression = "not_computed" ];

Property SetReason As %String(MAXLEN = 1000);

Property Approvable As %Boolean [ InitialExpression = 0 ];

/// JSON: { "id", "by", "givenAt", "goodUntil", "digest", "note" }, or empty.
Property Approval As %String(MAXLEN = 4000);

Property SentByShutter As %Integer [ InitialExpression = 0 ];

Property WordsFirst As %String(MAXLEN = 4000);

Property WordsDo As %String(MAXLEN = 4000);

Property WordsCall As %String(MAXLEN = 4000);

Property WordsCritical As %String(MAXLEN = 4000);

/// The row of a receiver that is not closed, or "".
ClassMethod ActiveFor(receiver As %String) As Shutter.Store.Outage
{
    If receiver = "" Quit ""
    Quit ..ActiveIdxOpen(receiver, 0)
}

/// Opens a receiver's outage from its profile entry, or finds the one already there: one row per receiver. opened says which.
ClassMethod Open(entry As %DynamicObject, kind As %String, why As %String, by As %String, Output outage As Shutter.Store.Outage, Output opened As %Boolean) As %Status
{
    Set outage = "", opened = 0
    Set receiver = entry.%Get("name")
    Lock +^Shutter.Outage("open", receiver):5
    If '$TEST Quit $$$ERROR($$$GeneralError, "The outage of " _ receiver _ " is locked")
    Set sc = $$$OK
    Try {
        Set outage = ..ActiveFor(receiver)
        If $ISOBJECT(outage) Quit
        Set outage = ..NewRow(entry, kind)
        Set sc = outage.%Save()
        If $$$ISERR(sc) Quit
        Set opened = 1
        Set sc = ##class(Shutter.Store.OutageEvent).Add(outage.%Id(), "opened", why, by)
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Lock -^Shutter.Outage("open", receiver)
    Quit sc
}

/// A new row from a profile entry, not saved.
ClassMethod NewRow(entry As %DynamicObject, kind As %String) As Shutter.Store.Outage [ Private ]
{
    Set json = "Shutter.Util.Json", profile = "Shutter.Store.SiteProfile"
    Set receiver = entry.%Get("name"), watch = entry.%Get("watch")
    Set row = ..%New()
    Set row.Receiver = receiver, row.ActiveReceiver = receiver, row.Kind = kind
    Set row.Namespace = $CLASSMETHOD(json, "Str", watch, "namespace"), row.Item = $CLASSMETHOD(json, "Str", watch, "item")
    Set row.Runbook = $CLASSMETHOD(json, "Str", entry, "runbook"), row.CallLine = $CLASSMETHOD(json, "Str", entry, "call")
    Set row.Approvers = ..ApproversOf(entry).%ToJSON()
    Set now = ##class(Shutter.Util.Time).NowUTC()
    Set row.OpenedAt = now
    Set minutes = ##class(Shutter.Store.SiteProfile).ReceiverMinutes(receiver, "window_minutes")
    Set row.WindowFrom = ##class(Shutter.Util.Time).PlusMillis(now, -60000 * $SELECT(minutes > 0: minutes, 1: 5))
    If '##class(%Dictionary.CompiledClass).%ExistsId("Shutter.Util.ResendSet") Set row.SetReason = "no set gate in this build"
    Quit row
}

/// Who may approve at this receiver: its own approvers, else the profile's escalation line.
ClassMethod ApproversOf(entry As %DynamicObject) As %DynamicArray
{
    If $ISOBJECT(entry.%Get("approvers")) Quit entry.%Get("approvers")
    Set out = []
    Set approvers = ##class(Shutter.Store.SiteProfile).Current().%Get("approvers")
    If $ISOBJECT(approvers) && (approvers.%Get("escalation") '= "") Do out.%Push(approvers.%Get("escalation"))
    Quit out
}

/// The kind the engine shows now, with an event when it changed. Under the row's lock, on what the store holds: only Kind
/// changes, and a closed row or a state moved since this copy was read stays as it is, so a poll's old copy never undoes a
/// person's act. It gives up quietly, with this copy reading the store, and the next poll reads the row again. No state moves
/// here, and the version with it.
Method SetKind(kind As %String, by As %String) As %Status
{
    If kind = ..Kind Quit $$$OK
    Set id = ..%Id()
    If id = "" Quit $$$ERROR($$$GeneralError, "This outage is not saved")
    Lock +^Shutter.Outage(id):5
    If '$TEST Quit $$$ERROR($$$GeneralError, "Outage " _ id _ " is locked")
    Set sc = $$$OK, state = ..State, version = ..Version
    Try {
        Set sc = ..%Reload()
        If $$$ISERR(sc) Quit
        If (..State = "closed") || (..State '= state) || (..Version '= version) Quit
        Set was = ..Kind
        If kind = was Quit
        Set ..Kind = kind
        Set sc = ..%Save()
        If $$$ISERR(sc) Quit
        Set sc = ##class(Shutter.Store.OutageEvent).Add(id, "kind", was _ " to " _ kind, by)
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    If $$$ISERR(sc) Do ..%Reload()
    Lock -^Shutter.Outage(id)
    Quit sc
}

/// "Down on purpose" until a time: a person's act, which withholds any set.
Method Pause(until As %String, by As %String) As %Status
{
    If until = "" Quit $$$ERROR($$$GeneralError, "A pause needs the time it ends")
    If by = "" Quit $$$ERROR($$$GeneralError, "A pause needs the person")
    Quit ..Move("paused", "until " _ until, by, until)
}

/// A person closes it, with a reason.
Method Close(reason As %String, by As %String) As %Status
{
    If reason = "" Quit $$$ERROR($$$GeneralError, "A close needs a reason")
    If by = "" Quit $$$ERROR($$$GeneralError, "A close needs the person")
    Quit ..Move("closed", reason, by)
}

/// One change of state, under the row's lock, on the version this copy read: a stale copy changes nothing, and a closed row
/// never changes. On any refusal this copy goes back to what the store holds.
Method Move(state As %String, detail As %String, by As %String, until As %String = "") As %Status [ Private ]
{
    Set id = ..%Id()
    If id = "" Quit $$$ERROR($$$GeneralError, "This outage is not saved")
    Lock +^Shutter.Outage(id):5
    If '$TEST Quit $$$ERROR($$$GeneralError, "Outage " _ id _ " is locked")
    Set sc = $$$OK, version = ..Version
    Try {
        Set sc = ..%Reload()
        If $$$ISERR(sc) Quit
        If ..Version '= version Set sc = $$$ERROR($$$GeneralError, "Outage " _ id _ " has moved on: read it again") Quit
        If ..State = "closed" Set sc = $$$ERROR($$$GeneralError, "Outage " _ id _ " is closed") Quit
        Set ..State = state, ..Version = version + 1
        If state = "closed" {
            Set ..ClosedAt = ##class(Shutter.Util.Time).NowUTC(), ..CloseReason = $EXTRACT(detail, 1, 1000), ..ClosedBy = by, ..ActiveReceiver = ""
            Set kind = "closed"
        } Else {
            Set ..PausedUntil = until, ..PausedBy = by, ..SetStatus = "withheld", ..SetReason = "down on purpose"
            Set kind = "paused"
        }
        Set sc = ..%Save()
        If $$$ISERR(sc) Quit
        Set sc = ##class(Shutter.Store.OutageEvent).Add(id, kind, detail, by)
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    If $$$ISERR(sc) Do ..%Reload()
    Lock -^Shutter.Outage(id)
    Quit sc
}

/// Replaces a JSON list: name is Alerts, ListQueued, ListOffered, ListReached, ListRefused or OpenCases. The caller saves.
Method PutList(name As %String, list As %DynamicArray) As %Status
{
    Set stream = $PROPERTY($THIS, name)
    Set sc = stream.Clear()
    If $$$ISERR(sc) Quit sc
    // %ToJSON into a stream answers no status, so success is said here.
    Do list.%ToJSON(stream)
    Quit $$$OK
}

/// A stored JSON list, or an empty one.
Method GetList(name As %String) As %DynamicArray
{
    Set stream = $PROPERTY($THIS, name)
    If 'stream.Size Quit []
    Do stream.Rewind()
    Quit [].%FromJSON(stream)
}

/// The Outage of the routes' JSON, every field present.
Method ToJSON() As %DynamicObject
{
    Set o = {"id": (..%Id() _ ""), "receiver": (..Receiver), "state": (..State)}
    Do ..Put(o, "namespace", ..Namespace), ..Put(o, "item", ..Item), ..Put(o, "kind", ..Kind)
    Do ..Put(o, "openedAt", ..OpenedAt), ..Put(o, "drainedAt", ..DrainedAt), ..Put(o, "closedAt", ..ClosedAt)
    Do ..Put(o, "runbook", ..Runbook), ..Put(o, "call", ..CallLine), ..Put(o, "pausedUntil", ..PausedUntil), ..Put(o, "overdueAt", ..OverdueAt)
    Set o.approvers = $SELECT(..Approvers '= "": [].%FromJSON(..Approvers), 1: [])
    Set o.readings = ##class(Shutter.Store.ReceiverReading).Last(..Receiver)
    Set window = {}
    Do ..Put(window, "from", ..WindowFrom), ..Put(window, "to", ..WindowTo)
    Set o.window = window
    Set o.settled = {"completed": (+..SettledCompleted), "suspended": (+..SettledSuspended), "error": (+..SettledError), "other": (+..SettledOther)}
    Set o.alerts = ..GetList("Alerts")
    Set o.lists = {"queued": (..GetList("ListQueued")), "offered": (..GetList("ListOffered")), "reached": (..GetList("ListReached")), "refused": (..GetList("ListRefused"))}
    Set o.openCases = ..GetList("OpenCases")
    Do o.%Set("version", +..Version, "number")
    Set set = {"status": (..SetStatus)}
    Do ..Put(set, "digest", ..SetDigest), ..Put(set, "computedAt", ..SetComputedAt), ..Put(set, "setPolicyVersion", ..SetPolicyVersion), ..Put(set, "reason", ..SetReason)
    Set o.set = set
    Do o.%Set("approvable", ''..Approvable, "boolean")
    If ..Approval '= "" {
        Set o.approval = {}.%FromJSON(..Approval)
    } Else {
        Do o.%Set("approval", "", "null")
    }
    Do o.%Set("sentByShutter", +..SentByShutter, "number")
    Set o.acts = $SELECT(..State = "closed": [], 1: ["pause", "close"])
    Set words = {}
    Do ..Put(words, "first", ..WordsFirst), ..Put(words, "do", ..WordsDo), ..Put(words, "call", ..WordsCall), ..Put(words, "critical", ..WordsCritical)
    Set o.words = words
    Quit o
}

/// A string, or null when nothing has filled it.
ClassMethod Put(o As %DynamicObject, key As %String, value As %String) [ Private ]
{
    If value = "" Do o.%Set(key, "", "null") Quit
    Do o.%Set(key, value)
}

}
