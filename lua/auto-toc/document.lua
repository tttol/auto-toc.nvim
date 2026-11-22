local mdx = require('auto-toc.mdx')

local M = {}

local markers_by_extension = {
  md = { start = '<!-- auto-toc:start -->', finish = '<!-- auto-toc:end -->' },
  mdx = { start = '{/* auto-toc:start */}', finish = '{/* auto-toc:end */}' },
}

local protected_types = {
  fenced_code_block = true,
  indented_code_block = true,
  minus_metadata = true,
  plus_metadata = true,
}

local function parse(lines)
  local source = table.concat(lines, '\n') .. '\n'
  return vim.treesitter.get_string_parser(source, 'markdown'):parse()[1]:root(), source
end

local function protected_rows(node, rows, nested)
  local kind = node:type()
  if protected_types[kind] then
    if (kind == 'fenced_code_block' and not nested) or kind == 'indented_code_block' then
      return
    end
    local start_row, _, end_row, end_col = node:range()
    local last = end_row + (end_col > 0 and 1 or 0)
    for row = start_row + 1, last do
      rows[row] = true
    end
    return
  end
  if kind == 'inline' then
    return
  end
  nested = nested or kind == 'block_quote' or kind == 'list_item'
  for child in node:iter_children() do
    protected_rows(child, rows, nested)
  end
end

local function collect(node, source, lines, document, delimiters)
  local kind = node:type()
  if protected_types[kind] or kind == 'inline' then
    return
  end

  if kind == 'atx_heading' or kind == 'setext_heading' then
    local first = node:named_child(0)
    local atx = kind == 'atx_heading'
    local inline = atx and node:field('heading_content')[1] or (not atx and first:named_child(0))
    local title = inline and vim.treesitter.get_node_text(inline, source) or ''
    if atx then
      title = title:gsub('[ \t]+#+[ \t]*$', ''):gsub('^#+[ \t]*$', '')
    end
    local row = node:start()
    document.headings[#document.headings + 1] = {
      row = row + 1,
      level = atx and tonumber(first:type():match('^atx_h(%d)_marker$')) or nil,
      title = vim.trim(title),
    }
    return
  end

  if kind == 'html_block' then
    local first, col, last, end_col = node:range()
    local marker = delimiters[lines[first + 1]:gsub('[ \t]+$', '')]
    if marker and col == 0 and last == first + 1 and end_col == 0 then
      document.markers[#document.markers + 1] = { row = first + 1, kind = marker }
    end
    return
  end

  for child in node:iter_children() do
    collect(child, source, lines, document, delimiters)
  end
end

--- Parse heading and marker positions without mutating the buffer.
--- @param lines string[]
--- @param extension 'md'|'mdx'
function M.inspect(lines, extension)
  local document = { headings = {}, markers = {}, front_matter_end = 0 }
  local marker_text = markers_by_extension[extension]
  local delimiters = { [marker_text.start] = 'start', [marker_text.finish] = 'finish' }
  local root, source = parse(lines)
  local first = root:named_child(0)
  if first and (first:type() == 'minus_metadata' or first:type() == 'plus_metadata') then
    local last, col = first:end_()
    document.front_matter_end = last + (col > 0 and 1 or 0)
  end

  if extension == 'mdx' then
    local protected = {}
    protected_rows(root, protected)
    lines, document.markers = mdx.mask(lines, protected, delimiters)
    root, source = parse(lines)
    delimiters = {}
  end
  collect(root, source, lines, document, delimiters)
  return document
end

--- Locate the only region the plugin is allowed to replace.
--- @return { first: integer, last: integer }? block
--- @return string? err
function M.block(document)
  local markers = document.markers
  if #markers == 0 then
    return
  end
  if #markers == 2 and markers[1].kind == 'start' and markers[2].kind == 'finish' then
    return { first = markers[1].row, last = markers[2].row }
  end
  return nil, 'Expected exactly one ordered pair of auto-toc markers'
end

function M.heading_signature(document, block)
  local signature = {}
  for _, heading in ipairs(document.headings) do
    if not block or heading.row < block.first or heading.row > block.last then
      signature[#signature + 1] = { level = heading.level, title = heading.title }
    end
  end
  return signature
end

--- Prepare exactly one line edit, expressed with Neovim's zero-based indices.
function M.edit(lines, document, extension, block, entries)
  if #entries == 0 then
    if block then
      return { first = block.first - 1, last = block.last, lines = {} }
    end
    return
  end

  local markers = markers_by_extension[extension]
  local replacement = { markers.start }
  vim.list_extend(replacement, entries)
  replacement[#replacement + 1] = markers.finish
  if block then
    local existing = vim.list_slice(lines, block.first, block.last)
    if not vim.deep_equal(existing, replacement) then
      return { first = block.first - 1, last = block.last, lines = replacement }
    end
    return
  end

  local first = document.front_matter_end
  if first > 0 then
    if lines[first + 1] == '' then
      first = first + 1
    else
      table.insert(replacement, 1, '')
    end
  end
  if lines[first + 1] and not lines[first + 1]:match('^%s*$') then
    replacement[#replacement + 1] = ''
  end
  return { first = first, last = first, lines = replacement }
end

return M
