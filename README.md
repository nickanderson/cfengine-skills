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

## Prerequisites

- [Claude Code](https://code.claude.com/)
- CFEngine (`cf-agent`) -- optional but recommended. Install from
  [cfengine.com/downloads](https://cfengine.com/downloads) or via the
  `cfengine` CLI (`pipx install cfengine && cfengine install`)

## License

Apache 2.0
