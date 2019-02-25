#lang at-exp racket/base

(require db
         net/url
         racket/contract/base
         racket/format
         racket/match
         "base.rkt"
         "../base.rkt")

(provide
 (contract-out
  [struct sqlite-adapter ([conn connection?])]
  [url->sqlite-adapter (-> url? adapter?)]))

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

   (define (adapter-apply! ad revision script)
     (define conn (sqlite-adapter-conn ad))
     (with-handlers ([exn:fail:sql?
                      (lambda (e)
                        (raise (exn:fail:adapter:migration @~a{failed to apply revision '@revision'}
                                                           (current-continuation-marks) e revision)))])
       (call-with-transaction conn
         (lambda ()
           (log-north-sqlite-adapter-debug "applying revision ~a" revision)
           (and script (query-exec conn script))

           (query-exec conn "delete from north_schema_version")
           (query-exec conn "insert into north_schema_version values ($1)" revision)))))])

(define (url->sqlite-adapter url)
  (define conn
    (if (null? (url-path url))
        (sqlite3-connect #:database 'memory)
        (sqlite3-connect #:database (url->path url)
                         #:mode 'create)))

  (sqlite-adapter conn))
