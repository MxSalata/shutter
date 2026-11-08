import type { Snapshot } from '@/api/types';
import { asObject } from '@/lib/json';

const str = (v: unknown) => (v === undefined || v === null ? '' : String(v));

/** An observation of the snapshot by its kind, else the same part of the snapshot's summary. */
export function evidenceOf(
  snapshot: Snapshot | null | undefined,
  kind: string,
): Record<string, unknown> | null {
  const item = snapshot?.items?.find((i) => i.kind === kind);
  return asObject(item?.data) ?? asObject(asObject(snapshot?.summary)?.[kind]) ?? null;
}

/**
 * The case's HL7 message as IRIS types it, from the evidence Shutter read: the document type IRIS parsed it as
 * ("2.5.1:ADT_A02", the schema category and the message structure), the event type the message carries (MSH-9,
 * "ADT^A02"), and the version the message itself declares (MSH-12) when the route parsed it under another one.
 */
export interface MessageType {
  /** IRIS's DocType, "2.5.1:ADT_A02"; empty when the evidence names none. */
  docType: string;
  /** MSH-9, "ADT^A02"; empty when the evidence names none. */
  messageType: string;
  /** The HL7 version the message says it is (MSH-12). */
  version: string;
  /** The version the message declares, when the route parsed it as another ("2.4", parsed as 2.5.1); else empty. */
  declaredOther: string;
}

/** The message's type as the evidence records it, or null when the evidence names neither a document type nor MSH-9. */
export function messageTypeOf(snapshot: Snapshot | null | undefined): MessageType | null {
  const message = evidenceOf(snapshot, 'message') ?? {};
  const validation = evidenceOf(snapshot, 'validation') ?? {};
  const docType = str(message.doc_type) || str(validation.doc_type);
  const messageType = str(message.message_type);
  if (!docType && !messageType) return null;
  const version = str(message.message_version) || str(validation.message_version) || str(message.hl7_version);
  return {
    docType,
    messageType,
    version,
    declaredOther: validation.version_agrees === false && version ? version : '',
  };
}

/**
 * The message's type in a few characters, as IRIS writes it: the DocType, else MSH-9 and its version. When the event
 * parses as another structure (ADT^A40 as ADT_A39), the event leads and the structure follows: "ADT^A40 (structure
 * 2.5.1:ADT_A39)", so the header names the same event as the scenario.
 */
export function messageTypeLabel(m: MessageType): string {
  const structure = m.docType.slice(m.docType.indexOf(':') + 1);
  if (m.docType && m.messageType && structure !== m.messageType.replace('^', '_'))
    return `${m.messageType} (structure ${m.docType})`;
  if (m.docType) return m.docType;
  return m.version ? `${m.messageType}, HL7 ${m.version}` : m.messageType;
}
