import {
  Table,
  type TableProps,
  type TableTbodyProps,
  type TableTdProps,
  type TableTheadProps,
  type TableThProps,
  type TableTrProps,
} from '@mantine/core';
import { createContext, useContext } from 'react';

/**
 * A table that stacks on a phone (`stack-table`, `stack-table-wide`, `kv-list` in styles.css). Stacking sets its
 * parts to display: block, and Chrome and Safari then stop treating them as a table, so a screen reader loses which
 * column header a cell belongs to. Each part here states its role, which keeps the table, its rows, the column
 * headers and the cells announced as they are at full width. A header cell in the body heads its row.
 */
const InHead = createContext(false);

function StackTableRoot(props: TableProps) {
  return <Table role="table" {...props} />;
}

function Thead(props: TableTheadProps) {
  return (
    <InHead.Provider value>
      <Table.Thead role="rowgroup" {...props} />
    </InHead.Provider>
  );
}

function Tbody(props: TableTbodyProps) {
  return (
    <InHead.Provider value={false}>
      <Table.Tbody role="rowgroup" {...props} />
    </InHead.Provider>
  );
}

function Tr(props: TableTrProps) {
  return <Table.Tr role="row" {...props} />;
}

function Th(props: TableThProps) {
  const head = useContext(InHead);
  return <Table.Th role={head ? 'columnheader' : 'rowheader'} {...props} />;
}

function Td(props: TableTdProps) {
  return <Table.Td role="cell" {...props} />;
}

export const StackTable = Object.assign(StackTableRoot, { Thead, Tbody, Tr, Th, Td });
