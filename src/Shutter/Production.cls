/// The Shutter production: the ADT feed to the downstream system, and the recovery side that opens
/// and works cases. Paths and the downstream system's address come from system default settings written by
/// Shutter.Setup, so this definition carries none. The agent items default to replay so that the
/// production runs without a model; the aihub module's installer switches them to live.
Class Shutter.Production Extends Ens.Production
{

/// The connector item that delivers to the downstream system (the demo bed-management system): the receiver that
/// the feed, the case workflow, evidence, verification and the blind-resend preview use when nothing names another.
Parameter RECEIVER = "Downstream Out";

/// When the container's environment carries ANTHROPIC_API_KEY and the provider configuration is
/// not there yet, or was written from another key (the .env changed), write it, so live agents need
/// no manual step. Replay mode needs nothing. The knowledge files (block reasons, catalogue, site
/// profile seed, recordings) are re-read when they changed since the last start: a rebuilt image
/// brings its knowledge to the data the volume kept.
ClassMethod OnStart(pTimeStarted As %String) As %Status
{
    // In a container, the production starts with the instance, after the two known startup alerts are
    // logged: clear them here, so Docker's health check shows the instance's real state.
    Try {
        Do ##class(Shutter.Setup).ClearStartupAlerts()
    } Catch {
    }
    Try {
        Set key = $SYSTEM.Util.GetEnviron("ANTHROPIC_API_KEY")
        If (key '= "") && ('##class(Shutter.Setup).ProviderConfigured() || '##class(Shutter.Setup).ProviderKeyMatches(key)) {
            Do ##class(Shutter.Setup).ConfigureProvider(key, $SYSTEM.Util.GetEnviron("SHUTTER_MODEL"))
        }
        // A mode set by hand (record, for the recordings) survives a restart: only an environment that names one
        // changes it.
        If $SYSTEM.Util.GetEnviron("SHUTTER_AGENT_MODE") '= "" Do ##class(Shutter.Setup).RecordAgentMode($SYSTEM.Util.GetEnviron("SHUTTER_AGENT_MODE"))
    } Catch {
    }
    Try {
        Do ##class(Shutter.Setup).RefreshKnowledge()
    } Catch {
    }
    Quit $$$OK
}

XData ProductionDefinition
{
<Production Name="Shutter.Production" TestingEnabled="true" LogGeneralTraceEvents="true">
  <Description>Shutter: supervised recovery for IRIS Interoperability. A failed message is a case, not a retry.</Description>
  <ActorPoolSize>1</ActorPoolSize>
  <Item Name="ADT In" Category="Feed" ClassName="EnsLib.HL7.Service.FileService" PoolSize="1" Enabled="true" Foreground="false" Comment="Synthetic ADT messages, one per file" LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="FileSpec">*.hl7</Setting>
    <Setting Target="Adapter" Name="CallInterval">1</Setting>
    <Setting Target="Adapter" Name="DeleteFromServer">1</Setting>
    <Setting Target="Host" Name="TargetConfigNames">ADT to Downstream</Setting>
    <Setting Target="Host" Name="MessageSchemaCategory">2.5.1</Setting>
    <Setting Target="Host" Name="AckMode">Never</Setting>
    <Setting Target="Host" Name="UseAckCommitCodes">0</Setting>
  </Item>
  <Item Name="HL7 Index" Category="Feed" ClassName="Shutter.Index.Indexer" PoolSize="1" Enabled="true" Foreground="false" Comment="The exact index of the watched HL7 traffic: one row per message with the visit number, patient, event, time, location, operation key and route, filled a few seconds behind the feed" LogTraceEvents="false" Schedule="">
    <Setting Target="Adapter" Name="CallInterval">5</Setting>
    <Setting Target="Host" Name="Routes">ADT In</Setting>
  </Item>
  <Item Name="ADT to Downstream" Category="Feed" ClassName="Shutter.Process.ADTToWard" PoolSize="1" Enabled="true" Foreground="false" Comment="Builds the downstream operation, delivers it, opens a case on failure" LogTraceEvents="true" Schedule="">
  </Item>
  <Item Name="Downstream Out" Category="Feed,Recovery" ClassName="Shutter.Operation.Ward" PoolSize="1" Enabled="true" Foreground="false" Comment="The one connector to the downstream system (the demo bed-management system): feed, rehearsals and recovery writes" LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="Credentials">DownstreamAPI</Setting>
    <Setting Target="Adapter" Name="ResponseTimeout">15</Setting>
    <Setting Target="Adapter" Name="ConnectTimeout">5</Setting>
    <Setting Target="Host" Name="FailureTimeout">0</Setting>
  </Item>
  <Item Name="Escalation Mail" Category="Recovery" ClassName="Shutter.Operation.EscalationMail" PoolSize="1" Enabled="true" Foreground="false" Comment="Escalation emails a person reviewed: through the site's mail server, or as .eml files under the output folder when no server is set" LogTraceEvents="true" Schedule="">
    <Setting Target="Host" Name="FailureTimeout">0</Setting>
  </Item>
  <Item Name="Case Workflow" Category="Recovery" ClassName="Shutter.Process.CaseWorkflow" PoolSize="1" Enabled="true" Foreground="false" Comment="One instance per case: evidence, the board, the gate, approval, execution, verification" LogTraceEvents="true" Schedule="">
    <Setting Target="Host" Name="SettleSeconds">15</Setting>
  </Item>
  <Item Name="Incident Workflow" Category="Recovery" ClassName="Shutter.Process.IncidentWorkflow" PoolSize="1" Enabled="true" Foreground="false" Comment="One instance per incident: the quiet period, chains per encounter, the plan and its approval, the ordered release through each case's own dispatch" LogTraceEvents="true" Schedule="">
  </Item>
  <Item Name="Evidence Collector" Category="Recovery" ClassName="Shutter.Operation.Evidence" PoolSize="1" Enabled="true" Foreground="false" Comment="An immutable snapshot of the message store, the downstream system's state and receipts, and the route" LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="Credentials">DownstreamAPI</Setting>
    <Setting Target="Adapter" Name="ResponseTimeout">15</Setting>
    <Setting Target="Adapter" Name="ConnectTimeout">5</Setting>
    <Setting Target="Host" Name="FailureTimeout">0</Setting>
    <Setting Target="Host" Name="FreshSeconds">3600</Setting>
  </Item>
  <Item Name="Agent Conformance" Category="Board" ClassName="Shutter.Bridge.Operation.Agent" PoolSize="1" Enabled="true" Foreground="false" Comment="Conformance specialist" LogTraceEvents="true" Schedule="">
    <Setting Target="Host" Name="AgentClass">Shutter.Agent.Conformance</Setting>
    <Setting Target="Host" Name="Mode">auto</Setting>
  </Item>
  <Item Name="Agent Encounter" Category="Board" ClassName="Shutter.Bridge.Operation.Agent" PoolSize="1" Enabled="true" Foreground="false" Comment="Encounter integrity specialist" LogTraceEvents="true" Schedule="">
    <Setting Target="Host" Name="AgentClass">Shutter.Agent.Encounter</Setting>
    <Setting Target="Host" Name="Mode">auto</Setting>
  </Item>
  <Item Name="Agent Impact" Category="Board" ClassName="Shutter.Bridge.Operation.Agent" PoolSize="1" Enabled="true" Foreground="false" Comment="Impact analysis specialist" LogTraceEvents="true" Schedule="">
    <Setting Target="Host" Name="AgentClass">Shutter.Agent.Impact</Setting>
    <Setting Target="Host" Name="Mode">auto</Setting>
  </Item>
  <Item Name="Agent Coordinator" Category="Board" ClassName="Shutter.Bridge.Operation.Agent" PoolSize="1" Enabled="true" Foreground="false" Comment="The coordinator: one plan from the findings" LogTraceEvents="true" Schedule="">
    <Setting Target="Host" Name="AgentClass">Shutter.Agent.Coordinator</Setting>
    <Setting Target="Host" Name="Mode">auto</Setting>
  </Item>
  <Item Name="Agent Board" Category="Board" ClassName="Shutter.Bridge.Operation.Agent" PoolSize="1" Enabled="true" Foreground="false" Comment="Any library member whose request names its agent class; the single investigator runs here" LogTraceEvents="true" Schedule="">
    <Setting Target="Host" Name="Mode">auto</Setting>
  </Item>
  <Item Name="Gate" Category="Recovery" ClassName="Shutter.Operation.Gate" PoolSize="1" Enabled="true" Foreground="false" Comment="The deterministic checks: pass, block or unknown per check" LogTraceEvents="true" Schedule="">
  </Item>
  <Item Name="Shutter Approvers" Category="Recovery" ClassName="EnsLib.Workflow.Operation" PoolSize="1" Enabled="true" Foreground="false" Comment="Approval tasks for the Workflow role of the same name" LogTraceEvents="true" Schedule="">
  </Item>
  <Item Name="Shutter API" Category="Recovery" ClassName="Shutter.Service.API" PoolSize="0" Enabled="true" Foreground="false" Comment="Requests the REST API sends into the production, so that they show in the trace" LogTraceEvents="true" Schedule="">
  </Item>
  <Item Name="Scenario Player" Category="Demo" ClassName="Shutter.Operation.ScenarioPlayer" PoolSize="1" Enabled="true" Foreground="false" Comment="Plays a demo scenario's steps in its own job, so a run never needs a new process and shows in the trace" LogTraceEvents="true" Schedule="">
  </Item>
  <Item Name="Verifier" Category="Recovery" ClassName="Shutter.Operation.Verify" PoolSize="1" Enabled="true" Foreground="false" Comment="Reads the receiver's committed history and receipts after an attempt" LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="Credentials">DownstreamAPI</Setting>
    <Setting Target="Adapter" Name="ResponseTimeout">15</Setting>
    <Setting Target="Adapter" Name="ConnectTimeout">5</Setting>
    <Setting Target="Host" Name="FailureTimeout">0</Setting>
  </Item>
</Production>
}

}
