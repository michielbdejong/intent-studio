# Intent Studio

An Elm drawing editor exploring **intent trees**, **intent sourcing**, and **The Elm Architecture**. A Paris postcard starts with 140 strokes grouped by their purpose. Rearrange whole branches, move chunks, inspect explanations, and replay how the document evolved.

**Start with [HANDOFF.md](HANDOFF.md) for project status and remaining work.**

## Status

- The original, working editor is published at https://intent-tree-paris-studio.michielbdejong.chatgpt.site (owner-private).
- This repository includes the subsequent AI subtree-regeneration implementation and a **Redraw** button for fresh variations of the same intention.
- **The AI update is not deployed or live-model-tested.** It needs a server-side OpenAI API key. No key was created or stored during this task.
- Automated checks: 22 Elm checks and 15 server tests, including mocked model responses. These do not establish live model quality or hosted API compatibility.

## Run locally

Requires Node.js **22.15 or newer** and npm. Elm is installed by npm; the first build needs network access to fetch Elm packages.

```sh
npm ci
npm run build
npm test
npm start
```

Open http://localhost:8765. The UI works without an API key, but redraw requests return a clear connection error and leave the document untouched.

For live regeneration, configure `OPENAI_API_KEY` in an ignored `.env.local` file using your approved credential workflow. Optional `OPENAI_MODEL` defaults to `gpt-5-mini`. See `.env.example` for variable names only. `npm start` loads `.env.local` on the server; browser code never receives the key. API usage is billed to the associated OpenAI project.

## Try it

1. Select an intention to highlight its strokes; expand branches to reach individual strokes.
2. Drag a branch by its grip onto another name to reorder it. Drop on ↳ to move it inside a branch.
3. Use **Move** arrows to translate a chunk and **Order** arrows to change sibling paint order.
4. At **Latest**, edit an intention and choose **Redraw subtree with AI**. With the API configured, a complete generated replacement becomes one explained history entry.
5. Click **↻ Redraw** to request a fresh variation using the saved intention (not an unsaved text draft).
6. Expand history entries, click numbered moments, or use the replay slider. Past states are read-only; return to **Latest** to edit.
7. Export the history as JSON or the drawing as SVG. Sessions are saved in browser-local storage, separately for each origin.

## Code map

| File | Purpose |
| --- | --- |
| `src/Main.elm` | Document and message types, pure reducers, editor, SVG view, and model-result handling |
| `src/Checks.elm` | Elm worker testing replay, tree integrity, and regeneration transitions |
| `dist/index.html`, `dist/style.css` | Source HTML and styles (currently maintained directly in `dist/`) |
| `dist/bridge.js` | Browser storage, downloads, and same-origin API calls through Elm ports |
| `server/regenerate.mjs` | Authenticated OpenAI Responses request, structured output, and validation |
| `server/worker.mjs` | Hosted route handler; serves embedded assets and the model endpoint |
| `scripts/build-worker.mjs` | Packages the Elm bundle and server into one Worker ESM module |
| `scripts/preview.mjs` | Local-only Node preview server with a synthetic local identity |
| `server/regenerate.test.mjs` | Server validation and failure tests using a mocked model transport |

The current document is a pure fold over a chronological log of `Change` records. Each change includes an intention reference, explanation, and exact operations. `Replace` stores the complete generated subtree, so replay never calls AI. The editable tree and historical order are separate structures.

## Boundaries

This is a single-user prototype. There is no collaborative storage, import-history UI, freehand drawing, dependency propagation across branches, or editing of past history. Reparenting preserves coordinates; it does not infer new geometry. Regeneration changes only the selected subtree. The paper, sun disk, and water tint are fixed presentation elements outside the recorded tree. See the handoff for known limitations and the next validation steps.

## License

[MIT](LICENSE) © 2026 Michiel de Jong.
