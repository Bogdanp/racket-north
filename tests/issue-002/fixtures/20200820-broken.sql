#lang north

-- @revision: 96b942239e196e0ff5c555ea78b26a64
-- @description: One of the @ups fails
-- @up {
create table test();
-- }

-- @up {
drop table idontexist;
-- }
