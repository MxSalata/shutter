---
id: production-review-rules
version: 1.0
collection: review
applies_to: [iris-interoperability-production, hl7-v2-adt]
effective_from: 2026-10-25
---

# Production review rules: what each check means

Integration team rules for reading a Shutter production review. Version 1.0, in force from 25 October 2026. A review
is one read-only pass over one IRIS Interoperability production: deterministic checks over its items' effective
settings, its event log's errors and its messages' failures over a window, tied to the cases Shutter opened for it.
These rules say, for each check, what the finding means, why it matters, the safer value, when such a finding is
intended, and how a reviewer tells. They say nothing about any one production: the review does.

## PRR-1 How to read a finding

PRR-1.1. **Severity and confidence are kept apart.** Severity (high, medium, low, info) says how bad the problem is
when it is real. Confidence says how the finding was established: `confirmed` was read from the configuration or the
message store as a fact; `consistent` is a reading that fits the evidence but was not traced to a mechanism;
`indicative` is a count from the logs that points at something without saying what. A high-severity latent hazard with
no cases in the window stands: it has no linked evidence, not no risk.

PRR-1.2. **The effective value has a source.** A setting's value comes from one of three places, and the finding says
which: `item` (set on the item in the production definition), `default_setting` (a system default setting for the
production, item or class), `class_default` (the host or adapter class's initial value, which applies when nothing
else is set). A default is not wrong by itself; the finding says what the value does.

PRR-1.3. **Cases are evidence, not proof.** A finding's cases are the cases Shutter opened in the window whose
receiver or source route is the item. `count` counts cases, `unique` counts distinct cases (retries and reopened cases
do not inflate it), `latest` names the newest. The configuration is the one in force now, not the one at the time of
each case, so the right words are "the current configuration is consistent with these failures"; "caused" is reserved
for a mechanism that was traced or reproduced. A zero means no linked evidence was found in the window, which a purge
or a short window can explain.

PRR-1.4. **The baseline order is deterministic**: severity tier, then unique cases, then recency. An explanation may
propose another order within a tier and say why; it never moves a finding across tiers and never changes a severity, a
confidence, a count or a value.

PRR-1.5. **Intended is an annotation, never a production edit.** A person records that a finding is `intended`, an
`accepted_risk` or a `false_positive`, with a reason, an owner and an expiry. The annotation is bound to the finding's
code, item, setting and value: when the value changes or the annotation expires, the finding reopens as new. An
annotated finding stays visible in the review with its status.

## PRR-2 Retries and failure

### RETRY_FOREVER (high, confirmed)

PRR-2.1. `FailureTimeout` is how long, in seconds, an operation or process keeps retrying a message before it fails it
forward. A value of -1 means for ever: the message never fails, nothing opens a case, and the item's queue holds every
later message behind it while the retries go on. On an HL7 TCP operation -1 is the class default, so the finding is
often `class_default`, not a choice anyone made.

PRR-2.2. The safer value is a finite budget agreed with the receiver's team, in seconds, long enough to ride out a short
outage and short enough that a person hears of a long one; on Shutter's own connectors 0 (fail at once) is what lets
the process open a case instead of retrying.

PRR-2.3. Intended when an operation must never lose a message and a staffed watch exists on its queue depth and the
oldest message's age (queue alerts on, an alert consumer present, someone named to act). A reviewer tells by looking
for that watch: `QUEUE_ALERTS_OFF` or `NO_ALERT_CONSUMER` on the same production says it is not there.

### GIVES_UP_EARLY (medium, confirmed)

PRR-2.4. `FailureTimeout` is set between 0 and twice the `RetryInterval`: the message fails before a second attempt can
be made, so a transient fault (a connection reset, a receiver restarting) fails messages that a single retry would have
delivered.

PRR-2.5. The safer value is a timeout of at least a few retry intervals, or 0 when failing at once is the design (as on
the connectors a Shutter process watches). Intended when the item is such a connector and the design says so: the
reviewer tells by whether a process opens a case for its failures.

### REPLY_CODES_LENIENT (high, confirmed)

PRR-2.6. On an HL7 operation, `ReplyCodeActions` maps the receiver's acknowledgement code (the MSA-1 value: AA or CA
accept, AE or CE error, AR or CR reject) to what the operation does with the message. From the product documentation:
C treats the message as completed, R retries it, F fails it, S suspends it, W logs a warning, D disables the item;
`?E` matches the error codes, `?R` the rejections, `?A` the accepts, `~` a reply that is not an acknowledgement, `*`
anything else. This finding is an E or R code mapped to C: a negative acknowledgement is treated as a delivery, so a
message the receiver refused counts as sent and no case is opened.

PRR-2.7. The safer value is explicit, receiver-agreed handling in which accepts complete, rejections have a bounded
retry and then fail, and errors reach a visible place (a suspension that is watched, or a failure that opens a case).
Intended only for a receiver that is known to answer AE for messages it has committed, under a written interface
agreement with an owner and an independent check of the receiver's state; even then it hides any new rejection
reason. A reviewer tells by asking for that agreement and that check.

### REPLY_CODES_SUSPEND_UNWATCHED (medium, consistent)

PRR-2.8. E or R codes are mapped to S (suspend), and the item has no alerting (`AlertOnError` off or no alert group).
From the product documentation, the class's own default when `ReplyCodeActions` is empty is
`:?R=RF,:?E=S,:~=S,:?A=C,:*=S,:I?=W,:T?=C`: rejections retry then fail, errors and unexpected replies suspend,
accepts complete. That default string is from the documentation, not read on an instance. A suspended message leaves
the queue and waits in the suspended messages list until a person resumes or discards it; with no alert nobody is told
it is there.

PRR-2.9. The safer value keeps the suspension and adds the alert (`AlertOnError` on, an alert group, an alert consumer
in the production), or fails errors forward so a case is opened. Intended when a daily check of the suspended messages
list is part of someone's routine: the reviewer tells by asking who looks and how often, and by `SUSPENDED_MESSAGES`
on the same item, which says whether anything has sat there in the window.

### FRAMING_MISMATCH (high, confirmed)

PRR-2.10. An HL7 TCP operation and a TCP service in the same namespace point at the same address and port with a
different `Framing` (MLLP, or another of the framing options). The connection succeeds, the bytes flow, and no
complete message or acknowledgement is recognised on one side: the feed stalls with the connection up.

PRR-2.11. The safer value is the same framing on both sides, the one the interface contract names, MLLP for an MLLP
peer. Intended only when the two items are not in fact talking to each other (a test service left on a port a real
receiver also uses is still a problem); the reviewer tells by whether the service is enabled and what connects to it.

## PRR-3 Alerting and watching

### NO_ALERT_CONSUMER (medium, confirmed)

PRR-3.1. `AlertOnError` on an item sends an alert request to the item named Ens.Alert (or one of that class) when an
error occurs. The production has no such item, so every alert the items would raise has nowhere to go: alerts reach
the event log only, where nobody is told of them.

PRR-3.2. The safer value is an Ens.Alert item that routes alerts to a staffed destination (email, a notification
operation, a monitoring system), or an external monitor that reads the event log's alert and error entries. Intended
when such an external monitor exists and someone owns it; the reviewer tells by asking what reads the event log and
when it last raised anything.

### ALERTING_OFF (medium, confirmed; one finding for the production)

PRR-3.3. Items on the feed path (the HL7 service, the delivering process, the connector operation) have `AlertOnError`
off or no `AlertGroups` while an alert consumer exists: the consumer is there and these items never speak to it. The
finding lists the items.

PRR-3.4. The safer value is `AlertOnError` on and an alert group that the consumer routes, on each feed-path item.
Intended for an item whose errors another item already reports (a process that opens a case for every failure of its
connector), or for a demo item. The reviewer tells by whether each listed item's failures reach a person some other
way.

### QUEUE_ALERTS_OFF (low, confirmed; one finding for the production)

PRR-3.5. Operations with `QueueCountAlert` 0 and `QueueWaitAlert` 0: no alert when the queue grows or when its oldest
message has waited too long. A backlog, a stuck message or an endless retry is then noticed only when someone looks,
or when a patient's location is wrong downstream.

PRR-3.6. The safer value is a count and a wait agreed locally for each operation (what is normal at the busiest hour,
and how long a message may wait before it matters), with an alert consumer to receive them. Intended when an external
monitor watches queue depth, or for items that never queue (an adapterless item driven synchronously). The reviewer
tells by `QUEUE_BACKLOG` on the same production and by what the external monitor reads.

### FEED_SILENCE_UNWATCHED (low, consistent)

PRR-3.7. The feed's service has `InactivityTimeout` 0: it never says that the feed has gone quiet. A sender that
stopped, a share that was unmounted or a port that nothing connects to looks the same as a quiet night.

PRR-3.8. The safer value is a timeout longer than the longest normal gap between messages (the night, a weekend for
some feeds), with alerting on the item so the alert reaches someone. Intended for feeds that are quiet by schedule and
watched by the sender's side; the reviewer tells by whether the sender's team confirms the feed when Shutter asks.

## PRR-4 Settings that change what is kept or how it flows

### ARCHIVE_IO_ON (low, confirmed)

PRR-4.1. `ArchiveIO` on an item keeps the raw inbound or outbound I/O in the message store beside the messages:
every byte the item read or wrote. That is diagnostic evidence, and it is also a second copy of each message's content
under the same retention and access as the message store.

PRR-4.2. The safer value is off, switched on for a bounded diagnostic period when a fault needs the raw bytes. Intended
when the site's retention and access rules cover it and the purge task purges it with the messages (`BodiesToo`); the
reviewer tells by asking who turned it on, for what, and when it will go off.

### POOL_SIZE_REORDERS (high, confirmed)

PRR-4.3. `PoolSize` above 1 on an HL7 operation or on the process that delivers to it: several jobs take messages from
the queue in parallel, and two movements for one patient can complete in the wrong order. The downstream system applies
operations in the order they arrive, so a transfer delivered after a later discharge moves the patient's recorded
location back.

PRR-4.4. The safer value is 1 on every item that carries an ordered feed. Intended only when the parallel streams are
independent by design (each job owns its own set of patients or encounters, with a proven partition) and the receiver
is known to tolerate it; one job on the operation alone does not prove end-to-end order when an upstream item is
parallel. The reviewer tells by reading the whole path from the service to the connector.

### ITEM_DISABLED (high, confirmed)

PRR-4.5. A feed-path item is disabled: messages for it queue or are never read, and nothing downstream hears of the
movements. A disabled service reads nothing; a disabled operation lets its queue grow.

PRR-4.6. The safer value is enabled, or the item removed from the production when it is retired. Intended during a
planned stop (a receiver's maintenance window) with someone named to enable it again; the reviewer tells by how long
it has been off and whether the queue behind it is watched.

## PRR-5 The purge task

### PURGE_MISSING and PURGE_SUSPENDED (high, confirmed)

PRR-5.1. The namespace has no scheduled message purge task (the Task Manager's Ens.Util.Tasks.Purge task for that
namespace), or it is suspended. Message headers, bodies and the event log then grow without bound until the database
fills and the production stops; a purge that runs again after a long pause may take hours.

PRR-5.2. The safer value is a daily purge task for the namespace with the retention the site agreed. Intended when a
site purges another way (a task in another namespace that covers this one, a site-wide job) and someone owns it; the
reviewer tells by finding that job and its last run.

### PURGE_SHORT (medium, confirmed), PURGE_LONG (low, confirmed), BODIES_KEPT (low, confirmed)

PRR-5.3. `NumberOfDaysToKeep` below 7 removes evidence before an incident is likely to be found; above 365 keeps a
year of messages that few sites need and that slow searches and backups; `BodiesToo` off purges the headers and keeps
the message bodies, which then have no header to be found by and grow for ever.

PRR-5.4. The safer values are the site's incident and audit retention (often 30 to 90 days) with bodies purged with
their headers (`BodiesToo` on) and `KeepIntegrity` on, so an open session is not cut in half. Intended when a site's
retention policy says otherwise in writing; the reviewer asks for it.

## PRR-6 What was observed in the window

### SUSPENDED_MESSAGES (high, confirmed)

PRR-6.1. Messages for the item sit in the suspended messages list (header status Suspended): each was taken out of the
queue by a reply code action or by an error, and waits for a person to resume or discard it. The count and the newest
header id are in the finding. A suspended ADT movement is a patient whose downstream location is not what the PAS
sent, until someone acts.

PRR-6.2. The action is a person's: open the suspended messages list for the item, decide each message (resume,
resend, discard) against the receiver's state, and look for the reply code or the error behind them. Never intended as
a standing state; a routine that empties the list daily makes the finding short-lived, not wrong.

### QUEUE_BACKLOG (medium, confirmed; high above 1000)

PRR-6.3. The item's queue holds more messages than its `QueueCountAlert` (or 100 when none is set). Messages are
waiting: an outage, a slow receiver, an endless retry at the head of the queue, or a disabled item behind it. The
downstream system's picture of where patients are lags by the backlog.

PRR-6.4. The action is to read the head of the queue (the oldest message and what it is waiting on) and the item's
event log. Intended only for a known batch window (a nightly load that queues and drains) at the time of the review;
the reviewer tells by the time of day and by whether the count falls.

### ERRORS_GROUPED (medium, indicative)

PRR-6.5. Event-log errors in the window for one item, grouped by their signature (the error text before its first `#`
or `:`), with the count, the latest entry and, for the operator only, a clipped example. A group is a pattern, not a
diagnosis: the same signature from one item hundreds of times is one fault repeating, not hundreds of faults.

PRR-6.6. The action is to read the latest example and the item's trace for that session. Consistent with the cases of
the same item in the window when their failure kinds match the signature (a delivery unavailable error and cases with
failure kind unavailable); say so with the counts, and say "consistent with".

### RULE_ERRORS (medium, indicative)

PRR-6.7. Routing rule or transformation errors in the window, by rule name from the rule log where it has rows, else
by the transform class read from the error text's stack location (the finding says "from the error text"). A rule that
errors routes nothing for that message; a transformation that errors leaves the message in error status.

PRR-6.8. The action is to open the rule or transformation named and the latest failing message; a rule error on one
message shape (a new trigger event, a new segment) is the usual cause.

### MESSAGE_ERRORS (medium, indicative)

PRR-6.9. Message headers in error status in the window, grouped by target and source item, with the count and the
latest header id. On Shutter's own production these are the deliveries whose process opened a case: the error status
is the process's, set when it terminated for the failure, and the header carries no error text of its own. The
finding's cases say how many of these became cases.

PRR-6.10. Consistent with the cases of the same target in the window: the right reading is that the configuration and
these errors agree with those cases, in these numbers. A target that no longer exists in the production (a renamed
item) is labelled so; its errors are history.

### NAMESPACE_UNREADABLE (info, confirmed)

PRR-6.11. The review could not read the production's namespace: it does not exist, the reader's job lacked the right,
or the production class is not there. The finding carries the error and the review stands with nothing else about
that production. The action is a person's check of the namespace and of what Shutter was told to watch.

## PRR-7 When a finding is intended

PRR-7.1. A finding is intended when a person has decided the value on purpose, with a compensating control, and has
recorded that decision as an annotation with a reason, an owner and an expiry (PRR-1.5). Legitimate cases include:
an endless retry with a staffed watch on queue depth and age; a feed that is quiet by schedule with the sender's team
watching it; a known batch window at review time; a single job kept deliberately for order; parallel streams that are
independent by design; raw I/O kept off for privacy; alerting done by an external monitor instead of an alert
consumer.

PRR-7.2. A reviewer does not take a finding as intended because it has been there a long time, because the value is
the class default, or because nobody has complained. The explanation says "annotated as intended by its owner" when
the status says so, and "no annotation" otherwise.

PRR-7.3. A changed configuration says only that the predicate no longer matches. Whether the operational problem is
solved is for the person who owns the item, after a test.
