#!/usr/bin/env node
// Dependency updates merged into main make a patch release (ci.yml, the dependency-release-build
// job): this writes the release's CHANGELOG section from the Dependabot commits since the last
// version tag, whose messages name each package and its versions, and prints the same lines for
// the GitHub release. It reads the history rather than a push, so updates merged together, or
// whose own run a newer push replaced, are all named. The section goes before the newest version's
// section, after "## Unreleased", which keeps what the next feature release will say. The version
// itself is written by scripts/check-versions.py --set.
//
// Usage: node scripts/dependency-release.mjs <version> <last version tag>
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';

const [version, since] = process.argv.slice(2);
if (!/^\d+\.\d+\.\d+$/.test(version ?? '') || !since) {
  console.error('usage: dependency-release.mjs <major.minor.patch> <last version tag>');
  process.exit(1);
}
// Oldest first; %x1e (the record separator) ends each message, which never contains it.
const messages = execFileSync(
  'git',
  ['log', '--reverse', '--author=dependabot\\[bot\\]', '--format=%B%x1e', `${since}..HEAD`],
  { encoding: 'utf8' },
)
  .split('\x1e')
  .map((message) => message.trim())
  .filter(Boolean);

const bullets = [];
for (const message of messages) {
  const [title, ...body] = message.split('\n');
  if (!/^Bump\b/.test(title)) continue;
  // "Updates `@tabler/icons-react` from 3.46.0 to 3.48.0" lines of a grouped update, or the title
  // of a single one ("Bump globals from 16.5.0 to 17.12.0 in /web"), which already names the versions.
  const updates = body
    .map((line) => line.trim())
    .map((line) => /^Updates? `([^`]+)` from (\S+) to (\S+)/.exec(line))
    .filter(Boolean)
    .map((m) => `${m[1]} ${m[2]} to ${m[3]}`);
  const clean = title.replace(/\s+\(#\d+\)$/, '');
  bullets.push(updates.length ? `- ${clean}: ${updates.join(', ')}.` : `- ${clean}.`);
}
if (!bullets.length) bullets.push('- Dependency updates merged from Dependabot.');

const date = new Date().toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric' });
const section = `## ${version} - Dependency updates (${date})\n\n${bullets.join('\n')}\n\n`;
const path = 'CHANGELOG.md';
const text = readFileSync(path, 'utf8');
const at = text.search(/^## \d/m);
writeFileSync(
  path,
  at < 0 ? `${text.trimEnd()}\n\n${section}` : text.slice(0, at) + section + text.slice(at),
);
process.stdout.write(`${bullets.join('\n')}\n`);
