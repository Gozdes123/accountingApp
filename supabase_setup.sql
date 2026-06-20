-- =========================================================================
-- Supabase Unified Database Setup Script
-- Run this in your Supabase SQL Editor:
-- https://supabase.com/dashboard/project/_/sql
-- =========================================================================

-- Enable UUID extension if not enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. Create accounts table
CREATE TABLE IF NOT EXISTS accounts (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  name text NOT NULL,
  balance numeric NOT NULL DEFAULT 0,
  type text NOT NULL, -- 'Bank', 'Cash', 'E-Wallet', 'OtherLiquid', etc.
  auto_record jsonb,  -- Auto-record config JSON
  custom_group text,  -- Custom grouping name
  created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 2. Create investments table
CREATE TABLE IF NOT EXISTS investments (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  symbol text NOT NULL,           -- e.g. TSLA, BTC
  name text,                      -- e.g. 特斯拉
  type text NOT NULL DEFAULT 'Stock',
  asset_class text DEFAULT 'tw_stock', -- e.g. 'tw_stock', 'us_stock', 'crypto'
  quantity numeric NOT NULL DEFAULT 0,
  average_cost numeric,
  current_price numeric DEFAULT 0,
  buy_price numeric DEFAULT 0,
  buy_date date,
  currency text DEFAULT 'TWD',
  custom_group text,
  funding_account_id text,        -- Linked funding account
  price_updated_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 3. Create net_worth_history table
CREATE TABLE IF NOT EXISTS net_worth_history (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  date date NOT NULL UNIQUE,
  amount numeric NOT NULL,
  created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- =========================================================================
-- Enable Row Level Security (RLS) & Create Public Policies (to bypass auth)
-- =========================================================================

-- Accounts policies
ALTER TABLE accounts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow all public actions on accounts" ON accounts;
CREATE POLICY "Allow all public actions on accounts" ON accounts
  FOR ALL TO public USING (true) WITH CHECK (true);

-- Investments policies
ALTER TABLE investments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow all public actions on investments" ON investments;
CREATE POLICY "Allow all public actions on investments" ON investments
  FOR ALL TO public USING (true) WITH CHECK (true);

-- Net Worth History policies
ALTER TABLE net_worth_history ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow all public actions on net_worth_history" ON net_worth_history;
CREATE POLICY "Allow all public actions on net_worth_history" ON net_worth_history
  FOR ALL TO public USING (true) WITH CHECK (true);
