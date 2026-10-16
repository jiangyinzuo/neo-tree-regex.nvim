local plugin = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(plugin)
local dependencies = vim.env.NEO_TREE_TEST_PLUGIN_DIR or vim.fn.expand("~/plugged")
for _, name in ipairs({ "neo-tree.nvim", "nui.nvim", "plenary.nvim" }) do
	vim.opt.runtimepath:append(dependencies .. "/" .. name)
end

local function equal(actual, expected)
	assert(vim.deep_equal(actual, expected), vim.inspect({ actual = actual, expected = expected }))
end

local notifications = {}
vim.notify = function(message) notifications[#notifications + 1] = message end
local warnings = {}
require("neo-tree.log").warn = function(...)
	local parts = {}
	for _, value in ipairs({ ... }) do
		parts[#parts + 1] = type(value) == "string" and value or vim.inspect(value)
	end
	warnings[#warnings + 1] = table.concat(parts, " ")
end
local source = require("neo-tree-regex")
local answer_module = source.register("omp-answer", { pattern = [[^\s*###\s\+\S]] })
local errors_module = source.register("errors", { pattern = [[\v(ERROR|WARN)]] })
local literal_module = source.register("literal", { pattern = "foo.bar[0]", literal = true })
require("neo-tree").setup({
	sources = { "neo-tree-regex", answer_module, errors_module, literal_module },
	default_source = "regex_lines",
	enable_git_status = false,
	enable_diagnostics = false,
	source_selector = { winbar = false },
})
dofile(plugin .. "/plugin/neo-tree-regex.lua")
vim.cmd("runtime plugin/neo-tree.lua")
local manager = require("neo-tree.sources.manager")
local original_win = vim.api.nvim_get_current_win()
local buf = vim.api.nvim_get_current_buf()
local lines = {
	"plain", "### 第一章", "  ### 重复", "## ignore", "#### ignore",
	"###", "### ", "### 重复", "ERROR: failure", "WARN: warning",
	"literal foo.bar[0]", "literal fooXbar0", [[literal \(]], "two words",
}
vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

local matches = source.collect(buf, source.default_config.pattern)
equal(vim.tbl_map(function(item) return item.extra.lnum end, matches), { 2, 3, 8 })
assert(matches[2].id ~= matches[3].id)
equal(source.collect(buf, [[\v(ERROR|WARN)]])[2].extra.lnum, 10)
equal(source.collect(buf, "foo.bar[0]", true)[1].extra.lnum, 11)
equal(#source.collect(buf, "foo.bar[0]", true), 1)
equal(source.collect(buf, [[\(]], true)[1].extra.lnum, 13)
equal(source.collect(buf, [[\(]]), nil)
assert(#notifications > 0)
notifications = {}

vim.cmd("NeotreeRegex")
local state = manager.get_state("regex_lines")
assert(vim.wait(1000, function() return state.tree ~= nil end))
local node = state.tree:get_node(buf .. ":3")
assert(node and node.name:find("重复", 1, true))
local tree_win = vim.api.nvim_get_current_win()
require("neo-tree.ui.renderer").focus_node(state, node.id)
source.commands.open(state)
equal(vim.api.nvim_get_current_win(), original_win)
equal(vim.api.nvim_win_get_cursor(original_win), { 3, 0 })
equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), lines)

-- Named rules have independent patterns and inherit the original buffer when switched.
vim.cmd("Neotree omp-answer")
local answer_state = manager.get_state("omp-answer")
equal(answer_state.target_bufnr, buf)
assert(answer_state.tree:get_node(buf .. ":2"))
vim.cmd("Neotree errors")
local errors_state = manager.get_state("errors")
equal(errors_state.target_bufnr, buf)
assert(errors_state.tree:get_node(buf .. ":9"))
equal(errors_state.tree:get_node(buf .. ":2"), nil)
local named_input
vim.ui.input = function(_, callback) named_input = callback end
source.commands.set_pattern(errors_state)
named_input([[^WARN]])
equal(errors_state.tree:get_node(buf .. ":9"), nil)
assert(errors_state.tree:get_node(buf .. ":10"))
vim.cmd("Neotree literal")
local literal_state = manager.get_state("literal")
assert(literal_state.tree:get_node(buf .. ":11"))
equal(literal_state.tree:get_node(buf .. ":12"), nil)
vim.cmd("Neotree omp-answer")
equal(answer_state.pattern, [[^\s*###\s\+\S]])
equal(answer_state.literal, false)
require("neo-tree.ui.renderer").focus_node(answer_state, buf .. ":8")
source.commands.open(answer_state)
equal(vim.api.nvim_get_current_win(), original_win)
equal(vim.api.nvim_win_get_cursor(original_win), { 8, 0 })
equal(errors_state.pattern, [[^WARN]])

-- Literal commands accept punctuation and spaces without regex escaping.
vim.cmd("NeotreeLiteral foo.bar[0]")
equal(state.literal, true)
assert(state.tree:get_node(buf .. ":11"))
equal(state.tree:get_node(buf .. ":12"), nil)
vim.cmd("NeotreeLiteral two words")
assert(state.tree:get_node(buf .. ":14"))
local text_input, text_prompt
vim.ui.input = function(opts, callback)
	text_prompt, text_input = opts.prompt, callback
end
source.commands.set_pattern(state)
equal(text_prompt, "Text: ")
text_input([[\(]])
assert(state.tree:get_node(buf .. ":13"))
vim.cmd("NeotreeLiteral")
text_input(nil)
equal(state.pattern, [[\(]])
text_input("重复")
assert(state.tree:get_node(buf .. ":3"))
assert(state.tree:get_node(buf .. ":8"))

-- A new expression refreshes the existing sidebar and keeps row order.
vim.cmd([[NeotreeRegex \v(ERROR|WARN)]])
equal(state.literal, false)
equal(state.pattern, [[\v(ERROR|WARN)]])
assert(state.tree:get_node(buf .. ":9"))
assert(state.tree:get_node(buf .. ":10"))
equal(state.tree:get_node(buf .. ":2"), nil)

-- Invalid interactive patterns and cancelled input preserve the directory.
local input
vim.ui.input = function(_, callback) input = callback end
source.commands.set_pattern(state)
input([[\(]])
equal(state.pattern, [[\v(ERROR|WARN)]])
input(nil)
equal(state.pattern, [[\v(ERROR|WARN)]])
input([[^plain$]])
equal(state.pattern, [[^plain$]])
assert(state.tree:get_node(buf .. ":1"))

-- Refresh from the tree follows edits in the bound original buffer.
vim.api.nvim_buf_set_lines(buf, 0, 0, false, { "inserted" })
source.commands.refresh(state)
assert(state.tree:get_node(buf .. ":2"))
source.commands.close_window(state)
vim.api.nvim_set_current_win(original_win)

-- Capture a real terminal buffer after ANSI rendering.
local terminal = vim.api.nvim_create_buf(false, true)
vim.api.nvim_win_set_buf(original_win, terminal)
local channel = vim.api.nvim_open_term(terminal, {})
vim.api.nvim_chan_send(channel, "\27[38;2;18;52;86m ### 彩色章节\27[0m\r\nbody")
assert(vim.wait(1000, function()
	return vim.api.nvim_buf_get_lines(terminal, 0, 1, false)[1] == " ### 彩色章节"
end))
vim.cmd([[NeotreeRegex ^\s*###\s\+\S]])
state = manager.get_state("regex_lines")
equal(state.target_bufnr, terminal)
node = state.tree:get_node(terminal .. ":1")
assert(node)
require("neo-tree.ui.renderer").focus_node(state, node.id)
source.commands.open(state)
equal(vim.api.nvim_get_current_buf(), terminal)
equal(vim.api.nvim_win_get_cursor(original_win)[1], 1)

-- Missing source buffers fail gracefully without jumping to unrelated text.
vim.api.nvim_set_current_win(state.winid)
vim.api.nvim_buf_delete(terminal, { force = true })
local previous_notices = #notifications
source.commands.open(state)
equal(#notifications, previous_notices + 1)
equal(vim.api.nvim_get_current_win(), state.winid)
equal(warnings, {})
print("PASS: regex matching, Neo-tree rendering, jumps, custom patterns, refresh, and colored terminal buffers")
