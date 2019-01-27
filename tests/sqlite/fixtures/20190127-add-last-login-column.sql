#lang north

-- @revision: 69b4a4717dadb8fe03d847e5e7eaa035
-- @parent: fe716365ac516d89fa2811e5e1f1d60e
-- @description: Adds a last_login column to the users table.
-- @up {
alter table users add column last_login timestamp;
-- }
