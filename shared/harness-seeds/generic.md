[Seed #S1] Always read the target file before editing; never assume file contents from memory
[Seed #S2] When an edit fails with "not unique", include more surrounding context in old_string
[Seed #S3] Do not create new files when an existing file can be extended; check with Glob first
[Seed #S4] Run the project's test/build command after multi-file changes to catch integration errors early
[Seed #S5] When a tool call fails, diagnose the root cause before retrying the same approach
[Seed #S6] When the user rejects a change ("doesn't work", "wrong", "revert"), log it with: bash "${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-${AI_SYMBIOTE_ROOT:-$HOME/plugins/ai-symbiote}}}/hooks/scripts/feedback-logger.sh" "<file_path>" "<rejection_reason>" "<what_to_do_differently>"
