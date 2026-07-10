# Session State Management

- **Continuous Tracking:** You must maintain a running summary of our progress in a file named `CODING_MEMORY.md`.
- **Event-Based Saves:** Update `CODING_MEMORY.md` immediately after completing any major task, resolving a significant bug, or making a structural architectural decision.
- **Pre-Compaction Save:** If the conversation context is growing long, or before you execute any `/compact` commands to clear history, you must update `CODING_MEMORY.md` first to prevent context loss.
- **State File Structure:** Your updates to the state file must concisely include:
  1. A summary of the current session.
  2. Key decisions made and new conventions established.
  3. The exact next steps required.
- **Session Startup:** At the beginning of every new session, silently read `CODING_MEMORY.md` to restore your context before beginning work.
- **Pre-Session Planning Check:** Right before each session begins, if the next task starts in planning mode, pause and ask the user whether to switch models or continue using the current model. Do not begin planning until the user answers.
- **Per-Task Planning Check:** Right before starting any new task during a session, if that task will require planning, brainstorming, or similar ideation, pause and inform the user, then ask whether to switch models or continue using the current model. Do not start that task until the user answers.
- **Pre-Task Implementation Check:** Right after brainstorming/planning is complete and immediately before implementation begins, pause again and ask whether to switch to a lower-tier model for smaller tasks. Do not begin implementation until the user answers.
- **Token-Limit Checkpoint:** When the token limit is close to being reached, pause and ask the user whether to continue using credits now or stop and resume after the token limit refreshes. Do not continue high-token work until the user answers.
