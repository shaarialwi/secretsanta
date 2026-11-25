# Secret Santa — Strategy Edition

1. Create a fresh Supabase project at https://supabase.com/dashboard.
2. Run `supabase.sql` once in SQL Editor. Enable anonymous sign-ins under Authentication; consider CAPTCHA and rate limits. Never use a service role key in the frontend.
3. Copy the project URL and publishable/anon key into `config.js`.
4. Under GitHub Settings > Pages, deploy from main / (root).
5. Open the Pages URL. Create a room, copy the invitation and share privately. Participants join with a name and wishlist. Keep the same browser/profile to retain the anonymous session; clearing browser data loses access. Moderator may join as a participant too.
6. Test with at least two different browser profiles, then draw, open each gift, send hints, guess and reveal. Do not use actual staff details until this test passes.

Room access uses a randomly generated room code and anonymous Supabase sessions. Server-side functions enforce host actions and private assignments; no direct access to data tables. This MVP polls every 3.5 seconds and does not yet enforce MRANTI Google SSO. Anyone with the room code can register before draw. Mission completion is self-reported. All assignments become visible to joined players at reveal. Delete room data after the event through the Supabase dashboard. No external analytics. Not independently security-audited.
