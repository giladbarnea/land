#!/bin/zsh

# ---------[ Linear GraphQL Introspection ]---------
# ## Using Introspection Queries
# 
# ### 1. Query Available Types
# 
# To see all types in the schema:
# 
# ```graphql
# {
#   __schema {
#     types {
#       name
#       kind
#       description
#     }
#   }
# }
# ```
# 
# ### 2. Query Available Queries and Mutations
# 
# To see what operations you can perform:
# 
# ```graphql
# {
#   __schema {
#     queryType {
#       fields {
#         name
#         description
#         args {
#           name
#           description
#           type {
#             name
#             kind
#           }
#         }
#       }
#     }
#     mutationType {
#       fields {
#         name
#         description
#       }
#     }
#   }
# }
# ```
# 
# ### 3. Explore a Specific Type
# 
# To see what fields are available on a specific type (like an Issue):
# 
# ```graphql
# {
#   __type(name: "Issue") {
#     name
#     fields {
#       name
#       description
#       type {
#         name
#         kind
#       }
#     }
#   }
# }
# ```

# # Interesting Issue-related mutations:
# IssueCreate, IssueUpdate, issueArchive, issueUnarchive, issueDelete
# # Interesting Github-related mutations:
# gitAutomationTargetBranchCreate, gitAutomationTargetBranchUpdate, gitAutomationTargetBranchDelete

STICKLIGHT_TEAM_ID='04ed8a01-33ab-4b03-ad55-5b46d592518b'
function .linear-post(){
	local payload="${1}"
	curl -X POST -H "Content-Type: application/json" -H "Authorization: $(<~/.linear-api-key)" --data "$payload" https://api.linear.app/graphql
}

# # linear-introspect-issue-create
# Query the schema to find the mutation for creating an issue.
# Example: `linear-introspect-issue-create | jq '.data.__type.fields[].name' -r | sort -u`
function linear-introspect-issue-create(){
	local query='{"query": "{ __type(name: \"Issue\") { name fields { name type { name kind ofType { name kind } } } } }"}'
	.linear-post "${query}"
}

# # linear-post-issue <title> <description> [team_id]
function linear-post-issue(){
	[[ -z "$2" ]] && {
		log.error "Usage: $0 <title> <description> [team_id]"
		return 1
	}
	local title="${1}"
	local description="${2}"
	local team_id="${3:-${STICKLIGHT_TEAM_ID}}"
	# • title: The title of the issue (required)
	# • description: A markdown description of the issue
	# • teamId: The ID of the team the issue belongs to (required)
	# • stateId: The status of the issue
	# Maybe:
	# • assigneeId: ID of the user assigned to the issue
	# • priority: Priority level of the issue
	# • labelIds: IDs of labels to attach to the issue
	# • dueDate: Due date for the issue
	# • parentId: ID of a parent issue (for sub-issues)
	# • estimate: Story point estimate
	.linear-post "$(cat << EOF
	{
		"query": "mutation IssueCreate(\$input: IssueCreateInput!) { issueCreate(input: \$input) { success issue { id title identifier url branchName createdAt updatedAt number priority state { name color } assignee { name email } description team { name } labels { nodes { name color } } } } }",
		"variables": {
				"input": {
						"title": "$title",
						"description": $(jq -Rs <<< "$description"),
						"teamId": "$team_id"
				}
		}
	}
EOF
	)"
}
