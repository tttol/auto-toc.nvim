local api = vim.api
local document = require('auto-toc.document')
local render = require('auto-toc.render')

local M = {}
local buffers = {}
local debounce_ms = 150

local function extension(buf)
  if api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == '' then
    return api.nvim_buf_get_name(buf):match('%.(mdx?)$')
  end
end

local function warn(state, message)
  if state.warning ~= message then
    state.warning = message
    vim.notify(message, vim.log.levels.WARN, { title = 'auto-toc.nvim' })
  end
end

local function cancel(state)
  state.revision = state.revision + 1
  state.pending = false
  state.history_tick = nil
  if state.timer then
    state.timer:stop()
  end
end

local function inspect(buf, state)
  local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  local parsed = document.inspect(lines, state.extension)
  local block, err = document.block(parsed)
  return {
    lines = lines,
    document = parsed,
    block = block,
    marker_error = err,
    headings = document.heading_signature(parsed, block),
  }
end

local function reset(buf, state)
  cancel(state)
  state.warning = nil
  state.headings = state.extension and inspect(buf, state).headings or nil
  local undo = vim.fn.undotree(buf)
  state.undo_current = undo.seq_cur
  state.undo_latest = undo.seq_last
end

local function write(buf, edit, join)
  return api.nvim_buf_call(buf, function()
    if join then
      local ok, err = pcall(vim.cmd.undojoin)
      if not ok then
        -- An undo immediately before the update must retain its redo history.
        if tostring(err):find('E790:', 1, true) then
          return false
        end
        error(err)
      end
    end
    api.nvim_buf_set_lines(buf, edit.first, edit.last, true, edit.lines)
    return true
  end)
end

local function reconcile(buf, state, force)
  if buffers[buf] ~= state or not state.extension or extension(buf) ~= state.extension then
    return
  end
  if vim.b[buf].auto_toc_disabled or (not force and not state.pending) then
    return
  end
  if not vim.bo[buf].modifiable or vim.bo[buf].readonly then
    return
  end

  local undo = vim.fn.undotree(buf)
  local restored = state.history_tick == api.nvim_buf_get_changedtick(buf)
    or (undo.seq_last == state.undo_latest and undo.seq_cur ~= state.undo_current)
  cancel(state)
  local snapshot = inspect(buf, state)
  local previous = state.headings
  state.headings = snapshot.headings
  state.undo_current = undo.seq_cur
  state.undo_latest = undo.seq_last
  if not force and (restored or vim.deep_equal(previous, snapshot.headings)) then
    return
  end
  if snapshot.marker_error then
    state.headings = previous
    warn(state, snapshot.marker_error)
    return
  end

  state.warning = nil
  local entries = render.entries(snapshot.headings)
  local edit = document.edit(snapshot.lines, snapshot.document, state.extension, snapshot.block, entries)
  if not edit then
    return
  end

  state.writing = true
  local join = not force and undo.seq_cur > 0 and vim.bo[buf].undolevels >= 0
  local ok, written = pcall(write, buf, edit, join)
  state.writing = false
  if not ok then
    state.headings = previous
    state.pending = true
    warn(state, 'Unable to update the table of contents')
  elseif written then
    local updated = vim.fn.undotree(buf)
    state.undo_current = updated.seq_cur
    state.undo_latest = updated.seq_last
  end
end

local function queue(buf, state)
  state.pending = true
  state.revision = state.revision + 1
  local revision = state.revision
  if not state.timer then
    state.timer = assert(vim.uv.new_timer())
  end
  state.timer:start(debounce_ms, 0, vim.schedule_wrap(function()
    if revision == state.revision then
      reconcile(buf, state, false)
    end
  end))
end

--- Establish the initial baseline and observe changes to an eligible buffer.
--- @param buf integer
function M.attach(buf)
  if buffers[buf] then
    return
  end
  local kind = extension(buf)
  if not kind then
    return
  end

  local state = { extension = kind, revision = 0 }
  local markdown = vim.treesitter.language.add('markdown')
  local markdown_inline = vim.treesitter.language.add('markdown_inline')
  if not markdown or not markdown_inline then
    vim.notify_once('Markdown and Markdown inline Tree-sitter parsers are required', vim.log.levels.WARN,
      { title = 'auto-toc.nvim' })
    return
  end

  reset(buf, state)
  if api.nvim_buf_attach(buf, false, {
    on_lines = function(_, _, tick)
      if tick and state.extension and not state.writing and not vim.b[buf].auto_toc_disabled then
        queue(buf, state)
      end
    end,
    on_changedtick = function(_, _, tick)
      if state.pending then
        state.history_tick = tick
      end
    end,
    on_reload = function()
      reset(buf, state)
    end,
    on_detach = function()
      cancel(state)
      if state.timer then
        state.timer:close()
      end
      buffers[buf] = nil
    end,
  }) then
    buffers[buf] = state
  end
end

--- Refresh eligibility and the baseline when the filename changes.
--- @param buf integer
function M.rename(buf)
  local state = buffers[buf]
  if not state then
    M.attach(buf)
    return
  end
  local kind = extension(buf)
  if state.extension ~= kind then
    state.extension = kind
    reset(buf, state)
  end
end

--- Flush a pending edit before the file is written.
--- @param buf integer
function M.flush(buf)
  local state = buffers[buf]
  if state then
    reconcile(buf, state, false)
  end
end

--- Set automatic generation for a Markdown or MDX buffer.
--- @param buf integer
--- @param enabled boolean
function M.set_enabled(buf, enabled)
  if not extension(buf) then
    vim.notify('Open a .md or .mdx file to change automatic TOC generation', vim.log.levels.INFO,
      { title = 'auto-toc.nvim' })
    return
  end
  M.attach(buf)
  local state = buffers[buf]
  if not state then
    return
  end

  vim.b[buf].auto_toc_disabled = not enabled
  if enabled then
    reconcile(buf, state, true)
  else
    cancel(state)
  end

  vim.notify(enabled and 'Automatic TOC generation enabled' or 'Automatic TOC generation disabled',
    vim.log.levels.INFO, { title = 'auto-toc.nvim' })
end

return M
