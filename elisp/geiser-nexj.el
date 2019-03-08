;; geiser-nexj.el -- NexJ Scheme's implementation of the geiser protocols



(require 'geiser-connection)
(require 'geiser-syntax)
(require 'geiser-custom)
(require 'geiser-base)
(require 'geiser-eval)
(require 'geiser-edit)
(require 'geiser-log)
(require 'geiser)

(require 'compile)
(require 'info-look)

(eval-when-compile (require 'cl))

;;; Customization:

(defgroup geiser-nexj nil
  "Customization for Geiser's NexJ flavour."
  :group 'geiser)

(geiser-custom--defcustom geiser-nexj-binary
  (cond ((eq system-type 'windows-nt) "nexj-scheme")
        ((eq system-type 'darwin) "nexj-scheme")
        (t "nexj-scheme"))
  "Name to use to call the NexJ executable when starting a REPL."
  :type '(choice string (repeat string))
  :group 'geiser-nexj)

(defun geiser-nexj--parameters ()
  "Return a list with all parameters needed to start NexJ Scheme."
  `(,(concat "(load " "\"" (expand-file-name "nexj/geiser/emacs.scm" geiser-scheme-dir) "\"" ")")))

(geiser-custom--defcustom geiser-nexj-case-sensitive-p t
  "Non-nil means keyword highlighting is case-sensitive."
  :type 'boolean
  :group 'geiser-nexj)


;;; REPL support:

(defun geiser-nexj--binary ()
  (if (listp geiser-nexj-binary)
      (car geiser-nexj-binary)
    geiser-nexj-binary))

(defconst geiser-nexj--prompt-regexp "> ")

;;; Evaluation support:
(defun geiser-nexj--symbol-begin (module)
  (if module
      (max (save-excursion (beginning-of-line) (point))
           (save-excursion (skip-syntax-backward "^(>") (1- (point))))
    (save-excursion (skip-syntax-backward "^'-()>") (point))))

(defun geiser-nexj--get-module (&optional module)
  :f)

(defun geiser-nexj--geiser-procedure (proc &rest args)
  (case proc
    ((eval compile)
     (let
	 ((form (mapconcat 'identity (cdr args) " "))
	  (module (cond ((string-equal "'()" (car args))
                          "'()")
                         ((and (car args))
                             (concat "'" (car args)))
                         (t
                          "#f"))))
	 (format "(geiser:eval '%s)" form)))
    ((no-values)
     "(geiser:no-values)")
    (t (let ((form (mapconcat 'identity args " ")))
	 (format "(geiser:%s %s)" proc form)))))

(defun geiser-nexj--exit-command () "^C")

(defun geiser-nexj--startup (remote)
  (let ((geiser-log-verbose-p t))
    (compilation-setup t)))


;;; definition:

(define-geiser-implementation nexj
  (binary geiser-nexj--binary)
  (arglist geiser-nexj--parameters)
  (repl-startup geiser-nexj--startup)
  (prompt-regexp geiser-nexj--prompt-regexp)
  (exit-command geiser-nexj--exit-command)
  (find-module geiser-nexj--get-module)
  (marshall-procedure geiser-nexj--geiser-procedure)
  (find-symbol-begin geiser-nexj--symbol-begin))

(geiser-impl--add-to-alist 'regexp "\\.scm$" 'nexj t)


(provide 'geiser-nexj)
