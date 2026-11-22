# auto-toc.nvim

Maintain a linked table of contents in Markdown and MDX while editing in Neovim.

## Installation

Requires Neovim 0.12 or later with the bundled `markdown` and `markdown_inline`
Tree-sitter parsers. For a local copy, add its path to `runtimepath` in
`init.lua`:

```lua
vim.opt.runtimepath:prepend('/path/to/auto-toc.nvim')
```

Run `:helptags ALL` once to make the help topic available. If you have a Git
checkout, you can install it and generate help tags with Neovim's package
manager. Use the checkout's absolute path or its remote Git URL:

```lua
vim.pack.add({ { src = 'file:///path/to/auto-toc.nvim', name = 'auto-toc.nvim' } })
```

### lazy.nvim

Add this local plugin spec to the directory your `lazy.nvim` config imports:

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

## Usage

Open a `.md` or `.mdx` file and add, rename, change the level of, or remove a
`#` heading. After a short pause, the plugin updates the TOC in the buffer.
It also processes pending heading changes before a write.

- Opening a file or editing prose or code alone leaves the TOC untouched.
- `:AutoTocToggle` pauses generation for the current buffer and keeps its TOC.
  Run it again to resume and refresh the TOC immediately.
- The generated list goes before the document body, after any leading front
  matter. Its start and end comments identify the region the plugin manages.
  Removing the final heading removes the managed list.
- Links use GitHub-style heading fragments. MDX support covers Markdown
  headings and fenced code outside JSX and JavaScript. Configure your MDX
  renderer to generate matching heading IDs for the links to work.

See `:help auto-toc` for details.

## Tests

```sh
nvim --clean --headless --cmd 'set runtimepath^=.' -l tests/run.lua
```
