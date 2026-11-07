/// The rig's transform on a route: the receiver's own ward code in PV1-3.1.
Class OnbFan.WardMap Extends Ens.DataTransformDTL [ DependsOn = EnsLib.HL7.Message ]
{
Parameter IGNOREMISSINGSOURCE = 1;
Parameter REPORTERRORS = 1;
Parameter TREATEMPTYREPEATINGFIELDASNULL = 0;
XData DTL [ XMLNamespace = "http://www.intersystems.com/dtl" ]
{
<transform sourceClass='EnsLib.HL7.Message' targetClass='EnsLib.HL7.Message' sourceDocType='2.5.1:ADT_A01' targetDocType='2.5.1:ADT_A01' create='copy' language='objectscript' >
<assign value='"MAPPED-WARD"' property='target.{PV1:3.1}' action='set' />
</transform>
}
}
