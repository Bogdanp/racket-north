#lang racket/base

(require db
         racket/contract/base
         racket/lazy-require
         racket/match
         "adapter/base.rkt"
         "base.rkt")

(lazy-require
 ["adapter/postgres.rkt" (postgres-adapter)]
 ["adapter/sqlite.rkt" (sqlite-adapter)])

(provide
 (contract-out
  [migrate (-> connection? (or/c path? path-string?) void?)]))

(define (migrate conn path)
  (define base (path->migration path))
  (define adapter
    (match (dbsystem-name (connection-dbsystem conn))
      ['sqlite3 (sqlite-adapter conn)]
      ['postgresql (postgres-adapter conn)]
      [name (error 'migrate "dbsystem not supported: ~a" name)]))
  (adapter-init adapter)
  (define current (adapter-current-revision adapter))
  (define target (migration-revision (migration-most-recent base)))
  (for ([migration (in-list (migration-plan base current target))])
    (adapter-apply! adapter (migration-revision migration) (migration-up migration))))
