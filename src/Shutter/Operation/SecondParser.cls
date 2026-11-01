/// The Second Parser's production item (CONTRACTS 6.7, v1.34): the PEX business operation that runs shutter.pex.SecondParser
/// in Java, with its classpath set here at start from Shutter.Util.SecondParser (IRIS's own PEX framework jar as the build
/// recorded it, the parser's jar and lib/*.jar). It is a class of Shutter's rather than a bare EnsLib.PEX.BusinessOperation
/// item because a setting written into the production's definition does not last: compiling Shutter.Production writes the
/// definition again from the XData, and an item whose classpath had been written by the install died at the next start with
/// NoClassDefFoundError (core, 1 Nov 2026). The classpath setting, when a site fills it, is used as given.
Class Shutter.Operation.SecondParser Extends EnsLib.PEX.BusinessOperation
{

Method OnInit() As %Status
{
    If ..%remoteClassname = "" Set ..%remoteClassname = ##class(Shutter.Util.SecondParser).#CLASSNAME
    If ..%gatewayName = "" Set ..%gatewayName = "%Java Server"
    If (..%gatewayExtraClasspaths = "") && ##class(Shutter.Util.SecondParser).Available() Set ..%gatewayExtraClasspaths = ##class(Shutter.Util.SecondParser).Classpath()
    Quit ##super()
}

}
