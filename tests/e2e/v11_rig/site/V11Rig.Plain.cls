/// The rig's plain namespace, on stock classes: a service straight to an operation, one pair per retry behaviour. Retry Out
/// retries for ever, Bounded Out for 25 s, NoRetry Out not at all, and OneShot Out doesn't retry and closes after each send.
/// Nothing of Shutter's is in it.
Class V11Rig.Plain Extends Ens.Production
{
XData ProductionDefinition
{
<Production Name="V11Rig.Plain" TestingEnabled="false" LogGeneralTraceEvents="false">
  <ActorPoolSize>1</ActorPoolSize>
  <Item Name="Retry In" ClassName="EnsLib.HL7.Service.TCPService" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="Port">7611</Setting>
    <Setting Target="Host" Name="MessageSchemaCategory">2.5.1</Setting>
    <Setting Target="Host" Name="TargetConfigNames">Retry Out</Setting>
  </Item>
  <Item Name="Retry Out" ClassName="EnsLib.HL7.Operation.TCPOperation" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="IPAddress">127.0.0.1</Setting>
    <Setting Target="Adapter" Name="Port">7711</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
    <Setting Target="Host" Name="FailureTimeout">-1</Setting>
  </Item>
  <Item Name="NoRetry In" ClassName="EnsLib.HL7.Service.TCPService" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="Port">7612</Setting>
    <Setting Target="Host" Name="MessageSchemaCategory">2.5.1</Setting>
    <Setting Target="Host" Name="TargetConfigNames">NoRetry Out</Setting>
  </Item>
  <Item Name="NoRetry Out" ClassName="EnsLib.HL7.Operation.TCPOperation" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="IPAddress">127.0.0.1</Setting>
    <Setting Target="Adapter" Name="Port">7712</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
    <Setting Target="Host" Name="FailureTimeout">0</Setting>
  </Item>
  <Item Name="Bounded In" ClassName="EnsLib.HL7.Service.TCPService" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="Port">7613</Setting>
    <Setting Target="Host" Name="MessageSchemaCategory">2.5.1</Setting>
    <Setting Target="Host" Name="TargetConfigNames">Bounded Out</Setting>
  </Item>
  <Item Name="Bounded Out" ClassName="EnsLib.HL7.Operation.TCPOperation" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="IPAddress">127.0.0.1</Setting>
    <Setting Target="Adapter" Name="Port">7713</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
    <Setting Target="Host" Name="FailureTimeout">25</Setting>
  </Item>
  <Item Name="OneShot In" ClassName="EnsLib.HL7.Service.TCPService" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="Port">7614</Setting>
    <Setting Target="Host" Name="MessageSchemaCategory">2.5.1</Setting>
    <Setting Target="Host" Name="TargetConfigNames">OneShot Out</Setting>
  </Item>
  <Item Name="OneShot Out" ClassName="EnsLib.HL7.Operation.TCPOperation" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="IPAddress">127.0.0.1</Setting>
    <Setting Target="Adapter" Name="Port">7714</Setting>
    <Setting Target="Adapter" Name="StayConnected">0</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
    <Setting Target="Host" Name="FailureTimeout">0</Setting>
  </Item>
  <Item Name="Ens.Alert" ClassName="V11Rig.AlertLog" PoolSize="1" Enabled="true">
    <Setting Target="Host" Name="AlertOnError">1</Setting>
  </Item>
</Production>
}
}
