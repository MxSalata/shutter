/// The site profile's validator (Shutter.Store.SiteProfile.Validate, CONTRACTS 6.4) for the approvers rules and the
/// mail rules, and CloseNeedsApprover, which reads the stored row: every row of the table in XData Rows patches the
/// shipped defaults (Default(); a patch is merged as Shutter.Test.Gate merges one, null removes a field) and names the
/// problem it expects, "" for a profile that passes. The validator is pure; the one test that stores a profile puts the
/// row back as it was.
Class Shutter.Test.SiteProfile Extends %UnitTest.TestCase
{

/// The stored site profile's text before a test changed it, and whether there was a stored row at all.
Property SavedProfile As %String;

Property ProfileChanged As %Boolean [ InitialExpression = 0 ];

Property HadProfileRow As %Boolean [ InitialExpression = 0 ];

Method OnAfterOneTest() As %Status
{
    Do ..RestoreProfile()
    Quit $$$OK
}

Method TestApprovers()
{
    Do ..RunRows("approvers")
}

Method TestMail()
{
    Do ..RunRows("mail")
}

Method TestTeamsNeedADomain()
{
    Do ..RunRows("teams")
}

/// The shipped defaults still pass, and so does the validator's SQL form.
Method TestDefaultProfileValidates()
{
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Validate(##class(Shutter.Store.SiteProfile).Default()), "", "the shipped defaults pass")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).ValidateJSON(##class(Shutter.Store.SiteProfile).Default().%ToJSON()), "ok", "and through SQL")
}

/// The shipped seed profile (knowledge/site/profile.json, read from the repository when the tests run from it) passes:
/// its teams need mail.allowed_domains.
Method TestSeedProfileValidates()
{
    Set path = $PIECE($GET(^UnitTestRoot), "tests/unit/", 1) _ "knowledge/site/profile.json"
    If ($GET(^UnitTestRoot) = "") || '##class(%File).Exists(path) {
        Do $$$LogMessage("knowledge/site/profile.json is not on the mounted path; the seed was not checked")
        Quit
    }
    Set p = ##class(Shutter.Util.Json).Parse(##class(Shutter.Knowledge.Text).ReadFile(path), .sc)
    Do $$$AssertStatusOK(sc, "the seed parses")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Validate(p), "", "the shipped seed profile passes the validator")
}

/// The receiver's category and history policy (v1.23): the validator's values, the derivation, and the deprecated
/// site-wide flag as the fallback for an entry with neither.
Method TestReceiverCategory()
{
    Set name = $PARAMETER("Shutter.Production", "RECEIVER")
    Set p = ##class(Shutter.Store.SiteProfile).Default()
    Do $$$AssertEquals(p.receivers.%Get(0).category, "current_state", "the default receiver is a current_state system")
    Set p.receivers.%Get(0).category = "warehouse"
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Validate(p), "receivers[0].category: must be current_state, history_of_record or orders_results", "an unknown category")
    Set p.receivers.%Get(0).category = "history_of_record", p.receivers.%Get(0)."history_policy" = "sometimes"
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Validate(p), "receivers[0].history_policy: must be current or correct", "an unknown policy")
    Do p.receivers.%Get(0).%Remove("history_policy")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Validate(p), "", "history_of_record passes")
    // Stored: the category derives the policy; an own policy overrides it; neither falls back to the site-wide flag.
    Do ..ChangeProfile({"receivers": [{"name": (name), "tier": 2, "category": "history_of_record"}], "history_policy": null})
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).ReceiverCategory(name), "history_of_record", "the stored category")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).ReceiverHistoryPolicy(name), "correct", "history_of_record keeps the history straight")
    Do ..ChangeProfile({"receivers": [{"name": (name), "tier": 2, "category": "history_of_record", "history_policy": "current"}]})
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).ReceiverHistoryPolicy(name), "current", "the entry's own policy wins")
    Do ..ChangeProfile({"receivers": [{"name": (name), "tier": 2}], "history_policy": "correct"})
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).ReceiverCategory(name), "current_state", "no category reads as current_state")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).ReceiverHistoryPolicy(name), "correct", "and the site-wide flag still answers for it")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).ReceiverCategory("Not A Receiver"), "current_state", "an unnamed receiver is current_state")
}

/// The two-person rule's reader: on only for a stored true.
Method TestCloseNeedsApprover()
{
    Do ..ChangeProfile({"approvers": {"close_needs_approver": true}})
    Do $$$AssertTrue(##class(Shutter.Store.SiteProfile).CloseNeedsApprover(), "true reads as on")
    Do ..ChangeProfile({"approvers": {"close_needs_approver": false}})
    Do $$$AssertNotTrue(##class(Shutter.Store.SiteProfile).CloseNeedsApprover(), "false reads as off")
    Do ..ChangeProfile({"approvers": {"close_needs_approver": null}})
    Do $$$AssertNotTrue(##class(Shutter.Store.SiteProfile).CloseNeedsApprover(), "an absent answer reads as off")
    Do ..ChangeProfile({"approvers": null})
    Do $$$AssertNotTrue(##class(Shutter.Store.SiteProfile).CloseNeedsApprover(), "no approvers at all reads as off")
    Set before = ..SavedProfile, had = ..HadProfileRow
    Do ..RestoreProfile()
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    Do $$$AssertEquals($ISOBJECT(row), had, "the stored row is as it was: " _ $SELECT(had: "present", 1: "absent"))
    If had Do $$$AssertEquals(row.Json, before, "with its text")
}

/// Runs every row of a group: the defaults patched, the problem expected.
Method RunRows(group As %String)
{
    Set n = 0
    Set iter = ..Rows().%GetIterator()
    While iter.%GetNext(.i, .row) {
        Continue:row.group'=group
        Set n = n + 1
        Set p = ##class(Shutter.Store.SiteProfile).Default()
        Do ..Merge(p, row.patch)
        Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Validate(p), row.expect, row.name)
    }
    Do $$$AssertTrue(n > 0, "the group " _ group _ " has rows")
}

/// Changes the stored site profile for one test, keeping its version; the patch is merged at the top level.
Method ChangeProfile(patch As %DynamicObject)
{
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    If '..ProfileChanged {
        Set ..HadProfileRow = $ISOBJECT(row), ..SavedProfile = $SELECT($ISOBJECT(row): row.Json, 1: ""), ..ProfileChanged = 1
    }
    Set p = ##class(Shutter.Store.SiteProfile).Current()
    Set version = +p.version
    Do p.%Remove("version")
    Do ..Merge(p, patch)
    If '$ISOBJECT(row) Set row = ##class(Shutter.Store.SiteProfile).%New(), row.Version = version
    Set row.Json = p.%ToJSON()
    Do $$$AssertStatusOK(row.%Save(), "the site profile is changed for the test")
}

Method RestoreProfile()
{
    Quit:'..ProfileChanged
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    If '..HadProfileRow {
        If $ISOBJECT(row) Do ##class(Shutter.Store.SiteProfile).%DeleteId(row.%Id())
    } ElseIf $ISOBJECT(row) {
        Set row.Json = ..SavedProfile
        Do row.%Save()
    }
    Set ..ProfileChanged = 0
}

ClassMethod Merge(target As %DynamicObject, patch As %DynamicObject)
{
    Set iter = patch.%GetIterator()
    While iter.%GetNext(.k, .v) {
        Set type = patch.%GetTypeOf(k)
        If type = "null" {
            Do target.%Remove(k)
        } ElseIf (type = "object") && (target.%GetTypeOf(k) = "object") {
            Do ..Merge(target.%Get(k), v)
        } ElseIf type = "boolean" {
            Do target.%Set(k, v, "boolean")
        } Else {
            Do target.%Set(k, v)
        }
    }
}

ClassMethod Rows() As %DynamicArray
{
    Set xdata = ##class(%Dictionary.CompiledXData).%OpenId($CLASSNAME() _ "||Rows")
    Quit ##class(%DynamicArray).%FromJSON(xdata.Data)
}

/// The table: group, name, the patch merged into the defaults, and the problem expected.
XData Rows [ MimeType = application/json ]
{
[
 {"group": "approvers", "name": "a misspelt switch is refused, not read as off", "patch": {"approvers": {"close_needs_aprover": true}}, "expect": "approvers.close_needs_aprover: unknown setting"},
 {"group": "approvers", "name": "the switch must be true or false", "patch": {"approvers": {"close_needs_approver": "yes"}}, "expect": "approvers.close_needs_approver: must be true or false"},
 {"group": "approvers", "name": "the role must be a string", "patch": {"approvers": {"role": 5}}, "expect": "approvers.role: must be a string"},
 {"group": "approvers", "name": "the escalation text must be a string", "patch": {"approvers": {"escalation": false}}, "expect": "approvers.escalation: must be a string"},
 {"group": "approvers", "name": "an array is not an object", "patch": {"approvers": []}, "expect": "approvers: must be an object"},
 {"group": "approvers", "name": "the three keys pass", "patch": {"approvers": {"role": "Shutter Approvers", "escalation": "the on-call", "close_needs_approver": true}}, "expect": ""},
 {"group": "approvers", "name": "no approvers at all passes", "patch": {"approvers": null}, "expect": ""},
 {"group": "mail", "name": "a header injected in the sender", "patch": {"mail": {"allowed_domains": ["example.nhs.uk"], "from": "x\r\nBcc: e@evil.com"}}, "expect": "mail.from: must not contain line breaks or control characters"},
 {"group": "mail", "name": "a sender with a display name", "patch": {"mail": {"from": "Shutter <shutter@example.nhs.uk>"}}, "expect": "mail.from: must be a bare address, local@domain, with no display name, brackets or spaces"},
 {"group": "mail", "name": "a bare sender passes", "patch": {"mail": {"from": "shutter@example.nhs.uk"}}, "expect": ""},
 {"group": "mail", "name": "an empty sender passes", "patch": {"mail": {"from": ""}}, "expect": ""},
 {"group": "mail", "name": "a domain entry with an @", "patch": {"mail": {"allowed_domains": ["@nhs.net"]}}, "expect": "mail.allowed_domains[0]: must be a domain name such as example.nhs.uk (letters, digits, hyphens and dots)"},
 {"group": "mail", "name": "a domain entry with a space", "patch": {"mail": {"allowed_domains": ["example.nhs.uk", " x"]}}, "expect": "mail.allowed_domains[1]: must be a domain name such as example.nhs.uk (letters, digits, hyphens and dots)"},
 {"group": "mail", "name": "an empty domain entry", "patch": {"mail": {"allowed_domains": [""]}}, "expect": "mail.allowed_domains[0]: must be a domain"},
 {"group": "mail", "name": "domains with no teams pass", "patch": {"mail": {"allowed_domains": ["example.nhs.uk", "NHS.NET"]}}, "expect": ""},
 {"group": "teams", "name": "a team mailbox with no mail key", "patch": {"teams": [{"id": "pas", "name": "PAS team", "mailbox": "pas@example.nhs.uk"}]}, "expect": "teams[0].mailbox: no allowed mail domains are set in the site profile (mail.allowed_domains)"},
 {"group": "teams", "name": "a team mailbox with an empty list", "patch": {"mail": {"allowed_domains": []}, "teams": [{"id": "pas", "name": "PAS team", "mailbox": "pas@example.nhs.uk"}]}, "expect": "teams[0].mailbox: no allowed mail domains are set in the site profile (mail.allowed_domains)"},
 {"group": "teams", "name": "a team mailbox inside the domains", "patch": {"mail": {"allowed_domains": ["example.nhs.uk"]}, "teams": [{"id": "pas", "name": "PAS team", "mailbox": "pas@example.nhs.uk", "cc": ["oncall@trust.example.nhs.uk"]}]}, "expect": ""},
 {"group": "teams", "name": "a second @ in a mailbox", "patch": {"mail": {"allowed_domains": ["example.nhs.uk"]}, "teams": [{"id": "pas", "name": "PAS team", "mailbox": "a@example.nhs.uk@evil.com"}]}, "expect": "teams[0].mailbox: must be one address with one @"},
 {"group": "teams", "name": "a mailbox outside the domains", "patch": {"mail": {"allowed_domains": ["example.nhs.uk"]}, "teams": [{"id": "pas", "name": "PAS team", "mailbox": "a@evil.com"}]}, "expect": "teams[0].mailbox: not in the allowed domains"},
 {"group": "teams", "name": "a cc outside the domains", "patch": {"mail": {"allowed_domains": ["example.nhs.uk"]}, "teams": [{"id": "pas", "name": "PAS team", "mailbox": "pas@example.nhs.uk", "cc": ["b@evil.com"]}]}, "expect": "teams[0].cc[0]: not in the allowed domains"},
 {"group": "teams", "name": "no teams and no mail pass", "patch": {}, "expect": ""}
]
}

}
