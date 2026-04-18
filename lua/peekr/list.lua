local Renderer = require('peekr.renderer')
local Winbar = require('peekr.winbar')
local lsp = require('peekr.lsp')
local Range = require('peekr.range')
local folds = require('peekr.folds')
local config = require('peekr.config')
local utils = require('peekr.utils')

local List = {}
List.__index = List

local winhl = {
  'Normal:PeekrListNormal',
  'NormalFloat:PeekrListNormal',
  'CursorLine:PeekrListCursorLine',
  'EndOfBuffer:PeekrListEndOfBuffer',
}

local win_opts_tbl = {
  winfixwidth = true,
  winfixheight = true,
  cursorline = true,
  wrap = false,
  signcolumn = 'no',
  foldenable = false,
  winhighlight = table.concat(winhl, ','),
}

function List.create(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_create_buf(false, true)
  local winnr = vim.api.nvim_open_win(bufnr, true, opts.win_opts)

  local list = List:new(bufnr, winnr)
  for k, v in pairs(win_opts_tbl) do
    pcall(function() vim.wo[winnr][k] = v end)
  end
  vim.bo[bufnr].bufhidden = 'wipe'
  vim.bo[bufnr].buftype = 'nofile'
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].buflisted = false
  vim.bo[bufnr].filetype = 'Peekr'

  list:setup(opts)
  list:set_keymaps()
  return list
end

function List:new(bufnr, winnr)
  local scope = { bufnr = bufnr, winnr = winnr, items = {}, groups = {}, winbar = nil }
  if config.options.winbar.enable then
    local wb = Winbar:new(winnr)
    wb:append('title', 'WinBarTitle')
    scope.winbar = wb
  end
  return setmetatable(scope, self)
end

function List:set_keymaps()
  local kopts = { buffer = self.bufnr, noremap = true, nowait = true, silent = true }
  for key, action in pairs(config.options.mappings.list) do
    vim.keymap.set('n', key, action, kopts)
  end
end

function List:is_valid()
  return self.winnr and vim.api.nvim_win_is_valid(self.winnr)
end

-- Location processing helpers

local function is_starting_location(params, uri, range)
  if not params.position or uri ~= params.textDocument.uri then return false end
  local r = Range:new(range.start.line, range.start.character, range.finish.line, range.finish.character)
  return r:contains({ line = params.position.line, col = params.position.character })
end

local function get_preview_line(range, offset, text)
  local word = utils.get_word_until_position(range.start_col - offset, text)
  local end_col = range.end_line > range.start_line and (#text + 1) or range.end_col
  return {
    value = {
      before = utils.get_value_in_range(word.start_col, range.start_col, text):gsub('^%s+', ''),
      inside = utils.get_value_in_range(range.start_col, end_col, text),
      after = utils.get_value_in_range(end_col, #text + 1, text):gsub('%s+$', ''),
    },
  }
end

local function sort_by_position(a, b)
  if a.start.line ~= b.start.line then return a.start.line < b.start.line end
  return a.start.character < b.start.character
end

local function process_locations(locations, position_params, offset_encoding)
  local result = {}
  local grouped = setmetatable({}, {
    __index = function(t, k) local v = {}; rawset(t, k, v); return v end,
  })

  for _, loc in ipairs(locations) do
    local uri = loc.uri or loc.targetUri
    local range = loc.range or loc.targetSelectionRange
    table.insert(grouped[uri], { start = range.start, finish = range['end'] })
  end

  local keys = vim.tbl_keys(grouped)
  table.sort(keys)

  for _, uri in ipairs(keys) do
    local rows = grouped[uri]
    table.sort(rows, sort_by_position)
    local filename = vim.uri_to_fname(uri)
    local bufnr = vim.uri_to_bufnr(uri)
    result[filename] = { filename = filename, uri = uri, items = {} }

    local uri_rows = {}
    for _, pos in ipairs(rows) do table.insert(uri_rows, pos.start.line) end
    local lines = utils.get_lines(bufnr, uri, uri_rows)

    for index, pos in ipairs(rows) do
      local line = lines and lines[pos.start.line]
      local preview_line, is_unreachable
      local sc, ec = pos.start.character, pos.finish.character

      if not line then
        line = ('%s:%d:%d'):format(vim.fn.fnamemodify(filename, ':t'), sc + 1, ec + 1)
        is_unreachable = true
      else
        sc = utils.get_line_byte_from_position(line, pos.start, offset_encoding)
        ec = utils.get_line_byte_from_position(line, pos.finish, offset_encoding)
        preview_line = get_preview_line({
          start_line = pos.start.line, start_col = sc,
          end_col = ec, end_line = pos.finish.line,
        }, 8, line)
      end

      table.insert(result[filename].items, {
        filename = filename, bufnr = bufnr, index = index, uri = uri,
        preview_line = preview_line, is_unreachable = is_unreachable,
        full_text = line or '', start_line = pos.start.line, end_line = pos.finish.line,
        start_col = sc, end_col = ec,
        is_starting = position_params and position_params.textDocument
          and is_starting_location(position_params, uri, { start = pos.start, finish = pos.finish }),
      })
    end
  end
  return result
end

local function find_starting_group(groups, params)
  local fallback
  for _, group in pairs(groups) do
    for _, item in ipairs(group.items) do
      if item.is_starting then return group, item end
    end
    if not fallback and params and params.textDocument and params.textDocument.uri == group.uri then
      fallback = { group = group, item = group.items[1] }
    end
  end
  if fallback then return fallback.group, fallback.item end
  local _, g = next(groups)
  return g, g.items[1]
end

function List:setup(opts)
  self.groups = process_locations(opts.results, opts.position_params, opts.offset_encoding)
  local group, location = find_starting_group(self.groups, opts.position_params)

  folds.reset()
  folds.open(group.filename)
  self:update(self.groups)

  local _, line = utils.tbl_find(self.items, function(item) return vim.deep_equal(item, location) end)

  if self.winbar then
    local label = lsp.methods[opts.method] and utils.capitalize(lsp.methods[opts.method].label) or opts.method
    self.winbar:render({ title = ('%s (%d)'):format(label, #opts.results) })
  end

  vim.api.nvim_win_set_cursor(self.winnr, { line or 1, 1 })
  vim.schedule(function() vim.cmd('norm! zz') end)
end

function List:update(groups)
  vim.bo[self.bufnr].modifiable = true
  vim.bo[self.bufnr].readonly = false
  self:render(groups)
  vim.bo[self.bufnr].modifiable = false
  vim.bo[self.bufnr].readonly = true
end

function List:close()
  if vim.api.nvim_win_is_valid(self.winnr) then vim.api.nvim_win_close(self.winnr, true) end
  if vim.api.nvim_buf_is_valid(self.bufnr) then vim.api.nvim_buf_delete(self.bufnr, {}) end
  folds.reset()
end

function List:destroy()
  self.winnr, self.bufnr, self.items, self.groups, self.winbar = nil, nil, nil, nil, nil
end

function List:render(groups)
  local r = Renderer:new(self.bufnr)
  local icons = config.options.folds

  if vim.tbl_count(groups) > 1 then
    for filename, group in pairs(groups) do
      self.items[r.line_nr + 1] = {
        filename = filename, uri = group.uri, is_group = true, count = #group.items,
      }
      local icon = folds.is_folded(filename) and icons.fold_closed or icons.fold_open
      r:append((' %s '):format(icon), 'FoldIcon')
      r:append(vim.fn.fnamemodify(filename, ':t'), 'ListFilename', ' ')
      r:append(vim.fn.fnamemodify(filename, ':p:.:h'), 'ListFilepath', ' ')
      r:append((' %d '):format(#group.items), 'ListCount', ' ')
      r:nl()
      if not folds.is_folded(filename) then
        self:render_locations(group.items, r, true)
      end
    end
  else
    local _, group = next(groups)
    self:render_locations(group.items, r, false)
  end

  r:render()
  r:highlight()
end

function List:render_locations(locations, renderer, indent)
  local opts = config.options
  for _, loc in ipairs(locations) do
    self.items[renderer.line_nr + 1] = loc
    local prefix = ' '
    if opts.indent_lines.enable and indent then
      prefix = (' %s  '):format(opts.indent_lines.icon)
    end
    renderer:append(prefix, 'Indent')
    if loc.preview_line then
      local pl = loc.preview_line.value
      renderer:append(pl.before)
      renderer:append(pl.inside, 'ListMatch')
      renderer:append(pl.after)
    else
      renderer:append(loc.full_text)
    end
    renderer:nl()
  end
end

function List:get_line() return vim.api.nvim_win_get_cursor(self.winnr)[1] end
function List:get_col() return vim.api.nvim_win_get_cursor(self.winnr)[2] end
function List:get_current_item() return self.items[self.get_line and self:get_line() or 1] end

function List:walk(opts)
  local idx = opts.start
  return function()
    local count = vim.api.nvim_buf_line_count(self.bufnr)
    idx = idx + (opts.backwards and -1 or 1)
    if opts.cycle then idx = ((idx - 1) % count) + 1 end
    local item = self.items[idx]
    if not item or idx > count then return nil end
    return idx, item
  end
end

function List:next(opts)
  opts = opts or {}
  for i, item in self:walk({ start = self:get_line() + (opts.offset or 0), cycle = opts.cycle }) do
    if opts.skip_groups and item.is_group and folds.is_folded(item.filename) then
      self:toggle_fold(item)
      return self:next({ offset = i - self:get_line(), cycle = opts.cycle, skip_groups = true })
    end
    if not (opts.skip_groups and item.is_group) then
      vim.api.nvim_win_set_cursor(self.winnr, { i, self:get_col() })
      return item
    end
  end
end

function List:previous(opts)
  opts = opts or {}
  for i, item in self:walk({ start = self:get_line() + (opts.offset or 0), cycle = opts.cycle, backwards = true }) do
    if opts.skip_groups and item.is_group and folds.is_folded(item.filename) then
      local is_last = i == vim.api.nvim_buf_line_count(self.bufnr)
      self:toggle_fold(item)
      return self:previous({ offset = is_last and 0 or item.count, cycle = opts.cycle, skip_groups = true })
    end
    if not (opts.skip_groups and item.is_group) then
      vim.api.nvim_win_set_cursor(self.winnr, { i, self:get_col() })
      return item
    end
  end
end

function List:get_active_group(opts)
  local loc = opts.location or self:get_current_item()
  return self.groups[loc.filename]
end

function List:is_flat() return vim.tbl_count(self.groups) == 1 end

function List:toggle_fold(item)
  if folds.is_folded(item.filename) then self:open_fold(item) else self:close_fold(item) end
end

function List:open_fold(item)
  if not folds.is_folded(item.filename) then return end
  folds.open(item.filename)
  self:update(self.groups)
end

function List:close_fold(item)
  if folds.is_folded(item.filename) then return end
  local cur = self:get_line()
  folds.close(item.filename)
  self:update(self.groups)
  if not item.is_group then
    vim.api.nvim_win_set_cursor(self.winnr, { math.max(cur - item.index, 1), self:get_col() })
  end
end

return List
