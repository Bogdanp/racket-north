#lang north

-- @revision: 9bfd76d90c767269b167d5d486665c60
-- @description: Creates the price domain and the orders table.
-- @up {
create domain price integer check(value > 0);
-- }

-- @up {
create table orders(
  id serial primary key,
  email text not null,
  created_at timestamptz not null default current_timestamp
);
-- }

-- @up {
create table order_items(
  id serial primary key,
  order_id integer not null references orders(id),
  sku text not null,
  price price not null,
  quantity integer not null check(quantity > 0)
);
-- }

-- @down {
drop table order_items;
-- }

-- @down {
drop table orders;
-- }

-- @down {
drop domain price;
-- }
