/// Shutter's housekeeping, run daily by the task "Shutter retention" the installer schedules (the message store's
/// own purge is the standard Ens.Util.Tasks.Purge task "Shutter message purge", scheduled beside it): idempotency
/// keys older than a day go; the text of each escalation email goes EscalationDays days after its case closed, since
/// it is the one copy of the patient's identifiers Shutter keeps outside the message store; closed cases older than the
/// retention go only when PurgeClosedCases is on, because the record of what was decided is the product.
Class Shutter.Util.RetentionTask Extends %SYS.Task.Definition
{

Parameter TaskName = "Shutter retention";

/// Closed cases older than this many days are purged when PurgeClosedCases is on.
Property RetentionDays As %Integer [ InitialExpression = 30 ];

/// Off by default: a closed case, its evidence, plans, approvals, attempts and verifications are the record.
Property PurgeClosedCases As %Boolean [ InitialExpression = 0 ];

/// The email text of an escalation (the hospital number, the NHS number, the date of birth) goes this many days after
/// its case closed, the .eml file with it; the row stays with its digest, recipients, who drafted and sent it, and when.
/// The installer sets it from SHUTTER_ESCALATION_DAYS, else the message days (90); 0 keeps the texts.
Property EscalationDays As %Integer [ InitialExpression = 90 ];

Method OnTask() As %Status
{
    Set sc = $$$OK
    Try {
        Set keys = ##class(Shutter.Store.Idempotency).Purge()
        Set cases = 0
        If ..PurgeClosedCases {
            Set cutoff = ##class(Shutter.Util.Time).FromNow(-86400 * $SELECT(..RetentionDays < 1: 1, 1: ..RetentionDays))
            Set cases = ##class(Shutter.Store.Case).PurgeClosedBefore(cutoff)
        }
        Set escalations = 0
        If ..EscalationDays > 0 {
            Set escalations = ##class(Shutter.Store.Escalation).PurgeTextBefore(##class(Shutter.Util.Time).FromNow(-86400 * ..EscalationDays), ..EscalationDays)
        }
        Set ^Shutter.Retention("last") = $LISTBUILD(##class(Shutter.Util.Time).NowUTC(), keys, cases, escalations)
    } Catch ex {
        Set sc = ex.AsStatus()
        Set ^Shutter.Retention("last_error") = $LISTBUILD(##class(Shutter.Util.Time).NowUTC(), $SYSTEM.Status.GetErrorText(sc))
    }
    Quit sc
}

}
