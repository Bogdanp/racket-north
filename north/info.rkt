#lang info

(define version "0.0.0")
(define collection "north")

(define deps '("base"
               "db-lib"
               "gregor-lib"))
(define build-deps '("rackunit-lib"))

(define raco-commands '(("north" north/cli "run schema migrations" #f)))
