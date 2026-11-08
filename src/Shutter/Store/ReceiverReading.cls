/// The last reading of one watched receiver, overwritten by the Receiver Watch on each poll: what the engine showed, and
/// nothing a receiver was asked. Last and All are the named reads. A failed read is stored as unknown, and a row the watcher
/// has stopped writing reads unknown with its last stamp, so neither can ever look healthy.
Class Shutter.Store.ReceiverReading Extends %Persistent
{

/// Past this many seconds without a write, the row says nothing about now.
Parameter STALESECONDS = 60;

/// Exact, as the profile's names are: two receivers that differ only in case are two rows.
Property Receiver As %String(COLLATION = "EXACT", MAXLEN = 128) [ Required ];

Index ReceiverIdx On Receiver [ Unique ];

Property Namespace As %String(MAXLEN = 64);

Property Item As %String(MAXLEN = 128);

/// healthy, slow, down, refusing, not_answering, cant_tell or unknown.
Property Reading As %String(MAXLEN = 16);

Property Status As %String(MAXLEN = 32);

Property AdapterState As %String(MAXLEN = 128);

Property Queue As %String(MAXLEN = 12);

Property HeadHeaderId As %String(MAXLEN = 20);

/// What the job list shows, a check on the head. Empty means unknown, not none.
Property ActiveMessage As %String(MAXLEN = 20);

Property FailureTimeout As %String(MAXLEN = 12);

/// unlimited, bounded, none or unknown.
Property Retry As %String(MAXLEN = 12);

Property DefCharEncoding As %String(MAXLEN = 64);

/// The item's effective string, never an assumed one.
Property ReplyCodeActions As %String(MAXLEN = "");

/// 1 when ReplyCodeActions is the engine's own default string.
Property ReplyCodeActionsStock As %Boolean;

Property GetReply As %String(MAXLEN = 12);

Property StayConnected As %String(MAXLEN = 12);

/// JSON: { setting: "item"|"class_default"|"unknown" }.
Property SettingSources As %String(MAXLEN = 1000);

/// JSON: the names of the fields that could not be read.
Property UnknownFields As %String(MAXLEN = 1000);

/// Why the reading is unknown, in the engine's words.
Property Why As %String(MAXLEN = 1000);

Property CheckedAt As %String(MAXLEN = 30);

/// When the unbroken run of "down" readings began, or empty. The poll's clock.
Property DownSince As %String(MAXLEN = 30);

/// The head message the last poll saw, whatever it read: "the same head across two polls".
Property LastHead As %String(MAXLEN = 20);

/// The newest Error header to the item already judged, so that a new one can be told from one seen before.
Property ErrorHeaderMark As %String(MAXLEN = 20);

/// The row of one receiver, or "".
ClassMethod Find(receiver As %String) As Shutter.Store.ReceiverReading
{
    If receiver = "" Quit ""
    Quit ..ReceiverIdxOpen(receiver, 0)
}

/// The named read of one receiver's stored reading, as the routes give it. A receiver with no row yet reads unknown.
ClassMethod Last(receiver As %String) As %DynamicObject
{
    Set row = ..Find(receiver)
    If $ISOBJECT(row) Quit row.ToJSON()
    Set o = {"receiver": (receiver), "reading": "unknown", "why": "not read yet"}
    For key = "namespace", "item", "status", "adapterState", "queue", "headHeaderId", "activeMessage", "failureTimeout", "defCharEncoding", "replyCodeActions", "replyCodeActionsStock", "getReply", "stayConnected", "checkedAt" {
        Do o.%Set(key, "", "null")
    }
    Set o.retry = "unknown", o.settingSources = {}, o.unknownFields = []
    Quit o
}

/// The always-on line: one reading per receiver the profile watches now, none on a profile without a watch block.
ClassMethod All() As %DynamicArray
{
    Set out = []
    Set iter = ##class(Shutter.Store.SiteProfile).WatchedReceivers().%GetIterator()
    While iter.%GetNext(.i, .entry) {
        Do out.%Push(..Last(entry.%Get("name")))
    }
    Quit out
}

/// Whether a row stamped checkedAt says nothing about now.
ClassMethod Stale(checkedAt As %String, now As %String) As %Boolean
{
    Set millis = ##class(Shutter.Util.Time).MillisBetween(checkedAt, now)
    If millis = "" Quit 1
    Quit millis > (..#STALESECONDS * 1000)
}

/// The Reading of the routes' JSON. now is for a test; a stale row reads unknown with its last checkedAt.
Method ToJSON(now As %String = "") As %DynamicObject
{
    If now = "" Set now = ##class(Shutter.Util.Time).NowUTC()
    Set stale = ..Stale(..CheckedAt, now)
    Set o = {"receiver": (..Receiver), "reading": ($SELECT(stale: "unknown", 1: ..Reading)), "retry": ($SELECT(..Retry '= "": ..Retry, 1: "unknown"))}
    Do ..Put(o, "namespace", ..Namespace), ..Put(o, "item", ..Item), ..Put(o, "status", ..Status), ..Put(o, "adapterState", ..AdapterState)
    Do ..Put(o, "queue", ..Queue, "number"), ..Put(o, "headHeaderId", ..HeadHeaderId), ..Put(o, "activeMessage", ..ActiveMessage)
    Do ..Put(o, "failureTimeout", ..FailureTimeout, "number"), ..Put(o, "defCharEncoding", ..DefCharEncoding), ..Put(o, "replyCodeActions", ..ReplyCodeActions)
    Do ..Put(o, "replyCodeActionsStock", ..ReplyCodeActionsStock, "boolean"), ..Put(o, "getReply", ..GetReply, "number"), ..Put(o, "stayConnected", ..StayConnected, "number")
    Do ..Put(o, "checkedAt", ..CheckedAt)
    Set o.settingSources = $SELECT(..SettingSources '= "": {}.%FromJSON(..SettingSources), 1: {})
    Set o.unknownFields = $SELECT(..UnknownFields '= "": [].%FromJSON(..UnknownFields), 1: [])
    If stale {
        Set o.why = "the watcher has not written for over " _ ..#STALESECONDS _ " s"
    } Else {
        Do ..Put(o, "why", ..Why)
    }
    Quit o
}

/// A value by its type, or null when it was not read.
ClassMethod Put(o As %DynamicObject, key As %String, value As %String, type As %String = "string") [ Private ]
{
    If value = "" Do o.%Set(key, "", "null") Quit
    Do o.%Set(key, $SELECT(type = "string": value, type = "boolean": ''value, 1: +value), type)
}

}
