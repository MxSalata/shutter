/// The Doctor (Shutter.Setup.Doctor; CONTRACTS 12) on this instance: the checks added for the builds of 25 Oct to 1 Nov say
/// what a fresh install and an upgrade must show: every item of INSTALLITEMS present, the gate's policy version, the
/// catalogue's entries, the records namespace of a demo install, the index's adapter, the question store, Embedded Python.
Class Shutter.Test.Doctor Extends %UnitTest.TestCase
{

Method TestDoctorReportsTheNewPieces()
{
    Set r = ##class(Shutter.Util.Json).Parse(##class(Shutter.Setup).Doctor(), .sc)
    Do $$$AssertStatusOK(sc, "the Doctor answers JSON")
    Do $$$AssertTrue(r.%IsDefined("missing_items") && r.%IsDefined("disabled_items"), "it lists missing and disabled items")
    Do $$$AssertEquals(r."missing_items".%Size(), 0, "every item of INSTALLITEMS is in the production: " _ r."missing_items".%ToJSON())
    Do $$$AssertEquals(r."gate_policy_version", $PARAMETER("Shutter.Operation.Gate", "POLICYVERSION"), "the gate's policy version")
    Do $$$AssertTrue(+r."catalogue_entries" >= 15, "the catalogue's entries are counted: " _ r."catalogue_entries")
    Do $$$AssertTrue(r.%IsDefined("catalogue_ids") && (r."catalogue_ids" [ "E1"), "and listed: " _ r."catalogue_ids")
    Do $$$AssertEquals(r."index_adapter", "Shutter.Index.Adapter", "the index's adapter")
    Do $$$AssertTrue(r.%IsDefined("questions"), "the questions are counted")
    Do $$$AssertTrue(r.%IsDefined("python_zoneinfo"), "Embedded Python's zoneinfo is reported")
    Do $$$AssertTrue(r.%IsDefined("records_namespace"), "the records namespace is reported")
    Do $$$AssertTrue((r.edition = "aihub") || (r.edition = "core"), "the edition is one word, never broken, on an installed instance: " _ r.edition)
    Do $$$AssertTrue(r.%IsDefined("last_live_run") && ((r.%GetTypeOf("last_live_run") = "null") || r."last_live_run".%IsDefined("at")), "the newest run that reached a model, or null (v1.35)")
    If r.demo Do $$$AssertTrue(r."records_namespace", "a demo install has the RECORDS namespace")
    Do $$$AssertTrue(r.%IsDefined("records_webapp"), "the records web application is reported")
}

/// The stored credentials are tried against their users (v1.38) by a login in a background job, never a web request: on
/// this instance every one the install made signs in, a wrong password is refused with a reason, and the result is cached
/// for ten minutes unless a refresh is asked for. The cache is cleared at the end, so the next Doctor recomputes.
Method TestCredentialsAreTried()
{
    Set r = ##class(Shutter.Util.Json).Parse(##class(Shutter.Setup).Doctor(1), .sc)
    Do $$$AssertTrue(r.%IsDefined("credentials") && r.%IsDefined("credentials_ok") && r.%IsDefined("credentials_checked_at"), "the Doctor carries the checks and their time")
    Set it = r.credentials.%GetIterator(), n = 0
    While it.%GetNext(, .c) {
        Set n = n + 1
        Do $$$AssertEquals(c.ok, 1, c.namespace _ ":" _ c.name _ " as " _ c.user _ " is " _ c.status _ ": " _ c.detail)
    }
    If r.demo Do $$$AssertTrue(n >= 1, "a demo install has at least its DownstreamAPI credential to try: " _ n)
    Do $$$AssertEquals(r."credentials_ok", 1, "and all of them sign in")
    Do $$$AssertEquals(##class(Shutter.Setup).TryLogin("operator", "shutter", .reason), 1, "the demo operator signs in: " _ reason)
    Do $$$AssertEquals(##class(Shutter.Setup).TryLogin("operator", "not-the-password", .reason), 0, "a wrong password is refused")
    Do $$$AssertTrue(reason [ "not the user's", "with the reason: " _ reason)
    Do $$$AssertEquals($USERNAME = "operator", 0, "and this process keeps its own identity: " _ $USERNAME)
    Set c = ##class(Shutter.Setup).CredentialCheck("SHUTTER", "NoSuchCredential")
    Do $$$AssertEquals(c.status _ "|" _ c.ok, "missing|0", "a credential the namespace lacks is missing: " _ c.detail)
    Do $$$AssertEquals($DATA(^Shutter.Health("login")), 0, "the jobs' answers are cleaned up")
}

Method TestCredentialChecksAreCached()
{
    Set keep = $GET(^Shutter.Health("credentials", "json")), keepAt = $GET(^Shutter.Health("credentials", "at")), keepIso = $GET(^Shutter.Health("credentials", "iso"))
    Set fresh = ##class(Shutter.Setup).CredentialChecks(1)
    Do $$$AssertNotEquals($GET(^Shutter.Health("credentials", "at")), "", "a refresh writes the cache with its time")
    Set ^Shutter.Health("credentials", "json") = "[{""name"":""marker""}]"
    Set cached = ##class(Shutter.Setup).CredentialChecks()
    Do $$$AssertEquals(cached.%Size() _ "|" _ cached.%Get(0).name, "1|marker", "within ten minutes the cache is answered, no login made")
    Set ^Shutter.Health("credentials", "at") = ##class(Shutter.Util.Time).EpochSeconds() - 601
    Set again = ##class(Shutter.Setup).CredentialChecks()
    Do $$$AssertNotEquals($SELECT(again.%Size() > 0: again.%Get(0).name, 1: ""), "marker", "after ten minutes the checks run again")
    Set forced = ##class(Shutter.Setup).CredentialChecks(1)
    Do $$$AssertEquals(forced.%Size(), fresh.%Size(), "a refresh runs them whatever the cache's age")
    Kill ^Shutter.Health("credentials")
    If keepAt '= "" Set ^Shutter.Health("credentials", "json") = keep, ^Shutter.Health("credentials", "at") = keepAt, ^Shutter.Health("credentials", "iso") = keepIso
}

}
