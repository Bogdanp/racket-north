#lang info

(define version "0.3.0")
(define collection "north")

(define deps
  '("base"
    "db-lib"
    "gregor-lib"
    "parser-tools-lib"))

(define build-deps
  '("at-exp-lib"
    "racket-doc"
    "rackunit-lib"
    "scribble-lib"))

(define test-omit-paths '("cli.rkt"))

(define raco-commands '(("north" north/cli "run schema migrations" #f)))

(define scribblings '(("north.scrbl")))
