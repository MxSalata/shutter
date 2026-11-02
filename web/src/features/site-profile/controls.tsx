import {
  Checkbox as MantineCheckbox,
  NativeSelect as MantineNativeSelect,
  NumberInput as MantineNumberInput,
  Radio as MantineRadio,
  Switch as MantineSwitch,
  TextInput as MantineTextInput,
  type CheckboxProps,
  type NativeSelectProps,
  type NumberInputProps,
  type RadioProps,
  type SwitchProps,
  type TextInputProps,
} from '@mantine/core';
import { useEditable } from './editable';

/** The questionnaire's controls: Mantine's own, disabled when the reader may not change the answers (`editable.ts`). */
export function TextInput(props: TextInputProps) {
  const editable = useEditable();
  return <MantineTextInput {...props} disabled={!editable || props.disabled} />;
}

export function NativeSelect(props: NativeSelectProps) {
  const editable = useEditable();
  return <MantineNativeSelect {...props} disabled={!editable || props.disabled} />;
}

export function NumberInput(props: NumberInputProps) {
  const editable = useEditable();
  return <MantineNumberInput {...props} disabled={!editable || props.disabled} />;
}

export function Switch(props: SwitchProps) {
  const editable = useEditable();
  return <MantineSwitch {...props} disabled={!editable || props.disabled} />;
}

export function Checkbox(props: CheckboxProps) {
  const editable = useEditable();
  return <MantineCheckbox {...props} disabled={!editable || props.disabled} />;
}
Checkbox.Group = MantineCheckbox.Group;

export function Radio(props: RadioProps) {
  const editable = useEditable();
  return <MantineRadio {...props} disabled={!editable || props.disabled} />;
}
Radio.Group = MantineRadio.Group;
