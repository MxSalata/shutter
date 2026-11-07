/// Shutter.Util.EngineWords, by table. The rows named as measured are the words a stock HL7 TCP operation wrote into its event
/// log with made-up listeners on the loopback address, on 2027.1 build 109 and 2026.2; the reply codes are the engine's own.
Class Shutter.Test.EngineWords Extends %UnitTest.TestCase
{

Parameter CONNECT = "ERROR <Ens>ErrOutConnectExpired: TCP Connect timeout period (5) expired for 127.0.0.1:7202";

Parameter TIMEDOUT = "ERROR <Ens>ErrFailureTimeout: FailureTimeout of 25 seconds exceeded in EnsLib.HL7.Operation.TCPOperation; status from last attempt was ";

Parameter LOSTREAD = "ERROR <Ens>ErrOutConnectionLost: Lost HL7 Read connection to 127.0.0.1:7202 - detected via ERROR #5002: ObjectScript error: <READ>ReadLine+11^%IO.DeviceStream.1";

Parameter READTIMEOUT = "ERROR <Ens>ErrTCPTerminatedReadTimeoutExpired: TCP Read timeout (30) expired waiting for terminator SegTerminator, on 127.0.0.1:7202";

/// Suspended on an AE, as the log wraps it.
Parameter AEROW = "ERROR <Ens>ErrSuspending: Suspending message 12 as requested by message handler with status: ERROR <Ens>ErrGeneral: Suspending HL7 Message body 9@EnsLib.HL7.Message / 12 because response 11@EnsLib.HL7.Message MSA code 'AE' matched ReplyCodeActions 1-6 : ':?R=RF,:?E=S,:~=S,:?A=C,:*=S,:I?=W', resulting in Action code S :  MSH|^~\&|LAB|LAB|X|X|202611070100||ACK|1|P|2.4 MSA|AE|T-1|Patient not found";

/// The first of an AR's two rows.
Parameter ARFIRST = "ERROR <Ens>ErrGeneral: Retrying HL7 Message body 9@EnsLib.HL7.Message / 12 because response 11@EnsLib.HL7.Message MSA code 'AR' matched ReplyCodeActions 1-6 : ':?R=RF,:?E=S,:~=S,:?A=C,:*=S,:I?=W', resulting in Action code RF :  MSH|^~\&|LAB|LAB|X|X|202611070100||ACK|1|P|2.4 MSA|AR|T-1|Patient not found ERR||PID^1^3|204^Unknown key identifier^HL70357|E";

/// The second of an AR's two rows.
Parameter ARSECOND = "Discarding message on ERROR <Ens>ErrFailureTimeout: FailureTimeout of 0 seconds exceeded in EnsLib.HL7.Operation.TCPOperation; status from last attempt was ERROR <Ens>ErrGeneral: Retrying HL7 Message body 9@EnsLib.HL7.Message / 12 because response 11@EnsLib.HL7.Message MSA code 'AR'";

/// The rows for one header, from the texts given, each naming that header.
ClassMethod Rows(texts... As %String) As %DynamicArray
{
    Set rows = []
    For i = 1:1:$GET(texts) {
        Do rows.%Push({"text": (texts(i)), "messageId": "353"})
    }
    Quit rows
}

Method TestAttemptsNeverOpened()
{
    Do $$$AssertEquals(##class(Shutter.Util.EngineWords).Attempts(..Rows(..#CONNECT)), "never_opened", "a connect expired alone")
    Do $$$AssertEquals(##class(Shutter.Util.EngineWords).Attempts(..Rows(..#CONNECT _ " (alert request ID=126)")), "never_opened", "with the type 6 suffix")
    Do $$$AssertEquals(##class(Shutter.Util.EngineWords).Attempts(..Rows(..#TIMEDOUT _ ..#CONNECT)), "never_opened", "FailureTimeout wrapping only that")
    Do $$$AssertEquals(##class(Shutter.Util.EngineWords).Attempts(..Rows(..#TIMEDOUT _ ..#CONNECT _ " (alert request ID=126)")), "never_opened", "and its type 6 copy")
    // Measured: nothing listening, FailureTimeout 0 and above 0, types 2 and 6.
    Do $$$AssertEquals(##class(Shutter.Util.EngineWords).Attempts(..Rows(..#CONNECT, ..#CONNECT _ " (alert request ID=7)", ..#TIMEDOUT _ ..#CONNECT, ..#TIMEDOUT _ ..#CONNECT _ " (alert request ID=8)")), "never_opened", "the whole measured shape")
}

/// The binding case: the receiver took the frame on the first attempt and the last attempt says never opened.
Method TestAttemptsReachedReceiver()
{
    Do $$$AssertEquals(##class(Shutter.Util.EngineWords).Attempts(..Rows(..#LOSTREAD, ..#CONNECT, ..#TIMEDOUT _ ..#CONNECT)), "reached_receiver", "taken, then the last attempt says never opened")
    Do $$$AssertEquals(##class(Shutter.Util.EngineWords).Attempts(..Rows(..#CONNECT, ..#LOSTREAD)), "reached_receiver", "a later lost read, whatever came first")
    Do $$$AssertEquals(##class(Shutter.Util.EngineWords).Attempts(..Rows(..#LOSTREAD)), "reached_receiver", "a lost read alone")
    Do $$$AssertEquals(##class(Shutter.Util.EngineWords).Attempts(..Rows(..#LOSTREAD, ..#TIMEDOUT _ ..#LOSTREAD)), "reached_receiver", "FailureTimeout wrapping a lost read")
    Do $$$AssertEquals(##class(Shutter.Util.EngineWords).Attempts(..Rows(..#READTIMEOUT)), "reached_receiver", "a read timeout")
    Do $$$AssertEquals(##class(Shutter.Util.EngineWords).Attempts(..Rows(..#AEROW)), "reached_receiver", "an AE")
    Do $$$AssertEquals(##class(Shutter.Util.EngineWords).Attempts(..Rows(..#ARFIRST, ..#ARSECOND)), "reached_receiver", "an AR's pair")
    Do $$$AssertEquals(##class(Shutter.Util.EngineWords).Attempts(..Rows(..#ARSECOND)), "reached_receiver", "the second of the pair alone")
    Do $$$AssertEquals(##class(Shutter.Util.EngineWords).Attempts(..Rows("Something new MSA|AA|T-1")), "reached_receiver", "any reply segment")
    Do $$$AssertEquals(##class(Shutter.Util.EngineWords).Attempts(..Rows("Words not held", ..#LOSTREAD)), "reached_receiver", "it outranks words not held")
}

/// Anchored: a word the table knows, inside other words, is not the row the table knows.
Method TestAttemptsUnknown()
{
    Do $$$AssertEquals(##class(Shutter.Util.EngineWords).Attempts(..Rows("ERROR <Ens>ErrPreviouslyCrashedMessage: Message 12 was being processed when the job crashed")), "unknown", "crashed")
    Do $$$AssertEquals(##class(Shutter.Util.EngineWords).Attempts(..Rows("Not Alerting during retry grace period (60) for " _ ..#CONNECT)), "unknown", "the grace period's prefix")
    Do $$$AssertEquals(##class(Shutter.Util.EngineWords).Attempts(..Rows("Alerting at expiration of retry grace period (60) for " _ ..#CONNECT)), "unknown", "and the other one")
    Do $$$AssertEquals(##class(Shutter.Util.EngineWords).Attempts(..Rows("ERROR <Ens>ErrOutConnectException: TCP Connect failed for 127.0.0.1:7202")), "unknown", "connect exception, which the rule leaves out")
    Do $$$AssertEquals(##class(Shutter.Util.EngineWords).Attempts(..Rows("ERROR <Ens>ErrOutConnectionLost: Lost HL7 Write connection to 127.0.0.1:7202")), "unknown", "a lost write")
    Do $$$AssertEquals(##class(Shutter.Util.EngineWords).Attempts(..Rows(..#TIMEDOUT _ "ERROR <Ens>ErrOutConnectionLost: Lost HL7 Write connection to 127.0.0.1:7202")), "unknown", "FailureTimeout wrapping a lost write")
    Do $$$AssertEquals(##class(Shutter.Util.EngineWords).Attempts(..Rows(..#CONNECT _ " and then something else")), "unknown", "known words with more after them")
    Do $$$AssertEquals(##class(Shutter.Util.EngineWords).Attempts(..Rows("Note: " _ ..#CONNECT)), "unknown", "known words with something before them")
    Do $$$AssertEquals(##class(Shutter.Util.EngineWords).Attempts(..Rows("Discarding message on " _ ..#TIMEDOUT _ ..#CONNECT)), "unknown", "a prefix never seen on these words")
    Do $$$AssertEquals(##class(Shutter.Util.EngineWords).Attempts(..Rows(..#CONNECT, "Words not held")), "unknown", "one row not held spoils the rest")
    Do $$$AssertEquals(##class(Shutter.Util.EngineWords).Attempts(..Rows("")), "unknown", "a row with no words")
    Do $$$AssertEquals(##class(Shutter.Util.EngineWords).Attempts("unknown"), "unknown", "a reader's answer that it could not read")
    Do $$$AssertEquals(##class(Shutter.Util.EngineWords).Attempts(""), "unknown", "nothing passed is not an empty log")
    Do $$$AssertEquals(##class(Shutter.Util.EngineWords).Attempts({"text": (..#CONNECT), "messageId": "353"}), "unknown", "an object, not a list")
    Do $$$AssertEquals(##class(Shutter.Util.EngineWords).Attempts(["not an object"]), "unknown", "a row that is not an object")
}

/// A session row naming no header, whose text names the item, could be any message's.
Method TestAttemptsRowWithNoMessageId()
{
    Set rows = [{"text": "ERROR <Ens>ErrGeneral: LIMS Out could not start", "messageId": ""}]
    Do $$$AssertEquals(##class(Shutter.Util.EngineWords).Attempts(rows), "unknown", "alone")
    Set rows = ..Rows(..#CONNECT)
    Do rows.%Push({"text": (..#CONNECT), "messageId": ""})
    Do $$$AssertEquals(##class(Shutter.Util.EngineWords).Attempts(rows), "unknown", "beside rows that would pass, even with the same words")
    Set rows = ..Rows(..#CONNECT)
    Do rows.%Push({"text": (..#CONNECT)})
    Do $$$AssertEquals(##class(Shutter.Util.EngineWords).Attempts(rows), "unknown", "and a row with no such member at all")
}

Method TestAttemptsNoRows()
{
    Do $$$AssertEquals(##class(Shutter.Util.EngineWords).Attempts([]), "no_rows", "an empty list")
}

/// Asks one row: the answer, and the reason as a whole or a part of it.
Method Ack(level As %String, actions As %String, getReply As %String, answer As %String, reasonHolds As %String = "", label As %String)
{
    Set got = ##class(Shutter.Util.EngineWords).EffectiveAck(level, actions, getReply, .reason)
    Do $$$AssertEquals(got, answer, label _ ": " _ answer)
    If reasonHolds = "" {
        Do $$$AssertEquals(reason, "", label _ ": no reason")
    } Else {
        Do $$$AssertTrue(reason [ reasonHolds, label _ ": the reason '" _ reason _ "' names " _ reasonHolds)
    }
}

Method TestEffectiveAckStands()
{
    Set default = ":?R=RF,:?E=S,:~=S,:?A=C,:*=S,:I?=W,:T?=C"
    Do ..Ack("application", default, 1, "application", "", "application at the default string")
    Do ..Ack("application", "", 1, "application", "", "an empty string on a stock class")
    Do ..Ack("application", "   ", 1, "application", "", "a blank string")
    Do ..Ack("commit", default, 1, "commit", "", "commit at the default")
    Do ..Ack("connection", default, 1, "connection", "", "connection at the default")
    Do ..Ack("", default, 1, "connection", "", "an empty level")
    Do ..Ack("none", default, 1, "connection", "", "none")
    Do ..Ack("verified", default, 1, "connection", "", "a level not known here is not rounded up")
    Do ..Ack("application", ":?R=RF,:?E=S,:~=S,:?A=C,:*=S,:I?=W", 1, "application", "", "the string the log shows, without :T?")
    Do ..Ack("application", ":AA=C,:CA=S,:AE=S,:CE=S,:AR=RF,:CR=RF,:~=S,:*=S", 1, "application", "", "a site that completes on AA alone")
    Do ..Ack("application", ":AA=W,:CA=C", 1, "application", "", "a warning on AA")
    Do ..Ack("application", ":?a=c, :?e=s", 1, "application", "", "case and space, as the engine reads them")
    Do ..Ack("application", ":?A=C,", 1, "application", "", "a trailing comma")
    Do ..Ack("application", ":?A=C,:?E=RF,:?R=RD,E=F", 1, "application", "", "retries and failures complete on nothing")
}

Method TestEffectiveAckFailsOnAPattern()
{
    Set stock = ":?R=RF,:?E=S,:~=S,:?A=C,:*=S,:I?=W,:T?=C"
    Do ..Ack("application", ":?E=C,:?R=RF", 1, "not_established", ":?E=C", "application with ?E")
    Do ..Ack("application", ":?R=C", 1, "not_established", ":?R=C", "with ?R")
    Do ..Ack("application", ":?E=W", 1, "not_established", ":?E=W", "a warning on ?E")
    Do ..Ack("application", ":*=C", 1, "not_established", ":*=C", "a wildcard")
    Do ..Ack("application", ":~=C", 1, "not_established", ":~=C", "no MSA")
    Do ..Ack("application", stock _ ",:I?=C", 1, "not_established", ":I?=C", "I? with C added")
    Do ..Ack("application", ":?A=C,:I?=S", 1, "not_established", ":I?=S", "I? with any other action, a stricter one too")
    Do ..Ack("application", ":?A=C,:T?=W", 1, "not_established", ":T?=W", "T? with any other action")
    Do ..Ack("connection", ":?E=C", 1, "not_established", ":?E=C", "connection falls too")
    Do ..Ack("", ":?E=C", 1, "not_established", ":?E=C", "and an empty level")
    Do ..Ack("application", ":AE=C", 1, "not_established", ":AE=C", "a literal E code")
    Do ..Ack("application", ":CR=W", 1, "not_established", ":CR=W", "a literal R code")
    Do ..Ack("application", ":?e=c", 1, "not_established", ":?e=c", "as the engine reads it, in lower case")
    Do ..Ack("application", ":?E=SW", 1, "not_established", ":?E=SW", "W in a combination")
    Do ..Ack("application", ":_=C", 1, "not_established", ":_=C", "an empty MSA-1")
    Do ..Ack("application", ":ZZ=C", 1, "not_established", ":ZZ=C", "an unknown code")
    Do ..Ack("application", "E=C", 1, "not_established", "E=C", "an error status")
    Do ..Ack("application", "X=C", 1, "not_established", "X=C", "no reply at all")
    Do ..Ack("application", ":?E=C,:*=W", 1, "not_established", ":?E=C, :*=W", "every pattern is named")
}

Method TestEffectiveAckCannotRead()
{
    Do ..Ack("application", ":?A=C,:?R=RF", 0, "not_established", "GetReply off", "GetReply off")
    Do ..Ack("connection", "", 0, "not_established", "GetReply off", "GetReply off at connection too")
    Do ..Ack("application", "unknown", 0, "not_established", "GetReply off", "GetReply off is known even when the string is not")
    Do ..Ack("application", "unknown", 1, "not_established", "unreadable", "the string unknown")
    Do ..Ack("application", "default", 1, "not_established", "unreadable", "a word that is no string of actions")
    Do ..Ack("application", ":?A", 1, "not_established", "unreadable", "a piece with no action")
    Do ..Ack("application", ":?E=Z", 1, "not_established", "unreadable", "an action the engine replaces with its own default")
    Do ..Ack("application", ":?A=", 1, "not_established", "unreadable", "an empty action")
    Do ..Ack("application", ":?E=C,:?A", 1, "not_established", ":?E=C", "a pattern is named before the rest")
    Do ..Ack("application", "", "unknown", "not_established", "unreadable", "GetReply unread is not GetReply off")
    Do ..Ack("application", "", "", "not_established", "unreadable", "GetReply empty")
}

Method TestDeliveredWordsAtALevel()
{
    Set at = "2026-11-07 03:12:01.123"
    Do $$$AssertEquals(##class(Shutter.Util.EngineWords).DeliveredWords(17, at, "application"), "Delivered by the engine at 03:12 (header 17); accepted by the receiver's application (its ACK), as declared in the site profile; nothing was resent by Shutter.", "application")
    Do $$$AssertEquals(##class(Shutter.Util.EngineWords).DeliveredWords(17, at, "commit"), "Delivered by the engine at 03:12 (header 17); accepted by the receiver's transport; processing not confirmed; nothing was resent by Shutter.", "commit")
    Do $$$AssertEquals(##class(Shutter.Util.EngineWords).DeliveredWords(17, at, "connection"), "Delivered by the engine at 03:12 (header 17); accepted on the connection; nothing was resent by Shutter.", "connection")
    Do $$$AssertEquals(##class(Shutter.Util.EngineWords).DeliveredWords(17, at, "none"), "Delivered by the engine at 03:12 (header 17); accepted on the connection; nothing was resent by Shutter.", "none")
    Do $$$AssertEquals(##class(Shutter.Util.EngineWords).DeliveredWords(17, at, ""), "Delivered by the engine at 03:12 (header 17); accepted on the connection; nothing was resent by Shutter.", "an empty level")
    Do $$$AssertEquals(##class(Shutter.Util.EngineWords).DeliveredWords(17, "2026-11-07T03:12:01Z", "connection"), "Delivered by the engine at 03:12 (header 17); accepted on the connection; nothing was resent by Shutter.", "an ISO time")
    Do $$$AssertEquals(##class(Shutter.Util.EngineWords).DeliveredWords(17, "", "connection"), "Delivered by the engine (header 17); accepted on the connection; nothing was resent by Shutter.", "no time")
    Do $$$AssertEquals(##class(Shutter.Util.EngineWords).DeliveredWords(17, "not a time", "connection"), "Delivered by the engine (header 17); accepted on the connection; nothing was resent by Shutter.", "a time that does not read")
}

Method TestDeliveredWordsNotEstablished()
{
    Set at = "2026-11-07 03:12:01"
    Do $$$AssertEquals(##class(Shutter.Util.EngineWords).DeliveredWords(17, at, "not_established", ":?E=C"), "IRIS marked this delivery Completed. Receiver acceptance has not been established. This operation's reply actions complete on :?E=C. Header 17 at 03:12.", "its pattern")
    Do $$$AssertEquals(##class(Shutter.Util.EngineWords).DeliveredWords(17, at, "not_established", "reply actions unreadable"), "IRIS marked this delivery Completed. Receiver acceptance has not been established. Reply actions unreadable. Header 17 at 03:12.", "unreadable")
    Do $$$AssertEquals(##class(Shutter.Util.EngineWords).DeliveredWords(17, at, "not_established", "GetReply off"), "IRIS marked the delivery Completed without waiting for an acknowledgement. Check receiver acceptance separately. Header 17 at 03:12.", "GetReply off")
    Do $$$AssertEquals(##class(Shutter.Util.EngineWords).DeliveredWords(17, "", "not_established"), "IRIS marked this delivery Completed. Receiver acceptance has not been established. Header 17.", "no reason, no time")
    Do $$$AssertEquals(##class(Shutter.Util.EngineWords).DeliveredWords(17, at, "application, probably"), "IRIS marked this delivery Completed. Receiver acceptance has not been established. Header 17 at 03:12.", "an answer not known here is not rounded up")
}

/// From a real answer through to the sentence, and the words no row may hold.
Method TestWordsNeverClaimMore()
{
    For level = "application", "commit", "connection", "" {
        For actions = ":?R=RF,:?E=S,:~=S,:?A=C,:*=S,:I?=W,:T?=C", ":?E=C", ":*=C", ":I?=C", "unknown" {
            For getReply = 1, 0, "unknown" {
                Set answer = ##class(Shutter.Util.EngineWords).EffectiveAck(level, actions, getReply, .reason)
                Set words = ##class(Shutter.Util.EngineWords).DeliveredWords(17, "03:12", answer, reason)
                Set label = level _ " / " _ actions _ " / " _ getReply
                Do $$$AssertTrue(words '[ "Verified", label _ ": never Verified")
                If answer = "not_established" {
                    Do $$$AssertTrue(words '[ "accepted", label _ ": no acceptance claimed: " _ words)
                    For name = "application", "transport", "connection" {
                        Do $$$AssertTrue(words '[ name, label _ ": no level named")
                    }
                } Else {
                    Do $$$AssertTrue(words [ "accepted", label _ ": a level")
                }
            }
        }
    }
}

}
