;;; idris-warnings-tree.el --- Tree view of warnings reported by idris in buffers -*- lexical-binding: t -*-

;; Copyright (C) 2014 Hannes Mehnert

;; Author: Hannes Mehnert <hannes@mehnert.org>
;; (modified slime-compiler-notes-tree.el by Helmut Eller <heller@common-lisp.net>)

;; License:
;; Inspiration is taken from SLIME/DIME (http://common-lisp.net/project/slime/) (https://github.com/dylan-lang/dylan-mode)
;; Therefore license is GPL

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING. If not, write to
;; the Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

`
(require 'idris-core)
(require 'idris-warnings)
(require 'idris-common-utils)

(defvar idris-notes-buffer-name (idris-buffer-name :notes)
  "The name of the buffer containing Idris errors")

(defun idris-list-compiler-notes ()
  "Show the compiler notes in tree view."
  (interactive)
  (with-temp-message "Preparing compiler note tree..."
    (let ((notes (reverse idris-raw-warnings))
          (buffer (get-buffer-create idris-notes-buffer-name)))
      (with-current-buffer buffer
        (idris-compiler-notes-mode)
        (setq buffer-read-only nil)
        (erase-buffer)
        (if (null notes)
            nil
          (let ((root (idris-compiler-notes-to-tree notes)))
            (idris-tree-insert root "")
            (insert "\n")
            (message "Press q to close, return or mouse on error to navigate to source")
            (setq buffer-read-only t)
            (goto-char (point-min))
            notes))))))

(defvar idris-tree-printer 'idris-tree-default-printer)

(defun idris-tree-for-note (note)
  (let* ((buttonp (> (length (nth 0 note)) 0)) ;; if empty source location
         (button-text `(,(format "%s line %s col %s:" (nth 0 note) (nth 1 note) (nth 2 note))
                               help-echo "go to source location"
                               action ,#'(lambda (_)
                                           (idris-show-source-location (nth 0 note)
                                                                       (nth 1 note)
                                                                       (nth 2 note))))))
    (make-idris-tree :item (nth 3 note)
                     :highlighting (if (> (length note) 4) (nth 4 note) '())
                     :button (if buttonp button-text nil)
                     :after-button (if buttonp "\n" nil)
                     :plist (list 'note note)
                     :print-fn idris-tree-printer)))

(defun idris-compiler-notes-to-tree (notes)
  (make-idris-tree :item (format "Errors (%d)" (length notes))
                   :kids (mapcar #'idris-tree-for-note notes)))

(defvar idris-compiler-notes-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "q") 'idris-notes-quit)
    (define-key map (kbd "C-c C-t") 'idris-type-at-point)
    (define-key map (kbd "C-c C-d") 'idris-type-at-point)
    map)
  "Keymap used in Idris Compiler Notes mode.")

(defun idris-notes-quit ()
  (interactive)
  (idris-kill-buffer :notes))

(define-derived-mode idris-compiler-notes-mode fundamental-mode "Compiler-Notes"
  "Idris compiler notes
     \\{idris-compiler-notes-mode-map}
Invokes `idris-compiler-notes-mode-hook'.")

(defun idris-compiler-notes-show-details ()
  (interactive)
  (let* ((tree (idris-tree-at-point))
         (note (plist-get (idris-tree.plist tree) 'note))
         (inhibit-read-only t))
    (cond ((not (idris-tree-leaf-p tree))
           (idris-tree-toggle tree))
          (t
           (idris-show-source-location (nth 0 note) (nth 1 note) (nth 2 note))))))

(defun idris-show-source-location (filename lineno col)
  (idris-goto-source-location filename lineno col))

(defun idris-goto-location (filename)
  "Opens buffer for filename"
  (let ((fullpath (concat idris-process-current-working-directory filename)))
    (or (get-buffer filename)
        (get-file-buffer fullpath)
        (find-file-noselect fullpath))))

(defun idris-goto-source-location (filename lineno col)
  "Move to the source location FILENAME LINENO COL."
  (let ((buf (idris-goto-location filename)))
    (set-buffer buf)
    (pop-to-buffer buf t)
    (goto-char (point-min))
    (let ((start (line-beginning-position lineno)))
      (goto-char (+ start col)))))


;;;;;; Tree Widget

(cl-defmacro with-struct ((conc-name &rest slots) struct &body body)
  "Like with-slots but works only for structs.
\(fn (CONC-NAME &rest SLOTS) STRUCT &body BODY)"
  (declare (indent 2))
  (let ((struct-var (cl-gensym "struct")))
    `(let ((,struct-var ,struct))
       (symbol-macrolet
           ,(mapcar (lambda (slot)
                      (etypecase slot
                        (symbol `(,slot (,(intern (concat (symbol-name conc-name) (symbol-name slot))) ,struct-var)))
                        (cons `(,(first slot) (,(intern (concat (symbol-name conc-name) (symbol-name (second slot))))
                                               ,struct-var)))))
                    slots)
         . ,body))))

(cl-defstruct (idris-tree (:conc-name idris-tree.))
  item
  highlighting
  (print-fn #'idris-tree-default-printer :type function)
  (kids '() :type (or list function))
  (collapsed-p nil :type boolean)
  (prefix "" :type string)
  (start-mark nil)
  (end-mark nil)
  (plist '() :type list)
  (active-p t :type boolean)
  (button nil :type list)
  (after-button "" :type string))

(defun idris-tree-leaf-p (tree)
  ;; Evaluate the kids to see if we are at a leaf
  (when (functionp (idris-tree.kids tree))
    (setf (idris-tree.kids tree) (funcall (idris-tree.kids tree))))
  (assert (listp (idris-tree.kids tree)))
  (null (idris-tree.kids tree)))

(defun idris-tree-default-printer (tree)
  (when (idris-tree.button tree)
    (apply #'insert-button (idris-tree.button tree))
    (insert (idris-tree.after-button tree)))
  (idris-propertize-spans (idris-repl-semantic-text-props (idris-tree.highlighting tree))
    (insert (idris-tree.item tree))))

(defun idris-tree-decoration (tree)
  (cond ((idris-tree-leaf-p tree) "--")
	((idris-tree.collapsed-p tree) "[+]")
	(t "- +")))

(defun idris-tree-insert-list (list prefix)
  "Insert a list of trees."
  (loop for (elt . rest) on list
	do (cond (rest
		  (insert prefix " |")
		  (idris-tree-insert elt (concat prefix " |"))
                  (insert "\n"))
		 (t
		  (insert prefix " `")
		  (idris-tree-insert elt (concat prefix "  "))))))

(defun idris-tree-insert-decoration (tree)
  (with-struct (idris-tree. print-fn kids collapsed-p start-mark end-mark active-p) tree
    (let ((deco (idris-tree-decoration tree)))
      (if (and active-p kids)
          (insert-button deco 'action #'(lambda (_)
                                          (setq buffer-read-only nil)
                                          (idris-tree-toggle tree)
                                          (setq buffer-read-only t))
                              'help-echo (if collapsed-p "expand" "collapse"))
        (insert deco))
      (insert " "))))

(defun idris-tree-indent-item (start end prefix)
  "Insert PREFIX at the beginning of each but the first line.
This is used for labels spanning multiple lines."
  (save-excursion
    (goto-char end)
    (beginning-of-line)
    (while (< start (point))
      (insert-before-markers prefix)
      (forward-line -1))))

(defun idris-tree-insert (tree prefix)
  "Insert TREE prefixed with PREFIX at point."
  (unless (idris-tree-p tree) (error "%s is not an idris-tree" tree))
  (with-struct (idris-tree. print-fn kids collapsed-p start-mark end-mark active-p) tree
    (let ((line-start (line-beginning-position)))
      (setf start-mark (point-marker))
      (idris-tree-insert-decoration tree)
      (funcall print-fn tree)
      (idris-tree-indent-item start-mark (point) (concat prefix "   "))
      (add-text-properties line-start (point) (list 'idris-tree tree))
      (set-marker-insertion-type start-mark t)
      (when  (not collapsed-p)
        (when (functionp kids)
          (setf kids (funcall kids))
          (assert (listp kids)))
        (when kids
          (terpri (current-buffer))
          (idris-tree-insert-list kids prefix)))
      (setf (idris-tree.prefix tree) prefix)
      (setf end-mark (point-marker)))))

(defun idris-tree-at-point ()
  (cond ((get-text-property (point) 'idris-tree))
        (t (error "No tree at point"))))

(defun idris-tree-delete (tree)
  "Delete the region for TREE."
  (delete-region (idris-tree.start-mark tree)
                 (idris-tree.end-mark tree)))

(defun idris-tree-toggle (tree)
  "Toggle the visibility of TREE's children."
  (with-struct (idris-tree. collapsed-p start-mark end-mark prefix) tree
    (save-excursion
      (setf collapsed-p (not collapsed-p))
      (goto-char start-mark)
      (idris-tree-delete tree)
      (insert-before-markers " ") ; move parent's end-mark
      (backward-char 1)
      (idris-tree-insert tree prefix)
      (delete-char 1))
    (goto-char start-mark)))

(provide 'idris-warnings-tree)
