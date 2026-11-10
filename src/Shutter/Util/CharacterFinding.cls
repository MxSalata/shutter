/// Where a message a receiver refused holds characters above ASCII, and what the engine sends for them: per field, the
/// segment, field, component and position, the code points as stored, the character in words, the stored MSH-18, the
/// operation's DefCharEncoding and the bytes it puts on the wire. A "?" in an identity field is raised as a question.
/// The count compares the field with the receiver's recent failures and recent deliveries, and the shared count says how
/// many of those failures hold the same character in any field.
///
/// A local diagnostic, never a model's input: it names where a character stands and which it is, never the value around
/// it. It repairs nothing, transliterates nothing and offers no Charset; a message resent unchanged fails the same way.
///
/// The wire bytes come from the engine's rule as read in EnsLib.HL7.Util.IOFraming and measured on 2026.2 and 2027.1.0AI:
/// an operation setting with "!" wins; otherwise the stored MSH-18; otherwise the setting (the stock default latin1). Only
/// the four settings measured (latin1, UTF-8, !UTF-8, !latin1) and the MSH-18 values measured (empty, UTF-8 and
/// UNICODE UTF-8, 8859/1) get bytes; anything else is "not known for this setting".
Class Shutter.Util.CharacterFinding [ Abstract ]
{

/// The identity fields where a "?" is raised as a question.
Parameter IDENTITY = "PID-2,PID-3,PID-4,PID-5,PID-6,PID-9,PID-19,MRG-1,MRG-7";

/// The most delivered messages compared.
Parameter DELIVERED = 300;

/// The days of failures compared.
Parameter DAYS = 7;

/// The finding for the delivery header <var>headerId</var> to <var>item</var> in the source namespace <var>ns</var>:
/// the stored body read there, the setting through EngineRead.ItemSetting, and the count. See Of for the shape.
ClassMethod Find(ns As %String, item As %String, headerId As %String) As %DynamicObject
{
    Set setting = {"source": "unknown", "value": "", "why": "not read"}
    Try {
        Set isStock = ##class(Shutter.Util.EngineScope).IsStockTcp(ns, item)
        Set setting = ##class(Shutter.Util.EngineRead).ItemSetting(ns, item, "DefCharEncoding", isStock)
    } Catch err {
        Set setting.why = err.DisplayString()
    }
    Set msg = ..Body(ns, headerId)
    Set out = ..Of(msg, $SELECT(setting.source = "unknown": "", 1: setting.value), setting.why)
    Set out.count = ..Count(ns, item, headerId, out)
    Set out.shared = ..Shared(ns, item, out)
    Set out.sentence = ..Sentence(out)
    Quit out
}

/// The finding for <var>msg</var>, with the operation's DefCharEncoding <var>setting</var> ("" when it could not be read,
/// with <var>why</var>): {"fields": [{"segment", "segment_index", "field", "repetition", "component", "position",
/// "codes", "character", "wire"}], "questions": [{"segment", "segment_index", "field", "position", "words"}], "msh18",
/// "setting", "encoding", "kind", "count", "sentence"}. kind is "characters", "question" (only a "?" in an identity
/// field), "none" or "unreadable".
ClassMethod Of(msg, setting As %String, why As %String = "") As %DynamicObject
{
    Set out = {"fields": [], "questions": [], "msh18": "", "setting": (setting), "encoding": "", "kind": "unreadable", "count": {}, "sentence": ""}
    If ('$ISOBJECT(msg)) || ('msg.%IsA("EnsLib.HL7.Message")) Set out.sentence = "The stored message could not be read." Quit out
    Set out.msh18 = msg.GetValueAt("MSH:18")
    Set out.encoding = $SELECT(setting = "": "unknown: " _ $SELECT(why '= "": why, 1: "DefCharEncoding not read"), 1: ..Encoding(setting, out.msh18))
    Set cs = $EXTRACT(msg.Separators, 2), rs = $EXTRACT(msg.Separators, 3)
    Set:cs="" cs = "^"
    Set:rs="" rs = "~"
    For i = 1:1:msg.SegCount {
        Set seg = msg.GetSegmentAt(i)
        Continue:'$ISOBJECT(seg)
        Set name = seg.Name
        // MSH-1 and MSH-2 are the separators themselves.
        For number = $SELECT(name = "MSH": 3, 1: 1):1:seg.Count {
            Set field = seg.GetValueAt(number)
            Continue:field=""
            For r = 1:1:$LENGTH(field, rs) {
                Set rep = $PIECE(field, rs, r)
                For c = 1:1:$LENGTH(rep, cs) {
                    Set comp = $PIECE(rep, cs, c)
                    Do ..Scan(out, name, i, number, r, c, comp)
                }
            }
        }
    }
    Set out.kind = $SELECT(out.fields.%Size(): "characters", out.questions.%Size(): "question", 1: "none")
    Set out.sentence = ..Sentence(out)
    Quit out
}

/// The runs of characters above ASCII in one component, and a "?" in an identity field.
ClassMethod Scan(out As %DynamicObject, name As %String, index As %Integer, number As %Integer, rep As %Integer, comp As %Integer, text As %String) [ Private ]
{
    Set run = "", start = 0
    For p = 1:1:$LENGTH(text) + 1 {
        Set ch = $EXTRACT(text, p)
        If (ch '= "") && ($ASCII(ch) > 127) {
            Set:run="" start = p
            Set run = run _ ch
            Continue
        }
        If run '= "" {
            Set codes = []
            For k = 1:1:$LENGTH(run) { Do codes.%Push($ASCII(run, k)) }
            Set one = {"segment": (name), "segment_index": (index), "field": (name _ "-" _ number), "repetition": (rep), "component": (comp), "position": (start), "codes": (codes), "character": (..Words(run)), "wire": (..Wire(run, out.setting, out.msh18))}
            Do out.fields.%Push(one)
            Set run = ""
        }
        If (ch = "?") && ((","_..#IDENTITY_",") [ (","_name_"-"_number_",")) {
            Do out.questions.%Push({"segment": (name), "segment_index": (index), "field": (name _ "-" _ number), "position": (p), "words": (name _ "-" _ number _ " holds a '?' at position " _ p _ ": it may be a lost character. A Latin-1 byte read as UTF-8 becomes '?' and takes the next byte with it, and the original bytes are not in the stored message.")})
        }
    }
}

/// The encoding the engine writes with: an operation setting with "!" wins, then the stored MSH-18, then the setting.
/// "latin1" or "utf8", or "" when the setting or MSH-18 is not one that was measured.
ClassMethod Encoding(setting As %String, msh18 As %String) As %String
{
    Set s = $ZCONVERT($ZSTRIP(setting, "<>W"), "U")
    Set:s="" s = "LATIN1"
    Set forced = ($EXTRACT(s) = "!"), s = $SELECT(forced: $EXTRACT(s, 2, *), 1: s)
    Set s = ..Measured(s)
    Quit:s="" ""
    Quit:forced s
    Set m = $ZCONVERT($ZSTRIP(msh18, "<>W"), "U")
    Quit:m="" s
    Quit ..Measured18(m)
}

/// An operation setting U4 measured, as latin1 or utf8; "" for any other.
ClassMethod Measured(s As %String) As %String [ Private ]
{
    Quit:(s="LATIN1") "latin1"
    Quit:(s="UTF-8") "utf8"
    Quit ""
}

/// An MSH-18 U4 measured, as latin1 or utf8; "" for any other.
ClassMethod Measured18(m As %String) As %String [ Private ]
{
    Quit:(m="UTF-8")||(m="UNICODE UTF-8") "utf8"
    Quit:(m="8859/1") "latin1"
    Quit ""
}

/// The bytes the engine sends for the stored characters <var>run</var>, as hex pairs ("C3 A8"), or "not known for this
/// setting".
ClassMethod Wire(run As %String, setting As %String, msh18 As %String) As %String
{
    Quit:setting="" "not known: the operation's DefCharEncoding could not be read"
    Set enc = ..Encoding(setting, msh18)
    Quit:enc="" "not known for this setting"
    If enc = "latin1" {
        Quit:..Over255(run) "not known for this setting"
        Set bytes = run
    } Else {
        Set bytes = $ZCONVERT(run, "O", "UTF8")
    }
    Set hex = ""
    For k = 1:1:$LENGTH(bytes) { Set hex = hex _ $SELECT(k = 1: "", 1: " ") _ $ZHEX($ASCII(bytes, k)) }
    Quit hex
}

/// The stored characters in words: one character named by its code point; two or more that are the UTF-8 bytes of one
/// character, said so.
ClassMethod Words(run As %String) As %String
{
    If $LENGTH(run) = 1 Quit ..Name($ASCII(run))
    Set codes = ""
    For k = 1:1:$LENGTH(run) { Set codes = codes _ $SELECT(k = 1: "", 1: " ") _ $ASCII(run, k) }
    Set decoded = ""
    Try {
        Set:'..Over255(run) decoded = $ZCONVERT(run, "I", "UTF8")
    } Catch {
        Set decoded = ""
    }
    If ($LENGTH(decoded) = 1) && ($ASCII(decoded) > 127) Quit "stored as " _ $LENGTH(run) _ " characters (" _ codes _ "), the UTF-8 bytes of " _ ..Name($ASCII(decoded))
    Quit $LENGTH(run) _ " characters above ASCII (" _ codes _ ")"
}

/// Whether any character of <var>run</var> is above 255.
ClassMethod Over255(run As %String) As %Boolean [ Private ]
{
    For k = 1:1:$LENGTH(run) { Return:$ASCII(run, k)>255 1 }
    Quit 0
}

/// A character in words with its code point: "e with a grave accent, U+00E8".
ClassMethod Name(code As %Integer) As %String
{
    Set hex = $ZHEX(code), hex = $TRANSLATE($JUSTIFY(hex, 4), " ", "0")
    Set name = ""
    If (code >= 192) && (code <= 255) && (code '= 215) && (code '= 247) {
        // The Latin-1 letters: the base letter and its mark.
        Set base = $EXTRACT("AAAAAAACEEEEIIIIDNOOOOO OUUUUYTsaaaaaaaceeeeiiiidnooooo ouuuuyty", code - 191)
        Set mark = $CASE(code # 32, 0: "grave", 1: "acute", 2: "circumflex", 3: "tilde", 4: "diaeresis", 5: "ring", 7: "cedilla", 8: "grave", 9: "acute", 10: "circumflex", 11: "diaeresis", 12: "grave", 13: "acute", 14: "circumflex", 15: "diaeresis", 17: "tilde", 18: "grave", 19: "acute", 20: "circumflex", 21: "tilde", 22: "diaeresis", 24: "stroke", 25: "grave", 26: "acute", 27: "circumflex", 28: "diaeresis", 29: "acute", 31: $SELECT(code = 255: "diaeresis", 1: ""), : "")
        Set slot = code # 32, upper = (code < 224)
        If slot = 6 Set name = $SELECT(upper: "AE", 1: "ae")
        If slot = 16 Set name = $SELECT(upper: "Eth", 1: "eth")
        If slot = 30 Set name = $SELECT(upper: "Thorn", 1: "thorn")
        If code = 223 Set name = "sharp s"
        If (name = "") && (mark '= "") Set name = base _ " with " _ $SELECT(mark = "stroke": "a stroke", mark = "ring": "a ring above", 1: "a" _ $SELECT(mark = "acute": "n", 1: "") _ " " _ mark _ $SELECT((mark = "diaeresis") || (mark = "cedilla") || (mark = "tilde"): "", 1: " accent"))
    }
    Quit $SELECT(name '= "": name _ ", U+" _ hex, 1: "U+" _ hex)
}

/// The count for the fields the finding names: how many of the receiver's failures in the last DAYS days, and of its last
/// DELIVERED delivered messages, carry a character above ASCII in each field. {"<field>": {"failures", "of_failures",
/// "delivered", "of_delivered"}}, with "delivered" "" and a "why" when what got through could not be compared.
ClassMethod Count(ns As %String, item As %String, headerId As %String, out As %DynamicObject) As %DynamicObject
{
    Set count = {}, names = ""
    Set iter = out.fields.%GetIterator()
    While iter.%GetNext(, .f) { Set:'$LISTFIND(names, f.field) names = names _ $LISTBUILD(f.field) }
    Quit:names="" count
    Set failures = ..Headers(ns, item, "failed", .whyF), delivered = ..Headers(ns, item, "delivered", .whyD)
    For i = 1:1:$LISTLENGTH(names) {
        Set field = $LIST(names, i)
        Set one = {"failures": (..Holding(ns, failures, field)), "of_failures": ($LISTLENGTH(failures)), "delivered": "", "of_delivered": ""}
        If whyF '= "" Set one.failures = "", one."of_failures" = "", one."why_failures" = whyF
        If whyD = "" {
            Set one.delivered = ..Holding(ns, delivered, field), one."of_delivered" = $LISTLENGTH(delivered)
        } Else {
            Set one."why_delivered" = whyD
        }
        Do count.%Set(field, one)
    }
    Quit count
}

/// How many of the receiver's failures in the last DAYS days hold one of the characters this message holds, in any field:
/// {"failures", "of_failures", "characters"}, the characters in words, with "failures" "" and a "why" when they could not
/// be compared. A character stored as its UTF-8 bytes counts as that character, so a message read as UTF-8 and one read as
/// Latin-1 share it. Empty when the message holds no character above ASCII.
ClassMethod Shared(ns As %String, item As %String, out As %DynamicObject) As %DynamicObject
{
    Set mine = ..Characters(out.fields)
    Quit:mine="" {}
    Set words = ""
    For i = 1:1:$LISTLENGTH(mine) { Set words = words _ $SELECT(i = 1: "", i = $LISTLENGTH(mine): " or ", 1: ", ") _ ..CharacterWords($LIST(mine, i)) }
    Set failures = ..Headers(ns, item, "failed", .why)
    Set shared = {"failures": "", "of_failures": "", "characters": (words)}
    If why '= "" Set shared.why = why Quit shared
    Set n = 0
    For i = 1:1:$LISTLENGTH(failures) {
        Set msg = ..Body(ns, $LIST(failures, i))
        Continue:'$ISOBJECT(msg)
        Set theirs = ..Characters(..Of(msg, "").fields), hit = 0
        For k = 1:1:$LISTLENGTH(theirs) { If $LISTFIND(mine, $LIST(theirs, k)) Set hit = 1 Quit }
        Set n = n + hit
    }
    Set shared.failures = n, shared."of_failures" = $LISTLENGTH(failures)
    Quit shared
}

/// The distinct characters of the finding's fields, each as its code point, a run that is the UTF-8 bytes of one character
/// as that character's, and any other run as its codes joined by "+".
ClassMethod Characters(fields As %DynamicArray) As %List
{
    Set out = ""
    Quit:'$ISOBJECT(fields) out
    Set iter = fields.%GetIterator()
    While iter.%GetNext(, .f) {
        Set run = ""
        Set codes = f.codes.%GetIterator()
        While codes.%GetNext(, .code) { Set run = run _ $CHAR(code) }
        Set key = ""
        If $LENGTH(run) = 1 {
            Set key = $ASCII(run)
        } Else {
            Set decoded = ""
            Try {
                Set:'..Over255(run) decoded = $ZCONVERT(run, "I", "UTF8")
            } Catch {
                Set decoded = ""
            }
            If ($LENGTH(decoded) = 1) && ($ASCII(decoded) > 127) {
                Set key = $ASCII(decoded)
            } Else {
                For k = 1:1:$LENGTH(run) { Set key = key _ $SELECT(k = 1: "", 1: "+") _ $ASCII(run, k) }
            }
        }
        Set:'$LISTFIND(out, key) out = out _ $LISTBUILD(key)
    }
    Quit out
}

/// One of Characters' entries in words.
ClassMethod CharacterWords(key As %String) As %String [ Private ]
{
    Quit:key'["+" ..Name(key)
    Quit "the characters " _ $TRANSLATE(key, "+", " ")
}

/// The header ids to the item in ns: "failed" (Error or Suspended, or marked in error, in the last DAYS days) or
/// "delivered" (Completed, the newest DELIVERED). why is set when the read failed.
ClassMethod Headers(ns As %String, item As %String, which As %String, Output why As %String) As %List [ Private ]
{
    Set why = "", list = ""
    New $NAMESPACE
    Try {
        Set $NAMESPACE = ns
        If which = "failed" {
            // TimeCreated is UTC, as $ZTIMESTAMP is.
            Set since = $ZDATETIME(($PIECE($ZTIMESTAMP, ",", 1) - ..#DAYS) _ "," _ $PIECE($PIECE($ZTIMESTAMP, ",", 2), "."), 3)
            Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Ens.MessageHeader WHERE TargetConfigName = ? AND (Status IN (5, 8) OR IsError = 1) AND TimeCreated >= ? ORDER BY ID DESC", item, since)
        } Else {
            Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP " _ ..#DELIVERED _ " ID FROM Ens.MessageHeader WHERE TargetConfigName = ? AND Status = 9 ORDER BY ID DESC", item)
        }
        If rs.%SQLCODE < 0 { Set why = rs.%Message } Else { While rs.%Next() { Set list = list _ $LISTBUILD(rs.%Get("ID")) } }
    } Catch err {
        Set why = err.DisplayString()
    }
    Quit list
}

/// How many of the headers' bodies carry a character above ASCII in the field ("PID-5").
ClassMethod Holding(ns As %String, headers As %List, field As %String) As %Integer [ Private ]
{
    Set n = 0
    For i = 1:1:$LISTLENGTH(headers) {
        Set msg = ..Body(ns, $LIST(headers, i))
        Continue:'$ISOBJECT(msg)
        Set n = n + ..HasHigh(msg, field)
    }
    Quit n
}

/// Whether any segment named as the field's carries a character above ASCII in that field, any repetition.
ClassMethod HasHigh(msg, field As %String) As %Boolean
{
    Set name = $PIECE(field, "-", 1), number = $PIECE(field, "-", 2)
    For i = 1:1:msg.SegCount {
        Set seg = msg.GetSegmentAt(i)
        Continue:'$ISOBJECT(seg)
        Continue:seg.Name'=name
        Set value = seg.GetValueAt(number)
        For p = 1:1:$LENGTH(value) { Return:$ASCII(value, p)>127 1 }
    }
    Quit 0
}

/// The stored body of a header in ns, copied here (Shutter.Util.MessageCopy), or "".
ClassMethod Body(ns As %String, headerId As %String) [ Private ]
{
    Quit ##class(Shutter.Util.MessageCopy).Of(ns, headerId)
}

/// The finding in words, one sentence per field, the count beside it.
/// The finding's fields grouped by field, character and the bytes sent, in the order they first stand: [{"field",
/// "character", "wire", "places": ["position 3", "position 4 of component 2"]}].
ClassMethod Groups(out As %DynamicObject) As %DynamicArray
{
    Set groups = [], at = ""
    Quit:'$ISOBJECT(out.%Get("fields")) groups
    Set iter = out.fields.%GetIterator()
    While iter.%GetNext(, .f) {
        Set key = f.field _ $CHAR(0) _ f.character _ $CHAR(0) _ f.wire
        Set place = $SELECT(f.position '= "": "position " _ f.position _ $SELECT(f.component > 1: " of component " _ f.component, 1: ""), 1: "")
        If $DATA(at(key)) {
            Do:place'="" groups.%Get(at(key)).places.%Push(place)
        } Else {
            Set at(key) = groups.%Size()
            Do groups.%Push({"field": (f.field), "character": (f.character), "wire": (f.wire), "places": ($SELECT(place '= "": [(place)], 1: []))})
        }
    }
    Quit groups
}

/// One group in words: "NTE-3 holds e with a grave accent, U+00E8 at position 9, position 11 and position 28; the
/// operation sends E8."
/// With places 0 (the escalation email), the places are left out: "NTE-3 holds e with a grave accent, U+00E8; ...".
ClassMethod GroupLine(g As %DynamicObject, places As %Boolean = 1) As %String
{
    Set n = g.places.%Size(), where = ""
    For i = 0:1:n - 1 { Set where = where _ $SELECT(i = 0: "", i = (n - 1): " and ", 1: ", ") _ g.places.%Get(i) }
    Quit g.field _ " holds " _ g.character _ $SELECT(places && (where '= ""): " at " _ where, 1: "") _ "; the operation sends " _ g.wire _ "."
}

ClassMethod Sentence(out As %DynamicObject) As %String
{
    If out.kind = "unreadable" Quit "The stored message could not be read."
    If out.kind = "none" Quit "The message holds no character above ASCII and no '?' in an identity field."
    Set text = "", seen = ""
    // The shared count leads: how many recent failures to this receiver hold the same character, in whichever field.
    Set shared = $SELECT(out.%IsDefined("shared"): out.shared, 1: "")
    If $ISOBJECT(shared) && (shared.characters '= "") {
        Set text = $SELECT(shared.failures '= "": shared.failures _ " of the last " _ shared."of_failures" _ " failures to this receiver in " _ ..#DAYS _ " days hold " _ shared.characters _ ", in any field.", 1: "Its failures could not be compared for " _ shared.characters _ ".")
    }
    // One sentence per field and character, every place it stands named once, then that field's count (1.4.1: a field
    // that held the character at several places repeated the whole sentence for each).
    Set iter = ..Groups(out).%GetIterator()
    While iter.%GetNext(, .g) {
        Set text = text _ $SELECT(text = "": "", 1: " ") _ ..GroupLine(g)
        If '$LISTFIND(seen, g.field) && $ISOBJECT(out.count) && out.count.%IsDefined(g.field) {
            Set seen = seen _ $LISTBUILD(g.field), c = out.count.%Get(g.field)
            Set text = text _ " " _ $SELECT(c.failures '= "": c.failures _ " of the last " _ c."of_failures" _ " failures to this receiver in " _ ..#DAYS _ " days carry a character above ASCII in " _ g.field, 1: "Its failures could not be compared") _ "; " _ $SELECT(c.delivered '= "": c.delivered _ " of the last " _ c."of_delivered" _ " delivered do.", 1: "not compared with what got through.")
        }
    }
    Set iter = out.questions.%GetIterator()
    While iter.%GetNext(, .q) { Set text = text _ $SELECT(text = "": "", 1: " ") _ q.words }
    Quit text _ " Stored MSH-18: " _ $SELECT(out.msh18 '= "": out.msh18, 1: "empty") _ "; the operation's DefCharEncoding: " _ $SELECT(out.setting '= "": out.setting, 1: "unknown") _ "."
}

}
