#lang racket/base

(require racket/format
         racket/path
         racket/port
         syntax/readerr)

(provide
 (rename-out [migrations-read read]
             [migrations-read-syntax read-syntax]))

(define all-keywords
  (list "description" "revision" "parent" "up" "down"))

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
    (cond
      [(eof-object? current-char)
       (raise-read-error (format "unexpected end of file, expected '~a'" c) src line col pos 0)]

      [(not (char=? current-char c))
       (raise-read-error (format "expected '~a' but found '~a'" c current-char) src line col pos 1)]))

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

  (define (read-block)
    (define-values (line col pos) (port-next-location in))
    (call-with-output-string
     (lambda (out)
       (unless (regexp-match #px"\n--\\s*\\}" in 0 #f out)
         (raise-read-error "unexpected end of file while reading block" src line col pos 0)))))

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
         (read-block)]

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

      (define metadata
        (make-immutable-hasheq (list (cons 'name #,(symbol->string module-name))
                                     (cons 'path #,(path->string src))
                                     #,@declarations)))

      (unless (hash-has-key? metadata 'revision)
        (raise-syntax-error '#,module-name "@revision missing"))

      (unless (hash-has-key? metadata 'up)
        (raise-syntax-error '#,module-name "@up missing"))))
