# Supabase setup

1. Create a Supabase project.
2. Open **SQL Editor**, paste `schema.sql`, and run it.
3. In **Authentication > Providers > Email**, keep email/password enabled.
4. In **Authentication > URL Configuration**, set the site URL to:
   `https://young222-debug.github.io/time-corridor-diary/`
5. Disable public signups. Add users from **Authentication > Users** with **Send invitation** or **Create user**.
6. Copy the project URL and publishable/anon key into `../config.js`.
7. Never place a `service_role` or secret key in this repository.

The frontend remains in local mode while `config.js` contains empty values. Once both values are set, it switches to cloud mode automatically.

Cloud mode syncs text entries, dates, types, moods, tags, photos, and videos. The private `diary-media` bucket accepts JPEG, PNG, WebP, GIF, MP4, MOV, and WebM files. Photos are limited to 10 MB after compression; videos use resumable uploads and are limited to 50 MB on the Supabase Free plan.

Deleted entries are soft-deleted into the recycle bin. The database trigger stores the previous text version at most once every five minutes, plus an extra version whenever an entry enters or leaves the recycle bin. Version rows are read-only to authenticated clients.
