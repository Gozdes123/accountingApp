-- Create expenses table
create table expenses (
  id uuid default uuid_generate_v4() primary key,
  title text not null,
  amount numeric not null,
  category text not null,
  date date not null,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Create favorites table (for Quick Add)
create table favorites (
  id uuid default uuid_generate_v4() primary key,
  title text not null,
  amount numeric not null,
  category text not null,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Create subscriptions table
create table subscriptions (
  id uuid default uuid_generate_v4() primary key,
  name text not null,
  cost numeric not null,
  billing_cycle text not null, -- 'monthly' or 'yearly'
  next_payment_date date,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Create investments table
create table investments (
  id uuid default uuid_generate_v4() primary key,
  symbol text not null, -- e.g. TSLA, BTC
  type text not null, -- 'Stock' or 'Crypto'
  quantity numeric not null,
  average_cost numeric,
  current_price numeric, -- To be updated manually or via API later
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);
