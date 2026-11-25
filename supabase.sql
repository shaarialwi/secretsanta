-- Run once in a fresh Supabase project. Enable anonymous sign-ins in Authentication.
create table public.santa_rooms(id uuid primary key default gen_random_uuid(), code text unique not null, host uuid not null, title text not null, budget text not null, phase text not null default 'lobby' check(phase in ('lobby','drawn','revealed')));
create table public.santa_players(room uuid references public.santa_rooms on delete cascade, uid uuid not null, name text not null, wish text not null default '', recipient uuid, clue text not null default '', guess uuid, mission boolean not null default false, primary key(room,uid), unique(room,name));
alter table public.santa_rooms enable row level security;
alter table public.santa_players enable row level security;
revoke all on public.santa_rooms,public.santa_players from anon,authenticated;
create or replace function public.santa_game(action text, payload jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare me uuid := auth.uid(); r public.santa_rooms; p public.santa_players; ids uuid[]; n integer; i integer; c text; result jsonb;
begin
if me is null then raise exception 'Sign in first'; end if;
if action='create' then
 c := upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
 insert into santa_rooms(code,host,title,budget) values(c,me,left(coalesce(nullif(trim(payload->>'title'),''),'Strategy Secret Santa'),100),left(coalesce(payload->>'budget','RM50'),50)) returning * into r;
 return jsonb_build_object('code',r.code);
end if;
select * into r from santa_rooms where code=upper(trim(payload->>'code')) for update;
if not found then raise exception 'Room not found'; end if;
select * into p from santa_players where room=r.id and uid=me;
if action='join' then
 if r.phase<>'lobby' then raise exception 'Registration is closed'; end if;
 if coalesce(length(trim(payload->>'name')),0)=0 then raise exception 'Enter your name'; end if;
 insert into santa_players(room,uid,name,wish) values(r.id,me,left(trim(payload->>'name'),60),left(coalesce(payload->>'wish',''),300)) on conflict(room,uid) do update set name=excluded.name,wish=excluded.wish;
 return jsonb_build_object('code',r.code);
end if;
if me<>r.host and p.uid is null then raise exception 'Join this room first'; end if;
if action='draw' then
 if me<>r.host or r.phase<>'lobby' then raise exception 'Only the host can draw once'; end if;
 select array_agg(uid order by random()) into ids from santa_players where room=r.id;
 n:=coalesce(array_length(ids,1),0); if n<2 then raise exception 'At least two players required'; end if;
 for i in 1..n loop update santa_players set recipient=ids[(i % n)+1] where room=r.id and uid=ids[i]; end loop;
 update santa_rooms set phase='drawn' where id=r.id returning * into r;
elsif action='clue' then
 if p.uid is null or r.phase<>'drawn' then raise exception 'Not available'; end if;
 update santa_players set clue=left(coalesce(payload->>'clue',''),300) where room=r.id and uid=me;
elsif action='guess' then
 if p.uid is null or r.phase<>'drawn' then raise exception 'Not available'; end if;
 if not exists(select 1 from santa_players where room=r.id and uid=(payload->>'guess')::uuid and uid<>me) then raise exception 'Choose another player'; end if;
 update santa_players set guess=(payload->>'guess')::uuid where room=r.id and uid=me;
elsif action='mission' then
 if p.uid is null or r.phase<>'drawn' then raise exception 'Not available'; end if;
 update santa_players set mission=true where room=r.id and uid=me;
elsif action='reveal' then
 if me<>r.host or r.phase<>'drawn' then raise exception 'Only the host can reveal after drawing'; end if;
 update santa_rooms set phase='revealed' where id=r.id returning * into r;
elsif action<>'state' then raise exception 'Unknown action';
end if;
select * into p from santa_players where room=r.id and uid=me;
result:=jsonb_build_object('code',r.code,'title',r.title,'budget',r.budget,'phase',r.phase,'host',me=r.host,'joined',p.uid is not null,
'players',coalesce((select jsonb_agg(jsonb_build_object('id',uid,'name',name) order by name) from santa_players where room=r.id),'[]'::jsonb),
'me',me,'guess',p.guess,'mission',coalesce(p.mission,false),'clue',p.clue,
'recipient',(select jsonb_build_object('name',name,'wish',wish) from santa_players where room=r.id and uid=p.recipient),
'hint',(select clue from santa_players where room=r.id and recipient=me));
if r.phase='revealed' then
result:=result||jsonb_build_object('reveal',coalesce((select jsonb_agg(jsonb_build_object('santa',a.name,'recipient',b.name,'score',(case when a.mission then 10 else 0 end)+(case when a.guess=(select uid from santa_players where room=r.id and recipient=a.uid) then 20 else 0 end)) order by a.name) from santa_players a join santa_players b on b.room=a.room and b.uid=a.recipient where a.room=r.id),'[]'::jsonb));
end if;
return result;
end $$;
revoke all on function public.santa_game(text,jsonb) from public,anon;
grant execute on function public.santa_game(text,jsonb) to authenticated;
