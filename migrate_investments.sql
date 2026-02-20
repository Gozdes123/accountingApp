-- Migration: Add buy_price and buy_date columns to investments table
-- Run this in your Supabase SQL Editor

-- 新增 buy_price 欄位（每筆買入時的股價）
ALTER TABLE investments
  ADD COLUMN IF NOT EXISTS buy_price numeric;

-- 新增 buy_date 欄位（買入日期）
ALTER TABLE investments
  ADD COLUMN IF NOT EXISTS buy_date date;

-- 新增 name 欄位（股票名稱，如尚未有的話）
ALTER TABLE investments
  ADD COLUMN IF NOT EXISTS name text;

-- 新增 asset_class 欄位（如尚未有的話）
ALTER TABLE investments
  ADD COLUMN IF NOT EXISTS asset_class text default 'tw_stock';

-- 新增 currency 欄位（如尚未有的話）
ALTER TABLE investments
  ADD COLUMN IF NOT EXISTS currency text default 'TWD';

-- 新增 price_updated_at 欄位（如尚未有的話）
ALTER TABLE investments
  ADD COLUMN IF NOT EXISTS price_updated_at timestamp with time zone;

-- 把舊資料的 average_cost 複製到 buy_price（相容舊資料）
UPDATE investments
SET buy_price = average_cost
WHERE buy_price IS NULL AND average_cost IS NOT NULL;

-- 把舊資料的 created_at 日期複製到 buy_date（相容舊資料）
UPDATE investments
SET buy_date = DATE(created_at)
WHERE buy_date IS NULL;
