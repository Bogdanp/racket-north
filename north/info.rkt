#lang info

(define version "0.1.2")
(define collection "north")

(define deps
  '("base"
    "db-lib"
    "gregor-lib"))

(define build-deps
  '("at-exp-lib"
    "racket-doc"
    "rackunit-lib"
    "scribble-lib"))

(define test-omit-paths '("cli.rkt"))

(define raco-commands '(("north" north/cli "run schema migrations" #f)))

(define scribblings '(("north.scrbl")))
