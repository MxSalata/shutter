/// Shutter's housekeeping, run daily by the task "Shutter retention" the installer schedules (the message store's
/// own purge is the standard Ens.Util.Tasks.Purge task "Shutter message purge", scheduled beside it): idempotency
/// keys older than a day go; the text of each escalation email goes EscalationDays days after its case closed, since
/// it is the one copy of the patient's identifiers Shutter keeps outside the message store; closed cases older than the
/// retention go only when PurgeClosedCases is on, because the record of what was decided is the product; the questions
/// asked about a page from the Ask Shutter panel, their runs and tool calls go after the same retention days whatever
/// PurgeClosedCases says, since they hang off no case and decide nothing.
Class Shutter.Util.RetentionTask Extends %SYS.Task.Definition
{

Parameter TaskName = "Shutter retention";

/// Finished cases older than this many days are purged when PurgeClosedCases is on: resolved, handled by hand or abandoned,
/// never a blocked, escalated or failed case waiting for a person.
Property RetentionDays As %Integer [ InitialExpression = 30 ];

/// Off by default: a closed case, its evidence, plans, approvals, attempts and verifications are the record.
Property PurgeClosedCases As %Boolean [ InitialExpression = 0 ];

/// The email text of an escalation (the hospital number, the NHS number, the date of birth) goes this many days after
/// its case closed, the .eml file with it; the row stays with its digest, recipients, who drafted and sent it, and when.
/// The installer sets it from SHUTTER_ESCALATION_DAYS, else the message days (90); 0 keeps the texts.
Property EscalationDays As %Integer [ InitialExpression = 90 ];

/// The time before which a finished case, and a page question, is old enough to go: RetentionDays ago, a day at least.
Method Cutoff() As %String
{
    Quit ##class(Shutter.Util.Time).FromNow(-86400 * $SELECT(..RetentionDays < 1: 1, 1: ..RetentionDays))
}

Method OnTask() As %Status
{
    Set sc = $$$OK
    Try {
        Set keys = ##class(Shutter.Store.Idempotency).Purge()
        Set cases = 0, cutoff = ..Cutoff()
        If ..PurgeClosedCases {
            Set cases = ##class(Shutter.Store.Case).PurgeClosedBefore(cutoff)
        }
        Set pages = ##class(Shutter.Store.PageQuestion).PurgeBefore(cutoff)
        Set escalations = 0
        If ..EscalationDays > 0 {
            Set escalations = ##class(Shutter.Store.Escalation).PurgeTextBefore(##class(Shutter.Util.Time).FromNow(-86400 * ..EscalationDays), ..EscalationDays)
        }
        Set ^Shutter.Retention("last") = $LISTBUILD(##class(Shutter.Util.Time).NowUTC(), keys, cases, escalations, pages)
    } Catch ex {
        Set sc = ex.AsStatus()
        Set ^Shutter.Retention("last_error") = $LISTBUILD(##class(Shutter.Util.Time).NowUTC(), $SYSTEM.Status.GetErrorText(sc))
    }
    Quit sc
}

}
