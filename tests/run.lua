local api = vim.api
local md_start, md_end = '<!-- auto-toc:start -->', '<!-- auto-toc:end -->'
local mdx_start, mdx_end = '{/* auto-toc:start */}', '{/* auto-toc:end */}'
local notices = {}
local count = 0

vim.opt.hidden = true
vim.notify = function(message)
  notices[#notices + 1] = message
end

local function equal(expected, actual)
  assert(vim.deep_equal(expected, actual),
    ('Expected %s\nReceived %s'):format(vim.inspect(expected), vim.inspect(actual)))
end

local function open(suffix, contents)
  local path = vim.fn.tempname() .. suffix
  vim.fn.writefile(contents, path)
  vim.cmd.edit(vim.fn.fnameescape(path))
  return api.nvim_get_current_buf(), path
end

local function lines(buf)
  return api.nvim_buf_get_lines(buf, 0, -1, true)
end

local function replace(buf, old, new)
  local index = vim.fn.index(lines(buf), old)
  assert(index >= 0, 'Missing line: ' .. old)
  api.nvim_buf_set_lines(buf, index, index + 1, true, new)
end

local function append(buf, new)
  api.nvim_buf_set_lines(buf, -1, -1, true, new)
end

local function block(buf, start, finish)
  local content = lines(buf)
  local first = vim.fn.index(content, start)
  local last = vim.fn.index(content, finish)
  return first >= 0 and last > first and vim.list_slice(content, first + 1, last + 1) or nil
end

local function toc(start, finish, entries)
  local expected = { start }
  vim.list_extend(expected, entries)
  expected[#expected + 1] = finish
  return expected
end

local function await_block(buf, expected, start, finish)
  start, finish = start or md_start, finish or md_end
  vim.wait(1300, function()
    return vim.deep_equal(expected, block(buf, start, finish))
  end, 10)
  equal(expected, block(buf, start, finish))
end

local function idle()
  vim.wait(225, function() return false end, 10)
end

local function test(name, run)
  local ok, err = xpcall(run, debug.traceback)
  assert(ok, name .. '\n' .. tostring(err))
  count = count + 1
  print('ok - ' .. name)
end

test('startup defers loading and ignores other extensions', function()
  equal(2, vim.fn.exists(':AutoTocOn'))
  equal(2, vim.fn.exists(':AutoTocOff'))
  equal(0, vim.fn.exists(':AutoTocToggle'))
  local buf = open('.txt', { '# Ignored' })

  append(buf, { '## Also ignored' })
  idle()

  equal(nil, package.loaded['auto-toc'])
  equal({ '# Ignored', '## Also ignored' }, lines(buf))
end)

test('opening and prose edits leave a file without a TOC', function()
  local initial = { '# Title', '', 'A paragraph.' }
  local buf = open('.md', initial)
  idle()
  equal(false, vim.bo[buf].modified)
  equal(initial, lines(buf))

  replace(buf, 'A paragraph.', { 'A changed paragraph with a # in it.' })
  idle()

  equal({ '# Title', '', 'A changed paragraph with a # in it.' }, lines(buf))
end)

test('heading edits insert, update and remove a TOC', function()
  local buf, path = open('.md', { '# First', '', 'Body.' })
  append(buf, { '', '## Second' })
  await_block(buf, toc(md_start, md_end, { '- [First](#first)', '  - [Second](#second)' }))
  equal({ '# First', '', 'Body.' }, vim.fn.readfile(path))

  replace(buf, '## Second', { '# Renamed ###' })
  await_block(buf, toc(md_start, md_end, { '- [First](#first)', '- [Renamed](#renamed)' }))

  replace(buf, '# First', { 'First' })
  await_block(buf, toc(md_start, md_end, { '- [Renamed](#renamed)' }))
  replace(buf, '# Renamed ###', { 'Renamed' })
  await_block(buf, nil)
  equal({ '', 'First', '', 'Body.', '', 'Renamed' }, lines(buf))
end)

test('updating an existing TOC removes blank lines next to both markers', function()
  local original = { md_start, '', '', '', '- [Old](#old)', '', md_end, '', '# Old' }
  local buf = open('.md', original)
  equal(original, lines(buf))

  replace(buf, '# Old', { '# New' })

  await_block(buf, { md_start, '- [New](#new)', md_end })
end)

test('updates are visible while still in Insert mode', function()
  local path = vim.fn.tempname() .. '.md'
  vim.fn.writefile({ '# Original' }, path)
  local child = vim.fn.jobstart({
    vim.v.progpath, '--clean', '--headless', '--embed', '--cmd', 'set runtimepath^=.', path,
  }, { rpc = true })
  assert(child > 0, 'Could not start embedded Neovim')
  vim.rpcrequest(child, 'nvim_input', 'Go## While typing')

  local expected = { 'i', '  - [While typing](#while-typing)' }
  local observed
  vim.wait(1300, function()
    observed = vim.rpcrequest(child, 'nvim_eval', '[mode(), getline(3)]')
    return vim.deep_equal(expected, observed)
  end, 10)

  vim.rpcrequest(child, 'nvim_input', '<Esc>')
  vim.rpcnotify(child, 'nvim_command', 'qa!')
  equal({ 0 }, vim.fn.jobwait({ child }, 1300))
  equal(expected, observed)
end)

test('fences and indented code are excluded and code edits do not write', function()
  local buf = open('.md', {
    '# Real', '', '````lua', '# Four backticks', '```', md_start, '````', '',
    '~~~~ text', '# Tildes', md_end, '~~~~', '',
    '    # Four spaces', '', '> ```', '> # Quoted code', '> ```', '',
    'A # in the middle', '\\# Escaped', '####### Too many', '#No space',
  })
  replace(buf, '# Four backticks', { '# Edited code' })
  idle()
  equal('# Real', lines(buf)[1])

  replace(buf, '# Real', { '# Updated' })
  await_block(buf, toc(md_start, md_end, { '- [Updated](#updated)' }))
  replace(buf, '# Tildes', { '# Changed tildes' })
  local tick = api.nvim_buf_get_changedtick(buf)
  idle()

  equal(tick, api.nvim_buf_get_changedtick(buf))
  equal(toc(md_start, md_end, { '- [Updated](#updated)' }), block(buf, md_start, md_end))
end)

test('unclosed fences exclude their contents until closed', function()
  local buf = open('.md', { '# Real', '', '~~~', '# Hidden' })

  replace(buf, '# Real', { '# Updated' })
  await_block(buf, toc(md_start, md_end, { '- [Updated](#updated)' }))
  replace(buf, '# Hidden', { '~~~~', '# Visible' })

  await_block(buf, toc(md_start, md_end, { '- [Updated](#updated)', '- [Visible](#visible)' }))
end)

test('TOC indentation accounts for a skipped heading level', function()
  local buf = open('.md', { '# dotfiles', '### asfdasf' })

  append(buf, { '', '## Overview' })

  await_block(buf, toc(md_start, md_end, {
    '- [dotfiles](#dotfiles)',
    '    - [asfdasf](#asfdasf)',
    '  - [Overview](#overview)',
  }))
end)

test('a TOC starting at a deeper heading level still starts with a list', function()
  local buf = open('.md', { '#### Overview' })

  append(buf, { '###### Details', '##### Notes' })

  await_block(buf, toc(md_start, md_end, {
    '- [Overview](#overview)',
    '    - [Details](#details)',
    '  - [Notes](#notes)',
  }))
end)

test('anchors handle duplicates, Setext, Unicode and inline markup', function()
  local buf = open('.md', {
    '# Root',
    '## Overview',
    '',
    'Overview',
    '--------',
    '',
    '## Overview',
    '## Overview-1',
    '###### **日本語**：導入×🎯',
    '### [Guide](guide.md) &amp; `do_it`',
  })

  append(buf, { '## Last' })

  await_block(buf, toc(md_start, md_end, {
    '- [Root](#root)',
    '  - [Overview](#overview)',
    '  - [Overview](#overview-2)',
    '  - [Overview-1](#overview-1-1)',
    '      - [日本語：導入×🎯](#日本語導入)',
    '    - [Guide \\& do\\_it](#guide--do_it)',
    '  - [Last](#last)',
  }))
end)

test('YAML front matter stays above the Markdown TOC', function()
  local buf = open('.md', { '---', 'title: Page', '# metadata comment', '---', '', '# Initial' })

  replace(buf, '# Initial', { '# Updated' })
  await_block(buf, toc(md_start, md_end, { '- [Updated](#updated)' }))

  equal({ '---', 'title: Page', '# metadata comment', '---', '', md_start }, vim.list_slice(lines(buf), 1, 6))
end)

test('MDX keeps front matter and skips JSX, expressions, comments and code', function()
  local buf = open('.mdx', {
    '---', 'title: Page', '---', '', '# Before', '',
    '{/*', '# Hidden in a comment', '*/}', '',
    '<>', '<Panel value={"a > b"}>', '# Inside JSX', '</Panel>', '</>', '## After JSX',
    'export const example = `', '# Inside JavaScript', '`', '## After JavaScript',
    '{', '  /* # In an expression */', '}', '',
    '~~~', mdx_start, '# Hidden in a fence', mdx_end, '~~~',
    '', '```js', '# Hidden in backticks', '```',
  })
  vim.bo[buf].filetype = ''

  append(buf, { '', '# Last' })
  await_block(buf, toc(mdx_start, mdx_end, {
    '- [Before](#before)', '  - [After JSX](#after-jsx)', '  - [After JavaScript](#after-javascript)', '- [Last](#last)',
  }), mdx_start, mdx_end)
  equal({ '---', 'title: Page', '---', '', mdx_start }, vim.list_slice(lines(buf), 1, 5))

  replace(buf, '## After JavaScript', { '## Renamed' })
  await_block(buf, toc(mdx_start, mdx_end, {
    '- [Before](#before)', '  - [After JSX](#after-jsx)', '  - [Renamed](#renamed)', '- [Last](#last)',
  }), mdx_start, mdx_end)
end)

test('write flushes pending heading changes before the debounce', function()
  local buf, path = open('.md', { '# Original' })

  replace(buf, '# Original', { '# Saved' })
  vim.cmd.write()

  local expected = toc(md_start, md_end, { '- [Saved](#saved)' })
  vim.list_extend(expected, { '', '# Saved' })
  equal(expected, vim.fn.readfile(path))
  idle()
  equal(false, vim.bo[buf].modified)
end)

test('AutoTocOff cancels pending generation and AutoTocOn resumes it for one buffer', function()
  local first = open('.md', { '# A' })
  replace(first, '# A', { '# First' })
  await_block(first, toc(md_start, md_end, { '- [First](#first)' }))

  replace(first, '# First', { '# Paused' })
  vim.cmd.AutoTocOff()
  replace(first, '# Paused', { '# While disabled' })
  vim.cmd.AutoTocOff()
  local second = open('.md', { '# B' })
  replace(second, '# B', { '# Second' })
  await_block(second, toc(md_start, md_end, { '- [Second](#second)' }))
  equal(toc(md_start, md_end, { '- [First](#first)' }), block(first, md_start, md_end))

  api.nvim_set_current_buf(first)
  vim.cmd.AutoTocOn()

  equal(toc(md_start, md_end, { '- [While disabled](#while-disabled)' }), block(first, md_start, md_end))
  equal('Automatic TOC generation enabled', notices[#notices])
end)

test('AutoTocOn creates a TOC from existing headings and can be repeated', function()
  local buf = open('.mdx', { '# Existing heading' })
  equal(nil, block(buf, mdx_start, mdx_end))

  vim.cmd.AutoTocOn()
  local tick = api.nvim_buf_get_changedtick(buf)
  vim.cmd.AutoTocOn()

  equal(toc(mdx_start, mdx_end, { '- [Existing heading](#existing-heading)' }), block(buf, mdx_start, mdx_end))
  equal(tick, api.nvim_buf_get_changedtick(buf))
end)

test('undo and redo restore both the heading and the TOC', function()
  local initial = { '# Before', '', 'Body' }
  local buf = open('.md', initial)
  vim.cmd.normal({ bang = true, args = { 'ggcc# After' } })
  await_block(buf, toc(md_start, md_end, { '- [After](#after)' }))
  local edited = lines(buf)

  vim.cmd.undo()
  idle()
  equal(initial, lines(buf))

  vim.cmd.redo()
  idle()
  equal(edited, lines(buf))
end)

test('TOC insertion preserves the cursor on its heading', function()
  local buf = open('.md', { '# Old' })
  replace(buf, '# Old', { '# Updated' })
  api.nvim_win_set_cursor(0, { 1, 4 })

  await_block(buf, toc(md_start, md_end, { '- [Updated](#updated)' }))

  local cursor = api.nvim_win_get_cursor(0)
  equal(4, cursor[2])
  equal('# Updated', lines(buf)[cursor[1]])
end)

test('reopening a saved file leaves its TOC clean', function()
  local buf, path = open('.md', { '# Before' })
  replace(buf, '# Before', { '# Saved' })
  vim.cmd.write()
  local expected = lines(buf)
  vim.cmd.bwipeout()

  vim.cmd.edit(vim.fn.fnameescape(path))
  idle()

  equal(expected, lines(api.nvim_get_current_buf()))
  equal(false, vim.bo.modified)
end)

local malformed = {
  { 'missing end', { md_start, '', '# Before' } },
  { 'reversed', { md_end, '', md_start, '', '# Before' } },
  { 'duplicate', { md_start, '', md_end, '', md_start, '', '# Before' } },
}

for _, scenario in ipairs(malformed) do
  test('malformed markers are safe: ' .. scenario[1], function()
    local buf = open('.md', scenario[2])
    local expected = vim.deepcopy(scenario[2])
    expected[#expected] = '# Changed'

    replace(buf, '# Before', { '# Changed' })
    idle()

    equal(expected, lines(buf))
    equal('Expected exactly one ordered pair of auto-toc markers', notices[#notices])
  end)
end

test('repairing a marker lets the skipped heading change apply', function()
  local buf = open('.md', { md_start .. ' ', '', '# Before' })
  replace(buf, '# Before', { '# Changed' })
  idle()
  equal('Expected exactly one ordered pair of auto-toc markers', notices[#notices])

  api.nvim_buf_set_lines(buf, 1, 1, true, { md_end })

  await_block(buf, toc(md_start, md_end, { '- [Changed](#changed)' }))
end)

test('read-only buffers skip updates until writable', function()
  local buf = open('.md', { '# Initial' })
  vim.bo[buf].readonly = true

  replace(buf, '# Initial', { '# Changed' })
  idle()
  equal(nil, block(buf, md_start, md_end))

  vim.bo[buf].readonly = false
  vim.cmd.write()
  equal(toc(md_start, md_end, { '- [Changed](#changed)' }), block(buf, md_start, md_end))
end)

test('wiping a buffer cancels its queued update', function()
  local buf = open('.md', { '# Initial' })
  replace(buf, '# Initial', { '# Changed' })

  vim.cmd.bwipeout({ bang = true })
  idle()

  equal(false, api.nvim_buf_is_valid(buf))
end)

print(('%d tests passed'):format(count))
