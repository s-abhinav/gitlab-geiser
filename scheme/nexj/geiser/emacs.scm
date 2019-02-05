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
