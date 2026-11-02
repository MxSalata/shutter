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

/// Every request, REST or WebSocket, needs this resource on top of the application's own authentication.
Parameter RESOURCE = "Shutter_Publish";

Parameter VERSION = "Shutter publisher 1.0";

}
