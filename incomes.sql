-- Create incomes table
create table incomes (
  id uuid default uuid_generate_v4() primary key,
  title text not null,
  amount numeric not null,
  date date not null,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);
