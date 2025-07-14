#lang at-exp racket/base

(require db
         net/url
         racket/contract/base
         racket/format
         racket/match
         "base.rkt")

(provide
 (contract-out
  [struct postgres-adapter
    ([conn connection?]
     [schema string?])]
  [url->postgres-adapter (-> url? adapter?)]))

(define (~table ad)
  (define schema (postgres-adapter-schema ad))
  (format "~s.north_schema_version" schema))

(define (~create-table ad)
  (format #<<STMT
CREATE TABLE IF NOT EXISTS ~a(
  current_revision TEXT NOT NULL
) WITH (fillfactor = 10)
STMT
          (~table ad)))

(struct postgres-adapter (conn schema)
  #:methods gen:adapter
  [(define (adapter-init ad)
     (define conn (postgres-adapter-conn ad))
     (call-with-transaction conn
       (lambda ()
         (log-north-adapter-debug "creating schema table")
         (query-exec conn (~create-table ad)))))

   (define (adapter-current-revision ad)
     (query-maybe-value
      (postgres-adapter-conn ad)
      (format "SELECT current_revision FROM ~a" (~table ad))))

   (define (adapter-apply! ad revision scripts)
     (define conn (postgres-adapter-conn ad))
     (define table (~table ad))
     (with-handlers ([exn:fail:sql?
                      (lambda (e)
                        (raise (exn:fail:adapter:migration
                                @~a{failed to apply revision '@revision'}
                                (current-continuation-marks) e revision)))])
       (call-with-transaction conn
         (lambda ()
           (log-north-adapter-debug "applying revision ~a" revision)
           (for ([script (in-list scripts)])
             (query-exec conn script))
           (query-exec conn (format "DELETE FROM ~a" table))
           (query-exec conn (format "INSERT INTO ~a VALUES ($1)" table) revision)))))])

(define (url->postgres-adapter url)
  (define (oops message)
    (raise
     (exn:fail:adapter
      (~a message
          "\n connection URLs must have the form:"
          "\n  postgres://[username[:password]@]hostname[:port]/database_name[?sslmode=prefer|require|disable][&schema=SCHEMA]")
      (current-continuation-marks)
      #f)))
  (define host (url-host url))
  (when (string=? host "")
    (oops "host missing"))
  (define path (url-path url))
  (when (null? path)
    (oops "database_name missing"))
  (define database
    (path/param-path (car (url-path url))))
  (match-define (list _ username password)
    (regexp-match #px"([^:]+)(?::(.+))?" (or (url-user url) "root")))
  (define query (url-query url))
  (define sslmode
    (match (assq 'sslmode query)
      [#f 'no]
      ['(sslmode . "disable") 'no]
      ['(sslmode . "require") 'yes]
      ['(sslmode . "prefer") 'optional]
      [`(sslmode . #f) (oops "empty `sslmode'")]
      [`(sslmode . ,value) (oops (format "invalid `sslmode' value: ~e" value))]))
  (define schema
    (match (assq 'schema query)
      [`(schema . ,value) value]
      [#f "public"]))
  (define conn
    (postgresql-connect
     #:database database
     #:server host
     #:port (url-port url)
     #:ssl sslmode
     #:user username
     #:password password))
  (postgres-adapter conn schema))
