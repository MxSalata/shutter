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

}
