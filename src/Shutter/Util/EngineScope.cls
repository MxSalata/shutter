/// Whether the engine's hands can be read at a case's receiver: which production item the receiver names (ItemOf), and
/// whether that item's class has the stock HL7 TCP operation's delivery semantics (IsStockTcp). Both only read, and a
/// read that fails answers "unreadable", never a guess, so a write can't pass on an unknown. It lives in Shutter.Util
/// because that package is mapped into the watched namespace, and inside it only Ens and %Dictionary classes are
/// called. A namespace can be switched to from a production job, not from the approver's REST process.
Class Shutter.Util.EngineScope Extends %RegisteredObject
{

/// The stock operation whose delivery semantics the engine reads are measured on.
Parameter STOCKCLASS = "EnsLib.HL7.Operation.TCPOperation";

/// The answer when a production, an item or a class can't be read, from either method.
Parameter UNREADABLE = "unreadable";

/// The methods that decide what a reply means and how a message is sent.
Parameter METHODS = "OnGetReplyAction,OnReplyDocument,SendMessage,OnMessage";

/// The properties whose defaults change what a delivery does. GetReply is the adapter's on the stock class, so a
/// subclass declaring one is overriding it; see Overrides for a subclass that changes the adapter.
Parameter PROPERTIES = "FailureTimeout,ReplyCodeActions,GetReply";

/// Ens.MessageHeader's TargetBusinessType for a business operation.
Parameter OPERATIONTYPE = 3;

/// $$$eProductionStateRunning.
Parameter RUNNING = 1;

/// The production item a case's receiver names in namespace ns, or "unreadable". In order: the case's origin header's
/// target when that header is to a business operation; else the receiver's watch.item in the site profile; else the
/// receiver's name, or that name with its first word removed (a forwarder's ReceiverPrefix is put in front with a
/// space), when exactly one of the two is an item of the source production.
ClassMethod ItemOf(ns As %String, case As Shutter.Store.Case) As %String
{
    If (ns = "") || '$ISOBJECT(case) Quit ..#UNREADABLE
    Set answer = ..#UNREADABLE
    Try {
        // The site profile is in Shutter's own namespace, so it is read before the switch.
        Set watch = ..WatchItem(##class(Shutter.Store.SiteProfile).Receiver(case.Receiver))
        Set hid = case.OriginHeaderId, source = case.SourceProduction, receiver = case.Receiver
        New $NAMESPACE
        Set $NAMESPACE = ns
        Set target = ..OperationTarget(hid)
        If target '= "" Set answer = target Quit
        If source = "" {
            Set sc = ##class(Ens.Director).GetProductionStatus(.source, .state)
            If $$$ISERR(sc) Quit
        }
        Set answer = ..ItemFrom(..Definition(source), watch, receiver)
    } Catch ex {
        Set answer = ..#UNREADABLE
    }
    Quit answer
}

/// The item's delivery semantics in namespace ns, read from the definition of the production running there:
/// "yes" (the stock class, or a compiled subclass that overrides nothing relevant), "base" (a compiled subclass that
/// overrides any of it: unsupported for an automated resend, watched with its behaviour marked unknown), "no" (any other
/// class) or "unreadable" (the production is not running, or the production, the item or the class can't be read).
ClassMethod IsStockTcp(ns As %String, item As %String) As %String
{
    If (ns = "") || (item = "") || (item = ..#UNREADABLE) Quit ..#UNREADABLE
    Set answer = ..#UNREADABLE
    Try {
        New $NAMESPACE
        Set $NAMESPACE = ns
        Set name = "", state = ""
        Set sc = ##class(Ens.Director).GetProductionStatus(.name, .state)
        If $$$ISERR(sc) Quit
        Set answer = ..AnswerFor(name, state, item)
    } Catch ex {
        Set answer = ..#UNREADABLE
    }
    Quit answer
}

/// IsStockTcp's answer in this namespace for a production's name and state as Ens.Director reports them. Only a running
/// production counts: a stopped one's definition can have been edited since it ran.
ClassMethod AnswerFor(production As %String, state As %String, item As %String) As %String
{
    If state '= ..#RUNNING Quit ..#UNREADABLE
    Quit ..AnswerIn(..Definition(production), item)
}

/// IsStockTcp's answer for an item of a production definition (an Ens.Config.Production, saved or not).
ClassMethod AnswerIn(production As Ens.Config.Production, item As %String) As %String
{
    Quit ..ClassAnswer(..ItemClass(production, item))
}

/// IsStockTcp's answer for a class, in this namespace.
ClassMethod ClassAnswer(class As %String) As %String
{
    If class = "" Quit ..#UNREADABLE
    Set answer = ..#UNREADABLE
    Try {
        If '##class(%Dictionary.CompiledClass).%ExistsId(class) Quit
        If class = ..#STOCKCLASS Set answer = "yes" Quit
        If '$CLASSMETHOD(class, "%Extends", ..#STOCKCLASS) Set answer = "no" Quit
        Set answer = $SELECT(..Overrides(class): "base", 1: "yes")
    } Catch ex {
        Set answer = ..#UNREADABLE
    }
    Quit answer
}

/// True when a compiled subclass of the stock class has its own reply handling, sending or relevant defaults: a member's
/// origin differs from the stock class's, whichever class in the stock chain defines it on this build. Another adapter
/// counts too, since it does the sending and holds GetReply's default.
ClassMethod Overrides(class As %String) As %Boolean
{
    Set stock = ..#STOCKCLASS
    If $PARAMETER(class, "ADAPTER") '= $PARAMETER(stock, "ADAPTER") Quit 1
    Set found = 0
    For kind = "Method", "Property" {
        Set names = $SELECT(kind = "Method": ..#METHODS, 1: ..#PROPERTIES)
        For n = 1:1:$LENGTH(names, ",") {
            Set name = $PIECE(names, ",", n)
            If ..Origin(kind, class, name) '= ..Origin(kind, stock, name) Set found = 1
        }
    }
    Quit found
}

/// The class that defines a compiled member, or "" when the class has no such member.
ClassMethod Origin(kind As %String, class As %String, name As %String) As %String [ Private ]
{
    Set member = $CLASSMETHOD("%Dictionary.Compiled" _ kind, "%OpenId", class _ "||" _ name, 0)
    Quit $SELECT($ISOBJECT(member): member.Origin, 1: "")
}

/// The item ItemOf's last three steps name in a production definition, or "unreadable". A watch block's item is the
/// site's own word, so one the production doesn't hold is unreadable, not a reason to guess from the receiver's name.
ClassMethod ItemFrom(production As Ens.Config.Production, watch As %String, receiver As %String) As %String
{
    If '$ISOBJECT(production) Quit ..#UNREADABLE
    If watch '= "" Quit $SELECT(..HasItem(production, watch): watch, 1: ..#UNREADABLE)
    If receiver = "" Quit ..#UNREADABLE
    Set shorter = $PIECE(receiver, " ", 2, *)
    Set bare = ..HasItem(production, receiver), prefixed = (shorter '= "") && ..HasItem(production, shorter)
    If bare && prefixed Quit ..#UNREADABLE
    If bare Quit receiver
    If prefixed Quit shorter
    Quit ..#UNREADABLE
}

/// The item a profile entry's watch block names, or "".
ClassMethod WatchItem(entry) As %String
{
    If '$ISOBJECT(entry) Quit ""
    Set watch = entry.%Get("watch")
    If '$ISOBJECT(watch) Quit ""
    Quit ##class(Shutter.Util.Json).Str(watch, "item")
}

/// The target of a header to a business operation, in this namespace, or "" for any other header or none.
ClassMethod OperationTarget(headerId As %String) As %String [ Private ]
{
    If headerId = "" Quit ""
    Set header = ##class(Ens.MessageHeader).%OpenId(headerId, 0)
    If '$ISOBJECT(header) Quit ""
    Quit $SELECT(header.TargetBusinessType = ..#OPERATIONTYPE: header.TargetConfigName, 1: "")
}

/// A production's saved definition in this namespace, or "".
ClassMethod Definition(name As %String) As Ens.Config.Production [ Private ]
{
    If name = "" Quit ""
    Quit ##class(Ens.Config.Production).%OpenId(name, 0)
}

ClassMethod HasItem(production As Ens.Config.Production, name As %String) As %Boolean [ Private ]
{
    For i = 1:1:production.Items.Count() {
        If production.Items.GetAt(i).Name = name Return 1
    }
    Quit 0
}

/// The class of a named item, or "". A production can hold two items of one name with one enabled, and that one is the
/// item; with no such single one, the name doesn't say which class runs.
ClassMethod ItemClass(production As Ens.Config.Production, name As %String) As %String
{
    If '$ISOBJECT(production) || (name = "") Quit ""
    Set named = 0, enabled = 0, class = "", enabledClass = ""
    For i = 1:1:production.Items.Count() {
        Set item = production.Items.GetAt(i)
        Continue:item.Name'=name
        Set named = named + 1, class = item.ClassName
        If item.Enabled Set enabled = enabled + 1, enabledClass = item.ClassName
    }
    If named = 1 Quit class
    Quit $SELECT(enabled = 1: enabledClass, 1: "")
}

}
