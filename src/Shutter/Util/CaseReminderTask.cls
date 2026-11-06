/// Runs the reminders for cases left open every quarter of an hour, as the task "Shutter case reminders" the installer
/// schedules. Off unless the site profile switches them on. It reads the cases, asks Shutter.Util.CaseReminder who is due
/// what, and hands each digest to the Escalation Mail operation, so the mail goes by the escalation mail's server settings.
/// It writes to no receiver, calls no model, and moves no case. A failure is logged and goes again at the next run.
Class Shutter.Util.CaseReminderTask Extends %SYS.Task.Definition
{

Parameter TaskName = "Shutter case reminders";

/// Rows of digests older than this go: they hold no identifiers, only who was told about which case number.
Parameter KEEPDAYS = 90;

Method OnTask() As %Status
{
    // Never a task error: the Task Manager can suspend a task that fails, and a reminder must not stop anything.
    Try {
        Do ..Run()
    } Catch ex {
        Do ..Note("The reminder run failed: " _ ex.DisplayString())
    }
    Quit $$$OK
}

/// A warning in the production's event log and the Doctor's last_error. Never the text of a digest.
ClassMethod Note(text As %String)
{
    Set ^Shutter.Reminder("last_error") = $LISTBUILD(##class(Shutter.Util.Time).NowUTC(), text)
    Try { Do ##class(Ens.Util.Log).LogWarning($CLASSNAME(), "Note", text) } Catch ex { }
}

/// The SMTP server set on the Escalation Mail operation, "" when none or the item cannot be read.
ClassMethod MailServer() As %String
{
    Set server = ""
    Try {
        Set server = ##class(Ens.Director).GetItemSettingValue("Escalation Mail", "Adapter", "SMTPServer", .sc)
        If $$$ISERR(sc) Set server = ""
    } Catch ex {
        Set server = ""
    }
    Quit server
}

/// One run at a time. Returns how many digests were queued.
ClassMethod Run(now As %String = "") As %Integer
{
    If now = "" Set now = ##class(Shutter.Util.Time).NowUTC()
    Set settings = ##class(Shutter.Util.CaseReminder).Settings(##class(Shutter.Store.SiteProfile).Current())
    If 'settings.enabled Quit 0
    LOCK +^Shutter.Reminder("run"):0
    If '$TEST Quit 0
    Set queued = 0
    Try {
        Set ^Shutter.Reminder("last_run") = now
        Do ##class(Shutter.Store.ReminderDigest).ExpireStale(now)
        Do ##class(%SQL.Statement).%ExecDirectNoPriv(, "DELETE FROM Shutter_Store.ReminderDigest WHERE CreatedAt < ? AND State <> 'queued'", ##class(Shutter.Util.Time).FromNow(-86400 * ..#KEEPDAYS))
        Set decided = ##class(Shutter.Util.CaseReminder).Decide(..Gather(settings, now), now, settings, ##class(Shutter.Store.ReminderDigest).LastSent(now))
        If decided.digests.%Size() > 0 {
            If ..MailServer() = "" {
                // No file and no record: an .eml nobody reads would leave identifiers on disk and say a reminder went.
                Do ..Note("Reminders are due and no mail server is set on the Escalation Mail operation, so none went")
            } Else {
                Set it = decided.digests.%GetIterator()
                While it.%GetNext(, .digest) { Set queued = queued + ..Send(digest, settings, now) }
            }
        }
    } Catch ex {
        Do ..Note("The reminder run failed: " _ ex.DisplayString())
    }
    LOCK -^Shutter.Reminder("run")
    Quit queued
}

/// The cases that have reached the first threshold and need a person, oldest first, as Decide reads them.
ClassMethod Gather(settings As %DynamicObject, now As %String) As %DynamicArray
{
    Set out = []
    Set back = -(settings."team_hours" * 3600)
    Set cutoff = ##class(Shutter.Util.Time).PlusMillis(now, back * 1000)
    Set states = ##class(Shutter.Util.CaseReminder).#NEEDSPERSON
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.""Case"" WHERE State %INLIST ? AND OpenedAt <= ? ORDER BY OpenedAt, ID", $LISTFROMSTRING(states), cutoff)
    While rs.%Next() {
        Set case = ##class(Shutter.Store.Case).%OpenId(rs.%Get("ID"), 0)
        Continue:'$ISOBJECT(case)
        Set team = ##class(Shutter.Util.EscalationDraft).Team(case)
        Set c = {"id": (case.%Id()), "caseId": (case.CaseId), "state": (case.State), "disposition": (case.Disposition), "openedAt": (case.OpenedAt), "receiver": (case.Receiver), "failureKind": (case.FailureKind), "patientId": (case.PatientId), "patientIdAuthority": (case.PatientIdAuthority), "encounterId": (case.EncounterId)}
        Set c.teamAddress = ##class(Shutter.Util.Json).Str(team, "mailbox"), c.teamName = ##class(Shutter.Util.Json).Str(team, "name")
        Set c.reminded = ##class(Shutter.Store.CaseReminder).Thresholds(case.%Id())
        Do out.%Push(c)
    }
    Quit out
}

/// The first letter of the first name (PID-5.2) of the message the case came from, read for the digest and not kept; ""
/// when the message has gone or it has none. Asked only when the site's setting shows it.
ClassMethod Initial(caseRowId As %String) As %String
{
    Set out = ""
    Try {
        Set case = ##class(Shutter.Store.Case).%OpenId(caseRowId, 0)
        Quit:'$ISOBJECT(case)
        Set header = ##class(Ens.MessageHeader).%OpenId(case.SourceHeaderId)
        Quit:'$ISOBJECT(header)
        Set msg = ##class(EnsLib.HL7.Message).%OpenId(header.MessageBodyId)
        Quit:'$ISOBJECT(msg)
        Set out = $EXTRACT(##class(Shutter.Util.OperationKey).Value(msg, "PID", "5.2"), 1)
    } Catch ex {
        Set out = ""
    }
    Quit out
}

/// Build one digest, store it and hand it to the operation. Returns 1 when it was queued. A failure is the digest's own.
ClassMethod Send(digest As %DynamicObject, settings As %DynamicObject, now As %String) As %Boolean
{
    Set items = [], it = digest.items.%GetIterator()
    While it.%GetNext(, .item) {
        If settings."patient_detail" = "identifiers_initial" Set item.case.initial = ..Initial(item.case.id)
        Do items.%Push({"id": (item.case.id), "caseId": (item.case.caseId), "threshold": (item.threshold), "hours": (settings.%Get(item.threshold _ "_hours"))})
    }
    Do ##class(Shutter.Util.CaseReminder).Compose(digest, settings, .subject, .body)
    Set sc = ##class(Shutter.Store.ReminderDigest).Create(digest.to, subject, body, items, now, .row)
    If $$$ISERR(sc) Do ..Note("A reminder to " _ digest.to _ " could not be stored: " _ $SYSTEM.Status.GetErrorText(sc)) Quit 0
    Set msg = ##class(Shutter.Msg.ReminderSend).%New()
    Set msg.DigestId = row.%Id()
    Set sc = ##class(Ens.Director).CreateBusinessService("Shutter API", .service)
    If $$$ISOK(sc) && $ISOBJECT(service) {
        Set service.Target = "Escalation Mail", service.Async = 1
        Set sc = service.ProcessInput(msg)
    } ElseIf $$$ISOK(sc) {
        Set sc = $$$ERROR($$$GeneralError, "The API service is not running")
    }
    If $$$ISOK(sc) Quit 1
    Do row.MarkFailed($SYSTEM.Status.GetErrorText(sc))
    Quit 0
}

/// The Doctor's report: on or off, what it would use, its warnings, and its last run, send and error.
ClassMethod Status(taskId As %String) As %DynamicObject
{
    Set profile = ##class(Shutter.Store.SiteProfile).Current()
    Set settings = ##class(Shutter.Util.CaseReminder).Settings(profile)
    Set r = {}
    Do r.%Set("enabled", settings.enabled, "boolean")
    Quit:'settings.enabled r
    Set teams = ##class(Shutter.Store.SiteProfile).Teams().%Size()
    Set task = (taskId '= "") || ''$GET(^Shutter.Config("reminderTask"))
    Set r.warnings = ##class(Shutter.Util.CaseReminder).Warnings(settings, ..MailServer(), ##class(Shutter.Store.SiteProfile).AllowedDomains(), teams, task)
    Set r."patient_detail" = settings."patient_detail", r.zone = settings.zone
    Set r."last_run" = $GET(^Shutter.Reminder("last_run"))
    Set e = $GET(^Shutter.Reminder("last_error"))
    If e '= "" Set r."last_error" = $LIST(e, 1) _ ": " _ $LIST(e, 2)
    Quit r
}

}
