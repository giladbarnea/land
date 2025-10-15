# cursor-search <STRING>
# Search for a string in all chats.
# `cursor-search '%Refactor%'`
function cursor-search(){
	sqlite-utils "$HOME/Library/Application Support/Cursor/User/globalStorage/state.vscdb" \
		"SELECT key, value from ItemTable where value like '$1'" | \
	jq '
	def remove_empty:
			if type == "object" then
					to_entries
					| map(.value |= remove_empty)
					| map(select(.value != "" and .value != [] and .value != {}))
					| from_entries
			elif type == "array" then
					map(remove_empty)
					| map(select(. != "" and . != [] and . != {}))
			else
					.
			end;

	.[] | {key, value: (.value | fromjson | .richText |= fromjson? | remove_empty)}
	' -r
}