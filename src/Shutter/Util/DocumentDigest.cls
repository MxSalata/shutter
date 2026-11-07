/// A digest of a stored message that never holds the message: the engine writes the message into this object through its
/// own output call, piece by piece, and each 32,000 characters is hashed and let go (a hash of the hashes at the end). It
/// keeps two digests: of the whole body, and of the body after the first segment (MSH), so the same content under a new
/// control id can be told from changed content. They compare only with each other: this is no SHA-256 of the file.
Class Shutter.Util.DocumentDigest Extends %IO.I.CharacterStream
{

Parameter CHUNK = 32000;

Property Buffer As %String(MAXLEN = "") [ Private ];

Property ContentBuffer As %String(MAXLEN = "") [ Private ];

Property Hashes As %String(MAXLEN = "") [ Private ];

Property ContentHashes As %String(MAXLEN = "") [ Private ];

Property InContent As %Boolean [ InitialExpression = 0, Private ];

Property Bytes As %Integer [ InitialExpression = 0 ];

Method %OnNew(initvalue As %RawString = "") As %Status
{
    Set i%IsOpen = 1
    Quit $$$OK
}

/// What the engine's output call writes: taken in, hashed once a chunk is full, and dropped.
Method Write(pData As %String = "", pFlush As %Boolean, Output pSC As %Status)
{
    Set pSC = $$$OK
    Quit:pData=""
    Set ..Bytes = ..Bytes + $LENGTH(pData)
    Set rest = pData
    If '..InContent {
        Set cr = $FIND(rest, $CHAR(13))
        Set first = $SELECT(cr: $EXTRACT(rest, 1, cr - 1), 1: rest)
        Set ..Buffer = ..Buffer _ first
        Do ..Roll(0)
        Quit:'cr
        Set ..InContent = 1, rest = $EXTRACT(rest, cr, *)
    }
    Set ..Buffer = ..Buffer _ rest, ..ContentBuffer = ..ContentBuffer _ rest
    Do ..Roll(0)
}

Method WriteLine(pLine As %String = "", pFlush As %Boolean, Output pSC As %Status)
{
    Do ..Write(pLine _ $CHAR(13), .pFlush, .pSC)
}

Method Flush(Output pSC As %Status)
{
    Set pSC = $$$OK
}

Method Roll(final As %Boolean) [ Private ]
{
    Set size = ..#CHUNK
    While ($LENGTH(..Buffer) >= size) || (final && (..Buffer '= "")) {
        Set ..Hashes = ..Hashes _ $SYSTEM.Encryption.SHAHash(256, $ZCONVERT($EXTRACT(..Buffer, 1, size), "O", "UTF8"))
        Set ..Buffer = $EXTRACT(..Buffer, size + 1, *)
    }
    While ($LENGTH(..ContentBuffer) >= size) || (final && (..ContentBuffer '= "")) {
        Set ..ContentHashes = ..ContentHashes _ $SYSTEM.Encryption.SHAHash(256, $ZCONVERT($EXTRACT(..ContentBuffer, 1, size), "O", "UTF8"))
        Set ..ContentBuffer = $EXTRACT(..ContentBuffer, size + 1, *)
    }
}

/// The two digests, as hexadecimal: body and content.
Method Finish(Output content As %String) As %String
{
    Do ..Roll(1)
    Set content = ##class(Shutter.Util.DocumentDigest).Hex($SYSTEM.Encryption.SHAHash(256, ..ContentHashes))
    Quit ##class(Shutter.Util.DocumentDigest).Hex($SYSTEM.Encryption.SHAHash(256, ..Hashes))
}

ClassMethod Hex(raw As %String) As %String
{
    Set out = ""
    For i = 1:1:$LENGTH(raw) { Set out = out _ $ZCONVERT($TRANSLATE($JUSTIFY($ZHEX($ASCII(raw, i)), 2), " ", "0"), "L") }
    Quit out
}

/// The digests of a message's text (the intake's whole-text path), segments separated by carriage returns.
ClassMethod OfText(text As %String, Output content As %String) As %String
{
    Set d = ..%New()
    Do d.Write(text)
    Quit d.Finish(.content)
}

}
