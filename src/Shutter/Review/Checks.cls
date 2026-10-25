/// The production review's checks (docs/CONTRACTS.md, section 13): one row per code with its severity, its evidence
/// confidence, the setting it reads and the words every finding of that code carries (why it matters, the safer value,
/// the action a person takes), so that a check's words live in one place. Shutter.Review.Sweep decides when a check
/// fires and what it found; this class says what the finding means. The texts may use {item}, {setting}, {found} and
/// {count}, filled per finding. Severity (how bad the hazard is) and confidence (how sure the evidence is) are kept
/// apart: a configuration read from the production is "confirmed", a pattern the configuration is consistent with is
/// "consistent", and a count of errors or failed messages is "indicative" until a person has read them.
Class Shutter.Review.Checks Extends %RegisteredObject
{

/// The severity tiers in rank order.
Parameter TIERS = "high,medium,low,info";

/// The codes whose findings move with counts, ids and times rather than with the configuration. They stay out of the
/// configuration fingerprint (Shutter.Review.Sweep.Fingerprint), so the fingerprint, the record key and the annotations
/// bind to the configuration alone.
Parameter VOLATILE = "ERRORS_GROUPED,RULE_ERRORS,MESSAGE_ERRORS,SUSPENDED_MESSAGES,QUEUE_BACKLOG,NAMESPACE_UNREADABLE";

/// What an HL7 operation does with reply codes when ReplyCodeActions is left empty, as InterSystems documents it (the
/// class's InitialExpression is "" and the behaviour is built in; not read on an instance): E and R replies are
/// suspended, A replies complete.
Parameter DOCUMENTEDREPLYCODEACTIONS = ":?R=RF,:?E=S,:~=S,:?A=C,:*=S,:I?=W,:T?=C";

/// The rules table as a dynamic object keyed by code.
ClassMethod Rules() As %DynamicObject
{
    Set xdata = ##class(%Dictionary.CompiledXData).%OpenId($CLASSNAME() _ "||Rules", 0)
    If '$ISOBJECT(xdata) Quit {}
    Quit ##class(%DynamicObject).%FromJSON(xdata.Data)
}

/// One rule, or "" for a code the table does not know.
ClassMethod Rule(code As %String) As %DynamicObject
{
    Set rules = ..Rules()
    If rules.%GetTypeOf(code) '= "object" Quit ""
    Quit rules.%Get(code)
}

/// The codes, in the table's order.
ClassMethod Codes() As %DynamicArray
{
    Set out = []
    Set iter = ..Rules().%GetIterator()
    While iter.%GetNext(.code, .rule) {
        Do out.%Push(code)
    }
    Quit out
}

/// A severity's tier, 0 for high to 3 for info; a severity the table does not know ranks last.
ClassMethod Tier(severity As %String) As %Integer
{
    Set i = $LISTFIND($LISTFROMSTRING(..#TIERS), $ZCONVERT(severity, "L"))
    If i = 0 Quit $LENGTH(..#TIERS, ",") - 1
    Quit i - 1
}

/// Whether a code's findings move with counts, ids and times (and so stay out of the configuration fingerprint).
ClassMethod IsVolatile(code As %String) As %Boolean
{
    Quit ''$LISTFIND($LISTFROMSTRING(..#VOLATILE), code)
}

/// A finding of a code in the shape every finding has: identity (code, item, class, setting), observation (found, its
/// source, severity and confidence), the check's words, empty case and evidence blocks the sweep fills in, and the
/// workflow fields (status new, no annotation, no rank, no explanation). The setting defaults to the rule's. The
/// severity may be raised or lowered afterwards (a queue backlog above a thousand is high).
ClassMethod Finding(code As %String, item As %String = "", itemClass As %String = "", setting As %String = "", found As %String = "", source As %String = "", count As %Integer = 0) As %DynamicObject
{
    Set rule = ..Rule(code)
    Set f = {}
    Set f.id = ""
    Set f.code = code
    Set f.severity = ##class(Shutter.Util.Json).Str(rule, "severity", "info")
    Set f.confidence = ##class(Shutter.Util.Json).Str(rule, "confidence", "indicative")
    Set f.item = "" _ item
    Set f.itemClass = "" _ itemClass
    Set f.setting = "" _ $SELECT(setting '= "": setting, 1: ##class(Shutter.Util.Json).Str(rule, "setting"))
    Set f.found = "" _ found
    Set f.source = source
    Set values = {}
    Set values.item = item
    Set values.setting = f.setting
    Set values.found = found
    Set values.count = count
    Set f.suggested = ..Fill(##class(Shutter.Util.Json).Str(rule, "suggested"), values)
    Set f.why = ..Fill(##class(Shutter.Util.Json).Str(rule, "why"), values)
    Set f.action = ..Fill(##class(Shutter.Util.Json).Str(rule, "action"), values)
    Set f.cases = {"count": 0, "unique": 0, "latest": []}
    Set f.evidence = {"count": (+count), "latestHeaderId": "", "latestLogId": "", "latestRuleLogId": "", "latestAt": "", "example": ""}
    Set f.status = "new"
    Set f.annotationId = ""
    Do f.%Set("rank", "", "null")
    Set f.explanation = ""
    Quit f
}

/// A text with its placeholders filled: {item}, {setting}, {found} and {count}.
ClassMethod Fill(text As %String, values As %DynamicObject) As %String
{
    If text = "" Quit ""
    Set iter = values.%GetIterator()
    While iter.%GetNext(.key, .value) {
        Set text = $REPLACE(text, "{" _ key _ "}", value)
    }
    Quit text
}

/// The table. subject says what a finding of the code is about (an item, the production, the namespace or the purge
/// task); setting is the setting read, "" when the finding is not about one; the texts are the finding's words.
XData Rules [ MimeType = application/json ]
{
{
 "RETRY_FOREVER": {"severity": "high", "confidence": "confirmed", "setting": "FailureTimeout", "subject": "an operation or process",
   "why": "FailureTimeout -1 retries for ever: a message that cannot be delivered never fails forward, so no case opens, the queue behind it waits and the failure stays invisible until someone looks at the queue.",
   "suggested": "A finite FailureTimeout agreed with the receiver (a retry budget in seconds, with RetryInterval between tries), so that a failed delivery reaches Shutter as a case. Where indefinite retry is intended, an independent alert on the queue's age (QueueWaitAlert) must watch it, and the intention belongs in an annotation here with an owner.",
   "action": "Set FailureTimeout on {item} in the Management Portal (Interoperability, Configure, Production, the item's Settings) to the agreed budget, then confirm that a failed delivery opens a case."},
 "GIVES_UP_EARLY": {"severity": "medium", "confidence": "confirmed", "setting": "FailureTimeout", "subject": "an operation with retries",
   "why": "{found}: the operation fails the message before a second try can happen, so a receiver's brief outage fails every message at once instead of riding it out.",
   "suggested": "Either 0 (fail at once by design, as Shutter's own connectors do, so that every failure opens a case) or at least twice RetryInterval, so a transient refusal gets a second try.",
   "action": "Decide whether {item} should retry at all; set FailureTimeout to 0, or to a budget of several RetryIntervals."},
 "REPLY_CODES_LENIENT": {"severity": "high", "confidence": "confirmed", "setting": "ReplyCodeActions", "subject": "an HL7 operation",
   "why": "{found}: a negative application acknowledgement (AE or AR) is treated as a completed delivery, so the receiver's rejection disappears from failure handling and the message looks sent while the receiver did not apply it.",
   "suggested": "An explicit map agreed with the receiver: accepted replies complete (:?A=C), transient failures retry within a bounded budget (:?R=RF), permanent and unknown replies reach a visible queue or fail forward (:?E=F, or S with alerting on the item). AE or AR mapped to C or W needs a scoped interface agreement, an owner and independent discrepancy monitoring.",
   "action": "Confirm the receiver's reply contract, then change ReplyCodeActions on {item}. A receiver that always answers AE although it commits is a written exception: record it as an annotation here, with an owner and a review date."},
 "REPLY_CODES_SUSPEND_UNWATCHED": {"severity": "medium", "confidence": "consistent", "setting": "ReplyCodeActions", "subject": "an HL7 operation",
   "why": "{found}: E and R replies suspend the message, which is safe only while someone watches the suspended messages, and AlertOnError is off on this item, so a suspension raises no alert.",
   "suggested": "Keep the suspension and switch on AlertOnError with an AlertGroups value that reaches a staffed owner, or map the codes to F so that the failure fails forward into a case.",
   "action": "Switch on alerting for {item} or change its ReplyCodeActions, and check the suspended messages page for anything already waiting."},
 "FRAMING_MISMATCH": {"severity": "high", "confidence": "confirmed", "setting": "Framing", "subject": "an HL7 TCP operation",
   "why": "{found}: the operation and the service on the same address and port frame HL7 differently, so the connection opens but no complete message or acknowledgement is recognised, and the feed stalls with the connection up.",
   "suggested": "The same framing on both sides of the connection (MLLP for an MLLP peer); Flexible on the receiving side accepts either.",
   "action": "Confirm the peer's framing from an authorised capture, then set Framing on {item} and on the service to match."},
 "NO_ALERT_CONSUMER": {"severity": "medium", "confidence": "confirmed", "setting": "", "subject": "the production",
   "why": "The production has no Ens.Alert item: an alert raised by any item (AlertOnError, a queue alert, an inactivity alert) has nowhere to go, so an error writes an alert to the event log that nobody receives.",
   "suggested": "An Ens.Alert business process, or the site's alert operation, routing alerts to a staffed owner by email or a ticket; or a documented external monitor that reads the event log's alerts.",
   "action": "Add an alert consumer to the production (Add Process, Ens.Alert) and switch on AlertOnError on the feed-path items; send one deliberate alert to prove the path."},
 "ALERTING_OFF": {"severity": "medium", "confidence": "confirmed", "setting": "AlertOnError", "subject": "the production's feed-path items",
   "why": "Items on the clinical feed raise no alert on error, or name no alert group: {found}. A failure on them reaches the event log and waits for someone to read it.",
   "suggested": "AlertOnError 1 on every item on the feed (the service, the delivering process and the connector), with AlertGroups naming the team that owns the interface.",
   "action": "Switch on AlertOnError and set AlertGroups on the items listed; confirm that one alert reaches the owner."},
 "QUEUE_ALERTS_OFF": {"severity": "low", "confidence": "confirmed", "setting": "QueueCountAlert", "subject": "the production's feed-path operations",
   "why": "QueueCountAlert and QueueWaitAlert are 0 on {found}: a growing backlog or an old message in the queue raises nothing, so patients' locations can lag while throughput looks healthy.",
   "suggested": "Thresholds agreed for the interface (a count above the normal burst, a wait of a few minutes) with an owner for the backlog.",
   "action": "Set QueueCountAlert and QueueWaitAlert on the operations listed, then review the thresholds after a week against the real queue."},
 "FEED_SILENCE_UNWATCHED": {"severity": "low", "confidence": "consistent", "setting": "InactivityTimeout", "subject": "the feed's service",
   "why": "InactivityTimeout 0 on {item}: a feed that falls silent (the sender stopped, the folder or port no longer reached) is never noticed by the production itself, and the silence is consistent with messages going nowhere.",
   "suggested": "An InactivityTimeout longer than the feed's normal quiet period, in seconds, with AlertOnError on; or a documented external check on the feed's arrival rate.",
   "action": "Set InactivityTimeout on {item} to the agreed silence. Scheduled quiet periods (nights, weekends) belong on the item's Schedule, or in an annotation here."},
 "ARCHIVE_IO_ON": {"severity": "low", "confidence": "confirmed", "setting": "ArchiveIO", "subject": "an item",
   "why": "ArchiveIO is on for {item}: the raw inbound and outbound bytes are kept in the event log, with the patient data they carry, outside what the message purge is usually set to cover.",
   "suggested": "Off, unless a diagnosis needs it and then for a bounded time; raw I/O is not the message archive.",
   "action": "Switch ArchiveIO off on {item} once the diagnosis is done, and check what the purge task covers (TypesToPurge) and who may read the event log."},
 "POOL_SIZE_REORDERS": {"severity": "high", "confidence": "confirmed", "setting": "PoolSize", "subject": "an HL7 operation or the delivering process",
   "why": "PoolSize {found} on an ordered feed: several jobs complete messages in parallel, so an admission, a transfer or a discharge can overtake the one before it and a stale event can overwrite a later state at the receiver.",
   "suggested": "PoolSize 1 for an HL7 operation and for the process that delivers an ordered feed; a larger pool only with a proven ordering guarantee (a partition by patient or by sender the receiver agreed to).",
   "action": "Set PoolSize to 1 on {item}. If throughput needs more, partition the feed with the receiver's agreement rather than widen the pool."},
 "ITEM_DISABLED": {"severity": "high", "confidence": "confirmed", "setting": "Enabled", "subject": "a feed-path item",
   "why": "{item} is disabled: messages for it queue up or route nowhere, so the feed is silently stopped at this point.",
   "suggested": "Enabled, or removed from the production together with its route; a disabled item on a live feed is not a safe resting state.",
   "action": "Enable {item} in the Management Portal, or confirm that the feed is stopped on purpose and record that here with an owner and a date."},
 "PURGE_MISSING": {"severity": "high", "confidence": "confirmed", "setting": "", "subject": "the namespace",
   "why": "No message purge task (Ens.Util.Tasks.Purge) runs for this namespace: messages, the event log and traces grow until the database fills, and when it does the production stops.",
   "suggested": "A scheduled Ens.Util.Tasks.Purge for the namespace, keeping the days the incident and audit process needs (Shutter's own install makes one of 90 days, bodies too, sessions kept whole).",
   "action": "Create the task in the Task Manager (System Operation, Task Manager, New Task, class Ens.Util.Tasks.Purge) for this namespace; for Shutter's own namespace, Shutter.Setup.EnsureRetentionTasks makes it."},
 "PURGE_SUSPENDED": {"severity": "high", "confidence": "confirmed", "setting": "Suspended", "subject": "the purge task",
   "why": "The message purge task is suspended: nothing is purged while it stays so, and the database grows as if there were no task.",
   "suggested": "The task resumed once the reason for the suspension is settled.",
   "action": "Resume the task in the Task Manager and check that its next run finished."},
 "PURGE_SHORT": {"severity": "medium", "confidence": "confirmed", "setting": "NumberOfDaysToKeep", "subject": "the purge task",
   "why": "The purge keeps {found} days: an incident found later than that has no messages left to investigate, and Shutter's cases lose the evidence they point to.",
   "suggested": "At least 7 days, and the retention the incident process needs (30 to 90 days is usual).",
   "action": "Raise NumberOfDaysToKeep on the purge task to the agreed retention."},
 "PURGE_LONG": {"severity": "low", "confidence": "confirmed", "setting": "NumberOfDaysToKeep", "subject": "the purge task",
   "why": "The purge keeps {found} days: a long retention keeps patient data for that long and fills storage; check that it is a deliberate policy.",
   "suggested": "The retention the site's record-keeping policy names, with storage sized for it.",
   "action": "Confirm the retention with the information governance owner, or lower NumberOfDaysToKeep."},
 "BODIES_KEPT": {"severity": "low", "confidence": "confirmed", "setting": "BodiesToo", "subject": "the purge task",
   "why": "The purge deletes message headers but keeps the bodies (BodiesToo 0): the HL7 messages themselves, with their patient data, stay after their headers are gone, where nothing finds them.",
   "suggested": "BodiesToo 1, so that bodies go with their headers.",
   "action": "Set BodiesToo on the purge task."},
 "SUSPENDED_MESSAGES": {"severity": "high", "confidence": "confirmed", "setting": "", "subject": "an item",
   "why": "{count} message(s) to {item} are suspended in the window: each is a delivery that stopped and waits for a person to resend or discard it, and until then the receiver does not have it.",
   "suggested": "Suspended messages reviewed daily; each resent or discarded with the receiver's current state in view, since a resend of a stale event can overwrite a later one.",
   "action": "Open the suspended messages for {item}, decide each one, and find what suspended them (ReplyCodeActions, a permanent error)."},
 "QUEUE_BACKLOG": {"severity": "medium", "confidence": "confirmed", "setting": "QueueCountAlert", "subject": "an item",
   "why": "{count} message(s) wait in the queue of {item}, above the threshold ({found}): the item or its receiver is behind or stopped, and patients' current location lags by the age of the queue.",
   "suggested": "A queue near zero between bursts, and the alert threshold set so that this depth would have alerted.",
   "action": "Check the status of {item} and of its receiver, then the age of the oldest message; set QueueCountAlert and QueueWaitAlert so that a backlog alerts."},
 "ERRORS_GROUPED": {"severity": "medium", "confidence": "indicative", "setting": "", "subject": "an item and an error signature",
   "why": "{count} error(s) with the signature {found} in the window, logged by {item}. The count is consistent with repeated failures of the same kind; the signature is the event log's text before its first colon, and the latest text is kept as the example.",
   "suggested": "Each distinct signature understood, and either fixed or recorded here as expected.",
   "action": "Open the event log filtered on {item} and the latest entry of this signature; compare the count with the cases opened in the same window."},
 "RULE_ERRORS": {"severity": "medium", "confidence": "indicative", "setting": "", "subject": "a rule or transform",
   "why": "{count} rule or transform error(s) in the window for {item}: messages the routing or the transformation could not handle, which reached no target.",
   "suggested": "The rule or transform fixed, and the failed messages resent after review.",
   "action": "Open the rule log for {item} and the latest error; check whether the messages reached their target."},
 "MESSAGE_ERRORS": {"severity": "medium", "confidence": "indicative", "setting": "", "subject": "an item (target and source)",
   "why": "{count} message(s) to {item} ended in an error status in the window ({found}). The count is consistent with deliveries that failed; the error text is in the event log of the same session.",
   "suggested": "Every failed delivery accounted for: a case, a resend or a discard with a reason.",
   "action": "Compare the count with the cases opened for {item} in the same window; a failed message without a case needs a person's decision."},
 "NAMESPACE_UNREADABLE": {"severity": "info", "confidence": "confirmed", "setting": "", "subject": "the namespace",
   "why": "The namespace could not be read ({found}): the review has nothing to say about this production.",
   "suggested": "A namespace that exists, with the production defined in it, that this instance's production jobs may read.",
   "action": "Check the namespace name, that the production is defined there and that the production jobs have read access to its databases."}
}
}

}
