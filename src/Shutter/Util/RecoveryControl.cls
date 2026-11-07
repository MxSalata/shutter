/// Shadow mode and the recovery stop (CONTRACTS 17). Two different things: the site profile's recovery.mode says whether
/// this deployment attempts recovery at all, and anything but an explicit "enabled" means shadow; the stop is a latch on
/// the control row that a person sets in an emergency, which outlives a restart. Neither reaches the hospital's ordinary
/// feed, another system writing to a receiver, or a read.
/// The promise is exact: no recovery call is admitted after a stop commits. A call admitted before it may still reach the
/// receiver, and is listed as outstanding. Admit and Stop share one short lock, never held across a network call.
Class Shutter.Util.RecoveryControl Extends %RegisteredObject
{

/// How long an admission or a stop waits for the control's lock, in seconds. An admission that gets no lock is refused.
Parameter LOCKWAIT = 5;

/// How many outstanding permits a report or an event names.
Parameter LISTED = 50;

// ---- the mode ----

/// The mode in force: "enabled" only when the stored profile says exactly that.
ClassMethod Mode() As %String
{
    Try {
        Set mode = ..ModeOfProfile(##class(Shutter.Store.SiteProfile).Current())
    } Catch ex {
        Set mode = "shadow"
    }
    Quit mode
}

ClassMethod ModeOfProfile(profile As %DynamicObject) As %String
{
    If '$ISOBJECT(profile) Quit "shadow"
    Set recovery = profile.%Get("recovery")
    If '$ISOBJECT(recovery) Quit "shadow"
    Quit $SELECT(recovery.%Get("mode") = "enabled": "enabled", 1: "shadow")
}

/// The mode a profile's stored text says.
ClassMethod ModeOfJson(json As %String) As %String
{
    If $GET(json) = "" Quit "shadow"
    Set p = ##class(Shutter.Util.Json).Parse(json, .sc)
    Quit ..ModeOfProfile($SELECT($ISOBJECT(p): p, 1: ""))
}

/// Whether an email a person sent goes out: in shadow mode it does not, unless the site's profile says it may.
ClassMethod MailSuppressed() As %Boolean
{
    If ..Mode() = "enabled" Quit 0
    Try {
        Set n = ##class(Shutter.Store.SiteProfile).Current().%Get("notifications")
        Set allowed = $ISOBJECT(n) && (n.%Get("shadow_delivery") = "enabled")
    } Catch ex {
        Set allowed = 0
    }
    Quit 'allowed
}

// ---- the control row ----

/// The control row, made when there is none. A row that cannot be read throws, and whoever asked refuses recovery.
ClassMethod Control() As Shutter.Store.RecoveryControl
{
    If ##class(Shutter.Store.RecoveryControl).NameIdxExists("current", .id) {
        Set row = ##class(Shutter.Store.RecoveryControl).%OpenId(id, , .sc)
        If '$ISOBJECT(row) $$$ThrowStatus($SELECT($$$ISERR(sc): sc, 1: $$$ERROR($$$GeneralError, "The recovery control row cannot be read")))
        If (+row.Generation < 1) || (row.StopLatched '= (''row.StopLatched)) $$$ThrowStatus($$$ERROR($$$GeneralError, "The recovery control row is not valid"))
        Quit row
    }
    Set row = ##class(Shutter.Store.RecoveryControl).%New()
    Set row.DeploymentId = $SYSTEM.Util.CreateGUID(), row.Generation = 1, row.PlanFloor = ..NewestPlan()
    Set row.ReportKey = $SYSTEM.Encryption.Base64Encode($SYSTEM.Encryption.GenCryptRand(32))
    Set row.LastChangedAt = ##class(Shutter.Util.Time).NowUTC(), row.LastChangedBy = "install"
    $$$ThrowOnError(row.%Save())
    Quit row
}

/// Made at install and at each production start, so plans from before this feature stay under the floor and the first
/// plan after it is above it.
ClassMethod Ensure() As %Status
{
    Set sc = $$$OK
    Try {
        LOCK +^Shutter.RecoveryControl:..#LOCKWAIT
        If $TEST { Do ..Control() LOCK -^Shutter.RecoveryControl }
    } Catch ex {
        Set sc = ex.AsStatus()
        LOCK -^Shutter.RecoveryControl
    }
    Quit sc
}

ClassMethod NewestPlan() As %Integer [ Private ]
{
    Set newest = 0
    &sql(SELECT MAX(ID) INTO :newest FROM Shutter_Store.Plan)
    Quit $SELECT(SQLCODE = 0: +$GET(newest), 1: 0)
}

// ---- admission ----

/// Why a recovery call could not go now, or "": the check before sending a person or a case towards one. It takes no
/// permit: Admit, at the connector, is the one that counts.
ClassMethod Refusal(Output code As %String) As %String
{
    Set code = ""
    Try {
        Set text = ..RefusalOf(..Control(), .code)
    } Catch ex {
        Set code = "control_unreadable", text = "The recovery control could not be read, so nothing is sent"
    }
    Quit text
}

ClassMethod RefusalOf(control As Shutter.Store.RecoveryControl, Output code As %String) As %String [ Private ]
{
    Set code = ""
    If control.StopLatched {
        Set code = "recovery_stopped"
        Quit "Shutter recovery was stopped by " _ control.StoppedBy _ " at " _ control.StoppedAt
    }
    If ..Mode() '= "enabled" {
        Set code = "recovery_shadow"
        Quit "Shadow mode: Shutter investigates, but sends no recovery write, rehearsal or resend preview"
    }
    Quit ""
}

/// Why a person can't approve this case's plan now, or "". The words hold at the next step: a plan a stop, a clear or a mode
/// change has passed stays void, at the connector too, and a waiting case can be reinvestigated only once it is rejected.
ClassMethod CaseApprovalRefusal(plan As Shutter.Store.Plan, Output code As %String) As %String
{
    Set code = "", text = ""
    Try {
        Set control = ..Control()
        Do ..RefusalOf(control, .code)
        If code = "recovery_stopped" {
            Set text = "Shutter recovery is stopped, so this plan can't be approved. Clearing the stop will not release it: reject it and reinvestigate."
        } ElseIf code = "recovery_shadow" {
            Set text = "Shadow mode: recovery is off, so this plan can't be approved. Enabling recovery will not release it: reject it and reinvestigate."
        } ElseIf +plan.%Id() <= +control.PlanFloor {
            Set code = "plan_predates_control", text = "This plan was made before recovery was last stopped, cleared or changed, so it will not be sent: reject it and reinvestigate."
        }
    } Catch ex {
        Set code = "control_unreadable", text = "The recovery control could not be read, so this plan can't be approved."
    }
    Quit text
}

/// Why a person can't approve an incident now, or "". An incident holds no plan row: each item gathers fresh evidence and
/// makes its plan when it is released, under the floor's check like any other, so it only has to wait.
ClassMethod IncidentApprovalRefusal(Output code As %String) As %String
{
    Set text = ..Refusal(.code)
    If code = "recovery_stopped" Quit "Shutter recovery is stopped, so this incident can't be approved until the stop is cleared. Its items take fresh evidence when they are released."
    If code = "recovery_shadow" Quit "Shadow mode: recovery is off, so this incident can't be approved until recovery is enabled. Its items take fresh evidence when they are released."
    Quit text
}

/// The connector's check, immediately before its POST: 1 to send, with permit set when the call is a recovery call, or 0
/// with the response filled in as refused. The ordinary feed passes with no permit, reading nothing but its own message and
/// its sender, so nothing that happens to the control can reach it. Any other kind of call that isn't a rehearsal or a
/// recovery write is refused. source is the Ens item that sent the message.
ClassMethod AdmitWard(request As Shutter.Msg.WardOperation, source As %String, receiver As %String, body As %DynamicObject, response As Shutter.Msg.WardResult, Output permit As Shutter.Store.DispatchPermit) As %Boolean
{
    Set permit = ""
    If request.Purpose = "normal" {
        If ..IsOriginalFeed(request, source) Quit 1
        Set code = "not_original_feed", text = "A message marked as ordinary traffic came from " _ $SELECT(source = "": "no known item", 1: source) _ ", which is not a registered feed"
    } Else {
        Set digest = ##class(Shutter.Util.Digest).SHA256Hex(body.%ToJSON())
        If ..Admit(request.Purpose, request.CaseId, receiver, request.OperationKey, digest, .permit, .code, .text) Quit 1
    }
    Set response.Outcome = "refused", response.ReasonCode = code, response.Error = "Not sent: " _ text
    Quit 0
}

/// Ordinary traffic is what the feed process sends: a message with a source header and no case, from an item of the feed's
/// class. The purpose alone is not enough, since it is the message's default.
ClassMethod IsOriginalFeed(request As Shutter.Msg.WardOperation, source As %String) As %Boolean
{
    If (request.Purpose '= "normal") || (request.CaseId '= "") || (request.SourceHeaderId = "") || ($GET(source) = "") Quit 0
    Set class = $GET(^Ens.Runtime("ConfigItem", source, "ClassName"))
    If class = "" Quit 0
    Quit (class = "Shutter.Process.ADTToWard") || (##class(%Dictionary.CompiledClass).%ExistsId(class) && $CLASSMETHOD(class, "%Extends", "Shutter.Process.ADTToWard"))
}

/// Admit one recovery call, atomically with any stop: the permit commits under the lock Stop takes, and the sender keeps
/// a lock of its own on the permit until the call ends. Returns 1 with the permit, or 0 with why. Anything that goes wrong
/// here refuses.
ClassMethod Admit(kind As %String, caseId As %String, receiver As %String, operationKey As %String, bodyDigest As %String, Output permit As Shutter.Store.DispatchPermit, Output code As %String, Output text As %String) As %Boolean
{
    Set permit = "", code = "", text = "", admitted = 0, locked = 0, tlevel = $TLEVEL
    Try {
        If '$LISTFIND($LISTBUILD("rehearsal", "recovery"), kind) {
            Set code = "unknown_action", text = "The action " _ $SELECT(kind = "": "(none)", 1: kind) _ " is not one the recovery control knows"
            Quit
        }
        LOCK +^Shutter.RecoveryControl:..#LOCKWAIT
        If '$TEST {
            Set code = "control_unavailable", text = "The recovery control is busy, so nothing is sent"
            Quit
        }
        Set locked = 1
        Do ..ReconcileLocked()
        Set control = ..Control()
        Set text = ..RefusalOf(control, .code)
        Quit:code'=""
        Set planId = ""
        If caseId '= "" {
            Set case = ##class(Shutter.Store.Case).ByCaseId(caseId)
            If $ISOBJECT(case) && $ISOBJECT(case.CurrentPlan) Set planId = case.CurrentPlan.%Id()
        }
        If kind = "recovery" {
            If planId = "" Set code = "plan_unbound", text = "The write names no current plan of a case" Quit
            If +planId <= +control.PlanFloor {
                Set code = "plan_predates_control", text = "The plan was made before recovery was last stopped, cleared or changed; reinvestigate for fresh evidence and a new plan"
                Quit
            }
        }
        Set token = $INCREMENT(^Shutter.Config("recoveryPermit"))
        LOCK +^Shutter.RecoveryPermit(token):0
        If '$TEST Set code = "control_unavailable", text = "The recovery permit could not be held, so nothing is sent" Quit
        Set row = ##class(Shutter.Store.DispatchPermit).%New()
        Set row.Token = token, row.ActionKind = kind, row.CaseId = caseId, row.PlanId = planId, row.OperationKey = operationKey
        Set row.Receiver = receiver, row.BodyDigest = bodyDigest, row.Generation = control.Generation, row.Job = $JOB
        Set row.AdmittedAt = ##class(Shutter.Util.Time).NowUTC()
        // In a transaction for the commit's journal flush: the record of the call is durable before the call.
        TSTART
        $$$ThrowOnError(row.%Save())
        TCOMMIT
        Set permit = row, admitted = 1
    } Catch ex {
        While $TLEVEL > tlevel { TROLLBACK 1 }
        Set admitted = 0, permit = ""
        Set code = "control_unreadable", text = "The recovery control could not be read, so nothing is sent"
    }
    If locked LOCK -^Shutter.RecoveryControl
    Quit admitted
}

/// The call has ended: its record takes the connector's outcome. An outcome of uncertain stays uncertain here too; it
/// never reads as not sent. The case's own read-back goes on as before.
ClassMethod Finish(permit As Shutter.Store.DispatchPermit, response As Shutter.Msg.WardResult)
{
    If '$ISOBJECT($GET(permit)) Quit
    Try {
        Set permit.Outcome = response.Outcome, permit.HttpStatus = response.HttpStatus
        Set permit.State = $SELECT(response.Outcome = "uncertain": "uncertain", 1: "answered")
        Set permit.EndedAt = ##class(Shutter.Util.Time).NowUTC()
        $$$ThrowOnError(permit.%Save())
    } Catch ex {
        // The row still says admitted: when this job's lock goes, it reads as uncertain, which is the safe way to be wrong.
        Do ##class(Ens.Util.Log).LogWarning($CLASSNAME(), "Finish", "The recovery permit " _ permit.Token _ " could not be finished: " _ ex.DisplayString())
    }
    LOCK -^Shutter.RecoveryPermit(permit.Token)
}

/// Under the control's lock: a permit still admitted whose sender no longer holds its lock was cut off, by a restart or a
/// lost job. It is uncertain, never retried, and recovery stops until a person has seen it. A permit of this job is its
/// own call in progress.
ClassMethod ReconcileLocked() [ Private ]
{
    Set found = 0
    &sql(DECLARE PermitOpen CURSOR FOR SELECT ID, Token, Job INTO :id, :token, :job FROM Shutter_Store.DispatchPermit WHERE State = 'admitted')
    &sql(OPEN PermitOpen)
    Quit:SQLCODE'=0
    For {
        &sql(FETCH PermitOpen)
        Quit:SQLCODE'=0
        Continue:job=$JOB
        Set found = found + 1, open(found) = $LISTBUILD(id, token)
    }
    &sql(CLOSE PermitOpen)
    Set cut = 0
    For i = 1:1:found {
        Set token = $LIST(open(i), 2)
        LOCK +^Shutter.RecoveryPermit(token):0
        Continue:'$TEST
        LOCK -^Shutter.RecoveryPermit(token)
        Set row = ##class(Shutter.Store.DispatchPermit).%OpenId($LIST(open(i), 1))
        Continue:'$ISOBJECT(row)
        Set row.State = "uncertain", row.Orphaned = 1, row.EndedAt = ##class(Shutter.Util.Time).NowUTC()
        $$$ThrowOnError(row.%Save())
        Set cut = cut + 1
    }
    If cut {
        Set control = ..Control()
        If 'control.StopLatched Do ..Latch(control, "system", cut _ " recovery call(s) were left unanswered by a restart or a lost job, and may have been applied")
    }
}

/// Run the reconcile from outside an admission, as a read does.
ClassMethod Reconcile() As %Status
{
    Set sc = $$$OK
    Try {
        LOCK +^Shutter.RecoveryControl:..#LOCKWAIT
        If $TEST { Do ..ReconcileLocked() LOCK -^Shutter.RecoveryControl }
    } Catch ex {
        Set sc = ex.AsStatus()
        LOCK -^Shutter.RecoveryControl
    }
    Quit sc
}

// ---- the changes ----

/// Stop Shutter recovery. Idempotent: a stop already in force keeps its first author. Returns the control.
ClassMethod Stop(reason As %String, actor As %String, Output control As Shutter.Store.RecoveryControl) As %Status
{
    Set control = ""
    If $ZSTRIP($GET(reason), "<>W") = "" Quit $$$ERROR($$$GeneralError, "reason_required")
    LOCK +^Shutter.RecoveryControl:..#LOCKWAIT
    If '$TEST Quit $$$ERROR($$$GeneralError, "control_busy")
    Set sc = $$$OK
    Try {
        Do ..ReconcileLocked()
        Set control = ..Control()
        If 'control.StopLatched Do ..Latch(control, actor, reason)
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    LOCK -^Shutter.RecoveryControl
    Quit sc
}

ClassMethod Latch(control As Shutter.Store.RecoveryControl, actor As %String, reason As %String) [ Private ]
{
    Set old = control.Generation, now = ##class(Shutter.Util.Time).NowUTC()
    Set control.StopLatched = 1, control.StoppedAt = now, control.StoppedBy = actor, control.StopReason = $EXTRACT(reason, 1, 1000)
    Do ..Move(control, actor, now)
    Do ..Record("stop", actor, reason, old, control.Generation, "running", "stopped", control)
}

/// Clear the stop. It enables nothing: the mode stays as the profile says, and a plan made before this moment stays
/// refused. Clearing is how a person says they have seen the calls left uncertain; they stay uncertain.
ClassMethod ClearStop(reason As %String, expectedGeneration As %String, actor As %String, Output control As Shutter.Store.RecoveryControl) As %Status
{
    Set control = ""
    If $ZSTRIP($GET(reason), "<>W") = "" Quit $$$ERROR($$$GeneralError, "reason_required")
    LOCK +^Shutter.RecoveryControl:..#LOCKWAIT
    If '$TEST Quit $$$ERROR($$$GeneralError, "control_busy")
    Set sc = $$$OK
    Try {
        Do ..ReconcileLocked()
        Set control = ..Control()
        If ($GET(expectedGeneration) = "") || (+expectedGeneration '= control.Generation) {
            Set sc = $$$ERROR($$$GeneralError, "stale_generation")
        } ElseIf 'control.StopLatched {
            Set sc = $$$ERROR($$$GeneralError, "not_stopped")
        } Else {
            Set old = control.Generation, now = ##class(Shutter.Util.Time).NowUTC()
            Set control.StopLatched = 0, control.StoppedAt = "", control.StoppedBy = "", control.StopReason = ""
            Do ..Move(control, actor, now)
            Do ..Record("clear_stop", actor, reason, old, control.Generation, "stopped", "running", control)
            Do ..MarkReviewed(actor, now)
        }
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    LOCK -^Shutter.RecoveryControl
    Quit sc
}

/// The profile's mode changed (Shutter.Store.SiteProfile.Store): the same fence as a clear, so enabling recovery releases
/// no plan made before it. Called after the profile committed; a failure is logged, and the old floor stands.
ClassMethod NoteModeChange(oldMode As %String, newMode As %String, actor As %String)
{
    Try {
        LOCK +^Shutter.RecoveryControl:..#LOCKWAIT
        If '$TEST $$$ThrowStatus($$$ERROR($$$GeneralError, "control_busy"))
        Set control = ..Control(), old = control.Generation
        Do ..Move(control, actor, ##class(Shutter.Util.Time).NowUTC())
        Do ..Record("mode_change", actor, "The site profile's recovery.mode changed", old, control.Generation, oldMode, newMode, control)
    } Catch ex {
        Do ##class(Ens.Util.Log).LogWarning($CLASSNAME(), "NoteModeChange", "The recovery mode change was not recorded: " _ ex.DisplayString())
    }
    LOCK -^Shutter.RecoveryControl
}

/// A demo reset starts the demo afresh, as it does the receivers: a stop and its calls go with it. Only on a demo instance.
ClassMethod DemoReset(actor As %String) As %Status
{
    If ##class(Shutter.Store.SiteProfile).SiteInstall() Quit $$$OK
    LOCK +^Shutter.RecoveryControl:..#LOCKWAIT
    If '$TEST Quit $$$ERROR($$$GeneralError, "control_busy")
    Set sc = $$$OK
    Try {
        Do ..ReconcileLocked()
        Set control = ..Control()
        If control.StopLatched {
            Set old = control.Generation, now = ##class(Shutter.Util.Time).NowUTC()
            Set control.StopLatched = 0, control.StoppedAt = "", control.StoppedBy = "", control.StopReason = ""
            Do ..Move(control, actor, now)
            Do ..Record("demo_reset", actor, "The demo was reset", old, control.Generation, "stopped", "running", control)
            Do ..MarkReviewed(actor, now)
        }
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    LOCK -^Shutter.RecoveryControl
    Quit sc
}

/// The demo's store was emptied, which restarts the plan and case ids: the floor comes down with them, and the permits
/// and observations of the old ids go. A stop stays, for the reset to clear.
ClassMethod StoreEmptied() As %Status
{
    LOCK +^Shutter.RecoveryControl:..#LOCKWAIT
    If '$TEST Quit $$$ERROR($$$GeneralError, "control_busy")
    Set sc = $$$OK
    Try {
        $$$ThrowOnError(##class(Shutter.Store.DispatchPermit).%KillExtent())
        $$$ThrowOnError(##class(Shutter.Store.ShadowObservation).%KillExtent())
        Set control = ..Control()
        Set control.PlanFloor = 0
        $$$ThrowOnError(control.%Save())
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    LOCK -^Shutter.RecoveryControl
    Quit sc
}

ClassMethod Move(control As Shutter.Store.RecoveryControl, actor As %String, now As %String) [ Private ]
{
    Set control.Generation = control.Generation + 1, control.PlanFloor = ..NewestPlan()
    Set control.LastChangedAt = now, control.LastChangedBy = actor
}

/// The control row and its event, committed together.
ClassMethod Record(action As %String, actor As %String, reason As %String, oldGen As %Integer, newGen As %Integer, oldState As %String, newState As %String, control As Shutter.Store.RecoveryControl) [ Private ]
{
    Set event = ##class(Shutter.Store.RecoveryControlEvent).%New()
    Set event.At = control.LastChangedAt, event.Actor = actor, event.Action = action, event.Reason = $EXTRACT(reason, 1, 1000)
    Set event.OldGeneration = oldGen, event.NewGeneration = newGen, event.OldState = oldState, event.NewState = newState
    Set list = ..Outstanding(.count)
    Set event.OutstandingCount = count, ids = "", it = list.%GetIterator()
    While it.%GetNext(, .p) { Set ids = ids _ $SELECT(ids = "": "", 1: ",") _ p.id }
    Set event.OutstandingIds = $EXTRACT(ids, 1, 1000)
    TSTART
    Try {
        $$$ThrowOnError(control.%Save())
        $$$ThrowOnError(event.%Save())
        TCOMMIT
    } Catch ex {
        TROLLBACK 1
        Throw ex
    }
}

ClassMethod MarkReviewed(actor As %String, now As %String) [ Private ]
{
    &sql(UPDATE Shutter_Store.DispatchPermit SET ReviewedBy = :actor, ReviewedAt = :now WHERE Orphaned = 1 AND ReviewedAt IS NULL)
}

// ---- reading ----

/// The calls a person should know of: those admitted and perhaps still running, and those a restart left uncertain and
/// nobody has seen. A call whose answer was uncertain is the case's to read back, and is not listed.
ClassMethod Outstanding(Output count As %Integer) As %DynamicArray
{
    Set list = [], count = 0
    &sql(DECLARE PermitList CURSOR FOR SELECT ID, ActionKind, CaseId, Receiver, AdmittedAt, State INTO :id, :kind, :caseId, :receiver, :admittedAt, :state
        FROM Shutter_Store.DispatchPermit WHERE State = 'admitted' OR (Orphaned = 1 AND ReviewedAt IS NULL) ORDER BY ID)
    &sql(OPEN PermitList)
    Quit:SQLCODE'=0 list
    For {
        &sql(FETCH PermitList)
        Quit:SQLCODE'=0
        Set count = count + 1
        If list.%Size() < ..#LISTED Do list.%Push({"id": (id), "kind": (kind), "caseId": (caseId), "receiver": (receiver), "admittedAt": (admittedAt), "state": (state)})
    }
    &sql(CLOSE PermitList)
    Quit list
}

/// What the screen shows. A control that cannot be read says so, and reads as stopped.
ClassMethod Read() As %DynamicObject
{
    Set o = {}
    Set o.mode = ..Mode()
    Try {
        Do ..Reconcile()
        Set control = ..Control()
        Set o.generation = control.Generation, o.deploymentId = control.DeploymentId
        Do o.%Set("stopped", control.StopLatched, "boolean")
        Set o.stoppedAt = control.StoppedAt, o.stoppedBy = control.StoppedBy, o.stopReason = control.StopReason
        Set o.outstanding = ..Outstanding(.count)
        Set o.outstandingCount = count
        Do o.%Set("readable", 1, "boolean")
    } Catch ex {
        Do o.%Set("stopped", 1, "boolean")
        Do o.%Set("readable", 0, "boolean")
        Set o.outstanding = [], o.outstandingCount = 0
    }
    Set o.covers = "Rehearsals, recovery writes and blind-resend previews that Shutter itself starts."
    Set o.doesNotCover = "The hospital's ordinary feed and its retries, other systems or people writing to the receiver, Shutter's own records, and read-back of earlier attempts."
    Quit o
}

}
