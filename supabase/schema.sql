-- Run the entire script in Supabase SQL Editor.
create extension if not exists pgcrypto;
create table public.rooms (
 id uuid primary key default gen_random_uuid(), code text not null unique,
 phase text not null default 'lobby' check (phase in ('lobby','hint','vote','result')),
 round_no integer not null default 0, game_no integer not null default 0,
 award_points integer not null default 1 check (award_points between 1 and 100),
 category text, keyword text, liar_id uuid, host_id uuid,
 created_at timestamptz not null default now()
);
create table public.members (
 id uuid primary key default gen_random_uuid(), room_id uuid not null references public.rooms(id) on delete cascade,
 user_id uuid not null, nickname text not null,
 role text not null check (role in ('mc','player')),
 score integer not null default 0, joined_at timestamptz not null default now(),
 unique(room_id,user_id), unique(room_id,nickname)
);
create table public.hints (
 id uuid primary key default gen_random_uuid(), room_id uuid not null references public.rooms(id) on delete cascade,
 game_no integer not null, round_no integer not null, member_id uuid not null references public.members(id) on delete cascade,
 content text not null check (char_length(content) between 1 and 160),
 created_at timestamptz not null default now(), unique(room_id,game_no,round_no,member_id)
);
create table public.votes (
 id uuid primary key default gen_random_uuid(), room_id uuid not null references public.rooms(id) on delete cascade,
 game_no integer not null, voter_id uuid not null references public.members(id) on delete cascade,
 target_id uuid not null references public.members(id) on delete cascade,
 unique(room_id,game_no,voter_id)
);
create index on public.members(room_id);
create index on public.hints(room_id,game_no,round_no);
create index on public.votes(room_id,game_no);
-- The client may not read private game tables. All game access is mediated by SECURITY DEFINER RPCs.
alter table public.rooms enable row level security;
alter table public.members enable row level security;
alter table public.hints enable row level security;
alter table public.votes enable row level security;
revoke all on public.rooms,public.members,public.hints,public.votes from anon,authenticated;
revoke all on all sequences in schema public from anon,authenticated;

create or replace function public.my_member(p_code text)
returns public.members language sql security definer set search_path=public as $$
 select m.* from public.members m join public.rooms r on r.id=m.room_id
 where r.code=upper(trim(p_code)) and m.user_id=auth.uid() limit 1
$$;

create or replace function public.create_room(p_nickname text)
returns text language plpgsql security definer set search_path=public as $$
declare v_code text; v_room uuid; v_member uuid; v_attempt integer := 0;
begin
 if auth.uid() is null then raise exception '로그인이 필요합니다'; end if;
 if length(trim(p_nickname)) not between 1 and 20 then raise exception '닉네임은 1~20자입니다'; end if;
 loop
  v_code := upper(substr(encode(gen_random_bytes(5),'hex'),1,6));
  begin insert into rooms(code) values(v_code) returning id into v_room; exit;
  exception when unique_violation then v_attempt:=v_attempt+1; if v_attempt>10 then raise exception '방 생성 실패'; end if; end;
 end loop;
 insert into members(room_id,user_id,nickname,role) values(v_room,auth.uid(),trim(p_nickname),'mc') returning id into v_member;
 update rooms set host_id=v_member where id=v_room;
 return v_code;
end $$;

create or replace function public.join_room(p_code text,p_nickname text,p_role text)
returns void language plpgsql security definer set search_path=public as $$
declare r rooms%rowtype; v_count integer;
begin
 if auth.uid() is null then raise exception '로그인이 필요합니다'; end if;
 if length(trim(p_nickname)) not between 1 and 20 then raise exception '닉네임은 1~20자입니다'; end if;
 if p_role not in ('mc','player') then raise exception '잘못된 역할'; end if;
 select * into r from rooms where code=upper(trim(p_code)) for update;
 if not found then raise exception '방을 찾을 수 없습니다'; end if;
 if exists(select 1 from members where room_id=r.id and user_id=auth.uid()) then return; end if;
 if r.phase <> 'lobby' or r.game_no <> 0 then raise exception '게임이 시작된 방에는 새로 참여할 수 없습니다'; end if;
 select count(*) into v_count from members where room_id=r.id and role=p_role;
 if v_count >= case when p_role='mc' then 2 else 8 end then raise exception '해당 역할 정원이 가득 찼습니다'; end if;
 insert into members(room_id,user_id,nickname,role) values(r.id,auth.uid(),trim(p_nickname),p_role);
end $$;

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
revoke all on function public.my_member(text),public.create_room(text),public.join_room(text,text,text),public.game_state(text),public.game_action(text,text,jsonb) from public;
grant execute on function public.create_room(text),public.join_room(text,text,text),public.game_state(text),public.game_action(text,text,jsonb) to authenticated;
