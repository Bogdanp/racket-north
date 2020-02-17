#lang racket/base

(require (for-syntax racket/base
                     racket/port
                     syntax/parse)
         parser-tools/lex
         (prefix-in : parser-tools/lex-sre))

(provide
 read-token)

(define (val lex kind s e)
  (values lex kind #f (position-offset s) (position-offset e)))

(define-syntax-rule (make-lex-string ch kind)
  (lambda (s)
    (define lxr
      (lexer
       [(eof) (val "" 'error s end-pos)]
       [(:~ ch #\\ #\newline) (lxr input-port)]
       [(:: #\\ #\\) (lxr input-port)]
       [(:: #\\ #\newline) (lxr input-port)]
       [(:: #\\ ch) (lxr input-port)]
       [ch (val "" kind s end-pos)]
       [any-char (val "" 'error s end-pos)]))
    lxr))

(define lex-string-sq (make-lex-string #\' 'string))
(define lex-string-dq (make-lex-string #\" 'identifier))

(define-lex-trans (or/ci stx)
  (syntax-parse stx
    [(_ ds:string ...+)
     #:with (ss ...) (for/list ([s (in-list (syntax-e #'(ds ...)))])
                       (datum->syntax #'(ds ...) (string-upcase (syntax->datum s))))
     #'(:or ds ... ss ...)]))

(begin-for-syntax
  (define here
    (syntax-source #'here))

  (define (rel . p)
    (simplify-path (apply build-path here 'up p))))

(define-syntax (define-trans-from-file stx)
  (syntax-parse stx
    [(_ id:id filename:str)
     #:with (s ...) (for/list ([s (in-list (call-with-input-file (rel (syntax->datum #'filename)) port->lines))])
                      (datum->syntax stx s))
     #'(define-lex-trans (id stx)
         (syntax-parse stx
           [(_) #'(or/ci s ...)]))]))

(define-trans-from-file sql-constant "constants.txt")
(define-trans-from-file sql-keyword "keywords.txt")
(define-trans-from-file sql-operator "operators.txt")

(define read-token
  (lexer
   [(:+ whitespace)
    (val lexeme 'whitespace start-pos end-pos)]

   [(:: "--" (:* (:~ #\newline)))
    (val lexeme 'comment start-pos end-pos)]

   [(sql-keyword)
    (val lexeme 'keyword start-pos end-pos)]

   [(sql-constant)
    (val lexeme 'constant start-pos end-pos)]

   [(:: (:or alphabetic #\_) (:* (:or alphabetic numeric #\_)))
    (val lexeme 'identifier start-pos end-pos)]

   [(:: numeric (:* (:or #\. numeric)))
    (val lexeme 'number start-pos end-pos)]

   [#\" ((lex-string-dq start-pos) input-port)]
   [#\' ((lex-string-sq start-pos) input-port)]

   [(:: #\E #\')
    ((lex-string-sq start-pos) input-port)]

   [(:or #\( #\) #\[ #\] #\{ #\})
    (val lexeme 'parenthesis start-pos end-pos)]

   [(sql-operator)
    (val lexeme 'parenthesis start-pos end-pos)]

   [any-char
    (val lexeme 'error start-pos end-pos)]

   [(eof)
    (val lexeme 'eof start-pos end-pos)]))
