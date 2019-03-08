(define (geiser:no-values)
  '())

(define (geiser:eval form)
  (let ((port (current-output-port))
	(result
	 (try
	  (eval form)
	  (lambda (e)
	    (e'message)))))
    (write `((result ,(format "{0}" result))
             (output . "")))))

;; not available in minimal REPL
(define (collection->list col)
   (define l ())
   (for-each
      (lambda (i) (set! l (cons i l)))
      col
   )
   ;return:
   (reverse! l)
)

(define (geiser:completions prefix . rest)
  rest
  (define environment
    (((invocation-context)'machine)'globalEnvironment))
  (define (variables env)
    (define variablelist (collection))
    (define viterator (env'variableIterator))
    (define (loop)
      (cond ((viterator'hasNext)
	     (variablelist'add (symbol->string (viterator'next)))
	     (loop))
	    (else variablelist)))
    (loop))
  (collection->list
   (sort (filter (lambda (x)
		   (string-match x (string-append "^" prefix)))
		 (variables environment)) <)))

(define (geiser:module-completions prefix . rest)
  "NexJ Scheme does not support modules"
  '("")
  )

(define (geiser:autodoc ids . rest)
  (list "autodoc"))
