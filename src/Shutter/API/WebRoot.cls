/// The web application /shutter: its bare addresses go on to the app's page, and every other path is a file of the
/// built folder, served by the platform's own stream server as a file application's are. A file application has no
/// default page, so this class is the application's DispatchClass, and RedirectEmptyPath brings /shutter, with no slash,
/// to it. Page classes can't be reached through here, as they could through a file application.
Class Shutter.API.WebRoot Extends %CSP.StreamServer
{

/// The page behind the bare addresses.
Parameter HOME = "index.html";

ClassMethod OnPreHTTP() As %Boolean [ ServerOnly = 1 ]
{
    Set app = %request.Application, url = %request.URL
    Set asked = $ZCONVERT(url, "L"), root = $ZCONVERT(app, "L")
    If (asked = root) || (asked = $EXTRACT(root, 1, *-1)) {
        Set query = $GET(%request.CgiEnvs("QUERY_STRING"))
        Set %response.Redirect = app _ ..#HOME _ $SELECT(query = "": "", 1: "?" _ query)
        Quit 1
    }
    If ..Climbs(url) {
        Set %response.Status = "404 Not Found"
        Quit 0
    }
    // Always the address asked for: a caller's own FILE or STREAMOID parameter names nothing here.
    Kill %request.Data("STREAMOID")
    Set %request.Data("FILE", 1) = url
    Quit ##super()
}

/// Whether a path tries to leave its folder: a ".." segment, with either slash.
ClassMethod Climbs(url As %String) As %Boolean
{
    Quit ("/" _ $TRANSLATE(url, "\", "/") _ "/") [ "/../"
}

}
