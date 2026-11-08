import {
  Accordion,
  Anchor,
  Badge,
  Button,
  Code,
  CopyButton,
  Group,
  NativeSelect,
  Stack,
  Text,
  TextInput,
  Title,
  VisuallyHidden,
} from '@mantine/core';
import { IconApi, IconCheck, IconCopy, IconSearch } from '@tabler/icons-react';
import { createContext, Fragment, useCallback, useContext, useMemo, useState, type ReactNode } from 'react';
import { useSearchParams } from 'react-router';
import { CodeChip } from '@/components/CodeChip';
import { JsonBlock } from '@/components/JsonBlock';
import { KeyValueList } from '@/components/KeyValueList';
import { PageHeader } from '@/components/PageHeader';
import { Section } from '@/components/Section';
import { StackTable } from '@/components/StackTable';
import { TRIAL } from '@/env/mode';
import {
  allResources,
  API,
  BASE_PATH,
  choices,
  constraints,
  curlFor,
  deref,
  exampleOf,
  filterRoutes,
  firstSentence,
  groupsOf,
  jsonMedia,
  NO_FILTER,
  refOf,
  routesOf,
  successOf,
  tagLabel,
  typeName,
  type Filter,
  type Kind,
  type Operation,
  type Parameter,
  type Route,
  type Schema,
} from './openapi';

/** The page's section hue, as the navigation draws it (features/shell/sections.ts). */
export const API_HUE = 'pink';

/** The instance the curl lines address: this one, or a stand-in in the trial, which has none behind it. */
const TRIAL_ORIGIN = 'http://localhost:52773';

/** Opens a shape in the Shapes section and moves there: how a type's name in a table reaches its definition. */
const OpenShape = createContext<(name: string) => void>(() => {});

/** A shape's name as a link to its definition below. */
function ShapeLink({ name }: { name: string }) {
  const open = useContext(OpenShape);
  return (
    <Anchor component="button" type="button" size="sm" ff="monospace" onClick={() => open(name)}>
      {name}
    </Anchor>
  );
}

/** A schema's type in a cell: a named shape is a link to it, an array of one says so, the rest is words. */
function TypeCell({ schema }: { schema?: Schema }) {
  const ref = refOf(schema);
  if (ref) return <ShapeLink name={ref} />;
  if (schema?.oneOf || schema?.anyOf)
    return (
      <Text size="sm" span>
        {(schema.oneOf ?? schema.anyOf ?? []).map((part, i) => (
          <Fragment key={i}>
            {i ? ' or ' : ''}
            <TypeCell schema={part} />
          </Fragment>
        ))}
      </Text>
    );
  const items =
    schema && (schema.type === 'array' || (!schema.type && schema.items)) ? schema.items : undefined;
  if (items && (refOf(items) || items.oneOf))
    return (
      <Text size="sm" span>
        array of <TypeCell schema={items} />
      </Text>
    );
  return (
    <Text size="sm" span>
      {typeName(schema)}
    </Text>
  );
}

/** The values a schema allows, as chips. */
function Choices({ schema }: { schema?: Schema }) {
  const values = choices(schema);
  if (!values?.length) return null;
  return (
    <Text size="sm" span>
      One of{' '}
      {values.map((v, i) => (
        <Fragment key={String(v)}>
          {i ? ', ' : ''}
          <CodeChip>{String(v)}</CodeChip>
        </Fragment>
      ))}
      .
    </Text>
  );
}

/** A property's or a parameter's description, with the values it allows and the limits it states. */
function About({ schema, description }: { schema?: Schema; description?: string }) {
  const limits = constraints(deref(schema));
  return (
    <Stack gap={2}>
      {description ? <Text size="sm">{description}</Text> : null}
      <Choices schema={schema} />
      {limits.length ? (
        <Text size="sm" c="dimmed">
          {limits.join('; ')}.
        </Text>
      ) : null}
    </Stack>
  );
}

/** A field's name, with whether it must be sent. */
function FieldName({ name, required }: { name: string; required: boolean }) {
  return (
    <Stack gap={0}>
      <CodeChip>{name}</CodeChip>
      {required ? (
        <Text size="xs" c="dimmed">
          required
        </Text>
      ) : null}
    </Stack>
  );
}

/**
 * A shape as a table of its fields: name, type and description. A shape that is a list of values says so, an array
 * names what it holds, and a field that is an unnamed object shows its own fields one level down.
 */
function SchemaTable({ schema, label, depth = 0 }: { schema?: Schema; label: string; depth?: number }) {
  const s = deref(schema);
  if (!s) return null;
  if (s.oneOf || s.anyOf)
    return (
      <Text size="sm">
        One of these shapes: <TypeCell schema={s} />.
      </Text>
    );
  const values = choices(s);
  if (values && !s.properties) return <Choices schema={s} />;
  if (s.type === 'array' || (!s.type && s.items)) {
    const inner = deref(s.items);
    return (
      <Stack gap="xs">
        <Text size="sm">
          An array of <TypeCell schema={s.items} />.
        </Text>
        {inner?.properties && !refOf(s.items) && depth < 2 ? (
          <SchemaTable schema={inner} label={`${label}, each item`} depth={depth + 1} />
        ) : null}
      </Stack>
    );
  }
  if (!s.properties)
    return (
      <Text size="sm">
        {typeName(s)}
        {s.additionalProperties ? ', with any keys' : ''}.
      </Text>
    );
  const required = new Set(s.required ?? []);
  return (
    <StackTable className="stack-table" aria-label={label} verticalSpacing={6} highlightOnHover={false}>
      <StackTable.Thead>
        <StackTable.Tr>
          <StackTable.Th>Field</StackTable.Th>
          <StackTable.Th>Type</StackTable.Th>
          <StackTable.Th>Description</StackTable.Th>
        </StackTable.Tr>
      </StackTable.Thead>
      <StackTable.Tbody>
        {Object.entries(s.properties).map(([name, prop]) => {
          const inner = !refOf(prop) && !prop.oneOf ? deref(prop) : undefined;
          const nested = inner?.properties && depth < 2;
          return (
            <StackTable.Tr key={name}>
              <StackTable.Th style={{ verticalAlign: 'top' }}>
                <FieldName name={name} required={required.has(name)} />
              </StackTable.Th>
              <StackTable.Td style={{ verticalAlign: 'top' }}>
                <TypeCell schema={prop} />
              </StackTable.Td>
              <StackTable.Td style={{ verticalAlign: 'top', minWidth: 0 }}>
                <About schema={prop} description={prop.description} />
                {nested ? <SchemaTable schema={inner} label={`${label}, ${name}`} depth={depth + 1} /> : null}
              </StackTable.Td>
            </StackTable.Tr>
          );
        })}
      </StackTable.Tbody>
    </StackTable>
  );
}

/** A route's parameters: in the path, the query or a header. */
function ParametersTable({ parameters }: { parameters: Parameter[] }) {
  return (
    <StackTable className="stack-table" aria-label="Parameters" verticalSpacing={6} highlightOnHover={false}>
      <StackTable.Thead>
        <StackTable.Tr>
          <StackTable.Th>Name</StackTable.Th>
          <StackTable.Th>In</StackTable.Th>
          <StackTable.Th>Type</StackTable.Th>
          <StackTable.Th>Description</StackTable.Th>
        </StackTable.Tr>
      </StackTable.Thead>
      <StackTable.Tbody>
        {parameters.map((p) => (
          <StackTable.Tr key={`${p.in}-${p.name}`}>
            <StackTable.Th style={{ verticalAlign: 'top' }}>
              <FieldName name={p.name} required={p.required === true} />
            </StackTable.Th>
            <StackTable.Td style={{ verticalAlign: 'top' }}>
              <Text size="sm">{p.in}</Text>
            </StackTable.Td>
            <StackTable.Td style={{ verticalAlign: 'top' }}>
              <TypeCell schema={p.schema} />
            </StackTable.Td>
            <StackTable.Td style={{ verticalAlign: 'top', minWidth: 0 }}>
              <About schema={p.schema} description={p.description} />
            </StackTable.Td>
          </StackTable.Tr>
        ))}
      </StackTable.Tbody>
    </StackTable>
  );
}

/** What a route answers, by status code: the reply's shape and, for an error, the codes its `error` field takes. */
function RepliesTable({ op }: { op: Operation }) {
  return (
    <StackTable className="stack-table" aria-label="Replies" verticalSpacing={6} highlightOnHover={false}>
      <StackTable.Thead>
        <StackTable.Tr>
          <StackTable.Th>Status</StackTable.Th>
          <StackTable.Th>Body</StackTable.Th>
          <StackTable.Th>When</StackTable.Th>
        </StackTable.Tr>
      </StackTable.Thead>
      <StackTable.Tbody>
        {Object.entries(op.responses).map(([code, response]) => {
          const errors = response['x-error-codes'] ?? [];
          return (
            <StackTable.Tr key={code}>
              <StackTable.Th style={{ verticalAlign: 'top' }}>
                <CodeChip>{code}</CodeChip>
              </StackTable.Th>
              <StackTable.Td style={{ verticalAlign: 'top' }}>
                <TypeCell schema={jsonMedia(response.content)?.schema} />
              </StackTable.Td>
              <StackTable.Td style={{ verticalAlign: 'top', minWidth: 0 }}>
                <Stack gap={2}>
                  <Text size="sm">{response.description}</Text>
                  {errors.length ? (
                    <Text size="sm" span>
                      <Text span c="dimmed" size="sm">
                        error:{' '}
                      </Text>
                      {errors.map((e, i) => (
                        <Fragment key={e}>
                          {i ? ', ' : ''}
                          <CodeChip>{e}</CodeChip>
                        </Fragment>
                      ))}
                    </Text>
                  ) : null}
                </Stack>
              </StackTable.Td>
            </StackTable.Tr>
          );
        })}
      </StackTable.Tbody>
    </StackTable>
  );
}

/** A copy button for a piece of text, with its own name. */
function Copy({ value, label }: { value: string; label: string }) {
  return (
    <CopyButton value={value} timeout={1500}>
      {({ copied, copy }) => (
        <Button
          size="xs"
          variant="default"
          leftSection={copied ? <IconCheck size={14} aria-hidden /> : <IconCopy size={14} aria-hidden />}
          onClick={copy}
        >
          {copied ? 'Copied' : label}
        </Button>
      )}
    </CopyButton>
  );
}

/** One part of a route's detail, under its own small heading. */
function Part({ title, aside, children }: { title: string; aside?: ReactNode; children: ReactNode }) {
  return (
    <Stack gap={6}>
      <Group justify="space-between" align="center" wrap="wrap" gap="xs">
        <Title order={4} size="sm">
          {title}
        </Title>
        {aside}
      </Group>
      {children}
    </Stack>
  );
}

/** Everything about one route, open under its line. */
function RouteDetail({ route, origin }: { route: Route; origin: string }) {
  const body = jsonMedia(route.op.requestBody?.content);
  const ok = successOf(route.op);
  const okSchema = jsonMedia(ok?.response.content)?.schema;
  const curl = curlFor(route, origin);
  const paragraphs = (route.op.description ?? '').split(/\n\n+/).filter(Boolean);
  const okExample = okSchema ? exampleOf(okSchema) : undefined;
  return (
    <Stack gap="md">
      {paragraphs.map((p) => (
        <Text size="sm" key={p} maw="80ch">
          {p}
        </Text>
      ))}
      <KeyValueList
        labelWidth={150}
        rows={[
          [
            'Needs',
            route.resources.length ? (
              <Text size="sm" span>
                {route.resources.map((r, i) => (
                  <Fragment key={r}>
                    {i ? ' and ' : ''}
                    <CodeChip>{r}</CodeChip>
                  </Fragment>
                ))}
              </Text>
            ) : (
              'No resource: it answers before anyone signs in'
            ),
          ],
          [
            'A change',
            route.writes ? (
              <Text size="sm" span>
                Yes: send <CodeChip>X-Requested-With: Shutter</CodeChip>, or the answer is 403 csrf
              </Text>
            ) : (
              'No: it reads'
            ),
          ],
          [
            'Idempotency-Key',
            route.idempotent ? 'The same key and body replay the first reply' : 'Not read on this route',
          ],
          ['Contract', route.op['x-contract']],
          ['Served by', route.op['x-dispatch'] ? <CodeChip>{route.op['x-dispatch']}</CodeChip> : undefined],
        ]}
      />
      {route.parameters.length ? (
        <Part title="Parameters">
          <ParametersTable parameters={route.parameters} />
        </Part>
      ) : null}
      {body ? (
        <Part title={route.op.requestBody?.required ? 'Body' : 'Body (optional)'}>
          <Text size="sm">
            <TypeCell schema={body.schema} />
            {route.op.requestBody?.description ? `: ${route.op.requestBody.description}` : ''}
          </Text>
          <SchemaTable schema={body.schema} label={`Body of ${route.method.toUpperCase()} ${route.path}`} />
          <JsonBlock value={body.example ?? exampleOf(body.schema)} label="Example body" />
        </Part>
      ) : null}
      <Part title="Replies">
        <RepliesTable op={route.op} />
      </Part>
      {okExample !== undefined ? (
        <Part title={`Example reply (${ok?.code})`}>
          <JsonBlock
            value={okExample}
            label={`Example reply of ${route.method.toUpperCase()} ${route.path}`}
          />
        </Part>
      ) : null}
      <Part title="As curl" aside={<Copy value={curl} label="Copy the command" />}>
        <Code
          block
          className="json-block"
          aria-label={`${route.method.toUpperCase()} ${route.path} as curl`}
          tabIndex={0}
        >
          {curl}
        </Code>
      </Part>
    </Stack>
  );
}

/** A route's line in the list: its method (filled when it changes something), path, summary and resources. */
function RouteLine({ route }: { route: Route }) {
  return (
    <Group gap="xs" wrap="wrap" align="center">
      <Badge
        color="gray"
        variant={route.writes ? 'filled' : 'outline'}
        size="sm"
        radius="sm"
        w={62}
        style={{ textTransform: 'none', fontFamily: 'var(--mantine-font-family-monospace)' }}
      >
        {route.method.toUpperCase()}
      </Badge>
      {route.writes ? <VisuallyHidden>(a change)</VisuallyHidden> : null}
      <CodeChip>{route.path}</CodeChip>
      <Text size="sm" style={{ flex: '1 1 200px', minWidth: 0 }}>
        {route.op.summary}
      </Text>
      <Group gap={4} wrap="wrap">
        {route.resources.map((r) => (
          <Badge key={r} size="xs" color="gray" variant="outline" style={{ textTransform: 'none' }}>
            {r}
          </Badge>
        ))}
      </Group>
    </Group>
  );
}

/** The ways in, said once at the top: from the document's security schemes, headers and error shape. */
function CallingIt({ origin }: { origin: string }) {
  const schemes = API.components?.securitySchemes ?? {};
  const params = API.components?.parameters ?? {};
  const error = API.components?.schemas?.Error;
  const forwarded = API['x-forwarded-prefixes'] ?? [];
  return (
    <KeyValueList
      labelWidth={170}
      rows={[
        [
          'Base path',
          <Text size="sm" span key="base">
            <CodeChip>{BASE_PATH}</CodeChip> on the instance that serves this app
            {TRIAL ? `. The trial has no instance behind it, so the curl lines name ${origin}` : ''}.
          </Text>,
        ],
        [
          'Sign in',
          <Text size="sm" span key="sign-in">
            <CodeChip>POST {BASE_PATH}/session</CodeChip> with the username and password.{' '}
            {schemes.sessionCookie?.description} Or, on each request, HTTP Basic:{' '}
            {schemes.basicAuth?.description}
          </Text>,
        ],
        [
          'Changes',
          <Text size="sm" span key="changes">
            Send <CodeChip>X-Requested-With: Shutter</CodeChip>. {params.XRequestedWith?.description} Without
            it the answer is 403 <CodeChip>csrf</CodeChip>.
          </Text>,
        ],
        [
          'Repeats',
          <Text size="sm" span key="repeats">
            <CodeChip>Idempotency-Key</CodeChip>, on the routes that say so.{' '}
            {params.IdempotencyKey?.description}
          </Text>,
        ],
        ['Errors', error?.description],
        ['Times', 'ISO 8601, in UTC.'],
        [
          'Forwarded prefixes',
          forwarded.length ? (
            <Stack gap={2} key="forwarded">
              {forwarded.map((f) => (
                <Text size="sm" key={f.prefix}>
                  <CodeChip>{f.prefix}</CodeChip> goes to <CodeChip>{f.class}</CodeChip>
                  {f.note ? `: ${f.note}` : ''}
                </Text>
              ))}
            </Stack>
          ) : undefined,
        ],
      ]}
    />
  );
}

const KINDS: { value: Kind; label: string }[] = [
  { value: 'all', label: 'Reads and changes' },
  { value: 'reads', label: 'Reads only' },
  { value: 'changes', label: 'Changes only' },
];

/**
 * The API reference: every route of the REST API this app uses, from docs/api/openapi.json, read at build time. A
 * Technical page (the navigation shows it under that setting): the routes in their groups, each opening to what it
 * needs, takes and answers, with a curl line to copy; the shapes they share below; and, first, how to call it at all.
 * `?op=<operationId>` in the address opens that route.
 */
export default function ApiPage() {
  const [params] = useSearchParams();
  const routes = useMemo(() => routesOf(), []);
  const [filter, setFilter] = useState<Filter>(NO_FILTER);
  const [open, setOpen] = useState<string[]>(() => {
    const op = params.get('op');
    return op && routes.some((r) => r.id === op) ? [op] : [];
  });
  const [openShapes, setOpenShapes] = useState<string[]>([]);
  const shown = useMemo(() => filterRoutes(routes, filter), [routes, filter]);
  const groups = useMemo(() => groupsOf(shown), [shown]);
  const resources = useMemo(() => allResources(routes), [routes]);
  const shapes = useMemo(
    () => Object.entries(API.components?.schemas ?? {}).sort(([a], [b]) => a.localeCompare(b)),
    [],
  );
  const documentText = useMemo(() => JSON.stringify(API, null, 2), []);
  const origin = TRIAL ? TRIAL_ORIGIN : window.location.origin;
  const openShape = useCallback((name: string) => {
    setOpenShapes((prev) => (prev.includes(name) ? prev : [...prev, name]));
    requestAnimationFrame(() => {
      const item = document.getElementById(`shape-${name}`);
      item?.scrollIntoView({ block: 'start' });
      item?.querySelector('button')?.focus();
    });
  }, []);
  return (
    <OpenShape.Provider value={openShape}>
      <Stack gap="lg">
        <PageHeader
          title="API reference"
          icon={IconApi}
          hue={API_HUE}
          lead={`${routes.length} routes under ${BASE_PATH}, as the server builds them: what each needs, takes and answers.`}
          meta={
            <>
              <Text size="sm" c="dimmed">
                {API.info.title} {API.info.version}, OpenAPI {API.openapi}
              </Text>
              <Text size="sm" c="dimmed">
                From <CodeChip>docs/api/openapi.json</CodeChip>
              </Text>
            </>
          }
          actions={<Copy value={documentText} label="Copy the document" />}
          detailsLabel="Where this comes from"
          details={
            <Text size="sm" maw="80ch">
              The document is docs/api/openapi.json in the repository, read into this page when it is built.
              CI checks it against the routes of Shutter.API.Dispatch (scripts/check-openapi.py): every route
              has an operation here, every operation a route, and each says the resource and the write flag
              the route's own check says. Any OpenAPI reader opens the same file: Swagger UI, Redoc, or an
              import into Postman. The shapes below are the ones web/src/api/types.ts reads.
            </Text>
          }
        />
        <Section
          id="api-calling"
          title="Calling it"
          note="Sign in once, say it is you on every change, and read the error's code."
        >
          <CallingIt origin={origin} />
        </Section>
        <Section
          id="api-routes"
          title="Routes"
          note="By what they are about, in the document's order. Open a route for its parameters, body, replies and a curl line."
          aside={
            <Badge color="gray" variant="light" size="sm" style={{ textTransform: 'none' }}>
              {shown.length === routes.length
                ? `${routes.length} routes`
                : `${shown.length} of ${routes.length} routes`}
            </Badge>
          }
        >
          <Group gap="sm" align="flex-end" wrap="wrap">
            <TextInput
              label="Find"
              placeholder="A path, a word or a code"
              leftSection={<IconSearch size={16} aria-hidden />}
              value={filter.query}
              onChange={(e) => setFilter({ ...filter, query: e.currentTarget.value })}
              style={{ flex: '1 1 240px' }}
            />
            <NativeSelect
              label="Show"
              data={KINDS}
              value={filter.kind}
              onChange={(e) => setFilter({ ...filter, kind: e.currentTarget.value as Kind })}
            />
            <NativeSelect
              label="Needs"
              data={[{ value: '', label: 'Any resource' }, ...resources.map((r) => ({ value: r, label: r }))]}
              value={filter.resource}
              onChange={(e) => setFilter({ ...filter, resource: e.currentTarget.value })}
            />
          </Group>
          {groups.length === 0 ? (
            <Text size="sm" c="dimmed">
              No route matches. Clear the filter to see every route.
            </Text>
          ) : null}
          {groups.map((group) => (
            <Stack
              gap="xs"
              key={group.tag}
              component="section"
              aria-labelledby={`api-tag-${group.tag.replace(/\s+/g, '-')}`}
            >
              <Group gap="xs" align="baseline" wrap="wrap">
                <Title order={3} id={`api-tag-${group.tag.replace(/\s+/g, '-')}`}>
                  {tagLabel(group.tag)}
                </Title>
                {group.description ? (
                  <Text size="sm" c="dimmed">
                    {group.description}
                  </Text>
                ) : null}
              </Group>
              <Accordion multiple value={open} onChange={setOpen} variant="separated" chevronPosition="left">
                {group.routes.map((route) => (
                  <Accordion.Item value={route.id} key={route.id} id={`route-${route.id}`}>
                    <Accordion.Control>
                      <RouteLine route={route} />
                    </Accordion.Control>
                    <Accordion.Panel>
                      {open.includes(route.id) ? <RouteDetail route={route} origin={origin} /> : null}
                    </Accordion.Panel>
                  </Accordion.Item>
                ))}
              </Accordion>
            </Stack>
          ))}
        </Section>
        <Section
          id="api-shapes"
          title="Shapes"
          note="The JSON the routes take and send, by the names the document gives them; the web application's types carry the same names."
          aside={
            <Badge color="gray" variant="light" size="sm" style={{ textTransform: 'none' }}>
              {shapes.length} shapes
            </Badge>
          }
        >
          <Accordion
            multiple
            value={openShapes}
            onChange={setOpenShapes}
            variant="separated"
            chevronPosition="left"
          >
            {shapes.map(([name, schema]) => (
              <Accordion.Item value={name} key={name} id={`shape-${name}`}>
                <Accordion.Control>
                  <Group gap="xs" wrap="wrap" align="center">
                    <CodeChip>{name}</CodeChip>
                    <Text size="sm" c="dimmed" style={{ flex: '1 1 200px', minWidth: 0 }}>
                      {firstSentence(schema.description) || typeName(schema)}
                    </Text>
                  </Group>
                </Accordion.Control>
                <Accordion.Panel>
                  {openShapes.includes(name) ? (
                    <Stack gap="sm">
                      {schema.description && schema.description !== firstSentence(schema.description) ? (
                        <Text size="sm" maw="80ch">
                          {schema.description}
                        </Text>
                      ) : null}
                      <SchemaTable schema={schema} label={name} />
                      {schema.examples?.length ? (
                        <Part title="Example, from the recorded demo">
                          <JsonBlock value={schema.examples[0]} label={`Example of ${name}`} />
                        </Part>
                      ) : null}
                    </Stack>
                  ) : null}
                </Accordion.Panel>
              </Accordion.Item>
            ))}
          </Accordion>
        </Section>
      </Stack>
    </OpenShape.Provider>
  );
}
