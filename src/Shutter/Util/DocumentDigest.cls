/// A digest of a stored message that never holds the message: the engine writes the message into this object through its
/// own output call, one stored piece at a time, and each 32,000 characters is hashed and let go (a hash of the hashes at the end). It
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

/// What the engine's output call writes, one stored piece of the message at a time (at most the longest string IRIS holds, about
/// 3.6 MB): taken in 32,000 characters at a time and dropped.
Method Write(pData As %String = "", pFlush As %Boolean, Output pSC As %Status)
{
    Set pSC = $$$OK
    Quit:pData=""
    Set ..Bytes = ..Bytes + $LENGTH(pData)
    If ..InContent Do ..Feed(pData, 1) Quit
    Set cr = $FIND(pData, $CHAR(13))
    If 'cr Do ..Feed(pData, 0) Quit
    Do ..Feed($EXTRACT(pData, 1, cr - 1), 0)
    Set ..InContent = 1
    Do ..Feed($EXTRACT(pData, cr, *), 1)
}

Method WriteLine(pLine As %String = "", pFlush As %Boolean, Output pSC As %Status)
{
    Do ..Write(pLine _ $CHAR(13), .pFlush, .pSC)
}

Method Flush(Output pSC As %Status)
{
    Set pSC = $$$OK
}

/// A piece into the body's digest and, past the first segment, the content's. first: the part before the first segment's end.
Method Feed(text As %String, content As %Boolean) [ Private ]
{
    Set size = ..#CHUNK, len = $LENGTH(text), buf = ..Buffer, hashes = ..Hashes
    Set pos = 1
    While pos <= len {
        Set room = size - $LENGTH(buf), buf = buf _ $EXTRACT(text, pos, pos + room - 1), pos = pos + room
        If $LENGTH(buf) >= size Set hashes = hashes _ $SYSTEM.Encryption.SHAHash(256, $ZCONVERT(buf, "O", "UTF8")), buf = ""
    }
    Set ..Buffer = buf, ..Hashes = hashes
    Quit:'content
    Set buf = ..ContentBuffer, hashes = ..ContentHashes, pos = 1
    While pos <= len {
        Set room = size - $LENGTH(buf), buf = buf _ $EXTRACT(text, pos, pos + room - 1), pos = pos + room
        If $LENGTH(buf) >= size Set hashes = hashes _ $SYSTEM.Encryption.SHAHash(256, $ZCONVERT(buf, "O", "UTF8")), buf = ""
    }
    Set ..ContentBuffer = buf, ..ContentHashes = hashes
}

/// The two digests, as hexadecimal: body and content.
Method Finish(Output content As %String) As %String
{
    Set hashes = ..Hashes _ $SELECT(..Buffer = "": "", 1: $SYSTEM.Encryption.SHAHash(256, $ZCONVERT(..Buffer, "O", "UTF8")))
    Set chashes = ..ContentHashes _ $SELECT(..ContentBuffer = "": "", 1: $SYSTEM.Encryption.SHAHash(256, $ZCONVERT(..ContentBuffer, "O", "UTF8")))
    Set content = ..Hex($SYSTEM.Encryption.SHAHash(256, chashes))
    Quit ..Hex($SYSTEM.Encryption.SHAHash(256, hashes))
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
