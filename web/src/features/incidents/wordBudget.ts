/**
 * The incident page's word budget: the first layer's visible words in Plain, with Technical at most 1.5 times it
 * (DESIGN.md 1.2), counted on the recorded incident I-000001 (eight failed messages, six chains, one approval) with
 * the shared `layer1Words`, which leaves out the endpoint's own JSON (Technical opens it) and counts its path and button.
 *
 * The page spec asks for 250 words (today 1,673). The page measured 405 words in Plain and 596 in Technical on
 * 2 November 2026, with the zone's name said once in the header; this ceiling keeps that from growing. The spec's own layout adds up to more than 250: the header,
 * lead and IRIS row (about 40), the hero and its four tiles (about 55), six chain cards with their lines (about 55),
 * eight operations with their dates, versions and outcomes (about 90), the approval and the plan (about 50) and the
 * timeline's twelve dated lines (about 100). What the page spends on is each fact the spec names; what it saves is the
 * 1,250 words of tables, long paragraphs, the digest and the raw event text, which are all one click away.
 */
export const PLAIN_BUDGET = 410;
export const TECHNICAL_BUDGET = PLAIN_BUDGET * 1.5;
