/// What the engine's own words and settings can honestly be taken to say about one delivery. Pure: every answer comes from
/// the arguments, so a caller reads the instance first and judges here, and the tables are tested with no instance state.
/// Classify in Shutter.Intake.AlertProcess keeps its own meanings: it chooses a case's kind, and this chooses what may be said
/// or listed. Every receiver wording in the tests was made up for them.
Class Shutter.Util.EngineWords
{

/// The reason EffectiveAck gives when the operation awaits no reply.
Parameter REASONGETREPLYOFF = "GetReply off";

/// The reason EffectiveAck gives when the reply settings could not be read, or do not parse as the engine would read them.
Parameter REASONUNREADABLE = "reply actions unreadable";

/// The reason's words for a string with no action that stops codes its other patterns leave unmatched.
Parameter REASONNOCATCHALL = "codes no pattern names (no :* that stops them)";

/// The reason's words for a string with no action that stops a reply with no MSA.
Parameter REASONNONOMSA = "replies with no MSA (no :~ that stops them)";

/// The engine's own value when an operation's ReplyCodeActions is empty.
Parameter STOCKREPLYACTIONS = ":?R=RF,:?E=S,:~=S,:?A=C,:*=S,:I?=W,:T?=C";

/// A failed connect, the whole of its words up to the optional alert suffix.
Parameter CONNECTEXPIRED = "ERROR <Ens>ErrOutConnectExpired: TCP Connect timeout period \(\d+\) expired for [^\s()]+:\d+";

/// What the engine writes around a last attempt's words when FailureTimeout runs out.
Parameter FAILURETIMEOUT = "ERROR <Ens>ErrFailureTimeout: FailureTimeout of \d+ seconds exceeded in [%\w.]+; status from last attempt was ";

/// The type 6 copy of a row carries this after the words.
Parameter ALERTSUFFIX = "( \(alert request ID=\d+\))?";

/// Judges every retained error row for one delivery header: a %DynamicArray of objects, each with "text" (the row's
/// words) and "messageId" (the header the row names, empty when it names none). Answers one of:
/// <ul><li><b>never_opened</b>: at least one row, and every row is a failed connect, or FailureTimeout wrapping only that.
/// This describes the retained evidence: it does not by itself certify every delivery attempt, since a purged log has lost
/// rows and a repeat of the same words writes none. It may put a message on a list for a person; a send needs more.</li>
/// <li><b>reached_receiver</b>: any row shows the frame reached the receiver (a lost read, a read timeout, a reply's code).
/// This outranks every other row, because a later "never opened" says nothing about an earlier attempt.</li>
/// <li><b>unknown</b>: a row with words the table does not hold, a row naming no header, or anything but an array, such as
/// a reader's answer that it could not read. The match is anchored, so a known word inside other words is not enough.</li>
/// <li><b>no_rows</b>: an empty array.</li></ul>
ClassMethod Attempts(rows As %DynamicArray) As %String
{
    Quit:'$ISOBJECT(rows) "unknown"
    Quit:'rows.%IsA("%Library.DynamicArray") "unknown"
    Quit:rows.%Size()=0 "no_rows"
    Set answer = "never_opened"
    Set iterator = rows.%GetIterator()
    While iterator.%GetNext(.index, .row) {
        Set kind = ..RowKind(row)
        Quit:kind="reached_receiver"
        Set:kind="unknown" answer = "unknown"
    }
    Quit $SELECT(kind="reached_receiver": kind, 1: answer)
}

/// One row: never_opened, reached_receiver or unknown. A row naming no header could be any message's, so its words
/// count for nothing here.
ClassMethod RowKind(row As %DynamicObject) As %String [ Private ]
{
    Quit:'$ISOBJECT(row) "unknown"
    Quit:'row.%IsA("%Library.DynamicObject") "unknown"
    Quit:row.%Get("messageId")="" "unknown"
    Set text = row.%Get("text")
    If (text [ "ErrOutConnectionLost") && (text [ "HL7 Read") Quit "reached_receiver"
    If (text [ "ErrTCPTerminatedReadTimeoutExpired") || (text [ "Suspending HL7 Message") Quit "reached_receiver"
    If (text [ "Retrying HL7 Message") || (text [ "MSA code '") || (text [ "MSA|") Quit "reached_receiver"
    If $MATCH(text, ..#CONNECTEXPIRED _ ..#ALERTSUFFIX) Quit "never_opened"
    If $MATCH(text, ..#FAILURETIMEOUT _ ..#CONNECTEXPIRED _ ..#ALERTSUFFIX) Quit "never_opened"
    Quit "unknown"
}

/// What a Completed header can honestly claim at this item: application, commit, connection or not_established. The
/// declared level stands only when getReply is 1 and the effective reply actions complete (C or W) on no code but AA and
/// CA, with one exception, the engine default's own :I?=W and :T?=C, which assume a reply naming another message or of
/// another type is still the receiver's answer. The exception depends on place: :T?=C holds only after the :* and the :~,
/// since the engine stops at the first such match and before them it completes refusals. R alone completes too once
/// FailureTimeout runs out, so it counts as completing on anything but AA, CA or ?A. A code the string leaves unmatched
/// completes as well, with no row in the event log, so the string must also stop every other reply, with its own :* and
/// :~. Anything else completes on something that is not an acceptance, or awaits nothing, so the answer is not_established,
/// with reason naming the pattern (as written) or what is missing, or ..#REASONGETREPLYOFF or ..#REASONUNREADABLE. Pass
/// reason on to DeliveredWords.
/// <p>replyCodeActions is the item's resolved string: empty means the engine's default, which only a stock class has, and
/// a caller that could not read it, or whose class overrides the reply handling, passes "unknown". level is the site's
/// declaration; an empty one, "none" or one not known here reads as connection, so it is never rounded up.</p>
ClassMethod EffectiveAck(level As %String = "", replyCodeActions As %String = "", getReply As %String = "", Output reason As %String) As %String
{
    Set reason = ""
    If getReply = "0" {
        Set reason = ..#REASONGETREPLYOFF
    } ElseIf getReply '= "1" {
        Set reason = ..#REASONUNREADABLE
    } Else {
        Set reason = ..NotAcceptance(replyCodeActions)
    }
    Quit:reason'="" "not_established"
    Quit $CASE(level, "application": "application", "commit": "commit", : "connection")
}

/// Why a reply actions string completes on something other than an acceptance: the offending patterns as written, or
/// ..#REASONUNREADABLE when a piece does not parse as an action the engine knows (it then falls back to a default of its
/// own), or what the string lacks to stop other replies, or "" when the string passes. Codes and actions are read without
/// regard to case and space, as the engine reads them; a pattern not listed here is refused by being unlisted, so ":?*",
/// ":_", "E=C" and "X=C" need no rule of their own.
/// <p>The engine returns no action for a reply that matches nothing, and the header then reads Completed. :* and :~ are both
/// asked for because the engine's two ways of matching differ: only its map lets :* take a reply with no MSA. Each must hold
/// S, D or F: R alone has no final action, and on the engine's unmapped path a retry that runs out completes.</p>
/// <p>That goes for every R alone, E=R and :?E=R among them. This function cannot see FailureTimeout, so a site at -1, where
/// a retry never runs out, also answers not_established; writing RF instead keeps its level words.</p>
ClassMethod NotAcceptance(replyCodeActions As %String) As %String [ Private ]
{
    Set actions = $ZSTRIP(replyCodeActions, "<>W")
    Quit:actions="unknown" ..#REASONUNREADABLE
    Set:actions="" actions = ..#STOCKREPLYACTIONS
    Set (found, unreadable) = ""
    Set (stopsOther, stopsNoMsa) = 0
    For i = 1:1:$LENGTH(actions, ",") {
        Set piece = $ZSTRIP($PIECE(actions, ",", i), "<>W")
        Continue:piece=""
        Set code = $ZCVT($ZSTRIP($PIECE(piece, "="), "<>W"), "U")
        Set action = $ZCVT($ZSTRIP($PIECE(piece, "=", 2), "<>W"), "U")
        If action'?1.(1"C",1"W",1"R",1"S",1"D",1"F") {
            Set unreadable = 1
            Continue
        }
        If code = ":I?" {
            Set bad = (action '= "W")
        } ElseIf code = ":T?" {
            Set bad = (action '= "C") || 'stopsOther || 'stopsNoMsa
        } Else {
            Set completes = (action [ "C") || (action [ "W") || ($TRANSLATE(action, "R") = "")
            Set bad = completes && '$CASE(code, ":AA": 1, ":CA": 1, ":?A": 1, : 0)
        }
        Set:bad found = found _ $SELECT(found="": "", 1: ", ") _ piece
        Set final = (action [ "S") || (action [ "D") || (action [ "F")
        Set:(code=":*")&&final stopsOther = 1
        Set:(code=":~")&&final stopsNoMsa = 1
    }
    Quit:found'="" found
    Quit:unreadable ..#REASONUNREADABLE
    Set missing = $SELECT(stopsOther: "", 1: ..#REASONNOCATCHALL)
    Quit:stopsNoMsa missing
    Quit missing _ $SELECT(missing="": "", 1: ", ") _ ..#REASONNONOMSA
}

/// The one sentence for a delivery the engine marked Completed: effectiveAck is EffectiveAck's answer and reason its
/// reason. completedAt is printed as HH:MM exactly as given, so a caller wanting another zone converts first, and is left
/// out when it holds no time. At not_established no level is named, and the sentence is not proof that a case is resolved.
/// An answer not known here is treated as not_established, so nothing is rounded up.
ClassMethod DeliveredWords(headerId As %String, completedAt As %String = "", effectiveAck As %String = "", reason As %String = "") As %String
{
    Set clock = ..Clock(completedAt)
    Set words = $CASE(effectiveAck
        , "application": "accepted by the receiver's application (its ACK), as declared in the site profile"
        , "commit": "accepted by the receiver's transport; processing not confirmed"
        , "connection": "accepted on the connection"
        , "none": "accepted on the connection"
        , "": "accepted on the connection"
        , : "")
    If words '= "" {
        Quit "Delivered by the engine" _ $SELECT(clock="": "", 1: " at " _ clock) _ " (header " _ headerId _ "); " _ words _ "; nothing was resent by Shutter."
    }
    Set where = " Header " _ headerId _ $SELECT(clock="": "", 1: " at " _ clock) _ "."
    Quit:reason=..#REASONGETREPLYOFF "IRIS marked the delivery Completed without waiting for an acknowledgement. Check receiver acceptance separately." _ where
    Set beside = $SELECT(reason="": "", reason=..#REASONUNREADABLE: " Reply actions unreadable.", 1: " This operation's reply actions complete on " _ reason _ ".")
    Quit "IRIS marked this delivery Completed. Receiver acceptance has not been established." _ beside _ where
}

/// The first HH:MM in a time as given, or "".
ClassMethod Clock(time As %String) As %String [ Private ]
{
    Set clock = ""
    Set found = $LOCATE(time, "(?<!\d)\d\d:\d\d", 1, , clock)
    Quit clock
}

}
