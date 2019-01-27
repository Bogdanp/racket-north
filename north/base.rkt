#lang racket/base

(require (for-syntax racket/base
                     racket/format)
         racket/contract/base
         racket/file
         racket/function
         racket/match
         racket/path)

(provide
 (struct-out exn:fail:migration)

 (contract-out
  [struct migration ([metadata hash?]
                     [child (or/c false/c migration?)])]
  [path->migration (-> path-string? (or/c false/c migration?))]
  [migration-most-recent (-> migration? migration?)]
  [migration-find-parent (-> migration? string? (or/c false/c migration?))]
  [migration-find-revision (-> migration? string? (or/c false/c migration?))]
  [migration-plan (-> migration? (or/c false/c string?) (or/c false/c string?) (listof migration?))]))

(define (read-all-metadata path)
  (define migration-paths
    (find-files
     (lambda (p)
       (define ext (path-get-extension p))
       (and ext (bytes=? #".sql" ext)))

     path))

  (map (curryr dynamic-require 'metadata) migration-paths))

(struct migration (metadata child)
  #:transparent)

(struct exn:fail:migration exn:fail ())

(define-syntax (make-accessor stx)
  (syntax-case stx ()
    [(make-accessor name)
     (with-syntax ([accessor-name (datum->syntax stx (string->symbol (~a "migration-" (syntax->datum #'name))))])
       #'(begin
           (define (accessor-name migration)
             (hash-ref (migration-metadata migration) 'name #f))

           (provide
            (contract-out [accessor-name (-> migration? (or/c false/c string?))]))))]))

(make-accessor name)
(make-accessor revision)
(make-accessor parent)
(make-accessor path)
(make-accessor description)
(make-accessor up)
(make-accessor down)

(define (path->migration path)
  (define metadata-by-parent
    (for/fold ([metadata-by-parent (hash)])
              ([metadata (read-all-metadata path)])
      (define parent (hash-ref metadata 'parent #f))
      (define conflict? (hash-ref metadata-by-parent parent #f))
      (when conflict?
        (raise (exn:fail:migration (format "parent ~a is shared by revisions ~a and ~a"
                                           parent
                                           (hash-ref metadata 'revision)
                                           (hash-ref conflict? 'revision))
                                   (current-continuation-marks))))
      (hash-set metadata-by-parent parent metadata)))

  (define (make-migration metadata)
    (define revision (hash-ref metadata 'revision))
    (define child-metadata (hash-ref metadata-by-parent revision #f))
    (define child (and child-metadata (make-migration child-metadata)))
    (migration metadata child))

  (define orphans (hash-ref metadata-by-parent #f #f))
  (match orphans
    [#f #f]

    [root
     ;; Base is injected as root's parent to make it easy to roll
     ;; back all the migrations.
     (migration (hasheq 'revision "base" 'parent "base")
                (make-migration (hash-set root 'parent "base")))]))

(define (migration-map node proc #:stop-at [stop-at #f])
  (reverse
   (let loop ([current node]
              [results null])
     (match (migration-child current)
       [#f (cons (proc current) results)]
       [child (if (and stop-at (string=? stop-at (migration-revision current)))
                  (cons (proc current) results)
                  (loop child (cons (proc current) results)))]))))

(define (migration-most-recent node)
  (let loop ([current node])
    (define child (migration-child current))
    (cond
      [child (loop child)]
      [else current])))

(define (migration-find-parent node revision)
  (define current-migration (migration-find-revision node revision))
  (migration-find-revision node (migration-parent current-migration)))

(define (migration-find-revision node revision)
  (cond
    [(not node) #f]
    [(string=? (migration-revision node) revision) node]
    [else (migration-find-revision (migration-child node) revision)]))

(define (migration-parent-of? a b)
  (and (migration-find-revision a (migration-revision b)) #t))

(define (migration-plan node from-revision to-revision)
  (match (list from-revision to-revision)
    [(list #f #f) (migration-map node identity)]
    [(list #f  r) (migration-map node identity #:stop-at r)]
    [(list r  #f) (reverse (migration-map node identity #:stop-at r))]

    [(list r1 r2)
     (define m1 (migration-find-revision node r1))
     (define m2 (migration-find-revision node r2))
     (cond
       [(migration-parent-of? m1 m2)
        (cdr (migration-map m1 identity #:stop-at r2))]

       [(migration-parent-of? m2 m1)
        (reverse (cdr (migration-map m2 identity #:stop-at r1)))])]))

(module+ test
  (require rackunit)

  (define head
    (migration (hasheq 'revision "d"
                       'parent "c"
                       'name "20190128-alter-users-add-last-login.sql"
                       'up "d up"
                       'down "d down") #f))

  (define root
    (migration (hasheq 'revision "a"
                       'parent #f
                       'name "20190126-create-users-table.sql"
                       'up "a up"
                       'down "a down")
               (migration (hasheq 'revision "b"
                                  'parent "a"
                                  'name "20190127-alter-users-add-created-at.sql"
                                  'up "b up"
                                  'down "b down")
                          (migration (hasheq 'revision "c"
                                             'parent "b"
                                             'name "20190127-alter-users-add-updated-at.sql"
                                             'up "c up"
                                             'down "c down") head))))

  (check-equal?
   (migration-most-recent root)
   (migration-find-revision root "d"))

  (check-false (migration-find-revision root "invalid"))
  (check-equal? (migration-find-revision root "a") root)
  (check-equal? (migration-find-revision root "d") head)

  (check-true (migration-parent-of? root (migration-find-revision root "d")))
  (check-true (migration-parent-of? (migration-find-revision root "c") (migration-find-revision root "d")))
  (check-true (migration-parent-of? (migration-find-revision root "b") (migration-find-revision root "d")))
  (check-false (migration-parent-of? (migration-find-revision root "d") root))

  (check-equal?
   (migration-plan root #f #f)
   (list (migration-find-revision root "a")
         (migration-find-revision root "b")
         (migration-find-revision root "c")
         (migration-find-revision root "d")))

  (check-equal?
   (migration-plan root #f "b")
   (list (migration-find-revision root "a")
         (migration-find-revision root "b")))

  (check-equal?
   (migration-plan root #f "c")
   (list (migration-find-revision root "a")
         (migration-find-revision root "b")
         (migration-find-revision root "c")))

  (check-equal?
   (migration-plan root "c" #f)
   (list (migration-find-revision root "c")
         (migration-find-revision root "b")
         (migration-find-revision root "a")))

  (check-equal?
   (migration-plan root "b" #f)
   (list (migration-find-revision root "b")
         (migration-find-revision root "a")))

  (check-equal?
   (migration-plan root "a" "c")
   (list (migration-find-revision root "b")
         (migration-find-revision root "c")))

  (check-equal?
   (migration-plan root "b" "d")
   (list (migration-find-revision root "c")
         (migration-find-revision root "d")))

  (check-equal?
   (migration-plan root "d" "a")
   (list (migration-find-revision root "d")
         (migration-find-revision root "c")
         (migration-find-revision root "b")))

  (check-equal?
   (migration-plan root "d" "b")
   (list (migration-find-revision root "d")
         (migration-find-revision root "c"))))
