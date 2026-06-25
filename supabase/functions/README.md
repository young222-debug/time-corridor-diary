# Edge Functions

## invite-user

This function sends Supabase Auth invitation emails from the app.

Before it can work:

1. Run `supabase/schema.sql` in Supabase SQL Editor.
2. Insert the owner's user id into `public.app_admins`.
3. Deploy `invite-user` as a Supabase Edge Function.
4. Add `SUPABASE_SERVICE_ROLE_KEY` as a function secret in Supabase.

Do not place the service role key in GitHub, `index.html`, or `config.js`.
