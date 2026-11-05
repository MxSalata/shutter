Class OnbPath.Rule Extends Ens.Rule.Definition
{
Parameter RuleAssistClass = "EnsLib.HL7.MsgRouter.RuleAssist";
XData RuleDefinition [ XMLNamespace = "http://www.intersystems.com/rule" ]
{
<ruleDefinition alias="" context="EnsLib.HL7.MsgRouter.RoutingEngine" production="OnbPath.Production">
<ruleSet name="" effectiveBegin="" effectiveEnd="">
<rule name="orders"><when condition="Source=&quot;OrderComms In&quot;"><send transform="" target="LIMS Out"/><return/></when></rule>
<rule name="results"><when condition="Source=&quot;LIMS Results In&quot;"><send transform="" target="Results Out"/><return/></when></rule>
</ruleSet>
</ruleDefinition>
}
}
