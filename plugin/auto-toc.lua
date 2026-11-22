if vim.g.loaded_auto_toc or vim.fn.has('nvim-0.12') == 0 then
  return
end
vim.g.loaded_auto_toc = true

vim.api.nvim_create_user_command('AutoTocOn', function()
  require('auto-toc').set_enabled(vim.api.nvim_get_current_buf(), true)
end, { desc = 'Enable and refresh the automatic table of contents for this buffer' })

vim.api.nvim_create_user_command('AutoTocOff', function()
  require('auto-toc').set_enabled(vim.api.nvim_get_current_buf(), false)
end, { desc = 'Disable automatic table of contents updates for this buffer' })

local group = vim.api.nvim_create_augroup('AutoToc', { clear = true })
local patterns = { '*.md', '*.mdx' }

vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufNewFile', 'BufEnter' }, {
  group = group,
  pattern = patterns,
  callback = function(event)
    require('auto-toc').attach(event.buf)
  end,
})

vim.api.nvim_create_autocmd('BufFilePost', {
  group = group,
  callback = function(event)
    local plugin = package.loaded['auto-toc']
    if plugin then
      plugin.rename(event.buf)
    elseif vim.api.nvim_buf_get_name(event.buf):match('%.mdx?$') then
      require('auto-toc').attach(event.buf)
    end
  end,
})

vim.api.nvim_create_autocmd('BufWritePre', {
  group = group,
  pattern = patterns,
  callback = function(event)
    local plugin = package.loaded['auto-toc']
    if plugin then
      plugin.flush(event.buf)
    end
  end,
})

-- Native packages can be loaded after a Markdown buffer is already open.
for _, buf in ipairs(vim.api.nvim_list_bufs()) do
  if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_name(buf):match('%.mdx?$') then
    require('auto-toc').attach(buf)
  end
end
