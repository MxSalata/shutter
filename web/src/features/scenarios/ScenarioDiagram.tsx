import { useTechnical } from '@/stores/appearance';
import './ScenarioDiagram.css';
import type { Mode, Scenario } from '@/api/types';
import { scenarioDiagram, type DiagramEnd, type DiagramNode } from './scenarioDiagram';

/** The drawing's measures, in px: one row of marks, a row of captions under them, and the join between marks. */
const HEIGHT = 38;
const MARK_TOP = 1;
const MARK_HEIGHT = 20;
const MARK_MIDDLE = MARK_TOP + MARK_HEIGHT / 2;
const CAPTION_BASE = 34;
const JOIN = 8;
const ARROW = 10;

/** The width words take, a little over the system font's, since an SVG can't lay out text by itself; a browser test measures it. */
const wordsWidth = (text: string, perChar: number) => Math.ceil(text.length * perChar);
const markWidth = (text: string) => wordsWidth(text, 6) + 11;
const captionWidth = (text: string | undefined) => (text ? wordsWidth(text, 5.2) : 0);

interface Placed {
  key: string;
  width: number;
  draw: (x: number) => React.ReactNode;
}

/** The bolt of a fault at the receiver, and a person's head and shoulders: their shapes say it without colour. */
function Bolt({ cx }: { cx: number }) {
  return (
    <path
      className="diagram-fault"
      transform={`translate(${cx - 6} ${MARK_TOP + 3})`}
      d="M7.5 0 1 8h4l-1 6 7-8.5H6.8z"
    />
  );
}

function Person({ cx }: { cx: number }) {
  return (
    <g className="diagram-person" transform={`translate(${cx - 6} ${MARK_TOP + 4})`}>
      <circle cx="6" cy="3" r="2.8" />
      <path d="M0.8 13c0-3.2 2.3-5 5.2-5s5.2 1.8 5.2 5z" />
    </g>
  );
}

function Mark({
  x,
  width,
  text,
  className,
  cross = false,
}: {
  x: number;
  width: number;
  text: string;
  className: string;
  cross?: boolean;
}) {
  // A failed message carries a cross as well as its colour and its caption
  const crossAt = x + width - 12;
  return (
    <g className={className}>
      <rect x={x + 0.5} y={MARK_TOP + 0.5} width={width - 1} height={MARK_HEIGHT - 1} rx={5} />
      <text x={cross ? x + (width - 12) / 2 + 1 : x + width / 2} y={MARK_MIDDLE + 4} textAnchor="middle">
        {text}
      </text>
      {cross ? <path className="diagram-cross" d={`M${crossAt} ${MARK_MIDDLE - 3}l6 6m0-6l-6 6`} /> : null}
    </g>
  );
}

function Caption({
  x,
  width,
  text,
  className,
}: {
  x: number;
  width: number;
  text?: string;
  className?: string;
}) {
  if (!text) return null;
  return (
    <text
      className={`diagram-caption ${className ?? ''}`}
      x={x + width / 2}
      y={CAPTION_BASE}
      textAnchor="middle"
    >
      {text}
    </text>
  );
}

function placeNode(node: DiagramNode, technical: boolean, i: number): Placed {
  const key = `${i}`;
  const first = i === 0;
  switch (node.kind) {
    case 'fault':
    case 'person': {
      const width = Math.max(26, captionWidth(node.caption) + 7);
      return {
        key,
        width,
        draw: (x) => (
          <>
            {/* A caption can be wider than its mark: the line carries on to the mark, so the story stays joined */}
            {first ? null : (
              <line
                className="diagram-join"
                x1={x}
                x2={x + width / 2 - 8}
                y1={MARK_MIDDLE}
                y2={MARK_MIDDLE}
              />
            )}
            <line
              className="diagram-join"
              x1={x + width / 2 + 8}
              x2={x + width}
              y1={MARK_MIDDLE}
              y2={MARK_MIDDLE}
            />
            {node.kind === 'fault' ? <Bolt cx={x + width / 2} /> : <Person cx={x + width / 2} />}
            <Caption x={x} width={width} text={node.caption} />
          </>
        ),
      };
    }
    case 'messages': {
      // Not a failed mark: most of a long story arrives, and the caption says how many did not
      const text = `${node.total} sent`;
      const caption = `${node.failed} fail`;
      const width = Math.max(markWidth(text), captionWidth(caption));
      return {
        key,
        width,
        draw: (x) => (
          <>
            <Mark x={x} width={width} text={text} className="diagram-mark" />
            <Caption x={x} width={width} text={caption} className="diagram-caption-failed" />
          </>
        ),
      };
    }
    case 'message': {
      const name = technical ? node.event : node.plain;
      const text = node.count > 1 ? `${name} ×${node.count}` : name;
      const failed = node.mark === 'fails' || node.mark === 'refused';
      const caption =
        node.aside === 'source' ? 'bed manager' : node.aside === 'encounter' ? 'other visit' : node.mark;
      const width = Math.max(markWidth(text) + (failed ? 14 : 0), captionWidth(caption));
      const style = failed
        ? 'diagram-failed'
        : node.mark === 'withheld'
          ? 'diagram-withheld'
          : node.aside
            ? 'diagram-aside'
            : '';
      return {
        key,
        width,
        draw: (x) => (
          <>
            <Mark x={x} width={width} text={text} className={`diagram-mark ${style}`} cross={failed} />
            <Caption
              x={x}
              width={width}
              text={caption}
              className={failed ? 'diagram-caption-failed' : undefined}
            />
          </>
        ),
      };
    }
  }
}

function placeEnd(end: DiagramEnd): Placed {
  const width = Math.max(markWidth(end.label), captionWidth(end.caption));
  return {
    key: 'end',
    width,
    draw: (x) => (
      <>
        <g className={`diagram-end diagram-end-${end.kind}`}>
          <rect
            x={x + 0.75}
            y={MARK_TOP + 0.75}
            width={width - 1.5}
            height={MARK_HEIGHT - 1.5}
            rx={MARK_HEIGHT / 2 - 1}
          />
          <text x={x + width / 2} y={MARK_MIDDLE + 4} textAnchor="middle">
            {end.label}
          </text>
        </g>
        <Caption x={x} width={width} text={end.caption} />
      </>
    ),
  };
}

/**
 * A scenario's story in one small line, read from the scenario itself (`scenarioDiagram`): what is sent, what goes wrong
 * and what it should end in, in the mode the row or the card is showing. Every mark has its own shape and a word under
 * it, so nothing rests on colour; a screen reader gets the same in the label.
 */
export function ScenarioDiagram({ scenario, mode }: { scenario: Scenario; mode: Mode }) {
  const technical = useTechnical();
  const diagram = scenarioDiagram(scenario, mode, technical);
  if (!diagram) return null;
  const parts = diagram.nodes.map((n, i) => placeNode(n, technical, i));
  const end = placeEnd(diagram.end);
  let x = 0;
  const drawn: React.ReactNode[] = [];
  parts.forEach((part, i) => {
    drawn.push(<g key={part.key}>{part.draw(x)}</g>);
    x += part.width;
    if (i < parts.length - 1) {
      drawn.push(
        <line
          key={`${part.key}-join`}
          className="diagram-join"
          x1={x + 1}
          x2={x + JOIN - 1}
          y1={MARK_MIDDLE}
          y2={MARK_MIDDLE}
        />,
      );
      x += JOIN;
    }
  });
  drawn.push(
    <path
      key="arrow"
      className="diagram-arrow"
      d={`M${x + 2} ${MARK_MIDDLE}h${ARROW - 5}m-3.5-3.5l3.5 3.5l-3.5 3.5`}
    />,
  );
  x += ARROW;
  drawn.push(<g key={end.key}>{end.draw(x)}</g>);
  x += end.width;
  return (
    <svg
      className="scenario-diagram"
      role="img"
      aria-label={diagram.label}
      data-end={diagram.end.kind}
      width={x}
      height={HEIGHT}
      viewBox={`0 0 ${x} ${HEIGHT}`}
    >
      {drawn}
    </svg>
  );
}
