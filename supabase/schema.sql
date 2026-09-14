-- Run this once in Supabase SQL Editor.
create table if not exists public.portfolio_state (
  id text primary key check (id = 'singleton'),
  revision bigint not null check (revision >= 1),
  state jsonb not null,
  updated_at timestamptz not null default now()
);

alter table public.portfolio_state enable row level security;
