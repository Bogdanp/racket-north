#lang racket/base

(require racket/generic)

(provide (all-defined-out))

(define-logger north-adapter)

(define-generics adapter
  (adapter-init adapter)
  (adapter-current-revision adapter)
  (adapter-apply! adapter revision scripts))

(struct exn:fail:adapter exn:fail (cause))
(struct exn:fail:adapter:migration exn:fail:adapter (revision))
