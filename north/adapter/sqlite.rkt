#lang at-exp racket/base

(require db
         net/url
         racket/contract/base
         racket/format
         "base.rkt")

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

(struct sqlite-adapter (conn)
  #:methods gen:adapter
  [(define (adapter-init ad)
     (define conn (sqlite-adapter-conn ad))
     (call-with-transaction conn
       (lambda ()
         (log-north-adapter-debug "creating schema table")
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
           (log-north-adapter-debug "applying revision ~a" revision)
           (and script (query-exec conn script))

           (query-exec conn "delete from north_schema_version")
           (query-exec conn "insert into north_schema_version values ($1)" revision)))))])

(define (url->sqlite-adapter url)
  (sqlite-adapter
   (sqlite3-connect #:database (make-db-path url)
                    #:mode 'create)))

(define (make-db-path url)
  (define parts
    (for*/list ([part (in-list (url-path url))]
                [param (in-value (path/param-path part))])
      (if (string=? param "")
          "/"
          param)))

  (when (or (null? parts)
            (equal? parts '("")))
    (error 'url->sqlite-adapter "sqlite3 connection URL must contain a path"))

  (when (and (url-host url)
             (not (string=? (url-host url) "")))
    (error 'url->sqlite-adapter "sqlite3 connection URL must either start with 0 or 3 slashes"))

  (apply build-path parts))

(module+ test
  (require rackunit)

  (define make
    (compose1 path->string make-db-path string->url))

  (for ([(s e) (in-hash (hash  "sqlite:db.sqlite3"       "db.sqlite3"
                               "sqlite:///db.sqlite3"    "db.sqlite3"
                               "sqlite:///a/db.sqlite3"  "a/db.sqlite3"
                               "sqlite:////a/db.sqlite3" "/a/db.sqlite3"))])
    (check-equal? (make s) e))

  (for ([s (in-list (list "sqlite://"
                          "sqlite://a/"
                          "sqlite://a/db.sqlite3"))])
    (check-exn
     exn:fail?
     (lambda ()
       (make s)))))
