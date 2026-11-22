local unicode_ranges = require('auto-toc.unicode')

local M = {}

local entities = {
  amp = '&', apos = "'", gt = '>', lt = '<', quot = '"', nbsp = ' ',
  copy = '©', reg = '®', trade = '™', ndash = '–', mdash = '—', hellip = '…',
}

local link_nodes = {
  inline_link = true,
  full_reference_link = true,
  collapsed_reference_link = true,
  shortcut_link = true,
  image = true,
}

local hidden_nodes = { emphasis_delimiter = true, html_tag = true }

local function decode_entity(raw, kind)
  if kind == 'entity_reference' then
    return entities[raw:sub(2, -2)] or raw
  end
  local hex = raw:match('^&#[xX]([%da-fA-F]+);$')
  local number = hex and tonumber(hex, 16) or tonumber(raw:match('^&#(%d+);$'))
  if not number or number == 0 or number > 0x10FFFF or (number >= 0xD800 and number <= 0xDFFF) then
    return '�'
  end
  return vim.fn.nr2char(number)
end

-- Inline nodes describe markup spans; plain text lives between their children.
local function inline_text(node, source)
  local kind = node:type()
  local _, _, first = node:start()
  local _, _, last = node:end_()
  local raw = source:sub(first + 1, last)

  if hidden_nodes[kind] then
    return ''
  elseif kind == 'code_span' then
    local content = raw:gsub('^`+', ''):gsub('`+$', ''):gsub('\n', ' ')
    if content:match('^ .* $') and content:find('[^ ]') then
      content = content:sub(2, -2)
    end
    return content
  elseif kind == 'backslash_escape' then
    return raw:sub(2)
  elseif kind == 'uri_autolink' or kind == 'email_autolink' then
    return raw:sub(2, -2)
  elseif kind == 'entity_reference' or kind == 'numeric_character_reference' then
    return decode_entity(raw, kind)
  elseif link_nodes[kind] then
    for child in node:iter_children() do
      if child:type() == 'link_text' or child:type() == 'image_description' then
        return inline_text(child, source)
      end
    end
    return ''
  end

  local parts, offset = {}, first
  for child in node:iter_children() do
    local _, _, child_first = child:start()
    local _, _, child_last = child:end_()
    parts[#parts + 1] = source:sub(offset + 1, child_first)
    -- Anonymous punctuation is literal within an inline node.
    parts[#parts + 1] = child:named() and inline_text(child, source) or source:sub(child_first + 1, child_last)
    offset = child_last
  end
  parts[#parts + 1] = source:sub(offset + 1, last)
  return table.concat(parts)
end

local function unicode_word(character)
  local codepoint = vim.fn.char2nr(character)
  local first, last = 1, #unicode_ranges / 2
  while first <= last do
    local index = math.floor((first + last) / 2)
    if codepoint < unicode_ranges[index * 2 - 1] then
      last = index - 1
    elseif codepoint > unicode_ranges[index * 2] then
      first = index + 1
    else
      return true
    end
  end
  return false
end

local function slug(text)
  local result = {}
  for character in vim.fn.tolower(text):gmatch('[%z\1-\127\194-\244][\128-\191]*') do
    if character == ' ' then
      result[#result + 1] = '-'
    elseif character:match('^[a-z0-9_-]$') or (#character > 1 and unicode_word(character)) then
      result[#result + 1] = character
    end
  end
  return table.concat(result)
end

local function unique(base, used)
  local suffix = used[base] or 0
  local anchor = base
  while used[anchor] do
    suffix = suffix + 1
    anchor = base .. '-' .. suffix
  end
  used[base] = suffix
  used[anchor] = 0
  return anchor
end

--- Render ATX headings as a list. Count Setext headings when allocating anchors.
--- @param headings {level: integer?, title: string}[]
--- @return string[]
function M.entries(headings)
  local entries, ancestors, used = {}, {}, {}
  for _, heading in ipairs(headings) do
    local parser = vim.treesitter.get_string_parser(heading.title, 'markdown_inline')
    local text = vim.trim(inline_text(parser:parse()[1]:root(), heading.title):gsub('\n', ' '))
    local anchor = unique(slug(text), used)
    local level = heading.level
    if level and text ~= '' then
      while #ancestors > 0 and ancestors[#ancestors].level >= level do
        table.remove(ancestors)
      end
      local parent = ancestors[#ancestors]
      -- A child marker can be indented up to three spaces beyond its parent's content.
      local indent = parent and parent.indent + 2 * math.min(level - parent.level, 2) or 0
      local label = text:gsub('([\\%[%]*_`~<>&{}])', '\\%1')
      local entry = anchor == '' and label or ('[%s](#%s)'):format(label, anchor)
      entries[#entries + 1] = (' '):rep(indent) .. '- ' .. entry
      ancestors[#ancestors + 1] = { level = level, indent = indent }
    end
  end
  return entries
end

return M
