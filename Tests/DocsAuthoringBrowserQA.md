# Docs Authoring Browser QA

Use this checklist after changes to the in-browser docs editor. Run it against a disposable UE project with the docs server and editor API host running, for example `C:\Users\Rim28\Projects\UEToolSetTest` at `http://localhost:3000/docs/`.

## Required Browser Pass

1. Open `/docs/` in the in-app browser and verify browse mode has one visible `Edit` entrypoint.
2. Enter edit mode on a normal Markdown doc.
3. Verify frontmatter such as `slug:` and `sidebar_position:` is not visible in the authoring surface.
4. Verify every toolbar control is visible, readable, and at least 28x28 px:
   - save, discard, exit
   - bold, italic, underline, strikethrough, inline code, code block, clear formatting
   - H1, H2, H3
   - bulleted list, numbered list, task list, quote
   - link, unlink, image
   - left, center, right alignment
   - TOC marker, table, add/delete row, add/delete column, delete table
   - divider, note, Mermaid, emoji/icon markdown
5. Create a temporary page from the sidebar `New page` control.
6. On the temporary page, insert and save:
   - link, then remove a link while preserving its text
   - image, then save and reload to confirm it renders in browse mode
   - task list, then save and reload to confirm checkboxes render in browse mode
   - code block, then save and reload to confirm a fenced code block renders
   - TOC marker, then save or discard to confirm the editor is not locked
   - table, then add/delete a row and column, then delete the full table
   - note block, then confirm the editor renders a note panel and browse mode renders a Docusaurus admonition
   - Mermaid diagram, then confirm edit mode and browse mode render SVG output
7. Verify Save returns to browse mode with no visible error and no raw frontmatter, raw note fences, or raw Mermaid fences.
8. Re-enter edit mode on the same page and verify Discard returns content to the last saved state.
9. Create a temporary section from the sidebar `New section` control.
10. Open `Site Settings` and use the Site Settings structure ordering controls to reorder the temporary page and verify:
    - the page changes order without the sidebar blanking or duplicating rows
    - the public URL still loads through the preserved slug
    - no transform, save helper, or fetch error is visible
11. Hide the temporary page from the site and verify:
    - the page disappears from the sidebar after refresh
    - the direct URL still loads
    - no raw front matter is shown in browse mode
12. Show the same page in the site again and verify it returns to the sidebar in the expected order.
13. Use the same `Site Settings` structure ordering controls on a section and verify the section reorders cleanly with no stuck hover state or stale rows.
14. Clean up all temporary docs files and reload `/docs/` to confirm the sidebar is back to the expected state.

## Failure Capture

For each failure, record:

- exact visible action
- visible error text
- console error, if present
- failed API endpoint and status, if visible
- before/after file path or sibling order for reorder failures
- the temp page or section name used for reproduction

Keep a screenshot of the failing state and one screenshot of the final passing state.
