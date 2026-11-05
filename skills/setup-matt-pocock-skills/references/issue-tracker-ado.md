# Issue tracker: Azure DevOps

Specs and tickets for this repo live as Azure DevOps work items. Use the Azure DevOps MCP server for every operation.

- **Organization**: `<org>` (`https://dev.azure.com/<org>`)
- **Project**: `<project>`
- **Team**: `<team>` (whose board and sprints the stories go on)
- **Area path**: `<the team's area path>` (set on every work item you create, or it won't show on the team's board)
- **Process**: Agile (Feature → User Story → Task; states New → Active → Resolved → Closed)

The team works from the board and in sprints, both at the User Story level. The User Story is the unit that gets planned, pulled into a sprint and moved across the board; Tasks are the steps inside it.

## Hierarchy

| Skill term | Work item type | Created by |
|---|---|---|
| Spec (`/to-spec`) | **Feature** | `/to-spec` |
| Ticket (`/to-tickets`) | **User Story**, child of the Feature | `/to-tickets` |
| Ticket step | **Task**, child of the User Story | `/to-tickets`, with the story |

Never create Epics, and never edit a Feature's parent.

## Tasks

Every User Story gets **2–6 Tasks**: the concrete steps that deliver it, in the order they will be done. Where they apply, use steps like: prefactor, the failing test at the agreed seam, the implementation that turns it green, docs or migration. A story too small for two steps doesn't need Tasks; a story that needs more than six is too big and should be split.

- Tasks don't block each other and get no Predecessor links: blocking lives between stories. Order them by numbering the titles (`1. …`, `2. …`).
- A Task title is the step itself ("Add failing test for supply-temperature clamp at the network seam"); the description holds detail only when the title can't.
- Tasks inherit the story's area path and iteration.

## Sprints

The sprint is chosen per run, not stored here, because it changes every iteration. Before publishing, list the team's sprints (`work` `list_team_iterations`, and `timeframe: current` for the active one) and ask the user where the stories go, recommending one:

- **Current sprint**: for work starting now.
- **A named upcoming sprint**.
- **Backlog**: the team's backlog iteration (`work` `get_team_settings`), so the stories sit on the board until sprint planning.

The Feature from `/to-spec` gets no sprint: set only its area path.

## Tools

These are the tool names in `microsoft/azure-devops-mcp` as of October 2026. Older server versions use one tool per operation (`wit_get_work_item`, `wit_create_work_item`, `wit_work_items_link`, …). If the names differ, use the tool whose description matches the operation.

- `wit_work_item`: read (actions `get`, `get_batch`, `list_comments`, `get_type`)
- `wit_query`: query (action `wiql`)
- `wit_work_item_write`: create and update (actions `create`, `update`, `update_batch`, `add_child`)
- `wit_work_item_link_write`: links (action `link`, with link type `parent` or `predecessor`)
- `wit_work_item_comment_write`: comments (action `add`)
- `work`: sprints and team settings (actions `list_team_iterations`, `get_team_settings`)

Write long text fields (Description, Acceptance Criteria) with format `Markdown`.

## Conventions

- **Create a work item**: `wit_work_item_write` `create`, with `System.Title`, `System.Description`, `System.AreaPath`, `System.IterationPath` (stories and Tasks) and `System.Tags`.
- **Create Tasks under a story**: `wit_work_item_write` `add_child` with the story as `parentId`, `workItemType` `Task`, and the story's area and iteration paths.
- **Read a work item**: `wit_work_item` `get` with expand `Relations`, then `list_comments`. The user may write a reference as `1234`, `#1234` or `AB#1234`; all three mean ID 1234.
- **Make a work item a child of a parent**: `wit_work_item_link_write` `link` on the child, type `parent`, pointing at the parent ID.
- **Blocking**: a **Predecessor** link, between stories only. On the blocked story, add a link of type `predecessor` pointing at the blocker. A story is unblocked when every predecessor is Resolved, Closed or Removed.
- **Count open blockers**: `get` with expand `Relations`, collect the `System.LinkTypes.Dependency-Reverse` targets, `get_batch` them, and count those not in Resolved, Closed or Removed. Zero means startable.
- **Comment**: `wit_work_item_comment_write` `add`.
- **Labels**: triage labels are **tags**. Add one by appending it to `System.Tags` (tags are `; `-separated; keep the existing ones).
- **Close**: add a comment explaining why, then set `System.State` to `Closed`. If the project's states differ, read them with `wit_work_item` `get_type` and use the closed-category state.

Create work items only in the project above. Before the first write of a session, confirm the organization, project and team with the user if the conversation has not already named them.

## When a skill says "publish to the issue tracker"

- **A spec** (`/to-spec`): create a **Feature**. The spec goes in `System.Description`. Tag it `ready-for-agent`.
- **Tickets** (`/to-tickets`): when presenting the breakdown for approval, list each ticket's Tasks under it, so the user approves stories and Tasks together. After approval, ask for the sprint (see **Sprints**), then create one **User Story** per ticket, in dependency order (blockers first), so each Predecessor link can point at a real ID:
  - Title: the ticket title.
  - `System.Description`: the "What to build" section.
  - `Microsoft.VSTS.Common.AcceptanceCriteria`: the acceptance-criteria checklist. Leave it out of the description.
  - `System.IterationPath`: the chosen sprint.
  - Tag: `ready-for-agent`.
  - Link each story to its Feature as `parent`, and to each blocker as `predecessor`. Omit the "Blocked by" and "Parent" sections from the description, because the links carry them.
  - Create the story's Tasks (see **Tasks**) right after the story.
  - If the source was not a Feature (a conversation or a local spec file), ask the user which Feature to parent the stories under, or whether to create one first with `/to-spec`.

## When a skill says "fetch the relevant ticket"

Read it as in **Read a work item** above. For a User Story, also read its parent Feature (the spec lives there) and its child Tasks (the steps, in title order).

## When `/implement` works a User Story

The board shows progress, so keep states current:

1. Before any code: assign the story to the user and set it to `Active`.
2. Work the Tasks in order. Set each Task to `Active` when starting it and `Closed` when it is done. If the work needs a step no Task covers, add a Task for it rather than doing it silently.
3. When the story's work is committed: set the story to `Resolved` and add a comment with the commit. Leave `Closed` to the user, who accepts the story.
