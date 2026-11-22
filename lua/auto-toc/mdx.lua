local M = {}

local opens = { ['{'] = true, ['['] = true, ['('] = true }
local closes = { ['}'] = true, [']'] = true, [')'] = true }
local quotes = { ["'"] = true, ['"'] = true, ['`'] = true }

-- Track delimiters across lines so Markdown inside JavaScript stays opaque.
local function scan_js(line, cursor, js, stop_at_close)
  while cursor <= #line do
    local char = line:sub(cursor, cursor)
    local pair = line:sub(cursor, cursor + 1)
    if js.quote then
      if char == '\\' then
        cursor = cursor + 1
      elseif char == js.quote then
        js.quote = nil
      end
    elseif js.comment then
      if pair == '*/' then
        js.comment = nil
        cursor = cursor + 1
      end
    elseif pair == '//' then
      return #line + 1
    elseif pair == '/*' then
      js.comment = true
      cursor = cursor + 1
    elseif quotes[char] then
      js.quote = char
    elseif opens[char] then
      js.depth = js.depth + 1
    elseif closes[char] then
      js.depth = math.max(0, js.depth - 1)
      if stop_at_close and js.depth == 0 then
        return cursor + 1
      end
    end
    cursor = cursor + 1
  end
  return cursor
end

local function tag_start(line, cursor)
  local prefix, name, after = line:match('^(</?)([%a_$][%w_.:$-]*)()', cursor)
  if not prefix then
    prefix, after = line:match('^(</?)()>', cursor)
    name = ''
  end
  if not after then
    return
  end
  local next_char = line:sub(after, after)
  if next_char == '' or next_char == '>' or next_char:match('%s') or line:sub(after, after + 1) == '/>' then
    return { closing = prefix == '</', name = name }, after
  end
end

local function scan_jsx(line, jsx)
  local cursor = 1
  while cursor <= #line do
    local char = line:sub(cursor, cursor)
    if jsx.js then
      cursor = scan_js(line, cursor, jsx.js, true)
      if jsx.js.depth == 0 then
        jsx.js = nil
      end
    elseif jsx.quote then
      if char == jsx.quote then
        jsx.quote = nil
      end
      cursor = cursor + 1
    elseif char == '{' then
      jsx.js = { depth = 1 }
      cursor = cursor + 1
    elseif jsx.tag then
      if char == '"' or char == "'" then
        jsx.quote = char
      elseif char == '>' then
        local tag = jsx.tag
        if tag.closing and jsx.stack[#jsx.stack] == tag.name then
          table.remove(jsx.stack)
        elseif not tag.closing and line:sub(cursor - 1, cursor - 1) ~= '/' then
          jsx.stack[#jsx.stack + 1] = tag.name
        end
        jsx.tag = nil
      end
      cursor = cursor + 1
    elseif char == '<' then
      local tag, after = tag_start(line, cursor)
      jsx.tag = tag
      cursor = after or cursor + 1
    else
      cursor = cursor + 1
    end
  end
  return jsx.tag ~= nil or #jsx.stack > 0
end

local function fence_token(line)
  local indent, token, tail = line:match('^( *)(`+)(.*)$')
  if not token then
    indent, token, tail = line:match('^( *)(~+)(.*)$')
  end
  if token and #indent <= 3 and #token >= 3 then
    return token, tail
  end
end

local function open_fence(line)
  local token, tail = fence_token(line)
  if token and (token:sub(1, 1) == '~' or not tail:find('`', 1, true)) then
    return token
  end
end

--- Mask MDX flow constructs before parsing the remaining Markdown.
--- @param lines string[]
--- @param protected table<integer, boolean> One-based nested Markdown fences and metadata rows
--- @param delimiters table<string, string> Marker text to marker name
--- @return string[] markdown
--- @return {row: integer, kind: string}[] markers
function M.mask(lines, protected, delimiters)
  local markdown, markers = {}, {}
  local jsx, js, fence
  for row, line in ipairs(lines) do
    local visible = line:match('^%s*(.*)$')
    local kind = delimiters[line:gsub('[ \t]+$', '')]
    markdown[row] = line

    if fence then
      local token, tail = fence_token(line)
      if token and #token >= #fence and token:sub(1, 1) == fence:sub(1, 1) and tail:match('^%s*$') then
        fence = nil
      end
      if jsx then
        markdown[row] = ''
      end
    elseif jsx then
      markdown[row] = ''
      if not jsx.js and not jsx.tag then
        fence = open_fence(line)
      end
      if not fence and not protected[row] and not scan_jsx(line, jsx) then
        jsx = nil
      end
    elseif js then
      markdown[row] = ''
      scan_js(line, 1, js, not js.esm)
      if js.depth == 0 and not js.quote and not js.comment then
        js = nil
      end
    elseif not protected[row] then
      fence = open_fence(line)
      if not fence then
        if kind then
          markers[#markers + 1] = { row = row, kind = kind }
          markdown[row] = ''
        elseif visible:sub(1, 1) == '{' then
          local expression = { depth = 1 }
          scan_js(visible, 2, expression, true)
          if expression.depth > 0 then
            js = expression
          end
          markdown[row] = ''
        elseif visible:match('^import%s') or visible:match('^export%s') then
          local statement = { depth = 0, esm = true }
          scan_js(visible, 1, statement, false)
          if statement.depth > 0 or statement.quote or statement.comment or visible:match('[=,]%s*$') then
            js = statement
          end
          markdown[row] = ''
        elseif tag_start(visible, 1) then
          local element = { stack = {} }
          if scan_jsx(visible, element) then
            jsx = element
          end
          markdown[row] = ''
        end
      end
    end
  end
  return markdown, markers
end

return M
