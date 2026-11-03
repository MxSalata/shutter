Include Ensemble

/// The knowledge collections (the interface contract, the lifecycle policy, the effect contracts and
/// the recovery playbooks, Markdown under knowledge/) as FastEmbed knowledge bases in IRIS, one
/// search tool each (search_contracts, search_lifecycle, search_effects, search_playbooks). Built at
/// install; attached to an agent per run by the runner.
Class Shutter.Knowledge.Library
{

Parameter COLLECTIONS = "contracts,lifecycle,effects,playbooks,review,explain";

/// The vector store table of a collection.
ClassMethod TableFor(collection As %String) As %String
{
    Quit "Shutter_Knowledge." _ collection
}

ClassMethod DescriptionFor(collection As %String) As %String
{
    Quit $CASE(collection,
        "contracts": "The downstream system's interface contract: operations, identifiers, the operation key, conditional writes, receipts, dry runs, error codes",
        "lifecycle": "The encounter lifecycle policy: allowed transitions, supersession by later events, patient identity rules",
        "effects": "The dependency inventory and effect contracts: which systems read the downstream system's data and what a movement changes for them",
        "playbooks": "The recovery playbooks: the outcomes (resend, reconcile, superseded, more evidence, escalate), their preconditions and what each writes",
        "review": "The production review rules: what each check of a production review means, why it matters, the safer value, when such a finding is intended and how a reviewer tells",
        "explain": "Shutter in plain words: what each outcome, disposition and gate check means for the person reading a case, and what each site profile setting changes",
        : "Shutter knowledge: " _ collection)
}

/// The knowledge base of a collection, built (idempotent) and ready to search or index; "" with the
/// reason when the RAG stack is not available.
ClassMethod Open(collection As %String, Output err As %String) As %RegisteredObject
{
    Set err = ""
    Try {
        Set emb = ##class(%AI.RAG.Embedding.FastEmbed).Create()
        Set vs = ##class(%AI.RAG.VectorStore.IRIS).%New()
        Set vs.TableName = ..TableFor(collection), vs.Dimensions = 384, vs.ModelName = "AllMiniLML6V2"
        $$$ThrowOnError(vs.Build())
        Set kb = ##class(%AI.RAG.KnowledgeBase).%New("search_" _ collection, ..DescriptionFor(collection))
        Set kb.TopK = 4
        $$$ThrowOnError(kb.Build(emb, vs))
        Return kb
    } Catch ex {
        Set err = ex.DisplayString()
    }
    Return ""
}

/// Index every Markdown file of every collection under <var>dir</var> (the module's knowledge/ folder),
/// replacing each file's chunks. Returns JSON: chunks per collection, or the error. For install and SQL.
ClassMethod BuildAll(dir As %String) As %String [ SqlProc ]
{
    Set out = {}
    Set dir = ##class(%File).NormalizeDirectory(dir)
    For i = 1:1:$LENGTH(..#COLLECTIONS, ",") {
        Set coll = $PIECE(..#COLLECTIONS, ",", i)
        Set sub = dir _ coll _ "/"
        If '##class(%File).DirectoryExists(sub) Do out.%Set(coll, "no folder") Continue
        Set kb = ..Open(coll, .err)
        If '$ISOBJECT(kb) Do out.%Set(coll, "unavailable: " _ err) Continue
        Set chunks = 0, files = 0, kept = "", dropped = 0
        Try {
            Set rs = ##class(%File).FileSetFunc(sub, "*.md")
            While rs.%Next() {
                Set path = rs.%Get("Name")
                Set text = ..ReadFile(path)
                Continue:text=""
                Set source = ##class(%File).GetFilename(path)
                Set n = kb.ReindexDocument(source, text, {"collection": (coll), "source": (source)})
                Set chunks = chunks + n, files = files + 1, kept = kept _ $LISTBUILD(source)
            }
            // A file removed or renamed since the last build leaves its chunks behind, and a search would still find them
            Set table = ..TableFor(coll)
            Set found = ##class(%SQL.Statement).%ExecDirect(, "SELECT DISTINCT %EXACT(source) AS s FROM " _ table)
            While found.%Next() {
                Set s = found.%Get("s")
                Continue:$LISTFIND(kept, s)
                Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM " _ table _ " WHERE %EXACT(source) = ?", s)
                Set dropped = dropped + 1
            }
            Set ^Shutter.Config("knowledge", coll) = $LISTBUILD(files, chunks, ##class(Shutter.Util.Time).NowUTC())
            Do out.%Set(coll, {"files": (files), "chunks": (chunks), "dropped": (dropped)})
        } Catch ex {
            Do out.%Set(coll, "failed: " _ ex.DisplayString())
        }
    }
    Quit out.%ToJSON()
}

/// Attach a collection ("all" for every one) to an agent as search tools. Returns how many were
/// attached; <var>problems</var> lists what could not be.
ClassMethod Attach(agent, collection As %String = "all", Output problems As %String, Output attached As %String) As %Integer
{
    Set problems = "", n = 0, attached = ""
    Set list = $SELECT((collection = "all") || (collection = ""): ..#COLLECTIONS, 1: collection)
    For i = 1:1:$LENGTH(list, ",") {
        Set coll = $PIECE(list, ",", i)
        Continue:coll=""
        If '$DATA(^Shutter.Config("knowledge", coll)) Set problems = problems _ $LISTBUILD(coll _ ": not built") Continue
        Set kb = ..Open(coll, .err)
        If '$ISOBJECT(kb) Set problems = problems _ $LISTBUILD(coll _ ": " _ err) Continue
        Try {
            $$$ThrowOnError(kb.AddToAgent(agent))
            Set n = n + 1, attached = attached _ $SELECT(attached = "": "", 1: ",") _ coll
        } Catch ex {
            Set problems = problems _ $LISTBUILD(coll _ ": " _ ex.DisplayString())
        }
    }
    Set problems = $LISTTOSTRING(problems, "; ")
    Quit n
}

/// A whole UTF-8 text file.
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
