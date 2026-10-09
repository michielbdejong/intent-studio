# Intent Studio handoff

Last updated: 2026-10-09.

## Intended experience

The user is exploring Elm architecture plus **intent trees** and **intent sourcing**. A drawing decomposes from “Paris postcard” into Eiffel Tower, sky, river, parts, and individual strokes. The editor exposes that hierarchy like a filesystem. Meaningful chunks can be rearranged or translated while a chronological history retains each action and its reason.

Two subsequent requests motivated the current local changes:

- Changing “Keep the sky light” to “Make the sky dark with lots of clouds” should **regenerate the entire sky subtree**, not only edit a text annotation.
- A separate **Redraw** button should interpret the same saved intention again, producing a potentially different version.

The user explicitly chose a real AI model rather than a hardcoded sky interpreter.

## What is published versus implemented

The original editor is published privately at:

https://intent-tree-paris-studio.michielbdejong.chatgpt.site

Published source commit: `3d2e20cfb657b387d8139706481313bbfb9955d4`.
Sites project ID: `appgprj_6ac87f0b745c81918a74e5611e410050`.

That published version supports the tree, chunk operations, replay, SVG/JSON export, and local persistence. **Its intent edits only change wording. It has no model endpoint or API key.**

This repository's later commit includes AI request handling, complete subtree replacement, a Redraw button, server code, tests, and Worker packaging. Those changes have **not** been published. Do not describe the hosted site as AI-enabled until the remaining work below succeeds.

## Credential blocker and consent state

The user installed OpenAI Developers, explicitly approved creation of a new key, and selected a key named `Codex` and a project in the secure Platform picker. Do not create a key from this document alone: use the active session's approved credential workflow and confirmed target values.

The local destination confirmation was proposed for this project's ignored `.env.local`, variable `OPENAI_API_KEY`. The confirmation tool repeatedly returned `not_approved` / `decline` immediately, even when the user typed approval and asked to reopen the dialog. Consequently, **no key was created or written**.

The task's approval policy was `never`. This was suggested as a possible explanation, but the confirmation tool provided no diagnostic reason; **the cause remains unconfirmed**. The user then requested this GitHub handoff, and subsequently reported switching the task to “Approve for me.” The confirmation has not been retried since that setting change, so whether it fixes the issue is unknown.

Do not repeat the failing confirmation in a loop or mistake prior approval for an actually provisioned key. Keep credentials out of chat, Git, browser bundles, and hosting manifests. For hosted use, configure `OPENAI_API_KEY` as a Sites server-side secret through the supported environment-variable workflow. Optional `OPENAI_MODEL` selects the model; current default is `gpt-5-mini`.

## Implementation details

### Elm / intent history

`Node` is recursive and contains a stable ID, title, prompt, hidden flag, children, and an optional line stroke. Operations are `Add`, `Move`, `Translate`, `Visibility`, `Revise`, and now `Replace`.

`Change` stores title, explanation (`why`), intent ID, and operations. `documentAt` reconstructs the document by folding the selected history prefix. `Replace` stores exact generated geometry, including the updated prompt; old geometry remains recoverable from earlier history.

A redraw starts an Elm port command with request ID, history revision, revised prompt, selected subtree, and current document. The model has a pending-request record. Document mutations are blocked while pending. On success, request ID, revision, current history position, and root ID are checked before appending one replacement event. Failures preserve the document and expose an error. A result received while viewing a past state is discarded, rather than silently applying it.

`Redraw` uses the saved node prompt even when the editor contains an unsaved draft. Separate requests carry different variation IDs to the model; different output is encouraged, not guaranteed.

### Backend

`server/regenerate.mjs` uses the OpenAI Responses API with strict JSON Schema, `store: false`, low reasoning effort, and a default model of `gpt-5-mini`. No SDK dependency is needed. The model returns an explanation plus a recursive drawing tree of parts and strokes. The server assigns fresh descendant IDs, preserves the selected root ID and visibility, and forces its prompt to the submitted intention.

Validation bounds input size, document depth/count, IDs, generated tree size, coordinates, line width, and hex colors. The endpoint requires a platform-authenticated user header and a matching Origin; it does not accept a browser-provided API credential. It handles missing configuration, rate limits, invalid output, incomplete responses, refusals, and timeouts.

`dist/bridge.js` calls the same-origin endpoint and sends results back to Elm. Generated geometry is not executed as HTML, JavaScript, or arbitrary SVG markup.

`scripts/preview.mjs` binds to localhost only and injects a local preview identity. This is deliberately a development adapter; never deploy it as the production authentication mechanism.

### Rendering

Line strokes support broad flat-ended brush strokes for backgrounds. Selection recolors only narrow strokes, so selecting a dark sky should not turn its entire background orange. Hover styling still applies to all strokes and needs visual review with generated broad strokes.

The fixed sun and water tint are outside the intent tree. A generated wash can cover the sun, but true semantic ownership of all scene elements is a useful future improvement.

## Run and test

```sh
npm ci
npm run build
npm test
npm start
```

Requires Node 22.15+; first Elm compilation needs network access for packages. Set an approved `OPENAI_API_KEY` in `.env.local` for real generation. Without one, the local UI can be used and server failure handling exercised.

Validation completed before handoff:

- Optimized Elm build and Worker bundling succeeded.
- 22 Elm checks passed: tree integrity, replay, serialization, replacement, unrelated-branch preservation, stale/error handling, and saved-intention redraw behavior.
- 15 server tests passed with mocked model responses: identity/origin checks, input/output validation, missing configuration, structured requests, variation IDs, refusal, incomplete output, and rate limits.
- The original prototype was browser-tested for dragging, reparenting, translation, reload persistence, and replay.

**Not verified:** real OpenAI requests, model quality, the updated redraw UI in a browser, deployed Worker behavior, hosted identity headers on the new route, or successful live redraw after reload. Mocks are not a substitute for these checks.

## Suggested continuation order

1. Resolve/provision a usable API key through an approved flow. Configure it on the local server and as a hosted secret, without exposing it.
2. Run the local server and the user's exact dark-cloudy-sky example. Confirm a visually dark sky with visibly more clouds, meaningful child intentions, and no unintended tower/river changes.
3. Click Redraw twice using the same saved prompt. Confirm each success adds one history entry and old versions replay exactly.
4. Verify pending, failed, stale-response, and edited-draft behavior in the browser. Ensure action labels remain accurate during generation; the pending badge and disabled UI deserve review.
5. Revisit the model token/time limits if detailed trees frequently truncate. Do not silently accept partial output. Review generation size limits versus the cumulative document limit after repeated edits.
6. Verify and package the Worker deployment. The root `.openai/hosting.json` was changed from static hosting to Worker hosting. `npm run build` writes `dist/server/index.js` and `dist/.openai/hosting.json` (generated/ignored). Confirm compatibility with the current Sites deployment helper.
7. Preserve the existing private site's ID and audience. Use Sites source synchronization and publishing tools; the GitHub repository is a handoff copy, not an automatically connected deployment source.
8. After successful private deployment, test as the signed-in owner in the browser. Report actual live results and any remaining limitations.

## Known design constraints

- History is chronological, immutable through the UI, and currently has no branching or undo-edit feature. You can inspect a past state but must return to Latest to edit.
- A regenerated subtree receives new descendant IDs. Historical intent references can therefore point to nodes absent from the latest document. The old nodes are still available by replaying earlier changes.
- Reparenting changes ownership and paint order without adapting coordinates.
- Only the selected subtree changes. Cross-subtree dependencies, such as reflections or contrast adjustments, are not modeled.
- No durable collaborative document store, imported-history interface, cross-tab concurrency control, or generation job queue exists.
- The server has per-request bounds but no persistent per-user rate limiting or spend budget. Review this before changing the site from owner-private to a wider audience.
- HTML, CSS and the browser bridge are source files maintained directly under `dist/`. Only `dist/elm.js` is compiled there; `dist/server/` and `dist/.openai/` are generated. Do not delete all of `dist/` during builds.
- The preview adapter and hosted Worker deliberately differ in authentication. A successful local request does not establish hosted sign-in correctness.

## Documentation references

- Elm architecture: https://guide.elm-lang.org/architecture/
- OpenAI structured outputs: https://developers.openai.com/api/docs/guides/structured-outputs?api-mode=responses
- Model used by default: https://developers.openai.com/api/docs/models/gpt-5-mini
