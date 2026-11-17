# LIAR GAME V3.1 — 배포 및 수정 안내

## 이번 수정 사항
- **MC 운영 패널을 오른쪽 스코어보드 하단에 항상 표시**합니다. 대기실에는 참가자 정원(2~8명), 게임 진행 중에는 승점 및 +1점 버튼이 보입니다. +1점은 힌트 라운드에서만 활성화됩니다.
- 화면 우측 상단에 **V3.1 · FLEX + POINTS** 표시를 추가했습니다. 이 표시가 없으면 Vercel이 구버전 파일을 서비스 중인 것입니다.
- V3 SQL에 남아 있던 **8명 고정 투표 시작 검사**를 실제 참가자 수 기준으로 수정했습니다.
- 1명 테스트 시작, MC 자유 라운드 진행, 기존 방의 누적 점수 유지.

## 이미 V2/V3 Supabase와 Vercel을 사용 중인 경우
1. Supabase SQL Editor에서 **`supabase/upgrade_v3_1.sql` 전체**를 실행하세요. `schema.sql`을 다시 실행하지 마세요.
2. ZIP 안의 **`liar-game` 폴더 내부 전체 파일**을 GitHub 저장소 최상위에 업로드하세요. 특히 `app/page.tsx`, `app/style.css`가 교체됐는지 확인하세요. `liar-game/liar-game/app` 형태로 중첩 업로드하면 Vercel이 이전 코드를 빌드할 수 있습니다.
3. GitHub에서 Commit 후 Vercel → Deployments에서 **최신 커밋의 Production 배포**가 Ready인지 확인하세요. 배포된 사이트 오른쪽 상단에 `V3.1 · FLEX + POINTS`가 보여야 합니다.
4. Ctrl+Shift+R로 새로고침하고 새 방을 생성해 MC 패널을 확인하세요.

## 신규 Supabase 프로젝트인 경우
`supabase/schema.sql`만 실행합니다. 기존 프로젝트에는 사용하지 마세요.

## 게임 규칙
- MC 최대 2명, 참가자 정원은 2~8명 선택 가능, 테스트 시작은 참가자 1명부터 가능
- 한 게임에 라이어 1명, 일반 참가자에게만 키워드 공개
- 힌트 라운드에서 MC가 승점 +1, 다음 라운드 또는 투표 시작을 자유롭게 결정
- 1인 테스트는 투표 없이 정답 공개, 승점 0점
- 누적 승점은 **동일한 방**에서만 유지, 새 방은 새로운 스코어보드

## 오류 진단
- V3.1 표시 없음: 구버전 배포 또는 GitHub 업로드 경로 오류
- V3.1 표시 있으나 `player_limit` 누락 오류: `upgrade_v3_1.sql` 미적용
- 버튼은 있으나 클릭 시 오류: Supabase SQL Editor 실행 결과와 브라우저 Network → `game_action` Response 확인

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
