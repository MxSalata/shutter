/// The provider configuration written from the environment's key at the production's start (Shutter.Production.OnStart,
/// Shutter.Setup.ProviderNeedsRewrite): the record in ^Shutter.Config("aihub") sits in the data database, which a
/// container's volume keeps, while the wallet secret and the Config Store configuration are instance state the image
/// brings, so a container recreated on the same volume keeps the record and loses the secret. The start therefore asks
/// the instance for what the record names, and writes the key again when either is gone. Each test puts the record
/// back as it was; the wallet test runs where the wallet class is present and leaves no secret behind.
Class Shutter.Test.Provider Extends %UnitTest.TestCase
{

Parameter SECRET = "Shutter.Anthropic";

/// The record's nodes as they were before the test: whether each had a value, and the value.
Property Saved As %String [ MultiDimensional ];

Method OnBeforeOneTest(testname As %String) As %Status
{
    Kill i%Saved
    Do ..Save("provider"), ..Save("keyDigest")
    Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
    Do ..Restore("provider"), ..Restore("keyDigest")
    Quit $$$OK
}

Method Save(name As %String)
{
    Set i%Saved(name) = $DATA(^Shutter.Config("aihub", name)), i%Saved(name, "value") = $GET(^Shutter.Config("aihub", name))
}

Method Restore(name As %String)
{
    If i%Saved(name) # 2 { Set ^Shutter.Config("aihub", name) = i%Saved(name, "value") } Else { ZKill ^Shutter.Config("aihub", name) }
}

/// The record alone (the probes off, as the core edition's answer amounts to): no provider, or a digest of another key,
/// means a rewrite; a matching digest means none.
Method TestTheRecordDecidesFirst()
{
    Kill ^Shutter.Config("aihub", "provider"), ^Shutter.Config("aihub", "keyDigest")
    Do $$$AssertEquals(##class(Shutter.Setup).ProviderNeedsRewrite("k", .reason, 0), 1, "no provider recorded: a rewrite")
    Do $$$AssertTrue(reason [ "no provider", "with the reason: " _ reason)
    Set ^Shutter.Config("aihub", "provider") = "AI.LLM.Shutter"
    Set ^Shutter.Config("aihub", "keyDigest") = ##class(Shutter.Util.Digest).SHA256Hex("another")
    Do $$$AssertEquals(##class(Shutter.Setup).ProviderNeedsRewrite("k", .reason, 0), 1, "a digest of another key: a rewrite")
    Do $$$AssertTrue(reason [ "another key", "with the reason: " _ reason)
    Set ^Shutter.Config("aihub", "keyDigest") = ##class(Shutter.Util.Digest).SHA256Hex("k")
    Do $$$AssertEquals(##class(Shutter.Setup).ProviderNeedsRewrite("k", .reason, 0), 0, "a matching digest and no probe: none")
    Do $$$AssertEquals(reason, "", "and no reason")
    Do $$$AssertEquals(##class(Shutter.Setup).ProviderNeedsRewrite(" k ", .reason, 0), 0, "the key is compared stripped of blanks, as it was written")
}

/// With the record saying the key is written, the wallet decides: the secret present answers no (where the Config Store
/// holds the configuration too, or cannot say), the secret gone answers a rewrite. The secret is made as ConfigureProvider
/// makes it and removed again; an instance that holds a real one is left alone, and an instance without the wallet class
/// says nothing from the probe.
Method TestTheWalletIsAsked()
{
    Set state = ##class(Shutter.Setup).WalletSecretState()
    If '##class(%Dictionary.CompiledClass).%ExistsId("%Wallet.KeyValue") {
        Do $$$AssertEquals(state, "", "no wallet class: the probe says nothing")
        Do $$$LogMessage("the wallet class is absent on this instance: the create and delete part is skipped")
        Quit
    }
    If state = 1 {
        Do $$$LogMessage("this instance holds the secret " _ ..#SECRET _ ": it is left alone and the create and delete part is skipped")
        Quit
    }
    Do $$$AssertEquals(state, 0, "no secret yet: the probe says so")
    Set ^Shutter.Config("aihub", "provider") = "AI.LLM.Shutter"
    Set ^Shutter.Config("aihub", "keyDigest") = ##class(Shutter.Util.Digest).SHA256Hex("ut-provider-key")
    Do $$$AssertEquals(##class(Shutter.Setup).ProviderNeedsRewrite("ut-provider-key", .reason), 1, "the record says written, the wallet has no secret: a rewrite")
    Do $$$AssertTrue(reason [ "wallet secret", "with the reason: " _ reason)
    Set madeCollection = 0
    If '$CLASSMETHOD("%Wallet.Collection", "Exists", "Shutter") {
        Do $$$AssertStatusOK(##class(Shutter.Setup).EnsureSecretResource(), "the resource guarding the collection exists")
        Set sc = $CLASSMETHOD("%Wallet.Collection", "Create", "Shutter", {"UseResource": "Shutter_Secrets", "EditResource": "Shutter_Secrets"})
        Do $$$AssertStatusOK(sc, "the collection Shutter is created as ConfigureProvider creates it")
        Set madeCollection = 1
    }
    Set sc = $CLASSMETHOD("%Wallet.KeyValue", "Create", ..#SECRET, {"Usage": "CUSTOM", "Secret": {"key": "ut-provider-key"}})
    Do $$$AssertStatusOK(sc, "the secret is created as ConfigureProvider creates it")
    Try {
        Do $$$AssertEquals(##class(Shutter.Setup).WalletSecretState(), 1, "the probe sees it")
        Set config = ##class(Shutter.Setup).ProviderConfigState()
        Set needs = ##class(Shutter.Setup).ProviderNeedsRewrite("ut-provider-key", .reason)
        If config = 0 {
            Do $$$AssertEquals(needs, 1, "the secret is there but the Config Store configuration is not: a rewrite")
            Do $$$AssertTrue(reason [ "Config Store", "with the reason: " _ reason)
        } Else {
            Do $$$AssertEquals(needs, 0, "the secret is there and the Config Store " _ $SELECT(config = "": "cannot say", 1: "holds the configuration") _ ": no rewrite")
            Do $$$AssertEquals(reason, "", "and no reason")
        }
        Set r = ##class(Shutter.Util.Json).Parse(##class(Shutter.Setup).Doctor(), .sc)
        Do $$$AssertStatusOK(sc, "the Doctor answers JSON")
        Do $$$AssertEquals(r.provider, "AI.LLM.Shutter", "the Doctor names the recorded provider")
        Do $$$AssertEquals(r."wallet_secret", 1, "and says the wallet holds its secret")
    } Catch ex {
        Do $$$AssertTrue(0, "the checks threw: " _ ex.DisplayString())
    }
    Do $CLASSMETHOD("%Wallet.KeyValue", "Delete", ..#SECRET)
    If madeCollection Do $CLASSMETHOD("%Wallet.Collection", "Delete", "Shutter")
    Do $$$AssertEquals(##class(Shutter.Setup).WalletSecretState(), 0, "the secret deleted: the probe says so")
    Do $$$AssertEquals(##class(Shutter.Setup).ProviderNeedsRewrite("ut-provider-key", .reason), 1, "and the record alone no longer says written: a rewrite")
    Do $$$AssertTrue(reason [ "wallet secret", "with the reason: " _ reason)
}

/// The Doctor carries the provider the record names and the two probes, each true, false or null.
Method TestACallerWithoutTheRightIsToldNothing()
{
    // The wallet answers a caller without Shutter_Secrets as if the secret were gone, and the Config Store refuses one
    // without %Admin_ConfigStore: either would read as false in the Doctor. Each probe checks the right first.
    Do $$$AssertEquals(##class(Shutter.Setup).WalletSecretState(0), "", "no right to read the wallet: the probe says nothing, not false")
    Do $$$AssertEquals(##class(Shutter.Setup).ProviderConfigState(0), "", "no right to read the Config Store: the same")
    // With the right, the answer is what the instance holds (1 or 0), or nothing where the class is absent.
    Set wallet = ##class(Shutter.Setup).WalletSecretState(1), config = ##class(Shutter.Setup).ProviderConfigState(1)
    Do $$$AssertTrue((wallet = "") || (wallet = 0) || (wallet = 1), "with the right, the wallet probe answers 1, 0 or nothing: " _ wallet)
    Do $$$AssertTrue((config = "") || (config = 0) || (config = 1), "with the right, the Config Store probe answers 1, 0 or nothing: " _ config)
    Do $$$AssertEquals(##class(Shutter.Setup).WalletSecretState(), ##class(Shutter.Setup).WalletSecretState($SYSTEM.Security.Check("Shutter_Secrets", "USE")), "by default the probe reads this process's own right")
    Do $$$AssertEquals(##class(Shutter.Setup).ProviderConfigState(), ##class(Shutter.Setup).ProviderConfigState($SYSTEM.Security.Check("%Admin_ConfigStore", "USE")), "and so does the Config Store's")
}

Method TestTheDoctorReportsTheSecret()
{
    Set r = ##class(Shutter.Util.Json).Parse(##class(Shutter.Setup).Doctor(), .sc)
    Do $$$AssertStatusOK(sc, "the Doctor answers JSON")
    Do $$$AssertEquals(r.provider, $GET(^Shutter.Config("aihub", "provider")), "the provider as recorded, or empty")
    For name = "wallet_secret", "provider_config" {
        Do $$$AssertTrue(r.%IsDefined(name), name _ " is reported")
        Set type = r.%GetTypeOf(name)
        Do $$$AssertTrue((type = "boolean") || (type = "null"), name _ " is true, false or null: " _ type)
    }
    If '##class(%Dictionary.CompiledClass).%ExistsId("%ConfigStore.Configuration") Do $$$AssertEquals(r.%GetTypeOf("provider_config"), "null", "no Config Store class on this instance: null")
}

}
