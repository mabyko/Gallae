# Visual Diff (Labs)

Enable **Settings → Labs → Visual Diff · PR Lens**. In Changes, History, or Stash review, choose **Visualize**. Gallae generates a diagram from the comparison on screen; no graph file, Node installation, API key, or network request is needed.

Changes uses **HEAD → index** for Staged and **index → working tree** for Working Tree (including untracked files). History uses the selected commit and its first parent, or the empty tree for the initial commit. Stash uses its saved changes, including untracked files. Each changed file becomes a card grouped by folder, with its status and line counts. Connections represent unambiguous symbol references found in the before/after diff context. Added and removed references have corresponding edge colors. This is a local change overview, not a complete architecture, call graph, or runtime/data-flow analysis. Unchanged code outside patch context is not analyzed.

**Back to Diff** always returns to the file diff, including added, deleted, untracked, and binary files where Split is unavailable. Unified/Split can also exit Visualize; unsupported Split falls back to Unified. Click a file card to open its diff, pan the canvas, and use **− / Fit / +** to zoom. **Full Screen** moves the same viewer into a native macOS full-screen window; **Esc**, **Exit Full Screen**, or closing that window returns to the embedded diagram with its camera preserved. Esc in the embedded diagram returns to Diff.

Graphs regenerate when the comparison or repository refresh generation changes. **Refresh** rebuilds the current graph on demand. Leaving and reopening the same comparison reuses its generated graph and camera. Changing repositories/worktrees or disabling Labs clears it. Generation is cancellable and reads Git off the main actor. Up to 256 changed files and 512 reference edges are supported; each patch is capped at 128 KiB. Binary, oversized, missing, and non-UTF-8 patches still get file cards, labeled without text analysis. If there are more than 512 references, the header identifies the edge limit. Filenames unsupported by the PR Lens path schema still get cards marked as unlinked.

**More → Import Graph…** remains available for richer graphs generated externally with [PR Lens](https://github.com/coldteadotai/pr-lens). Import a UTF-8 `graph.json` or `drawn.graph.json` up to 4 MiB. The bundled schema validates it before rendering. Imported architecture/data-flow graphs remain snapshots; their base/head is displayed but not verified against the current checkout. **More → Show Example** opens an explicitly labeled sample. **Refresh** replaces an import or example with the current comparison's generated graph.

The full bundled copyright notices and licenses are available in **Settings → About → Open Source Licenses…**, including when Visual Diff is disabled. The sheet reads the generated `LICENSES.txt` directly and supports scrolling and text selection.

## Updating the bundled renderer

The app loads `Gallae/Resources/VisualDiff/index.html` and the committed `viewer.js` from its bundle. The viewer has no network access or external navigation. Node and npm are needed only to rebuild these developer resources:

```sh
cd scripts/visual-diff
npm ci
npm test
npm run build
```

Dependencies are pinned in `package.json` and `package-lock.json`: `@coldtea/pr-lens-renderer` 0.3.2, `@coldtea/pr-lens-schema` 0.7.0, and esbuild 0.28.2. `build.js` bundles `viewer.js` for Safari 18 and regenerates `LICENSES.txt` with the MIT notices for PR Lens and Zod. The renderer's unused manifest code imports `node:crypto`; the build excludes it and checks that no Node imports remain in the browser bundle.

After changing dependencies, regenerate and review both bundled files, run the renderer tests, build/test the macOS app, and check import, node navigation, Light/Dark, Full Screen → Esc, and Labs disable in a disposable app with isolated preferences.
