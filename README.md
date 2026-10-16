# neo-tree-regex.nvim

Neo-tree source，从当前缓冲区提取匹配纯文本或 **Vim 正则表达式** 的行。支持普通文本和已渲染的彩色终端快照，目录显示原文行号及完整行内容；回车跳回原文，不修改缓冲区。

使用 lazy.nvim 安装，将插件添加到 Neo-tree 的依赖，并注册 source（模块名为 `neo-tree-regex`，source 名为 `regex_lines`）：

```lua
{
  "nvim-neo-tree/neo-tree.nvim",
  lazy = false,
  dependencies = {
    "nvim-lua/plenary.nvim",
    "MunifTanjim/nui.nvim",
    "jiangyinzuo/neo-tree-regex.nvim",
  },
  opts = {
    sources = { "filesystem", "buffers", "git_status", "neo-tree-regex" },
  },
}
```

在原文缓冲区执行：

```vim
" 简单文本匹配，区分大小写；符号不需要转义，不用加引号
:NeotreeLiteral ###
:NeotreeLiteral 已执行
:NeotreeLiteral foo.bar[0]

" 不带参数时弹出输入框
:NeotreeLiteral

" 默认提取 ### 开头的章节，允许前导空白
:NeotreeRegex

" 使用其他 Vim 正则（不用加 / 分隔符）
:NeotreeRegex \v(ERROR|WARN|Traceback)
:NeotreeRegex ^\s*#\+\s
```

也可用 `:Neotree regex_lines` 或 source selector 中的 `###` 入口打开。需要切换到另一份原文时，在新缓冲区重新执行 `:NeotreeRegex`。

目录按原文顺序排列，重复内容按行号分别显示。`Enter` 跳转，`/` 修改当前 tab 的匹配文字或正则（沿用当前模式），`r` 重新扫描，`q` 关闭目录。使用带参数的 `:NeotreeLiteral` 或 `:NeotreeRegex` 切换匹配模式。原文改变后按 `r` 更新；原文窗口或缓冲区关闭后，在原文重新打开目录。

可以注册多个具名 source，每个 source 独立保存匹配规则、匹配模式和目录状态。调用 `register(name, config)` 后，将返回的模块名放入 Neo-tree 的 `sources`；source selector 和 `:Neotree` 使用注册时的名称。

使用 lazy.nvim 时，在 Neo-tree 的 `opts = function() ... end` 中注册，确保插件依赖已加载：

```lua
opts = function()
  local regex = require("neo-tree-regex")
  return {
    sources = {
      "filesystem", "buffers", "git_status", "neo-tree-regex",
      regex.register("omp-answer", { pattern = [[^\s*###\s\+\S]] }),
      regex.register("errors", { pattern = [[\v(ERROR|WARN|Traceback)]] }),
      regex.register("todos", { pattern = "TODO", literal = true }),
    },
    source_selector = {
      winbar = true,
      sources = {
        { source = "filesystem", display_name = "Files" },
        { source = "omp-answer", display_name = "###" },
        { source = "errors", display_name = "Errors" },
        { source = "todos", display_name = "TODO" },
      },
    },
  }
end,
```

例如 `:Neotree omp-answer` 打开回答章节，`:Neotree errors` 打开错误目录。不同规则之间切换时沿用当前浏览的原文，`/` 只修改当前 source 的规则。

`register` 必须在 `require("neo-tree").setup()` 之前调用；`config` 也支持与原 source 相同的 `window` 等选项。通用命令 `:NeotreeRegex`、`:NeotreeLiteral` 使用原来的 `regex_lines` source，保留 `"neo-tree-regex"` 即可继续使用；默认值仍可在 Neo-tree 的 `regex_lines = { pattern = ..., literal = ... }` 中配置。

这是逐行匹配，不解析 Markdown 语义：代码块里满足表达式的行也会列出。

从插件仓库根目录运行测试（依赖已安装的 Neo-tree、Nui、Plenary，默认在 `~/plugged`）：

```sh
nvim --headless -u NONE -l tests/source.lua
```

可用 `NEO_TREE_TEST_PLUGIN_DIR` 指定测试依赖所在目录。
