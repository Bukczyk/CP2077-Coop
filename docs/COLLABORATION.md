# KyleBuildsAI and Bukczyk: collaboration guide

Prepared 2026-10-05. **Approved by KyleBuildsAI for publication; proposed for Bukczyk's review.** Publication does not establish mutual acceptance, completed feature transfers or a runtime migration. Once accepted, maintain this guide in the shared repository; local knowledge bases should link here and identify their revision.

Start with [Shared goals and work split](SHARED_GOALS.md) for the plain-English goals, each person's part and the tests to run together.

## Project direction

KyleBuildsAI and Bukczyk are developing one shared Cyberpunk 2077 multiplayer project in **Bukczyk/CP2077-Coop**.

New shared development belongs in this repository. [KyleBuildsAI's existing repository](https://github.com/KyleBuildsAI/cp2077-coop) provides working features, research, testing tools and the v0.0.37 reference build. Its useful components should be evaluated and integrated through specific tasks.

Selecting a shared repository does not mean all previous features have already been transferred.

Use [ARCHITECTURE.md](../ARCHITECTURE.md), [MIGRATION_PLAN.md](../MIGRATION_PLAN.md) and the [session runtime notes](../runtime/session/README.md) for technical status. Check their evidence and current source rather than treating a design goal as implemented behavior.

## Responsibilities

| Owner | Responsibilities |
|---|---|
| **Bukczyk** | Session/server architecture, networking protocol, player/entity identities, ownership, epochs, reconnect, catalog restoration, interest management and authoritative NPC/world networking |
| **KyleBuildsAI** | Live REDengine integration, player presentation and animation, map/UI, vehicle and seat engine hooks, live-game testing and measurement |
| **Both** | Interfaces between those systems, acceptance tests, integration review and release decisions |

Repository ownership and technical responsibility are separate. Changes affecting both areas require coordination between both maintainers.

## Instructions for every AI session

Before implementing anything:

1. Read the repository instructions, this guide, the current milestone and the latest relevant handoff.
2. Check existing code, active tasks and open PRs. Determine whether the requested work already exists or is underway.
3. Confirm which maintainer owns the task and which files it will change.
4. Identify the existing interfaces the implementation must use.
5. Work on a task branch. Do not write directly to `main`.

Questions and requests for explanation authorize discussion and inspection. They do not authorize implementation or publication. Follow the directing maintainer's explicit instructions about when to edit, push or open a PR.

Once a maintainer assigns implementation within an agreed area, proceed within that scope. Additional coordination is needed when changing another owner's files, a shared interface or the agreed behavior.

## Preventing overlap

Each active task must have a shared record, such as a GitHub issue or PR, containing:

```text
Task and owner:
Branch and starting commit:
Exact files being changed:
Dependencies or shared interface:
Expected result and acceptance checks:
Current status:
```

Task ownership continues while its owner is asleep or offline. Do not take over unfinished work without an explicit handoff. A private local note does not communicate a claim to the other maintainer.

A file used by both areas must have one named editor for the relevant task. Separate branches do not make simultaneous rewrites of the same shared code safe.

If work is blocked by another task, record the dependency and continue independent assigned work. Do not build a competing implementation to bypass it.

## Keeping the pieces compatible

Both sides must use one agreed interface definition.

That definition records:

- Exact function names, inputs and outputs.
- Identity types, units and timing conventions.
- Which side owns each decision.
- Creation, update, removal and reconnect behavior.
- Failure responses and unsupported operations.
- The test that demonstrates both sides work together.

Use existing interfaces where suitable. Proposed additions must be identified as proposals until reviewed. Neither AI may silently rename calls, change their meaning or invent an incompatible alternative.

## Integrating existing work

Maintain a feature migration list with:

```text
Feature:
Source repository and commit:
Existing implementation in the shared repository:
Decision: reuse, adapt, replace or defer:
Owner and task:
Integration PR:
Verification status:
```

Start by accounting for KyleBuildsAI's minimap, movement fixes, vehicle findings, testing tools and packaging workflow.

Do not describe a feature as integrated merely because it was reviewed, copied or mentioned in a plan. Record the merged change and the checks actually completed.

## Immediate joint milestone

HOST and JOINER see the same stable NPC. JOINER can cause a supported stimulus or hit. HOST decides the AI and damage result. Both clients display the same reaction or death.

- **Bukczyk:** Provide the agreed identity, networking, authoritative result and recovery mechanisms.
- **KyleBuildsAI:** Provide and verify the engine representation, movement, interaction and reaction hooks.
- **Both:** Agree on the interface and test before implementing connected changes.

The first engine investigation is a visible, movable JOINER representation that does not make independent AI decisions. A proposed class or method is a research candidate until verified.

This milestone identifies the direction; it does not claim an implementation task or reserve files for either maintainer.

## Handoffs and review

Before ending an implementation session, push the assigned branch when authorized and record:

```text
UTC timestamp:
Latest commit and PR:
Completed work:
Remaining work:
Tests run and results:
Known failures:
Next action:
Ownership retained or explicitly transferred:
```

PRs should explain the behavior changed, affected interfaces and verification results. Changes crossing responsibility boundaries require the other maintainer's review before merging.

Distinguish automated tests, script compilation, local game tests and two-PC tests. Report only evidence actually obtained.
