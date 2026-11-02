/// The publisher (docs/CONTRACTS.md, section 15, v1.35): Shutter's read-only tools for an MCP client, served by IRIS's
/// own MCP gateway at the web application /mcp/shutter (made by Shutter.Setup.InstallAIHub on the AI Hub build). The
/// caller signs in as an IRIS user (the application's password authentication) and must hold Shutter_Publish on top:
/// operators and approvers do, the forwarder and the public demo's visitors do not. iris-mcp-server, shipped in the
/// image, bridges an MCP client to this endpoint ("iris-mcp-server run --iris-host 127.0.0.1 --iris-port 1972
/// --iris-endpoint /mcp/shutter --transport stdio"); the gateway also answers REST: GET /v1/health, GET /v1/services,
/// POST /v1/tool_call. There is no write tool here; operators have the app.
Class Shutter.Publish.Service Extends %AI.MCP.Service
{

/// The tool sets served: the publisher's read-only tools.
Parameter SPECIFICATION = "Shutter.Publish.Tools";

/// The resource every caller must hold. It is checked in OnAuthenticate, after the sign-in it performs, rather than through
/// the gateway's RESOURCE parameter, whose check runs before OnAuthenticate and so before an unauthenticated request could
/// sign in.
Parameter PUBLISHRESOURCE = "Shutter_Publish";

Parameter VERSION = "Shutter publisher 1.0";

/// The sign-in (CONTRACTS 15): iris-mcp-server passes the MCP client's own HTTP Basic credentials through to this
/// application, whose password authentication signs the caller in; this hook then requires Shutter_Publish (and can sign in
/// an anonymous caller from the Basic header, should a site run the application unauthenticated). Anything else is refused,
/// and the gateway answers a JSON 401. A stdio client carries no credentials, so the sidecar is run with an HTTP or SSE
/// transport and the client sends Basic or a bearer.
ClassMethod OnAuthenticate(authType As %String, auth As %String, headers As %DynamicObject = "") As %Status
{
    Set user = $SELECT($USERNAME = "UnknownUser": "", 1: $USERNAME)
    // A caller the application authenticated already (its password mode, from the HTTP Basic header iris-mcp-server passes
    // through from the MCP client) is kept; an anonymous caller on an unauthenticated application may still sign in here.
    If (user = "") && ($ZCONVERT(authType, "L") = "basic") {
        Set pair = ""
        Try { Set pair = $SYSTEM.Encryption.Base64Decode(auth) } Catch ex { Set pair = "" }
        Set name = $PIECE(pair, ":", 1), password = $PIECE(pair, ":", 2, *)
        If (name '= "") && (pair [ ":") && $SYSTEM.Security.Login(name, password) Set user = $USERNAME
    }
    If user = "" Quit $$$ERROR($$$GeneralError, "Sign in with HTTP Basic as a user who holds " _ ..#PUBLISHRESOURCE)
    If '$SYSTEM.Security.Check(..#PUBLISHRESOURCE, "USE") Quit $$$ERROR($$$GeneralError, user _ " does not hold " _ ..#PUBLISHRESOURCE)
    Quit $$$OK
}

}
