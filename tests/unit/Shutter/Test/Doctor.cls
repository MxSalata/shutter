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

/// The stored credentials are tried against their users (v1.38): on this instance every one the install made signs in,
/// and a wrong password is told from a right one by the web server's 401.
Method TestCredentialsAreTried()
{
    Set r = ##class(Shutter.Util.Json).Parse(##class(Shutter.Setup).Doctor(), .sc)
    Do $$$AssertTrue(r.%IsDefined("credentials") && r.%IsDefined("credentials_ok"), "the Doctor carries the checks")
    Set it = r.credentials.%GetIterator(), n = 0
    While it.%GetNext(, .c) {
        Set n = n + 1
        Do $$$AssertEquals(c.ok, 1, c.namespace _ ":" _ c.name _ " as " _ c.user _ " is " _ c.status _ ": " _ c.detail)
    }
    If r.demo Do $$$AssertTrue(n >= 1, "a demo install has at least its DownstreamAPI credential to try: " _ n)
    Do $$$AssertEquals(r."credentials_ok", 1, "and all of them sign in")
    Set port = $GET(^Shutter.Config("downstreamPort"), $GET(^Shutter.Config("wardPort"), 52773))
    Set code = ##class(Shutter.Setup).Probe("127.0.0.1", port, "/api/shutter/me", "operator", "not-the-password", .detail, .body)
    Do $$$AssertNotEquals(code, 200, "a wrong password does not sign in (HTTP " _ code _ ", the gateway's 404 on this application)")
    Set code = ##class(Shutter.Setup).Probe("127.0.0.1", port, "/api/shutter/me", "operator", "shutter", .detail, .body)
    Do $$$AssertEquals(code, 200, "the right one signs in: " _ detail)
    Do $$$AssertTrue(body [ """username"":""operator""", "and /me names the user: " _ $EXTRACT(body, 1, 60))
    Do $$$AssertEquals(##class(Shutter.Setup).Probe("127.0.0.1", port, "/downstream/api/encounters/none", "downstream-client", "not-the-password", .detail, .body), 401, "the downstream API refuses a wrong password with 401")
    Do $$$AssertEquals(##class(Shutter.Setup).Probe("127.0.0.1", 1, "/api/shutter/me", "operator", "shutter", .detail, .body), "", "an unreachable server is no answer, with the reason: " _ detail)
    // A check whose answer is not the one expected of a signed-in user is refused, whatever the code says.
    Set c = ##class(Shutter.Setup).CredentialCheck("SHUTTER", "DownstreamAPI", "127.0.0.1", port, "/downstream/api/encounters/none", "200")
    If r.demo Do $$$AssertEquals(c.status _ "|" _ c.ok, "refused|0", "a 404 where 200 alone was expected is refused: " _ c.detail)
    Set c = ##class(Shutter.Setup).CredentialCheck("SHUTTER", "NoSuchCredential", "127.0.0.1", port, "/downstream/api/encounters/none", "200,404")
    Do $$$AssertEquals(c.status _ "|" _ c.ok, "missing|0", "a credential the namespace lacks is missing: " _ c.detail)
}

}
