#lang north

-- @revision: fe716365ac516d89fa2811e5e1f1d60e
-- @parent: d4de4db8881177a07a1c8ede7f91c56f
-- @description: Adds a created_at column to the users table.
-- @up {
alter table users add column created_at timestamp;
-- }
