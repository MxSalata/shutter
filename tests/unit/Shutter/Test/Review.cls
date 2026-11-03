/// The production review's deterministic pass (Shutter.Review.Sweep and Shutter.Review.Checks over the data
/// Shutter.Util.ProductionReader returns; docs/CONTRACTS.md, section 13) on fabricated data: no production runs for these
/// tests and no namespace is switched, except that one test reads this namespace's own production for its shape and
/// one asks for a namespace that does not exist. The fabricated production has an HL7 TCP operation that retries for
/// ever and treats a rejection as sent, a disabled feed service, a pool of two, no purge task, suspended and failed
/// headers and grouped errors; a second one is set the safer way and yields no finding. Nothing is stored.
Class Shutter.Test.Review Extends %UnitTest.TestCase
{

Parameter FROM = "2026-10-18T10:00:00Z";

Parameter TO = "2026-10-25T10:00:00Z";

/// An effective value is resolved in three explicit steps: the item's own setting, the nearest system default setting
/// (this production over every production, the item over every item), then the host or adapter class's default.
Method TestEffectiveValueResolution()
{
    Set data = ..Data()
    Set item = ..Item("Lab Out", "EnsLib.HL7.Operation.TCPOperation", "EnsLib.HL7.Adapter.TCPOutboundAdapter", "operation", {"FailureTimeout": "30"})
    Do data.items.%Push(item)
    Do data.defaultSettings.%Push({"productionName": "UT.Production", "itemName": "*", "hostClassName": "*", "settingName": "RetryInterval", "settingValue": "11"})
    Do data.defaultSettings.%Push({"productionName": "UT.Production", "itemName": "Lab Out", "hostClassName": "*", "settingName": "RetryInterval", "settingValue": "12"})
    Do data.defaultSettings.%Push({"productionName": "Other.Production", "itemName": "Lab Out", "hostClassName": "*", "settingName": "QueueCountAlert", "settingValue": "99"})
    Do data.defaultSettings.%Push({"productionName": "*", "itemName": "*", "hostClassName": "EnsLib.HL7.Adapter.TCPOutboundAdapter", "settingName": "ResponseTimeout", "settingValue": "45"})
    Set v = ##class(Shutter.Review.Sweep).Effective(data, item, "FailureTimeout", .source)
    Do $$$AssertEquals(v, "30", "the item's own setting wins")
    Do $$$AssertEquals(source, "item", "and the source says so")
    Set v = ##class(Shutter.Review.Sweep).Effective(data, item, "RetryInterval", .source)
    Do $$$AssertEquals(v, "12", "the default setting named for the item beats the one for every item")
    Do $$$AssertEquals(source, "default_setting", "and the source says so")
    Set v = ##class(Shutter.Review.Sweep).Effective(data, item, "QueueCountAlert", .source)
    Do $$$AssertEquals(v, "0", "another production's default setting does not apply, so the class default does")
    Do $$$AssertEquals(source, "class_default", "and the source says so")
    Set v = ##class(Shutter.Review.Sweep).Effective(data, item, "ResponseTimeout", .source)
    Do $$$AssertEquals(v, "45", "a default setting for the adapter class applies to the item")
    Do $$$AssertEquals(source, "default_setting", "and the source says so")
    Set v = ##class(Shutter.Review.Sweep).Effective(data, item, "IPAddress", .source)
    Do $$$AssertEquals(source, "class_default", "an adapter setting falls back to the adapter class's default")
    Set v = ##class(Shutter.Review.Sweep).Effective(data, item, "NoSuchSetting", .source)
    Do $$$AssertEquals(v, "", "a setting nobody has is empty")
    Do $$$AssertEquals(source, "", "with no source")
}

/// Every check fires on the production that should trigger it, with the words, the severity and the evidence expected.
Method TestEveryCheckFires()
{
    Set data = ..Hazard()
    Set cases = {"Lab Out": {"count": 4, "unique": 3, "latest": ["C-000004", "C-000003"]}, "_total": {"count": 9, "unique": 7, "latest": ["C-000009"]}}
    Set findings = ##class(Shutter.Review.Sweep).Evaluate(data, cases, ..Window())
    Kill seen
    Set iter = findings.%GetIterator()
    While iter.%GetNext(.i, .f) {
        Set seen(f.code) = $GET(seen(f.code)) + 1
        Do $$$AssertTrue($LISTFIND($LISTBUILD("high", "medium", "low", "info"), f.severity) > 0, f.code _ " has a severity: " _ f.severity)
        Do $$$AssertTrue($LISTFIND($LISTBUILD("confirmed", "consistent", "indicative"), f.confidence) > 0, f.code _ " has a confidence: " _ f.confidence)
        Do $$$AssertTrue((f.why '= "") && (f.action '= "") && (f.suggested '= ""), f.code _ " has its words")
        Do $$$AssertEquals(f.status, "new", f.code _ " starts new")
        Do $$$AssertEquals(f.%GetTypeOf("rank"), "null", f.code _ " has no rank yet")
        Do $$$AssertEquals(f.%GetTypeOf("found"), "string", f.code _ " found is a string")
    }
    Set f = ..Find(findings, "RETRY_FOREVER", "Lab Out")
    Do $$$AssertTrue($ISOBJECT(f), "RETRY_FOREVER fires on FailureTimeout -1")
    If $ISOBJECT(f) {
        Do $$$AssertEquals(f.severity, "high", "it is high")
        Do $$$AssertEquals(f.confidence, "confirmed", "and confirmed")
        Do $$$AssertEquals(f.found, "-1", "found is the value")
        Do $$$AssertEquals(f.source, "item", "set on the item")
        Do $$$AssertEquals(f.setting, "FailureTimeout", "the setting is named")
        Do $$$AssertEquals(f.itemClass, "EnsLib.HL7.Operation.TCPOperation", "the class is named")
        Do $$$AssertEquals(f.cases.unique, 3, "the item's cases are tied to it")
        Do $$$AssertEquals(f.cases.latest.%Get(0), "C-000004", "with the newest case ids")
    }
    Set f = ..Find(findings, "REPLY_CODES_LENIENT", "Lab Out")
    Do $$$AssertTrue($ISOBJECT(f), "REPLY_CODES_LENIENT fires on :?E=C")
    If $ISOBJECT(f) {
        Do $$$AssertTrue(f.found [ "AE=C", "and names the code and its action: " _ f.found)
        Do $$$AssertEquals(f.severity, "high", "it is high")
    }
    Set f = ..Find(findings, "REPLY_CODES_SUSPEND_UNWATCHED", "Pharmacy Out")
    Do $$$AssertTrue($ISOBJECT(f), "REPLY_CODES_SUSPEND_UNWATCHED fires on the documented default with alerting off")
    If $ISOBJECT(f) {
        Do $$$AssertTrue(f.found [ "AE=S", "the suspension is named: " _ f.found)
        Do $$$AssertTrue(f.found [ "documented default", "and the default is called documented: " _ f.found)
        Do $$$AssertEquals(f.confidence, "consistent", "it is consistent, not confirmed")
        Do $$$AssertEquals(f.source, "class_default", "from the class default")
    }
    Set f = ..Find(findings, "POOL_SIZE_REORDERS", "Lab Out")
    Do $$$AssertTrue($ISOBJECT(f), "POOL_SIZE_REORDERS fires on PoolSize 2")
    If $ISOBJECT(f) Do $$$AssertEquals(f.found, "2", "with the pool size as found")
    Set f = ..Find(findings, "FRAMING_MISMATCH", "Lab Out")
    Do $$$AssertTrue($ISOBJECT(f), "FRAMING_MISMATCH fires for MLLP against a local AsciiLF service on the same port")
    If $ISOBJECT(f) Do $$$AssertTrue((f.found [ "Lab In") && (f.found [ "5000"), "and names the service and the port: " _ f.found)
    Set f = ..Find(findings, "ITEM_DISABLED", "ADT In")
    Do $$$AssertTrue($ISOBJECT(f), "ITEM_DISABLED fires on a disabled feed item")
    If $ISOBJECT(f) Do $$$AssertEquals(f.severity, "high", "it is high")
    Set f = ..Find(findings, "GIVES_UP_EARLY", "Ward Out")
    Do $$$AssertTrue($ISOBJECT(f), "GIVES_UP_EARLY fires on FailureTimeout 5 with RetryInterval 5")
    If $ISOBJECT(f) Do $$$AssertEquals(f.found, "FailureTimeout 5 with RetryInterval 5", "found names both")
    Do $$$AssertTrue($ISOBJECT(..Find(findings, "ARCHIVE_IO_ON", "Ward Out")), "ARCHIVE_IO_ON fires on ArchiveIO 1")
    Do $$$AssertTrue($ISOBJECT(..Find(findings, "FEED_SILENCE_UNWATCHED", "ADT In")), "FEED_SILENCE_UNWATCHED fires on the file service")
    Do $$$AssertTrue($ISOBJECT(..Find(findings, "FEED_SILENCE_UNWATCHED", "Lab In")), "and on the TCP service")
    Set f = ..Find(findings, "NO_ALERT_CONSUMER", "")
    Do $$$AssertTrue($ISOBJECT(f), "NO_ALERT_CONSUMER fires with no Ens.Alert item")
    If $ISOBJECT(f) Do $$$AssertEquals(f.cases.unique, 0, "a finding about the production as a whole carries no case count; the production's cases stay in the aggregates")
    Set f = ..Find(findings, "ALERTING_OFF", "")
    Do $$$AssertTrue($ISOBJECT(f), "ALERTING_OFF is one finding for the production")
    Do $$$AssertEquals($GET(seen("ALERTING_OFF")), 1, "exactly one")
    If $ISOBJECT(f) {
        Do $$$AssertTrue((f.found [ "Lab Out") && (f.found [ "ADT In") && (f.found [ "ADT to Ward"), "listing the feed-path items: " _ f.found)
        Do $$$AssertNotTrue(f.found [ "Agent Board", "and not an item off the feed path")
    }
    Set f = ..Find(findings, "QUEUE_ALERTS_OFF", "")
    Do $$$AssertTrue($ISOBJECT(f), "QUEUE_ALERTS_OFF is one finding for the production")
    Do $$$AssertEquals($GET(seen("QUEUE_ALERTS_OFF")), 1, "exactly one")
    If $ISOBJECT(f) {
        Do $$$AssertTrue((f.found [ "Lab Out") && (f.found [ "Ward Out"), "listing the feed-path operations: " _ f.found)
        Do $$$AssertNotTrue(f.found [ "ADT to Ward", "and no process")
    }
    Do $$$AssertTrue($ISOBJECT(..Find(findings, "PURGE_MISSING", "")), "PURGE_MISSING fires with no purge task")
    Set f = ..Find(findings, "SUSPENDED_MESSAGES", "Lab Out")
    Do $$$AssertTrue($ISOBJECT(f), "SUSPENDED_MESSAGES fires on status 5 headers")
    If $ISOBJECT(f) {
        Do $$$AssertEquals(f.evidence.count, 3, "with the count")
        Do $$$AssertEquals(f.evidence.latestHeaderId, "900", "the latest header id")
        Do $$$AssertTrue(f.why [ "3 messages", "and the count in the words, with its plural: " _ f.why)
    }
    Set f = ..Find(findings, "MESSAGE_ERRORS", "Ward Out")
    Do $$$AssertTrue($ISOBJECT(f), "MESSAGE_ERRORS fires on status 8 headers")
    If $ISOBJECT(f) {
        Do $$$AssertEquals(f.evidence.count, 12, "with the count")
        Do $$$AssertTrue(f.found [ "ADT to Ward", "and the source: " _ f.found)
        Do $$$AssertEquals(f.confidence, "indicative", "a count is indicative")
    }
    Set f = ..Find(findings, "ERRORS_GROUPED", "ADT to Ward")
    Do $$$AssertTrue($ISOBJECT(f), "ERRORS_GROUPED fires on the error group")
    If $ISOBJECT(f) {
        Do $$$AssertEquals(f.found, "ERROR <Ens>ErrBPTerminated", "found is the signature")
        Do $$$AssertEquals(f.evidence.latestHeaderId, "950", "the latest message id is the header id")
        Do $$$AssertTrue(f.evidence.example [ "ErrBPTerminated", "the example text is in the evidence")
        Do $$$AssertEquals(f.itemClass, "UT.Process", "the item's class is named")
    }
    Set f = ..Find(findings, "ERRORS_GROUPED", "Old Item")
    Do $$$AssertTrue($ISOBJECT(f), "an error group of an item that is gone is still reported")
    If $ISOBJECT(f) Do $$$AssertTrue(f.why [ "no longer in the production", "and says the item is gone: " _ f.why)
    Set f = ..Find(findings, "RULE_ERRORS", "UT.Transform")
    Do $$$AssertTrue($ISOBJECT(f), "RULE_ERRORS names the transform parsed from the error text when the rule log is empty")
    If $ISOBJECT(f) Do $$$AssertEquals(f.found, "from the error text", "and says where the name came from")
    Set f = ..Find(findings, "QUEUE_BACKLOG", "Lab Out")
    Do $$$AssertTrue($ISOBJECT(f), "QUEUE_BACKLOG fires above the default threshold")
    If $ISOBJECT(f) Do $$$AssertEquals(f.severity, "medium", "150 is medium")
    Set f = ..Find(findings, "QUEUE_BACKLOG", "Ward Out")
    Do $$$AssertTrue($ISOBJECT(f), "and on the second queue")
    If $ISOBJECT(f) Do $$$AssertEquals(f.severity, "high", "1500 is high")
    // The purge task's other findings, and the rule log's.
    Set data = ..Hazard()
    Set data.purgeTask = {"present": true, "suspended": true, "daysToKeep": 3, "bodiesToo": false, "keepIntegrity": true, "typesToPurge": "all", "lastFinished": ""}
    Set data.ruleErrors = [{"ruleName": "ADT Router", "ruleSet": "Main", "count": 2, "latestId": "5", "errorMsg": "ERROR <Ens>ErrGeneral: no rule matched"}]
    Set more = ##class(Shutter.Review.Sweep).Evaluate(data, "", ..Window())
    Set iter = more.%GetIterator()
    While iter.%GetNext(.i, .f) {
        Set seen(f.code) = $GET(seen(f.code)) + 1
    }
    Do $$$AssertTrue($ISOBJECT(..Find(more, "PURGE_SUSPENDED", "")), "PURGE_SUSPENDED fires")
    Set f = ..Find(more, "PURGE_SHORT", "")
    Do $$$AssertTrue($ISOBJECT(f), "PURGE_SHORT fires under 7 days")
    If $ISOBJECT(f) Do $$$AssertEquals(f.found, "3", "with the days")
    Do $$$AssertTrue($ISOBJECT(..Find(more, "BODIES_KEPT", "")), "BODIES_KEPT fires on BodiesToo 0")
    Set f = ..Find(more, "RULE_ERRORS", "ADT Router")
    Do $$$AssertTrue($ISOBJECT(f), "RULE_ERRORS fires from the rule log")
    If $ISOBJECT(f) {
        Do $$$AssertEquals(f.evidence.count, 2, "with the count")
        Do $$$AssertTrue(f.evidence.example [ "no rule matched", "and the error as the example")
    }
    Do $$$AssertNotTrue($ISOBJECT(..Find(more, "RULE_ERRORS", "UT.Transform")), "the error text is not parsed for a transform when the rule log has rows")
    Do $$$AssertNotTrue($ISOBJECT(..Find(more, "PURGE_MISSING", "")), "PURGE_MISSING does not fire with a task present")
    Set data.purgeTask.daysToKeep = 400
    Set more = ##class(Shutter.Review.Sweep).Evaluate(data, "", ..Window())
    Set f = ..Find(more, "PURGE_LONG", "")
    Do $$$AssertTrue($ISOBJECT(f), "PURGE_LONG fires over 365 days")
    If $ISOBJECT(f) Set seen("PURGE_LONG") = 1
    // The one code the checks never produce themselves is the reader's failure (TestRunOnAnUnknownNamespace).
    Set seen("NAMESPACE_UNREADABLE") = 1
    Set missing = ""
    Set codes = ##class(Shutter.Review.Checks).Codes()
    Set iter = codes.%GetIterator()
    While iter.%GetNext(.i, .code) {
        If '$DATA(seen(code)) Set missing = missing _ $SELECT(missing = "": "", 1: ", ") _ code
    }
    Do $$$AssertEquals(missing, "", "every code of the table fires on some input" _ $SELECT(missing = "": "", 1: "; not fired: " _ missing))
}

/// A production set the safer way yields no finding: the HL7 checks run only for HL7 operations, a pool of two off
/// the feed is no finding, and an operation pointed at another host does not pair with the local service.
/// The finding's words read as sentences for one and for many (no "(s)"), and an item left empty (an error the production
/// itself logged) reads "the production itself", never "logged by ." (the restyle review's D3).
Method TestTextsReadForOneAndForNone()
{
    Set f = ##class(Shutter.Review.Checks).Finding("ERRORS_GROUPED", "", "", "", "ERROR <Ens>ErrBPTerminated", "", 1)
    Do $$$AssertTrue(f.why [ "1 error with the signature ERROR <Ens>ErrBPTerminated in the window, logged by the production itself.", "one error, logged by the production itself: " _ f.why)
    Do $$$AssertEquals($FIND(f.why _ f.action _ f.suggested, "(s)"), 0, "no (s) plural anywhere")
    Do $$$AssertTrue(f.action [ "filtered on the production itself", "the action names the production: " _ f.action)
    Set f = ##class(Shutter.Review.Checks).Finding("ERRORS_GROUPED", "ADT to Downstream", "EnsLib.HL7.Operation.TCPOperation", "", "ERROR <Ens>ErrBPTerminated", "", 445)
    Do $$$AssertTrue(f.why [ "445 errors with the signature ERROR <Ens>ErrBPTerminated in the window, logged by ADT to Downstream.", "many errors, logged by the item: " _ f.why)
    Do $$$AssertTrue(f.action [ "filtered on ADT to Downstream", "the action names the item: " _ f.action)
    Set f = ##class(Shutter.Review.Checks).Finding("RULE_ERRORS", "Router", "", "", "", "", 2)
    Do $$$AssertTrue(f.why [ "2 rule or transform errors in the window for Router", "rule errors in the plural: " _ f.why)
    Set f = ##class(Shutter.Review.Checks).Finding("QUEUE_BACKLOG", "ADT to Downstream", "", "QueueCountAlert", "100", "", 1)
    Do $$$AssertTrue(f.why [ "1 message in the queue of ADT to Downstream, above the threshold (100)", "one message in the queue: " _ f.why)
    Set f = ##class(Shutter.Review.Checks).Finding("SUSPENDED_MESSAGES", "", "", "", "", "", 3)
    Do $$$AssertTrue(f.why [ "3 messages to the production itself, suspended in the window", "suspended messages with no item: " _ f.why)
    Set f = ##class(Shutter.Review.Checks).Finding("MESSAGE_ERRORS", "ADT to Downstream", "", "", "Errored", "", 1)
    Do $$$AssertTrue(f.why [ "1 message to ADT to Downstream ended in an error status in the window (Errored)", "one message in error: " _ f.why)
}

Method TestNothingFiresOnASafeProduction()
{
    Set data = ..Data()
    Do data.items.%Push(..Item("Lab Out", "EnsLib.HL7.Operation.TCPOperation", "EnsLib.HL7.Adapter.TCPOutboundAdapter", "operation", {"FailureTimeout": "300", "RetryInterval": "5", "ReplyCodeActions": ":?R=RF,:?E=F,:~=F,:?A=C,:*=F", "AlertOnError": "1", "AlertGroups": "Ops", "QueueCountAlert": "100", "QueueWaitAlert": "300", "IPAddress": "10.0.0.5", "Port": "5000", "Framing": "MLLP"}))
    Do data.items.%Push(..Item("Lab In", "EnsLib.HL7.Service.TCPService", "EnsLib.HL7.Adapter.TCPInboundAdapter", "service", {"Port": "5000", "Framing": "AsciiLF", "InactivityTimeout": "300", "AlertOnError": "1", "AlertGroups": "Ops"}))
    Do data.items.%Push(..Item("ADT In", "EnsLib.HL7.Service.FileService", "EnsLib.File.InboundAdapter", "service", {"InactivityTimeout": "600", "AlertOnError": "1", "AlertGroups": "Ops"}))
    Do data.items.%Push(..Item("ADT to Ward", "UT.Process", "", "process", {"AlertOnError": "1", "AlertGroups": "Ops"}))
    Do data.items.%Push(..Item("Ward Out", "UT.Operation", "EnsLib.HTTP.OutboundAdapter", "operation", {"FailureTimeout": "0", "AlertOnError": "1", "AlertGroups": "Ops", "QueueCountAlert": "50", "QueueWaitAlert": "60", "ReplyCodeActions": ":?E=C"}))
    Do data.items.%Push(..Item("Agent Board", "UT.Operation", "", "operation", {}, "Board", 1, 2))
    Do data.items.%Push(..Item("Alerts", "Ens.Alert", "", "process", {}, "Recovery"))
    Do data.%Set("alertItemPresent", 1, "boolean")
    Set data.queues = [{"name": "Lab Out", "count": 3, "created": "2026-10-25T09:00:00Z"}, {"name": "Agent Board", "count": 0, "created": "2026-10-25T09:00:00Z"}]
    Set findings = ##class(Shutter.Review.Sweep).Evaluate(data, "", ..Window())
    Do $$$AssertEquals(findings.%Size(), 0, "no finding: " _ ..Codes(findings))
    Do $$$AssertEquals(##class(Shutter.Review.Sweep).Fingerprint(findings), "", "and no fingerprint")
}

/// The reply code grammar: the first matching pattern decides, and only C or W alone is lenient.
Method TestReplyCodeActions()
{
    Set documented = ##class(Shutter.Review.Checks).#DOCUMENTEDREPLYCODEACTIONS
    Do $$$AssertEquals(##class(Shutter.Review.Sweep).ReplyAction(documented, "AE"), "S", "the documented default suspends AE")
    Do $$$AssertEquals(##class(Shutter.Review.Sweep).ReplyAction(documented, "AR"), "RF", "retries then fails AR")
    Do $$$AssertEquals(##class(Shutter.Review.Sweep).ReplyAction(documented, "AA"), "C", "completes AA")
    Do $$$AssertEquals(##class(Shutter.Review.Sweep).ReplyAction(":?E=C", "AE"), "C", "a lone pattern")
    Do $$$AssertEquals(##class(Shutter.Review.Sweep).ReplyAction(":?E=C", "AR"), "", "and nothing for a code it does not name")
    Do $$$AssertEquals(##class(Shutter.Review.Sweep).ReplyAction("AE=W, :*=S", "AE"), "W", "the code itself, with spaces")
    Do $$$AssertEquals(##class(Shutter.Review.Sweep).ReplyAction("AE=W,:*=S", "AR"), "S", "the wildcard takes the rest")
    Do $$$AssertEquals(##class(Shutter.Review.Sweep).ReplyAction(":I?=W,:?E=F", "IE"), "W", "the first match wins")
    Do $$$AssertEquals(##class(Shutter.Review.Sweep).ReplyAction("E=C", "CE"), "C", "a bare letter is the code's second letter")
    Do $$$AssertTrue(##class(Shutter.Review.Sweep).IsLenient("C"), "C is lenient")
    Do $$$AssertTrue(##class(Shutter.Review.Sweep).IsLenient("W"), "W is lenient")
    Do $$$AssertNotTrue(##class(Shutter.Review.Sweep).IsLenient("RF"), "RF is not")
    Do $$$AssertNotTrue(##class(Shutter.Review.Sweep).IsLenient("S"), "S is not")
    Do $$$AssertNotTrue(##class(Shutter.Review.Sweep).IsLenient(""), "nothing is not")
}

/// The error signature: the text before its first colon, a hash cuts it unless it starts an error number, clipped to 120.
Method TestErrorSignature()
{
    Set demo = "ERROR <Ens>ErrBPTerminated: Terminating BP ADT to Downstream # due to error: ERROR #5001: Delivery unavailable (ward_unavailable), HTTP 503: The downstream system is unavailable. A case was opened"
    Do $$$AssertEquals(##class(Shutter.Review.Sweep).Signature(demo), "ERROR <Ens>ErrBPTerminated", "the demo's error")
    Do $$$AssertEquals(##class(Shutter.Review.Sweep).Signature("ERROR #5001: Delivery unavailable (ward_unavailable), HTTP 503"), "ERROR #5001", "an error number is kept")
    Do $$$AssertEquals(##class(Shutter.Review.Sweep).Signature("Terminating BP ADT to Downstream # due to error"), "Terminating BP ADT to Downstream", "an instance number is cut")
    Do $$$AssertEquals(##class(Shutter.Review.Sweep).Signature(""), "", "nothing gives nothing")
    Set long = ""
    For i = 1:1:30 Set long = long _ "abcde"
    Do $$$AssertEquals($LENGTH(##class(Shutter.Review.Sweep).Signature(long)), 120, "clipped to 120")
    Do $$$AssertEquals(##class(Shutter.Review.Sweep).TransformIn("ERROR <Ens>ErrException: <UNDEFINED>zTransform+12^UT.Transform.1 *x"), "UT.Transform", "a transform class from a stack location")
    Do $$$AssertEquals(##class(Shutter.Review.Sweep).TransformIn("ERROR <Ens>ErrGeneral: nothing here"), "", "none when there is none")
}

/// The configuration fingerprint ignores counts, ids and times and moves with a setting value; the value fingerprint is
/// the key an annotation binds to.
Method TestFingerprint()
{
    Set a = ##class(Shutter.Review.Sweep).Evaluate(..Hazard(), "", ..Window())
    Set fa = ##class(Shutter.Review.Sweep).Fingerprint(a)
    Do $$$AssertEquals($LENGTH(fa), 64, "a SHA-256 in hex")
    Do $$$AssertEquals(fa, $ZCONVERT(fa, "L"), "in lower case")
    // Counts, ids and times move; the configuration does not.
    Set data = ..Hazard()
    Set h0 = data.headerErrors.%Get(0), h1 = data.headerErrors.%Get(1), g0 = data.logErrors.%Get(0), q0 = data.queues.%Get(0)
    Set h0.count = 30, h0.latestId = "9900", h1.count = 1
    Set g0.count = 1, g0.latestId = "1", g0.latestAt = "2026-10-19T00:00:00Z"
    Set q0.count = 2000
    Set data.readAt = "2026-10-26T10:00:00Z"
    Set b = ##class(Shutter.Review.Sweep).Evaluate(data, "", ..Window())
    Do $$$AssertEquals(##class(Shutter.Review.Sweep).Fingerprint(b), fa, "counts, ids and times do not move it")
    // A setting value does.
    Set data = ..Hazard()
    Set labOut = data.items.%Get(0)
    Set labOut.poolSize = 3
    Set c = ##class(Shutter.Review.Sweep).Evaluate(data, "", ..Window())
    Do $$$AssertNotEquals(##class(Shutter.Review.Sweep).Fingerprint(c), fa, "a changed setting value moves it")
    // Only the volatile findings: nothing to fingerprint.
    Set v = []
    Do v.%Push(##class(Shutter.Review.Checks).Finding("MESSAGE_ERRORS", "Ward Out", "", "", "12 in Error", "observed", 12))
    Do v.%Push(##class(Shutter.Review.Checks).Finding("ERRORS_GROUPED", "Ward Out", "", "", "ERROR #5001", "observed", 12))
    Do $$$AssertEquals(##class(Shutter.Review.Sweep).Fingerprint(v), "", "volatile findings alone give no fingerprint")
    Do $$$AssertEquals(##class(Shutter.Review.Sweep).Fingerprint([]), "", "and so does nothing")
    Set vf = ##class(Shutter.Review.Sweep).ValueFingerprint("RETRY_FOREVER", "Lab Out", "FailureTimeout", "-1")
    Do $$$AssertEquals($LENGTH(vf), 64, "the value fingerprint is a SHA-256 in hex")
    Do $$$AssertNotEquals(vf, ##class(Shutter.Review.Sweep).ValueFingerprint("RETRY_FOREVER", "Lab Out", "FailureTimeout", "0"), "and moves with the value")
}

/// The baseline rank: severity tier, then unique cases, then the newest evidence, then code and item; ids F1 onwards.
Method TestBaselineRank()
{
    Set findings = []
    Set a = ##class(Shutter.Review.Checks).Finding("ARCHIVE_IO_ON", "A", "", "ArchiveIO", "1", "item")
    Set a.cases.unique = 5
    Set b = ##class(Shutter.Review.Checks).Finding("RETRY_FOREVER", "B", "", "FailureTimeout", "-1", "item")
    Set c = ##class(Shutter.Review.Checks).Finding("MESSAGE_ERRORS", "C", "", "", "2 in Error", "observed", 2)
    Set c.cases.unique = 2, c.evidence.latestAt = "2026-10-20T10:00:00Z"
    Set d = ##class(Shutter.Review.Checks).Finding("ITEM_DISABLED", "D", "", "Enabled", "0", "item")
    Set d.cases.unique = 3
    Set e = ##class(Shutter.Review.Checks).Finding("MESSAGE_ERRORS", "E", "", "", "9 in Error", "observed", 9)
    Set e.cases.unique = 2, e.evidence.latestAt = "2026-10-24T10:00:00Z"
    Set g = ##class(Shutter.Review.Checks).Finding("MESSAGE_ERRORS", "A", "", "", "1 in Error", "observed", 1)
    Set g.cases.unique = 2, g.evidence.latestAt = "2026-10-24T10:00:00Z"
    For f = a, b, c, d, e, g Do findings.%Push(f)
    Do ##class(Shutter.Review.Sweep).BaselineRank(findings)
    Set order = ""
    Set iter = findings.%GetIterator()
    While iter.%GetNext(.i, .f) {
        Set order = order _ $SELECT(order = "": "", 1: ",") _ f.item _ "=" _ f.id
    }
    Do $$$AssertEquals(order, "D=F1,B=F2,A=F3,E=F4,C=F5,A=F6", "high first (more cases first), then medium by cases, newest evidence, then item; low last: " _ order)
    Do $$$AssertEquals(findings.%Size(), 6, "nothing lost")
}

/// Annotations: a finding whose code, item, setting and value fingerprint match takes the annotation's status and id;
/// a changed value no longer matches and the finding is new again. A stub resolver stands in for the store.
Method TestApplyAnnotations()
{
    Set findings = ##class(Shutter.Review.Sweep).Evaluate(..Hazard(), "", ..Window())
    Set n = ##class(Shutter.Review.Sweep).ApplyAnnotations(findings, "UT", "UT.Production", $CLASSNAME())
    Do $$$AssertEquals(n, 1, "one finding is annotated")
    Set f = ..Find(findings, "RETRY_FOREVER", "Lab Out")
    Do $$$AssertEquals(f.status, "intended", "with the annotation's status")
    Do $$$AssertEquals(f.annotationId, "UT-ANN-1", "and its id")
    Set other = ..Find(findings, "POOL_SIZE_REORDERS", "Lab Out")
    Do $$$AssertEquals(other.status, "new", "the others stay new")
    Set changed = []
    Do changed.%Push(##class(Shutter.Review.Checks).Finding("RETRY_FOREVER", "Lab Out", "EnsLib.HL7.Operation.TCPOperation", "FailureTimeout", "0", "item"))
    Do $$$AssertEquals(##class(Shutter.Review.Sweep).ApplyAnnotations(changed, "UT", "UT.Production", $CLASSNAME()), 0, "a changed value matches no annotation")
    Set reopened = changed.%Get(0)
    Do $$$AssertEquals(reopened.status, "new", "so the finding reopens")
    Do $$$AssertEquals(##class(Shutter.Review.Sweep).ApplyAnnotations(findings, "UT", "UT.Production", "Shutter.Test.NoSuchResolver"), 0, "no resolver class, nothing annotated")
}

/// The stub resolver: StatusFor as Shutter.Store.ReviewAnnotation answers it.
ClassMethod StatusFor(code As %String, namespace As %String, production As %String, item As %String, setting As %String, valueFingerprint As %String, Output annotationId As %String) As %String
{
    Set annotationId = ""
    If (code = "RETRY_FOREVER") && (item = "Lab Out") && (valueFingerprint = ##class(Shutter.Review.Sweep).ValueFingerprint("RETRY_FOREVER", "Lab Out", "FailureTimeout", "-1")) {
        Set annotationId = "UT-ANN-1"
        Quit "intended"
    }
    Quit ""
}

/// The reader on this namespace's own production: the shape, not the values.
Method TestReaderReadsThisNamespace()
{
    Set from = ##class(Shutter.Util.Time).FromNow(-7 * 86400)
    Set sc = ##class(Shutter.Util.ProductionReader).Read($NAMESPACE, ##class(Shutter.Setup).ProductionName(), from, .data)
    Do $$$AssertStatusOK(sc, "the namespace's own production reads" _ $SELECT($ISOBJECT($GET(data)): ": " _ data.error, 1: ""))
    Quit:$$$ISERR(sc)
    Do $$$AssertEquals(data.namespace, $NAMESPACE, "the namespace is echoed")
    Do $$$AssertEquals(data.%GetTypeOf("items"), "array", "items is an array")
    Do $$$AssertTrue(data.items.%Size() > 0, "and not empty")
    Set item = data.items.%Get(0)
    Do $$$AssertTrue((item.name '= "") && (item.className '= ""), "an item has a name and a class")
    Do $$$AssertTrue($LISTFIND($LISTBUILD("service", "process", "operation"), item.businessType) > 0, "and a business type: " _ item.businessType)
    Do $$$AssertEquals(item.%GetTypeOf("enabled"), "boolean", "enabled is a boolean")
    Do $$$AssertEquals(item.%GetTypeOf("settings"), "array", "settings is an array")
    Do $$$AssertEquals(data.%GetTypeOf("productionState"), "string", "the state is a string")
    Do $$$AssertTrue(data.productionState '= "", "and not empty")
    Set t = data.%GetTypeOf("purgeTask")
    Do $$$AssertTrue((t = "object") || (t = "null"), "the purge task is an object or null: " _ t)
    If t = "object" Do $$$AssertEquals(data.purgeTask.%GetTypeOf("present"), "boolean", "with present as a boolean")
    Do $$$AssertEquals(data.classDefaults.%GetTypeOf(item.className), "object", "the item's class has its defaults")
    Do $$$AssertEquals(data.%GetTypeOf("alertItemPresent"), "boolean", "alertItemPresent is a boolean")
    For key = "defaultSettings", "logErrors", "headerErrors", "queues", "ruleErrors" {
        Do $$$AssertEquals(data.%GetTypeOf(key), "array", key _ " is an array")
    }
    Set iter = data.logErrors.%GetIterator()
    While iter.%GetNext(.i, .g) {
        Do $$$AssertTrue((g.latestAt = "") || ($EXTRACT(g.latestAt, *) = "Z"), "a log group's time is ISO UTC: " _ g.latestAt)
        Do $$$AssertTrue($LENGTH(g.signature) <= 120, "its signature is clipped")
    }
    Do $$$AssertTrue($EXTRACT(data.readAt, *) = "Z", "readAt is ISO UTC")
    Do $$$AssertEquals(data.error, "", "no error")
}

/// A namespace that is not there gives one finding and a result, never an error.
Method TestRunOnAnUnknownNamespace()
{
    Set sc = ##class(Shutter.Review.Sweep).Run("UTNOSUCHNAMESPACE", "UT.Production", 7, .result)
    Do $$$AssertStatusOK(sc, "the run succeeds")
    Do $$$AssertTrue(result.unreadable, "and says the namespace is unreadable")
    Do $$$AssertEquals(result.findings.%Size(), 1, "with one finding")
    Set f = result.findings.%Get(0)
    Do $$$AssertEquals(f.code, "NAMESPACE_UNREADABLE", "NAMESPACE_UNREADABLE")
    Do $$$AssertEquals(f.severity, "info", "which is info")
    Do $$$AssertEquals(f.id, "F1", "ranked first")
    Do $$$AssertTrue(f.found [ "UTNOSUCHNAMESPACE", "naming the namespace: " _ f.found)
    Do $$$AssertEquals(result.fingerprint, "", "no configuration fingerprint")
    Do $$$AssertEquals(result.summary.bySeverity.info, 1, "the summary counts it")
    Do $$$AssertEquals(result.summary.findings, 1, "as the one finding")
    Do $$$AssertEquals(result.window.days, 7, "the window is echoed")
    Do $$$AssertEquals(result.productionState, "unknown", "the state is unknown")
    Do $$$AssertEquals(result.caseAggregates.%GetTypeOf("_total"), "object", "the case aggregates still have a total")
}

/// The targets: Shutter's own production first and marked own; a pair that is none of them is not a target.
Method TestTargets()
{
    Set targets = ##class(Shutter.Review.Sweep).Targets()
    Do $$$AssertTrue(targets.%Size() >= 1, "at least Shutter's own production")
    Set own = targets.%Get(0)
    Do $$$AssertEquals(own.namespace, $NAMESPACE, "the first is this namespace")
    Do $$$AssertEquals(own.production, ##class(Shutter.Setup).ProductionName(), "and Shutter's production")
    Do $$$AssertTrue(own.own, "marked own")
    Do $$$AssertNotTrue(own.watched, "not watched")
    Do $$$AssertTrue(##class(Shutter.Review.Sweep).IsTarget($NAMESPACE, ##class(Shutter.Setup).ProductionName()), "IsTarget knows it")
    Do $$$AssertNotTrue(##class(Shutter.Review.Sweep).IsTarget("UTNOSUCHNAMESPACE", "UT.Production"), "and refuses a pair that is not one")
}

// ---- the fabricated data ----

/// The reader's empty shape for a fabricated production, with the class defaults the checks compare against (the
/// values the AI Hub build's dictionary gives).
ClassMethod Data() As %DynamicObject
{
    Set d = {}
    Set d.namespace = "UT", d.production = "UT.Production", d.productionState = "running"
    Set d.items = [], d.defaultSettings = []
    Set d.classDefaults = {
        "EnsLib.HL7.Operation.TCPOperation": {"FailureTimeout": "-1", "RetryInterval": "5", "ReplyCodeActions": "", "AlertOnError": "0", "AlertGroups": "", "QueueCountAlert": "0", "QueueWaitAlert": "0", "InactivityTimeout": "0", "ArchiveIO": "0", "Framing": "MLLP", "NoFailWhileDisconnected": ""},
        "EnsLib.HL7.Adapter.TCPOutboundAdapter": {"ResponseTimeout": "30", "IPAddress": "", "Port": ""},
        "EnsLib.HL7.Service.FileService": {"AlertOnError": "0", "AlertGroups": "", "InactivityTimeout": "0", "ArchiveIO": "0", "Framing": "Flexible"},
        "EnsLib.File.InboundAdapter": {},
        "EnsLib.HL7.Service.TCPService": {"AlertOnError": "0", "AlertGroups": "", "InactivityTimeout": "0", "ArchiveIO": "0", "Framing": "Flexible"},
        "EnsLib.HL7.Adapter.TCPInboundAdapter": {"Port": ""},
        "UT.Process": {"FailureTimeout": "15", "RetryInterval": "5", "ReplyCodeActions": "", "AlertOnError": "0", "AlertGroups": "", "QueueCountAlert": "0", "QueueWaitAlert": "0", "InactivityTimeout": "0"},
        "UT.Operation": {"FailureTimeout": "15", "RetryInterval": "5", "ReplyCodeActions": "", "AlertOnError": "0", "AlertGroups": "", "QueueCountAlert": "0", "QueueWaitAlert": "0", "InactivityTimeout": "0", "ArchiveIO": "0"},
        "EnsLib.HTTP.OutboundAdapter": {"ResponseTimeout": "30"},
        "Ens.Alert": {"AlertOnError": "0", "AlertGroups": "", "FailureTimeout": "15", "RetryInterval": "5"}
    }
    Do d.%Set("alertItemPresent", 0, "boolean")
    Set d.logErrors = [], d.headerErrors = [], d.queues = [], d.ruleErrors = []
    Set d.purgeTask = {"present": true, "suspended": false, "daysToKeep": 30, "bodiesToo": true, "keepIntegrity": true, "typesToPurge": "all", "lastFinished": ""}
    Set d.host = "uthost"
    Set d.readAt = ..#TO, d.error = ""
    Quit d
}

/// An item as the reader lists it; settings is {name: value}, every one a Host setting (the resolution reads by name).
ClassMethod Item(name As %String, class As %String, adapter As %String, type As %String, settings As %DynamicObject, category As %String = "Feed", enabled As %Boolean = 1, pool As %Integer = 1) As %DynamicObject
{
    Set o = {}
    Set o.name = name, o.className = class, o.adapterClassName = adapter, o.businessType = type
    Do o.%Set("enabled", enabled, "boolean")
    Set o.poolSize = pool, o.category = category, o.alertGroups = "", o.comment = ""
    Set list = []
    If $ISOBJECT(settings) {
        Set iter = settings.%GetIterator()
        While iter.%GetNext(.key, .value) {
            Set s = {}
            Set s.name = key, s.target = "Host", s.value = value
            Do list.%Push(s)
        }
    }
    Set o.settings = list
    Quit o
}

/// The hazardous production: every check has a subject.
ClassMethod Hazard() As %DynamicObject
{
    Set d = ..Data()
    Do d.items.%Push(..Item("Lab Out", "EnsLib.HL7.Operation.TCPOperation", "EnsLib.HL7.Adapter.TCPOutboundAdapter", "operation", {"FailureTimeout": "-1", "ReplyCodeActions": ":?E=C", "IPAddress": "127.0.0.1", "Port": "5000", "Framing": "MLLP"}, "Feed", 1, 2))
    Do d.items.%Push(..Item("Lab In", "EnsLib.HL7.Service.TCPService", "EnsLib.HL7.Adapter.TCPInboundAdapter", "service", {"Port": "5000", "Framing": "AsciiLF"}))
    Do d.items.%Push(..Item("ADT In", "EnsLib.HL7.Service.FileService", "EnsLib.File.InboundAdapter", "service", {"FileSpec": "*.hl7"}, "Feed", 0))
    Do d.items.%Push(..Item("ADT to Ward", "UT.Process", "", "process", {}))
    Do d.items.%Push(..Item("Ward Out", "UT.Operation", "EnsLib.HTTP.OutboundAdapter", "operation", {"FailureTimeout": "5", "ArchiveIO": "1"}))
    Do d.items.%Push(..Item("Pharmacy Out", "EnsLib.HL7.Operation.TCPOperation", "EnsLib.HL7.Adapter.TCPOutboundAdapter", "operation", {"FailureTimeout": "60", "IPAddress": "10.0.0.9", "Port": "6000"}))
    Do d.items.%Push(..Item("Agent Board", "UT.Operation", "", "operation", {}, "Board"))
    Set d.purgeTask = {"present": false, "suspended": false, "daysToKeep": null, "bodiesToo": null, "keepIntegrity": null, "typesToPurge": "", "lastFinished": ""}
    Set d.headerErrors = [
        {"target": "Lab Out", "source": "ADT to Ward", "status": 5, "count": 3, "latestId": "900", "latestAt": "2026-10-25T09:00:00Z"},
        {"target": "Ward Out", "source": "ADT to Ward", "status": 8, "count": 12, "latestId": "950", "latestAt": "2026-10-25T09:30:00Z"}
    ]
    Set d.logErrors = [
        {"configName": "ADT to Ward", "sourceClass": "Ens.Actor", "sourceMethod": "MessageHeaderHandler", "signature": "ERROR <Ens>ErrBPTerminated", "count": 12, "latestId": "700", "latestAt": "2026-10-25T09:30:00Z", "latestMessageId": "950", "exampleText": "ERROR <Ens>ErrBPTerminated: Terminating BP ADT to Ward # due to error: ERROR #5001: Delivery unavailable (ward_unavailable), HTTP 503"},
        {"configName": "Old Item", "sourceClass": "Ens.Actor", "sourceMethod": "MessageHeaderHandler", "signature": "ERROR <Ens>ErrException", "count": 1, "latestId": "710", "latestAt": "2026-10-24T09:30:00Z", "latestMessageId": "", "exampleText": "ERROR <Ens>ErrException: <UNDEFINED>zTransform+12^UT.Transform.1 *x"}
    ]
    Set d.queues = [
        {"name": "Lab Out", "count": 150, "created": "2026-10-25T09:00:00Z"},
        {"name": "Ward Out", "count": 1500, "created": "2026-10-25T09:00:00Z"},
        {"name": "Ens.Actor", "count": 0, "created": "2026-10-25T09:00:00Z"}
    ]
    Quit d
}

ClassMethod Window() As %DynamicObject
{
    Quit {"days": 7, "from": (..#FROM), "to": (..#TO)}
}

/// The first finding of a code about an item ("" for the production), or "".
ClassMethod Find(findings As %DynamicArray, code As %String, item As %String) As %DynamicObject
{
    Set iter = findings.%GetIterator()
    While iter.%GetNext(.i, .f) {
        If (f.code = code) && (f.item = item) Quit
    }
    If $ISOBJECT($GET(f)) && (f.code = code) && (f.item = item) Quit f
    Quit ""
}

/// The codes of a list of findings, with their items, for a message.
ClassMethod Codes(findings As %DynamicArray) As %String
{
    Set out = ""
    Set iter = findings.%GetIterator()
    While iter.%GetNext(.i, .f) {
        Set out = out _ $SELECT(out = "": "", 1: ", ") _ f.code _ $SELECT(f.item = "": "", 1: " (" _ f.item _ ")")
    }
    Quit out
}

/// The review's agent request carries the requester, for the budget's share (v1.39): the person who started the review,
/// else the feed's own "system".
Method TestAgentRequestCarriesTheRequester()
{
    Set r = ##class(Shutter.Store.Review).%New()
    Set r.ReviewId = "PR-TEST", r.Namespace = "SHUTTER", r.Production = "Shutter.Production"
    Set result = {"fingerprint": "sha256:0123456789abcdef", "productionState": "Running", "findings": [], "window": {}, "summary": {}, "caseAggregates": {}}
    Set req = ##class(Shutter.Process.Review).BuildAgentRequest(r, result, 3, 60000, "demo")
    Do $$$AssertTrue($ISOBJECT(req), "the request is built")
    Do $$$AssertEquals(req.RequestedBy, "demo", "the requester is the person who started the review")
    Do $$$AssertEquals(req.Role, "review", "the role is the review's")
    Set req = ##class(Shutter.Process.Review).BuildAgentRequest(r, result, 3, 60000)
    Do $$$AssertEquals(req.RequestedBy, "system", "nobody named means the feed's own run")
}

}
