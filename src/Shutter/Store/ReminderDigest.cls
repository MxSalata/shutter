/// One reminder mail to one recipient, from the task that built it to the mail server's answer (CONTRACTS 6.4,
/// reminders). Its text, the one copy of the identifiers it carries, goes as soon as the send is over either way; the row
/// keeps who it went to, the case numbers and the answer. Only a digest the mail server took records its cases as reminded,
/// so a failed one is built afresh at the next run.
Class Shutter.Store.ReminderDigest Extends %Persistent
{

/// A digest not sent within this many seconds is failed and built afresh, so nothing goes out late from a production that
/// was stopped, or lists a case closed since.
Parameter STALESECONDS = 1800;

/// One bare address, lowercased.
Property Recipient As %String(MAXLEN = 320) [ Required ];

/// queued; accepted, which is the mail server's answer and says nothing of a person reading it; or failed.
Property State As %String(MAXLEN = 16, VALUELIST = ",queued,accepted,failed") [ InitialExpression = "queued" ];

Property Subject As %String(MAXLEN = 500);

Property Body As %String(MAXLEN = "");

/// The cases as JSON: [{"id", "caseId", "threshold", "hours"}].
Property Items As %String(MAXLEN = "");

/// The patient detail the text was built at.
Property Detail As %String(MAXLEN = 32);

Property CreatedAt As %String(MAXLEN = 30);

Property AcceptedAt As %String(MAXLEN = 30);

/// The mail server's answer, or why it did not go.
Property Result As %String(MAXLEN = 2000);

ClassMethod Create(recipient As %String, subject As %String, body As %String, items As %DynamicArray, now As %String, Output row As Shutter.Store.ReminderDigest, detail As %String = "") As %Status
{
    Set row = ..%New()
    Set row.Recipient = $ZCONVERT(recipient, "L"), row.Subject = subject, row.Body = body, row.Items = items.%ToJSON(), row.CreatedAt = now, row.Detail = detail
    Quit row.%Save()
}

/// Why this digest may not go now, or "": the setting off, the window shut, too old, or the address no longer allowed.
Method SendProblem(now As %String, settings As %DynamicObject, domains As %List) As %String
{
    If 'settings.enabled Quit "the reminders are off"
    If '##class(Shutter.Util.CaseReminder).InWindow(now, settings) Quit "outside the reminder window"
    Set age = ##class(Shutter.Util.Time).SecondsBetween(..CreatedAt, now)
    If (age = "") || (age >= ..#STALESECONDS) Quit "not sent within half an hour of being built"
    Set problem = ##class(Shutter.Util.Mail).AddressProblem(..Recipient, domains)
    If problem '= "" Quit ..Recipient _ ": " _ problem
    Quit ##class(Shutter.Util.Mail).ControlProblem(..Subject)
}

/// What has changed since the text was built, so that it must not go, or "": the patient detail, a case that no longer
/// needs a person or has had this reminder, or who the reminder is for. Read as late as the send can read it. Not a fault:
/// the next run builds what is still due.
Method ChangedSince(settings As %DynamicObject) As %String
{
    If ..Detail '= settings."patient_detail" Quit "the patient detail setting has changed"
    Set items = ##class(Shutter.Util.Json).Parse(..Items, .psc)
    If '$ISOBJECT(items) Quit "its cases cannot be read"
    Set states = $LISTFROMSTRING(##class(Shutter.Util.CaseReminder).#NEEDSPERSON)
    Set it = items.%GetIterator()
    While it.%GetNext(, .item) {
        Set case = ##class(Shutter.Store.Case).%OpenId(item.id, 0)
        If '$ISOBJECT(case) Return item.caseId _ " has gone"
        If '$LISTFIND(states, case.State) || (case.Disposition = "abandoned") Return item.caseId _ " no longer needs a person"
        If ##class(Shutter.Store.CaseReminder).CaseThresholdExists(item.id, item.threshold) Return item.caseId _ " has had this reminder"
        Set to = $SELECT(item.threshold = "officer": settings."officer_address", 1: ##class(Shutter.Util.Json).Str(##class(Shutter.Util.EscalationDraft).Team(case), "mailbox"))
        If $ZCONVERT(to, "L") '= ..Recipient Return item.caseId _ " has a new recipient"
    }
    Quit ""
}

/// The mail server took it: each case's threshold is recorded with a line on its audit trail, and the text goes. Touches
/// no case row: the version, the state and the time of the case stay as they are. A threshold already recorded is left.
Method MarkAccepted(result As %String, now As %String = {##class(Shutter.Util.Time).NowUTC()}) As %Status
{
    Set ..State = "accepted", ..Result = $EXTRACT(result, 1, 2000), ..AcceptedAt = now, ..Body = ""
    Set sc = ..%Save()
    Quit:$$$ISERR(sc) sc
    Set ^Shutter.Reminder("last_accepted") = now
    Kill ^Shutter.Reminder("last_error")
    Set it = ##class(Shutter.Util.Json).Parse(..Items, .psc)
    Quit:'$ISOBJECT(it) $$$OK
    Set iter = it.%GetIterator()
    While iter.%GetNext(, .item) {
        Set case = ##class(Shutter.Store.Case).%OpenId(item.id, 0)
        Continue:'$ISOBJECT(case)
        Set rec = ##class(Shutter.Store.CaseReminder).%New()
        Do rec.CaseSetObjectId(item.id)
        Set rec.Threshold = item.threshold, rec.Recipient = ..Recipient, rec.DigestId = ..%Id(), rec.AcceptedAt = now
        // The unique index refuses a threshold already recorded: nothing more to write for it.
        Continue:$$$ISERR(rec.%Save())
        Set word = $SELECT(item.threshold = "officer": "later reminder", 1: "first reminder")
        Set ev = ##class(Shutter.Store.CaseEvent).Append(case, "note", "", "", "The mail server accepted a reminder for " _ ..Recipient _ " (" _ word _ ", open " _ item.hours _ " hours or more). That does not show anyone has read it. It moves the case nowhere.", "system", "reminder:" _ ..%Id())
        If $$$ISERR(ev) Set sc = ev
    }
    Quit sc
}

/// It did not go: the reason is kept and, unless quiet, logged; the text goes, and the next run builds its cases into a new
/// digest. Quiet is for a digest overtaken by events, which is no fault to show on the Health page.
Method MarkFailed(reason As %String, quiet As %Boolean = 0) As %Status
{
    Set ..State = "failed", ..Result = $EXTRACT(reason, 1, 2000), ..Body = ""
    If 'quiet Do ##class(Shutter.Util.CaseReminderTask).Note("A reminder to " _ ..Recipient _ " did not go, and goes again at the next run: " _ $EXTRACT(reason, 1, 500))
    Quit ..%Save()
}

/// The latest digest per address that counts against the hourly limit, accepted or still queued, as an object of addresses
/// and times.
ClassMethod LastSent(now As %String) As %DynamicObject
{
    Set out = {}
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT Recipient, State, AcceptedAt, CreatedAt FROM Shutter_Store.ReminderDigest WHERE State IN ('queued', 'accepted') ORDER BY ID")
    While rs.%Next() {
        Set at = $SELECT(rs.%Get("State") = "accepted": rs.%Get("AcceptedAt"), 1: rs.%Get("CreatedAt"))
        Set to = rs.%Get("Recipient"), had = out.%Get(to)
        If (had = "") || (at ] had) Do out.%Set(to, at)
    }
    Quit out
}

/// Fail each queued digest older than STALESECONDS, as a production that is not running leaves them. Returns how many.
ClassMethod ExpireStale(now As %String) As %Integer
{
    Set n = 0
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID, CreatedAt FROM Shutter_Store.ReminderDigest WHERE State = 'queued'")
    While rs.%Next() {
        Set age = ##class(Shutter.Util.Time).SecondsBetween(rs.%Get("CreatedAt"), now)
        Continue:(age '= "")&&(age < ..#STALESECONDS)
        Set row = ..%OpenId(rs.%Get("ID"))
        If $ISOBJECT(row) && $$$ISOK(row.MarkFailed("not sent within half an hour of being built")) Set n = n + 1
    }
    Quit n
}

Storage Default
{
<Data name="ReminderDigestDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Recipient</Value>
</Value>
<Value name="3">
<Value>State</Value>
</Value>
<Value name="4">
<Value>Subject</Value>
</Value>
<Value name="5">
<Value>Body</Value>
</Value>
<Value name="6">
<Value>Items</Value>
</Value>
<Value name="7">
<Value>CreatedAt</Value>
</Value>
<Value name="8">
<Value>AcceptedAt</Value>
</Value>
<Value name="9">
<Value>Result</Value>
</Value>
<Value name="10">
<Value>Detail</Value>
</Value>
</Data>
<DataLocation>^Shutter.Store.ReminderDigestD</DataLocation>
<DefaultData>ReminderDigestDefaultData</DefaultData>
<IdLocation>^Shutter.Store.ReminderDigestD</IdLocation>
<IndexLocation>^Shutter.Store.ReminderDigestI</IndexLocation>
<StreamLocation>^Shutter.Store.ReminderDigestS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
