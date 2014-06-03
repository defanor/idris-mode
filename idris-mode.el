;;; idris-mode.el --- Major mode for editing Idris code -*- lexical-binding: t -*-

;; Copyright (C) 2013

;; Author:
;; URL: https://github.com/idris-hackers/idris-mode
;; Keywords: languages
;; Package-Requires: ((emacs "24"))


;;; Commentary:

;; This is an Emacs mode for editing Idris code. It requires the latest
;; version of Idris, and some features may rely on the latest Git version of
;; Idris.

;;; Code:

(require 'idris-core)
(require 'idris-settings)
(require 'idris-syntax)
(require 'idris-indentation)
(require 'idris-simple-indent)
(require 'idris-repl)
(require 'idris-commands)
(require 'idris-warnings)
(require 'idris-common-utils)
(require 'idris-ipkg-mode)
(require 'eldoc)


(defvar idris-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-l") 'idris-load-file)
    (define-key map (kbd "C-c C-n") 'idris-load-forward-line)
    (define-key map (kbd "C-c C-p") 'idris-load-backward-line)
    (define-key map (kbd "C-c C-t") 'idris-type-at-point)
    (define-key map (kbd "C-c C-d C-d") 'idris-docs-at-point)
    (define-key map (kbd "C-c C-d d") 'idris-docs-at-point)
    (define-key map (kbd "C-c C-d C-a") 'idris-apropos)
    (define-key map (kbd "C-c C-d a") 'idris-apropos)
    (define-key map (kbd "C-c C-d C-t") 'idris-type-search)
    (define-key map (kbd "C-c C-d t") 'idris-type-search)
    (define-key map (kbd "C-c C-c") 'idris-case-split)
    (define-key map (kbd "C-c C-m") 'idris-add-missing)
    (define-key map (kbd "C-c C-e") 'idris-make-lemma)
    (define-key map (kbd "C-c C-s") 'idris-add-clause)
    (define-key map (kbd "C-c C-w") 'idris-make-with-block)
    (define-key map (kbd "C-c C-a") 'idris-proof-search)
    (define-key map (kbd "C-c C-r") 'idris-refine)
    (define-key map (kbd "C-c _") 'idris-insert-bottom)
    (define-key map (kbd "C-c C-b C-b") 'idris-ipkg-build)
    (define-key map (kbd "C-c C-b b") 'idris-ipkg-build)
    (define-key map (kbd "C-c C-b C-c") 'idris-ipkg-clean)
    (define-key map (kbd "C-c C-b c") 'idris-ipkg-clean)
    (define-key map (kbd "C-c C-b C-i") 'idris-ipkg-install)
    (define-key map (kbd "C-c C-b i") 'idris-ipkg-install)
    (define-key map (kbd "C-c C-b C-p") 'idris-open-package-file)
    (define-key map (kbd "C-c C-b p") 'idris-open-package-file)
    (define-key map (kbd "C-c C-z") 'idris-pop-to-repl)
    (define-key map (kbd "C-c f") 'idris-next-hole)
    (define-key map (kbd "C-c b") 'idris-previous-hole)
    (define-key map (kbd "C-c r") 'idris-refine-hole)
    (define-key map (kbd "RET") 'idris-newline-and-indent)
    map)
  "Keymap used in Idris mode.")

(easy-menu-define idris-mode-menu idris-mode-map
  "Menu for the Idris major mode"
  `("Idris"
    ["New Project" idris-start-project t]
    "-----------------"
    ["Load file" idris-load-file t]
    ["Choose packages" idris-set-idris-packages t]
    ["Compile and execute" idris-compile-and-execute]
    ["Delete IBC file" idris-delete-ibc t]
    ["View compiler log" idris-view-compiler-log (get-buffer idris-log-buffer-name)]
    ["Quit inferior idris process" idris-quit t]
    "-----------------"
    ["Add initial match clause to type declaration" idris-add-clause t]
    ["Add missing cases" idris-add-missing t]
    ["Case split pattern variable" idris-case-split t]
    ["Add with block" idris-make-with-block t]
    ["Attempt to solve metavariable" idris-proof-search t]
    ["Display type" idris-type-at-point t]
    "-----------------"
    ["Open package" idris-open-package-file t]
    ["Build package" idris-ipkg-build t]
    ["Install package" idris-ipkg-install t]
    ["Clean package" idris-ipkg-clean t]
    "-----------------"
    ["Get documentation" idris-docs-at-point t]
    ["Search for type" idris-type-search t]
    ["Apropos" idris-apropos t]
    "-----------------"
    ("Interpreter options" :active idris-process
     ["Show implicits" (idris-set-option :show-implicits t)
      :visible (not (idris-get-option :show-implicits))]
     ["Hide implicits" (idris-set-option :show-implicits nil)
      :visible (idris-get-option :show-implicits)]
     ["Show error context" (idris-set-option :error-context t)
      :visible (not (idris-get-option :error-context))]
     ["Hide error context" (idris-set-option :error-context nil)
      :visible (idris-get-option :error-context)])
    ["Customize idris-mode" (customize-group 'idris) t]
    ))


;;;###autoload
(define-derived-mode idris-mode prog-mode "Idris"
  "Major mode for Idris
     \\{idris-mode-map}
Invokes `idris-mode-hook'."
  :syntax-table idris-syntax-table
  :group 'idris
  (set (make-local-variable 'font-lock-defaults)
       (idris-font-lock-defaults))
  (set (make-local-variable 'indent-tabs-mode) nil)
  (set (make-local-variable 'comment-start) "--")

  ; REPL completion for Idris source
  (set (make-local-variable 'completion-at-point-functions) '(idris-complete-symbol-at-point))

  ; imenu support
  (set (make-local-variable 'imenu-case-fold-search) nil)
  (set (make-local-variable 'imenu-generic-expression)
       '(("Data" "^\\s-*data\\s-+\\(\\sw+\\)" 1)
         ("Data" "^\\s-*record\\s-+\\(\\sw+\\)" 1)
         ("Data" "^\\s-*codata\\s-+\\(\\sw+\\)" 1)
         ("Postulates" "^\\s-*postulate\\s-+\\(\\sw+\\)" 1)
         ("Classes" "^\\s-*class\\s-+\\(\\sw+\\)" 1)
         (nil "^\\s-*\\(\\sw+\\)\\s-*:" 1)
         ("Namespaces" "^\\s-*namespace\\s-+\\(\\sw\\|\\.\\)" 1)))

  ; eldoc support
  (set (make-local-variable 'eldoc-documentation-function) 'idris-eldoc-lookup)

  ; Filling of comments and docs
  (set (make-local-variable 'fill-paragraph-function) 'idris-fill-paragraph)
  ; Make dirty if necessary
  (add-hook 'after-change-functions 'idris-possibly-make-dirty)
  (setq mode-name `("Idris"
                    (:eval (if idris-rex-continuations "!" ""))
                    " "
                    (:eval (if (idris-current-buffer-dirty-p)
                               "(Not loaded)"
                             "(Loaded)")))))

;; Automatically use idris-mode for .idr and .lidr files.
;;;###autoload
(push '("\\.idr$" . idris-mode) auto-mode-alist)
;;;###autoload
(push '("\\.lidr$" . idris-mode) auto-mode-alist)


;;; Handy utilities for other modes
;;;###autoload
(eval-after-load 'flycheck
  '(progn
     (flycheck-define-checker idris
       "An Idris syntax and type checker."
       :command ("idris" "--check" "--nocolor" "--warnpartial" source)
       :error-patterns
       ((warning line-start (file-name) ":" line ":" column ":Warning - "
                 (message (and (* nonl) (* "\n" (not (any "/" "~")) (* nonl)))))
        (error line-start (file-name) ":" line ":" column ":"
               (message (and (* nonl) (* "\n" (not (any "/" "~")) (* nonl))))))
       :modes idris-mode)

     (add-to-list 'flycheck-checkers 'idris)))

(provide 'idris-mode)
;;; idris-mode.el ends here
