-- Run in the existing Secret Santa Supabase project, not a new project.
-- Existing rooms, participant records and draw assignments are preserved.
begin;
alter table public.santa_players add column if not exists photo text;
alter table public.santa_rooms add column if not exists moderator_key_hash text;
create or replace function public.santa_game(action text, payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare me uuid:=auth.uid(); r public.santa_rooms; p public.santa_players; ids uuid[]; n int; i int; pic text; secret text;
begin
if me is null then raise exception 'Sign in first'; end if;
if action in ('create','create_registration') then
 secret:=replace(gen_random_uuid()::text,'-','');
 insert into santa_rooms(code,host,title,budget,moderator_key_hash)
 values(upper(substr(replace(gen_random_uuid()::text,'-',''),1,10)),me,left(coalesce(nullif(trim(payload->>'title'),''),'Strategy Secret Santa'),100),left(coalesce(payload->>'budget','RM50'),50),encode(sha256(convert_to(secret,'UTF8')),'hex')) returning * into r;
 return jsonb_build_object('code',r.code,'moderator_key',secret,'registration_only',true);
end if;
select * into r from santa_rooms where code=upper(trim(payload->>'code')) for update;
if not found then raise exception 'Room not found'; end if;
select * into p from santa_players where room=r.id and uid=me;
if action='moderator_login' then
 secret:=trim(coalesce(payload->>'key',''));
 if r.moderator_key_hash is null or length(secret)<>32 or r.moderator_key_hash<>encode(sha256(convert_to(secret,'UTF8')),'hex') then raise exception 'Incorrect moderator access key'; end if;
 update santa_rooms set host=me where id=r.id returning * into r;
elsif action in ('join','register') then
 if r.phase<>'lobby' and p.uid is null then raise exception 'Registration is closed'; end if;
 if coalesce(length(trim(payload->>'name')),0)=0 then raise exception 'Enter your name'; end if;
 if payload ? 'photo' then
  pic:=nullif(payload->>'photo','');
  if pic is not null and (length(pic)>350000 or pic !~ '^data:image/jpeg;base64,[A-Za-z0-9+/=]+$') then raise exception 'Invalid or oversized photo'; end if;
 else pic:=p.photo; end if;
 insert into santa_players(room,uid,name,wish,photo) values(r.id,me,left(trim(payload->>'name'),60),left(coalesce(payload->>'wish',''),300),pic)
 on conflict(room,uid) do update set name=excluded.name,wish=excluded.wish,photo=excluded.photo;
elsif me<>r.host and p.uid is null then raise exception 'Join this room first';
elsif action='draw' then
 if me<>r.host or r.phase<>'lobby' then raise exception 'Only the moderator can draw once'; end if;
 select array_agg(uid order by random()) into ids from santa_players where room=r.id;
 n:=coalesce(array_length(ids,1),0); if n<2 then raise exception 'At least two participants required'; end if;
 for i in 1..n loop update santa_players set recipient=ids[(i%n)+1] where room=r.id and uid=ids[i]; end loop;
 update santa_rooms set phase='drawn' where id=r.id returning * into r;
elsif action<>'state' then raise exception 'This action is no longer available';
end if;
select * into p from santa_players where room=r.id and uid=me;
return jsonb_build_object('code',r.code,'title',r.title,'budget',r.budget,'phase',r.phase,'host',me=r.host,'joined',p.uid is not null,'registration_only',true,
'own',case when p.uid is not null then jsonb_build_object('name',p.name,'wish',p.wish,'photo',p.photo) else null end,
'count',(select count(*) from santa_players where room=r.id),
'players',case when me=r.host then coalesce((select jsonb_agg(jsonb_build_object('name',a.name,'wish',a.wish,'photo',a.photo,'recipient',b.name) order by a.name) from santa_players a left join santa_players b on b.room=a.room and b.uid=a.recipient where a.room=r.id),'[]'::jsonb) else '[]'::jsonb end);
end $$;
revoke all on function public.santa_game(text,jsonb) from public,anon;
grant execute on function public.santa_game(text,jsonb) to authenticated;
-- Generate a private moderator key for the existing room once.
-- Copy the key from the SQL result and keep it private. No key is printed on reruns.
commit;
with secret as materialized (select replace(gen_random_uuid()::text,'-','') as k)
update public.santa_rooms r set moderator_key_hash=encode(sha256(convert_to(secret.k,'UTF8')),'hex')
from secret where r.code='61F69DABC8' and r.moderator_key_hash is null
returning r.code as room_code,secret.k as moderator_access_key;
