-- 駱駝教師生涯導航｜Supabase schema v3
-- 修正重點：positions.id 是 UUID，因此不再把 'admin'、'mentor' 等文字塞入 UUID 欄位。
-- positions.code 才存放穩定的文字代碼。可在全新 Supabase 專案執行。
-- 若已建立舊版同名資料表，請先備份並依 README 的遷移說明處理，IF NOT EXISTS 不會改變既有欄位型別。

create extension if not exists pgcrypto;

create table if not exists public.positions (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null unique,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

insert into public.positions(code,name) values
 ('admin','行政'),('mentor','導師'),('subject_teacher','科任教師')
on conflict (code) do update set name=excluded.name;

create table if not exists public.users (
 id uuid primary key references auth.users(id) on delete cascade,
 email text, display_name text, is_active boolean not null default true,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.user_roles (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.users(id) on delete cascade,
 role text not null check(role in ('teacher','admin')),
 created_at timestamptz not null default now(), unique(user_id,role)
);
create table if not exists public.teacher_profiles (
 user_id uuid primary key references public.users(id) on delete cascade,
 current_position_id uuid references public.positions(id),
 salary_grade_code text, years_of_service numeric(4,1), profile_note text,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.competency_models (
 id uuid primary key default gen_random_uuid(),
 position_id uuid not null references public.positions(id),
 name text not null, description text,
 created_by uuid references public.users(id) on delete set null,
 created_at timestamptz not null default now()
);
create table if not exists public.competencies (
 id uuid primary key default gen_random_uuid(), code text unique,
 name text not null, definition text not null default '',
 is_active boolean not null default true,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.competency_versions (
 id uuid primary key default gen_random_uuid(),
 model_id uuid not null references public.competency_models(id) on delete cascade,
 version_number integer not null check(version_number>0),
 status text not null default 'draft' check(status in ('draft','published','archived')),
 published_at timestamptz, created_by uuid references public.users(id) on delete set null,
 created_at timestamptz not null default now(), unique(model_id,version_number)
);
create unique index if not exists competency_versions_one_published_per_model
 on public.competency_versions(model_id) where status='published';
create table if not exists public.model_competencies (
 id uuid primary key default gen_random_uuid(),
 version_id uuid not null references public.competency_versions(id) on delete cascade,
 competency_id uuid not null references public.competencies(id),
 target_level integer not null default 4 check(target_level between 1 and 5),
 weight numeric(6,3) not null default 1 check(weight>0),
 is_applicable boolean not null default true, sort_order integer not null default 0,
 unique(version_id,competency_id)
);
create table if not exists public.competency_indicators (
 id uuid primary key default gen_random_uuid(),
 competency_id uuid not null references public.competencies(id) on delete cascade,
 level integer not null check(level between 1 and 5), description text not null,
 created_at timestamptz not null default now(), unique(competency_id,level)
);
create table if not exists public.assessment_rule_versions (
 id uuid primary key default gen_random_uuid(), version_number integer not null unique check(version_number>0),
 status text not null default 'draft' check(status in ('draft','published','archived')),
 scoring_method text not null default 'weighted_average',
 gap_method text not null default 'max_zero_target_minus_score',
 max_action_cards integer not null default 3 check(max_action_cards between 1 and 10),
 rule_config jsonb not null default '{}'::jsonb, published_at timestamptz,
 created_at timestamptz not null default now()
);
create table if not exists public.development_plans (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.users(id) on delete cascade,
 mode text not null check(mode in ('current_review','target_development','combined')),
 current_position_id uuid references public.positions(id), target_position_id uuid references public.positions(id),
 reason text, status text not null default 'active' check(status in ('active','completed','archived')),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.assessments (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.users(id) on delete cascade,
 plan_id uuid references public.development_plans(id) on delete set null,
 position_id uuid not null references public.positions(id),
 competency_version_id uuid references public.competency_versions(id) on delete restrict,
 rule_version_id uuid references public.assessment_rule_versions(id) on delete restrict,
 status text not null default 'in_progress' check(status in ('in_progress','submitted','cancelled')),
 overall_score numeric(5,2), note text, started_at timestamptz not null default now(), submitted_at timestamptz
);
create table if not exists public.assessment_responses (
 id uuid primary key default gen_random_uuid(),
 assessment_id uuid not null references public.assessments(id) on delete cascade,
 competency_id uuid not null references public.competencies(id) on delete restrict,
 score integer not null check(score between 1 and 5), response_note text,
 created_at timestamptz not null default now(), unique(assessment_id,competency_id)
);
create table if not exists public.competency_results (
 id uuid primary key default gen_random_uuid(),
 assessment_id uuid not null references public.assessments(id) on delete cascade,
 competency_id uuid not null references public.competencies(id) on delete restrict,
 score numeric(5,2) not null check(score between 1 and 5),
 target_level integer not null check(target_level between 1 and 5),
 gap numeric(5,2) not null check(gap>=0), weight numeric(6,3) not null default 1 check(weight>0),
 priority_rank integer, created_at timestamptz not null default now(), unique(assessment_id,competency_id)
);
create table if not exists public.action_templates (
 id uuid primary key default gen_random_uuid(), competency_id uuid references public.competencies(id) on delete set null,
 title text not null, description text not null default '',
 suggested_duration_weeks integer not null default 1 check(suggested_duration_weeks>0),
 is_active boolean not null default true, created_at timestamptz not null default now()
);
create table if not exists public.plan_action_cards (
 id uuid primary key default gen_random_uuid(),
 plan_id uuid not null references public.development_plans(id) on delete cascade,
 assessment_id uuid references public.assessments(id) on delete set null,
 competency_id uuid references public.competencies(id) on delete set null,
 action_template_id uuid references public.action_templates(id) on delete set null,
 title text not null, description text not null default '', priority_rank integer not null default 1,
 status text not null default 'active' check(status in ('active','completed','paused')),
 created_at timestamptz not null default now()
);
create table if not exists public.weekly_tasks (
 id uuid primary key default gen_random_uuid(),
 plan_id uuid not null references public.development_plans(id) on delete cascade,
 action_card_id uuid references public.plan_action_cards(id) on delete set null,
 week_start date not null, title text not null, description text not null default '',
 status text not null default 'not_started' check(status in ('not_started','in_progress','completed','skipped')),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.weekly_task_logs (
 id uuid primary key default gen_random_uuid(),
 task_id uuid not null references public.weekly_tasks(id) on delete cascade,
 user_id uuid not null references public.users(id) on delete cascade,
 status text not null check(status in ('not_started','in_progress','completed','skipped')),
 note text, logged_at timestamptz not null default now()
);
create table if not exists public.weekly_reviews (
 id uuid primary key default gen_random_uuid(),
 plan_id uuid not null references public.development_plans(id) on delete cascade,
 user_id uuid not null references public.users(id) on delete cascade,
 week_start date not null, reflection text, next_week_intention text,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(plan_id,week_start)
);
create table if not exists public.audit_logs (
 id uuid primary key default gen_random_uuid(),
 actor_user_id uuid references public.users(id) on delete set null,
 action text not null, entity_table text not null, entity_id text,
 details jsonb not null default '{}'::jsonb, created_at timestamptz not null default now()
);

create index if not exists assessments_user_id_idx on public.assessments(user_id);
create index if not exists assessments_position_id_idx on public.assessments(position_id);
create index if not exists development_plans_user_id_idx on public.development_plans(user_id);
create index if not exists weekly_tasks_plan_week_idx on public.weekly_tasks(plan_id,week_start);
create index if not exists competency_results_assessment_idx on public.competency_results(assessment_id);

alter table public.users enable row level security;
alter table public.user_roles enable row level security;
alter table public.teacher_profiles enable row level security;
alter table public.development_plans enable row level security;
alter table public.assessments enable row level security;
alter table public.assessment_responses enable row level security;
alter table public.competency_results enable row level security;
alter table public.weekly_tasks enable row level security;
alter table public.weekly_task_logs enable row level security;
alter table public.weekly_reviews enable row level security;
