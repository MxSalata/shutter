/// The demo flag an install writes (Shutter.Setup.DemoSetting, 1.4.8): the modules' demo parameter is empty unless
/// zpm "load <dir> -Ddemo=0" (or -Ddemo=1) gives it, and an empty one keeps the flag the instance already holds. So a
/// first install with no parameter is still the demo, an upgrade of a site's install with no parameter stays a site's,
/// and an explicit -Ddemo always wins. The modules' manifests are read from the tree for the empty default. Nothing is
/// written: DemoSetting is given the stored flag, and the instance's own is only read.
Class Shutter.Test.DemoFlag Extends %UnitTest.TestCase
{

/// A first install, nothing stored, with no parameter: the demo, as a plain zpm "load" has always installed it.
Method TestFirstInstallWithNoArgumentIsTheDemo()
{
    Do $$$AssertEquals(##class(Shutter.Setup).DemoSetting("", ""), 1, "nothing stored and no -Ddemo: the demo")
    Do $$$AssertEquals(##class(Shutter.Setup).DemoSetting(), 1, "Install called with no demo argument on a new instance: the demo")
    Do $$$AssertEquals(##class(Shutter.Setup).DemoSetting($CHAR(0), ""), 1, "SQL's empty argument ($CHAR(0)) with nothing stored: the demo")
}

/// An upgrade with no parameter over a site's install (stored 0) stays a site's install; over a demo (stored 1) a demo.
Method TestUpgradeWithNoArgumentKeepsTheStoredFlag()
{
    Do $$$AssertEquals(##class(Shutter.Setup).DemoSetting("", 0), 0, "a site's install upgraded with no -Ddemo stays a site's")
    Do $$$AssertEquals(##class(Shutter.Setup).DemoSetting("", "0"), 0, "the stored flag as the global holds it")
    Do $$$AssertEquals(##class(Shutter.Setup).DemoSetting($CHAR(0), 0), 0, "SQL's empty argument over a site's install stays a site's")
    Do $$$AssertEquals(##class(Shutter.Setup).DemoSetting(" ", 0), 0, "a blank argument is empty")
    Do $$$AssertEquals(##class(Shutter.Setup).DemoSetting("", 1), 1, "a demo upgraded with no -Ddemo stays a demo")
}

/// An explicit -Ddemo=1 or -Ddemo=0 (or Install's second argument) always wins over what is stored.
Method TestExplicitArgumentAlwaysWins()
{
    Do $$$AssertEquals(##class(Shutter.Setup).DemoSetting(1, 0), 1, "-Ddemo=1 over a site's install makes it a demo")
    Do $$$AssertEquals(##class(Shutter.Setup).DemoSetting("1", "0"), 1, "the parameter as IPM passes it, a string")
    Do $$$AssertEquals(##class(Shutter.Setup).DemoSetting(0, 1), 0, "-Ddemo=0 over a demo makes it a site's")
    Do $$$AssertEquals(##class(Shutter.Setup).DemoSetting("0", ""), 0, "-Ddemo=0 on a first install")
    Do $$$AssertEquals(##class(Shutter.Setup).DemoSetting(0, 0), 0, "-Ddemo=0 on a site's upgrade is harmless")
    Do $$$AssertEquals(##class(Shutter.Setup).DemoSetting(1, ""), 1, "-Ddemo=1 on a first install")
}

/// Both manifests leave the parameter empty, so that the install, not the manifest, decides; each still passes ${demo}.
Method TestManifestsLeaveTheDefaultEmpty()
{
    Set root = $GET(^Shutter.Config("root"))
    If (root = "") || '##class(%File).Exists(root _ "module.xml") Do $$$AssertSkipped("the module's tree is not on disk here") Quit
    For path = "module.xml", "core/module.xml" {
        Set file = root _ path
        If '##class(%File).Exists(file) Do $$$AssertSkipped(path _ " is not in the tree here") Continue
        Set stream = ##class(%Stream.FileCharacter).%New()
        Do $$$AssertStatusOK(stream.LinkToFile(file), "opens " _ path)
        Set text = stream.Read(1000000)
        Do $$$AssertTrue(text [ "<Default Name=""demo"" Value=""""/>", path _ ": the demo parameter's default is empty")
        Do $$$AssertNotTrue(text [ "<Default Name=""demo"" Value=""1""/>", path _ ": no default of 1")
        Do $$$AssertTrue(text [ "<Arg>${demo}</Arg>", path _ ": the install is still given ${demo}")
    }
}

}
