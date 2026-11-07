/// What a receiver's entry may say about its outages (Shutter.Store.SiteProfile.ReceiverWatchProblem, CONTRACTS 6.4). XData
/// Rows is one table for both validators: each row adds its keys to one bare receiver, and optionally to the profile, and
/// names the problem it expects, "" for a profile that passes. web/src/features/site-profile/profile.test.ts reads the same
/// table from this file, so the two validators agree word for word or one suite fails.
Class Shutter.Test.ProfileWatch Extends %UnitTest.TestCase
{

/// The stored row before a test changed it, and whether there was one.
Property Changed As %Boolean [ InitialExpression = 0 ];

Property HadRow As %Boolean [ InitialExpression = 0 ];

Property SavedJson As %String(MAXLEN = "");

Property SavedSource As %String(MAXLEN = 500);

Property SavedVersion As %Integer;

Method OnAfterOneTest() As %Status
{
    Do ..PutBack()
    Quit $$$OK
}

/// Every row of the table.
Method TestRows()
{
    Set n = 0
    Set iter = ..Rows().%GetIterator()
    While iter.%GetNext(.i, .row) {
        Set n = n + 1
        Set p = {"receivers": [{"name": "R", "tier": 2}], "policy": {}}
        Do ..Add(p.receivers.%Get(0), row.receiver)
        If row.%IsDefined("top") Do ..Add(p, row.top)
        Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Validate(p), row.expect, row.name)
    }
    Do $$$AssertTrue(n > 60, "the table has its rows, " _ n)
}

/// A profile with none of these keys validates as it did: the shipped defaults, and the same entry with its keys gone.
Method TestAProfileWithoutThemIsUnmoved()
{
    Set p = ##class(Shutter.Store.SiteProfile).Default()
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Validate(p), "", "the shipped defaults pass")
    Set r = p.receivers.%Get(0)
    For k = "watch", "runbook", "call", "approvers", "ack_level", "duplicates", "engine_resend", "hold", "mail", "resend_approval_minutes", "settle_minutes", "window_minutes" {
        Do $$$AssertTrue('r.%IsDefined(k), "the shipped receiver has no " _ k)
    }
    Set path = $PIECE($GET(^UnitTestRoot), "tests/unit/", 1) _ "knowledge/site/profile.json"
    If ($GET(^UnitTestRoot) = "") || '##class(%File).Exists(path) {
        Do $$$LogMessage("knowledge/site/profile.json is not on the mounted path; the seed was not checked")
        Quit
    }
    Set seed = ##class(Shutter.Util.Json).Parse(##class(Shutter.Knowledge.Text).ReadFile(path), .sc)
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Validate(seed), "", "the shipped seed passes")
    Set iter = seed.receivers.%GetIterator()
    While iter.%GetNext(.i, .entry) { Do $$$AssertTrue('entry.%IsDefined("watch"), "the seed watches nothing: " _ entry.name) }
}

/// A profile a person saved, with these keys in it, is never overwritten by the seed.
Method TestASavedProfileOutlivesTheSeed()
{
    Set p = ##class(Shutter.Store.SiteProfile).Default()
    Set r = p.receivers.%Get(0)
    Set r.watch = {"namespace": "LAB", "item": "Lims Out"}, r.runbook = "Check the listener", r.call = "Lab desk, 01632 960000"
    Do ..Stored(p, "api")
    Set before = ##class(Shutter.Store.SiteProfile).Row()
    Set json = before.Json, version = before.Version
    Set path = ##class(%File).TempFilename("json")
    Set file = ##class(%Stream.FileCharacter).%New()
    Do $$$AssertStatusOK(file.LinkToFile(path), "the seed file is linked")
    Do file.Write(##class(Shutter.Store.SiteProfile).Default().%ToJSON())
    Do $$$AssertStatusOK(file.%Save(), "the seed file is written")
    Do $$$AssertStatusOK(##class(Shutter.Store.SiteProfile).SeedFromFile(path), "the seed runs")
    Do ##class(%File).Delete(path)
    Set after = ##class(Shutter.Store.SiteProfile).Row()
    Do $$$AssertEquals(after.Json, json, "the saved profile's text is unmoved")
    Do $$$AssertEquals(after.Version, version, "and its version")
    Do $$$AssertEquals(after.Source, "api", "and its source")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).WatchedReceivers().%Size(), 1, "the saved watch block is what's read")
}

/// The readers give the design's defaults when an entry doesn't say, and the entry's own figure when it does.
Method TestReaders()
{
    Set class = "Shutter.Store.SiteProfile"
    Set p = $CLASSMETHOD(class, "Default")
    Do p.receivers.%Push({"name": "Bare", "tier": 2})
    Do p.receivers.%Push({"name": "Said", "tier": 2, "watch": {"namespace": "LAB", "item": "Said Out"}, "ack_level": "application", "duplicates": {"behaviour": "refuses", "phrase": "ALREADY HELD", "refers_to": "order"}, "hold": {"minutes": 25}, "resend_approval_minutes": 7, "settle_minutes": 8, "window_minutes": 9})
    Do p.receivers.%Push({"name": "Hold default", "tier": 2, "hold": {}})
    Do p.receivers.%Push({"name": "Lab", "tier": 3, "category": "orders_results"})
    Do ..Stored(p, "api")
    Do $$$AssertEquals($CLASSMETHOD(class, "WatchedReceivers").%Size(), 1, "one receiver is watched")
    Do $$$AssertEquals($CLASSMETHOD(class, "WatchedReceivers").%Get(0).name, "Said", "the one with a watch block")
    Do $$$AssertEquals($CLASSMETHOD(class, "ReceiverAckLevel", "Bare"), "connection", "no declaration reads connection")
    Do $$$AssertEquals($CLASSMETHOD(class, "ReceiverAckLevel", "Said"), "application", "a declaration is read")
    Do $$$AssertEquals($CLASSMETHOD(class, "ReceiverAckLevel", "Nobody"), "connection", "an unnamed receiver reads connection")
    Set d = $CLASSMETHOD(class, "ReceiverDuplicates", "Bare")
    Do $$$AssertEquals(d.behaviour _ "/" _ d."refers_to", "unknown/unknown", "no declaration reads unknown")
    Set d = $CLASSMETHOD(class, "ReceiverDuplicates", "Said")
    Do $$$AssertEquals(d.behaviour _ "/" _ d."refers_to" _ "/" _ d.phrase, "refuses/order/ALREADY HELD", "a declaration is read")
    Do $$$AssertEquals($CLASSMETHOD(class, "ReceiverMinutes", "Bare", "resend_approval_minutes"), 15, "the approval's default")
    Do $$$AssertEquals($CLASSMETHOD(class, "ReceiverMinutes", "Bare", "settle_minutes"), 10, "the settling default")
    Do $$$AssertEquals($CLASSMETHOD(class, "ReceiverMinutes", "Bare", "window_minutes"), 5, "the window's default")
    Do $$$AssertEquals($CLASSMETHOD(class, "ReceiverMinutes", "Said", "resend_approval_minutes"), 7, "the entry's own approval")
    Do $$$AssertEquals($CLASSMETHOD(class, "ReceiverMinutes", "Said", "settle_minutes"), 8, "the entry's own settling")
    Do $$$AssertEquals($CLASSMETHOD(class, "ReceiverMinutes", "Said", "window_minutes"), 9, "the entry's own window")
    Do $$$AssertEquals($CLASSMETHOD(class, "ReceiverHoldMinutes", "Bare"), 0, "no block, no hold")
    Do $$$AssertEquals($CLASSMETHOD(class, "ReceiverHoldMinutes", "Said"), 25, "the block's minutes")
    Do $$$AssertEquals($CLASSMETHOD(class, "ReceiverHoldMinutes", "Hold default"), 10, "a block without minutes holds for 10")
    Do $$$AssertEquals($CLASSMETHOD(class, "ReceiverHoldMinutes", "Lab"), 0, "never on orders_results")
}

/// A stored profile for one test, written directly so no store's side effects run.
Method Stored(p As %DynamicObject, source As %String)
{
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    If '..Changed {
        Set ..Changed = 1, ..HadRow = $ISOBJECT(row)
        If ..HadRow Set ..SavedJson = row.Json, ..SavedSource = row.Source, ..SavedVersion = row.Version
    }
    If '$ISOBJECT(row) Set row = ##class(Shutter.Store.SiteProfile).%New()
    Set row.Json = p.%ToJSON(), row.Source = source
    Do $$$AssertStatusOK(row.%Save(), "the profile is stored for the test")
}

Method PutBack()
{
    Quit:'..Changed
    Set ..Changed = 0
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    If '..HadRow {
        If $ISOBJECT(row) Do ##class(Shutter.Store.SiteProfile).%DeleteId(row.%Id())
        Quit
    }
    If '$ISOBJECT(row) Set row = ##class(Shutter.Store.SiteProfile).%New()
    Set row.Json = ..SavedJson, row.Source = ..SavedSource, row.Version = ..SavedVersion
    Do $$$AssertStatusOK(row.%Save(), "the stored profile is put back")
}

ClassMethod Add(target As %DynamicObject, keys As %DynamicObject)
{
    Set iter = keys.%GetIterator()
    While iter.%GetNext(.k, .v) {
        Set type = keys.%GetTypeOf(k)
        If $LISTFIND($LISTBUILD("boolean", "number", "string"), type) { Do target.%Set(k, v, type) } Else { Do target.%Set(k, v) }
    }
}

ClassMethod Rows() As %DynamicArray
{
    Set xdata = ##class(%Dictionary.CompiledXData).%OpenId($CLASSNAME() _ "||Rows")
    Quit ##class(%DynamicAbstractObject).%FromJSON(xdata.Data)
}

XData Rows [ MimeType = application/json ]
{
[
 {"name": "a bare entry passes", "receiver": {}, "expect": ""},
 {"name": "watch with both keys", "receiver": {"watch": {"namespace": "LAB", "item": "Lims Out"}}, "expect": ""},
 {"name": "watch as text", "receiver": {"watch": "Lims Out"}, "expect": "receivers[0].watch: must be an object"},
 {"name": "watch as a list", "receiver": {"watch": []}, "expect": "receivers[0].watch: must be an object"},
 {"name": "watch with no namespace", "receiver": {"watch": {"item": "Lims Out"}}, "expect": "receivers[0].watch.namespace: required"},
 {"name": "watch with no item", "receiver": {"watch": {"namespace": "LAB"}}, "expect": "receivers[0].watch.item: required"},
 {"name": "watch with an empty item", "receiver": {"watch": {"namespace": "LAB", "item": ""}}, "expect": "receivers[0].watch.item: required"},
 {"name": "watch with a number for its namespace", "receiver": {"watch": {"namespace": 5, "item": "Lims Out"}}, "expect": "receivers[0].watch.namespace: required"},
 {"name": "watch with a misspelt key", "receiver": {"watch": {"namespace": "LAB", "items": "Lims Out"}}, "expect": "receivers[0].watch.items: unknown setting"},
 {"name": "a runbook", "receiver": {"runbook": "Check the listener, then the switch"}, "expect": ""},
 {"name": "a runbook as a number", "receiver": {"runbook": 5}, "expect": "receivers[0].runbook: must be a string"},
 {"name": "who to call", "receiver": {"call": "Lab desk, 01632 960000"}, "expect": ""},
 {"name": "who to call as a list", "receiver": {"call": ["Lab desk"]}, "expect": "receivers[0].call: must be a string"},
 {"name": "approvers named", "receiver": {"approvers": ["Lab manager", "Duty biomedical scientist"]}, "expect": ""},
 {"name": "approvers as text", "receiver": {"approvers": "Lab manager"}, "expect": "receivers[0].approvers: must be an array of names"},
 {"name": "approvers holding an empty name", "receiver": {"approvers": ["Lab manager", ""]}, "expect": "receivers[0].approvers[1]: must be a name"},
 {"name": "approvers holding a number", "receiver": {"approvers": [5]}, "expect": "receivers[0].approvers[0]: must be a name"},
 {"name": "ack_level connection", "receiver": {"ack_level": "connection"}, "expect": ""},
 {"name": "ack_level commit", "receiver": {"ack_level": "commit"}, "expect": ""},
 {"name": "ack_level application", "receiver": {"ack_level": "application"}, "expect": ""},
 {"name": "ack_level on an orders receiver", "receiver": {"category": "orders_results", "ack_level": "application"}, "expect": ""},
 {"name": "ack_level on a history receiver", "receiver": {"category": "history_of_record", "ack_level": "commit"}, "expect": ""},
 {"name": "ack_level misspelt", "receiver": {"ack_level": "app"}, "expect": "receivers[0].ack_level: must be connection, commit or application"},
 {"name": "ack_level as a number", "receiver": {"ack_level": 1}, "expect": "receivers[0].ack_level: must be connection, commit or application"},
 {"name": "duplicates refused by code", "receiver": {"duplicates": {"behaviour": "refuses", "code": "205"}}, "expect": ""},
 {"name": "duplicates refused by phrase", "receiver": {"duplicates": {"behaviour": "refuses", "phrase": "ALREADY HELD"}}, "expect": ""},
 {"name": "duplicates filed twice", "receiver": {"duplicates": {"behaviour": "files_twice"}}, "expect": ""},
 {"name": "duplicates unknown", "receiver": {"duplicates": {"behaviour": "unknown"}}, "expect": ""},
 {"name": "duplicates saying nothing", "receiver": {"duplicates": {}}, "expect": ""},
 {"name": "refers_to message", "receiver": {"duplicates": {"behaviour": "unknown", "refers_to": "message"}}, "expect": ""},
 {"name": "refers_to order", "receiver": {"duplicates": {"behaviour": "unknown", "refers_to": "order"}}, "expect": ""},
 {"name": "refers_to result", "receiver": {"duplicates": {"behaviour": "unknown", "refers_to": "result"}}, "expect": ""},
 {"name": "refers_to unknown", "receiver": {"duplicates": {"behaviour": "unknown", "refers_to": "unknown"}}, "expect": ""},
 {"name": "refers_to anything else", "receiver": {"duplicates": {"refers_to": "specimen"}}, "expect": "receivers[0].duplicates.refers_to: must be message, order, result or unknown"},
 {"name": "refers_to as a number", "receiver": {"duplicates": {"refers_to": 1}}, "expect": "receivers[0].duplicates.refers_to: must be message, order, result or unknown"},
 {"name": "duplicates as text", "receiver": {"duplicates": "refuses"}, "expect": "receivers[0].duplicates: must be an object"},
 {"name": "duplicates with an unknown behaviour", "receiver": {"duplicates": {"behaviour": "ignores"}}, "expect": "receivers[0].duplicates.behaviour: must be refuses, files_twice or unknown"},
 {"name": "duplicates with a misspelt key", "receiver": {"duplicates": {"words": "ALREADY HELD"}}, "expect": "receivers[0].duplicates.words: unknown setting"},
 {"name": "a code as a number", "receiver": {"duplicates": {"behaviour": "refuses", "code": 205}}, "expect": "receivers[0].duplicates.code: must be a string"},
 {"name": "a phrase as a list", "receiver": {"duplicates": {"behaviour": "refuses", "phrase": ["ALREADY HELD"]}}, "expect": "receivers[0].duplicates.phrase: must be a string"},
 {"name": "refuses with nothing to match", "receiver": {"duplicates": {"behaviour": "refuses"}}, "expect": "receivers[0].duplicates.behaviour: refuses needs a code or a phrase"},
 {"name": "refuses with an empty phrase", "receiver": {"duplicates": {"behaviour": "refuses", "phrase": ""}}, "expect": "receivers[0].duplicates.behaviour: refuses needs a code or a phrase"},
 {"name": "engine_resend on orders and results", "receiver": {"category": "orders_results", "engine_resend": true}, "expect": ""},
 {"name": "engine_resend on current_state with application", "receiver": {"category": "current_state", "ack_level": "application", "engine_resend": true}, "expect": ""},
 {"name": "engine_resend on history_of_record with application", "receiver": {"category": "history_of_record", "ack_level": "application", "engine_resend": true}, "expect": ""},
 {"name": "engine_resend with no category and application", "receiver": {"ack_level": "application", "engine_resend": true}, "expect": ""},
 {"name": "engine_resend on current_state with commit", "receiver": {"category": "current_state", "ack_level": "commit", "engine_resend": true}, "expect": "receivers[0].engine_resend: needs ack_level application on a current_state or history_of_record receiver"},
 {"name": "engine_resend on current_state with connection", "receiver": {"category": "current_state", "ack_level": "connection", "engine_resend": true}, "expect": "receivers[0].engine_resend: needs ack_level application on a current_state or history_of_record receiver"},
 {"name": "engine_resend on current_state with no level", "receiver": {"category": "current_state", "engine_resend": true}, "expect": "receivers[0].engine_resend: needs ack_level application on a current_state or history_of_record receiver"},
 {"name": "engine_resend on history_of_record with no level", "receiver": {"category": "history_of_record", "engine_resend": true}, "expect": "receivers[0].engine_resend: needs ack_level application on a current_state or history_of_record receiver"},
 {"name": "engine_resend with no category and no level", "receiver": {"engine_resend": true}, "expect": "receivers[0].engine_resend: needs ack_level application on a current_state or history_of_record receiver"},
 {"name": "engine_resend beside rewritten", "receiver": {"category": "orders_results", "resend_timestamp": "rewritten", "engine_resend": true}, "expect": "receivers[0].engine_resend: refused beside resend_timestamp rewritten, since the stored message goes out unchanged"},
 {"name": "engine_resend beside the questionnaire's fresh", "receiver": {"category": "orders_results", "resend_timestamp": "fresh", "engine_resend": true}, "expect": "receivers[0].engine_resend: refused beside resend_timestamp rewritten, since the stored message goes out unchanged"},
 {"name": "engine_resend beside rewritten with application", "receiver": {"ack_level": "application", "resend_timestamp": "rewritten", "engine_resend": true}, "expect": "receivers[0].engine_resend: refused beside resend_timestamp rewritten, since the stored message goes out unchanged"},
 {"name": "engine_resend beside original", "receiver": {"category": "orders_results", "resend_timestamp": "original", "engine_resend": true}, "expect": ""},
 {"name": "engine_resend off, wherever", "receiver": {"category": "current_state", "resend_timestamp": "fresh", "engine_resend": false}, "expect": ""},
 {"name": "engine_resend as text", "receiver": {"category": "orders_results", "engine_resend": "yes"}, "expect": "receivers[0].engine_resend: must be true or false"},
 {"name": "engine_resend as a number", "receiver": {"category": "orders_results", "engine_resend": 1}, "expect": "receivers[0].engine_resend: must be true or false"},
 {"name": "hold on current_state at 10", "receiver": {"category": "current_state", "hold": {"minutes": 10}}, "expect": ""},
 {"name": "hold on history_of_record at 10", "receiver": {"category": "history_of_record", "hold": {"minutes": 10}}, "expect": ""},
 {"name": "hold with no category", "receiver": {"hold": {"minutes": 10}}, "expect": ""},
 {"name": "hold at the lower bound", "receiver": {"hold": {"minutes": 1}}, "expect": ""},
 {"name": "hold at the upper bound", "receiver": {"hold": {"minutes": 60}}, "expect": ""},
 {"name": "hold taking its default", "receiver": {"hold": {}}, "expect": ""},
 {"name": "hold on orders and results", "receiver": {"category": "orders_results", "hold": {"minutes": 10}}, "expect": "receivers[0].hold: is for ADT receivers only, not orders_results"},
 {"name": "hold at 0", "receiver": {"hold": {"minutes": 0}}, "expect": "receivers[0].hold.minutes: must be a whole number from 1 to 60"},
 {"name": "hold at 61", "receiver": {"hold": {"minutes": 61}}, "expect": "receivers[0].hold.minutes: must be a whole number from 1 to 60"},
 {"name": "hold at a part of a minute", "receiver": {"hold": {"minutes": 1.5}}, "expect": "receivers[0].hold.minutes: must be a whole number from 1 to 60"},
 {"name": "hold minutes as text", "receiver": {"hold": {"minutes": "10"}}, "expect": "receivers[0].hold.minutes: must be a whole number from 1 to 60"},
 {"name": "hold as a switch", "receiver": {"hold": true}, "expect": "receivers[0].hold: must be an object"},
 {"name": "hold with a misspelt key", "receiver": {"hold": {"minute": 10}}, "expect": "receivers[0].hold.minute: unknown setting"},
 {"name": "mail with addresses and states", "receiver": {"mail": {"to": ["lab.desk@example.nhs.uk", "oncall@lab.example.nhs.uk"], "on": ["open", "needs_person", "closed"]}}, "top": {"mail": {"allowed_domains": ["example.nhs.uk"]}}, "expect": ""},
 {"name": "mail on one state", "receiver": {"mail": {"to": ["lab.desk@example.nhs.uk"], "on": ["closed"]}}, "top": {"mail": {"allowed_domains": ["example.nhs.uk"]}}, "expect": ""},
 {"name": "mail with an unknown state", "receiver": {"mail": {"to": ["lab.desk@example.nhs.uk"], "on": ["open", "drained"]}}, "top": {"mail": {"allowed_domains": ["example.nhs.uk"]}}, "expect": "receivers[0].mail.on[1]: must be open, needs_person or closed"},
 {"name": "mail with a number for a state", "receiver": {"mail": {"to": ["lab.desk@example.nhs.uk"], "on": [1]}}, "top": {"mail": {"allowed_domains": ["example.nhs.uk"]}}, "expect": "receivers[0].mail.on[0]: must be open, needs_person or closed"},
 {"name": "mail with no states", "receiver": {"mail": {"to": ["lab.desk@example.nhs.uk"]}}, "top": {"mail": {"allowed_domains": ["example.nhs.uk"]}}, "expect": "receivers[0].mail.on: must be an array of one or more of open, needs_person and closed"},
 {"name": "mail with an empty list of states", "receiver": {"mail": {"to": ["lab.desk@example.nhs.uk"], "on": []}}, "top": {"mail": {"allowed_domains": ["example.nhs.uk"]}}, "expect": "receivers[0].mail.on: must be an array of one or more of open, needs_person and closed"},
 {"name": "mail with no addresses", "receiver": {"mail": {"on": ["open"]}}, "expect": "receivers[0].mail.to: must be an array of one or more addresses"},
 {"name": "mail with one address as text", "receiver": {"mail": {"to": "lab.desk@example.nhs.uk", "on": ["open"]}}, "expect": "receivers[0].mail.to: must be an array of one or more addresses"},
 {"name": "mail with an empty list of addresses", "receiver": {"mail": {"to": [], "on": ["open"]}}, "expect": "receivers[0].mail.to: must be an array of one or more addresses"},
 {"name": "mail with a number for an address", "receiver": {"mail": {"to": [5], "on": ["open"]}}, "expect": "receivers[0].mail.to[0]: must be an address"},
 {"name": "mail outside the allowed domains", "receiver": {"mail": {"to": ["someone@elsewhere.example"], "on": ["open"]}}, "top": {"mail": {"allowed_domains": ["example.nhs.uk"]}}, "expect": "receivers[0].mail.to[0]: not in the allowed domains"},
 {"name": "mail with no allowed domains", "receiver": {"mail": {"to": ["lab.desk@example.nhs.uk"], "on": ["open"]}}, "expect": "receivers[0].mail.to[0]: no allowed mail domains are set in the site profile (mail.allowed_domains)"},
 {"name": "mail with a display name", "receiver": {"mail": {"to": ["Lab <lab.desk@example.nhs.uk>"], "on": ["open"]}}, "top": {"mail": {"allowed_domains": ["example.nhs.uk"]}}, "expect": "receivers[0].mail.to[0]: must be a bare address, local@domain, with no display name, brackets or spaces"},
 {"name": "mail as a list", "receiver": {"mail": ["lab.desk@example.nhs.uk"]}, "expect": "receivers[0].mail: must be an object"},
 {"name": "mail with a misspelt key", "receiver": {"mail": {"cc": []}}, "expect": "receivers[0].mail.cc: unknown setting"},
 {"name": "the approval's minutes", "receiver": {"resend_approval_minutes": 15}, "expect": ""},
 {"name": "the approval at 0", "receiver": {"resend_approval_minutes": 0}, "expect": "receivers[0].resend_approval_minutes: must be a whole number of 1 or more"},
 {"name": "the approval as text", "receiver": {"resend_approval_minutes": "15"}, "expect": "receivers[0].resend_approval_minutes: must be a whole number of 1 or more"},
 {"name": "the settling minutes", "receiver": {"settle_minutes": 10}, "expect": ""},
 {"name": "the settling at a part of a minute", "receiver": {"settle_minutes": 0.5}, "expect": "receivers[0].settle_minutes: must be a whole number of 1 or more"},
 {"name": "the settling as a switch", "receiver": {"settle_minutes": true}, "expect": "receivers[0].settle_minutes: must be a whole number of 1 or more"},
 {"name": "the window's minutes", "receiver": {"window_minutes": 5}, "expect": ""},
 {"name": "the window below zero", "receiver": {"window_minutes": -5}, "expect": "receivers[0].window_minutes: must be a whole number of 1 or more"},
 {"name": "every key at once, on one entry", "receiver": {"watch": {"namespace": "LAB", "item": "Lims Out"}, "runbook": "Check the listener", "call": "Lab desk", "approvers": ["Lab manager"], "ack_level": "application", "duplicates": {"behaviour": "refuses", "code": "205", "phrase": "ALREADY HELD", "refers_to": "order"}, "engine_resend": true, "hold": {"minutes": 10}, "resend_approval_minutes": 15, "settle_minutes": 10, "window_minutes": 5}, "expect": ""}
]
}

}
