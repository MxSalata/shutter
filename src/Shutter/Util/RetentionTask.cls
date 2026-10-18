/// Shutter's housekeeping, run daily by the task "Shutter retention" the installer schedules (the message store's
/// own purge is the standard Ens.Util.Tasks.Purge task "Shutter message purge", scheduled beside it): idempotency
/// keys older than a day go; closed cases older than the retention go only when PurgeClosedCases is on, because the
/// record of what was decided is the product.
Class Shutter.Util.RetentionTask Extends %SYS.Task.Definition
{

Parameter TaskName = "Shutter retention";

/// Closed cases older than this many days are purged when PurgeClosedCases is on.
Property RetentionDays As %Integer [ InitialExpression = 30 ];

/// Off by default: a closed case, its evidence, plans, approvals, attempts and verifications are the record.
Property PurgeClosedCases As %Boolean [ InitialExpression = 0 ];

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
        Set ^Shutter.Retention("last") = $LISTBUILD(##class(Shutter.Util.Time).NowUTC(), keys, cases)
    } Catch ex {
        Set sc = ex.AsStatus()
        Set ^Shutter.Retention("last_error") = $LISTBUILD(##class(Shutter.Util.Time).NowUTC(), $SYSTEM.Status.GetErrorText(sc))
    }
    Quit sc
}

}
