# Peekr

A Neovim plugin that provides a floating peek UI for LSP locations -- definitions, references, implementations, call hierarchy, and more -- with treesitter syntax highlighting in the preview pane.

![Neovim](https://img.shields.io/badge/Neovim-0.12%2B-57A143?style=flat&logo=neovim&logoColor=white)

## Features

-  Browse LSP locations in a split floating window (list + preview)
-  Treesitter syntax highlighting in the preview panel
-  File-grouped results with foldable sections
-  Winbar showing method name, filename, and path
-  Tagstack integration (`<C-t>` to jump back)
-  Quickfix integration (optionally via trouble.nvim)
-  Session resume with `:Peekr resume`
-  Custom LSP method registration
-  Responsive layout on terminal resize
-  Fully customizable keymaps, highlights, and hooks

## Requirements

- **Neovim >= 0.12**
- Treesitter parsers installed for languages you want highlighted (optional but recommended)
- [trouble.nvim](https://github.com/folke/trouble.nvim) (optional, for quickfix via Trouble)

## Installation

### lazy.nvim

```lua
{
  'mikkurogue/peekr',
  event = 'LspAttach',
  opts = {
    -- your configuration here
  },
}
```

### packer.nvim

```lua
use {
  'mikkurogue/peekr',
  config = function()
    require('peekr').setup({
      -- your configuration here
    })
  end,
}
```

### Native package manager (Neovim 0.12+)

Add the following to your `init.lua`:

```lua
vim.pack.add({ src = 'https://github.com/mikkurogue/peekr' })
require('peekr').setup({
  -- your configuration here
})
```

## Showcase

<img width="1992" height="622" alt="image" src="https://github.com/user-attachments/assets/a5c8f841-b2fb-4c81-83ca-1f5582bd699a" />

## Usage

### Commands

| Command | Description |
|---|---|
| `:Peekr definitions` | Peek at definitions |
| `:Peekr references` | Peek at references |
| `:Peekr implementations` | Peek at implementations |
| `:Peekr type_definitions` | Peek at type definitions |
| `:Peekr declaration` | Peek at declaration |
| `:Peekr incoming_calls` | Peek at incoming calls |
| `:Peekr outgoing_calls` | Peek at outgoing calls |
| `:Peekr document_symbols` | Peek at document symbols |
| `:Peekr workspace_symbols` | Peek at workspace symbols |
| `:Peekr resume` | Re-open the last Peekr session |

Tab completion is available for all method names.

### Suggested keymaps

```lua
vim.keymap.set('n', 'gd', '<CMD>Peekr definitions<CR>')
vim.keymap.set('n', 'gr', '<CMD>Peekr references<CR>')
vim.keymap.set('n', 'gi', '<CMD>Peekr implementations<CR>')
vim.keymap.set('n', 'gD', '<CMD>Peekr type_definitions<CR>')
```

Or using the Lua API directly:

```lua
vim.keymap.set('n', 'gd', function() require('peekr').open('definitions') end)
vim.keymap.set('n', 'gr', function() require('peekr').open('references') end)
```

## Configuration

Below is the default configuration. All fields are optional.

```lua
require('peekr').setup({
  height = 20,              -- float height in lines
  width = 0.75,             -- fraction of editor width (0.0 - 1.0)
  zindex = 50,
  border = 'rounded',       -- border style: 'rounded', 'single', 'double', 'solid', etc.

  preview_win_opts = {
    cursorline = true,
    number = true,
    wrap = true,
  },

  list = {
    position = 'left',      -- 'left' or 'right'
    width = 0.30,            -- fraction of the total float width
  },

  treesitter = {
    enable = true,           -- treesitter highlighting in preview
  },

  folds = {
    fold_closed = '',       -- nerd font icon for collapsed groups
    fold_open = '',         -- nerd font icon for expanded groups
    folded = true,           -- whether groups start folded
  },

  indent_lines = {
    enable = true,
    icon = '│',
  },

  winbar = {
    enable = true,           -- show winbar with filename and method info
  },

  use_trouble_qf = false,   -- use trouble.nvim for quickfix instead of :copen

  hooks = {
    ---Called before the Peekr window opens.
    ---@param results table       -- raw LSP results
    ---@param open function       -- call to proceed with opening
    ---@param jump function       -- call to jump to first result instead
    ---@param method string       -- the LSP method name
    before_open = function(results, open, jump, method) end,

    ---Called before the window closes.
    before_close = function() end,

    ---Called after the window closes.
    after_close = function() end,
  },

  mappings = {
    list = {
      ['j']         = actions.next,
      ['k']         = actions.previous,
      ['<Down>']    = actions.next,
      ['<Up>']      = actions.previous,
      ['<Tab>']     = actions.next_location,
      ['<S-Tab>']   = actions.previous_location,
      ['<CR>']      = actions.jump,
      ['o']         = actions.jump,
      ['v']         = actions.jump_vsplit,
      ['s']         = actions.jump_split,
      ['t']         = actions.jump_tab,
      ['l']         = actions.open_fold,
      ['h']         = actions.close_fold,
      ['<C-u>']     = actions.preview_scroll_win(5),
      ['<C-d>']     = actions.preview_scroll_win(-5),
      ['<leader>l'] = actions.enter_win('preview'),
      ['q']         = actions.close,
      ['Q']         = actions.close,
      ['<Esc>']     = actions.close,
      ['<C-q>']     = actions.quickfix,
    },
    preview = {
      ['<Tab>']     = actions.next_location,
      ['<S-Tab>']   = actions.previous_location,
      ['<leader>l'] = actions.enter_win('list'),
      ['q']         = actions.close,
      ['Q']         = actions.close,
      ['<Esc>']     = actions.close,
    },
  },
})
```

> Set any mapping to `false` to disable it.

## Default keymaps

### List window

| Key | Action |
|---|---|
| `j` / `<Down>` | Next item |
| `k` / `<Up>` | Previous item |
| `<Tab>` | Next location (cycles, skips headers) |
| `<S-Tab>` | Previous location |
| `<CR>` / `o` | Jump to location |
| `v` | Jump in vertical split |
| `s` | Jump in horizontal split |
| `t` | Jump in new tab |
| `l` | Open fold |
| `h` | Close fold |
| `<C-u>` | Scroll preview up |
| `<C-d>` | Scroll preview down |
| `<leader>l` | Move cursor to preview window |
| `q` / `Q` / `<Esc>` | Close |
| `<C-q>` | Send all results to quickfix |

### Preview window

| Key | Action |
|---|---|
| `<Tab>` | Next location |
| `<S-Tab>` | Previous location |
| `<leader>l` | Move cursor to list window |
| `q` / `Q` / `<Esc>` | Close |

## Hooks

The `before_open` hook allows you to intercept results and decide whether to open the peek UI or jump directly:

```lua
require('peekr').setup({
  hooks = {
    before_open = function(results, open, jump, method)
      -- Jump directly if there is only one result
      if #results == 1 then
        jump(results[1])
      else
        open(results)
      end
    end,
  },
})
```

## Custom LSP methods

Register additional LSP methods via the API:

```lua
require('peekr').register_method({
  name = 'my_method',
  label = 'My Method',
  method = 'custom/lspMethod',
  transform = function(results)
    -- transform raw LSP results into location items
    return results
  end,
})
```

Then use it with `:Peekr my_method`.

## Highlight groups

All highlight groups are prefixed with `Peekr` and use `default = true`, so they can be overridden in your colorscheme or config. They re-apply automatically on `ColorScheme` changes.

| Group | Default link |
|---|---|
| `PeekrPreviewNormal` | `NormalFloat` |
| `PeekrPreviewCursorLine` | `CursorLine` |
| `PeekrPreviewSignColumn` | `SignColumn` |
| `PeekrPreviewLineNr` | `LineNr` |
| `PeekrPreviewMatch` | `Search` |
| `PeekrListNormal` | `NormalFloat` |
| `PeekrListCursorLine` | `CursorLine` |
| `PeekrListMatch` | `Search` |
| `PeekrListFilename` | `Directory` |
| `PeekrListFilepath` | `Comment` |
| `PeekrListCount` | `Number` |
| `PeekrBorder` | `FloatBorder` |
| `PeekrTitle` | `FloatTitle` |
| `PeekrFoldIcon` | `Comment` |
| `PeekrIndent` | `Comment` |
| `PeekrWinBarFilename` | `FloatTitle` |
| `PeekrWinBarFilepath` | `Comment` |
| `PeekrWinBarTitle` | `FloatTitle` |

## API

```lua
local peekr = require('peekr')

peekr.setup(opts)                    -- configure the plugin
peekr.open('references')             -- open peek for a method
peekr.open('definitions', { ... })   -- open with per-call option overrides
peekr.is_open()                      -- returns true if the peek UI is visible
peekr.actions.close()                -- close the peek UI
peekr.actions.resume()               -- re-open the last session
peekr.register_method({ ... })       -- register a custom LSP method
```

## License

MIT
