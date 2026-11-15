# Issue tracker: GitHub, tickets inside the spec

Specs live as GitHub issues. Their tickets do not: every ticket of a spec lives as a section in the spec issue's body, so one issue holds the whole plan. Use the `gh` CLI for all operations.

## Conventions

- **Create an issue**: `gh issue create --title "..." --body "..."`. Use a heredoc for multi-line bodies.
- **Read an issue**: `gh issue view <number> --json number,title,body,labels,comments`.
- **List issues**: `gh issue list --state open --json number,title,labels` with appropriate `--label` and `--state` filters.
- **Comment on an issue**: `gh issue comment <number> --body "..."`
- **Apply / remove labels**: `gh issue edit <number> --add-label "..."` / `--remove-label "..."`
- **Close**: post the explanation with `gh issue comment <number> --body "..."`, then `gh issue close <number>`.

Infer the repo from `git remote -v`; `gh` does this automatically when run inside a clone.

## Tickets

A spec's tickets go into a `## Tickets` section at the end of the spec issue's body, never into issues of their own. Edit the body with `gh issue edit <spec> --body-file <file>`, keeping everything above the section unchanged.

Each ticket is a `###` heading numbered in dependency order (blockers first), shaped like this:

```markdown
### T1: <Ticket title>

- [ ] Done

**Blocked by:** None (can start immediately) | T<n>, T<n>

**What to build:** the end-to-end behaviour this ticket makes work.

**Acceptance criteria:**

- [ ] Criterion 1
- [ ] Criterion 2
```

- **Refer to a ticket** as `#<spec> T<n>`.
- **Blocking**: a ticket is unblocked when every ticket in its "Blocked by" line has its `Done` box ticked.
- **Resolve a ticket**: tick its `Done` box (and the criteria it met) in the spec body. The spec issue closes with the PR that implements it (`Closes #<spec>`).

## When a skill says "publish to the issue tracker"

For a spec, create a GitHub issue. For tickets, add them to the spec issue's `## Tickets` section as above; do not create issues.

## When a skill says "fetch the relevant ticket"

Read the spec issue as in **Read an issue** and take the ticket's section from its body.
