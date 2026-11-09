/// A receiver's own words in its negative acknowledgement (AE or AR), read by field: MSA-1 (the code), MSA-2 (the control
/// id), MSA-3 (the text), and each ERR's location (ERR-2, or ERR-1 in the older style), code and table (ERR-3) and
/// diagnostic and user message (ERR-7, ERR-8). The saved reply's body is read first, where the engine kept it; otherwise
/// the engine's own log row, where the reply follows about 300 characters of boilerplate with its carriage returns turned
/// into spaces (measured on 2026.2 and 2027.1.0AI).
///
/// The words are the receiver's: they are quoted, at most QUOTE characters, and never interpreted beyond naming which field
/// held them. A receiver's text can itself hold a name or a result, so the words are shown locally and never go to a model;
/// Codes() is the view with no free text in it. Nothing here reads the original message's OBX-5 or any name.
Class Shutter.Util.ReplyWords [ Abstract ]
{

/// The most characters quoted.
Parameter QUOTE = 300;

/// The words for one failed delivery: <var>logText</var> is the engine's full log row (type 2 or 6) for it, and
/// <var>replyId</var> the saved reply's body id, or "" to take it from the row's "because response N@EnsLib.HL7.Message".
/// Returns {"source", "msa1", "msa2", "msa3", "errors": [{"location", "code", "code_text", "table", "diagnostic",
/// "user_message"}], "kind", "quote"}: source is "reply" (the saved body), "log" (the flat text) or "none"; kind is
/// "words" (the receiver said something), "code_only" (a location and a code with no words, the older ERR style),
/// "no_words" (an MSA with nothing beside its code) or "unknown" (no MSA found: the text is quoted and nothing named).
ClassMethod Read(logText As %String, replyId As %String = "") As %DynamicObject
{
    Set:replyId="" replyId = ..ReplyId(logText)
    Set out = ""
    If replyId '= "" {
        Try {
            Set reply = ##class(EnsLib.HL7.Message).%OpenId(replyId)
            Set:$ISOBJECT(reply) out = ..FromReply(reply)
        } Catch {
            Set out = ""
        }
    }
    Set:'$ISOBJECT(out) out = ..FromLog(logText)
    Quit out
}

/// The saved reply's body id named in the log row, or "".
ClassMethod ReplyId(logText As %String) As %String
{
    Set m = ##class(%Regex.Matcher).%New("because response (\d+)@EnsLib\.HL7\.Message", logText)
    Quit $SELECT(m.Locate(): m.Group(1), 1: "")
}

/// The words, read by field from the reply's own segments.
ClassMethod FromReply(reply) As %DynamicObject
{
    Set out = ..Empty("reply")
    Set errors = out.errors
    For i = 1:1:reply.SegCount {
        Set seg = reply.GetSegmentAt(i)
        Continue:'$ISOBJECT(seg)
        If (seg.Name = "MSA") && (out.msa1 = "") {
            Set out.msa1 = seg.GetValueAt("1"), out.msa2 = seg.GetValueAt("2"), out.msa3 = seg.GetValueAt("3")
        } ElseIf seg.Name = "ERR" {
            Do errors.%Push(..Err(seg.GetValueAt("1"), seg.GetValueAt("2"), seg.GetValueAt("3"), seg.GetValueAt("7"), seg.GetValueAt("8"), "^"))
        }
    }
    Quit ..Finish(out, "")
}

/// The words from the log row's flat text: the last MSA, then each " ERR|" after it, the field separator "|" and the
/// component separator "^" as the measured replies used them.
ClassMethod FromLog(logText As %String) As %DynamicObject
{
    Set out = ..Empty("log")
    // The type 6 copy ends with the alert request's id, which is the engine's, not the receiver's.
    Set text = ##class(%Regex.Matcher).%New(" \(alert request ID=\d+\)$", logText).ReplaceAll("")
    Set at = ..LastFind(text, "MSA|")
    If at = 0 {
        Set out.source = $SELECT(text = "": "none", 1: "log")
        Quit ..Finish(out, text)
    }
    Set reply = $EXTRACT(text, at - 4, *)
    Set parts = ..Split(reply, " ERR|")
    Set msa = $LIST(parts, 1)
    Set out.msa1 = $PIECE(msa, "|", 2), out.msa2 = $PIECE(msa, "|", 3), out.msa3 = $ZSTRIP($PIECE(msa, "|", 4), "<>W")
    For i = 2:1:$LISTLENGTH(parts) {
        Set err = "ERR|" _ $LIST(parts, i)
        Do out.errors.%Push(..Err($PIECE(err, "|", 2), $PIECE(err, "|", 3), $PIECE(err, "|", 4), $ZSTRIP($PIECE(err, "|", 8), "<>W"), $ZSTRIP($PIECE(err, "|", 9), "<>W"), "^"))
    }
    Quit ..Finish(out, text)
}

/// The view with no free text: MSA-1, MSA-2 and each ERR's code and table, for facts that may leave IRIS.
ClassMethod Codes(words As %DynamicObject) As %DynamicObject
{
    Set codes = {"msa1": (words.msa1), "msa2": (words.msa2), "errors": []}
    Set iter = words.errors.%GetIterator()
    While iter.%GetNext(, .err) { Do codes.errors.%Push({"code": (err.code), "table": (err.table)}) }
    Quit codes
}

/// One ERR: the location from ERR-2, or from the older ERR-1 (segment^sequence^field^code), whose fourth component is
/// then the code; ERR-3's code, its text and its table; ERR-7 and ERR-8.
ClassMethod Err(err1 As %String, err2 As %String, err3 As %String, err7 As %String, err8 As %String, cs As %String) As %DynamicObject [ Private ]
{
    Set location = err2, code = $PIECE(err3, cs, 1), codeText = $PIECE(err3, cs, 2), table = $PIECE(err3, cs, 3)
    If (location = "") && (err1 '= "") {
        Set location = $PIECE(err1, cs, 1, 3)
        Set:code="" code = $PIECE(err1, cs, 4)
    }
    Quit {"location": (location), "code": (code), "code_text": (codeText), "table": (table), "diagnostic": (err7), "user_message": (err8)}
}

ClassMethod Empty(source As %String) As %DynamicObject [ Private ]
{
    Quit {"source": (source), "msa1": "", "msa2": "", "msa3": "", "errors": [], "kind": "", "quote": ""}
}

/// The kind and the quote: the receiver's words by field, at most QUOTE characters; with no MSA, the text's own tail.
ClassMethod Finish(out As %DynamicObject, text As %String) As %DynamicObject [ Private ]
{
    If out.msa1 = "" {
        Set out.kind = "unknown"
        // No MSA: the words are not known, so the end of the text, where a reply's words stand, is quoted as it is.
        Set out.quote = $SELECT($LENGTH(text) > ..#QUOTE: $EXTRACT(text, * - ..#QUOTE + 1, *), 1: text)
        Quit out
    }
    Set quote = $SELECT(out.msa3 '= "": "MSA-3: " _ out.msa3, 1: ""), words = (out.msa3 '= ""), codes = 0
    Set iter = out.errors.%GetIterator()
    While iter.%GetNext(, .err) {
        Set one = ""
        Set:err.diagnostic'="" one = one _ $SELECT(one = "": "", 1: "; ") _ "ERR-7: " _ err.diagnostic, words = 1
        Set:err."user_message"'="" one = one _ $SELECT(one = "": "", 1: "; ") _ "ERR-8: " _ err."user_message", words = 1
        Set:err.code'="" one = one _ $SELECT(one = "": "", 1: "; ") _ "code " _ err.code _ $SELECT(err."code_text" '= "": " (" _ err."code_text" _ ")", 1: ""), codes = 1
        Set:err.location'="" one = one _ $SELECT(one = "": "", 1: "; ") _ "at " _ err.location, codes = 1
        Set:one'="" quote = quote _ $SELECT(quote = "": "", 1: "; ") _ one
    }
    Set out.kind = $SELECT(words: "words", codes: "code_only", 1: "no_words")
    Set out.quote = $EXTRACT(quote, 1, ..#QUOTE)
    Quit out
}

/// The position just after the last <var>find</var> in <var>text</var>, or 0.
ClassMethod LastFind(text As %String, find As %String) As %Integer [ Private ]
{
    Set at = 0, from = 1
    For {
        Set next = $FIND(text, find, from)
        Quit:next=0
        Set at = next, from = next
    }
    Quit at
}

/// <var>text</var> split at each <var>sep</var>, as a $LIST.
ClassMethod Split(text As %String, sep As %String) As %List [ Private ]
{
    Set list = "", from = 1
    For {
        Set at = $FIND(text, sep, from)
        If at = 0 {
            Set list = list _ $LISTBUILD($EXTRACT(text, from, *))
            Quit
        }
        Set list = list _ $LISTBUILD($EXTRACT(text, from, at - $LENGTH(sep) - 1)), from = at
    }
    Quit list
}

}
