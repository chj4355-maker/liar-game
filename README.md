# LIAR GAME — Vercel + Supabase

1–8 players + up to 2 MCs. Each game selects one random liar. Non-liars see the keyword; MCs see the keyword and liar. Every player submits one hint per round, with hints revealed together. MCs control rounds and voting. Correct voters gain the MC-adjustable point award, accumulated across games.

## Setup

1. Create a Supabase project at https://supabase.com/dashboard.
2. In **Authentication → Providers → Anonymous**, enable anonymous sign-ins. (This is separate from the email provider.)
3. In **SQL Editor**, run `supabase/schema.sql` in full. Run it once on a new project.
4. Copy `.env.example` to `.env.local` and enter your project URL and **publishable/anon** key (never a service_role key).
5. Run `npm install` and `npm run dev`, then visit `http://localhost:3000`.
6. Push the project to GitHub. In https://vercel.com/new, import the repository, set the two `NEXT_PUBLIC_...` environment variables, and deploy.
7. Send everyone the Vercel URL. One MC creates a room and shares the six-character room code; the second MC and eight players join.

## Rules

- Maximum 8 players and 2 MCs; MC sets a player cap of 2–8 in the lobby; 1 player may start a test game, and only one MC is required.
- MCs set category and keyword for each game; one player is randomly chosen as liar.
- Each player writes one hint per round; all participating players' hints become visible together.
- MCs can continue indefinitely or start voting after all participating players' hints are submitted.
- Each player votes once for another player. In a one-player test there is no valid voting target, so the MC may reveal with zero votes (no points awarded). MC reveals results only after all participating players' votes.
- Each game starts at 1 point per correct vote. Either MC may click **+1점 올리기** during any hint round to increase the award (maximum 100). The increased award carries across rounds within the current game and is granted once to each correct voter when results are revealed. The next game resets the award to 1. Scores remain cumulative across games in the same room.
- MCs don't vote or earn points. A liar can vote but cannot vote for themselves.

## Notes / limitations

- State sync uses ~1.8-second polling, not WebSocket push. This is near-real-time and suitable for small rooms.
- A browser's anonymous account is stored by Supabase in browser local storage. Clearing storage or changing browser/device loses that room membership. No account recovery is provided.
- Room state and scores are stored in Supabase. There is no room deletion UI, cleanup schedule, or admin moderation in this MVP.
- MCs have equal privileges, including ability to reveal liar/keyword and advance rounds. Share the MC role only with trusted people.
- Game hints are hidden from other players until everyone submits; MCs can view the secret but not hints early.
- Anonymous auth should be combined with Supabase rate limits / CAPTCHA before broad public distribution. Consider room expiry, reporting, moderation, and nickname filtering for production.
- Do not enable broad SELECT policies on `rooms` or `members`; the keyword and liar are secret database fields. All reads go through the `game_state` RPC.

## Upgrading an existing Supabase deployment

If you already ran the original `supabase/schema.sql`, **do not run it again**. Instead run `supabase/migrate_points.sql` in Supabase SQL Editor, then deploy the updated Next.js files to Vercel. For a brand-new database, run `supabase/schema.sql` only.

## V3 upgrade for existing V2 deployment
1. In Supabase SQL Editor run **`supabase/migrate_flexible_players.sql`** in full (do not rerun `schema.sql`).
2. Upload the updated frontend files to your GitHub repo and redeploy Vercel. No new environment variables required.
3. In the lobby, either MC can set the player cap (2–8), provided it is not below the number already joined. The cap only changes before the first game starts. Games can start with 1 to the configured cap; existing room scores are retained.
4. With one player, that player is always the liar. No one can vote for themselves; MC reveals after switching to voting, and no score is awarded.

For a new Supabase project use `supabase/schema.sql` only.
