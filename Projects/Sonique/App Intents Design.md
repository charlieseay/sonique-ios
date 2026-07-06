# App Intents Design

Pre-built Siri-discoverable intents for Slack, Linear, GitHub, Notion, and Docker.
Each intent runs on iOS, sends parameters to SoniqueBar over HTTP, and speaks the result.

## Architecture

```
Siri / Shortcuts → iOS App Intent → IntentBarClient → POST /intent/<name> → SoniqueBar IntentHandlers → Connector / CLI / API
```

## Intent Signatures

| Intent | Siri Phrase Example | Parameters | Return | Error Cases |
|--------|---------------------|------------|--------|-------------|
| **SlackPostIntent** | "Post to Slack: team meeting at 3pm" | `message` (required), `channel` (default: sonique) | Voice confirmation | empty message, token missing, SoniqueBar offline |
| **LinearCreateIntent** | "Create Linear task: fix barge-in latency" | `title` (required), `taskDescription` (optional) | "Task LIN-123 created." | empty title, API key missing, CLI not found |
| **GitHubSearchIntent** | "Search GitHub for pull requests labeled bug" | `query` (required), `repository`, `label` | "Found N open PRs…" | gh not installed, repo invalid, API down |
| **GitHubCreateIssueIntent** | "Create GitHub issue: fix microphone echo" | `title` (required), `repository`, `body` | "GitHub issue created." | gh not installed, auth failed, empty title |
| **NotionCreateIntent** | "Create Notion page: weekly standup notes" | `title` (required), `body` (optional) | "Notion page created." | API key missing, database ID missing, rate limit |
| **DockerListIntent** | "List Docker containers" | `showAll` (bool, default false) | Container count summary | Docker daemon down |

## Regex / Voice Routing (SoniqueBar voice loop)

These phrases are distinct to avoid collision with Helmsman "create task":

| Service | Prefix phrases | Avoid |
|---------|----------------|-------|
| Slack | `post to slack`, `slack message` | — |
| Linear | `create linear task`, `linear task`, `new linear issue` | `create task` (Helmsman) |
| GitHub | `search github`, `github search`, `find github pull requests` | `create issue` without "github" |
| GitHub create | `create github issue`, `github issue`, `new github issue` | bare `create issue` (Linear collision) |
| Notion | `create notion page`, `notion page`, `new notion entry` | — |
| Docker | `list docker`, `docker containers` | — |

## iOS Files

| File | Role |
|------|------|
| `Sonique/Intents/IntentTypes.swift` | Shared types, validation, JSON parsing |
| `Sonique/Intents/IntentBarClient.swift` | HTTP dispatch to SoniqueBar |
| `Sonique/Intents/SlackPostIntent.swift` | @AppIntent for Slack |
| `Sonique/Intents/LinearCreateIntent.swift` | @AppIntent for Linear |
| `Sonique/Intents/GitHubSearchIntent.swift` | @AppIntent for GitHub PR search |
| `Sonique/Intents/GitHubCreateIssueIntent.swift` | @AppIntent for GitHub issue create |
| `Sonique/Intents/NotionCreateIntent.swift` | @AppIntent for Notion |
| `Sonique/Intents/DockerListIntent.swift` | @AppIntent for Docker |
| `Sonique/SoniqueShortcuts.swift` | AppShortcutsProvider registration |

## Timeouts

- iOS `IntentBarClient`: 10s request timeout
- Siri practical limit: ~5s perceived; failures return "I can't reach the brain right now."

## Security

- Parameters validated on iOS before send (length, empty checks)
- Channel/repo names stripped of shell metacharacters on both sides
- SoniqueBar uses `Process` with argument arrays (not string concat) for CLI calls
- API tokens read from `/Volumes/data/secrets/`, never logged or spoken

## Dependencies

| Secret / Tool | Path / Command | Required For |
|---------------|----------------|--------------|
| `slack_bot_token` | `/Volumes/data/secrets/slack_bot_token` | Slack |
| `linear_api_key` | `/Volumes/data/secrets/linear_api_key` | Linear (API fallback) |
| `linear_team_id` | `/Volumes/data/secrets/linear_team_id` | Linear (API) |
| `notion_api_key` | `/Volumes/data/secrets/notion_api_key` | Notion |
| `notion_database_id` | `/Volumes/data/secrets/notion_database_id` | Notion |
| `gh` | Homebrew `/opt/homebrew/bin/gh` | GitHub search/create |
| `linear` CLI | optional | Linear (preferred if installed) |
| SoniqueBar | `http://<host>:8890` | All intents |
