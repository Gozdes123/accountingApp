-- Create accounts table
create table accounts (
  id uuid default uuid_generate_v4() primary key,
  name text not null,
  balance numeric not null default 0,
  type text not null, -- 'Bank', 'Cash', 'Credit', etc.
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);
