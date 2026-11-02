import { createContext, useContext } from 'react';

/**
 * Whether the reader may change the answers. The questionnaire used to sit in one disabled `fieldset`, which also
 * disabled every button inside it, the disclosures of each question's second layer included. Now each control takes the
 * answer from here, so a reader who cannot save (an operator, the public demo's role) can still open "Keys and values".
 */
const Editable = createContext(true);
export const EditableProvider = Editable.Provider;
export const useEditable = () => useContext(Editable);
