#lang north

-- @revision: d4de4db8881177a07a1c8ede7f91c56f
-- @parent: 554a960cad8fe24fa6b4d4da845b026d
-- @description: Adds an updated_at column to the users table.
-- @up {
alter table users add column updated_at timestamp;
-- }

-- @down {
alter table users drop column updated_at;
-- }
