/// A runner carries out one agent run described by a RunSpec and fills the response. The core
/// module ships the replay runner; the aihub module ships the live one. Runners return an error
/// status only for programming errors; a run that failed is reported in the response's Status.
Class Shutter.Bridge.Runner Extends %RegisteredObject [ Abstract ]
{

Method Run(spec As Shutter.Bridge.RunSpec, ByRef response As Shutter.Bridge.Msg.AgentResponse) As %Status [ Abstract ]
{
}

/// Copy the specification's identity into a response.
ClassMethod Stamp(spec As Shutter.Bridge.RunSpec, response As Shutter.Bridge.Msg.AgentResponse)
{
    Set response.AgentClass = spec.AgentClass
    Set response.ConfigVersion = spec.ConfigVersion
    Set response.Mode = spec.Mode
    If response.Model = "" Set response.Model = spec.Model
    If response.ProviderConfig = "" Set response.ProviderConfig = spec.ProviderConfig
}

}
