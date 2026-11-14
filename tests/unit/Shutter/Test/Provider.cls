/// The provider configuration written from the environment's key at the production's start (Shutter.Production.OnStart,
/// Shutter.Setup.ProviderNeedsRewrite): the record in ^Shutter.Config("aihub") sits in the data database, which a
/// container's volume keeps, while the wallet secret and the Config Store configuration are instance state the image
/// brings, so a container recreated on the same volume keeps the record and loses the secret. The start therefore asks
/// the instance for what the record names, and writes the key again when either is gone. Each test puts the record
/// back as it was; the wallet test runs where the wallet class is present and leaves no secret behind.
/// The install configures one of two providers, Anthropic or OpenAI (Shutter.Setup.ProviderChoice, ConfigureProvider):
/// which one an environment asks for, and each provider's configuration, have a test each below. Neither calls a
/// model: the key is a placeholder, and writing a configuration sends nothing to the provider. The part that writes
/// the wallet and the Config Store runs where AI Hub's classes are present and the instance holds no provider.
Class Shutter.Test.Provider Extends %UnitTest.TestCase
{

Parameter SECRET = "Shutter.Anthropic";

/// The record's nodes a test may change.
Parameter NODES = "provider,modelProvider,model,keyDigest,providerConfiguredAt";

/// A key that is no key: nothing here sends it anywhere.
Parameter PLACEHOLDER = "ut-placeholder-not-a-key";

/// The record's nodes as they were before the test: whether each had a value, and the value.
Property Saved As %String [ MultiDimensional ];

Method OnBeforeOneTest(testname As %String) As %Status
{
    Kill i%Saved
    For i = 1:1:$LENGTH(..#NODES, ",") Do ..Save($PIECE(..#NODES, ",", i))
    Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
    For i = 1:1:$LENGTH(..#NODES, ",") Do ..Restore($PIECE(..#NODES, ",", i))
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
    Kill ^Shutter.Config("aihub", "provider"), ^Shutter.Config("aihub", "keyDigest"), ^Shutter.Config("aihub", "modelProvider")
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
    Kill ^Shutter.Config("aihub", "modelProvider")
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

/// A caller without the right a probe needs is told nothing (null), never false: the wallet and the Config Store would
/// otherwise answer such a caller as if the secret or the record were gone.
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

/// The Doctor carries the provider the record names and the two probes, each true, false or null.
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

/// Which provider an environment asks for (SHUTTER_PROVIDER and the two keys): the one whose key is set, Anthropic when
/// both are, and the one SHUTTER_PROVIDER names when its key is set. A named provider with no key, and a name the
/// install does not configure, choose nothing and say why, and the other provider's key is not used instead.
Method TestTheEnvironmentChoosesTheProvider()
{
    Do $$$AssertEquals(##class(Shutter.Setup).ProviderChoice("", "", "", .key, .problem), "", "no key at all: no provider")
    Do $$$AssertEquals(key _ "|" _ problem, "|", "and no problem: the agents replay")
    Do $$$AssertEquals(##class(Shutter.Setup).ProviderChoice("openai", "", "", .key, .problem), "", "a provider named with no key at all: still none")
    Do $$$AssertEquals(problem, "", "and still no problem")
    Do $$$AssertEquals(##class(Shutter.Setup).ProviderChoice("", "ka", "", .key, .problem), "anthropic", "only Anthropic's key: anthropic")
    Do $$$AssertEquals(key _ "|" _ problem, "ka|", "with its key")
    Do $$$AssertEquals(##class(Shutter.Setup).ProviderChoice("", "", "ko", .key, .problem), "openai", "only OpenAI's key: openai")
    Do $$$AssertEquals(key _ "|" _ problem, "ko|", "with its key")
    Do $$$AssertEquals(##class(Shutter.Setup).ProviderChoice("", "ka", "ko", .key, .problem), "anthropic", "both keys and none named: anthropic")
    Do $$$AssertEquals(key, "ka", "with Anthropic's key")
    Do $$$AssertEquals(##class(Shutter.Setup).ProviderChoice("openai", "ka", "ko", .key, .problem), "openai", "both keys, openai named: openai")
    Do $$$AssertEquals(key, "ko", "with OpenAI's key")
    Do $$$AssertEquals(##class(Shutter.Setup).ProviderChoice(" OpenAI ", "ka", "ko", .key, .problem), "openai", "the name in any case, blanks aside")
    Do $$$AssertEquals(##class(Shutter.Setup).ProviderChoice("anthropic", "ka", "ko", .key, .problem), "anthropic", "both keys, anthropic named: anthropic")
    Do $$$AssertEquals(key, "ka", "with Anthropic's key")
    Do $$$AssertEquals(##class(Shutter.Setup).ProviderChoice("openai", "ka", "", .key, .problem), "", "openai named with only Anthropic's key: none")
    Do $$$AssertEquals(key, "", "Anthropic's key is not used in its place")
    Do $$$AssertTrue(problem [ "OPENAI_API_KEY is empty", "and the problem names the empty variable: " _ problem)
    Do $$$AssertEquals(##class(Shutter.Setup).ProviderChoice("anthropic", "", "ko", .key, .problem), "", "anthropic named with only OpenAI's key: none")
    Do $$$AssertTrue(problem [ "ANTHROPIC_API_KEY is empty", "and the problem names the empty variable: " _ problem)
    Do $$$AssertEquals(##class(Shutter.Setup).ProviderChoice("gemini", "ka", "ko", .key, .problem), "", "a provider the install does not configure: none")
    Do $$$AssertEquals(key, "", "and no key")
    Do $$$AssertTrue((problem [ "gemini") && (problem [ "anthropic or openai"), "the problem names it and the two the install configures: " _ problem)
    Do $$$AssertEquals(##class(Shutter.Setup).ProviderChoice("sk-" _ "ant-api03-NOTAREALKEY", "ka", "", .key, .problem), "", "a key pasted into SHUTTER_PROVIDER: none")
    Do $$$AssertTrue((problem '[ "sk-ant") && (problem [ "hidden"), "and the problem does not repeat it: " _ problem)
}

/// Anthropic, as before the install took a second provider: the two-argument call, the wallet secret
/// Shutter.Anthropic, model_provider anthropic and claude-opus-5-5 when no model is named.
Method TestAnthropicIsConfigured()
{
    Do $$$AssertEquals(##class(Shutter.Setup).ProviderFact("anthropic", "variable"), "ANTHROPIC_API_KEY", "its key comes from ANTHROPIC_API_KEY")
    Do $$$AssertEquals(##class(Shutter.Setup).ProviderConfiguration("anthropic", "claude-opus-5-5").%ToJSON(), "{""model_provider"":""anthropic"",""model"":""claude-opus-5-5"",""api_key"":""secret://Shutter.Anthropic#key""}", "the configuration written is the one written before, the key by reference")
    Do $$$AssertEquals(##class(Shutter.Setup).ConfigureProvider("  "), "no key given", "a blank key is refused, as before")
    Do $$$AssertEquals(##class(Shutter.Setup).ConfigureProvider("", "claude-opus-5-5", "anthropic"), "no key given", "and with the provider named")
    // SQL passes an empty string as $CHAR(0): an empty model and provider from SQL are the defaults, not names.
    Do $$$AssertEquals(##class(Shutter.Setup).ConfigureProvider("", $CHAR(0), $CHAR(0)), "no key given", "an empty model and provider from SQL are Anthropic's defaults")
    Set r = ##class(Shutter.Setup).ConfigureProvider(..#PLACEHOLDER, "gpt-4.1")
    Do $$$AssertTrue((r [ "gpt-4.1") && (r [ "is not one of anthropic's") && (r [ "claude-opus-5-5"), "a model that is plainly OpenAI's is refused, with the default it could take: " _ r)
    Do $$$AssertEquals(##class(Shutter.Setup).ModelFits("anthropic", "claude-sonnet-5-5"), 1, "another of its models passes")
    Do ..RoundTrip("anthropic")
}

/// OpenAI: the provider named as the third argument, the wallet secret Shutter.OpenAI, model_provider openai and
/// gpt-4.1 when no model is named.
Method TestOpenAIIsConfigured()
{
    Do $$$AssertEquals(##class(Shutter.Setup).ProviderFact("openai", "variable"), "OPENAI_API_KEY", "its key comes from OPENAI_API_KEY")
    Do $$$AssertEquals(##class(Shutter.Setup).ProviderConfiguration("openai", "gpt-4.1").%ToJSON(), "{""model_provider"":""openai"",""model"":""gpt-4.1"",""api_key"":""secret://Shutter.OpenAI#key""}", "the configuration names the provider, the model and its own secret by reference")
    Do $$$AssertEquals(##class(Shutter.Setup).ConfigureProvider(" ", "", "openai"), "no key given", "a blank key is refused")
    Set r = ##class(Shutter.Setup).ConfigureProvider(..#PLACEHOLDER, "claude-opus-5-5", "openai")
    Do $$$AssertTrue((r [ "claude-opus-5-5") && (r [ "is not one of openai's") && (r [ "gpt-4.1"), "a SHUTTER_MODEL left from Anthropic is refused, with the default it could take: " _ r)
    Do $$$AssertEquals(##class(Shutter.Setup).ModelFits("openai", "o4-mini"), 1, "a model of any other name passes: the install keeps no list")
    Set r = ##class(Shutter.Setup).ConfigureProvider(..#PLACEHOLDER, "", "gemini")
    Do $$$AssertTrue(($EXTRACT(r, 1, 2) '= "ok") && (r [ "no such provider: gemini") && (r [ "anthropic or openai"), "a provider the install does not configure is refused: " _ r)
    Do ..RoundTrip("openai")
}

/// A model with no price row (R146-02): ConfigureProvider's status, which the install prints and the production's start
/// logs, says its runs are unpriced and that the day's cap and the users' shares do not limit what they spend. A priced
/// model's status says nothing more. OpenAI's default model has no price row.
Method TestAnUnpricedModelIsSaid()
{
    Do $$$AssertTrue($ISOBJECT(##class(Shutter.Store.ModelPrice).ByModel("claude-opus-5-5")), "Anthropic's default model has a price row")
    Do $$$AssertEquals(##class(Shutter.Setup).UnpricedNote("claude-opus-5-5"), "", "and its status says nothing more")
    Do $$$AssertNotTrue($ISOBJECT(##class(Shutter.Store.ModelPrice).ByModel("gpt-4.1")), "OpenAI's default model has none")
    Set note = ##class(Shutter.Setup).UnpricedNote("gpt-4.1")
    Do $$$AssertTrue((note [ "unpriced") && (note [ "gpt-4.1") && (note [ "SHUTTER_DAILY_BUDGET_USD") && (note [ "SHUTTER_JUDGE_BUDGET_USD") && (note [ "do not limit"), "its status says the cap and the shares do not limit it: " _ note)
}

/// A refusal changes nothing: the record a refused call leaves is the record it found.
Method TestARefusalChangesNothing()
{
    Set ^Shutter.Config("aihub", "provider") = "AI.LLM.Shutter", ^Shutter.Config("aihub", "modelProvider") = "anthropic"
    Set ^Shutter.Config("aihub", "model") = "claude-opus-5-5", ^Shutter.Config("aihub", "keyDigest") = "d"
    For args = $LISTBUILD(..#PLACEHOLDER, "claude-opus-5-5", "openai"), $LISTBUILD(..#PLACEHOLDER, "", "gemini"), $LISTBUILD("", "", "openai") {
        Set r = ##class(Shutter.Setup).ConfigureProvider($LIST(args, 1), $LIST(args, 2), $LIST(args, 3))
        Do $$$AssertNotEquals($EXTRACT(r, 1, 2), "ok", "refused: " _ r)
        Do $$$AssertEquals($GET(^Shutter.Config("aihub", "modelProvider")) _ "|" _ $GET(^Shutter.Config("aihub", "model")) _ "|" _ $GET(^Shutter.Config("aihub", "keyDigest")), "anthropic|claude-opus-5-5|d", "and the record is as it was")
    }
}

/// The record names its provider, and a record from before it did is Anthropic's. The start writes the configuration
/// again when the environment asks for the other provider, and ClearProvider forgets whichever it was.
Method TestTheRecordNamesItsProvider()
{
    Kill ^Shutter.Config("aihub", "provider"), ^Shutter.Config("aihub", "modelProvider")
    Do $$$AssertEquals(##class(Shutter.Setup).ModelProvider(), "", "no provider configured: none")
    Set ^Shutter.Config("aihub", "provider") = "AI.LLM.Shutter"
    Set ^Shutter.Config("aihub", "keyDigest") = ##class(Shutter.Util.Digest).SHA256Hex("k")
    Do $$$AssertEquals(##class(Shutter.Setup).ModelProvider(), "anthropic", "a record that names no provider is Anthropic's")
    Do $$$AssertEquals(##class(Shutter.Setup).ProviderNeedsRewrite("k", .reason, 0, "anthropic"), 0, "the environment asks for anthropic, as recorded: no rewrite")
    Do $$$AssertEquals(##class(Shutter.Setup).ProviderNeedsRewrite("k", .reason, 0, "openai"), 1, "it asks for openai: a rewrite, though the key's digest matches")
    Do $$$AssertTrue((reason [ "anthropic") && (reason [ "openai"), "with the reason: " _ reason)
    Set ^Shutter.Config("aihub", "modelProvider") = "openai"
    Do $$$AssertEquals(##class(Shutter.Setup).ModelProvider(), "openai", "the provider as recorded")
    Do $$$AssertEquals(##class(Shutter.Setup).ProviderNeedsRewrite("k", .reason, 0, "openai"), 0, "openai recorded and asked for: no rewrite")
    Do $$$AssertEquals(##class(Shutter.Setup).ProviderNeedsRewrite("k", .reason, 0, "anthropic"), 1, "anthropic asked for: a rewrite")
    Do $$$AssertEquals(##class(Shutter.Setup).ProviderNeedsRewrite("k", .reason, 0), 0, "a caller that names no provider is answered from the key alone, as before")
    // The probes are only asked on an instance this test may change: one that holds no provider's secret.
    If '..HoldsAProvider() {
        Do $$$AssertEquals(##class(Shutter.Setup).ClearProvider(), "ok: no provider configured; the agents replay recordings", "ClearProvider answers as before")
        Do $$$AssertEquals(##class(Shutter.Setup).ProviderConfigured(), 0, "and the record is gone")
        Do $$$AssertEquals($DATA(^Shutter.Config("aihub", "modelProvider")), 0, "with the provider it named")
        Do $$$AssertEquals(##class(Shutter.Setup).ProviderNeedsRewrite("k", .reason, 0, "openai"), 1, "so the next start writes it from the environment")
    } Else {
        Do $$$LogMessage("this instance holds a provider: ClearProvider is not called on it")
    }
}

/// Whether the instance holds a provider this test must leave alone: a record of one from before the test, a wallet
/// secret of either provider, or the Config Store configuration. An instance without AI Hub's classes and with no
/// record holds none.
Method HoldsAProvider() As %Boolean
{
    If $GET(i%Saved("provider", "value")) '= "" Quit 1
    Quit (##class(Shutter.Setup).WalletSecretState(-1, "anthropic") = 1) || (##class(Shutter.Setup).WalletSecretState(-1, "openai") = 1) || (##class(Shutter.Setup).ProviderConfigState() = 1)
}

/// One provider written and removed on a real wallet and Config Store, with a placeholder key and no model call: the
/// status, the configuration as the Config Store holds it, the provider's own secret and not the other's, the record,
/// the Doctor, then ClearProvider. Skipped, with a line saying so, where AI Hub's classes are absent, this process may
/// not read them, or the instance holds a provider (it is left alone).
Method RoundTrip(provider As %String)
{
    If '##class(%Dictionary.CompiledClass).%ExistsId("%Wallet.KeyValue") || '##class(%Dictionary.CompiledClass).%ExistsId("%ConfigStore.Configuration") {
        Do $$$LogMessage("no wallet or Config Store class on this instance: " _ provider _ " is not written here")
        Quit
    }
    If (##class(Shutter.Setup).WalletSecretState() = "") || (##class(Shutter.Setup).ProviderConfigState() = "") {
        Do $$$LogMessage("this process may not read the wallet or the Config Store: " _ provider _ " is not written here")
        Quit
    }
    If ..HoldsAProvider() {
        Do $$$LogMessage("this instance holds a provider: it is left alone and " _ provider _ " is not written here")
        Quit
    }
    Set other = $SELECT(provider = "anthropic": "openai", 1: "anthropic")
    Set model = ##class(Shutter.Setup).ProviderFact(provider, "model"), secret = ##class(Shutter.Setup).ProviderFact(provider, "secret")
    Set hadCollection = $CLASSMETHOD("%Wallet.Collection", "Exists", "Shutter")
    Kill ^Shutter.Config("aihub", "provider"), ^Shutter.Config("aihub", "modelProvider")
    Try {
        // The other provider's secret is there first, as after a switch: the configuring call removes it.
        Do ##class(Shutter.Setup).ConfigureProvider(..#PLACEHOLDER, "", other)
        Do $$$AssertEquals(##class(Shutter.Setup).WalletSecretState(-1, other), 1, "the other provider's secret is there first")
        // Anthropic by the two-argument call, as every caller made it before the install took a second provider.
        If provider = "anthropic" { Set r = ##class(Shutter.Setup).ConfigureProvider(..#PLACEHOLDER) } Else { Set r = ##class(Shutter.Setup).ConfigureProvider(..#PLACEHOLDER, "", provider) }
        // A model with no price row (OpenAI's) is said to be unpriced, so whoever configured it learns that the day's cap
        // and the shares do not limit what its runs spend (R146-02).
        Do $$$AssertEquals(r, "ok: AI.LLM.Shutter, " _ provider _ ", model " _ model _ $SELECT(provider = "openai": ##class(Shutter.Setup).UnpricedNote(model), 1: ""), "the status names the provider and the model, never the key")
        Do $$$AssertStatusOK($CLASSMETHOD("%ConfigStore.Configuration", "GetDetails", "AI.LLM.Shutter", .details, 0, 0), "the Config Store holds AI.LLM.Shutter")
        Do $$$AssertEquals(details.%Get("model_provider"), provider, "with the provider")
        Do $$$AssertEquals(details.%Get("model"), model, "its default model")
        Do $$$AssertEquals(details.%Get("api_key"), "secret://" _ secret _ "#key", "and the key by reference to its own secret")
        Do $$$AssertTrue(details.%ToJSON() '[ ..#PLACEHOLDER, "the key itself is not in the configuration")
        Do $$$AssertEquals(##class(Shutter.Setup).WalletSecretState(), 1, "the wallet holds the provider's secret")
        Do $$$AssertEquals(##class(Shutter.Setup).WalletSecretState(-1, other), 0, "and no longer the other provider's")
        Do $$$AssertEquals(##class(Shutter.Setup).ModelProvider(), provider, "the record names the provider")
        Do $$$AssertEquals($GET(^Shutter.Config("aihub", "model")), model, "and the model")
        Do $$$AssertEquals(##class(Shutter.Setup).ProviderNeedsRewrite(..#PLACEHOLDER, .reason, 1, provider), 0, "a start with the same key and provider writes nothing: " _ $GET(reason))
        Do $$$AssertEquals(##class(Shutter.Setup).ProviderNeedsRewrite(..#PLACEHOLDER, .reason, 1, other), 1, "a start that asks for the other provider writes it again")
        Set r = ##class(Shutter.Util.Json).Parse(##class(Shutter.Setup).Doctor(), .sc)
        Do $$$AssertStatusOK(sc, "the Doctor answers JSON")
        Do $$$AssertEquals(r.provider, "AI.LLM.Shutter", "the Doctor names the configuration")
        Do $$$AssertEquals(r."wallet_secret", 1, "says the wallet holds its secret")
        Do $$$AssertEquals(r."provider_config", 1, "and that the Config Store holds it")
    } Catch ex {
        Do $$$AssertTrue(0, "the checks threw: " _ ex.DisplayString())
    }
    Do $$$AssertEquals(##class(Shutter.Setup).ClearProvider(), "ok: no provider configured; the agents replay recordings", "ClearProvider answers")
    Do $$$AssertEquals(##class(Shutter.Setup).WalletSecretState(-1, provider) _ "|" _ ##class(Shutter.Setup).WalletSecretState(-1, other), "0|0", "neither provider's secret is left")
    Do $$$AssertEquals(##class(Shutter.Setup).ProviderConfigState(), 0, "nor the configuration")
    Do $$$AssertEquals(##class(Shutter.Setup).ProviderConfigured(), 0, "nor the record")
    If 'hadCollection Do $CLASSMETHOD("%Wallet.Collection", "Delete", "Shutter")
}

}
