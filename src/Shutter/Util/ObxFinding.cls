/// Which OBX a receiver refused a result for, from its own words: the words are matched literally against every OBX's
/// test code (OBX-3.1), and the finding names the k-th OBX, its set id (OBX-1) and the code, or says no OBX matches.
/// A message that fits no structure (an OBX before its OBR) is a finding of its own, in the words Validate("dm") gives.
///
/// The OBX are found by scanning every segment by name, never by a group path: on a stock ORU, OBX(*) with no group
/// path counts 0, and a site's own schema flattens the paths (measured on 2026.2 and 2027.1.0AI). This scan reads every
/// segment for this finding only; the evidence's own scan keeps its cap of 50 segments.
///
/// A local diagnostic: it names a set id and a code, and never reads, prints or weighs a result's value (OBX-5).
Class Shutter.Util.ObxFinding [ Abstract ]
{

/// The most validation words kept, in characters.
Parameter SCHEMAWORDS = 300;

/// The finding for <var>msg</var> (an EnsLib.HL7.Message) and the receiver's <var>words</var>:
/// {"kind", "obx_count", "matches": [{"position", "set_id", "code"}], "schema", "sentence"}. kind is
/// "obx" (one or more OBX named), "no_match" (OBX present, none of their codes in the words), "no_obx",
/// "no_words" (the receiver said nothing to match), "schema" (the message fits no structure; matches may still be
/// listed) or "unreadable" (no message). position counts OBX segments from 1 in the order they stand.
ClassMethod Find(msg, words As %String) As %DynamicObject
{
    Set out = {"kind": "unreadable", "obx_count": 0, "matches": [], "schema": "", "sentence": "The message could not be read, so no OBX is named."}
    Quit:'$ISOBJECT(msg) out
    Quit:'msg.%IsA("EnsLib.HL7.Message") out
    Set obx = ..Codes(msg)
    Do out.%Set("obx_count", obx.%Size(), "number")
    // The structure is checked only for a message with an OBX: this finding is about results, and an ADT missing an EVN is not.
    Set:obx.%Size()>0 out.schema = ..Schema(msg)
    For k = 1:1:obx.%Size() {
        Set one = obx.%Get(k - 1)
        Continue:one.code=""
        Continue:'..Names(words, one.code)
        Do out.matches.%Push(one)
    }
    If obx.%Size() = 0 {
        Set out.kind = "no_obx"
    } ElseIf out.schema '= "" {
        Set out.kind = "schema"
    } ElseIf $ZSTRIP(words, "<>W") = "" {
        Set out.kind = "no_words"
    } ElseIf out.matches.%Size() = 0 {
        Set out.kind = "no_match"
    } Else {
        Set out.kind = "obx"
    }
    Set out.sentence = ..Sentence(out)
    Quit out
}

/// Every OBX segment, by name, in order: {"position", "set_id", "code"}.
ClassMethod Codes(msg) As %DynamicArray
{
    Set list = [], k = 0
    For i = 1:1:msg.SegCount {
        Set seg = msg.GetSegmentAt(i)
        Continue:'$ISOBJECT(seg)
        Continue:seg.Name'="OBX"
        Set k = k + 1
        Set one = {"position": (k), "set_id": (seg.GetValueAt("1")), "code": (seg.GetValueAt("3.1"))}
        Do one.%Set("position", k, "number")
        Do list.%Push(one)
    }
    Quit list
}

/// Validate("dm")'s words when the message fits no structure of its DocType, cut to SCHEMAWORDS; "" when it fits, or
/// when it has no DocType to check against.
ClassMethod Schema(msg) As %String
{
    Quit:msg.DocType="" ""
    Try {
        Set sc = msg.Validate("dm")
    } Catch err {
        Set sc = err.AsStatus()
    }
    Quit:$$$ISOK(sc) ""
    Quit $EXTRACT($SYSTEM.Status.GetErrorText(sc), 1, ..#SCHEMAWORDS)
}

/// Whether <var>words</var> name <var>code</var> literally: the code, case and all, with no letter or digit on either side,
/// so that a code such as "K" is not found inside "OK" and "GLU" is not found in "GLUC".
ClassMethod Names(words As %String, code As %String) As %Boolean
{
    Quit:code="" 0
    Set from = 1, len = $LENGTH(code)
    For {
        Set at = $FIND(words, code, from)
        Quit:at=0
        Set before = $EXTRACT(words, at - len - 1), after = $EXTRACT(words, at)
        Quit:'..Word(before)&&'..Word(after)
        Set from = at - len + 1
    }
    Quit at'=0
}

/// Whether one character is a letter or a digit (ASCII; a code is matched as written).
ClassMethod Word(char As %String) As %Boolean [ Private ]
{
    Quit:char="" 0
    Quit char?1(1A,1N)
}

/// The finding in words.
ClassMethod Sentence(out As %DynamicObject) As %String
{
    If out.kind = "schema" Quit "The message does not fit its structure, so the receiver may not have read it as sent: " _ out.schema
    If out.kind = "no_obx" Quit "The message holds no OBX, so no test code is named."
    If out.kind = "no_words" Quit "The receiver's words name no test code, so no OBX is named."
    If out.kind = "no_match" Quit "No OBX matches the receiver's words: none of the " _ out."obx_count" _ " test codes appears in them."
    Set text = ""
    For i = 0:1:out.matches.%Size() - 1 {
        Set m = out.matches.%Get(i)
        Set text = text _ $SELECT(i = 0: "", i = (out.matches.%Size() - 1): " and ", 1: ", ") _ "the " _ ..Ordinal(m.position) _ " OBX of " _ out."obx_count" _ ", set id OBX-1 = " _ m."set_id" _ ", code '" _ m.code _ "'"
    }
    Quit "The receiver's words name " _ text _ "."
}

/// 1st, 2nd, 3rd, 4th, 11th, 12th, 13th, 21st.
ClassMethod Ordinal(n As %Integer) As %String
{
    Set tens = n # 100
    Quit:((tens>=11)&&(tens<=13)) n _ "th"
    Quit n _ $CASE(n # 10, 1: "st", 2: "nd", 3: "rd", : "th")
}

}
