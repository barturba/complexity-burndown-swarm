# Complexity Burndown Swarm

A tiny local coordinator for burning down cyclomatic complexity with multiple AI coding agents.

This is not a feature-building framework. It is deliberately narrow: scan a target repo for complex Ruby methods, put the methods into SQLite-backed batches, let isolated worktree agents claim one batch at a time, and merge completed branches back through a single lock.

It also includes a small Ruby duplicate-code finder. It uses normalized `Ripper` syntax fingerprints and Jaccard similarity to report methods with similar structure, even when names and literal values differ.

It was extracted from a real Rails cleanup run and scrubbed for public use. The repo contains no live queue database, process IDs, logs, private project paths, generated reports, or application code.

## What It Is Good For

- Mechanical refactors where the success metric is objective.
- Reducing `Metrics/CyclomaticComplexity` in Ruby/Rails repos.
- Finding candidate duplicate Ruby methods before assigning cleanup work.
- Running several low-reasoning agents safely because each gets a narrow file/method list.
- Keeping merge state explicit instead of trusting agents to coordinate in chat.

## What It Is Bad For

- Product features.
- UX/copy decisions.
- Anything where agents need to invent the acceptance criteria.

## Architecture

The swarm has four parts:

- `bin/burndown`: SQLite coordinator. It scans complexity, creates batches, claims work, records completion, writes a Markdown status file, and serializes merges with a lock.
- `bin/burndown-worktrees`: creates or reuses target-repo worktrees such as `agent-A`, `agent-B`, `agent-C`, and `agent-D`.
- `bin/burndown-tmux`: opens a 2x2 tmux session in those worktrees.
- AI agents: each agent reads `bin/burndown prompt <agent>`, edits only the listed methods, runs focused checks, commits, and records completion.

The default worker set is `A B C D`. That is usually enough. More workers increase merge pressure faster than they increase useful throughput.

## Requirements

- Ruby
- `sqlite3` Ruby gem
- Git
- Bundler and RuboCop available in the target repo
- tmux, optional
- Codex or another coding agent, optional

Install the SQLite gem if your system Ruby does not already have it:

```bash
gem install sqlite3
```

## Quick Start

Clone this repo next to the target repo:

```bash
git clone https://github.com/barturba/complexity-burndown-swarm.git
cd target-rails-repo
```

Initialize state and worktrees:

```bash
../complexity-burndown-swarm/bin/burndown init
../complexity-burndown-swarm/bin/burndown refresh
../complexity-burndown-swarm/bin/burndown backfill 2 6
../complexity-burndown-swarm/bin/burndown-worktrees init
../complexity-burndown-swarm/bin/burndown-tmux
```

In an agent pane:

```bash
../complexity-burndown-swarm/bin/burndown prompt A
```

Give that prompt to the coding agent running in the `agent-A` worktree.

## Typical Agent Loop

Each worker should do exactly this:

1. Claim one batch: `bin/burndown claim A`.
2. Merge latest `main` into its worktree branch.
3. Edit only the files and methods listed in the batch.
4. Reduce methods below the next useful threshold.
5. Run `git diff --check`, touched-file RuboCop, and one focused test when obvious.
6. Commit.
7. Record completion: `bin/burndown complete A <batch_id> <commit_sha> '<checks>'`.
8. Run `bin/burndown self-merge A <batch_id>` only if the merge is clean and obvious.
9. If the merge conflicts or looks non-trivial, abort and mark conflict: `bin/burndown conflict A <batch_id> '<files/reason>'`.

Do not let workers resolve broad conflicts casually. Conflict resolution is where mechanical cleanup becomes accidental product work.

## Commands

```bash
bin/burndown init
bin/burndown refresh
bin/burndown backfill [target_open=2] [batch_size=6]
bin/burndown claim <agent>
bin/burndown complete <agent> <batch_id> <commit_sha> '<checks>'
bin/burndown self-merge <agent> <batch_id>
bin/burndown conflict <agent> <batch_id> '<notes>'
bin/burndown status
bin/burndown prompt <agent>
bin/burndown write-md
```

Worktree helpers:

```bash
bin/burndown-worktrees init
bin/burndown-worktrees status
bin/burndown-worktrees path A
bin/burndown-worktrees sync
bin/burndown-tmux
```

Duplicate finder:

```bash
bin/ruby-duplicates [options] [file-or-directory ...]
```

## Configuration

Environment variables:

- `BURNDOWN_TARGET_REPO`: target repo path. Defaults to the current directory.
- `BURNDOWN_STATE_DIR`: state directory. Defaults to `.burndown-swarm` in the target repo.
- `BURNDOWN_AGENTS`: space-separated worker labels. Defaults to `A B C D`.
- `BURNDOWN_BRANCH_PREFIX`: branch prefix. Defaults to `agent`.
- `BURNDOWN_TARGET_MIN_CC`: minimum complexity to queue. Defaults to `5`.
- `BURNDOWN_WORKTREES_DIR`: parent directory for worktrees. Defaults to a sibling `<repo>-burndown-worktrees` directory.
- `BURNDOWN_TMUX_SESSION`: tmux session name. Defaults to `burndown-swarm`.

Example:

```bash
BURNDOWN_AGENTS="A B" BURNDOWN_TARGET_MIN_CC=8 bin/burndown backfill 1 4
```

## Duplicate Code Metric

`bin/ruby-duplicates` is a simple Ruby version of the structural metric used by `dry4clj`: normalize syntax, fingerprint subtrees, then compare methods with Jaccard similarity.

```bash
bin/ruby-duplicates app lib test
bin/ruby-duplicates --threshold 0.9 --min-lines 5 --min-nodes 30 app
bin/ruby-duplicates --json app/models app/controllers
```

Options:

```bash
--threshold N    Minimum similarity score, default 0.82
--min-lines N    Minimum method source lines, default 4
--min-nodes N    Minimum normalized syntax nodes, default 20
--max-results N  Maximum matches to print, default 50
--format F       text or json, default text
--json           Same as --format json
--ignore-dir N   Directory basename or path to skip; may be repeated
```

Example output:

```text
DUPLICATE score=1.00 shared=21
  examples/duplicate_sample.rb:1-4 alpha nodes=64
  examples/duplicate_sample.rb:7-10 beta nodes=64
```

## State Files

By default, generated state lives under the target repo in `.burndown-swarm/`:

- `coordination.sqlite3`
- `current-complexity.tsv`
- `BURNDOWN_COORDINATION.md`

These files are local operating state. Do not commit them to your application repo.

## Safety Rules

- Keep `main` clean before merging completed branches.
- Merge one worker branch at a time.
- Prefer smaller batches over bigger batches.
- Do not create new complex helper methods to hide old complex methods.
- Do not run this against uncommitted user work unless you intend to manage that work manually.
- Treat failing focused tests as a stop signal, not noise.

## Why SQLite

Markdown is readable but weak as a lock. SQLite gives the swarm atomic claims, a merge lock, durable completion state, and a cheap audit trail. The Markdown file is generated from SQLite for human scanning.

## Sanitization Note

This public repo intentionally excludes:

- real queue databases
- process IDs
- tmux pane IDs
- generated complexity reports from private code
- private file paths
- private prompts
- commit history from the source project

Only the generic workflow and scripts are included.
