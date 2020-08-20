#lang racket/base

(require racket/format
         racket/path
         racket/port
         syntax/readerr)

(provide
 get-info
 (rename-out [migrations-read read]
             [migrations-read-syntax read-syntax]))

(define all-keywords
  (list "description" "revision" "parent" "engine" "up" "down"))

(define (migrations-read in)
  (syntax->datum (migrations-read-syntax #f in)))

(define (migrations-read-syntax src in)
  (define (chomp-spaces)
    (regexp-match #px"^\\s*" in))

  (define (peek c)
    (define next-char (peek-char in))
    (and (not (eof-object? next-char)) (char=? next-char c)))

  (define (expect c)
    (define-values (line col pos) (port-next-location in))
    (define current-char (read-char in))
    (when (eof-object? current-char)
      (raise-read-error (format "unexpected end of file, expected '~a'" c) src line col pos 0))
    (unless (char=? current-char c)
      (raise-read-error (format "expected '~a' but found '~a'" c current-char) src line col pos 1)))

  (define (read-keyword)
    (define-values (line col pos) (port-next-location in))
    (define keyword
      (let loop ([keyword ""])
        (define next-char (peek-char in))
        (cond
          [(eof-object? next-char)            keyword]
          [(not (char-alphabetic? next-char)) keyword]

          [else (loop (~a keyword (read-char in)))])))

    (when (string=? "" keyword)
      (raise-read-error "unexpected end of file while reading keyword" src line col pos 0))

    (unless (member keyword all-keywords)
      (raise-read-error (format "invalid keyword ~a" keyword) src line col pos (string-length keyword)))

    keyword)

  (define (read-string)
    (define-values (line col pos) (port-next-location in))
    (call-with-output-string
     (lambda (out)
       (unless (regexp-match #px"\n" in 0 #f out)
         (raise-read-error "unexpected end of file while reading string" src line col pos 0)))))

  (define (read-block name)
    (define-values (line col pos) (port-next-location in))
    (call-with-output-string
     (lambda (out)
       (unless (regexp-match #px"\n--\\s*\\}" in 0 #f out)
         (raise-read-error (format "unexpected end of file while reading ~v block" name) src line col pos 0)))))

  (define (read-declaration)
    (expect #\-)
    (expect #\-)
    (chomp-spaces)

    (expect #\@)
    (define keyword (read-keyword))
    (chomp-spaces)

    (define value
      (cond
        [(peek #\{)
         (expect #\{)
         (chomp-spaces)
         (read-block keyword)]

        [else
         (expect #\:)
         (chomp-spaces)
         (read-string)]))

    #`(cons '#,(string->symbol keyword) #,value))

  (define declarations
   (let loop ([declarations null])
     (define next-char (peek-char in))
     (cond
       [(eof-object? next-char)
        (reverse declarations)]

       [(char=? next-char #\-)
        (loop (cons (read-declaration) declarations))]

       [else
        (read-char in)
        (loop declarations)])))

  (define module-name
    (string->symbol
     (path->string (path-replace-extension (file-name-from-path src) ""))))

  #`(module #,module-name racket/base
      (provide metadata)

      (define pairs
        (list (cons 'name #,(symbol->string module-name))
              (cons 'path #,(path->string src))
              #,@declarations))

      (define metadata
        (for/fold ([metadata (hasheq)]
                   #:result (hash-update
                             (hash-update metadata 'up reverse null)
                             'down reverse null))
                  ([p (in-list pairs)])
          (define k (car p))
          (define v (cdr p))
          (case k
            [(up down)
             (hash-update metadata k
                          (lambda (vs)
                            (cons v vs))
                          null)]

            [else
             (hash-set metadata k v)])))

      (unless (hash-has-key? metadata 'revision)
        (raise-syntax-error '#,module-name "@revision missing"))

      (unless (hash-has-key? metadata 'up)
        (raise-syntax-error '#,module-name "@up missing"))))

(define ((get-info _in _mod _line _col _pos) key default)
  (case key
    [(drracket:default-filters) '(["north Migrations" ".sql"])]
    [(drracket:default-extension) "sql"]
    [(color-lexer) (dynamic-require 'north/tool/syntax-color 'read-token)]
    [(module-language) 'racket/base]
    [else default]))
