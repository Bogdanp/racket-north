#lang scribble/manual

@(require (for-label db
                     north
                     north/migrate
                     racket/base
                     racket/contract/base))

@title{@tt{north}: Database Migrations}
@author[(author+email "Bogdan Popa" "bogdan@defn.io")]
@defmodule[north]

@;; Introduction ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

@section[#:tag "intro"]{Introduction}

@(define racket-link (link "https://racket-lang.org" "Racket"))

@tt{north} is a database migration tool written in @|racket-link|.

@subsection{Features}

@itemlist[
  @item{Programming language agnostic.}
  @item{SQL-based DSL for writing schema migrations.}
  @item{PostgreSQL and SQLite support.}
  @item{Migrations are each run inside individual transactions.}
  @item{
    Migrations have a strict ordering based on revision ids.
    Individual migration files can have arbitrary names, which can be
    changed at any point.
  }
  @item{
    All operations perform dry runs by default, resulting in
    executable SQL that you can send to your DBA for approval.
  }
]


@;; Installation ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

@section[#:tag "install"]{Installation}

Assuming you've already installed Racket, run the following command to
install @tt{north}.

@commandline{$ raco pkg install north}


@;; Tutorial ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

@section[#:tag "tutorial"]{Tutorial}

For the purposes of this tutorial, we're going to export a
@tt{DATABASE_URL} environment variable that will be implictly used by
each of the commands that follow:

@commandline{$ export DATABASE_URL=sqlite:db.sqlite}

This tells @tt{north} to execute operations against an SQLite database
located in the current working directory called "db.sqlite".  To use
PostgreSQL instead of SQLite, you can provide a @tech{database URL}
that looks like this instead:

@verbatim["postgres://example@127.0.0.1/example"]

By default, @tt{north} looks for migrations inside a folder called
"migrations" in the current working directory, so you have to create
that folder before moving on:

@commandline{$ mkdir migrations}

Let's try creating our first migration:

@commandline{$ raco north create add-users-table}

Running the above command will create a new SQL file inside your
"migrations" folder with the suffix @tt{-add-users-table}.  Open it up
in your favorite text editor and you should see something along these
lines:

@margin-note{
  The @tt{revision} number in your migration will be different to
  what's shown here.
}

@codeblock|{
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

The @hash-lang[] @tt{north} line declares that this is a @tt{north}
migration.  These types of files are made up of definitions where each
definition is a line starting with @exec["--"] followed by an @tt["@"]
sign and the name of the binding being defined followed by either a
colon or an open bracket.  If the name is followed by a colon then
everything after that colon until the end of the line represents the
string value of that binding.  If the name is followed by an open
bracket, then everything between the start of the next line and the
next occurrence of @exec["-- }"] represents the string value of that
binding.

The reason this syntax was chosen is because it is compatible with
standard SQL syntax.  Each @exec["--"] line is just a comment in SQL.
This makes it easy to use whatever text editor you prefer to edit
these files since most editors come with some sort of a SQL mode.

This particular migration has a @tt{revision} id of
@racket{2f00470a20a53ff3f3b12b79a005070e}, a @tt{description} and
@tt{up} and @tt{down} scripts.  The @tt{up} scripts are run when
applying a migration and the @tt{down} scripts are run when rolling
back a migration.  The @tt{down} scripts are optional.

Change the @tt{up} script so it creates a new table named @tt{users}:

@codeblock[#:keep-lang-line? #f]|{
#lang north
-- @up {
create table users(
  id serial primary key,
  username text not null unique,
  password_hash text not null,

  constraint users_username_is_lowercase check(username = lower(username))
);
-- }
}|

And the @tt{down} script so it drops the table:

@codeblock[#:keep-lang-line? #f]|{
#lang north
-- @down {
drop table users;
-- }
}|

If we tell @tt{north} to migrate the database now, it'll display the
pending migrations, but will not modify the database:

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
actually modified.  Unless we explicitly pass the @tt{-f} flag to the
@exec{raco north migrate} command, none of the pending changes will be
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

Next, add a @tt{last-login} column to the @tt{users} table:

@commandline{$ raco north create add-last-login-column}

The new migration should contain content that looks like this:

@margin-note{
  The @tt{revision} and @tt{parent} numbers in your migration will be
  different to what's shown here.
}

@codeblock|{
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
of the @tt{parent} binding.  This tells @tt{north} that this
migration follows the previous one (its parent).

Alter its @tt{up} script:

@codeblock[#:keep-lang-line? #f]|{
#lang north
-- @up {
alter table users add column last_login timestamp;
-- }
}|

And remove its @tt{down} script since SQLite does not support
dropping columns.

If we call @tt{migrate} now, we'll get the following output:

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
  in some kind of data loss.  This command is intended for testing &
  local development only.
}

To roll back the last migration we can run:

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
revision doesn't contain a @tt{down} script.  We can tell
@tt{rollback} which revision it should roll back to and we can even
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
can find out about them by running:

@commandline{$ raco north help}


@;; Reference ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

@section[#:tag "reference"]{Reference}
@subsection{Database URLs}

@deftech{Database URLs}, whether provided via the @tt{DATABASE_URL}
environment variable or the @tt{-u} flags to the @exec{raco north
migrate} and @exec{raco north rollback} commands, must follow this
format:

@verbatim|{protocol://[username[:password]@]hostname[:port]/database_name[?sslmode=prefer|require|disable]}|

The @tt{protocol} must be either @tt{sqlite} or @tt{postgres}.

The @tt{sslmode} parameter only applies to PostgreSQL connections.
When not provided, the default is @tt{disable}.  Its values have the
following meanings:

@itemlist[
  @item{@tt{prefer} -- try TLS and fall back to plain text if it's not available,}
  @item{@tt{require} -- fail if a TLS connection cannot be established,}
  @item{@tt{disable} -- don't attempt to use TLS.}
]

@subsection{Programmatic Use}
@defmodule[north/migrate]

@defproc[
  (migrate [conn connection?]
           [path (or/c path? path-string?)]) void?
]{
  Migrates the database using the given @racket[conn] up to @tt{HEAD}
  using the migrations defined at @racket[path].
}
