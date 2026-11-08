/// The app's own addresses, asked over HTTP as a signed-out stranger: /shutter and /shutter/ reach the app, its files
/// still load as they did, and nothing else is served from the application.
Class Shutter.Test.WebRoot Extends %UnitTest.TestCase
{

Parameter APP = "/shutter";

/// Asks the instance's own web server, following no redirect. Returns the response, or "" with why.
Method Ask(path As %String, Output why As %String, method As %String = "GET") As %Net.HttpResponse
{
    Set why = ""
    Do ##class(%RoutineMgr).GetWebServerPort(.port)
    If +$GET(port) = 0 Set why = "this instance has no web server port" Quit ""
    Set http = ##class(%Net.HttpRequest).%New()
    Set http.Server = "127.0.0.1", http.Port = port, http.Timeout = 30, http.FollowRedirect = 0
    Set sc = http.Send(method, path)
    If $$$ISERR(sc) || '$ISOBJECT(http.HttpResponse) Set why = "no answer: " _ $SYSTEM.Status.GetErrorText(sc) Quit ""
    Quit http.HttpResponse
}

/// The application's settings, or "" with a skip recorded when this instance has no /shutter (no built files on it).
Method Settings(Output props) As %Boolean
{
    New $NAMESPACE
    Set $NAMESPACE = "%SYS"
    If '##class(Security.Applications).Exists(..#APP) {
        Do $$$AssertSkipped("No " _ ..#APP _ " web application on this instance")
        Quit 0
    }
    Quit $$$ISOK(##class(Security.Applications).Get(..#APP, .props))
}

Method AssertAnswers(path As %String, code As %Integer, what As %String) As %Net.HttpResponse
{
    Set r = ..Ask(path, .why)
    If '$ISOBJECT(r) {
        Do $$$AssertTrue(0, what _ ": " _ why)
        Quit ""
    }
    Do $$$AssertEquals(+r.StatusCode, code, what _ ": " _ path)
    Quit r
}

Method TestTheApplicationIsSetToDispatch()
{
    Quit:'..Settings(.props)
    Do $$$AssertEquals($GET(props("DispatchClass")), "Shutter.API.WebRoot", "every request goes through the one class")
    Do $$$AssertEquals(+$GET(props("RedirectEmptyPath")), 1, "the path with no slash reaches the application")
    Do $$$AssertEquals(+$GET(props("AutheEnabled")), 64, "still open to a signed-out caller: the app signs in over the API")
}

Method TestTheBareAddressesReachTheApp()
{
    Quit:'..Settings(.props)
    For path = ..#APP, ..#APP _ "/" {
        Set r = ..AssertAnswers(path, 302, "goes on to the app")
        Do:$ISOBJECT(r) $$$AssertEquals(r.GetHeader("LOCATION"), ..#APP _ "/index.html", "and names the page: " _ path)
    }
}

/// The trial's arrival links carry a query; a redirect that dropped it would lose the tour they ask for.
Method TestTheRedirectKeepsTheQuery()
{
    Quit:'..Settings(.props)
    Set r = ..AssertAnswers(..#APP _ "/?trial=tour", 302, "goes on to the app")
    Do:$ISOBJECT(r) $$$AssertEquals(r.GetHeader("LOCATION"), ..#APP _ "/index.html?trial=tour", "with its query")
}

Method TestTheFilesStillLoad()
{
    Quit:'..Settings(.props)
    Set r = ..AssertAnswers(..#APP _ "/index.html", 200, "the page")
    If $ISOBJECT(r) {
        Do $$$AssertTrue(r.ContentType [ "text/html", "as a page: " _ r.ContentType)
        Do $$$AssertTrue(r.Data.Read(32000) [ "id=""root""", "the app's own page")
    }
    Set r = ..AssertAnswers(..#APP _ "/color-scheme.js", 200, "a script")
    Do:$ISOBJECT(r) $$$AssertTrue(r.ContentType [ "javascript", "as a script: " _ r.ContentType)
    Set r = ..AssertAnswers(..#APP _ "/favicon.svg", 200, "an image")
    Do:$ISOBJECT(r) $$$AssertTrue(r.ContentType [ "svg", "as an image: " _ r.ContentType)
    // A binary file arrives byte for byte: no character conversion on the way.
    Set r = ..AssertAnswers(..#APP _ "/s8-visual-trace.png", 200, "a binary file")
    If $ISOBJECT(r) {
        Do $$$AssertTrue(r.ContentType [ "image/png", "as a picture: " _ r.ContentType)
        Do $$$AssertEquals($EXTRACT(r.Data.Read(8), 1, 8), $CHAR(137, 80, 78, 71, 13, 10, 26, 10), "starts with the PNG signature")
    }
}

/// HEAD is what a link checker sends, and it worked before.
Method TestHeadAnswers()
{
    Quit:'..Settings(.props)
    Set r = ..Ask(..#APP _ "/index.html", .why, "HEAD")
    If '$ISOBJECT(r) Do $$$AssertTrue(0, why) Quit
    Do $$$AssertEquals(+r.StatusCode, 200, "HEAD of the page")
}

/// Only files in the built folder: no page class of the namespace, no folder listing, nothing outside the folder.
Method TestNothingElseIsServed()
{
    Quit:'..Settings(.props)
    Do ..AssertAnswers(..#APP _ "/nothing-here.js", 404, "a file that is not there")
    Do ..AssertAnswers(..#APP _ "/assets", 404, "a folder")
    Do ..AssertAnswers(..#APP _ "/assets/", 404, "a folder, with its slash")
    Do ..AssertAnswers(..#APP _ "/Shutter.API.WebRoot.cls", 404, "a class as a page")
    Do ..AssertAnswers(..#APP _ "/%25CSP.Portal.Home.zen", 404, "a system page")
    Do ..AssertAnswers(..#APP _ "/index.csp", 404, "a csp page")
    For path = "/assets/%2e%2e/%2e%2e/%2e%2e/%2e%2e/etc/passwd", "/..%2f..%2f..%2f..%2fetc%2fpasswd", "/assets/..%5c..%5cindex.html" {
        Set r = ..Ask(..#APP _ path, .why)
        If '$ISOBJECT(r) Do $$$AssertTrue(0, why) Continue
        Do $$$AssertNotEquals(+r.StatusCode, 200, "nothing outside the folder: " _ path)
    }
    // A caller's own FILE parameter names no other file.
    Set r = ..Ask(..#APP _ "/index.html?FILE=/csp/sys/UtilHome.csp", .why)
    If $ISOBJECT(r) Do $$$AssertTrue(r.Data.Read(32000) [ "id=""root""", "the page asked for, whatever FILE says")
}

/// The pure check behind the last test: a path that climbs is refused before any file is looked for.
Method TestAPathThatClimbsIsRefused()
{
    Do $$$AssertTrue(##class(Shutter.API.WebRoot).Climbs("/shutter/../x"), "dots")
    Do $$$AssertTrue(##class(Shutter.API.WebRoot).Climbs("/shutter/a/..\b"), "a backslash")
    Do $$$AssertNotTrue(##class(Shutter.API.WebRoot).Climbs("/shutter/assets/a-B_1.js"), "a file")
    Do $$$AssertNotTrue(##class(Shutter.API.WebRoot).Climbs("/shutter/a..b.js"), "dots inside a name")
}

}
