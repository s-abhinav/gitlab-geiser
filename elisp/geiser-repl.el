;;; geiser-repl.el --- Geiser's REPL

;; Copyright (C) 2009, 2010, 2011, 2012, 2013, 2015, 2016, 2018, 2019 Jose Antonio Ortega Ruiz

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the Modified BSD License. You should
;; have received a copy of the license along with this program. If
;; not, see <http://www.xfree86.org/3.3.6/COPYRIGHT2.html#5>.



(require 'geiser-company)
(require 'geiser-doc)
(require 'geiser-autodoc)
(require 'geiser-edit)
(require 'geiser-completion)
(require 'geiser-syntax)
(require 'geiser-impl)
(require 'geiser-eval)
(require 'geiser-connection)
(require 'geiser-menu)
(require 'geiser-image)
(require 'geiser-custom)
(require 'geiser-base)

(require 'comint)
(require 'compile)
(require 'scheme)
(require 'font-lock)


;;; Customization:

(defgroup geiser-repl nil
  "Interacting with the Geiser REPL."
  :group 'geiser)

(geiser-custom--defcustom geiser-repl-buffer-name-function
    'geiser-repl-buffer-name
  "Function used to define the name of a REPL buffer.
The function is called with a single argument - an implementation
symbol (e.g., `guile', `chicken', etc.)."
  :type '(choice (function-item geiser-repl-buffer-name)
                 (function :tag "Other function"))
  :group 'geiser-repl)

(geiser-custom--defcustom geiser-repl-use-other-window t
  "Whether to Use a window other than the current buffer's when
switching to the Geiser REPL buffer."
  :type 'boolean
  :group 'geiser-repl)

(geiser-custom--defcustom geiser-repl-window-allow-split t
  "Whether to allow window splitting when switching to the Geiser
REPL buffer."
  :type 'boolean
  :group 'geiser-repl)

(geiser-custom--defcustom geiser-repl-history-filename
    (expand-file-name "~/.geiser_history")
  "File where REPL input history is saved, so that it persists between sessions.

This is actually the base name: the concrete Scheme
implementation name gets appended to it."
  :type 'file
  :group 'geiser-repl)

(geiser-custom--defcustom geiser-repl-history-size comint-input-ring-size
  "Maximum size of the saved REPL input history."
  :type 'integer
  :group 'geiser-repl)

(geiser-custom--defcustom geiser-repl-history-no-dups-p t
  "Whether to skip duplicates when recording history."
  :type 'boolean
  :group 'geiser-repl)

(geiser-custom--defcustom geiser-repl-save-debugging-history-p nil
  "Whether to skip debugging input in REPL history.

By default, REPL interactions while scheme is in the debugger are
not added to the REPL command history.  Set this variable to t to
change that."
  :type 'boolean
  :group 'geiser-repl)

(geiser-custom--defcustom geiser-repl-autodoc-p t
  "Whether to enable `geiser-autodoc-mode' in the REPL by default."
  :type 'boolean
  :group 'geiser-repl)

(geiser-custom--defcustom geiser-repl-company-p t
  "Whether to use company-mode for completion, if available."
  :group 'geiser-mode
  :type 'boolean)

(geiser-custom--defcustom geiser-repl-read-only-prompt-p t
  "Whether the REPL's prompt should be read-only."
  :type 'boolean
  :group 'geiser-repl)

(geiser-custom--defcustom geiser-repl-read-only-output-p t
  "Whether the REPL's output should be read-only."
  :type 'boolean
  :group 'geiser-repl)

(geiser-custom--defcustom geiser-repl-highlight-output-p nil
  "Whether to syntax highlight REPL output."
  :type 'boolean
  :group 'geiser-repl)

(geiser-custom--defcustom geiser-repl-auto-indent-p t
  "Whether newlines for incomplete sexps are autoindented."
  :type 'boolean
  :group 'geiser-repl)

(geiser-custom--defcustom geiser-repl-forget-old-errors-p t
  "Whether to forget old errors upon entering a new expression.

When on (the default), every time a new expression is entered in
the REPL old error messages are flushed, and using \\[next-error]
afterwards will jump only to error locations produced by the new
expression, if any."
  :type 'boolean
  :group 'geiser-repl)

(geiser-custom--defcustom geiser-repl-skip-version-check-p nil
  "Whether to skip version checks for the Scheme executable.

When set, Geiser won't check the version of the Scheme
interpreter when starting a REPL, saving a few tenths of a
second.
"
  :type 'boolean
  :group 'geiser-repl)

(geiser-custom--defcustom geiser-repl-query-on-exit-p nil
  "Whether to prompt for confirmation on \\[geiser-repl-exit]."
  :type 'boolean
  :group 'geiser-repl)

(geiser-custom--defcustom geiser-repl-delete-last-output-on-exit-p nil
  "Whether to delete partial outputs when the REPL's process exits."
  :type 'boolean
  :group 'geiser-repl)

(geiser-custom--defcustom geiser-repl-query-on-kill-p t
  "Whether to prompt for confirmation when killing a REPL buffer with
a life process."
  :type 'boolean
  :group 'geiser-repl)

(geiser-custom--defcustom geiser-repl-default-host "localhost"
  "Default host when connecting to remote REPLs."
  :type 'string
  :group 'geiser-repl)

(geiser-custom--defcustom geiser-repl-default-port 37146
  "Default port for connecting to remote REPLs."
  :type 'integer
  :group 'geiser-repl)

(geiser-custom--defcustom geiser-repl-startup-time 10000
  "Time, in milliseconds, to wait for Racket to startup.
If you have a slow system, try to increase this time."
  :type 'integer
  :group 'geiser-repl)

(geiser-custom--defcustom geiser-repl-inline-images-p t
  "Whether to display inline images in the REPL."
  :type 'boolean
  :group 'geiser-repl)

(geiser-custom--defcustom geiser-repl-auto-display-images-p t
  "Whether to automatically invoke the external viewer to display
images popping up in the REPL.

See also `geiser-debug-auto-display-images-p'."
  :type 'boolean
  :group 'geiser-repl)

(geiser-custom--defface repl-input
  'comint-highlight-input geiser-repl "evaluated input highlighting")

(geiser-custom--defface repl-output
  'font-lock-string-face geiser-repl "REPL output")

(geiser-custom--defface repl-prompt
  'comint-highlight-prompt geiser-repl "REPL prompt")



;;; Implementation-dependent parameters

(geiser-impl--define-caller geiser-repl--binary binary ()
  "A variable or function returning the path to the scheme binary
for this implementation.")

(geiser-impl--define-caller geiser-repl--arglist arglist ()
  "A function taking no arguments and returning a list of
arguments to be used when invoking the scheme binary.")

(geiser-impl--define-caller geiser-repl--prompt-regexp prompt-regexp ()
  "A variable (or thunk returning a value) giving the regular
expression for this implementation's geiser scheme prompt.")

(geiser-impl--define-caller
    geiser-repl--debugger-prompt-regexp debugger-prompt-regexp ()
  "A variable (or thunk returning a value) giving the regular
expression for this implementation's debugging prompt.")

(geiser-impl--define-caller geiser-repl--startup repl-startup (remote)
  "Function taking no parameters that is called after the REPL
has been initialised. All Geiser functionality is available to
you at that point.")

(geiser-impl--define-caller geiser-repl--enter-cmd enter-command (module)
  "Function taking a module designator and returning a REPL enter
module command as a string")

(geiser-impl--define-caller geiser-repl--import-cmd import-command (module)
  "Function taking a module designator and returning a REPL import
module command as a string")

(geiser-impl--define-caller geiser-repl--exit-cmd exit-command ()
  "Function returning the REPL exit command as a string")

(geiser-impl--define-caller geiser-repl--version version-command (binary)
  "Function returning the version of the corresponding scheme process,
   given its full path.")

(geiser-impl--define-caller geiser-repl--min-version minimum-version ()
  "A variable providing the minimum required scheme version, as a string.")


;;; Geiser REPL buffers and processes:

(defvar geiser-repl--repls nil)
(defvar geiser-repl--closed-repls nil)

(defvar geiser-repl--last-output-start nil)
(defvar geiser-repl--last-output-end nil)

(make-variable-buffer-local
 (defvar geiser-repl--repl nil))

(defsubst geiser-repl--set-this-buffer-repl (r)
  (setq geiser-repl--repl r))

(defun geiser-repl--live-p ()
  (and geiser-repl--repl
       (get-buffer-process geiser-repl--repl)))

(defun geiser-repl--repl/impl (impl &optional repls)
  (catch 'repl
    (dolist (repl (or repls geiser-repl--repls))
      (when (buffer-live-p repl)
        (with-current-buffer repl
          (when (eq geiser-impl--implementation impl)
            (throw 'repl repl)))))))

(defun geiser-repl--set-up-repl (impl)
  (or (and (not impl) geiser-repl--repl)
      (setq geiser-repl--repl
            (let ((impl (or impl
                            geiser-impl--implementation
                            (geiser-impl--guess))))
              (when impl (geiser-repl--repl/impl impl))))))

(defun geiser-repl--active-impls ()
  (let ((act))
    (dolist (repl geiser-repl--repls act)
      (with-current-buffer repl
        (add-to-list 'act geiser-impl--implementation)))))

(defsubst geiser-repl--repl-name (impl)
  (format "%s REPL" (geiser-impl--impl-str impl)))

(defsubst geiser-repl--buffer-name (impl)
  (funcall geiser-repl-buffer-name-function impl))

(defun geiser-repl-buffer-name (impl)
  "Return default name of the REPL buffer for implementation IMPL."
  (format "* %s *" (geiser-repl--repl-name impl)))

(defun geiser-repl--switch-to-buffer (buffer)
  (unless (eq buffer (current-buffer))
    (let ((pop-up-windows geiser-repl-window-allow-split))
      (if geiser-repl-use-other-window
          (switch-to-buffer-other-window buffer)
        (switch-to-buffer buffer)))))

(defun geiser-repl--to-repl-buffer (impl)
  (unless (and (eq major-mode 'geiser-repl-mode)
               (eq geiser-impl--implementation impl)
               (not (get-buffer-process (current-buffer))))
    (let* ((old (geiser-repl--repl/impl impl geiser-repl--closed-repls))
           (old (and (buffer-live-p old)
                     (not (get-buffer-process old))
                     old)))
      (geiser-repl--switch-to-buffer
       (or old (generate-new-buffer (geiser-repl--buffer-name impl))))
      (unless old
        (geiser-repl-mode)
        (geiser-impl--set-buffer-implementation impl)
        (geiser-syntax--add-kws t)))))

(defun geiser-repl--read-impl (prompt &optional active)
  (geiser-impl--read-impl prompt (and active (geiser-repl--active-impls))))

(defsubst geiser-repl--only-impl-p ()
  (and (null (cdr geiser-active-implementations))
       (car geiser-active-implementations)))

(defun geiser-repl--get-impl (prompt)
  (or (geiser-repl--only-impl-p)
      (and (eq major-mode 'geiser-repl-mode) geiser-impl--implementation)
      (geiser-repl--read-impl prompt)))


;;; Prompt &co.

(defun geiser-repl--last-prompt-end ()
  (cond ((and (boundp 'comint-last-prompt) (markerp (cdr comint-last-prompt)))
         (marker-position (cdr comint-last-prompt)))
        ((and (boundp 'comint-last-prompt-overlay) comint-last-prompt-overlay)
         (overlay-end comint-last-prompt-overlay))
        (t (save-excursion
             (geiser-repl--bol)
             (min (+ 1 (point)) (point-max))))))

(defun geiser-repl--last-prompt-start ()
  (cond ((and (boundp 'comint-last-prompt) (markerp (car comint-last-prompt)))
         (marker-position (car comint-last-prompt)))
        ((and (boundp 'comint-last-prompt-overlay) comint-last-prompt-overlay)
         (overlay-start comint-last-prompt-overlay))
        (t (save-excursion (geiser-repl--bol) (point)))))


;;; REPL connections

(make-variable-buffer-local
 (defvar geiser-repl--address nil))

(make-variable-buffer-local
 (defvar geiser-repl--connection nil))

(defun geiser-repl--local-p ()
  "Return non-nil, if current REPL is local (connected to socket)."
  (stringp geiser-repl--address))

(defun geiser-repl--remote-p ()
  "Return non-nil, if current REPL is remote (connected to host:port)."
  (consp geiser-repl--address))

(defsubst geiser-repl--host () (car geiser-repl--address))
(defsubst geiser-repl--port () (cdr geiser-repl--address))

(defun geiser-repl--read-address (&optional host port)
  (let ((defhost (or (geiser-repl--host) geiser-repl-default-host))
        (defport (or (geiser-repl--port) geiser-repl-default-port)))
    (cons (or host
              (read-string (format "Host (default %s): " defhost)
                           nil nil defhost))
          (or port (read-number "Port: " defport)))))

(defun geiser-repl--autodoc-mode (n)
  (when (or geiser-repl-autodoc-p (< n 0))
    (geiser--save-msg (geiser-autodoc-mode n))))

(defun geiser-repl--save-remote-data (address)
  (setq geiser-repl--address address)
  (setq header-line-format
        (cond ((consp address)
               (format "Host: %s   Port: %s"
                       (geiser-repl--host)
                       (geiser-repl--port)))
              ((stringp address)
               (format "Socket: %s" address))
              (t nil))))

(defun geiser-repl--fontify-output-region (beg end)
  "Apply highlighting to a REPL output region."
  (remove-text-properties beg end '(font-lock-face nil face nil))
  (if geiser-repl-highlight-output-p
      (geiser-syntax--fontify-syntax-region beg end)
    (geiser-repl--fontify-plaintext beg end)))

(defun geiser-repl--fontify-plaintext (start end)
  "Fontify REPL output plainly."
  (add-text-properties
   start end
   '(font-lock-fontified t
     fontified t
     font-lock-multiline t
     font-lock-face geiser-font-lock-repl-output)))

(defun geiser-repl--narrow-to-prompt ()
  "Narrow to active prompt region and return t, otherwise returns nil."
  (let* ((proc (get-buffer-process (current-buffer)))
         (pmark (and proc (process-mark proc)))
         (intxt (when (>= (point) (marker-position pmark))
                  (save-excursion
                    (if comint-eol-on-send
                        (if comint-use-prompt-regexp
                            (end-of-line)
                          (goto-char (field-end))))
                    (buffer-substring pmark (point)))))
         (prompt-beg (marker-position pmark))
         (prompt-end (+ prompt-beg (length intxt))))
    (when (> (length intxt) 0)
      (narrow-to-region prompt-beg prompt-end)
      t)))

(defun geiser-repl--wrap-fontify-region-function (beg end &optional loudly)
  (save-restriction
    (when (geiser-repl--narrow-to-prompt)
      (let ((font-lock-dont-widen t))
        (font-lock-default-fontify-region (point-min) (point-max) nil)))))

(defun geiser-repl--wrap-unfontify-region-function (beg end &optional loudly)
  (save-restriction
    (when (geiser-repl--narrow-to-prompt)
      (let ((font-lock-dont-widen t))
        (font-lock-default-unfontify-region (point-min) (point-max))))))

(defun geiser-repl--output-filter (txt)
  (let ((mark-output nil))
    (save-excursion
      (goto-char (point-max))
      (re-search-backward comint-prompt-regexp)
      ;; move to start of line to prevent accidentally marking a REPL prompt
      (move-to-column 0)
      ;; Only mark output which:
      ;; a) is not on the REPL output line
      ;; b) has at least one character
      ;;
      ;; This makes the magic number for distance 3 -- as the newline
      ;; after executing expression is also counted. This is due to the point
      ;; being set before comint-send-input.
      ;;
      ;; Restriction a) applies due to our inability to distinguish between
      ;; output from the REPL, and the REPL prompt output.
      (let ((distance (- (point) geiser-repl--last-output-start)))
        (when (> distance 2)
          (setq mark-output t)
          (set-marker geiser-repl--last-output-end (point)))))
    (when mark-output
      (with-silent-modifications
        (add-text-properties (1+ geiser-repl--last-output-start)
                             geiser-repl--last-output-end
                             `(read-only ,geiser-repl-read-only-output-p))
        (geiser-repl--fontify-output-region geiser-repl--last-output-start
                                            geiser-repl--last-output-end)
        (font-lock-ensure geiser-repl--last-output-start
                          geiser-repl--last-output-end))))

  (geiser-con--connection-update-debugging geiser-repl--connection txt)
  (geiser-image--replace-images geiser-repl-inline-images-p
                                geiser-repl-auto-display-images-p)
  (when (string-match-p (geiser-con--connection-prompt geiser-repl--connection)
                        txt)
    (geiser-autodoc--disinhibit-autodoc)))

(defun geiser-repl--check-version (impl)
  (when (not geiser-repl-skip-version-check-p)
    (let ((v (geiser-repl--version impl (geiser-repl--binary impl)))
          (r (geiser-repl--min-version impl)))
      (when (and v r (geiser--version< v r))
        (error "Geiser requires %s version %s but detected %s" impl r v)))))

(defun geiser-repl--start-repl (impl address)
  (message "Starting Geiser REPL for %s ..." impl)
  (when (not address) (geiser-repl--check-version impl))
  (geiser-repl--to-repl-buffer impl)
  (sit-for 0)
  (goto-char (point-max))
  (geiser-repl--autodoc-mode -1)
  (let* ((prompt-rx (geiser-repl--prompt-regexp impl))
         (deb-prompt-rx (geiser-repl--debugger-prompt-regexp impl))
         (prompt (geiser-con--combined-prompt prompt-rx deb-prompt-rx)))
    (unless prompt-rx
      (error "Sorry, I don't know how to start a REPL for %s" impl))
    (geiser-repl--save-remote-data address)
    (geiser-repl--start-scheme impl address prompt)
    (geiser-repl--quit-setup)
    (geiser-repl--history-setup)
    (add-to-list 'geiser-repl--repls (current-buffer))
    (geiser-repl--set-this-buffer-repl (current-buffer))
    (setq geiser-repl--connection
          (geiser-con--make-connection (get-buffer-process (current-buffer))
                                       prompt-rx
                                       deb-prompt-rx))
    (geiser-repl--startup impl address)
    (geiser-repl--autodoc-mode 1)
    (geiser-company--setup geiser-repl-company-p)
    (add-hook 'comint-output-filter-functions
              'geiser-repl--output-filter
              nil
              t)
    (set-process-query-on-exit-flag (get-buffer-process (current-buffer))
                                    geiser-repl-query-on-kill-p)
    (message "%s up and running!" (geiser-repl--repl-name impl))))

(defun geiser-repl--start-scheme (impl address prompt)
  (setq comint-prompt-regexp prompt)
  (let* ((name (geiser-repl--repl-name impl))
         (buff (current-buffer))
         (args (cond ((consp address) (list address))
                     ((stringp address) '(()))
                     (t `(,(geiser-repl--binary impl)
                          nil
                          ,@(geiser-repl--arglist impl))))))
    (condition-case err
        (if (and address (stringp address))
            ;; Connect over a Unix-domain socket.
            (let ((proc (make-network-process :name (buffer-name buff)
                                              :buffer buff
                                              :family 'local
                                              :remote address)))
              ;; brittleness warning: this is stuff
              ;; make-comint-in-buffer sets up, via comint-exec, when
              ;; it creates its own process, something we're doing
              ;; here by ourselves.
              (set-process-filter proc 'comint-output-filter)
              (goto-char (point-max))
              (set-marker (process-mark proc) (point)))
          (apply 'make-comint-in-buffer `(,name ,buff ,@args)))
      (error (insert "Unable to start REPL:\n"
                     (error-message-string err)
                     "\n")
             (error "Couldn't start Geiser: %s" err)))
    (geiser-repl--wait-for-prompt geiser-repl-startup-time)))

(defun geiser-repl--wait-for-prompt (timeout)
  (let ((p (point)) (seen) (buffer (current-buffer)))
    (while (and (not seen)
                (> timeout 0)
                (get-buffer-process buffer))
      (sleep-for 0.1)
      (setq timeout (- timeout 100))
      (goto-char p)
      (setq seen (re-search-forward comint-prompt-regexp nil t)))
    (goto-char (point-max))
    (unless seen (error "%s" "No prompt found!"))))

(defun geiser-repl--is-debugging ()
  (let ((dp (geiser-con--connection-debug-prompt geiser-repl--connection)))
    (and dp
         (save-excursion
           (goto-char (geiser-repl--last-prompt-start))
           (re-search-forward dp (geiser-repl--last-prompt-end) t)))))

(defun geiser-repl--connection* ()
  (let ((buffer (geiser-repl--set-up-repl geiser-impl--implementation)))
   (and (buffer-live-p buffer)
        (get-buffer-process buffer)
        (with-current-buffer buffer geiser-repl--connection))))

(defun geiser-repl--connection ()
  (or (geiser-repl--connection*)
      (error "No Geiser REPL for this buffer (try M-x run-geiser)")))

(setq geiser-eval--default-connection-function 'geiser-repl--connection)

(defun geiser-repl--prepare-send ()
  (geiser-image--clean-cache)
  (geiser-autodoc--inhibit-autodoc)
  (geiser-con--connection-deactivate geiser-repl--connection))

(defun geiser-repl--send (cmd &optional save-history)
  "Send CMD input string to the current REPL buffer.
If SAVE-HISTORY is non-nil, save CMD in the REPL history."
  (when (and cmd (eq major-mode 'geiser-repl-mode))
    (geiser-repl--prepare-send)
    (goto-char (point-max))
    (comint-kill-input)
    (insert cmd)
    (let ((comint-input-filter (if save-history
                                   comint-input-filter
                                 'ignore)))
      (comint-send-input nil t))))

(defun geiser-repl-interrupt ()
  (interactive)
  (when (get-buffer-process (current-buffer))
    (interrupt-process nil comint-ptyp)))


;;; REPL history

(defconst geiser-repl--history-separator "\n}{\n")

(defsubst geiser-repl--history-file ()
  (format "%s.%s" geiser-repl-history-filename geiser-impl--implementation))

(defun geiser-repl--read-input-ring ()
  (let ((comint-input-ring-file-name (geiser-repl--history-file))
        (comint-input-ring-separator geiser-repl--history-separator)
        (buffer-file-coding-system 'utf-8))
    (comint-read-input-ring t)))

(defun geiser-repl--write-input-ring ()
  (let ((comint-input-ring-file-name (geiser-repl--history-file))
        (comint-input-ring-separator geiser-repl--history-separator)
        (buffer-file-coding-system 'utf-8))
    (comint-write-input-ring)))

(defun geiser-repl--history-setup ()
  (set (make-local-variable 'comint-input-ring-size) geiser-repl-history-size)
  (set (make-local-variable 'comint-input-filter) 'geiser-repl--input-filter)
  (geiser-repl--read-input-ring))


;;; Cleaning up

(defun geiser-repl--on-quit ()
  (geiser-repl--write-input-ring)
  (let ((cb (current-buffer))
        (impl geiser-impl--implementation)
        (comint-prompt-read-only nil))
    (geiser-con--connection-deactivate geiser-repl--connection t)
    (geiser-con--connection-close geiser-repl--connection)
    (setq geiser-repl--repls (remove cb geiser-repl--repls))
    (dolist (buffer (buffer-list))
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (when (and (eq geiser-impl--implementation impl)
                     (equal cb geiser-repl--repl))
            (geiser-repl--set-up-repl geiser-impl--implementation)))))))

(defun geiser-repl--sentinel (proc event)
  (let ((pb (process-buffer proc)))
    (when (buffer-live-p pb)
      (with-current-buffer pb
        (let ((comint-prompt-read-only nil)
              (comint-input-ring-file-name (geiser-repl--history-file))
              (comint-input-ring-separator geiser-repl--history-separator))
          (geiser-repl--on-quit)
          (push pb geiser-repl--closed-repls)
          (goto-char (point-max))
          (when geiser-repl-delete-last-output-on-exit-p
            (comint-kill-region comint-last-input-start (point)))
          (insert "\nIt's been nice interacting with you!\n")
          (insert "Press C-c C-z to bring me back.\n"))))))

(defun geiser-repl--on-kill ()
  (geiser-repl--on-quit)
  (setq geiser-repl--closed-repls
        (remove (current-buffer) geiser-repl--closed-repls)))

(defun geiser-repl--input-filter (str)
  (not (or (and (not geiser-repl-save-debugging-history-p)
                (geiser-repl--is-debugging))
           (string-match "^\\s *$" str)
           (string-match "^,quit *$" str))))

(defun geiser-repl--old-input ()
  (save-excursion
    (let ((end (point)))
      (backward-sexp)
      (buffer-substring (point) end))))

(defun geiser-repl--quit-setup ()
  (add-hook 'kill-buffer-hook 'geiser-repl--on-kill nil t)
  (set-process-sentinel (get-buffer-process (current-buffer))
                        'geiser-repl--sentinel))


;;; geiser-repl mode:

(defun geiser-repl--bol ()
  (interactive)
  (when (= (point) (comint-bol)) (beginning-of-line)))

(defun geiser-repl--beginning-of-defun ()
  (save-restriction
    (narrow-to-region (geiser-repl--last-prompt-end) (point))
    (let ((beginning-of-defun-function nil))
      (beginning-of-defun))))

(defun geiser-repl--module-function (&optional module)
  (if (and module geiser-eval--get-impl-module)
      (funcall geiser-eval--get-impl-module module)
      :f))

(defun geiser-repl--doc-module ()
  (interactive)
  (let ((geiser-eval--get-module-function
         (geiser-impl--method 'find-module geiser-impl--implementation)))
    (geiser-doc-module)))

(defun geiser-repl--newline-and-indent ()
  (interactive)
  (save-restriction
    (narrow-to-region comint-last-input-start (point-max))
    (insert "\n")
    (lisp-indent-line)))

(defun geiser-repl--nesting-level ()
  (save-restriction
    (narrow-to-region (geiser-repl--last-prompt-end) (point-max))
    (geiser-syntax--nesting-level)))

(defun geiser-repl--is-input ()
  (not (eq (field-at-pos (point)) 'output)))

(defun geiser-repl--grab-input ()
  (let ((pos (comint-bol)))
    (goto-char (point-max))
    (insert (field-string-no-properties pos))))

(defun geiser-repl--send-input ()
  (set-marker geiser-repl--last-output-start (point-max))

  (let* ((proc (get-buffer-process (current-buffer)))
         (pmark (and proc (process-mark proc)))
         (intxt (and pmark (buffer-substring pmark (point))))
         (eob (point-max)))
    (when intxt
      (and geiser-repl-forget-old-errors-p
           (not (geiser-repl--is-debugging))
           (compilation-forget-errors))
      (geiser-repl--prepare-send)
      (comint-send-input)
      (when (string-match "^\\s-*$" intxt)
        (comint-send-string proc (geiser-eval--scheme-str '(:ge no-values)))
        (comint-send-string proc "\n")))))

(defun geiser-repl--maybe-send ()
  (interactive)
  (let ((p (point)))
    (cond ((< p (geiser-repl--last-prompt-start))
           (if (geiser-repl--is-input)
               (geiser-repl--grab-input)
             (ignore-errors (compile-goto-error))))
          ((let ((inhibit-field-text-motion t))
             (end-of-line)
             (<= (geiser-repl--nesting-level) 0))
           (geiser-repl--send-input))
          (t (goto-char p)
             (if geiser-repl-auto-indent-p
                 (geiser-repl--newline-and-indent)
               (insert "\n"))))))

(defun geiser-repl-tab-dwim (n)
  "If we're after the last prompt, complete symbol or indent (if
there's no symbol at point). Otherwise, go to next error in the REPL
buffer."
  (interactive "p")
  (if (>= (point) (geiser-repl--last-prompt-end))
      (or (completion-at-point)
          (lisp-indent-line))
    (compilation-next-error n)))

(defun geiser-repl--previous-error (n)
  "Go to previous error in the REPL buffer."
  (interactive "p")
  (compilation-next-error (- n)))

(defun geiser-repl-clear-buffer ()
  "Delete the output generated by the scheme process."
  (interactive)
  (let ((inhibit-read-only t))
    (delete-region (point-min) (geiser-repl--last-prompt-start))
    (when (< (point) (geiser-repl--last-prompt-end))
      (goto-char (geiser-repl--last-prompt-end)))
    (recenter t)))

(define-derived-mode geiser-repl-mode comint-mode "REPL"
  "Major mode for interacting with an inferior scheme repl process.
\\{geiser-repl-mode-map}"
  (scheme-mode-variables)
  (set (make-local-variable 'geiser-repl--last-output-start) (point-marker))
  (set (make-local-variable 'geiser-repl--last-output-end) (point-marker))
  (set (make-local-variable 'face-remapping-alist)
       '((comint-highlight-prompt geiser-font-lock-repl-prompt)
         (comint-highlight-input geiser-font-lock-repl-input)))
  (set (make-local-variable 'mode-line-process) nil)
  (set (make-local-variable 'comint-use-prompt-regexp) nil)
  (set (make-local-variable 'comint-prompt-read-only)
       geiser-repl-read-only-prompt-p)
  (setq comint-process-echoes nil)
  (set (make-local-variable 'beginning-of-defun-function)
       'geiser-repl--beginning-of-defun)
  (set (make-local-variable 'comint-input-ignoredups)
       geiser-repl-history-no-dups-p)
  (setq geiser-eval--get-module-function 'geiser-repl--module-function)
  (geiser-completion--setup t)
  (setq geiser-smart-tab-mode-string "")
  (geiser-smart-tab-mode t)

  (setq-local font-lock-fontify-region-function
              #'geiser-repl--wrap-fontify-region-function)
  (setq-local font-lock-unfontify-region-function
              #'geiser-repl--wrap-unfontify-region-function)

  ;; enabling compilation-shell-minor-mode without the annoying highlighter
  (compilation-setup t))

(define-key geiser-repl-mode-map "\C-d" 'delete-char)
(define-key geiser-repl-mode-map "\C-m" 'geiser-repl--maybe-send)
(define-key geiser-repl-mode-map [return] 'geiser-repl--maybe-send)
(define-key geiser-repl-mode-map "\C-j" 'geiser-repl--newline-and-indent)
(define-key geiser-repl-mode-map (kbd "TAB") 'geiser-repl-tab-dwim)
(define-key geiser-repl-mode-map [backtab] 'geiser-repl--previous-error)

(define-key geiser-repl-mode-map "\C-a" 'geiser-repl--bol)
(define-key geiser-repl-mode-map (kbd "<home>") 'geiser-repl--bol)

(geiser-menu--defmenu repl geiser-repl-mode-map
  ("Complete symbol" ((kbd "M-TAB"))
   completion-at-point :enable (geiser--symbol-at-point))
  ("Complete module name" ((kbd "C-.") (kbd "M-`"))
   geiser-completion--complete-module :enable (geiser--symbol-at-point))
  ("Edit symbol" "\M-." geiser-edit-symbol-at-point
   :enable (geiser--symbol-at-point))
  --
  ("Load scheme file..." "\C-c\C-l" geiser-load-file)
  ("Switch to module..." "\C-c\C-m" switch-to-geiser-module)
  ("Import module..." "\C-c\C-i" geiser-repl-import-module)
  ("Add to load path..." "\C-c\C-r" geiser-add-to-load-path)
  --
  ("Previous matching input" "\M-p" comint-previous-matching-input-from-input
   "Previous input matching current")
  ("Next matching input" "\M-n" comint-next-matching-input-from-input
   "Next input matching current")
  ("Previous prompt" "\C-c\C-p" geiser-repl-previous-prompt)
  ("Next prompt" "\C-c\C-n" geiser-repl-next-prompt)
  ("Previous input" "\C-c\M-p" comint-previous-input)
  ("Next input" "\C-c\M-n" comint-next-input)
  --
  ("Interrupt evaluation" ("\C-c\C-k" "\C-c\C-c" "\C-ck")
   geiser-repl-interrupt)
  --
  (mode "Autodoc mode" ("\C-c\C-da" "\C-c\C-d\C-a") geiser-autodoc-mode)
  ("Symbol documentation" ("\C-c\C-dd" "\C-c\C-d\C-d")
   geiser-doc-symbol-at-point
   "Documentation for symbol at point" :enable (geiser--symbol-at-point))
  ("Lookup symbol in manul" ("\C-c\C-di" "\C-c\C-d\C-i")
   geiser-doc-look-up-manual
   "Documentation for symbol at point" :enable (geiser--symbol-at-point))
  ("Module documentation" ("\C-c\C-dm" "\C-c\C-d\C-m") geiser-repl--doc-module
   "Documentation for module at point" :enable (geiser--symbol-at-point))
  --
  ("Clear buffer" "\C-c\M-o" geiser-repl-clear-buffer
   "Clean up REPL buffer, leaving just a lonely prompt")
  ("Kill Scheme interpreter" "\C-c\C-q" geiser-repl-exit
   :enable (geiser-repl--live-p))
  ("Restart" "\C-c\C-z" switch-to-geiser :enable (not (geiser-repl--live-p)))
  --
  (custom "REPL options" geiser-repl))

(define-key geiser-repl-mode-map [menu-bar completion] 'undefined)


;;; User commands

(defun run-geiser (impl)
  "Start a new Geiser REPL."
  (interactive
   (list (geiser-repl--get-impl "Start Geiser for scheme implementation: ")))
  (let ((buffer (current-buffer)))
    (geiser-repl--start-repl impl nil)
    (geiser-repl--maybe-remember-scm-buffer buffer)))

(defalias 'geiser 'run-geiser)

(defun geiser-connect (impl &optional host port)
  "Start a new Geiser REPL connected to a remote Scheme process."
  (interactive
   (list (geiser-repl--get-impl "Connect to Scheme implementation: ")))
  (let ((buffer (current-buffer)))
    (geiser-repl--start-repl impl
                             (geiser-repl--read-address host port))
    (geiser-repl--maybe-remember-scm-buffer buffer)))

(defun geiser-connect-local (impl socket)
  "Start a new Geiser REPL connected to a remote Scheme process
over a Unix-domain socket."
  (interactive
   (list (geiser-repl--get-impl "Connect to Scheme implementation: ")
         (expand-file-name (read-file-name "Socket file name: "))))
  (let ((buffer (current-buffer)))
    (geiser-repl--start-repl impl socket)
    (geiser-repl--maybe-remember-scm-buffer buffer)))

(make-variable-buffer-local
 (defvar geiser-repl--last-scm-buffer nil))

(defun geiser-repl--maybe-remember-scm-buffer (buffer)
  (when (and buffer
             (eq 'scheme-mode (with-current-buffer buffer major-mode))
             (eq major-mode 'geiser-repl-mode))
    (setq geiser-repl--last-scm-buffer buffer)))

(defun switch-to-geiser (&optional ask impl buffer)
  "Switch to running Geiser REPL.

If REPL is the current buffer, switch to the previously used
scheme buffer.

With prefix argument, ask for which one if more than one is running.
If no REPL is running, execute `run-geiser' to start a fresh one."
  (interactive "P")
  (let* ((impl (or impl geiser-impl--implementation))
         (in-repl (eq major-mode 'geiser-repl-mode))
         (in-live-repl (and in-repl (get-buffer-process (current-buffer))))
         (repl (unless ask
                 (if impl
                     (geiser-repl--repl/impl impl)
                   (or geiser-repl--repl (car geiser-repl--repls))))))
    (cond (in-live-repl
           (when (and (not (eq repl buffer))
                      (buffer-live-p geiser-repl--last-scm-buffer))
             (geiser-repl--switch-to-buffer geiser-repl--last-scm-buffer)))
          (repl (geiser-repl--switch-to-buffer repl))
          ((geiser-repl--remote-p)
           (geiser-connect impl (geiser-repl--host) (geiser-repl--port)))
          ((geiser-repl--local-p)
           (geiser-connect-local impl geiser-repl--address))
	  (impl (run-geiser impl))
          (t (call-interactively 'run-geiser)))
    (geiser-repl--maybe-remember-scm-buffer buffer)))

(defun switch-to-geiser-module (&optional module buffer)
  "Switch to running Geiser REPL and try to enter a given module."
  (interactive)
  (let* ((module (or module
                     (geiser-completion--read-module
                      "Switch to module (default top-level): ")))
         (cmd (and module
                   (geiser-repl--enter-cmd geiser-impl--implementation
                                           module))))
    (unless (eq major-mode 'geiser-repl-mode)
      (switch-to-geiser nil nil (or buffer (current-buffer))))
    (geiser-repl--send cmd)))

(defun geiser-repl-import-module (&optional module)
  "Import a given module in the current namespace of the REPL."
  (interactive)
  (let* ((module (or module
                     (geiser-completion--read-module "Import module: ")))
         (cmd (and module
                   (geiser-repl--import-cmd geiser-impl--implementation
                                            module))))
    (switch-to-geiser nil nil (current-buffer))
    (geiser-repl--send cmd)))

(defun geiser-repl-exit (&optional arg)
  "Exit the current REPL.
With a prefix argument, force exit by killing the scheme process."
  (interactive "P")
  (when (or (not geiser-repl-query-on-exit-p)
            (y-or-n-p "Really quit this REPL? "))
    (geiser-con--connection-deactivate geiser-repl--connection t)
    (let ((cmd (and (not arg)
                    (geiser-repl--exit-cmd geiser-impl--implementation))))
      (if cmd
          (when (stringp cmd) (geiser-repl--send cmd))
        (comint-kill-subjob)))))

(defun geiser-repl-next-prompt (n)
  (interactive "p")
  (when (> n 0)
    (end-of-line)
    (re-search-forward comint-prompt-regexp nil 'go n)))

(defun geiser-repl-previous-prompt (n)
  (interactive "p")
  (when (> n 0)
    (end-of-line 0)
    (when (re-search-backward comint-prompt-regexp nil 'go n)
      (goto-char (match-end 0)))))


;;; Unload:

(defun geiser-repl--repl-list ()
  (let (lst)
    (dolist (repl geiser-repl--repls lst)
      (when (buffer-live-p repl)
        (with-current-buffer repl
          (push (cons geiser-impl--implementation
                      geiser-repl--address)
                lst))))))

(defun geiser-repl--restore (impls)
  (dolist (impl impls)
    (when impl
      (condition-case err
          (geiser-repl--start-repl (car impl) (cdr impl))
        (error (message (error-message-string err)))))))

(defun geiser-repl-unload-function ()
  (dolist (repl geiser-repl--repls)
    (when (buffer-live-p repl)
      (with-current-buffer repl
        (let ((geiser-repl-query-on-exit-p nil)) (geiser-repl-exit))
        (sit-for 0.05)
        (kill-buffer)))))


(provide 'geiser-repl)


;;; Initialization:
;; After providing 'geiser-repl, so that impls can use us.
(mapc 'geiser-impl--load-impl geiser-active-implementations)
