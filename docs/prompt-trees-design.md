# Prompt trees and intent sourcing

Recorded 2026-10-11 from Michiel's delegated handoff from **“Find intent sourcing discussion”**, source thread `01a11bc7-1e37-71d1-8d45-7076d2acba9c`, to **“Set up intent-studio”**. This note preserves the discussion before the source chat is archived. It is an exploration brief, not a commitment to implement every suggestion.

## Michiel's core proposal: prompt trees

Use a deterministic LLM with a fixed system prompt to take a high-level description of software behaviour and split it into prompts for components. Those components produce prompts for subcomponents. After several layers, leaf prompts produce JavaScript, and that JavaScript is the running software.

An equivalent formulation is JavaScript modules whose main code comments specify enough that the deterministic LLM plus fixed system prompt can generate each module's contents from its main comment. The descriptions of intent are maintained source artifacts; JavaScript is their compiled output.

Explore this deterministic-LLM premise on its own terms. Whether a particular hosted model provides the required determinism is an experimental question, not a reason to silently replace the proposal with a different workflow.

## Related user idea: intent sourcing / commit messages for data

Preserve what someone requested, against which state, and why, together with the resulting outcome. The preceding discussion considered authored data across GitHub, Airtable, Atomic, and ELFA/NextGraph: schemas, signatures, access control, commit history, merges, semantic patches, commit messages, PR and branch descriptions, issues, and assignments.

Prior artifacts supplied with the handoff:

- [ELFA intent-sourcing plan and handoff](https://git.elfaconsortium.eu/ELFA/database-apps/src/branch/docs/intent-sourcing-handoff/docs/intent-sourcing-handoff.md)
- [ELFA pull request 20](https://git.elfaconsortium.eu/ELFA/database-apps/pulls/20)

At the time of that earlier handoff, intent sourcing was a design with no implementation. These links and that historical statement are retained from the supplied handoff; their current contents and repository status were not checked when this note was written. Verify the current repository before relying on that implementation status.

## Tentative assistant suggestions, not settled requirements

1. **Separate decomposition from independent regeneration.** Generating the entire hierarchy and regenerating one module from its specification without reading its old implementation are different capabilities. Deleting and regenerating a module is a useful test of specification completeness.
2. **Make delegated decisions explicit.** A node might specify responsibility, observable behaviour, exported interface, dependency interfaces, constraints, edge cases/examples, and decisions delegated to children. Deterministic generation from a vague prompt can still consistently make unintended decisions.
3. **Generate contracts as well as children.** Parents could produce contracts between children so sibling modules compose. A tree of responsibility may coexist with a dependency graph for shared modules.
4. **Preserve child refinements.** An independently edited child specification adds information absent from its parent. Possible policies include propagating decisions upward, retaining explicit refinements, or treating the subtree as independently authored. Choose and test a policy; ancestor regeneration must not silently erase these refinements.
5. **Distinguish inference determinism from released-build reproducibility.** One engineering option is to record full generation inputs, model/configuration, and outputs; reuse recorded outputs for existing builds; and treat new generations as explicit revisions. Hosted output should not be assumed byte-identical across calls. This option supplements exploration of the user's deterministic premise rather than replacing it.
6. **Connect specification changes to intent history.** Record the changed specification, rationale, regenerated descendants, generated-code changes, and behavioural validation evidence.
7. **Start with a small experiment.** An order calculator with three modules could exercise independent regeneration, a behavioural change with limited propagation, and independently authored acceptance tests that catch plausible but incorrect decomposition.
8. **Measure the central tradeoff.** Can specifications be precise enough for reliable regeneration while remaining easier for humans to understand and change than the generated JavaScript? Evaluate exact-byte reproduction separately from equivalent observable behaviour.

## Relationship to Intent Studio

Intent Studio currently explores a drawing tree: intentions own subtrees of parts and strokes. Its Elm reducers replay chronological changes, and a `Replace` operation records generated geometry so replay does not call the model. The current AI backend generates drawing data, not executable JavaScript. Prompt trees extend this direction into software construction; they are not an already implemented feature.

| Existing drawing concept | Possible software experiment | Question to resolve |
| --- | --- | --- |
| Prompt attached to a drawing node | Maintained component specification or main module comment | Does it contain enough information for independent regeneration? |
| Parts and stroke descendants | Child specifications and generated modules | Which decisions belong to a parent, and which are delegated? |
| Replacing one drawing subtree | Regenerating a module or affected descendants | How do dependency contracts determine propagation outside the tree? |
| Exact geometry stored in `Replace` history | Generated code and generation inputs recorded with the revision | Which records are needed to reproduce a release and explain its provenance? |
| Replay and stale-result protection | Generation against an explicit specification revision | How are concurrent refinements or stale generated modules handled? |

The current **Redraw** action deliberately requests a fresh variation, even for unchanged wording. That behaviour must be distinguished from the proposed deterministic software compilation experiment. Likewise, restoring an old recorded drawing proves replayability, not deterministic model inference.

Replacing a whole subtree in the drawing prototype makes loss of independently authored child refinements a particularly relevant issue. The current prototype also does not model cross-subtree dependencies; software interfaces and shared modules would require explicit exploration. The existing drawing validator does not establish correctness of generated JavaScript.

## Candidate experiment, pending a decision to implement

Keep an order-calculator experiment separate from the drawing application's production path. One possible three-module decomposition is subtotal, discount policy, and order-total composition; this decomposition is a proposal, not a user decision. Author observable acceptance criteria independently before generation, including money representation/rounding, empty orders, and discount eligibility boundaries.

Record the fixed system prompt, root description, child specifications, interface contracts, model identifier and available generation settings, generated outputs, and test evidence. Do not put credentials in these records.

Compare three trials:

1. Generate the hierarchy and modules, then remove one generated implementation and regenerate from its specification and declared interfaces alone. Compare bytes and behavioural results independently.
2. Change one behaviour, predict the affected nodes from their contracts, regenerate, and compare actual propagation with the prediction. Test unchanged behaviours as well as the requested change.
3. Refine a child independently, then regenerate its ancestor. Observe whether the chosen refinement policy preserves the added information and makes any conflict visible.

For each trial, retain failures as evidence alongside successes. Assess specification size and comprehensibility, unstated decisions, test failures, regeneration scope, and the human effort required to make a change. No experiment has been run as part of this documentation handoff.

## Research and model-selection context

[Parsel: “Algorithmic Reasoning with Language Models by Composing Decompositions”](https://arxiv.org/abs/2212.10561) is related primary research supplied in the handoff. It decomposes tasks into hierarchical natural-language function descriptions and searches for implementations using tests. Maintaining that hierarchy over time was an additional question in this discussion. The paper was not independently reviewed for this note.

Michiel asked whether this exploration suits Sol 6.1 or Astra 6.0. The preceding assistant suggested Sol for development and experiments, with Astra providing an additional critique of ambiguous foundational design. This was advice, not a task-specific benchmark or an instruction to change models. No separate agent was started for that discussion or for recording this handoff.

## Continuation guidance

Use these distinctions when proposing future changes: authored intent versus generated artifacts, decomposition versus independent regeneration, exact reproduction versus equivalent behaviour, and refinements versus ancestor-generated defaults. Preserve the core proposal separately from unaccepted engineering options. Keep the existing drawing/deployment work in scope; this research handoff does not require rewriting the editor or implementing a software compiler immediately.
