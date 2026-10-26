/// The deterministic card (Shutter.Util.WhatIf; CONTRACTS 14.1): a change is validated against the current site profile by
/// applying it to a copy, and a case without evidence has no facts. Nothing here writes the profile.
Class Shutter.Test.WhatIf Extends %UnitTest.TestCase
{

Parameter CASEID = "UT-W-0001";

Property CaseRowId As %String;

Method OnBeforeOneTest(testname As %String) As %Status
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Shutter_Store.""Case"" WHERE CaseId = ?", ..#CASEID)
    While rs.%Next() { If ##class(Shutter.Store.Case).%ExistsId(rs.%Get("ID")) Do ##class(Shutter.Store.Case).%DeleteId(rs.%Get("ID")) }
    Set c = ##class(Shutter.Store.Case).%New()
    Set c.CaseId = ..#CASEID, c.OperationKey = "PAS^HOSP^MRN9008^ENC-9008^transfer^2026-10-15T08:20:00Z"
    Set c.Event = "transfer", c.EncounterId = "ENC-9008", c.PatientId = "MRN9008", c.FailureKind = "delivery_failed"
    Set c.State = "collecting", c.Receiver = "Downstream Out"
    Set c.OpenedAt = "2026-10-20T10:00:00Z", c.UpdatedAt = c.OpenedAt
    Set sc = c.%Save()
    Quit:$$$ISERR(sc) sc
    Set ..CaseRowId = c.%Id()
    Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
    Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.CaseEvent WHERE ""Case"" = ?", ..CaseRowId)
    Kill ^Shutter.Counter("event", ..CaseRowId)
    If ##class(Shutter.Store.Case).%ExistsId(..CaseRowId) Do ##class(Shutter.Store.Case).%DeleteId(..CaseRowId)
    Quit $$$OK
}

/// A change to a receiver's category, the site's authoritative source or a policy cell passes the validator on a copy; a field
/// outside the list, an unknown receiver and a value the schema refuses are named.
Method TestValidateChange()
{
    Set profile = ##class(Shutter.Store.SiteProfile).Current()
    Do $$$AssertTrue($ISOBJECT(profile), "a profile is seeded")
    Set receivers = profile.%Get("receivers")
    Do $$$AssertTrue($ISOBJECT(receivers) && (receivers.%Size() > 0), "with receivers")
    Set name = receivers.%Get(0).name
    Do $$$AssertEquals(##class(Shutter.Util.WhatIf).ValidateChange(profile, {"field": "receivers[].category", "receiver": (name), "to": "history_of_record"}), "", "a category change is valid")
    Do $$$AssertEquals(##class(Shutter.Util.WhatIf).ValidateChange(profile, {"field": "authoritative_source", "to": "BEDMGR"}), "", "an authoritative source is valid")
    Do $$$AssertEquals(##class(Shutter.Util.WhatIf).ValidateChange(profile, {"field": "policy.2.single", "to": "approval"}), "", "a policy cell is valid")
    Do $$$AssertNotEquals(##class(Shutter.Util.WhatIf).ValidateChange(profile, {"field": "receivers[].category", "receiver": (name), "to": "nonsense"}), "", "a category outside the three is refused")
    Do $$$AssertNotEquals(##class(Shutter.Util.WhatIf).ValidateChange(profile, {"field": "receivers[].category", "receiver": "No Such Receiver", "to": "history_of_record"}), "", "an unknown receiver is named")
    Do $$$AssertNotEquals(##class(Shutter.Util.WhatIf).ValidateChange(profile, {"field": "mail.from", "to": "x@example.nhs.uk"}), "", "a field outside the list is refused")
    Do $$$AssertNotEquals(##class(Shutter.Util.WhatIf).ValidateChange(profile, {"field": "policy.9.single", "to": "approval"}), "", "an unknown tier is named")
    // The profile itself is untouched.
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Current().%Get("authoritative_source"), profile.%Get("authoritative_source"), "the stored profile is unchanged")
}

/// A case without a snapshot has no entry, no facts and the note that says so.
Method TestNoEvidenceNoFacts()
{
    Set case = ##class(Shutter.Store.Case).%OpenId(..CaseRowId)
    Set out = ##class(Shutter.Util.WhatIf).ForCase(case)
    Do $$$AssertEquals(out."case_id", ..#CASEID, "the case is named")
    Do $$$AssertEquals(out.receiver, "Downstream Out", "and its receiver")
    Do $$$AssertEquals(out.facts.%Size(), 0, "no facts without evidence")
    Do $$$AssertEquals(out.entry, "", "no entry")
    Do $$$AssertTrue(out.note [ "No profile setting", "the note says so: " _ out.note)
    Do $$$AssertTrue(+out."profile_version" > 0, "the profile's version is named")
}

}
