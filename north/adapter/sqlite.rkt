#lang racket/base

(require db
         "base.rkt"
         "../base.rkt")

(provide
 (struct-out sqlite-adapter))

(define CREATE-SCHEMA-TABLE #<<EOQ
create table if not exists north_schema_version(
  current_revision text not null
);
EOQ
)

(define-logger north-sqlite-adapter)

(struct sqlite-adapter (conn)
  #:methods gen:adapter
  [(define (adapter-init ad)
     (define conn (sqlite-adapter-conn ad))
     (call-with-transaction conn
       (lambda ()
         (log-north-sqlite-adapter-debug "creating schema table")
         (query-exec conn CREATE-SCHEMA-TABLE))))

   (define (adapter-current-revision ad)
     (define conn (sqlite-adapter-conn ad))
     (query-maybe-value conn "select current_revision from north_schema_version"))

   (define (adapter-apply! ad migrations script-proc revision-proc)
     (define conn (sqlite-adapter-conn ad))
     (for ([migration migrations])
       (with-handlers ([exn:fail:sql?
                        (lambda (e)
                          (raise (exn:fail:adapter:migration "failed to apply migration" (current-continuation-marks) e migration)))])
         (call-with-transaction conn
           (lambda ()
             (log-north-sqlite-adapter-debug "running migration ~a" (migration-revision migration))

             (define script (script-proc migration))
             (and script (query-exec conn script))

             (query-exec conn "delete from north_schema_version")
             (query-exec conn "insert into north_schema_version values ($1)" (revision-proc migration)))))))])
