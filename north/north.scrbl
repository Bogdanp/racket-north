#lang scribble/manual

@(require (for-label north racket/base))

@title{@exec{north}: Database Migrations}
@author[(author+email "Bogdan Popa" "bogdan@defn.io")]


@;; Introduction ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

@section[#:tag "intro"]{Introduction}

@(define racket-uri "https://racket-lang.org")

@exec{north} is a database migration tool written in @link[racket-uri]{Racket}.
It helps you keep your database schema in sync across all your environments.

@subsection{Features}

@itemlist[
  @item{Programming language agnostic.}
  @item{SQL-based DSL for writing schema migrations.}
  @item{PostgreSQL and SQLite support.}
  @item{Migrations are each run inside individual transactions.}
  @item{Migrations have a strict ordering based on revision ids.  Individual migration files can have arbitrary names.}
  @item{All operations perform dry runs by default, resulting in executable SQL that you can send to your DBA for approval.}
]


@;; Installation ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

@section[#:tag "install"]{Installation}

Assing you've already installed Racket, run the following command to
install @exec{north}.

@commandline{$ raco pkg install north}


@;; Tutorial ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

@section[#:tag "tutorial"]{Tutorial}

For the purposes of this tutorial, we're going to export a
@exec{DATABASE_URL} environment variable to be used with each of the
following commands.

@commandline{$ export DATABASE_URL=sqlite:db.sqlite}

This tells @exec{north} to execute operations against an SQLite
database located in the current directory called @filepath{db.sqlite}.
@exec{DATABASE_URL} must have the following format:

@verbatim|{protocol://[username[:password]@]hostname[:port]/database_name}|

Assuming you wanted to use PostgreSQL instead of SQLite, your URL
would look something like this:

@verbatim|{postgres://example@127.0.0.1/example}|

By default, @exec{north} looks for migrations inside @filepath{migrations}
folder in the current directory so you have to create that folder
before moving on.

@commandline{$ mkdir migrations}

Now, let's try creating our first migration:

@commandline{$ raco north create add-users-table}

That should create a new SQL file inside your @filepath{migrations}
folder with the suffix @exec{-add-users-table}.  Open it up in your
favorite text editor and you should see something along these
lines:

@verbatim|{
#lang north

-- @revision: 2f00470a20a53ff3f3b12b79a005070e
-- @description: Creates some table.
-- @up {
create table example();
-- }

-- @down {
drop table example;
-- }
}|

The @hash-lang[] @exec{north} line declares that this is a @exec{north}-style
migration.  These types of files are made up of definitions where each
definition is a line starting with @exec{--} followed by an @exec["@"]
sign and the name of the binding being defined followed by either a
colon or an open bracket.  If the name is followed by a colon then
everything after that colon until the end of the line represents the
string value of that binding.  If the name is followed by a bracket,
then everything between the start of the next line and the next
occurrence of @exec["-- }"] represents the string value of that
binding.

The reason this syntax was chosen is because it is compatible with
standard SQL syntax.  Each @exec{--} line in SQL is just a comment.
This makes it easy to use whatever text editor you prefer to edit
these files since most editors come with some sort of a SQL mode.

This particular migration has a @exec{revision} id of
@racket{2f00470a20a53ff3f3b12b79a005070e}, a @exec{description} and
@exec{up} and @exec{down} scripts.  @exec{up} scripts are run when
applying a migration and @exec{down} scripts are run when rolling back
a migration.  @exec{down} scripts are optional.

Let's change the @exec{up} script so it creates a new table named
@exec{users}:

@verbatim|{
-- @up {
create table users(
  id serial primary key,
  username text not null unique,
  password_hash text not null,

  constraint users_username_is_lowercase check(username = lower(username))
);
-- }
}|

And the @exec{down} script so it drops the table:

@verbatim|{
-- @down {
drop table users;
-- }
}|

If we tell @exec{north} to migrate the database now, it'll spit out a
dry run of the pending migrations:

@commandline{$ raco north migrate}

@margin-note{Note how the dry run output is valid SQL.}

@verbatim|{
-- Current revision: base
-- Target revision: 2f00470a20a53ff3f3b12b79a005070e

-- Applying revision: base

-- Applying revision: 2f00470a20a53ff3f3b12b79a005070e
-- Revision: 2f00470a20a53ff3f3b12b79a005070e
-- Parent: base
-- Path: /Users/bogdan/migrations/20190128-add-users-table.sql
create table users(
  id serial primary key,
  username text not null unique,
  password_hash text not null,

  constraint users_username_is_lowercase check(username = lower(username))
);
}|

As noted, this output represents a dry run.  The database was not
actually modified.  Unless we explicitly pass the @exec{-f} flag to
the @exec{migrate} command, none of the pending changes will be
applied.

Let's force it to migrate the DB:

@commandline{$ raco north migrate -f}

@verbatim|{
Current revision: base
Target revision: 2f00470a20a53ff3f3b12b79a005070e

Applying revision: base

Applying revision: 2f00470a20a53ff3f3b12b79a005070e
}|

If you inspect the schema of your users table now it should look like
this:

@commandline{$ echo ".schema users" | sqlite3 db.sqlite}

@verbatim|{
CREATE TABLE users(
  id serial primary key,
  username text not null unique,
  password_hash text not null,

  constraint users_username_is_lowercase check(username = lower(username))
);
}|

Next, let's add a @exec{last-login} column to the @exec{users} table:

@commandline{$ raco north create add-last-login-column}

The new migration should contain content that looks like this:

@verbatim|{
#lang north

-- @revision: 91dc39c84aa496e5e0fda2d5a947eea3
-- @parent: 2f00470a20a53ff3f3b12b79a005070e
-- @description: Alters some table.
-- @up {
alter table example add column created_at timestamp not null default now();
-- }

-- @down {
alter table example drop column created_at;
-- }
}|

Not much different from the first migration, but note the introduction
of the @exec{parent} binding.  This tells @exec{north} that this
migration follows the first one (its parent).

Let's update its @exec{up} script:

@verbatim|{
-- @up {
alter table users add column last_login timestamp;
-- }
}|

And remove its @exec{down} script since SQLite does not support
dropping columns.

If we call @exec{migrate} now, we'll get the following output:

@verbatim|{
-- Current revision: 2f00470a20a53ff3f3b12b79a005070e
-- Target revision: 91dc39c84aa496e5e0fda2d5a947eea3

-- Applying revision: 91dc39c84aa496e5e0fda2d5a947eea3
-- Revision: 91dc39c84aa496e5e0fda2d5a947eea3
-- Parent: 2f00470a20a53ff3f3b12b79a005070e
-- Path: /Users/bogdan/migrations/20190128-add-last-login-column.sql
alter table users add column last_login timestamp;
}|

Apply that migration:

@commandline{$ raco north migrate -f}

@margin-note{
  Never roll back a production database.  It will almost always result
  in some kind of data loss.  This command is intended for local
  development only.
}

If we wanted to roll back the last migration we could run:

@commandline{$ raco north rollback}

@verbatim|{
-- WARNING: Never roll back a production database!
-- Current revision: 91dc39c84aa496e5e0fda2d5a947eea3
-- Target revision: 2f00470a20a53ff3f3b12b79a005070e

-- Rolling back revision: 91dc39c84aa496e5e0fda2d5a947eea3
-- Revision: 91dc39c84aa496e5e0fda2d5a947eea3
-- Parent: 2f00470a20a53ff3f3b12b79a005070e
-- Path: /Users/bogdan/migrations/20190128-add-last-login-column.sql
-- no content --
}|

Of course, there's not much point in doing that since our last
revision doesn't contain a @exec{down} script.  We can tell
@exec{rollback} which revision it should roll back to and we can even
tell it to roll back all the way back to before the first revision:

@commandline{$ raco north rollback base}

@verbatim|{
-- WARNING: Never roll back a production database!
-- Current revision: 91dc39c84aa496e5e0fda2d5a947eea3
-- Target revision: base

-- Rolling back revision: 91dc39c84aa496e5e0fda2d5a947eea3
-- Revision: 91dc39c84aa496e5e0fda2d5a947eea3
-- Parent: 2f00470a20a53ff3f3b12b79a005070e
-- Path: /Users/bogdan/migrations/20190128-add-last-login-column.sql
-- no content --

-- Rolling back revision: 2f00470a20a53ff3f3b12b79a005070e
-- Revision: 2f00470a20a53ff3f3b12b79a005070e
-- Parent: base
-- Path: /Users/bogdan/migrations/20190128-add-users-table.sql
drop table users;

-- Rolling back revision: base
}|

If we force a full rollback then all our changes to the database will
be dropped.

@commandline{$ raco north rollback -f base}

@verbatim|{
WARNING: Never roll back a production database!
Current revision: 91dc39c84aa496e5e0fda2d5a947eea3
Target revision: base

Rolling back revision: 91dc39c84aa496e5e0fda2d5a947eea3

Rolling back revision: 2f00470a20a53ff3f3b12b79a005070e

Rolling back revision: base
}|

And that's pretty much it.  There are a couple other commands, but you
can find out about them by running

@commandline{$ raco north help}
