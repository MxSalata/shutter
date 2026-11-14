/// Pins the material digest of every recorded case snapshot. <code>web/src/mocks/fixtures.json</code> holds each
/// recorded case with its evidence snapshot: the summary and the material digest the snapshot was sealed with. For
/// each one, <code>Digest.OfObject(Snapshot.Material(summary))</code> must still give that digest, so a change to the
/// material view that moves the digest of an existing kind of case (a transfer, a pathology result, a document) fails
/// here. A new branch of the material view may add a key only when its part of the summary is present.
/// The file was recorded on 2 November 2026, before the material view gained the route's "history" key, so the code
/// no longer gives the digests written in it. Each such case is pinned in XData Pinned to the digest the code gave
/// for its recorded summary when this test was written, and the test holds the view to that value.
/// The file is read from the mounted repository, beside the unit runner's root; on an instance that does not mount
/// the repository (a stock install) the tests are skipped with a message.
Class Shutter.Test.SnapshotMaterial Extends %UnitTest.TestCase
{

/// The recorded cases, relative to the repository's root.
Parameter FIXTURES = "web/src/mocks/fixtures.json";

/// Every recorded snapshot's summary gives the material digest recorded with it. A case whose recorded digest is
/// not what the code gives is pinned in XData Pinned to the code's value, and named in the assertion's message.
Method TestEveryRecordedSnapshotKeepsItsMaterialDigest()
{
    Set cases = ..RecordedCases(.why)
    If '$ISOBJECT(cases) {
        Do $$$AssertSkipped(why)
        Quit
    }
    Set pinned = ..Pinned(), checked = 0, usedPins = 0
    Set iter = cases.%GetIterator()
    While iter.%GetNext(.caseId, .case) {
        Set snap = case.%Get("snapshot")
        Continue:'$ISOBJECT(snap)
        Set summary = snap.%Get("summary"), recorded = snap.%Get("materialDigest")
        If '$ISOBJECT(summary) || (recorded = "") {
            Do $$$AssertTrue(0, caseId _ ": the recorded snapshot has no summary or no materialDigest")
            Continue
        }
        Set checked = checked + 1
        Set expected = recorded, note = ""
        If pinned.%IsDefined(caseId) {
            Set expected = pinned.%Get(caseId), usedPins = usedPins + 1
            Set note = " (pinned in XData Pinned; the file records " _ recorded _ ")"
        }
        Set got = ##class(Shutter.Util.Digest).OfObject(##class(Shutter.Store.Snapshot).Material(summary))
        Do $$$AssertEquals(got, expected, caseId _ ": the material digest of its recorded summary" _ note)
    }
    Do $$$AssertTrue(checked > 0, checked _ " recorded snapshots checked")
    Do $$$LogMessage(usedPins _ " of " _ checked _ " recorded snapshots are held to a digest pinned in XData Pinned, the others to the file's own")
    Do $$$AssertEquals(usedPins, pinned.%Size(), "every case pinned in XData Pinned is a recorded case with a snapshot")
}

/// A summary with no "fhir" part gives a material view with no "fhir" key: every recorded summary, an empty one,
/// and one whose "fhir" is not an object.
Method TestASummaryWithoutFhirGainsNoFhirKey()
{
    Set empty = ##class(Shutter.Store.Snapshot).Material({})
    Do $$$AssertNotTrue(empty.%IsDefined("fhir"), "an empty summary gives no fhir key")
    Do $$$AssertEquals(..Keys(empty), "ward_state,receipt,later", "an empty summary gives the three keys it always gave")
    Set transfer = {"operation": {"operation_key": "op-1", "payload_digest": "sha256:00"}, "ward_state_http_status": 200, "ward_state": {"state": "admitted", "ward": "W1", "version": 3}, "fhir": ""}
    Set m = ##class(Shutter.Store.Snapshot).Material(transfer)
    Do $$$AssertNotTrue(m.%IsDefined("fhir"), "a summary whose fhir is not an object gives no fhir key")
    Do $$$AssertEquals(..Keys(m), "operation,ward_state,receipt,later", "and only the keys of its own parts")

    Set cases = ..RecordedCases(.why)
    If '$ISOBJECT(cases) {
        Do $$$LogMessage("the recorded summaries were not checked: " _ why)
        Quit
    }
    Set without = 0, gained = ""
    Set iter = cases.%GetIterator()
    While iter.%GetNext(.caseId, .case) {
        Set snap = case.%Get("snapshot")
        Continue:'$ISOBJECT(snap)
        Set summary = snap.%Get("summary")
        Continue:'$ISOBJECT(summary)
        Continue:summary.%IsDefined("fhir")
        Set without = without + 1
        If ##class(Shutter.Store.Snapshot).Material(summary).%IsDefined("fhir") Set gained = gained _ $SELECT(gained = "": "", 1: ", ") _ caseId
    }
    Do $$$AssertEquals(gained, "", "no recorded summary without fhir gains a fhir key (" _ without _ " checked)")
    Do $$$AssertTrue(without > 0, without _ " recorded summaries have no fhir part")
}

/// The "cases" object of the recorded file, or "" with the reason in why.
ClassMethod RecordedCases(Output why As %String) As %DynamicObject
{
    Set why = ""
    Set root = $GET(^UnitTestRoot)
    Set file = $PIECE(root, "tests/unit/", 1) _ ..#FIXTURES
    If (root = "") || (root '[ "tests/unit/") || '##class(%File).Exists(file) {
        Set why = "the recorded cases are not on this instance (" _ file _ "); they are read from the mounted repository"
        Quit ""
    }
    Set stream = ##class(%Stream.FileCharacter).%New()
    Do stream.LinkToFile(file)
    Set stream.TranslateTable = "UTF8"
    Set doc = {}.%FromJSON(stream)
    Set cases = doc.%Get("cases")
    If '$ISOBJECT(cases) Set why = file _ " has no cases object" Quit ""
    Quit cases
}

/// The keys of an object, in order, joined with commas.
ClassMethod Keys(obj As %DynamicObject) As %String
{
    Set out = ""
    Set iter = obj.%GetIterator()
    While iter.%GetNext(.key) { Set out = out _ $SELECT(out = "": "", 1: ",") _ key }
    Quit out
}

/// The pinned cases: case id to the material digest the code gives for its recorded summary.
ClassMethod Pinned() As %DynamicObject
{
    Set xdata = ##class(%Dictionary.CompiledXData).%OpenId($CLASSNAME() _ "||Pinned")
    Quit {}.%FromJSON(xdata.Data)
}

/// A recorded case whose recorded materialDigest differs from what the code gives for its summary is listed here
/// with the code's value, so the test holds the material view to it. A case that is not listed is held to the
/// file's own digest.
XData Pinned [ MimeType = application/json ]
{
{
"C-000001": "sha256:5725b2b1aeb039c4aa29b77010e24f0c3bf885f684afa850f1991436e0917c4b",
"C-000002": "sha256:8bad3f20d52c590276a8cb88503a60a5f48d7daf5631598f1239c95a73a164f0",
"C-000003": "sha256:03febe53264141d62bf74ac69cc985c5fe425aa7ea3f459ae059405aeaa094d7",
"C-000004": "sha256:8e7cbd44f75717300cb53aa29a457ceb5fe4e1ad1f3bbcd3c5c63fc949c2e554",
"C-000005": "sha256:53f5b43d38d8a7353cc50cfcad1bc6533406f9ed8f134c068ce0e1af0d829c2c",
"C-000006": "sha256:9a08b017eb7867ff505c41878fd0a52b989a7658bd7fddbb8f857d52be37c5ec",
"C-000007": "sha256:3520ed1b664bf09ac92cfb67ba1a39f5d3c0dd31c920b000163acf23583f2f19",
"C-000008": "sha256:1b2f38fd7fb4bb8b3b5da7589be2650b7d62011e25653d520bde0d2b171de859",
"C-000009": "sha256:59239e50fd8d3e8669db3529db1e0cc895ae436f63a5812eae5212215668a6b4",
"C-000010": "sha256:6c8b1d4dcb813c64a2cdfbad9c4b0254e64e206c7504cd54c1024e5795e1daff",
"C-000011": "sha256:3df9442844401298b43398d60affeee7079723ff4b11e4d7b7c6a5af7d7442ec",
"C-000012": "sha256:a0a341bde84459d30dd145685513d9bad13c0f7f1eb015555574c1911d82af08",
"C-000013": "sha256:79da6ccfeeb9e1f10218ef1edfe4f959394b9f17d429c577ebb820808ede723c",
"C-000014": "sha256:5a7dc90778d451a78620c65f405b46b758e1fccfc573ff0d9cb0534637d165ff",
"C-000015": "sha256:db5c0580bd76446282b217fb2a4b9afb83383782dfca6a4a69e18951143441b0",
"C-000016": "sha256:769bcc2a5ade8af703882d5678e6cffab5fa2dd672a372c4fc8be65ed0110d2b",
"C-000017": "sha256:1bfa71629df6e1c9401f235b2d4011b642d390a311c5e338259da3bfafc3621f",
"C-000018": "sha256:9bff807c07e14b22dd04ef913d50a18b5f9389501aeb6063fc27569c967190a3",
"C-000019": "sha256:92cad00bd3de7624315bd58faefb96db25025e5435e8ad6bd92214d596fac06e",
"C-000020": "sha256:93f79ffd06ad3e3b84437c0878fe1c410ffa3cc7c7145f9a60c349dde568156f",
"C-000021": "sha256:bcdd2535ec3d42d628404b14898e379d683dc954164dc0a33d5658f439cd7e01",
"C-000022": "sha256:dab0fb84c73fc54a36e5f30222a3d7646a6ea0255c4b4b3390d2d895fa7d8eee",
"C-000023": "sha256:4b880b2ac7d8621584338fd67110176b88aa353798844160dd27e3148b56d0e0",
"C-000024": "sha256:4518be925f3e37ddd350be13873abfc189985b4dd47df11116fafe36ea7a19f2",
"C-000025": "sha256:d1ce3706dfb27b17b1c238b15ac927aad282ca8b293f1f3c9f975cae5acafc03",
"C-000026": "sha256:fa60c3b0fe0a6f234527b7fab6b3966cab950eac14bd4494d268a849c04bb990",
"C-000027": "sha256:d8ef7b06506396bffa5bfa16441cde9e316304af64cdf43a61bbc6c8dc982111",
"C-000028": "sha256:576b98d252b4c1ed04df4a91196875c845b6c1abe4dc8406236ed3b4a78a117b",
"C-000029": "sha256:156736334d05e23774c7932b03827520574b4cfb8762becbcbc93bbf24fcbe38",
"C-000030": "sha256:18666e1069a9ec15bba8f8dafe5b020279ed8a8390e3939a195cb5e9d9777a4a",
"C-000031": "sha256:3c9d3f20bacde808e6b10b41bd21f0e95d2cd571559332fa816991333ad1cd7a",
"C-000032": "sha256:e7d15508149a1276a7a88fae934bf6ccc8a067f7224b5045328942877b558905",
"C-000033": "sha256:57379c14072f3fe44e565ec45c26c930ef6162d625ec24d0df72ed96040acc1e",
"C-000034": "sha256:9ff29970d637b26e4ca6d8974401c5bc0f1ea6337730b38011df2ca86b883b0b",
"C-000035": "sha256:7686e7e37fba3d50c2876b3bcbf9a4cd42cf072c5e498bfbec8ce9c5f6d52d71",
"C-000036": "sha256:d47fdd3ccdad1cc824f97ce537e161ef4bf905d1d835e2d56c86d8dc5142de67",
"C-000037": "sha256:2551c355e02aa656279114802f041f3ea576e436fc9f96e5c88b98e3e6659093",
"C-000038": "sha256:a59ce687d4b41f0901571fdda912959f19574394fee8669eaeb3a978b35c8fdd",
"C-000039": "sha256:4d9a301722b735e10c6da0c8ded72dfb7521f5737b8a6203d1c865b8e48f5c12",
"C-000040": "sha256:6c841a29abe964e0518108cd3e2dd56fa2603e6c494a5156b6da97db0339a3c0",
"C-000041": "sha256:3d7510a02e9983fee8ad84b7f99c97f6481265c2ed77bd1c547004a445881b3b",
"C-000042": "sha256:f068818f6e76d0add2edcce8439b819f5ab0677fbc752967fae95c7a161100f2",
"C-000043": "sha256:e12a7273cba83a62cd467f14c46ecfe23fe277261af547a130893b93e5dd8b36",
"C-000044": "sha256:d27c84baaacf150d012b614cf0f74ee085b597ed2688034e0494bb3a518a9c24",
"C-000045": "sha256:af507dd49fae904bed161f03f73e955e028f62a7151c0c7d5e2d3552adc63408",
"C-000046": "sha256:bc87b06de2a5c417bc5baf4a592c04ebc87c2b616becaeae7c62781c06096304",
"C-000047": "sha256:bb7645614654a2aee483e14ee8befb58529b8cf73415a4593205153857316f68",
"C-000048": "sha256:f90b726b615295c573cb636c763ba79ce20f94af65ea7d645ab19313e0258c74",
"C-000049": "sha256:6509f9de235318ae56d8e9654eeb9b542dba027e653163fddf5f1875cf90ccc6",
"C-000050": "sha256:dfe8ca7376d10eabdf3b7cc70e9a947387fc2bd9050bbae775ca996ef0f6f848",
"C-000051": "sha256:97e97a09915ee1078f412e21a8a89ac9fbe6da5ce599f0a46f03c9a0428d8a78",
"C-000052": "sha256:54b2229c24a5b11675b253ed423cc6ab3599f5359f1b6936c8612d9698ade1d3",
"C-000053": "sha256:bee825e3954426ffde0b83d7ab91620d575c33db9846c3011de77aec7d303f9b",
"C-000054": "sha256:77e8e0a4b7bbf267d2a7240bf403ef046d7ae30df1edbf668272d1a6453db5d7",
"C-000055": "sha256:a397ea2feb072d2e57325fab3cddfeca6ac471141dfdaa24718cda08197bbdc6",
"C-000056": "sha256:f2d14816ae70da2f576e3ee3cd388c54b2ab36445a4ccfa708c05f08c04f2f7b",
"C-000057": "sha256:1ea54bbe0291b39dd2572cb0093e0e27ab5a40e028094a2a94a2c0e194be6290",
"C-000058": "sha256:07a60c3fc6171c6e88ffb1f0d664e5bc388115182dfe9dca68864b38f614a031",
"C-000059": "sha256:9955f0ff536bfea52658d8dfdb0d6ec5dc75fa11fa7f32596007e22ffa3ab50c",
"C-000060": "sha256:468e648b2c4544a02e51e46fe3a45423e6ee277fe7e0fbb572106001f3bb1b9e",
"C-000061": "sha256:42ad99258b34d8bca67fff74714de81e6303476932e6e16e8d2e4e4ab48d2a3a",
"C-000062": "sha256:43964ffbadc577e7a0a55dd175455e4e9b4f835ad5b0d2fa41f4383fdbb9ebc8",
"C-000063": "sha256:10fe391f7d1ea84aeceaf1daa2b22e176318f61bd0961bcc96c985c1b53300af",
"C-000064": "sha256:4fe55dfd7d7626ac8c33db920fedc6faf5494d3d393309c8c9bbce955602339e"
}
}

}
