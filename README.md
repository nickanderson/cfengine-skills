# CFEngine Skills for Claude Code

Skills that teach [Claude Code](https://code.claude.com/) how to work with
CFEngine policy.

## Skills

| Skill | Purpose |
|-------|---------|
| `cfengine-policy` | Write, review, and debug CFEngine `.cf` files, augments, and cfbs projects |

## Install

Clone into your Claude Code skills directory:

```bash
git clone https://github.com/nickanderson/cfengine-skills-public.git \
    ~/.claude/skills/cfengine-skills
```

The skill will appear as `/cfengine-policy` in Claude Code.

## What it does

On first use the skill:

1. Clones the [CFEngine documentation](https://github.com/cfengine/documentation)
   repo, matching the branch to your installed `cf-agent` version
2. Checks for missing tools (`cf-agent`, `cf-promises`, `cfengine` CLI) and
   prints install guidance
3. Loads a concise policy language reference into context

The documentation checkout is cached at `~/.local/share/cfengine/docs/` and
updated weekly. Override with `CFENGINE_DOCS_DIR`.

## Staying up to date

The skill also checks whether its own checkout has fallen behind this repo, and
tells Claude to ask you before doing anything about it. It never updates itself:
the update is a `git pull` in your checkout, so it is yours to approve.

It is built to stay out of your way.

- Silent when there is nothing to decide. It prints only when the skill itself
  has changed upstream.
- Commits that do not touch the skill -- eval results, tests, this README --
  are not worth interrupting you for, and do not trigger a notice.
- It fetches at most weekly, and re-raises a notice you have already seen at
  most weekly. A new upstream version re-notifies immediately.
- Uncommitted local edits to the skill are reported, never discarded. If you
  have edited the skill *and* upstream has moved, it says so and declines to
  hand over a pull command.
- A failed fetch, an unreachable remote, or a copied-in (non-git) install all
  exit quietly. A skill that fails to render because the network is down is
  worse than a skill that is a week stale.

| Variable | Effect |
|----------|--------|
| `CFENGINE_SKILL_UPDATE_DISABLE=1` | Turn the check off entirely |
| `CFENGINE_SKILL_UPDATE_INTERVAL_DAYS` | Days between fetches (default 7) |
| `CFENGINE_SKILL_UPDATE_NOTICE_DAYS` | Days before repeating a notice (default 7) |

## Tests

```bash
tests/test-ensure-docs.sh          # documentation checkout behaviour
tests/test-check-skill-update.sh   # update-check behaviour
```

Both are hermetic -- local fixture repos stand in for the remotes, so they need
no network and no CFEngine install.

## Prerequisites

- [Claude Code](https://code.claude.com/)
- `cf-remote` -- optional but recommended. Tooling to provision install and bootstrap CFEngine. (https://github.com/cfengine/cf-remote) (`uv tool install cf-remote`).
- CFEngine CLI -- optional but recommended. Tooling to help work with CFEngine and policy. (https://github.com/cfengine/cfengine-cli) (`uv tool install cfengine`).
- CFEngine (`cf-agent`) -- optional but recommended. Install from
  [cfengine.com/downloads](https://cfengine.com/downloads) or via `cf-remote` or `cfengine` CLI

## License

Apache 2.0
