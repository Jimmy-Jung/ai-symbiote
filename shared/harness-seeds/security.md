[Seed #SEC-S1] Never hardcode API keys, tokens, or passwords in source code; use environment variables or a secret manager
[Seed #SEC-S2] Always add .env files to .gitignore before the first commit; never commit .env with real values
[Seed #SEC-S3] Use parameterized queries for SQL; never concatenate user input into query strings
[Seed #SEC-S4] Sanitize user input before rendering in HTML; avoid innerHTML and dangerouslySetInnerHTML with untrusted data
[Seed #SEC-S5] Disable debug mode (DEBUG=true, verbose logging) before deploying to production
[Seed #SEC-S6] Bind development servers to 127.0.0.1, not 0.0.0.0, to prevent external access to sensitive ports
