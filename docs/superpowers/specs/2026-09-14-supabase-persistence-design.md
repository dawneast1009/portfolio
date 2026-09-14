# Supabase Persistence Design

## Goal

Keep portfolio state and uploaded files after free Render restarts, idle shutdowns, and redeploys while keeping public viewing open and requiring the existing login only for edits.

## Decision

Use a private Supabase Storage bucket through its server-side REST API. Store the complete application state as `state.json` and each uploaded file as `files/<file-id>.blob`. This avoids adding a database client or changing the existing repository data model; the current PStore remains the local-development fallback.

Render enables the remote backend with `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, and optional `SUPABASE_BUCKET` (default `portfolio-data`). The service-role key is read only by Ruby server code and is never rendered, exported, or sent to the browser. A private bucket is required.

## Behavior

- On startup, if remote persistence is configured, download `state.json` when present and restore all referenced file objects into the local cache before serving requests.
- On a first empty remote bucket, initialize the normal schema locally; the first state mutation uploads it. Existing local development behavior is unchanged when remote variables are absent.
- After every successful state transaction, upload the new `state.json`. File creation uploads the file object before publishing its metadata; file deletion removes metadata and then best-effort deletes the remote object.
- If a configured remote backend cannot be reached during startup, fail closed with a clear configuration error. A configured production service must not silently fall back to ephemeral local data.
- Public routes remain unauthenticated. `/admin` routes and every mutation continue to require the existing username/password session and CSRF token.

## Limits and operations

The application keeps its existing 10 MiB per-file and 100 MiB total Render preview limits. Supabase Free currently includes 1 GB Storage; each file is below its 50 MB Free upload limit. A Supabase Free project can pause after prolonged inactivity, so the first request after a pause may be slow while data remains durable.

The private bucket must be created once in Supabase. A setup document will provide the bucket name, Render environment variables, and a migration command for an existing local `storage/` directory. No Supabase credentials are committed to GitHub.

## Testing

Use an in-memory fake object client for deterministic tests. Verify state and file restoration across a new repository instance, upload/delete synchronization, startup failure when the remote is unavailable, local fallback without variables, and unchanged public/admin authentication behavior. Run the complete existing suite plus the new persistence tests.
