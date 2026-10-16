local renderer = require("neo-tree.ui.renderer")
local common = require("neo-tree.sources.common.commands")

local M = {
	name = "regex_lines",
	display_name = "Regex lines",
	default_config = {
		pattern = [[^\s*###\s\+\S]],
		literal = false,
		renderers = {
			root = { { "name" } },
			regex_line = { { "name" } },
		},
		window = {
			position = "right",
			width = 45,
			mappings = {
				["<cr>"] = "open",
				["<2-LeftMouse>"] = "open",
				["r"] = "refresh",
				["/"] = "set_pattern",
				["q"] = "close_window",
			},
		},
	},
}
local source_names = { [M.name] = true }

local function notify(message)
	vim.notify(message, vim.log.levels.WARN, { title = "Neo-tree regex lines" })
end

-- Vim regular expressions, as in / searches, rather than Lua patterns.
function M.collect(bufnr, pattern, literal)
	local regex
	if not literal then
		local ok, result = pcall(vim.regex, pattern)
		if not ok then
			notify("Invalid Vim regex: " .. tostring(result))
			return nil
		end
		regex = result
	end
	local items = {}
	for lnum, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
		local col
		if literal then
			local first = line:find(pattern, 1, true)
			col = first and first - 1
		else
			col = regex:match_str(line)
		end
		if col ~= nil then
			items[#items + 1] = {
				id = bufnr .. ":" .. lnum,
				name = string.format("%d: %s", lnum, vim.trim(line)),
				type = "regex_line",
				extra = { bufnr = bufnr, lnum = lnum, col = col },
			}
		end
	end
	return items
end

local function capture_target(state)
	if vim.bo.filetype ~= "neo-tree" then
		state.target_bufnr = vim.api.nvim_get_current_buf()
		state.target_winid = vim.api.nvim_get_current_win()
	elseif source_names[vim.b.neo_tree_source] then
		-- A newly selected rule should scan the same original buffer.
		local current = require("neo-tree.sources.manager").get_state(vim.b.neo_tree_source)
		state.target_bufnr = current.target_bufnr
		state.target_winid = current.target_winid
	end
end

function M.navigate(state, _path, _reveal, callback)
	capture_target(state)
	local buf = state.target_bufnr
	local children = {}
	local name = "No source buffer"
	if buf and vim.api.nvim_buf_is_loaded(buf) then
		children = M.collect(buf, state.pattern, state.literal)
		if not children then
			return
		end
		name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t")
		name = (name ~= "" and name or "[No Name]") .. " (" .. #children .. " matches)"
	end
	state.path = buf and ("buffer:" .. buf) or "buffer:none"
	state.dirty = false
	renderer.show_nodes({ {
		id = state.path,
		name = name,
		type = "root",
		children = children,
		_is_expanded = true,
	} }, state, nil, callback)
end

-- Neo-tree also injects common components (such as indent) into renderers.
M.components = vim.tbl_extend("force", require("neo-tree.sources.common.components"), {
	name = function(_, node)
		return {
			text = node.name,
			highlight = node.type == "root" and "NeoTreeRootName" or "NeoTreeFileName",
		}
	end,
})

M.commands = {
	open = function(state)
		local node = state.tree:get_node()
		if not node or not node.extra then
			return
		end
		local target = node.extra
		if not vim.api.nvim_buf_is_loaded(target.bufnr) then
			notify("Source buffer has been closed; reopen the outline from a buffer.")
			return
		end
		local win = state.target_winid
		if not win or not vim.api.nvim_win_is_valid(win)
			or vim.api.nvim_win_get_buf(win) ~= target.bufnr then
			notify("Source window has changed; reopen the outline from the source buffer.")
			return
		end
		if target.lnum > vim.api.nvim_buf_line_count(target.bufnr) then
			notify("Source text has changed; press r to refresh.")
			return
		end
		vim.api.nvim_set_current_win(win)
		vim.api.nvim_win_set_cursor(win, { target.lnum, target.col })
		vim.cmd("normal! zz")
	end,
	refresh = function(state)
		M.navigate(state)
	end,
	set_pattern = function(state)
		local prompt = state.literal and "Text: " or "Vim regex: "
		vim.ui.input({ prompt = prompt, default = state.pattern }, function(pattern)
			if pattern == nil then
				return
			end
			if not state.literal then
				local ok, err = pcall(vim.regex, pattern)
				if not ok then
					notify("Invalid Vim regex: " .. tostring(err))
					return
				end
			end
			state.pattern = pattern
			M.navigate(state)
		end)
	end,
}
common._add_common_commands(M.commands, "node")
common._add_common_commands(M.commands, "^close_window$")
common._add_common_commands(M.commands, "source$")
common._add_common_commands(M.commands, "help")

function M.setup(config)
	-- Global mappings include filesystem commands. Disable unsupported ones
	-- for this source while preserving valid common and user commands.
	for key, mapping in pairs(config.window.mappings) do
		local command = type(mapping) == "table" and (mapping.command or mapping[1]) or mapping
		if type(command) == "string" and not config.commands[command] then
			config.window.mappings[key] = "none"
		end
	end
end

-- Call before neo-tree.setup; use the returned module name in its sources list.
function M.register(name, config)
	assert(type(name) == "string" and name:match("^[%w_-]+$") and name ~= M.name,
		"Source name must contain letters, digits, underscores or hyphens and differ from " .. M.name)
	config = config or {}
	local defaults = vim.tbl_deep_extend("force", vim.deepcopy(M.default_config), config)
	assert(type(defaults.pattern) == "string", "pattern must be a string")
	if not defaults.literal then
		local ok, err = pcall(vim.regex, defaults.pattern)
		assert(ok, "Invalid Vim regex: " .. tostring(err))
	end
	local module_name = "neo-tree-regex.sources." .. name
	local source = {
		name = name,
		display_name = config.display_name or name,
		default_config = defaults,
		components = vim.deepcopy(M.components),
		commands = vim.deepcopy(M.commands),
		navigate = M.navigate,
		setup = M.setup,
	}
	source_names[name] = true
	package.preload[module_name] = function() return source end
	package.loaded[module_name] = nil
	return module_name
end

function M.open(pattern, literal)
	local state = require("neo-tree.sources.manager").get_state(M.name)
	capture_target(state)
	if pattern ~= nil then
		if not literal then
			local ok, err = pcall(vim.regex, pattern)
			if not ok then
				notify("Invalid Vim regex: " .. tostring(err))
				return
			end
		end
		state.pattern = pattern
		state.literal = literal == true
	end
	state.dirty = true
	require("neo-tree.command").execute({ source = M.name, action = "focus" })
end

function M.open_text(text)
	if text ~= nil then
		M.open(text, true)
		return
	end
	vim.ui.input({ prompt = "Text: " }, function(value)
		if value ~= nil then
			M.open(value, true)
		end
	end)
end

return M
