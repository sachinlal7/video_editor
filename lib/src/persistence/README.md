# Persistence

Schema v2 preserves all supported project data. Version 1 migrates explicitly to v2; unknown schemas fail instead of guessing. EditorProjectFile serializes operations per owner, performs JSON work off the UI isolate, caps documents at 16 MiB, and atomically replaces a flushed sibling file. Use one owner per path in an existing durable app-owned directory. Source media and undo history are not embedded. See docs/PHASE_1_VERIFICATION.md for limitations and restart-test commands.
