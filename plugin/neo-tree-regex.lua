vim.api.nvim_create_user_command("NeotreeRegex", function(command)
	require("neo-tree-regex").open(command.args ~= "" and command.args or nil)
end, {
	nargs = "?",
	desc = "List lines matching a Vim regex in Neo-tree",
})

vim.api.nvim_create_user_command("NeotreeLiteral", function(command)
	require("neo-tree-regex").open_text(command.args ~= "" and command.args or nil)
end, {
	nargs = "?",
	desc = "List lines containing literal text in Neo-tree",
})
