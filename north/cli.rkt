#lang at-exp racket/base

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
         "adapter/base.rkt"
         "adapter/postgres.rkt"
         "adapter/sqlite.rkt"
         "base.rkt")

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
       (exit-with-errors! @~a{error: migrations path '@p' does not exist}))

     p)))

(define adapter-factories
  (hasheq 'postgres url->postgres-adapter
          'sqlite   url->sqlite-adapter))

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
  (define revision (exn:fail:adapter:migration-revision e))
  (define info (exn:fail:sql-info (exn:fail:adapter-cause e)))
  (apply exit-with-errors!
         @~a{error: failed to apply revision @revision}
         @~a{details:}
         (for/list ([i info])
           @~a{  @(car i): @(cdr i)})))

(define (read-migrations)
  (with-handlers ([exn:fail:migration?
                   (lambda (e)
                     (exit-with-errors! @~a{error: @(exn-message e)}))]

                  [exn:fail:read?
                   (lambda (e)
                     (exit-with-errors! @~a{error: @(exn-message e)}))]

                  [exn:fail?
                   (lambda (_)
                     (exit-with-errors! @~a{error: '@(migrations-path)' folder not found}))])
    (path->migration (migrations-path))))

(define (call-with-migrator proc)
  (define revision
    (command-line
     #:program (current-program-name)
     #:once-each
     [("-f" "--force")
      "Unless specified, none of the operations will be applied."
      (dry-run? #f)]
     [("-u" "--database-url")
      URL
      "The URL with which to connect to the database."
      (database-url URL)]
     [("-p" "--path")
      PATH
      "The path to the migrations folder."
      (migrations-path PATH)]
     #:args ([REVISION #f])
     REVISION))

  (unless (database-url)
    (exit-with-errors! "error: no database url"))

  (define base (read-migrations))
  (unless base
    (exit-with-errors! "error: no migrations"))

  (define adapter (make-adapter (database-url)))
  (unless adapter
    (exit-with-errors! "error: no adapter"))

  (define ok? #f)
  (dynamic-wind
    (lambda ()
      (adapter-lock! adapter))
    (lambda ()
      (adapter-init adapter)
      (proc adapter base (adapter-current-revision adapter) revision)
      (set! ok? #t))
    (lambda ()
      (with-handlers ([exn:fail?
                       (lambda (e)
                         (if ok?
                             (raise e)
                             ((error-display-handler)
                              (format "call-with-migrator: ~a" (exn-message e))
                              e)))])
        (adapter-unlock! adapter)))))

(define (display-message message)
  (if (and (dry-run?) (not (string=? message "")))
      (displayln (~a "-- " message))
      (displayln message)))

(define (display-dry-run migration script-proc)
  (unless (string=? (migration-revision migration) "base")
    (define scripts (script-proc migration))
    (display-message @~a{Revision: @(migration-revision migration)})
    (display-message @~a{Parent: @(migration-parent migration)})
    (display-message @~a{Path: @(migration-path migration)})
    (cond
      [(null? scripts) (displayln "-- no content --")]
      [else (for-each displayln scripts)])))

(define (display-migration migration)
  (unless (string=? (migration-revision migration) "base")
    (display-message @~a{Revision: @(migration-revision migration)})
    (display-message @~a{Parent: @(migration-parent migration)})
    (display-message @~a{Path: @(migration-path migration)})
    (display-message @~a{Description: @(migration-description migration)})
    (display-message "")))

(define (handle-help)
  (exit-with-errors!
   "usage: raco north <command> <option> ... <arg> ..."
   ""
   "available commands:"
   "  create        create a new revision"
   "  help          print this message and exit"
   "  migrate       migrate to a particular revision"
   "  rollback      roll back to a previous revision"
   "  show          print information about each revision"))

(define (handle-migrate)
  (call-with-migrator
   (lambda (adapter base current-revision input-revision)
     (define target-revision
       (or input-revision (migration-revision (migration-most-recent base))))

     (display-message @~a{Current revision: @(or current-revision "base")})
     (display-message @~a{Target revision: @target-revision})
     (when (equal? current-revision target-revision)
       (exit 0))

     (define plan
       (migration-plan base current-revision target-revision))

     (with-handlers ([exn:fail:adapter:migration? exit-with-adapter-error!])
       (for ([migration plan])
         (display-message "")
         (display-message @~a{Applying revision: @(migration-revision migration)})
         (if (dry-run?)
             (display-dry-run migration migration-up)
             (adapter-apply! adapter (migration-revision migration) (migration-up migration))))))))

(define (handle-rollback)
  (call-with-migrator
   (lambda (adapter base current-revision input-revision)
     (define target-migration
       (if input-revision
           (migration-find-revision base input-revision)
           (migration-find-parent base (or current-revision "base"))))

     (unless target-migration
       (exit-with-errors! @~a{error: invalid revision '@input-revision'}))

     (define target-revision
       (match (migration-revision target-migration)
         ["base" #f]
         [rev rev]))

     (display-message @~a{WARNING: Never roll back a production database!})
     (display-message @~a{Current revision: @(or current-revision "base")})
     (display-message @~a{Target revision: @(or target-revision "base")})
     (when (equal? current-revision target-revision)
       (exit-with-errors! "error: nothing to do"))

     (define plan
       (migration-plan base current-revision target-revision))

     (with-handlers ([exn:fail:adapter:migration? exit-with-adapter-error!])
       (for ([migration plan])
         (display-message "")
         (display-message @~a{Rolling back revision: @(migration-revision migration)})
         (if (dry-run?)
             (display-dry-run migration migration-down)
             (adapter-apply! adapter (migration-parent migration) (migration-down migration))))))))

(define (handle-create)
  (define name
    (command-line
     #:program (current-program-name)
     #:once-each
     [("-p" "--path") path
                      "The path to the migrations folder."
                      (migrations-path path)]

     #:args (name) name))

  (define revision (generate-revision-id name))
  (define filename (generate-revision-filename name))
  (define content
    (match (read-migrations)
      [#f   (format root-revision-template revision)]
      [base (format child-revision-template revision (migration-revision (migration-most-recent base)))]))

  (with-handlers ([exn:fail:filesystem:exists?
                   (lambda (_e)
                     (exit-with-errors! @~a{error: output file '@filename' already exists}))])
    (void (call-with-output-file filename (curry write-string content)))))

(define (handle-extract)
  (define revision
    (command-line
     #:program (current-program-name)
     #:once-each
     [("-p" "--path")
      PATH
      "The path to the migrations folder."
      (migrations-path PATH)]
     #:args ([revision #f]) revision))
  (parameterize ([dry-run? #f])
    (define base (read-migrations))
    (unless base
      (exit-with-errors! "error: no migration"))
    (cond
      [revision
       (define migration (migration-find-revision base revision))
       (unless migration
         (exit-with-errors! @~a{error: revision '@revision' not found}))
       (for-each displayln (migration-up migration))]
      [else
       (for ([migration (in-list (migration->list base))])
         (for-each displayln (migration-up migration)))])))

(define (handle-show)
  (define revision
    (command-line
     #:program (current-program-name)
     #:once-each
     [("-p" "--path")
      PATH
      "The path to the migrations folder."
      (migrations-path PATH)]
     #:args ([revision #f]) revision))
  (parameterize ([dry-run? #f])
    (define base (read-migrations))
    (unless base
      (exit-with-errors! "error: no migrations"))
    (cond
      [revision
       (define migration (migration-find-revision base revision))
       (unless migration
         (exit-with-errors! @~a{error: revision '@revision' not found}))
       (display-migration migration)]
      [else
       (for-each display-migration (reverse (migration->list base)))])))

(define ((handle-unknown command))
  (exit-with-errors! @~a{error: unrecognized command '@command'}))

(define all-commands
  (hasheq 'create   handle-create
          'extract  handle-extract
          'help     handle-help
          'migrate  handle-migrate
          'rollback handle-rollback
          'show     handle-show))

(define-values (command handler args)
  (match (current-command-line-arguments)
    [(vector command args ...) ;; noqa
     (values command (hash-ref all-commands (string->symbol command) (handle-unknown command)) args)]

    [_
     (values "help" handle-help null)]))

(parameterize ([current-command-line-arguments (list->vector args)]
               [current-program-name (~a (current-program-name) " " command)])
  (with-handlers ([(λ (e)
                     (or (exn:fail:adapter? e)
                         (exn:fail:sql? e)))
                   (λ (e)
                     (eprintf "error: ~a~n" (exn-message e))
                     (exit 1))])
    (handler)))
