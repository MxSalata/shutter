/// The rig's namespace for what a completed message proves: a receiver that answers on the connection and then on its own feed.
/// Order App Out delivers; App ACK In is the receiver's acknowledgement feed, set up as a site must (IgnoreInboundAck 0, AckMode
/// Never), and Stock ACK In the same feed with stock settings. The Measure items send one message three ways to a listener
/// that answers by the message's control id. Nothing of Shutter's is in it before the apply, but the process, which names the helper.
Class OnbAck.Production Extends Ens.Production
{
XData ProductionDefinition
{
<Production Name="OnbAck.Production" TestingEnabled="false" LogGeneralTraceEvents="false">
  <ActorPoolSize>1</ActorPoolSize>
  <Item Name="Orders In" ClassName="EnsLib.HL7.Service.TCPService" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="Port">7131</Setting>
    <Setting Target="Host" Name="MessageSchemaCategory">2.5.1</Setting>
    <Setting Target="Host" Name="TargetConfigNames">Order App Out</Setting>
  </Item>
  <Item Name="Order App Out" ClassName="EnsLib.HL7.Operation.TCPOperation" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="IPAddress">127.0.0.1</Setting>
    <Setting Target="Adapter" Name="Port">7231</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
    <Setting Target="Host" Name="FailureTimeout">0</Setting>
  </Item>
  <Item Name="App ACK In" ClassName="EnsLib.HL7.Service.TCPService" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="Port">7132</Setting>
    <Setting Target="Host" Name="IgnoreInboundAck">0</Setting>
    <Setting Target="Host" Name="AckMode">Never</Setting>
    <Setting Target="Host" Name="TargetConfigNames">App ACK Match</Setting>
  </Item>
  <Item Name="Stock ACK In" ClassName="EnsLib.HL7.Service.TCPService" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="Port">7133</Setting>
    <Setting Target="Host" Name="TargetConfigNames">App ACK Match</Setting>
  </Item>
  <Item Name="App ACK Match" ClassName="OnbAck.AckProcess" PoolSize="1" Enabled="true">
    <Setting Target="Host" Name="Receiver">Order App Out</Setting>
  </Item>
  <Item Name="Measure In" ClassName="EnsLib.HL7.Service.TCPService" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="Port">7134</Setting>
    <Setting Target="Host" Name="MessageSchemaCategory">2.5.1</Setting>
    <Setting Target="Host" Name="TargetConfigNames">Measure Stock Out,Measure Off Out,Measure Strict Out</Setting>
  </Item>
  <Item Name="Measure Stock Out" ClassName="EnsLib.HL7.Operation.TCPOperation" PoolSize="1" Enabled="true" Comment="Stock reply settings">
    <Setting Target="Adapter" Name="IPAddress">127.0.0.1</Setting>
    <Setting Target="Adapter" Name="Port">7232</Setting>
    <Setting Target="Adapter" Name="ResponseTimeout">3</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
    <Setting Target="Host" Name="FailureTimeout">0</Setting>
  </Item>
  <Item Name="Measure Off Out" ClassName="EnsLib.HL7.Operation.TCPOperation" PoolSize="1" Enabled="true" Comment="GetReply off">
    <Setting Target="Adapter" Name="IPAddress">127.0.0.1</Setting>
    <Setting Target="Adapter" Name="Port">7232</Setting>
    <Setting Target="Adapter" Name="GetReply">0</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
    <Setting Target="Host" Name="FailureTimeout">0</Setting>
  </Item>
  <Item Name="Measure Strict Out" ClassName="EnsLib.HL7.Operation.TCPOperation" PoolSize="1" Enabled="true" Comment="A commit ACK does not complete">
    <Setting Target="Adapter" Name="IPAddress">127.0.0.1</Setting>
    <Setting Target="Adapter" Name="Port">7232</Setting>
    <Setting Target="Adapter" Name="ResponseTimeout">3</Setting>
    <Setting Target="Host" Name="ReplyCodeActions">:AA=C,:CA=S,:?R=RF,:?E=S,:~=S,:*=S,:I?=W,:T?=C</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
    <Setting Target="Host" Name="FailureTimeout">0</Setting>
  </Item>
  <Item Name="Ens.Alert" ClassName="OnbSite.AlertLog" PoolSize="1" Enabled="true">
  </Item>
</Production>
}
}
