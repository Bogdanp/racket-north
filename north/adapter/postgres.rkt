#lang at-exp racket/base

(require db
         net/url
         racket/contract/base
         racket/format
         racket/match
         "base.rkt")

(provide
 (contract-out
  [struct postgres-adapter ([conn connection?])]
  [url->postgres-adapter (-> url? adapter?)]))

(define CREATE-SCHEMA-TABLE #<<EOQ
create table if not exists north_schema_version(
  current_revision text not null
);
EOQ
)

(struct postgres-adapter (conn)
  #:methods gen:adapter
  [(define (adapter-init ad)
     (define conn (postgres-adapter-conn ad))
     (call-with-transaction conn
       (lambda ()
         (log-north-adapter-debug "creating schema table")
         (query-exec conn CREATE-SCHEMA-TABLE))))

   (define (adapter-current-revision ad)
     (define conn (postgres-adapter-conn ad))
     (query-maybe-value conn "select current_revision from north_schema_version"))

   (define (adapter-apply! ad revision script)
     (define conn (postgres-adapter-conn ad))
     (with-handlers ([exn:fail:sql?
                      (lambda (e)
                        (raise (exn:fail:adapter:migration @~a{failed to apply revision '@revision'}
                                                           (current-continuation-marks) e revision)))])
       (call-with-transaction conn
         (lambda ()
           (log-north-adapter-debug "applying revision ~a" revision)
           (and script (query-exec conn script))

           (query-exec conn "delete from north_schema_version")
           (query-exec conn "insert into north_schema_version values ($1)" revision)))))])

(define (url->postgres-adapter url)
  (define database (substring (path->string (url->path url)) 1))
  (match-define (list _ username password)
    (regexp-match #px"([^:]+)(?::(.+))?" (or (url-user url) "root")))

  (postgres-adapter
   (postgresql-connect #:database database
                       #:server (url-host url)
                       #:port (url-port url)
                       #:user username
                       #:password password)))
