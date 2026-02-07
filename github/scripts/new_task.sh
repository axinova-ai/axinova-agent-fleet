#!/usr/bin/env bash
set -euo pipefail

TITLE="${1:?Usage: $0 <task-title> [description] [repo]}"
DESCRIPTION="${2:-}"
REPO="${3:-axinova-ai/axinova-home-go}"

echo "==> Creating new task: $TITLE"

# Step 1: Create GitHub issue
echo "→ Creating GitHub issue in $REPO..."
ISSUE_URL=$(gh issue create \
  --repo "$REPO" \
  --title "$TITLE" \
  --body "$DESCRIPTION" \
  --label "agent-created" \
  --label "task" \
  --assignee "@me")

# Extract issue number from URL
ISSUE_NUM=$(echo "$ISSUE_URL" | grep -o '[0-9]*$')

echo "  Created issue #$ISSUE_NUM: $ISSUE_URL"

# Step 2: Create Vikunja task via MCP
echo "→ Creating Vikunja task..."

# Note: This requires axinova-mcp-server-go running
# For now, output instructions for manual creation or agent execution

cat <<EOF

Next steps (execute via agent with MCP tools):

1. Create Vikunja task:
   vikunja_create_task(
     project_id: 1,  # Engineering project
     title: "$TITLE",
     description: "<p>GitHub issue: <a href='$ISSUE_URL'>#$ISSUE_NUM</a></p><p>$DESCRIPTION</p>",
     priority: 3
   )

2. Create SilverBullet wiki page:
   silverbullet_create_page(
     page_name: "tasks/$ISSUE_NUM-${TITLE// /-}",
     content: "# $TITLE\n\n**GitHub Issue:** [$ISSUE_URL]($ISSUE_URL)\n\n## Description\n\n$DESCRIPTION\n\n## Progress\n\n- [ ] Task created\n- [ ] Implementation started\n- [ ] Tests written\n- [ ] PR created\n- [ ] Deployed\n"
   )
EOF

echo ""
echo "✅ Task creation initiated"
echo "  GitHub issue: $ISSUE_URL"
echo "  Execute MCP commands above via agent"
