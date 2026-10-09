# Intent Studio

An interactive Elm example connecting The Elm Architecture, intent trees, and intent sourcing. The Paris postcard contains 140 individual strokes, grouped into meaningful branches.

## Run locally

Requires Node.js/npm and Python 3 for the convenience preview server.

```sh
npm ci
npm run build
npm test
npm start
```

Open http://localhost:8765. The compiled app is also included in `dist/`.

## Try it

- Select an intention to highlight all its strokes. Expand a branch to reach individual strokes.
- Drag a branch by its grip onto another name to move it before that sibling. Drop on the ↳ target to move it inside a branch. This changes grouping and paint order while retaining coordinates.
- Use the Move arrows to translate a selected chunk; Order arrows give a keyboard-accessible alternative for sibling reordering.
- Hide/show a chunk, or expand “Edit this intention” to revise its text.
- Expand a history entry to inspect its operations. Click its numbered dot or use the slider to reconstruct that moment. Replay animates the recorded changes.
- Earlier states are read-only. Return to Latest to append more changes.
- Changes save automatically to this browser's local storage. Export history downloads the complete versioned JSON log. Save drawing exports SVG without selection highlighting.

## Architecture

`src/Main.elm` holds the document types, pure operation reducer, seed history, Elm update loop, SVG projection, and editor views. `src/Checks.elm` exercises meaningful invariants using an Elm worker; `checks/run.cjs` reports the results.

The recursive `Node` type represents both intentions and leaf strokes. `Operation` records addition, reparenting/reordering, translation, visibility, and wording changes. A `Change` adds the intention reference, a title, and an explanation. The document at a point in time is a pure fold over the corresponding history prefix. Sibling order determines paint order; reparenting rejects self/descendant cycles and missing destinations.

Temporary UI state (selection, disclosure state, drag state, playback position) is separate from saved document changes. The small `dist/bridge.js` handles only local storage and downloads. Application state and interaction logic live in Elm.

## Prototype boundaries

This is a curated drawing example, not an AI drawing service or freehand editor. Intent-text edits do not generate new geometry. Reparenting preserves existing coordinates; it does not infer how to adapt geometry to a new purpose. History is chronological and append-only; the current intent tree is freely rearrangeable. There is no collaboration server, imported-history UI, dependency-graph regeneration, or editing of past history. Saving is specific to the browser and origin. A fixed paper backdrop, sun disk, and water tint provide presentation context outside the recorded strokes.

Validation: Elm compilation, 13 reducer/serialization checks, and browser interaction checks for translation, reordering, reparenting, replay and reload restoration.
