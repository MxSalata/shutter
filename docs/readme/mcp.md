# The publisher from an MCP client: a transcript

Shutter's read-only tools for an MCP client ([CONTRACTS.md, section 15](https://github.com/MxSalata/shutter/blob/main/docs/CONTRACTS.md#15-the-publisher-v135)), called from the MCP Inspector's command line through the sidecar the AI Hub image ships. Everything below was run, not written up: a tool list, one case, and a user without `Shutter_Publish` refused. No model was called.

**When and what:** 8 November 2026, 15:02 UTC, commit `4e5ab015` (Health reads version 1.1.1), built with `docker build` on the AI Hub build `2027.1.0AI.109.0` (IRIS reports `2027.1.0AI.109.0com`), on a Linux VM with 12 threads (Docker 29.1.3). No API key, so the board replays its recordings. The sidecar is `iris-mcp-server 2.0.0` from `/usr/irissys/bin`; the client is `@modelcontextprotocol/inspector` 2.11.0 in `--cli` mode, in a `node:24.22.1-trixie-slim` container on the Shutter container's network.

## A case to read

```text
$ python3 tests/e2e/scenario_check.py --url http://127.0.0.1:52811 S2 --modes board --approve
ok      S2 board: C-000001 resolved, resend, one write, downstream admitted WARD-B
all 1 as expected
```

## The sidecar

Inside the container (its log below without timestamps), with the TOML from [INSTALL.md](https://github.com/MxSalata/shutter/blob/main/docs/INSTALL.md#the-publisher-shutters-read-only-tools-for-an-mcp-client) (the `[iris.server]` user is the sidecar's own connection; each client signs in as itself):

```text
$ iris-mcp-server -c /tmp/shutter-mcp.toml --transport http://127.0.0.1:8765 run --iris-host 127.0.0.1 --iris-port 1972 --iris-endpoint /mcp/shutter
...
INFO  Connected to IRIS at 127.0.0.1:1972 with pool size 10
INFO  IRIS connection established; tool discovery deferred to first client connection
INFO  Using HTTP streaming transport on 127.0.0.1:8765/mcp (listener '127.0.0.1:8765')
```

## tools/list, as `operator`

```text
$ npx @modelcontextprotocol/inspector@2.11.0 --cli http://127.0.0.1:8765/mcp --transport http \
    --header "Authorization: Basic $(printf operator:shutter | base64)" --method tools/list
```

Eleven tools, the publisher's eleven ClassMethods, each named `mcp_shutter_<method>`; the sidecar logs "Discovered 11 tool(s) from /mcp/shutter". In the order listed:

```text
mcp_shutter_GetFailure
mcp_shutter_GetIncident
mcp_shutter_ListCases
mcp_shutter_GetPlan
mcp_shutter_Health
mcp_shutter_GetPrecedents
mcp_shutter_GetTimeline
mcp_shutter_ListIncidents
mcp_shutter_GetEvents
mcp_shutter_GetCase
mcp_shutter_GetEvidence
```

Each description starts with the sidecar's `[Remote Service: default_mcp_shutter]` and carries the method's own comment. `GetCase` in full:

```json
{
  "name": "mcp_shutter_GetCase",
  "description": "[Remote Service: default_mcp_shutter] One case: its public fields, its current plan (digest, disposition, summary), the approval of record, where it stands in its incident, and the precedents for its conditions at its receiver. The version lets a client see that the case changed between two reads.\ncaseId: the case identifier, for example C-000012",
  "inputSchema": {
    "type": "object",
    "properties": {
      "caseId": {
        "type": "string"
      }
    },
    "required": [
      "caseId"
    ]
  },
  "outputSchema": {
    "type": "object"
  }
}
```

## tools/call GetCase, as `operator`

```text
$ npx @modelcontextprotocol/inspector@2.11.0 --cli http://127.0.0.1:8765/mcp --transport http \
    --header "Authorization: Basic $(printf operator:shutter | base64)" \
    --method tools/call --tool-name mcp_shutter_GetCase --tool-arg caseId=C-000001
```

The answer's `content` is one text block holding the same object as a string; here is `structuredContent`:

```json
{
  "structuredContent": {
    "approval": {
      "approver": "approver",
      "decidedAt": "2026-11-08T15:01:10Z",
      "decision": "approved",
      "expiresAt": "2026-11-08T16:01:10Z",
      "planDigest": "sha256:a4867fb1779285c750f79e0d4d6db879d46ed94ff6ac3c455325b5b43f0e0906",
      "policyVersion": "2026-11-06.1",
      "revoked": false,
      "siteProfileVersion": 2
    },
    "caseId": "C-000001",
    "closedAt": "2026-11-08T15:01:13Z",
    "disposition": "resend",
    "event": "transfer",
    "eventTime": "2026-10-15T08:20:00Z",
    "failureHttpStatus": 503,
    "failureKind": "delivery_failed",
    "failureOutcome": "unavailable",
    "failureReasonCode": "ward_unavailable",
    "failureText": "Delivery unavailable (ward_unavailable), HTTP 503: The downstream system is unavailable",
    "headline": "Resend the transfer to WARD-B unchanged, after rehearsal and approval. Transfer MSG00202 (ENC-T1 to WARD-B) failed with 503 ward_unavailable. The receipt lookup returned 404, and the receiver still shows admitted on WARD-A at version 1, epoch 80. No later events\u2026",
    "heldSchema": "",
    "incidentId": null,
    "mode": "board",
    "openedAt": "2026-11-08T15:00:52Z",
    "outcome": "Committed and current: receipt 2026-11-08T15:01:13, version 2; the encounter is admitted in WARD-B",
    "plan": {
      "actionType": "resend",
      "catalogueEntry": "E2",
      "createdBy": "run:4",
      "digest": "sha256:a4867fb1779285c750f79e0d4d6db879d46ed94ff6ac3c455325b5b43f0e0906",
      "disposition": "resend",
      "expectedVersion": 1,
      "outcome": "preferred",
      "summary": "Transfer MSG00202 (ENC-T1 to WARD-B) failed with 503 ward_unavailable. The receipt lookup returned 404, and the receiver still shows admitted on WARD-A at version 1, epoch 80. No later events exist. Resend the operation unchanged, conditional on version 1.",
      "version": 1
    },
    "precedents": {
      "approved": 1,
      "lastApprover": "approver",
      "lastAt": "2026-11-08T15:01:13Z",
      "lastCaseId": "C-000001",
      "lastDecision": "approved",
      "rejected": 0,
      "samePolicy": true,
      "signature": "sha256:414391004e85ec91ee0d5c817d27d0cbdbb6e0a3a826da1b24bb1f4a81b1f26a",
      "windowDays": 180
    },
    "receiver": "Downstream Out",
    "retryAfterUntil": "",
    "scenario": "S2",
    "sourceNamespace": "",
    "sourceProduction": "",
    "sourceRoute": "",
    "state": "resolved",
    "updatedAt": "2026-11-08T15:01:13Z",
    "version": 11,
    "waitsOnCase": ""
  },
  "isError": false
}
```

S2's message names the encounter `ENC-1002` and the patient `MRN1002`; the answer has the encounter's token, `ENC-T1`, and neither number. The audit row the call wrote (`Shutter.Store.PublishCall`), read in SQL afterwards, its columns lined up here:

```text
CalledAt              User      Tool     Target    Version  DurationMs
2026-11-08T15:02:41Z  operator  GetCase  C-000001  11       1
```

`tools/list` writes no row: only a tool call does.

## The same calls as `forwarder`, without `Shutter_Publish`

The forwarder's password is right (`$SYSTEM.Security.Login("forwarder", "shutter")` returns 1), and it holds no `Shutter_Publish` (`$SYSTEM.Security.Check("Shutter_Publish", "USE")` returns 0).

```text
$ npx @modelcontextprotocol/inspector@2.11.0 --cli http://127.0.0.1:8765/mcp --transport http \
    --header "Authorization: Basic $(printf forwarder:shutter | base64)" --method tools/list
{
  "tools": []
}
```

The sidecar's log says why (timestamp left out, and the line broken after the path):

```text
WARN  Discovery failed for default/mcp/shutter: Service discovery failed: HTTP 401 Unauthorized: /mcp/shutter/v1/services
      Unauthorized: Authentication required. (no previous registration; tools unavailable until next refresh)
```

Asked to call a tool, the Inspector stops at that empty list:

```text
$ npx @modelcontextprotocol/inspector@2.11.0 --cli http://127.0.0.1:8765/mcp --transport http \
    --header "Authorization: Basic $(printf forwarder:shutter | base64)" \
    --method tools/call --tool-name mcp_shutter_GetCase --tool-arg caseId=C-000001
{"error":{"code":"tool_not_found","message":"Tool 'mcp_shutter_GetCase' not found on server."}}
(exit code 5)
```

The Inspector checks its own tool list before it calls, so this refusal is the client's. A client that sends `tools/call` anyway (a plain JSON-RPC client, protocol `2025-06-18`, the same credentials) gets `isError: true` from the sidecar, which logs it as an `ERROR` line: `Service unavailable: tool 'mcp_shutter_GetCase' cannot be reached (... HTTP 401 Unauthorized: /mcp/shutter/v1/services ...)`.

No audit row was written for the forwarder. The refusal is the web application's: `/mcp/shutter` requires `Shutter_Publish` ([Setup.cls](https://github.com/MxSalata/shutter/blob/main/src/Shutter/Setup.cls), `EnsurePublishApp`), so the forwarder's sign-in to it fails and the gateway answers 401 before the service runs. `OnAuthenticate` in [Service.cls](https://github.com/MxSalata/shutter/blob/main/src/Shutter/Publish/Service.cls) checks `Shutter_Publish` again, as a second gate.
