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
CREATE TABLE IF NOT EXISTS north_schema_version(
  current_revision TEXT NOT NULL
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
     (query-maybe-value conn "SELECT current_revision FROM north_schema_version"))

   (define (adapter-apply! ad revision scripts)
     (define conn (sqlite-adapter-conn ad))
     (with-handlers ([exn:fail:sql?
                      (lambda (e)
                        (raise (exn:fail:adapter:migration @~a{failed to apply revision '@revision'}
                                                           (current-continuation-marks) e revision)))])
       (call-with-transaction conn
         (lambda ()
           (log-north-adapter-debug "applying revision ~a" revision)
           (for ([script (in-list scripts)])
             (query-exec conn script))
           (query-exec conn "DELETE FROM north_schema_version")
           (query-exec conn "INSERT INTO north_schema_version VALUES ($1)" revision)))))])

(define (url->sqlite-adapter url)
  (sqlite-adapter
   (sqlite3-connect
    #:database (make-db-path url)
    #:mode 'create)))

(define (make-db-path url)
  (define parts
    (for*/list ([part (in-list (url-path url))]
                [path (in-value (path/param-path part))])
      (cond
        [(symbol? path) path]
        [(string=? path "") "/"]
        [else path])))
  (when (or (null? parts)
            (equal? parts '("")))
    (error 'url->sqlite-adapter "sqlite3 connection URL must contain a path"))
  (when (and (url-host url)
             (not (string=? (url-host url) "")))
    (error 'url->sqlite-adapter "sqlite3 connection URL must either start with 0 or 3 slashes"))
  (apply build-path parts))

(module+ test
  (require net/url rackunit)

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
