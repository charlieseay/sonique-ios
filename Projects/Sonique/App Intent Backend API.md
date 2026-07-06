# App Intent Backend API

SoniqueBar HTTP routes invoked by iOS App Intents. Base URL: `http://<soniquebar-host>:8890`

## Common Response Shape

```json
{
  "success": true,
  "message": "Human-readable voice response",
  "error": null,
  "data": { "key": "value" }
}
```

Failure responses use HTTP `422` with `success: false` and a machine-readable `error` code.

| HTTP Status | Meaning |
|-------------|---------|
| 200 | Intent executed successfully |
| 400 | Malformed JSON body |
| 404 | Unknown intent name |
| 422 | Intent understood but execution failed |
| 503 | SoniqueBar unavailable (client maps to "brain offline") |

## Error Codes

| Code | Voice Message (typical) |
|------|-------------------------|
| `unreachable` | I can't reach the brain right now. |
| `missing_message` | Message is required. |
| `missing_title` | Title is required. |
| `slack_token_missing` | Slack token missing. Check Settings on the Mac. |
| `slack_failed` | Failed to post to Slack. |
| `linear_key_missing` | Linear CLI not found. Add linear_api_key to secrets. |
| `linear_api_failed` | Linear API rejected the request. |
| `linear_api_down` | Linear API is down. Try again later. |
| `gh_missing` | GitHub CLI not installed on the Mac. |
| `github_search_failed` | Couldn't search pull requests. |
| `notion_key_missing` | Notion API key not configured on the Mac. |
| `notion_db_missing` | Notion database ID not configured. |
| `notion_rate_limit` | Creating note — Notion is busy. |
| `docker_failed` | Couldn't list containers. |
| `timeout` | That took too long. Try again. |

---

## POST /intent/slack

Post a message to a Slack channel.

### Request

```json
{
  "message": "team meeting at 3pm",
  "channel": "sonique"
}
```

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `message` | string | yes | — | Message text |
| `channel` | string | no | `sonique` | Channel name without `#` |

### Response (200)

```json
{
  "success": true,
  "message": "Posted to #sonique",
  "error": null,
  "data": null
}
```

### Implementation

Uses `SlackConnector.post_message` → `slack-post-filtered` CLI, falls back to Slack Web API.

---

## POST /intent/linear

Create a Linear issue.

### Request

```json
{
  "title": "fix barge-in latency",
  "description": "Siri timeout on long responses"
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `title` | string | yes | Issue title |
| `description` | string | no | Issue body |

### Response (200)

```json
{
  "success": true,
  "message": "Task ENG-42 created.",
  "error": null,
  "data": { "identifier": "ENG-42" }
}
```

### Implementation

1. `linear issue create` CLI if installed
2. Else Linear GraphQL API with `linear_api_key` + `linear_team_id` secrets

---

## POST /intent/github

Search open pull requests (default) or create an issue (`action: create_issue`).

### Request — Search

```json
{
  "query": "bug",
  "repo": "charlieseay/sonique-ios",
  "label": "bug"
}
```

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `query` | string | yes | — | Search term (also used as label if `label` omitted) |
| `repo` | string | no | `charlieseay/sonique-ios` | `owner/repo` |
| `label` | string | no | — | PR label filter |
| `action` | string | no | `search` | `search` or `create_issue` |

### Request — Create Issue

```json
{
  "action": "create_issue",
  "repo": "charlieseay/sonique-ios",
  "title": "fix microphone echo",
  "body": "optional description"
}
```

### Response (200)

```json
{
  "success": true,
  "message": "Found 3 open pull requests. #42: Fix echo; #38: Mic gain",
  "error": null,
  "data": { "count": "3" }
}
```

### Implementation

`gh pr list` for search; `GitHubConnector.create_issue` for create.

---

## POST /intent/notion

Create a page in a Notion database.

### Request

```json
{
  "title": "weekly standup notes",
  "body": "Discussed QW2 intents",
  "database_id": "optional-override"
}
```

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `title` | string | yes | — | Page title (maps to `Name` property) |
| `body` | string | no | — | Paragraph block content |
| `database_id` | string | no | secret file | Notion database UUID |

### Response (200)

```json
{
  "success": true,
  "message": "Notion page created.",
  "error": null,
  "data": { "page_id": "abc-123" }
}
```

### Implementation

Notion REST API `POST /v1/pages` with token from `/Volumes/data/secrets/notion_api_key`.

---

## POST /intent/docker

List Docker containers.

### Request

```json
{
  "all": "false"
}
```

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `all` | string | no | `"false"` | `"true"` to include stopped containers |

### Response (200)

```json
{
  "success": true,
  "message": "Found 5 containers",
  "error": null,
  "data": null
}
```

### Implementation

`DockerConnector.list_containers`.

---

## curl Examples

```bash
# Slack
curl -X POST http://localhost:8890/intent/slack \
  -H "Content-Type: application/json" \
  -d '{"message": "test from curl"}'

# Linear
curl -X POST http://localhost:8890/intent/linear \
  -H "Content-Type: application/json" \
  -d '{"title": "test task"}'

# GitHub search
curl -X POST http://localhost:8890/intent/github \
  -H "Content-Type: application/json" \
  -d '{"query": "bug", "label": "bug"}'

# Notion
curl -X POST http://localhost:8890/intent/notion \
  -H "Content-Type: application/json" \
  -d '{"title": "test page"}'

# Docker
curl -X POST http://localhost:8890/intent/docker \
  -H "Content-Type: application/json" \
  -d '{"all": "true"}'
```

## Version

- Added: iOS Build 127+ / SoniqueBar intent routes
- Port: 8890
- Auth: None (LAN/Tailscale only — same trust model as `/command`)
