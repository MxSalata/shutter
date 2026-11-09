/// An escalation to the people who can correct the systems by hand (T29): a case Shutter can't safely recover goes,
/// as an email a person reviewed, to the team that owns the receiver, with what Shutter knows. The draft is built from
/// the stored case alone (Shutter.Util.EscalationDraft), never by a model; sending binds the body's digest, as an
/// approval binds a plan's.
Class Shutter.Store.Escalation Extends (%Persistent, %JSON.Adaptor)
{

Property Case As Shutter.Store.Case(%JSONINCLUDE = "none") [ Required ];

Property Seq As %Integer(%JSONFIELDNAME = "seq") [ Required ];

Index CaseSeq On (Case, Seq) [ Unique ];

/// draft, queued, sent (the mail server accepted it), saved (v1.53: written as an .eml file with no mail server set, so
/// nobody was emailed), failed, cancelled.
Property State As %String(%JSONFIELDNAME = "state", MAXLEN = 16, VALUELIST = ",draft,queued,sent,saved,failed,cancelled") [ InitialExpression = "draft" ];

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

/// When the operation saved it as an .eml file (state saved, v1.53), UTC; sentAt stays empty then.
Property SavedAt As %String(%JSONFIELDNAME = "savedAt", MAXLEN = 30);

/// smtp, or file when no mail server is configured (the .eml is written to the operation's folder).
Property Transport As %String(%JSONFIELDNAME = "transport", MAXLEN = 16);

/// The mail server's answer, the file written, or the error.
Property Result As %String(%JSONFIELDNAME = "result", MAXLEN = 2000);

/// When the email's text was removed by the retention task (Shutter.Util.RetentionTask); the digest, the recipients
/// and the timeline stay.
Property PurgedAt As %String(%JSONFIELDNAME = "purgedAt", MAXLEN = 30);

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
    // A row stored before v1.53 that was written as a file reads saved, with savedAt from its sentAt: nothing is migrated.
    If (..State = "sent") && (..Transport = "file") {
        Set o.state = "saved"
        If ..SavedAt = "" Set o.savedAt = ..SentAt
        Do o.%Remove("sentAt")
    }
    // An empty body is left out of the export; a purged escalation says so with an empty one.
    If ..PurgedAt '= "" Set o.body = ""
    Quit o
}

/// What is wrong with a subject and its recipients (CONTRACTS 10), with the field named: the subject must carry no line
/// break or other control character, and to and cc must be bare addresses inside the allowed domains (Shutter.Util.Mail;
/// an empty list allows none). "" when they pass. The domains default to the site profile's; a test passes its own.
ClassMethod Problem(subject As %String, to As %String, cc As %String, Output field As %String, domains As %List = {##class(Shutter.Store.SiteProfile).AllowedDomains()}) As %String
{
    Set field = "subject", problem = ##class(Shutter.Util.Mail).ControlProblem(subject)
    If problem '= "" Quit problem
    Set field = "to", problem = ##class(Shutter.Util.Mail).AddressesProblem(to, domains)
    If problem '= "" Quit problem
    Set field = "cc", problem = ##class(Shutter.Util.Mail).AddressesProblem(cc, domains)
    If problem '= "" Quit problem
    Set field = ""
    Quit ""
}

/// The escalation's own subject and recipients against the profile as it stands now.
Method Check(Output field As %String) As %String
{
    Quit ..Problem(..Subject, ..ToAddr, ..CcAddr, .field)
}

/// Why a purged escalation can be neither edited nor sent, or "" when its text is still there.
Method PurgedProblem() As %String [ Private ]
{
    If ..PurgedAt = "" Quit ""
    Quit "Escalation " _ ..Seq _ "'s text was removed on " _ ..PurgedAt _ " by the retention task; it cannot be edited or sent"
}

/// Edit a draft (or a failed send) before it goes: the digest follows the new text. The subject and the addresses are
/// checked first; an error that starts with the field's name ("to: ...") is the person's to correct.
Method Edit(subject As %String, body As %String, to As %String, cc As %String, user As %String) As %Status
{
    If '$LISTFIND($LISTBUILD("draft", "failed"), ..State) Quit $$$ERROR($$$GeneralError, "Escalation " _ ..Seq _ " is " _ ..State _ ": only a draft or a failed send can be edited")
    If ..PurgedProblem() '= "" Quit $$$ERROR($$$GeneralError, ..PurgedProblem())
    If to = "" Quit $$$ERROR($$$GeneralError, "to: at least one address")
    Set problem = ..Problem(subject, to, cc, .field)
    If problem '= "" Quit $$$ERROR($$$GeneralError, field _ ": " _ problem)
    Set ..Subject = subject, ..Body = body, ..ToAddr = to, ..CcAddr = cc
    Set ..EditedBy = user, ..EditedAt = ##class(Shutter.Util.Time).NowUTC(), ..State = "draft"
    Do ..Redigest()
    Quit ..%Save()
}

/// The state as every route and count reads it: a row stored before v1.53 that was written as a file reads saved.
Method ShownState() As %String
{
    Quit $SELECT((..State = "sent") && (..Transport = "file"): "saved", 1: ..State)
}

/// Queue the send: the digest must be the one of the text the person last read, and the subject and addresses must
/// still pass (the allowed domains may have changed since the edit, or the row was changed outside the API). A saved
/// escalation can go again, as a draft or a failed one can: once a mail server is set the same text is sent.
Method Queue(bodyDigest As %String, user As %String) As %Status
{
    If '$LISTFIND($LISTBUILD("draft", "failed", "saved"), ..ShownState()) Quit $$$ERROR($$$GeneralError, "Escalation " _ ..Seq _ " is " _ ..ShownState())
    If ..PurgedProblem() '= "" Quit $$$ERROR($$$GeneralError, ..PurgedProblem())
    If bodyDigest '= ..BodyDigest Quit $$$ERROR($$$GeneralError, "bodyDigest is not the digest of the escalation's current text")
    If ..ToAddr = "" Quit $$$ERROR($$$GeneralError, "The escalation has no recipient")
    Set problem = ..Check(.field)
    If problem '= "" Quit $$$ERROR($$$GeneralError, field _ ": " _ problem)
    Set ..State = "queued", ..SentBy = user
    Set sc = ..%Save()
    Quit:$$$ISERR(sc) sc
    // The record names the digest of the text queued, so the timeline alone shows what the person approved for sending. The
    // person's act is a queue: whether the mail server took it or it was saved as a file is the operation's line after.
    Quit ..Note("Escalation " _ ..Seq _ " queued by " _ user _ " for " _ ..ToAddr _ "; digest of the text queued " _ ..BodyDigest, user)
}

/// The mail server accepted it (smtp): state sent. The server's acceptance is not a delivery to a person, and its words
/// say so. A file goes through MarkSaved.
Method MarkSent(transport As %String, result As %String) As %Status
{
    If transport = "file" Quit ..MarkSaved(result)
    Set ..State = "sent", ..Transport = transport, ..Result = $EXTRACT(result, 1, 2000), ..SentAt = ##class(Shutter.Util.Time).NowUTC()
    Set sc = ..%Save()
    Quit:$$$ISERR(sc) sc
    Quit ..Note("Escalation " _ ..Seq _ " sent through the mail server: " _ $EXTRACT(result, 1, 300), "system")
}

/// No mail server is set, so the email was written as an .eml file at path (v1.53): state saved, savedAt, sentAt empty.
/// Nobody was emailed, and the case's line says so.
Method MarkSaved(path As %String) As %Status
{
    Set ..State = "saved", ..Transport = "file", ..Result = $EXTRACT(path, 1, 2000), ..SavedAt = ##class(Shutter.Util.Time).NowUTC(), ..SentAt = ""
    Set sc = ..%Save()
    Quit:$$$ISERR(sc) sc
    Quit ..Note("Escalation " _ ..Seq _ " saved as an email file, not delivered: " _ $EXTRACT(path, 1, 300) _ ". No mail server is set, so nobody was emailed.", "system")
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

/// Remove the email's text (the body: the one copy of the NHS number and the date of birth outside the message store)
/// and, for a file transport, the .eml file, days days after the case closed; the row stays with its digest, its
/// recipients, who drafted, edited and sent it, and a line on the case's timeline says the text went.
Method PurgeText(days As %Integer) As %Status
{
    If ..Transport = "file" Do ..RemoveFile(..Result, ..Seq)
    Set ..Body = "", ..PurgedAt = ##class(Shutter.Util.Time).NowUTC()
    Set sc = ..%Save()
    Quit:$$$ISERR(sc) sc
    Quit ..Note("Escalation " _ ..Seq _ ": the email's text was removed " _ days _ " days after the case closed; the digest of the text " _ $SELECT(..ShownState() = "saved": "saved", 1: "sent") _ ", the recipients and who sent it stay on record", "system")
}

/// The retention task's pass (Shutter.Util.RetentionTask): the text of every escalation of a case closed before the
/// cutoff goes (PurgeText), queued ones excepted, since the mail operation is about to read them; a case reopened since
/// keeps its texts until it closes again. Rows whose case was purged before escalations were part of the case purge are
/// removed with their files. Returns how many rows were purged.
ClassMethod PurgeTextBefore(cutoff As %String, days As %Integer) As %Integer
{
    Set n = 0
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT e.ID FROM Shutter_Store.Escalation e, Shutter_Store.""Case"" c WHERE c.ID = e.""Case"" AND e.PurgedAt IS NULL AND e.State <> 'queued' AND c.State IN ('resolved', 'blocked', 'escalated', 'failed') AND c.ClosedAt IS NOT NULL AND c.ClosedAt < ?", cutoff)
    While rs.%Next() {
        Set e = ..%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(e)
        If $$$ISOK(e.PurgeText(days)) Set n = n + 1
    }
    Set orphans = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID, Seq, Transport, Result FROM Shutter_Store.Escalation WHERE ""Case"" NOT IN (SELECT ID FROM Shutter_Store.""Case"")")
    While orphans.%Next() {
        If orphans.%Get("Transport") = "file" Do ..RemoveFile(orphans.%Get("Result"), orphans.%Get("Seq"))
        If $$$ISOK(..%DeleteId(orphans.%Get("ID"))) Set n = n + 1
    }
    Quit n
}

/// Delete the .eml file an escalation was written to, by the path its Result holds. Only a file named as the mail
/// operation names them, <CaseId>-escalation-<Seq>.eml, is touched: anything else answers 0 and is left alone. A file
/// already gone counts as removed.
ClassMethod RemoveFile(path As %String, seq As %Integer) As %Boolean
{
    If path = "" Quit 0
    Set name = $PIECE($TRANSLATE(path, "\", "/"), "/", *), suffix = "-escalation-" _ (+seq) _ ".eml"
    Set start = $LENGTH(name) - $LENGTH(suffix) + 1
    If (start < 2) || ($EXTRACT(name, start, *) '= suffix) Quit 0
    If '##class(%File).Exists(path) Quit 1
    Quit ''##class(%File).Delete(path)
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
<Value name="21">
<Value>PurgedAt</Value>
</Value>
<Value name="22">
<Value>SavedAt</Value>
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
