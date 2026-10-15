/// The Interlock production: the ADT feed to the ward system, and the recovery side that opens
/// and works cases. Paths and the ward's address come from system default settings written by
/// Interlock.Setup, so this definition carries none.
Class Interlock.Production Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="Interlock.Production" TestingEnabled="true" LogGeneralTraceEvents="true">
  <Description>Interlock: supervised recovery for IRIS Interoperability. A failed message is a case, not a retry.</Description>
  <ActorPoolSize>2</ActorPoolSize>
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
  <Item Name="Ward Out" Category="Feed,Recovery" ClassName="Interlock.Operation.Ward" PoolSize="2" Enabled="true" Foreground="false" Comment="The one connector to the ward system: feed, rehearsals and recovery writes" LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="Credentials">WardsAPI</Setting>
    <Setting Target="Adapter" Name="ResponseTimeout">15</Setting>
    <Setting Target="Adapter" Name="ConnectTimeout">5</Setting>
    <Setting Target="Host" Name="FailureTimeout">0</Setting>
  </Item>
  <Item Name="Case Workflow" Category="Recovery" ClassName="Interlock.Process.CaseWorkflow" PoolSize="2" Enabled="true" Foreground="false" Comment="One instance per case: evidence, the board, the gate, approval, execution, verification" LogTraceEvents="true" Schedule="">
  </Item>
</Production>
}

}
