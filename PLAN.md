# auto-toc.nvim implementation plan

## Summary

Build a Lua plugin for Neovim 0.12 and later that maintains a table of contents in `.md` and `.mdx` files. Opening a file leaves it clean. The first heading edit creates the TOC, and later heading edits update it as the user types.

Follow Neovim's Lua plugin guidance with a small `plugin/` entry point, deferred modules under `lua/`, and documentation at `:help auto-toc`. [Neovim Lua plugin guide](https://neovim.io/doc/user/lua-plugin/)

## Implementation

- Match normal buffers by extension. Enable generation by default. `:AutoTocToggle` pauses or resumes the current buffer for its lifetime. Pausing keeps the TOC and cancels pending work. Resuming reconciles the TOC immediately.
- Use Neovim's bundled Markdown Tree-sitter parsers. Collect ATX headings in document order and exclude code blocks. For MDX, support Markdown-style headings outside JSX and embedded JavaScript, and ignore standalone comments. Render nested Markdown links with GitHub-style fragments. Setext headings count toward duplicate suffixes. MDX renderers need matching heading IDs. [GitHub section links](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#section-links)
- Place the generated block before document content and after leading front matter. Use HTML comments as Markdown markers and JSX comments as MDX markers. Update a single valid block in place and remove it when the last heading disappears. Ignore markers inside code. Warn and skip ambiguous marker layouts.
- Record a heading baseline on attachment. Debounce edits by 150 ms and flush pending changes before a write. Replace only the changed TOC range, preserve the cursor's document position, and join the update to the triggering edit when Neovim's undo state permits. Allow undo and redo to restore historical contents. Skip read-only and nonmodifiable buffers and cancel work when a buffer detaches.

## Verification

- Run headless tests on Neovim 0.12.0 and the latest stable 0.12 patch release.
- Cover clean opening, heading additions, renames, level changes, removal, immediate saves, and reopening.
- Cover code fences, indented Markdown code, heading-like prose, front matter, MDX comments, formatted headings, duplicate anchors, Japanese titles, and malformed markers.
- Verify per-buffer toggles, cancellation and resumption, undo and redo, cursor position, native package installation, and `:help auto-toc`.
