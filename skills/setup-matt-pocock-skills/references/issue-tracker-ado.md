# Issue tracker: Azure DevOps

Specs and tickets for this repo live as Azure DevOps work items. Use the Azure DevOps MCP server for every operation.

- **Organization**: `<org>` (`https://dev.azure.com/<org>`)
- **Project**: `<project>`
- **Area path**: `<area path>` (set on every work item you create)
- **Iteration path**: `<iteration path, or "leave unset">`
- **Process**: Agile (Feature → User Story → Task; states New → Active → Resolved → Closed)

## Hierarchy

| Skill term | Work item type | Created by |
|---|---|---|
| Spec (`/to-spec`) | **Feature** | `/to-spec` |
| Ticket (`/to-tickets`) | **User Story**, child of the Feature | `/to-tickets` |
| Step inside a ticket | **Task**, child of the User Story | Only when the user asks for Tasks |

Never create Epics, and never edit a Feature's parent. Don't create Tasks on your own initiative: they are the team's breakdown of a User Story. When the user asks for them (often while running `/implement` on a story), create them as children of that User Story.

## Tools

These are the tool names in `microsoft/azure-devops-mcp` as of October 2026. Older server versions use one tool per operation (`wit_get_work_item`, `wit_create_work_item`, `wit_work_items_link`, …). If the names differ, use the tool whose description matches the operation.

- `wit_work_item`: read (actions `get`, `get_batch`, `list_comments`, `get_type`)
- `wit_query`: query (action `wiql`)
- `wit_work_item_write`: create and update (actions `create`, `update`, `add_child`)
- `wit_work_item_link_write`: links (action `link`, with link type `parent`, `child` or `predecessor`)
- `wit_work_item_comment_write`: comments (action `add`)

Write long text fields (Description, Acceptance Criteria) with format `Markdown`.

## Conventions

- **Create a work item**: `wit_work_item_write` `create`, with `System.Title`, `System.Description`, `System.AreaPath`, `System.IterationPath` (when configured) and `System.Tags`.
- **Read a work item**: `wit_work_item` `get` with expand `Relations`, then `list_comments`. The user may write a reference as `1234`, `#1234` or `AB#1234`; all three mean ID 1234.
- **Make a work item a child of a parent**: `wit_work_item_link_write` `link` on the child, type `parent`, pointing at the parent ID.
- **Blocking**: a **Predecessor** link. On the blocked work item, add a link of type `predecessor` pointing at the blocker. A work item is unblocked when every predecessor is Resolved, Closed or Removed.
- **Count open blockers**: `get` with expand `Relations`, collect the `System.LinkTypes.Dependency-Reverse` targets, `get_batch` them, and count those not in Resolved, Closed or Removed. Zero means startable.
- **Comment**: `wit_work_item_comment_write` `add`.
- **Labels**: triage labels are **tags**. Add one by appending it to `System.Tags` (tags are `; `-separated; keep the existing ones).
- **Close**: add a comment explaining why, then set `System.State` to `Closed`. If the project's states differ, read them with `wit_work_item` `get_type` and use the closed-category state.

Create work items only in the project above. Before the first write of a session, confirm the organization and project with the user if the conversation has not already named them.

## When a skill says "publish to the issue tracker"

- **A spec** (`/to-spec`): create a **Feature**. The spec goes in `System.Description`. Tag it `ready-for-agent`.
- **Tickets** (`/to-tickets`): create one **User Story** per ticket, in dependency order (blockers first), so each Predecessor link can point at a real ID:
  - Title: the ticket title.
  - `System.Description`: the "What to build" section.
  - `Microsoft.VSTS.Common.AcceptanceCriteria`: the acceptance-criteria checklist. Leave it out of the description.
  - Tag: `ready-for-agent`.
  - Link each story to its Feature as `parent`, and to each blocker as `predecessor`. Omit the "Blocked by" and "Parent" sections from the description, because the links carry them.
  - If the source was not a Feature (a conversation or a local spec file), ask the user which Feature to parent the stories under, or whether to create one first with `/to-spec`.

## When a skill says "fetch the relevant ticket"

Read it as in **Read a work item** above. For a User Story, also read its parent Feature: the spec lives there.
