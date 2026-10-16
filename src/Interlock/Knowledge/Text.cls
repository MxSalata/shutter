/// Reading files for the seeds (the catalogue, the site profile). In the core, so the aihub module's library
/// and the core's seeds share it.
Class Interlock.Knowledge.Text
{

/// A whole UTF-8 text file, or "".
ClassMethod ReadFile(path As %String) As %String
{
    Set text = ""
    Set stream = ##class(%Stream.FileCharacter).%New()
    Set stream.TranslateTable = "UTF8"
    Set sc = stream.LinkToFile(path)
    If $$$ISERR(sc) Quit ""
    While 'stream.AtEnd { Set text = text _ stream.Read(32000) }
    Quit text
}

}
