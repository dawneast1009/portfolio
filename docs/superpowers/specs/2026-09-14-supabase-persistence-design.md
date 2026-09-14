# Supabase Persistence Design

## Goal

Keep portfolio state and uploaded files after free Render restarts, idle shutdowns, and redeploys while keeping public viewing open and requiring the existing login only for edits.

## Decision

Use Supabase Postgres as the authoritative state store through its server-side REST API and a private Supabase Storage bucket for file bytes. Store one JSONB state row with a monotonically increasing revision and each uploaded file as `files/<file-id>.blob`. Conditional revision updates prevent an old Render container from overwriting a newer edit during deployment overlap; the current PStore remains the local-development fallback.

Render enables the remote backend with `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, and optional `SUPABASE_BUCKET` (default `portfolio-data`). The service-role key is read only by Ruby server code and is never rendered, exported, or sent to the browser. A private bucket and the setup SQL table are required.

## Behavior

- On startup, if remote persistence is configured, read the single Postgres state row and restore all referenced file objects into the local cache before serving requests.
- On a first empty remote database, initialize the normal schema locally; the first state mutation inserts revision 1. Existing local development behavior is unchanged when remote variables are absent.
- After every successful state transaction, update the row only when its revision still matches the revision read at startup. A conflict fails the mutation rather than overwriting another container's edit. File creation uploads the file object before publishing its metadata; file deletion removes metadata and then best-effort deletes the remote object.
- If a configured remote backend cannot be reached during startup, fail closed with a clear configuration error. A configured production service must not silently fall back to ephemeral local data.
- Public routes remain unauthenticated. `/admin` routes and every mutation continue to require the existing username/password session and CSRF token.

## Limits and operations

The application keeps its existing 10 MiB per-file and 100 MiB total Render preview limits. Supabase Free currently includes 500 MB database size and 1 GB Storage; each file is below its 50 MB Free upload limit. A Supabase Free project can pause after prolonged inactivity, so the first request after a pause may be slow while data remains durable.

The private bucket and `portfolio_state` table must be created once in Supabase. A setup document will provide the SQL, bucket name, Render environment variables, and a migration command for an existing local `storage/` directory. No Supabase credentials are committed to GitHub.

## Testing

Use an in-memory fake object client for deterministic tests. Verify state and file restoration across a new repository instance, upload/delete synchronization, startup failure when the remote is unavailable, local fallback without variables, and unchanged public/admin authentication behavior. Run the complete existing suite plus the new persistence tests.
