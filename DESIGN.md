# Anx Reader Product Design Decisions

## Reading Agent Beta — Phase 1

### Intent

Reading Agent is part of the reading environment, not a chat feature placed on
top of it. It maintains local reading state and can carry out bounded reader
actions while preserving the user's attention and control.

### Quiet-first interaction contract

- Reading Agent is opt-in and defaults off.
- Page turns, dwell time, chapter changes, and rereading are local signals.
  They must never directly invoke a cloud model or open modal UI.
- Raw relocation events stay in memory. A location becomes observable Agent
  state only after 750ms of stability and duplicate locations are discarded.
- A chapter transition creates one pending checkpoint after the new location
  remains stable for two seconds. It changes only the status capsule count.
- The capsule is attached to the existing reader controls. It is absent when
  there is no active state and hidden whenever reader controls are hidden.
- The capsule contains only a short goal, progress, and pending count. It has
  no flashing animation, respects the platform's reduced-motion behavior, and
  exposes a complete accessibility label.
- Leaving the reader never asks for confirmation. Durable goal progress is
  saved and restored on the next session.

### Authority and confirmation

- Explicit requests such as “save”, “create”, or “mark” may execute directly
  and must offer immediate undo.
- Agent-initiated ideas are previews only until the user confirms them.
- Navigation is non-persistent and does not require confirmation. It is valid
  only for the mounted book and provides a return-to-previous-location action.
- A reading goal created from natural language is presented as structured
  preview before persistence. Template goals remain available without AI.
- User input, manual navigation, and close actions always take priority over
  Agent work.

### Data truth and memory

- There is at most one active goal per book. Comprehension criteria such as
  “can explain” are completed only by the user; location-based progress may be
  updated automatically.
- Reader Profile stores supported preferences as candidate, confirmed, or
  rejected. Only confirmed values enter Agent context.
- Explicit preferences can become candidates immediately. Behavioral evidence
  needs three distinct reading sessions before surfacing. Rejected candidates
  are suppressed for 90 days.
- Source text, user facts, and model inferences remain distinguishable. An AI
  note stores its text snapshot, CFI, chapter, model, and session provenance.

### Reversibility

- Persistent Reading Agent mutations go through `AgentActionService` and are
  journaled in the same database transaction as their data change.
- Undo is idempotent and available immediately from Snackbar and for 30 days
  in the AI workspace action history. At most 200 action records are retained.
- Undo refuses to overwrite data modified after the action and explains the
  conflict. There is no redo.
- Undoing an AI note removes its formal note and Agent-owned annotation.
  Difficulty undo restores the exact pre-action state.

### Phase boundaries

Phase 1 has no background wakeups, vector database, cross-book knowledge graph,
automatic skill learning, or automatic cloud analysis. It does not enable the
legacy `readingCoach` or its MaterialBanner behavior.

## Reading Agent Beta — Phase 2

### Reading closure

- A stable transition out of a chapter persists one local pending checkpoint.
  It changes only the capsule count; it never starts a model call or opens UI.
- A chapter check begins only after the user opens the Agent panel and presses
  “检查”. The user supplies the mastery level; the model cannot promote its own
  explanation into evidence of mastery.
- An optional one-sentence recall becomes a local knowledge card due the next
  day. Reviews use a deliberately small schedule: “再学习” returns in one day,
  while “记住了” doubles the interval up to 60 days.
- Unresolved difficulties are book-scoped rather than chapter-scoped in the
  queue. They remain visible across chapter and session boundaries and retain
  their original chapter and CFI for navigation.

### Resumable context and Markdown memory

- Starting the next reading session restores the active goal, pending chapter
  checks, unresolved difficulties, due-card count, recent mastery summary,
  confirmed profile, and Markdown memory titles before Agent chat is used.
- Markdown memory is a small, database-backed document format: title, Markdown
  body, optional source references, and timestamps. It is local-first and is
  included in the existing database snapshot sync; it is not a vector store.
- Explicit user requests may save Markdown memory immediately. Agent-initiated
  memory is a confirmation preview. Writes are journaled and undoable under the
  same 30-day conflict-safe rules as other Agent writes.
- Only memory titles enter the automatic world-state prompt. The document body
  is available through the explicit `reading_memory_recall` tool, preventing
  silent growth of prompt context.

### Low-interruption policy

- The policy output is intentionally limited to `none` or `passiveCapsule`.
  It has no authority to invoke a model, show a modal/banner/notification, or
  persist an Agent suggestion.
- The capsule appears only with reader controls, remains dismissible for the
  session, contains counts and short labels only, and never reveals a card
  answer or generated review text.
- All completion checks, card reviews, mastery updates, and memory previews are
  entered from a user click. Manual navigation, selection, and closing the
  reader remain higher priority than the closure workflow.

### Book reading outcomes

- “Book reading outcomes” is the durable review surface for the reading loop.
  It is reachable from book details and from the Reading Agent panel; it does
  not depend on a pending capsule being visible.
- The page answers four questions in order: what is the next action, what was
  read, what is understood, and what remains unresolved. It combines the
  active goal and goal history, pending chapter checks, chapter mastery,
  unresolved difficulties, active knowledge cards, and Markdown memories.
- The overview uses compact local metrics only. It never generates a summary
  or invokes a model merely because the page opens or refreshes.
- Knowledge-card answers stay collapsed until the user expands a card. Review
  actions remain explicit. “Learn again” schedules one day; “Remembered”
  doubles the interval up to 60 days.
- Markdown memory bodies are readable on demand and remain visually secondary
  to their titles. Source references navigate the mounted reader when opened
  during a reading session, otherwise they open the book at that location.
- Empty states teach the smallest complete loop: enable Reading Agent Beta,
  create a goal, finish a chapter check, and return to see the result.
- The page uses existing Material surface, typography, and color roles. On
  narrow screens it is one scrollable column; metric tiles wrap rather than
  forcing horizontal scrolling. All sections remain visible when empty so the
  reader understands what outcomes can be formed.

### Reading Skill registry and progressive loading

- A Reading Skill is a reading method, not a bundle of executable tools. The
  built-in registry contains Socratic concept teaching, argument mapping,
  historical source checking, fiction character tracking, academic critical
  reading, contextual language learning, financial assumption validation,
  chapter closure, exam review, and reading-to-action planning.
- The registry has three context layers. Catalog content is a title and one
  sentence for method selection; summary guidance is the only layer included
  for an ordinary AI turn; full guidance is loaded only after explicit method
  intent, deep analysis, or a user-opened chapter closure. The system never
  places every full method in one prompt, and ordinary reader events do not
  load a method or invoke a model.
- Matching is local and deterministic. A per-book pinned method wins, then an
  explicit task intent, then book metadata and reading mode. Fiction defaults
  to spoiler-safe character tracking, economics to argument or financial
  assumption analysis, and psychology to Socratic concept teaching. Chapter
  closure becomes the primary method only while that workflow is active, with
  at most one domain method included as a summary.
- Method output is not a mastery fact. A method may contribute a checkpoint,
  self-assessed mastery, unresolved difficulty, due knowledge card, Markdown
  memory, or next goal, but persistent writes still use the existing explicit
  request/confirmation and 30-day undo contract.
- Readers see the current method as a compact row in the AI workspace and as
  provenance on Book Reading Outcomes. They can pin one method for the book or
  restore automatic matching without exposing prompts, tools, or orchestration
  terminology.

### In-product help and teaching

- Reading Agent Beta and Reading Skill each have a durable, scrollable teaching
  page. Help is available before enabling the beta from AI Settings and while
  reading from the Agent panel, Skill row, Skill picker, and Book Reading
  Outcomes; it is not a one-time onboarding overlay.
- Both pages lead with a short purpose statement and a four-step quick start,
  then progressively disclose behavior and safeguards. Reading Agent teaching
  explains the closure loop, passive capsule, model-call boundary, write
  permissions, source traceability, undo, and local event handling. Reading
  Skill teaching explains local matching, per-book pinning, explicit intent,
  three prompt-loading layers, closure outputs, and all registered methods.
- The Skill page includes tailored starting points for fiction, economics, and
  psychology. Method descriptions use reader-facing language and never expose
  internal prompts or tool orchestration. The two pages cross-link so users can
  understand that Agent owns the loop while Skill owns the reading method.
- Help pages use the existing Material color and typography roles, a single
  responsive scroll column, semantic headings, minimum touch targets, and
  expandable catalog rows. Opening help never calls a model or changes reading
  state.

### Genre-adaptive reading closure policies

- Reading Agent Runtime, events, permissions, undo, and local persistence are
  shared infrastructure. A separate Closure Policy decides what counts as an
  outcome, whether a chapter checkpoint should surface, what the checkpoint
  asks, and whether mastery or review cards belong in the loop. Reading Skill
  continues to decide how AI reasons; it does not own product intervention.
- Closure selection is local and deterministic. A per-book override wins;
  otherwise psychology mode or metadata selects psychology reflection, fiction
  metadata selects fiction immersion, and remaining books use knowledge
  argument. Readers can inspect and override the result from the Reading Agent
  panel and Book Reading Outcomes.
- Fiction immersion prioritizes narrative flow and spoiler safety. Chapter
  switches may create local, optional review checkpoints but checkpoint-only
  state never surfaces the capsule. Fiction has no mastery score or scheduled
  review-card UI. Its explicit checkpoint captures an optional feeling or open
  question as undoable Markdown memory and uses only information available at
  the current progress.
- Knowledge argument uses claim, evidence, assumption, counterexample, and
  applicability as its checkpoint language and outcome vocabulary. Mastery is
  user-confirmed. A one-day recall card is opt-in rather than an automatic side
  effect of writing a reflection.
- Psychology reflection uses concept clarity instead of generic mastery. It
  distinguishes definition, boundary, example, counterexample, and application;
  personal reflection is always optional, is never treated as a diagnostic
  fact, and can be kept as undoable Markdown memory. Review cards remain opt-in.
- Goal templates, quick AI prompts, pending-checkpoint labels, difficulty and
  memory sections, outcome metrics, next action, and empty-state language all
  come from the active Closure Policy. Switching policy does not delete old
  outcomes; it only changes how the shared records are presented and what new
  interactions create.

### Extensible reading experience modules

- A closure module is identified by a stable, namespaced string such as
  `fiction.immersion`; persisted data must never depend on a Dart enum name.
  The former enum remains only as a compatibility adapter, and legacy values
  are normalized when read rather than copied into new records.
- `BookReadingProfile` is the synchronized per-book source of truth for the
  primary module, content facets, match confidence, match source, and whether
  the reader pinned the choice. The in-memory cache exists only to support
  synchronous UI and prompt lookups. A legacy SharedPreferences choice is
  lazily migrated to this table and removed after a successful database save.
- A module contributes declarations: goal templates, checkpoint behavior,
  mastery choices, outcome sections, quick prompts, capabilities, and reader-
  facing language. It cannot invoke a model, write persistent data, or open
  UI. Reader and outcomes surfaces render registry declarations without
  branching on built-in module ids.
- Registry extensibility is a tested contract. Registering another module with
  a new stable id and existing outcome sources must make its picker entry,
  goal templates, quick prompts, checkpoint vocabulary, and outcome sections
  render without edits to the reading page or outcomes page.

### Source-safe Reading Artifacts

- A Reading Artifact is a versioned module projection with a stable kind,
  structured payload, epistemic status, lifecycle status, source snapshot and
  location, session provenance, and creator. Text facts, user reflections,
  Agent inferences, and externally checked facts remain distinguishable.
- `discoveredProgress` is the enforceable spoiler boundary. Artifact queries
  filter by the current reading progress, and presentation surfaces apply the
  same check again. A future character, relationship, clue, scene, or mystery
  must not appear when the reader navigates to an earlier position.
- User- or Agent-authored Artifact writes require a traceable source, use the
  common Agent action transaction, and are conflict-safe and undoable for 30
  days. A deterministic runtime resume marker is local reader state rather
  than AI-authored content, so it is synchronized but does not create a noisy
  undo action.
- Fiction phase-one projections provide character recall, a suspense ledger,
  and resumable context. They are local-first and never trigger a model from a
  page turn or session start. On the next session, availability is shown only
  in the passive controls-attached capsule; details open after the reader taps.
