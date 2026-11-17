-- Existing deployments: run this in Supabase SQL Editor once. Do not re-run schema.sql.
ALTER TABLE public.rooms ADD COLUMN IF NOT EXISTS award_points integer NOT NULL DEFAULT 1 CHECK (award_points BETWEEN 1 AND 100);

create or replace function public.game_state(p_code text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r rooms%rowtype; me members%rowtype; v_members jsonb; v_hints jsonb; v_votes jsonb; v_word text; v_liar uuid;
begin
 select * into r from rooms where code=upper(trim(p_code));
 if not found then raise exception '방이 없습니다'; end if;
 select * into me from members where room_id=r.id and user_id=auth.uid();
 if not found then raise exception '참여자가 아닙니다'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'nickname',nickname,'role',role,'score',score) order by joined_at),'[]'::jsonb) into v_members from members where room_id=r.id;
 select coalesce(jsonb_agg(jsonb_build_object('id',h.id,'round',h.round_no,'member_id',h.member_id,'content',h.content) order by h.round_no,h.created_at),'[]'::jsonb) into v_hints from hints h where h.room_id=r.id and h.game_no=r.game_no and (h.round_no<r.round_no or r.phase in ('vote','result') or (select count(*) from hints x where x.room_id=r.id and x.game_no=r.game_no and x.round_no=r.round_no)=8);
 select coalesce(jsonb_agg(jsonb_build_object('voter_id',voter_id,'target_id',target_id)),'[]'::jsonb) into v_votes from votes where room_id=r.id and game_no=r.game_no and (r.phase='result' or voter_id=me.id);
 v_word := case when me.role='mc' or (r.phase='result') or (me.id<>r.liar_id and r.phase<>'lobby') then r.keyword else null end;
 v_liar := case when me.role='mc' or r.phase='result' or me.id=r.liar_id then r.liar_id else null end;
 return jsonb_build_object('code',r.code,'phase',r.phase,'round',r.round_no,'game',r.game_no,'award_points',r.award_points,'category',r.category,'keyword',v_word,'liar_id',v_liar,'me_id',me.id,'my_role',me.role,'host_id',r.host_id,'members',v_members,'hints',v_hints,'votes',v_votes,'hint_count',(select count(*) from hints where room_id=r.id and game_no=r.game_no and round_no=r.round_no),'vote_count',(select count(*) from votes where room_id=r.id and game_no=r.game_no));
end $$;

create or replace function public.game_action(p_code text,p_action text,p_payload jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare r rooms%rowtype; me members%rowtype; v_players uuid[]; v_target uuid; v_count integer; v_correct integer; v_keyword text; v_category text;
begin
 select * into r from rooms where code=upper(trim(p_code)) for update;
 if not found then raise exception '방이 없습니다'; end if;
 select * into me from members where room_id=r.id and user_id=auth.uid();
 if not found then raise exception '참여자가 아닙니다'; end if;
 if p_action in ('start','next_round','start_vote','reveal','new_game','add_points') and me.role<>'mc' then raise exception 'MC만 진행할 수 있습니다'; end if;
 if p_action='start' or p_action='new_game' then
  if (p_action='start' and r.phase<>'lobby') or (p_action='new_game' and r.phase<>'result') then raise exception '시작할 수 없는 단계입니다'; end if;
  select array_agg(id order by id) into v_players from members where room_id=r.id and role='player';
  if coalesce(array_length(v_players,1),0)<>8 or (select count(*) from members where room_id=r.id and role='mc')<>2 then raise exception '참가자 8명과 MC 2명이 필요합니다'; end if;
  v_keyword:=trim(coalesce(p_payload->>'keyword','')); v_category:=trim(coalesce(p_payload->>'category',''));
  if length(v_keyword) not between 1 and 50 or length(v_category) not between 1 and 40 then raise exception '카테고리와 키워드를 입력하세요'; end if;
  update rooms set phase='hint',round_no=1,game_no=game_no+1,category=v_category,keyword=v_keyword,liar_id=v_players[1+floor(random()*8)::integer],award_points=1 where id=r.id;
 elsif p_action='add_points' then
  if r.phase<>'hint' then raise exception '힌트 라운드에서만 승점을 올릴 수 있습니다'; end if;
  if r.award_points>=100 then raise exception '최대 승점은 100점입니다'; end if;
  update rooms set award_points=award_points+1 where id=r.id;
 elsif p_action='hint' then
  if me.role<>'player' or r.phase<>'hint' then raise exception '힌트 입력 단계가 아닙니다'; end if;
  insert into hints(room_id,game_no,round_no,member_id,content) values(r.id,r.game_no,r.round_no,me.id,trim(coalesce(p_payload->>'content','')));
 elsif p_action='next_round' then
  if r.phase<>'hint' then raise exception '힌트 단계가 아닙니다'; end if;
  select count(*) into v_count from hints where room_id=r.id and game_no=r.game_no and round_no=r.round_no;
  if v_count<>8 then raise exception '8명의 힌트가 모두 제출되어야 합니다'; end if;
  update rooms set round_no=round_no+1 where id=r.id;
 elsif p_action='start_vote' then
  if r.phase<>'hint' then raise exception '투표를 시작할 수 없습니다'; end if;
  select count(*) into v_count from hints where room_id=r.id and game_no=r.game_no and round_no=r.round_no;
  if v_count<>8 then raise exception '모든 힌트 제출 후 투표할 수 있습니다'; end if;
  update rooms set phase='vote' where id=r.id;
 elsif p_action='vote' then
  if me.role<>'player' or r.phase<>'vote' then raise exception '투표 단계가 아닙니다'; end if;
  v_target:=(p_payload->>'target_id')::uuid;
  if v_target=me.id or not exists(select 1 from members where id=v_target and room_id=r.id and role='player') then raise exception '본인 또는 참가자가 아닌 사람에게 투표할 수 없습니다'; end if;
  insert into votes(room_id,game_no,voter_id,target_id) values(r.id,r.game_no,me.id,v_target);
 elsif p_action='reveal' then
  if r.phase<>'vote' then raise exception '투표 단계가 아닙니다'; end if;
  select count(*) into v_count from votes where room_id=r.id and game_no=r.game_no;
  if v_count<>8 then raise exception '8명의 투표가 필요합니다'; end if;
  update members set score=score+r.award_points where id in (select voter_id from votes where room_id=r.id and game_no=r.game_no and target_id=r.liar_id);
  update rooms set phase='result' where id=r.id;
 else raise exception '알 수 없는 동작'; end if;
end $$;
