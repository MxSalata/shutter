/// An escalation to the people who can correct the systems by hand (T29): a case Shutter can't safely recover goes,
/// as an email a person reviewed, to the team that owns the receiver, with what Shutter knows. The draft is built from
/// the stored case alone (Shutter.Util.EscalationDraft), never by a model; sending binds the body's digest, as an
/// approval binds a plan's.
Class Shutter.Store.Escalation Extends (%Persistent, %JSON.Adaptor)
{

Property Case As Shutter.Store.Case(%JSONINCLUDE = "none") [ Required ];

Property Seq As %Integer(%JSONFIELDNAME = "seq") [ Required ];

Index CaseSeq On (Case, Seq) [ Unique ];

/// draft, queued, sent, failed, cancelled.
Property State As %String(%JSONFIELDNAME = "state", MAXLEN = 16, VALUELIST = ",draft,queued,sent,failed,cancelled") [ InitialExpression = "draft" ];

Property TeamId As %String(%JSONFIELDNAME = "teamId", MAXLEN = 64);

Property TeamName As %String(%JSONFIELDNAME = "teamName", MAXLEN = 200);

/// Addresses, separated by commas.
Property ToAddr As %String(%JSONFIELDNAME = "to", MAXLEN = 2000);

Property CcAddr As %String(%JSONFIELDNAME = "cc", MAXLEN = 2000);

Property Subject As %String(%JSONFIELDNAME = "subject", MAXLEN = 500);

Property Body As %String(%JSONFIELDNAME = "body", MAXLEN = "");

/// The digest of the subject, recipients and body as last drafted or edited: a send names it, so what was sent is
/// what the person read.
Property BodyDigest As %String(%JSONFIELDNAME = "bodyDigest", MAXLEN = 80);

/// The evidence snapshot the draft was built from.
Property SnapshotDigest As %String(%JSONFIELDNAME = "snapshotDigest", MAXLEN = 80);

Property DraftedBy As %String(%JSONFIELDNAME = "draftedBy", MAXLEN = 100);

Property DraftedAt As %String(%JSONFIELDNAME = "draftedAt", MAXLEN = 30);

Property EditedBy As %String(%JSONFIELDNAME = "editedBy", MAXLEN = 100);

Property EditedAt As %String(%JSONFIELDNAME = "editedAt", MAXLEN = 30);

Property SentBy As %String(%JSONFIELDNAME = "sentBy", MAXLEN = 100);

Property SentAt As %String(%JSONFIELDNAME = "sentAt", MAXLEN = 30);

/// smtp, or file when no mail server is configured (the .eml is written to the operation's folder).
Property Transport As %String(%JSONFIELDNAME = "transport", MAXLEN = 16);

/// The mail server's answer, the file written, or the error.
Property Result As %String(%JSONFIELDNAME = "result", MAXLEN = 2000);

/// A new draft for the case, addressed to a team of the site profile (the receiver's, when teamId is empty).
ClassMethod Draft(case As Shutter.Store.Case, teamId As %String, user As %String, Output esc As Shutter.Store.Escalation) As %Status
{
    Set esc = ""
    If '$ISOBJECT(case) Quit $$$ERROR($$$GeneralError, "No case")
    Set team = ##class(Shutter.Util.EscalationDraft).Team(case, teamId)
    If teamId '= "" && (##class(Shutter.Util.Json).Str(team, "id") '= teamId) Quit $$$ERROR($$$GeneralError, "No team " _ teamId _ " in the site profile")
    Set sc = ##class(Shutter.Util.EscalationDraft).Build(case, team, .subject, .body)
    Quit:$$$ISERR(sc) sc
    Set esc = ..%New()
    Set esc.Case = case, esc.Seq = ..NextSeq(case)
    Set esc.TeamId = ##class(Shutter.Util.Json).Str(team, "id"), esc.TeamName = ##class(Shutter.Util.Json).Str(team, "name")
    Set esc.ToAddr = ##class(Shutter.Util.Json).Str(team, "mailbox")
    Set cc = team.%Get("cc")
    If $ISOBJECT(cc) {
        Set list = "", it = cc.%GetIterator()
        While it.%GetNext(, .addr) { Set list = list _ $SELECT(list = "": "", 1: ", ") _ addr }
        Set esc.CcAddr = list
    }
    Set esc.Subject = subject, esc.Body = body
    Set esc.SnapshotDigest = $SELECT($ISOBJECT(case.CurrentSnapshot): case.CurrentSnapshot.Digest, 1: "")
    Set esc.DraftedBy = user, esc.DraftedAt = ##class(Shutter.Util.Time).NowUTC()
    Do esc.Redigest()
    Set sc = esc.%Save()
    Quit:$$$ISERR(sc) sc
    Quit esc.Note("Escalation " _ esc.Seq _ " drafted for " _ $SELECT(esc.TeamName '= "": esc.TeamName, 1: "a person") _ " (" _ esc.ToAddr _ ")", user)
}

/// The escalations of a case, oldest first.
ClassMethod ForCase(case As Shutter.Store.Case) As %DynamicArray
{
    Set out = []
    Quit:'$ISOBJECT(case) out
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.Escalation WHERE ""Case"" = ? ORDER BY Seq", case.%Id())
    While rs.%Next() {
        Set e = ..%OpenId(rs.%Get("ID"))
        Do:$ISOBJECT(e) out.%Push(e.ToObject())
    }
    Quit out
}

ClassMethod BySeq(case As Shutter.Store.Case, seq As %Integer) As Shutter.Store.Escalation
{
    Quit:'$ISOBJECT(case) ""
    Set cid = case.%Id(), rid = ""
    &sql(SELECT ID INTO :rid FROM Shutter_Store.Escalation WHERE "Case" = :cid AND Seq = :seq)
    Quit $SELECT((SQLCODE = 0) && (rid '= ""): ..%OpenId(rid), 1: "")
}

ClassMethod NextSeq(case As Shutter.Store.Case) As %Integer [ Private ]
{
    Set cid = case.%Id(), n = 0
    &sql(SELECT MAX(Seq) INTO :n FROM Shutter_Store.Escalation WHERE "Case" = :cid)
    Quit +n + 1
}

Method ToObject() As %DynamicObject
{
    Set sc = ..%JSONExportToString(.json)
    Set o = $SELECT($$$ISOK(sc): ##class(%DynamicObject).%FromJSON(json), 1: {})
    Set o.caseId = ..Case.CaseId
    Quit o
}

/// Edit a draft (or a failed send) before it goes: the digest follows the new text.
Method Edit(subject As %String, body As %String, to As %String, cc As %String, user As %String) As %Status
{
    If '$LISTFIND($LISTBUILD("draft", "failed"), ..State) Quit $$$ERROR($$$GeneralError, "Escalation " _ ..Seq _ " is " _ ..State _ ": only a draft or a failed send can be edited")
    If to = "" Quit $$$ERROR($$$GeneralError, "to: at least one address")
    Set ..Subject = subject, ..Body = body, ..ToAddr = to, ..CcAddr = cc
    Set ..EditedBy = user, ..EditedAt = ##class(Shutter.Util.Time).NowUTC(), ..State = "draft"
    Do ..Redigest()
    Quit ..%Save()
}

/// Queue the send: the digest must be the one of the text the person last read.
Method Queue(bodyDigest As %String, user As %String) As %Status
{
    If '$LISTFIND($LISTBUILD("draft", "failed"), ..State) Quit $$$ERROR($$$GeneralError, "Escalation " _ ..Seq _ " is " _ ..State)
    If bodyDigest '= ..BodyDigest Quit $$$ERROR($$$GeneralError, "bodyDigest is not the digest of the escalation's current text")
    If ..ToAddr = "" Quit $$$ERROR($$$GeneralError, "The escalation has no recipient")
    Set ..State = "queued", ..SentBy = user
    Set sc = ..%Save()
    Quit:$$$ISERR(sc) sc
    Quit ..Note("Escalation " _ ..Seq _ " sent by " _ user _ " to " _ ..ToAddr, user)
}

Method MarkSent(transport As %String, result As %String) As %Status
{
    Set ..State = "sent", ..Transport = transport, ..Result = $EXTRACT(result, 1, 2000), ..SentAt = ##class(Shutter.Util.Time).NowUTC()
    Set sc = ..%Save()
    Quit:$$$ISERR(sc) sc
    Quit ..Note("Escalation " _ ..Seq _ " delivered (" _ transport _ "): " _ $EXTRACT(result, 1, 300), "system")
}

Method MarkFailed(error As %String) As %Status
{
    Set ..State = "failed", ..Result = $EXTRACT(error, 1, 2000)
    Set sc = ..%Save()
    Quit:$$$ISERR(sc) sc
    Quit ..Note("Escalation " _ ..Seq _ " could not be sent: " _ $EXTRACT(error, 1, 300), "system")
}

Method Redigest() [ Private ]
{
    Set ..BodyDigest = ##class(Shutter.Util.Digest).SHA256Hex(..ToAddr _ $CHAR(10) _ ..CcAddr _ $CHAR(10) _ ..Subject _ $CHAR(10) _ ..Body)
}

/// A line on the case's timeline, so the record says who it went to (RP-4.3).
Method Note(text As %String, user As %String) As %Status [ Private ]
{
    // "escalation" once CaseEvent's kinds list it; a note until then
    Set kind = $SELECT($$$ISOK(##class(Shutter.Store.CaseEvent).KindIsValid("escalation")): "escalation", 1: "note")
    Quit ##class(Shutter.Store.CaseEvent).Append(..Case, kind, "", "", text, user, "escalation:" _ ..Seq)
}

Storage Default
{
<Data name="EscalationDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Case</Value>
</Value>
<Value name="3">
<Value>Seq</Value>
</Value>
<Value name="4">
<Value>State</Value>
</Value>
<Value name="5">
<Value>TeamId</Value>
</Value>
<Value name="6">
<Value>TeamName</Value>
</Value>
<Value name="7">
<Value>ToAddr</Value>
</Value>
<Value name="8">
<Value>CcAddr</Value>
</Value>
<Value name="9">
<Value>Subject</Value>
</Value>
<Value name="10">
<Value>Body</Value>
</Value>
<Value name="11">
<Value>BodyDigest</Value>
</Value>
<Value name="12">
<Value>SnapshotDigest</Value>
</Value>
<Value name="13">
<Value>DraftedBy</Value>
</Value>
<Value name="14">
<Value>DraftedAt</Value>
</Value>
<Value name="15">
<Value>EditedBy</Value>
</Value>
<Value name="16">
<Value>EditedAt</Value>
</Value>
<Value name="17">
<Value>SentBy</Value>
</Value>
<Value name="18">
<Value>SentAt</Value>
</Value>
<Value name="19">
<Value>Transport</Value>
</Value>
<Value name="20">
<Value>Result</Value>
</Value>
</Data>
<DataLocation>^Shutter.Store.EscalationD</DataLocation>
<DefaultData>EscalationDefaultData</DefaultData>
<IdLocation>^Shutter.Store.EscalationD</IdLocation>
<IndexLocation>^Shutter.Store.EscalationI</IndexLocation>
<StreamLocation>^Shutter.Store.EscalationS</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
