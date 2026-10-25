/// One ranked finding of a production review: an element of the terminal tool's argument, so the model sees this
/// shape inside the tool's JSON Schema. The finding itself is the sweep's; only its place and its explanation are
/// the agent's.
Class Shutter.Schema.ReviewRank Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The finding's id as the review lists it (F1, F2, ...).
Property FindingId As %String(%JSONFIELDNAME = "finding_id", MAXLEN = 16) [ Required ];

/// The finding's place, 1 first; the ranks run from 1 to the number of findings without a gap.
Property Rank As %Integer(%JSONFIELDNAME = "rank", MINVAL = 1) [ Required ];

/// One or two sentences on what the finding means for this production against the case history: "consistent with" the cases counted, never "caused".
Property Explanation As %String(%JSONFIELDNAME = "explanation", MAXLEN = 600) [ Required ];

/// What limits the explanation: no cases in the window, an indicative count only, a class default not confirmed at run time.
Property ConfidenceNote As %String(%JSONFIELDNAME = "confidence_note", MAXLEN = 300);

/// The finding's code, item and setting, copied from the finding, so the ranking can be matched to the findings of another
/// run of the same configuration (a recording replayed on another instance) by what they are, not by their numbers.
Property Code As %String(%JSONFIELDNAME = "code", MAXLEN = 64) [ Required ];

Property Item As %String(%JSONFIELDNAME = "item", MAXLEN = 128);

Property Setting As %String(%JSONFIELDNAME = "setting", MAXLEN = 64);

}
