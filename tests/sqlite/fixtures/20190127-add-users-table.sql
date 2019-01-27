#lang north

-- @revision: 554a960cad8fe24fa6b4d4da845b026d
-- @description: Creates the users table.
-- @up {
create table users(
  id serial primary key,
  username text not null unique,
  password_hash text not null,

  constraint users_username_is_lowercase check(username = lower(username))
);
-- }

-- @down {
drop table users;
-- }
