/// The findings on an order or result case, for the person who handles it: what the engine did with the message (the
/// custody), the receiver's own words by field, where the message holds characters above ASCII and what went on the
/// wire, and which OBX the receiver's words name. Read in the source namespace from the delivery header, never from a
/// router's input. The evidence adds them as the snapshot's "findings" item; the model view's allowlists leave them out,
/// so they never reach a model, and the escalation draft takes only the parts with no free text in them.
///
/// Only a message whose type starts with "O" (ORM, ORU, OML, OUL and the rest of the order and result family) gets
/// findings: an ADT, SIU or MDM case's evidence is unchanged.
Class Shutter.Util.CaseFindings [ Abstract ]
{

/// Whether the case's message is an order or a result, by MSH-9.1 as the evidence read it.
ClassMethod Applies(msgInfo As %DynamicObject) As %Boolean
{
    Quit:'$ISOBJECT(msgInfo) 0
    Set type = $ZCONVERT($PIECE(##class(Shutter.Util.Json).Str(msgInfo, "message_type"), "^", 1), "U")
    Quit ($EXTRACT(type) = "O") && ($LENGTH(type) = 3)
}

/// The findings for the case: {"namespace", "item", "header_id", "custody": {"attempts", "state", "words"},
/// "reply", "character", "obx", "why"}. why names what could not be read; what was read is kept.
ClassMethod Build(case As Shutter.Store.Case) As %DynamicObject
{
    Set ns = $SELECT(case.SourceNamespace '= "": case.SourceNamespace, 1: $NAMESPACE)
    Set out = {"namespace": (ns), "item": "", "header_id": "", "custody": {}, "reply": {}, "character": {}, "obx": {}, "why": ""}
    Try {
        Set item = ##class(Shutter.Util.EngineScope).ItemOf(ns, case)
        If (item = "") || (item = "unreadable") {
            Set out.why = "the operation the message went to could not be read"
            Quit
        }
        Set out.item = item
        Set origin = $SELECT(case.OriginHeaderId '= "": case.OriginHeaderId, 1: case.SourceHeaderId)
        Set dh = ##class(Shutter.Util.EngineRead).DeliveryHeader(ns, origin, item)
        If dh.answer '= "found" {
            Set out.why = "the delivery header could not be read: " _ dh.why
            Quit
        }
        Set hid = dh.headerId, out."header_id" = hid
        // The custody: what the log's rows show of the attempts, and whether the engine holds the message now.
        Set rows = ##class(Shutter.Util.EngineRead).LogRows(ns, hid)
        Set attempts = $SELECT(rows.answer = "ok": ##class(Shutter.Util.EngineWords).Attempts(rows.rows), 1: "unknown")
        Set custody = ##class(Shutter.Util.EngineRead).Custody(ns, item, hid)
        Set out.custody = {"attempts": (attempts), "state": (custody.answer), "words": (..CustodyWords(attempts, custody.answer))}
        // The receiver's words: the saved reply, else the newest row's flat text.
        Set text = ""
        If rows.answer = "ok" {
            Set iter = rows.rows.%GetIterator()
            While iter.%GetNext(, .row) { Set:row.text["MSA|" text = row.text }
        }
        Set out.reply = ##class(Shutter.Util.ReplyWords).Read(text)
        Set out.character = ##class(Shutter.Util.CharacterFinding).Find(ns, item, hid)
        Set out.obx = ##class(Shutter.Util.ObxFinding).Find(..Body(ns, hid), ..WordsToMatch(out.reply))
    } Catch err {
        Set out.why = "the findings stopped: " _ err.DisplayString()
    }
    Quit out
}

/// The custody in words. The engine holding the message outranks the log: it is still trying.
ClassMethod CustodyWords(attempts As %String, state As %String) As %String
{
    Quit:state="engine" "The engine holds it; it is still trying this message: do not resend it and do not re-enter it by hand."
    Quit:state="delivered" "The engine has marked this message Completed: the receiver took it."
    Quit:attempts="reached_receiver" "The receiver took this message on at least one attempt (its answer, or a connection lost on the read, shows the frame reached it): do not resend it and do not re-enter it by hand before checking the receiver."
    Quit:attempts="never_opened" "Every attempt the engine's log keeps found no listener: those attempts never reached the receiver. The log may not keep every attempt."
    Quit "The engine's log does not show whether the receiver took this message."
}

/// The text the OBX finding matches codes in: MSA-3, each ERR's diagnostic and user message, or the unknown words.
ClassMethod WordsToMatch(reply As %DynamicObject) As %String
{
    Quit:'$ISOBJECT(reply) ""
    Quit:reply.kind="unknown" reply.quote
    Set text = reply.msa3
    Set iter = reply.errors.%GetIterator()
    While iter.%GetNext(, .e) { Set text = text _ " " _ e.diagnostic _ " " _ e."user_message" }
    Quit text
}

/// The lines for the escalation draft, with no free text: the custody, the OBX the receiver's words name, where the
/// characters above ASCII stand and what went out, and the reply's codes. The receiver's own words can hold a name or a
/// result, so they stay on the case page and are not put in an email.
ClassMethod DraftLines(findings As %DynamicObject) As %String
{
    Quit:'$ISOBJECT(findings) ""
    Set nl = $CHAR(13, 10), b = ""
    Set words = ##class(Shutter.Util.Json).Str(findings.custody, "words")
    Set:words'="" b = b _ "  " _ words _ nl
    Set codes = ##class(Shutter.Util.ReplyWords).Codes(findings.reply)
    If codes.msa1 '= "" {
        Set line = "  The receiver answered " _ codes.msa1
        Set iter = codes.errors.%GetIterator()
        While iter.%GetNext(, .e) { Set:e.code'="" line = line _ ", error code " _ e.code _ $SELECT(e.table '= "": " (" _ e.table _ ")", 1: "") }
        Set b = b _ line _ "; its words are on the case page." _ nl
    }
    Set kind = $SELECT($ISOBJECT(findings.obx): findings.obx.kind, 1: "")
    If (kind = "obx") || (kind = "no_match") || (kind = "schema") {
        Set b = b _ "  " _ ..ObxLine(findings.obx) _ nl
    }
    If $ISOBJECT(findings.character) && (findings.character.kind = "characters") {
        // One line per field and character, with each place it stands (1.4.1: a line per place repeated the field).
        Set iter = ##class(Shutter.Util.CharacterFinding).Groups(findings.character).%GetIterator()
        While iter.%GetNext(, .g) { Set b = b _ "  " _ ##class(Shutter.Util.CharacterFinding).GroupLine(g, 0) _ nl }
    }
    Quit b
}

/// The OBX finding's sentence without the schema's own words, which quote the message's structure only.
ClassMethod ObxLine(obx As %DynamicObject) As %String [ Private ]
{
    Quit:obx.kind="schema" "The message does not fit its structure, so the receiver may not have read it as sent."
    Quit obx.sentence
}

/// The stored body of a header in ns, copied here (Shutter.Util.MessageCopy), or "".
ClassMethod Body(ns As %String, headerId As %String) [ Private ]
{
    Quit ##class(Shutter.Util.MessageCopy).Of(ns, headerId)
}

}
