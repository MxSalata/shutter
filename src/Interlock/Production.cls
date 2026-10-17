/// The Interlock production: the ADT feed to the ward system, and the recovery side that opens
/// and works cases. Paths and the ward's address come from system default settings written by
/// Interlock.Setup, so this definition carries none. The agent items default to replay so that the
/// production runs without a model; the aihub module's installer switches them to live.
Class Interlock.Production Extends Ens.Production
{

/// When the container's environment carries ANTHROPIC_API_KEY and the provider configuration is
/// not there yet (a fresh `docker compose up` with a .env), write it, so live agents need no
/// manual step. Replay mode needs nothing.
ClassMethod OnStart(pTimeStarted As %String) As %Status
{
    // In a container, the production starts with the instance, after the two known startup alerts are
    // logged: clear them here, so Docker's health check shows the instance's real state.
    Try {
        Do ##class(Interlock.Setup).ClearStartupAlerts()
    } Catch {
    }
    Try {
        Set key = $SYSTEM.Util.GetEnviron("ANTHROPIC_API_KEY")
        If (key '= "") && '##class(Interlock.Setup).ProviderConfigured() {
            Do ##class(Interlock.Setup).ConfigureProvider(key, $SYSTEM.Util.GetEnviron("INTERLOCK_MODEL"))
        }
        Do ##class(Interlock.Setup).RecordAgentMode($SYSTEM.Util.GetEnviron("INTERLOCK_AGENT_MODE"))
    } Catch {
    }
    Quit $$$OK
}

XData ProductionDefinition
{
<Production Name="Interlock.Production" TestingEnabled="true" LogGeneralTraceEvents="true">
  <Description>Interlock: supervised recovery for IRIS Interoperability. A failed message is a case, not a retry.</Description>
  <ActorPoolSize>1</ActorPoolSize>
  <Item Name="ADT In" Category="Feed" ClassName="EnsLib.HL7.Service.FileService" PoolSize="1" Enabled="true" Foreground="false" Comment="Synthetic ADT messages, one per file" LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="FileSpec">*.hl7</Setting>
    <Setting Target="Adapter" Name="CallInterval">1</Setting>
    <Setting Target="Adapter" Name="DeleteFromServer">1</Setting>
    <Setting Target="Host" Name="TargetConfigNames">ADT to Ward</Setting>
    <Setting Target="Host" Name="MessageSchemaCategory">2.5.1</Setting>
    <Setting Target="Host" Name="AckMode">Never</Setting>
    <Setting Target="Host" Name="UseAckCommitCodes">0</Setting>
  </Item>
  <Item Name="ADT to Ward" Category="Feed" ClassName="Interlock.Process.ADTToWard" PoolSize="1" Enabled="true" Foreground="false" Comment="Builds the ward operation, delivers it, opens a case on failure" LogTraceEvents="true" Schedule="">
  </Item>
  <Item Name="Ward Out" Category="Feed,Recovery" ClassName="Interlock.Operation.Ward" PoolSize="1" Enabled="true" Foreground="false" Comment="The one connector to the ward system: feed, rehearsals and recovery writes" LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="Credentials">WardsAPI</Setting>
    <Setting Target="Adapter" Name="ResponseTimeout">15</Setting>
    <Setting Target="Adapter" Name="ConnectTimeout">5</Setting>
    <Setting Target="Host" Name="FailureTimeout">0</Setting>
  </Item>
  <Item Name="Case Workflow" Category="Recovery" ClassName="Interlock.Process.CaseWorkflow" PoolSize="1" Enabled="true" Foreground="false" Comment="One instance per case: evidence, the board, the gate, approval, execution, verification" LogTraceEvents="true" Schedule="">
    <Setting Target="Host" Name="SettleSeconds">15</Setting>
  </Item>
  <Item Name="Incident Workflow" Category="Recovery" ClassName="Interlock.Process.IncidentWorkflow" PoolSize="1" Enabled="true" Foreground="false" Comment="One instance per incident: the quiet period, chains per encounter, the plan and its approval, the ordered release through each case's own dispatch" LogTraceEvents="true" Schedule="">
  </Item>
  <Item Name="Evidence Collector" Category="Recovery" ClassName="Interlock.Operation.Evidence" PoolSize="1" Enabled="true" Foreground="false" Comment="An immutable snapshot of the message store, the ward's state and receipts, and the route" LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="Credentials">WardsAPI</Setting>
    <Setting Target="Adapter" Name="ResponseTimeout">15</Setting>
    <Setting Target="Adapter" Name="ConnectTimeout">5</Setting>
    <Setting Target="Host" Name="FailureTimeout">0</Setting>
  </Item>
  <Item Name="Agent Conformance" Category="Board" ClassName="Interlock.Bridge.Operation.Agent" PoolSize="1" Enabled="true" Foreground="false" Comment="Conformance specialist" LogTraceEvents="true" Schedule="">
    <Setting Target="Host" Name="AgentClass">Interlock.Agent.Conformance</Setting>
    <Setting Target="Host" Name="Mode">auto</Setting>
  </Item>
  <Item Name="Agent Encounter" Category="Board" ClassName="Interlock.Bridge.Operation.Agent" PoolSize="1" Enabled="true" Foreground="false" Comment="Encounter integrity specialist" LogTraceEvents="true" Schedule="">
    <Setting Target="Host" Name="AgentClass">Interlock.Agent.Encounter</Setting>
    <Setting Target="Host" Name="Mode">auto</Setting>
  </Item>
  <Item Name="Agent Impact" Category="Board" ClassName="Interlock.Bridge.Operation.Agent" PoolSize="1" Enabled="true" Foreground="false" Comment="Impact analysis specialist" LogTraceEvents="true" Schedule="">
    <Setting Target="Host" Name="AgentClass">Interlock.Agent.Impact</Setting>
    <Setting Target="Host" Name="Mode">auto</Setting>
  </Item>
  <Item Name="Agent Coordinator" Category="Board" ClassName="Interlock.Bridge.Operation.Agent" PoolSize="1" Enabled="true" Foreground="false" Comment="The coordinator: one plan from the findings" LogTraceEvents="true" Schedule="">
    <Setting Target="Host" Name="AgentClass">Interlock.Agent.Coordinator</Setting>
    <Setting Target="Host" Name="Mode">auto</Setting>
  </Item>
  <Item Name="Agent Board" Category="Board" ClassName="Interlock.Bridge.Operation.Agent" PoolSize="1" Enabled="true" Foreground="false" Comment="Any library member whose request names its agent class; the single investigator runs here" LogTraceEvents="true" Schedule="">
    <Setting Target="Host" Name="Mode">auto</Setting>
  </Item>
  <Item Name="Gate" Category="Recovery" ClassName="Interlock.Operation.Gate" PoolSize="1" Enabled="true" Foreground="false" Comment="The deterministic checks: pass, block or unknown per check" LogTraceEvents="true" Schedule="">
  </Item>
  <Item Name="Interlock Approvers" Category="Recovery" ClassName="EnsLib.Workflow.Operation" PoolSize="1" Enabled="true" Foreground="false" Comment="Approval tasks for the Workflow role of the same name" LogTraceEvents="true" Schedule="">
  </Item>
  <Item Name="Interlock API" Category="Recovery" ClassName="Interlock.Service.API" PoolSize="0" Enabled="true" Foreground="false" Comment="Requests the REST API sends into the production, so that they show in the trace" LogTraceEvents="true" Schedule="">
  </Item>
  <Item Name="Scenario Player" Category="Demo" ClassName="Interlock.Operation.ScenarioPlayer" PoolSize="1" Enabled="true" Foreground="false" Comment="Plays a demo scenario's steps in its own job, so a run never needs a new process and shows in the trace" LogTraceEvents="true" Schedule="">
  </Item>
  <Item Name="Verifier" Category="Recovery" ClassName="Interlock.Operation.Verify" PoolSize="1" Enabled="true" Foreground="false" Comment="Reads the receiver's committed history and receipts after an attempt" LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="Credentials">WardsAPI</Setting>
    <Setting Target="Adapter" Name="ResponseTimeout">15</Setting>
    <Setting Target="Adapter" Name="ConnectTimeout">5</Setting>
    <Setting Target="Host" Name="FailureTimeout">0</Setting>
  </Item>
</Production>
}

}
