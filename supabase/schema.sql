-- =====================================================================
-- Le Hub — schéma Supabase (v3 : badges, certifications, quêtes)
-- Toutes les tables commencent par hub_ : elles peuvent vivre dans le
-- MÊME projet Supabase que le dashboard Protect sans rien toucher.
-- À coller dans Supabase > SQL Editor > New query, puis "Run".
-- Le script peut être relancé sans danger.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------

-- Profils : un par compte Discord connecté (créé automatiquement)
create table if not exists public.hub_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  discord_id text unique,
  name text not null default 'Membre',
  avatar_url text,
  kind text not null default 'Staff / talent',      -- Staff / talent, Fondateur, Les deux
  skills text[] not null default '{}',
  bio text,
  dispo text,
  paid text default 'Bénévole',
  portfolio text,
  status text not null default 'incomplet'
    check (status in ('incomplet','en_attente','valide','refuse','suspendu')),
  refusal_reason text,
  has_link boolean generated always as
    (coalesce(bio,'') ~* '(https?://|www\.|discord\.gg|discord\.com/invite)') stored,
  verified boolean not null default false,         -- badge Talent Vérifié
  plan text not null default 'Gratuit',            -- Gratuit, Fondateur+, Fondateur Pro, Talent+, Talent Vérifié
  is_admin boolean not null default false,         -- accès au panneau admin du site
  notified_staff boolean not null default false,   -- le bot a posté la demande dans le salon de vérification
  staff_message_id text,                           -- message du bot dans le salon de vérification
  notified_user boolean not null default true,     -- false = le bot doit prévenir la personne de la décision
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Colonnes des badges (ajoutées même si la table existait déjà)
alter table public.hub_profiles add column if not exists certs text[] not null default '{}';   -- dev_bot, dev_site, graphiste, staff
alter table public.hub_profiles add column if not exists quests text[] not null default '{}';  -- quêtes Staff certifié validées
alter table public.hub_profiles add column if not exists team boolean not null default false;  -- Team Hub (synchronisé par le bot depuis le rôle staff)

-- Fiches serveurs : créées uniquement par la fonction claim-server
-- (qui vérifie auprès de Discord que la personne gère bien le serveur)
create table if not exists public.hub_servers (
  id bigint generated always as identity primary key,
  guild_id text unique not null,
  owner_id uuid not null references public.hub_profiles(id) on delete cascade,
  name text not null,
  icon text,
  description text,
  cat text,
  invite_url text,
  members int not null default 0,
  online int not null default 0,
  owner_verified boolean not null default false,   -- true = propriétaire, false = gestionnaire
  protect boolean not null default false,          -- mis à jour par le bot Protect
  pro boolean not null default false,              -- badge PRO (donné par le staff)
  month boolean not null default false,            -- Serveur du mois
  status text not null default 'en_attente'
    check (status in ('en_attente','valide','refuse','suspendu')),
  refusal_reason text,
  has_link boolean generated always as
    (coalesce(description,'') ~* '(https?://|www\.|discord\.gg|discord\.com/invite)') stored,
  notified_staff boolean not null default false,
  staff_message_id text,
  notified_user boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Annonces de recrutement (publiées dans le forum Discord par le bot)
create table if not exists public.hub_listings (
  id bigint generated always as identity primary key,
  owner_id uuid not null references public.hub_profiles(id) on delete cascade,
  server_id bigint not null references public.hub_servers(id) on delete cascade,
  role text not null,
  title text not null,
  description text,
  paid boolean not null default false,
  boosted boolean not null default false,
  boosted_until timestamptz,
  discord_message_id text,
  created_at timestamptz not null default now()
);

-- Candidatures
create table if not exists public.hub_applications (
  id bigint generated always as identity primary key,
  listing_id bigint not null references public.hub_listings(id) on delete cascade,
  user_id uuid not null references public.hub_profiles(id) on delete cascade,
  message text,
  status text not null default 'en attente',
  notified boolean not null default false,
  created_at timestamptz not null default now()
);

-- Avis dans les deux sens
create table if not exists public.hub_reviews (
  id bigint generated always as identity primary key,
  author_id uuid not null references public.hub_profiles(id) on delete cascade,
  target_id uuid not null references public.hub_profiles(id) on delete cascade,
  rating int not null check (rating between 1 and 5),
  comment text,
  created_at timestamptz not null default now(),
  unique (author_id, target_id)
);

-- Commandes du Studio
create table if not exists public.hub_orders (
  id bigint generated always as identity primary key,
  user_id uuid references public.hub_profiles(id) on delete set null,
  service text, theme text, colors text, size text, details text,
  status text not null default 'nouvelle',        -- nouvelle, en_cours, livree (livree = badge Client Studio)
  notified boolean not null default false,
  created_at timestamptz not null default now()
);

-- Badges personnalisés créés par le staff
create table if not exists public.hub_badges (
  id bigint generated always as identity primary key,
  label text unique not null,
  emoji text not null default '★',
  color text not null default '#5962FE' check (color ~ '^#[0-9A-Fa-f]{6}$'),
  created_at timestamptz not null default now()
);

-- Qui a quel badge (un serveur ou un profil)
create table if not exists public.hub_badge_links (
  badge_id bigint not null references public.hub_badges(id) on delete cascade,
  target_type text not null check (target_type in ('server','profile')),
  target_id text not null,
  primary key (badge_id, target_type, target_id)
);

insert into public.hub_badges (label, emoji, color) values
  ('Créé par le Studio', '◆', '#3ECF8E'),
  ('Partenaire', '★', '#F5B942'),
  ('Recrute activement', '⚑', '#5962FE')
on conflict (label) do nothing;

-- ---------------------------------------------------------------------
-- 2. Fonctions utiles
-- ---------------------------------------------------------------------

create or replace function public.hub_is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select is_admin from public.hub_profiles where id = auth.uid()), false);
$$;

-- "De confiance" = le bot / les fonctions (clé service_role), l'éditeur SQL, ou un admin du site
create or replace function public.hub_is_trusted() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(auth.role(), 'service_role') = 'service_role' or public.hub_is_admin();
$$;

-- Création automatique du profil à la première connexion Discord
create or replace function public.hub_handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.hub_profiles (id, discord_id, name, avatar_url)
  values (
    new.id,
    new.raw_user_meta_data->>'provider_id',
    coalesce(new.raw_user_meta_data->'custom_claims'->>'global_name',
             new.raw_user_meta_data->>'full_name',
             new.raw_user_meta_data->>'name', 'Membre'),
    new.raw_user_meta_data->>'avatar_url')
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists hub_on_auth_user_created on auth.users;
create trigger hub_on_auth_user_created
  after insert on auth.users
  for each row execute function public.hub_handle_new_user();

-- Comptes qui existaient déjà (ex. utilisateurs du dashboard Protect)
insert into public.hub_profiles (id, discord_id, name, avatar_url)
select u.id,
       u.raw_user_meta_data->>'provider_id',
       coalesce(u.raw_user_meta_data->'custom_claims'->>'global_name',
                u.raw_user_meta_data->>'full_name',
                u.raw_user_meta_data->>'name', 'Membre'),
       u.raw_user_meta_data->>'avatar_url'
from auth.users u
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- 3. Protections : un membre ne peut pas se donner un badge, un plan,
--    ni valider lui-même sa fiche. Toute modification du contenu
--    renvoie la fiche ou le profil en vérification.
-- ---------------------------------------------------------------------

create or replace function public.hub_guard_profiles() returns trigger
language plpgsql set search_path = public as $$
begin
  if public.hub_is_trusted() then
    -- une décision du staff (site ou Discord) : le bot prévient la personne
    if new.status is distinct from old.status and new.status in ('valide','refuse','suspendu') then
      new.notified_user := false;
    end if;
    new.updated_at := now(); return new;
  end if;
  new.id := old.id; new.discord_id := old.discord_id; new.avatar_url := old.avatar_url;
  new.verified := old.verified; new.plan := old.plan; new.is_admin := old.is_admin;
  new.status := old.status; new.refusal_reason := old.refusal_reason;
  new.notified_staff := old.notified_staff; new.staff_message_id := old.staff_message_id; new.notified_user := old.notified_user;
  new.certs := old.certs; new.quests := old.quests; new.team := old.team;
  if (new.name, new.kind, new.skills, new.bio, new.dispo, new.paid, new.portfolio)
     is distinct from
     (old.name, old.kind, old.skills, old.bio, old.dispo, old.paid, old.portfolio) then
    new.status := 'en_attente'; new.notified_staff := false; new.refusal_reason := null;
  end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists hub_guard_profiles on public.hub_profiles;
create trigger hub_guard_profiles before update on public.hub_profiles
  for each row execute function public.hub_guard_profiles();

create or replace function public.hub_guard_servers() returns trigger
language plpgsql set search_path = public as $$
begin
  if public.hub_is_trusted() then
    -- une décision du staff (site ou Discord) : le bot prévient la personne
    if new.status is distinct from old.status and new.status in ('valide','refuse','suspendu') then
      new.notified_user := false;
    end if;
    new.updated_at := now(); return new;
  end if;
  new.guild_id := old.guild_id; new.owner_id := old.owner_id; new.name := old.name; new.icon := old.icon;
  new.members := old.members; new.online := old.online; new.owner_verified := old.owner_verified;
  new.protect := old.protect; new.pro := old.pro; new.month := old.month;
  new.status := old.status; new.refusal_reason := old.refusal_reason;
  new.notified_staff := old.notified_staff; new.staff_message_id := old.staff_message_id; new.notified_user := old.notified_user;
  if (new.description, new.cat, new.invite_url)
     is distinct from (old.description, old.cat, old.invite_url) then
    new.status := 'en_attente'; new.notified_staff := false; new.refusal_reason := null;
  end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists hub_guard_servers on public.hub_servers;
create trigger hub_guard_servers before update on public.hub_servers
  for each row execute function public.hub_guard_servers();

create or replace function public.hub_guard_listings() returns trigger
language plpgsql set search_path = public as $$
begin
  if public.hub_is_trusted() then return new; end if;
  if tg_op = 'INSERT' then
    new.boosted := false; new.boosted_until := null; new.discord_message_id := null;
  else
    new.owner_id := old.owner_id; new.server_id := old.server_id;
    new.boosted := old.boosted; new.boosted_until := old.boosted_until;
    new.discord_message_id := old.discord_message_id;
  end if;
  return new;
end $$;
drop trigger if exists hub_guard_listings on public.hub_listings;
create trigger hub_guard_listings before insert or update on public.hub_listings
  for each row execute function public.hub_guard_listings();

-- ---------------------------------------------------------------------
-- 4. Vue publique des talents (seulement les profils validés)
-- ---------------------------------------------------------------------
create or replace view public.hub_talents as
select p.id, p.name, p.avatar_url, p.skills, p.bio as exp, p.paid, p.dispo,
       p.verified, p.portfolio, p.created_at,
       coalesce(round(avg(r.rating)::numeric, 1), 0) as rating,
       count(r.id) as reviews
from public.hub_profiles p
left join public.hub_reviews r on r.target_id = p.id
where p.status = 'valide' and p.kind <> 'Fondateur'
group by p.id;
grant select on public.hub_talents to anon, authenticated;

-- Badges de chaque membre (lue par le site et par le bot)
--   fondateur_certifie : propriétaire d'un serveur dont la fiche est validée
--   client_studio      : au moins une commande Studio livrée
create or replace view public.hub_profile_badges as
select p.id, p.discord_id, p.plan, p.verified, p.certs, p.quests, p.team,
       exists (select 1 from public.hub_servers s
               where s.owner_id = p.id and s.status = 'valide' and s.owner_verified) as fondateur_certifie,
       exists (select 1 from public.hub_orders o
               where o.user_id = p.id and o.status = 'livree') as client_studio
from public.hub_profiles p;
grant select on public.hub_profile_badges to anon, authenticated;

-- ---------------------------------------------------------------------
-- 5. Sécurité (RLS)
-- ---------------------------------------------------------------------
alter table public.hub_profiles     enable row level security;
alter table public.hub_servers      enable row level security;
alter table public.hub_listings     enable row level security;
alter table public.hub_applications enable row level security;
alter table public.hub_reviews      enable row level security;
alter table public.hub_orders       enable row level security;
alter table public.hub_badges       enable row level security;
alter table public.hub_badge_links  enable row level security;

do $$ declare p record; begin
  for p in select policyname, tablename from pg_policies
           where schemaname = 'public' and tablename like 'hub\_%' loop
    execute format('drop policy %I on public.%I', p.policyname, p.tablename);
  end loop;
end $$;

-- Profils
create policy "profils visibles" on public.hub_profiles for select
  using (status = 'valide' or id = auth.uid() or public.hub_is_admin());
create policy "modifier son profil" on public.hub_profiles for update
  using (id = auth.uid() or public.hub_is_admin());
create policy "supprimer son profil" on public.hub_profiles for delete
  using (id = auth.uid() or public.hub_is_admin());

-- Serveurs (pas d'insert ici : c'est la fonction claim-server qui crée les fiches)
create policy "serveurs visibles" on public.hub_servers for select
  using (status = 'valide' or owner_id = auth.uid() or public.hub_is_admin());
create policy "modifier sa fiche" on public.hub_servers for update
  using (owner_id = auth.uid() or public.hub_is_admin());
create policy "supprimer sa fiche" on public.hub_servers for delete
  using (owner_id = auth.uid() or public.hub_is_admin());

-- Annonces : il faut une fiche serveur validée pour publier
create policy "annonces visibles" on public.hub_listings for select using (true);
create policy "publier une annonce" on public.hub_listings for insert
  with check (owner_id = auth.uid() and exists (
    select 1 from public.hub_servers s
    where s.id = server_id and s.owner_id = auth.uid() and s.status = 'valide'));
create policy "modifier son annonce" on public.hub_listings for update
  using (owner_id = auth.uid() or public.hub_is_admin());
create policy "supprimer son annonce" on public.hub_listings for delete
  using (owner_id = auth.uid() or public.hub_is_admin());

-- Candidatures
create policy "postuler" on public.hub_applications for insert
  with check (user_id = auth.uid());
create policy "voir les candidatures" on public.hub_applications for select
  using (user_id = auth.uid() or public.hub_is_admin() or exists (
    select 1 from public.hub_listings l where l.id = listing_id and l.owner_id = auth.uid()));

-- Avis
create policy "avis visibles" on public.hub_reviews for select using (true);
create policy "laisser un avis" on public.hub_reviews for insert
  with check (author_id = auth.uid() and author_id <> target_id);

-- Commandes du Studio
create policy "commander" on public.hub_orders for insert with check (user_id = auth.uid());
create policy "voir ses commandes" on public.hub_orders for select
  using (user_id = auth.uid() or public.hub_is_admin());
create policy "gérer les commandes" on public.hub_orders for update using (public.hub_is_admin());

-- Badges : lecture pour tous, gestion réservée aux admins
create policy "badges visibles" on public.hub_badges for select using (true);
create policy "gérer les badges" on public.hub_badges for all
  using (public.hub_is_admin()) with check (public.hub_is_admin());
create policy "attributions visibles" on public.hub_badge_links for select using (true);
create policy "attribuer les badges" on public.hub_badge_links for all
  using (public.hub_is_admin()) with check (public.hub_is_admin());

-- ---------------------------------------------------------------------
-- 6. Te donner l'accès admin (à lancer APRÈS ta première connexion au site)
--    Remplace par ton identifiant Discord (Discord > Paramètres > Avancés >
--    Mode développeur, puis clic droit sur ton pseudo > Copier l'identifiant)
-- ---------------------------------------------------------------------
-- update public.hub_profiles set is_admin = true, status = 'valide' where discord_id = 'TON_ID_DISCORD';
