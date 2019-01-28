#lang racket/base

(require db
         gregor
         net/url
         openssl/md5
         racket/cmdline
         racket/format
         racket/function
         racket/match
         racket/port
         raco/command-name
         "base.rkt"
         "adapter/base.rkt"
         "adapter/postgres.rkt"
         "adapter/sqlite.rkt")

(define current-program-name
  (make-parameter (short-program+command-name)))

(define database-url
  (make-parameter (getenv "DATABASE_URL")))

(define dry-run?
  (make-parameter #t))

(define migrations-path
  (make-parameter
   (build-path (current-directory) "migrations")
   (lambda (p)
     (unless (directory-exists? p)
       (exit-with-errors! (format "error: migrations path '~a' does not exist" p)))

     p)))

(define (make-postgres-adapter url)
  (define database (substring (path->string (url->path url)) 1))
  (match-define (list _ username password)
    (regexp-match #px"([^:]+)(?::(.+))?" (or (url-user url) "root")))

  (postgres-adapter
   (postgresql-connect #:database database
                       #:server (url-host url)
                       #:port (url-port url)
                       #:user username
                       #:password password)))

(define (make-sqlite-adapter url)
  (define conn
    (if (null? (url-path url))
        (sqlite3-connect #:database 'memory)
        (sqlite3-connect #:database (url->path url)
                         #:mode 'create)))

  (sqlite-adapter conn))

(define adapter-factories
  (hasheq 'postgres make-postgres-adapter
          'sqlite make-sqlite-adapter))

(define (make-adapter dsn)
  (define url (string->url dsn))
  (define factory (hash-ref adapter-factories (string->symbol (url-scheme url)) #f))
  (and factory (factory url)))

(define root-revision-template #<<EOT
#lang north

-- @revision: ~a
-- @description: Creates some table.
-- @up {
create table example();
-- }

-- @down {
drop table example;
-- }
EOT
  )

(define child-revision-template #<<EOT
#lang north

-- @revision: ~a
-- @parent: ~a
-- @description: Alters some table.
-- @up {
alter table example add column created_at timestamp not null default now();
-- }

-- @down {
alter table example drop column created_at;
-- }
EOT
  )

(define (current-date->string)
  (~t (today) "yyyyMMdd"))

(define (generate-revision-id name)
  (call-with-input-string (~a (datetime->iso8601 (now)) name) md5))

(define (generate-revision-filename name)
  (build-path (migrations-path) (~a (current-date->string) "-" name ".sql")))

(define (exit-with-errors! . messages)
  (parameterize ([current-output-port (current-error-port)])
    (for ([message messages])
      (displayln message)))
  (exit 1))

(define (exit-with-adapter-error! e)
  (define migration (exn:fail:adapter:migration-migration e))
  (define info (exn:fail:sql-info (exn:fail:adapter-cause e)))
  (apply exit-with-errors!
   (format "error: failed to apply revision ~a" (migration-revision migration))
   (format "details:")
   (for/list ([i info])
     (format "  ~a: ~a" (car i) (cdr i)))))

(define (parse-migrator-args command)
  (define revision
    (command-line
     #:program (current-program-name)
     #:once-each
     [("-f" "--force") "Unless specified, none of the operations will be applied."
                       (dry-run? #f)]

     [("-u" "--database-url") url
                              "The URL with which to connect to the database."
                              (database-url url)]

     [("-m" "--migrations-path") path
                                 "The path to the migrations folder."
                                 (migrations-path path)]

     #:args ([revision #f]) revision))

  (unless (database-url)
    (exit-with-errors! "error: no database url"))

  (define root
    (with-handlers ([exn:fail:migration?
                     (lambda (e)
                       (exit-with-errors! (format "error: ~a" (exn-message e))))])
      (path->migration (migrations-path))))

  (unless root
    (exit-with-errors! "error: no migrations"))

  (define adapter (make-adapter (database-url)))
  (unless adapter
    (exit-with-errors! "error: no adapter"))

  (adapter-init adapter)
  (values adapter root (adapter-current-revision adapter) revision))

(define (print-dry-run migration script-proc)
  (unless (string=? (migration-revision migration) "base")
    (displayln "")
    (displayln (format "-- Revision: ~a" (migration-revision migration)))
    (displayln (format "-- Parent: ~a" (or (migration-parent migration) "base")))
    (displayln (format "-- Path: ~a" (migration-path migration)))
    (displayln (or (script-proc migration) "-- no content --"))))

(define (handle-help)
  (exit-with-errors!
   "usage: raco north <command> <option> ... <arg> ..."
   ""
   "available commands:"
   "  create        create a new revision"
   "  help          print this message and exit"
   "  migrate       migrate to a particular revision"
   "  rollback      roll back to a previous revision"))

(define (handle-migrate)
  (define-values (adapter root current-revision input-revision)
    (parse-migrator-args "migrate"))

  (define target-revision
    (or input-revision (migration-revision (migration-most-recent root))))

  (displayln (format "-- Current revision: ~a" (or current-revision "base")))
  (displayln (format "-- Target revision: ~a" target-revision))
  (when (equal? current-revision target-revision)
    (exit-with-errors! "error: nothing to do"))

  (define plan
    (migration-plan root current-revision target-revision))

  (with-handlers ([exn:fail:adapter:migration? exit-with-adapter-error!])
    (cond
      [(dry-run?) (for-each (curryr print-dry-run migration-up) plan)]
      [else (adapter-apply! adapter plan migration-up migration-revision)])))

(define (handle-rollback)
  (define-values (adapter root current-revision input-revision)
    (parse-migrator-args "rollback"))

  (define target-migration
    (if input-revision
        (migration-find-revision root input-revision)
        (migration-find-parent root (or current-revision "base"))))

  (unless target-migration
    (exit-with-errors! (format "error: invalid revision '~a'" input-revision)))

  (define target-revision
    (match (migration-revision target-migration)
      ["base" #f]
      [rev rev]))

  (displayln (format "-- Current revision: ~a" (or current-revision "base")))
  (displayln (format "-- Target revision: ~a" (or target-revision "base")))
  (when (equal? current-revision target-revision)
    (exit-with-errors! "error: nothing to do"))

  (define plan
    (migration-plan root current-revision target-revision))

  (with-handlers ([exn:fail:adapter:migration? exit-with-adapter-error!])
    (cond
      [(dry-run?) (for-each (curryr print-dry-run migration-down) plan)]
      [else (adapter-apply! adapter plan migration-down migration-parent)])))

(define (handle-create)
  (define name
    (command-line
     #:program (current-program-name)
     #:once-each
     [("-m" "--migrations-path") path
                                 "The path to the migrations folder."
                                 (migrations-path path)]

     #:args (name) name))

  (define revision (generate-revision-id name))
  (define filename (generate-revision-filename name))
  (define content
    (match (path->migration (migrations-path))
      [#f   (format root-revision-template revision)]
      [root (format child-revision-template revision (migration-revision (migration-most-recent root)))]))

  (with-handlers ([exn:fail:filesystem:exists?
                   (lambda _
                     (exit-with-errors! (format "error: output file '~a' already exists" filename)))])
    (void (call-with-output-file filename (curry write-string content)))))

(define ((handle-unknown command))
  (exit-with-errors! (format "error: unrecognized command ~a" command)))

(define all-commands
  (hasheq 'create   handle-create
          'help     handle-help
          'migrate  handle-migrate
          'rollback handle-rollback))

(define-values (command handler args)
  (match (current-command-line-arguments)
    [(vector command args ...)
     (values command (hash-ref all-commands (string->symbol command) (handle-unknown command)) args)]

    [_
     (values "help" handle-help null)]))

(parameterize ([current-command-line-arguments (list->vector args)]
               [current-program-name (~a (current-program-name) " " command)])
  (handler))
