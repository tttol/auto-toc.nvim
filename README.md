<!-- auto-toc:start -->
- [auto-toc.nvim](#auto-tocnvim)
  - [Installation](#installation)
    - [Local checkout](#local-checkout)
  - [Configuration](#configuration)
  - [Usage](#usage)
  - [Tests](#tests)
<!-- auto-toc:end -->

# auto-toc.nvim
Generates the table of contents in your *.md/*.mdx file automatically.

## Installation

Requires Neovim 0.12 or later with the bundled `markdown` and `markdown_inline` Tree-sitter parsers.

Add this spec to the directory your `lazy.nvim` config imports.

```lua
return {
  'tttol/auto-toc.nvim',
}
```

### Local checkout

For a local copy, add its path to `runtimepath` in `init.lua`.

```lua
vim.opt.runtimepath:prepend('/path/to/auto-toc.nvim')
```

Run `:helptags ALL` once to make the help topic available. If you have a Git
checkout, you can install it and generate help tags with Neovim's package
manager. Use the checkout's absolute path or its remote Git URL:

```lua
vim.pack.add({ { src = 'file:///path/to/auto-toc.nvim', name = 'auto-toc.nvim' } })
```

For local development with `lazy.nvim`, point the spec at your checkout.

```lua
return {
  dir = '/path/to/auto-toc.nvim',
  name = 'auto-toc.nvim',
  lazy = false,
}
```

If you add to `runtimepath` after `lazy.nvim` has started, source the entry
point explicitly with `vim.cmd.runtime('plugin/auto-toc.lua')`. In an open
Neovim session with the path already added, run `:runtime plugin/auto-toc.lua`.

## Configuration

Automatic updates are enabled by default. To start with them disabled, set
`enabled = false` in your `lazy.nvim` spec.

```lua
return {
  'tttol/auto-toc.nvim',
  opts = { enabled = false },
}
```

For a manual installation, call `require('auto-toc').setup({ enabled = false })`
after adding the plugin to `runtimepath`. The commands below override the
default for the current buffer.

## Usage

Open a `.md` or `.mdx` file and add, rename, change the level of, or remove a
`#` heading. After a short pause, the plugin updates the TOC in the buffer.
It also processes pending heading changes before a write.

- Opening a file or editing prose or code alone leaves the TOC untouched.
- `:AutoTocOn` enables automatic updates and refreshes the current buffer's
  TOC immediately.
- `:AutoTocOff` disables automatic updates for the current buffer and keeps
  its existing TOC.

See `:help auto-toc` for details.

## Tests

```sh
nvim --clean --headless --cmd 'set runtimepath^=.' -l tests/run.lua
```
