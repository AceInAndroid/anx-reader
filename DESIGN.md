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
