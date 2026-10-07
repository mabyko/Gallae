# Visual Diff (Labs)

Enable **Settings → Labs → Visual Diff · PR Lens**. In a file's Changes, History, or stash diff, choose **Visualize**, then **Import Graph…**. **Show Example** opens an explicitly labeled example for trying the controls.

Import a PR Lens `graph.json` or `drawn.graph.json` (UTF-8 JSON, at most 4 MiB). The bundled schema validates the full graph before replacing the current diagram. Architecture and data-flow views appear when the graph includes those lenses. A manifest or rendered SVG cannot be imported.

Drag the canvas to pan, use **− / Fit / +** to zoom, and click a file node to open its diff. Navigation uses the node's first file reference and only matches files in the current review, including original paths for renames. A node outside that list shows a message. **Full Screen** moves the same viewer into a native macOS full-screen window; **Esc**, **Exit Full Screen**, or the window close control returns to Diff. Manual zoom and pan survive this transition.

Imported graphs are snapshots. Their repository and base/head are displayed, but they are not verified against or regenerated from the current checkout. They remain in memory while reviewing the same workspace; changing repositories or worktrees, disabling the experiment, or restarting clears them. Gallae does not invoke an AI provider, install Node, or upload code. Generate graphs separately using the [PR Lens project](https://github.com/coldteadotai/pr-lens) or a coding agent. PR Lens CLI analysis covers committed base/head changes; it does not directly analyze Gallae's staged/unstaged selection.

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
