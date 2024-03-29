;;; -*- lexical-binding: t; -*-
;;; tasklist.el -- Make a list of commands; pick one and run it in a dedicated frame or window

;;; This is a "simplified" version of cmake-build.el, without all the cmake
;;; stuff.  Instead, make a list of commands and run them, with similar output
;;; to frame/window.
;;;
;;; (One might notice that, in fact, this is still the vast majority of
;;; cmake-build.el, and the majority of said code is just making the
;;; windows/frames work...)

;; Copyright (C) 2020-  Ryan Pavlik

;; Author: Ryan Pavlik <rpavlik@gmail.com>
;; URL: https://github.com/rpav/tasklist.el
;; Version: 1.0

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

(require 'cl-lib)
(require 'tramp)

(defgroup tasklist ()
  "Make a list of commands/tasks and run them in a dedicated window/frame."
  :group 'tools)

(defcustom tasklist-local-options-file
  (expand-file-name "tasklist-options.el" user-emacs-directory)
  "Store host/user-local tasklist options."
  :group 'tasklist)

(defcustom tasklist-display-type 'split
  "How to display tasklist output; 'split' will split the
window (using tasklist window splitting options), 'frame' will
create a new frame.  In all cases, the buffers will be reused if
they are visible, regardless of current display type."
  :type 'symbol
  :group 'tasklist
  :options '(split frame))

(defcustom tasklist-raise-frame t
  "Whether to raise the frame of the build window on build. This
only applies if `tasklist-display-type` is frame."
  :type 'boolean
  :group 'tasklist)

(defcustom tasklist-variable-alist nil
  "An ALIST of variables to replace in strings.  Setting a variable `foo` will let you refer to it as `%foo` in
most strings.  No lisp EVAL is performed!"
  :type '(alist :key-type string :value-type string)
  :group 'tasklist)

(defcustom tasklist-override-compile-keymap t
  "Whether to use tasklist-run-keymap for the compile window as well.
This more or less provides specific/consistent behavior for
quitting the frame or window."
  :type 'boolean
  :group 'tasklist)

(defcustom tasklist-quit-frame-type 'lower
  "How to handle the frame when quitting."
  :type 'symbol
  :group 'tasklist
  :options '(lower delete))

(defcustom tasklist-quit-kills-process nil
  "If tasklist-quit-window also kills the process when quitting."
  :type 'boolean
  :group 'tasklist)

(defcustom tasklist-run-window-size 20
  "Size of window to split."
  :type 'integer
  :group 'tasklist)

(defcustom tasklist-split-threshold 40.0
  "Threshold (percentage) at which to *not* split the current window, but instead use the other window.  That
is, if `tasklist-run-window-size` is greater than this percentage of the current window, it will not be
split."
  :type 'float
  :group 'tasklist)

(defcustom tasklist-never-split nil
  "Never split the window, instead always use the other window."
  :type 'boolean
  :group 'tasklist)


;;; These are very temporary and likely very host-specific variables,
;;; not something we want to constantly modify in custom.el
(defvar tasklist-project-root nil
  "Optionally, set this to the emacs-wide root of the current project.  Setting this to NIL will use
`projectile-project-root` to determine the root on a buffer-local basis, instead.")

(defvar tasklist-project-default nil
  "Optionally, set this to an emacs-wide root of a _default_ project.  Unlike `tasklist-project-root`, which
will override any project, `tasklist-project-default` will only apply if no other project-root is found.")

(defvar tasklist-run-keymap (make-sparse-keymap))

(defun tasklist-quit-window ()
  (interactive)
  (when (and tasklist-quit-kills-process
             (get-buffer-process (current-buffer)))
    (tasklist-kill-buffer-process))
  (if (= 1 (length (window-list)))
      (cl-case tasklist-quit-frame-type
        (lower (lower-frame))
        (delete (delete-frame)))
    (delete-window)))

(defun tasklist-kill-buffer-process (&optional buffer)
  (interactive)
  (let* ((buffer (get-buffer (or buffer (current-buffer))))
         (p (get-buffer-process buffer)))
    (when p
      (with-current-buffer buffer
        (cl-case major-mode
          (shell-mode (kill-process p))
          (compilation-mode (kill-compilation)))))))

(defun tasklist-kill-processes ()
  (interactive)
  (tasklist-kill-buffer-process (tasklist--task-buffer-name))
  (tasklist-kill-buffer-process (tasklist--run-buffer-name)))

(let ((map tasklist-run-keymap))
  (define-key map (kbd "q") 'tasklist-quit-window)
  (define-key map (kbd "C-c C-c") 'tasklist-kill-buffer-process))

(defun tasklist-string-subst (str &optional args)
  (when (and str (string-match "\\([^\\]\\)%" str))
    (cl-flet ((replace-one (s var value)
                (replace-regexp-in-string (concat "\\([^\\]\\)%" (regexp-quote var)) (concat "\\1" value) s)))
      (cl-loop
            for i from 1
            for p in args
            do (setq str (replace-one str (number-to-string i) p)))
      (dolist (variable-list (tasklist--get-vars))
        (dolist (var-value variable-list)
          (setq str (replace-one str (car var-value) (cdr var-value)))))))
  str)

(cl-defmacro tasklist--with-file ((filename &key readp writep) &body body)
  (declare (indent 1))
  `(with-temp-buffer
     (prog1
         ,(if readp
              `(when (file-exists-p ,filename)
                 (insert-file-contents ,filename)
                 ,@body)
            `(progn ,@body))
       (when ,writep
         (write-region 1 (point-max) ,filename)))))

(cl-defmacro tasklist--with-options-file ((&key readp writep) &body body)
  (declare (indent 1))
  `(tasklist--with-file (tasklist-local-options-file :readp ,readp :writep ,writep) ,@body))

(defun tasklist--has-tasklist-el (path)
  (when path
    (and (file-exists-p (concat (file-name-as-directory path) ".tasklist.el"))
         path)))

(defun tasklist--project-root ()
  (or (tasklist--has-tasklist-el tasklist-project-root)
      (tasklist--has-tasklist-el (projectile-project-root))
      (tasklist--has-tasklist-el tasklist-project-default)))

(defun tasklist--maybe-remote-project-root ()
  "Return current project root path, suitable for remote invocations too."
  (let* ((project-root-raw (tasklist--project-root))
         (project-root
          (file-name-as-directory
           (if (tramp-tramp-file-p project-root-raw)
               (let ((parsed-root (tramp-dissect-file-name project-root-raw)))
                 (tramp-file-name-localname parsed-root))
             (expand-file-name project-root-raw)))))
    (concat project-root (or (tasklist--source-root) ""))))

(cl-defmacro tasklist--save-project-root (nil &body body)
  (declare (indent 1))
  `(let ((tasklist-project-root (tasklist--project-root)))
     ,@body))

(defun tasklist--read-options ()
  (tasklist--with-options-file (:readp t)
    (let* ((form (read (buffer-string)))
           (task-project-root (cadr (assoc :task-project-root form))))
      (setq tasklist-project-root (or task-project-root tasklist-project-root)))))

(defun tasklist--read-project-data ()
  (let ((project-data-path (concat (file-name-as-directory (tasklist--project-root)) ".tasklist.el")))
    (tasklist--with-file (project-data-path :readp t)
      (read (buffer-string)))))

(defun tasklist--write-options ()
  (tasklist--with-options-file (:writep t)
    (print `((:task-project-root ,tasklist-project-root))
           (current-buffer))))

(defun tasklist--validity ()
  (cond
    ((not (tasklist--project-root)) :data-missing)
    ((null (tasklist--get-project-data)) :data-missing)
    (t t)))

(defun tasklist--validate (&optional tag)
  (not
   (cl-case (tasklist--validity)
     (:data-missing
      (message "tasklist: Not a valid project; no .tasklist.el data found (project root is %s)"
               (tasklist--project-root)))
     (t nil))))

(defun tasklist-project-name ()
  (let ((default-directory (tasklist--project-root)))
    (projectile-project-name)))

(defun tasklist--task-buffer-name (task-id)
  (concat "*Task: " (tasklist-project-name) "/" (tasklist--get-task-window task-id) "*"))

(defun tasklist--get-project-data ()
  (tasklist--read-project-data))

(defun tasklist--get-common ()
  (when (tasklist--project-root)
    (cdr (assoc 'common (tasklist--get-project-data)))))

(defun tasklist--get-tasks ()
  (when (tasklist--project-root)
    (cdr (assoc 'tasks (tasklist--get-project-data)))))

(defun tasklist--get-vars ()
  (let ((common (tasklist--get-common)))
    (list (cdr (assoc :variables common))
          tasklist-variable-alist)))

(defun tasklist--get-task (task)
  (cdr (assoc task (tasklist--get-tasks))))

(defun tasklist--get-task-env (task-id)
  (let ((task (tasklist--get-task task-id))
        (common (tasklist--get-common)))
    (append
     (cdr (assoc :env task))
     (cdr (assoc :env common)))))

(defun tasklist--get-task-name (task-id)
  (let ((task (tasklist--get-task task-id)))
    (or (tasklist-string-subst (cadr (assoc :name task)))
        (symbol-name task-id))))

(defun tasklist--get-task-window (task-id)
  (let ((task (tasklist--get-task task-id))
        (common (tasklist--get-common)))
    (or (tasklist-string-subst
         (or (cadr (assoc :window task))
             (cadr (assoc :window common))))
        (tasklist--get-task-name task-id))))

(defun tasklist--get-task-default-args (task-id)
  (let ((task (tasklist--get-task task-id)))
    (cdr (assoc :default-args task))))

(defun tasklist-get-task-cwd (task-id)
  (let* ((task (tasklist--get-task task-id))
         (common (tasklist--get-common))
         (root (tasklist--project-root))
         (cwd (or (cadr (assoc :cwd task))
                  (cadr (assoc :cwd common)))))
    (tasklist-string-subst
     (if cwd
         (if (file-name-absolute-p cwd)
             cwd
           (concat root cwd))
       root))))

(defun tasklist--get-task-shell (task-id)
  (let* ((task (tasklist--get-task task-id))
         (common (tasklist--get-common))
         (shell (or (cadr (assoc :shell task))
                    (cadr (assoc :shell common)))))
    (tasklist-string-subst shell)))

(defun tasklist--get-task-display-type (task-id)
  (let ((task (tasklist--get-task task-id)))
    (or (cadr (assoc :display task))
        tasklist-display-type)))

(defun tasklist--get-task-command (task-id)
  (let* ((task (tasklist--get-task task-id)))
    (tasklist-string-subst (string-join (cdr (assoc :command task)) " ")
                           (tasklist--get-task-default-args task-id))))

(defun tasklist--compose-task-commands (task-id &optional deps)
  (let* ((cmd (tasklist--get-task-command task-id)))
    (list cmd)))

(defun tasklist--split-to-buffer (name)
  (let* ((window-point-insertion-type t)
         (buffer (get-buffer-create name))
         (current-buffer-window (get-buffer-window))
         (new-buffer-window (get-buffer-window name))
         (split-is-current (eql current-buffer-window new-buffer-window)))
    (when (or
           (and (not tasklist-never-split)
                (not split-is-current)
                (<= tasklist-run-window-size
                    (* (/ tasklist-split-threshold 100.0)
                       (window-total-height current-buffer-window)))))
      (when (and (not (get-buffer-window name t)))
        (let ((window (split-window-below (- tasklist-run-window-size))))
          (set-window-buffer window buffer)
          ;;(set-window-dedicated-p window t)
          ))
      t)))

(defun tasklist--popup-buffer (name)
  (let* ((buffer (get-buffer-create name))
         (current-buffer-window (get-buffer-window buffer t)))
    (unless current-buffer-window
      (display-buffer-pop-up-frame buffer default-frame-alist))
    (when tasklist-raise-frame
      (raise-frame (window-frame (get-buffer-window buffer t))))
    t))

(defun tasklist--background-buffer (name)
  (get-buffer-create name)
  nil)

(defun tasklist--display-buffer (task-id buffer-name)
  (let* ((display-type (tasklist--get-task-display-type task-id)))
    (cl-ecase display-type
      (split (tasklist--split-to-buffer buffer-name))
      (frame (tasklist--popup-buffer buffer-name))
      (none (tasklist--background-buffer buffer-name)))))

(defun tasklist--buffer-filter (process output buffer)
  (let* ((max (buffer-size buffer)))
    (dolist (w (get-buffer-window-list buffer nil t))
      (with-selected-window w (set-window-point w (1+ max)))
      (with-current-buffer buffer (goto-char (1+ max))))))

(cl-defun tasklist--invoke (task-id buffer-name command &key sentinel)
  (let* ((did-split (tasklist--display-buffer task-id buffer-name))
         (buffer (get-buffer buffer-name))
         (display-buffer-alist
          ;; Suppress the window only if we actually split
          (if did-split
              (cons (list buffer-name #'display-buffer-no-window)
                    display-buffer-alist)
            display-buffer-alist))
         (actual-directory (tasklist-get-task-cwd task-id))
         (shell (tasklist--get-task-shell task-id))
         (command (if shell
                      (replace-regexp-in-string "\\([^\\]\\)%s" (concat "\\1" command) shell)
                    command)))
    (if (get-buffer-process buffer)
        (message "Already running task in window: %s" buffer)
      ;; compile saves buffers; rely on this now
      (let* ((compilation-buffer-name-function (lambda (&rest r) buffer)))
        (cl-flet ((run-compile ()
                    (setq-local compilation-directory actual-directory)
                    (let ((display-buffer-overriding-action '(display-buffer-no-window))
                          (default-directory actual-directory)
                          (process-environment
                           (append (tasklist--get-task-env task-id)
                                   process-environment)))
                      (compile (concat "time " command)))))
          (let ((w (get-buffer-window buffer t)))
            (if (and w (not (eql (get-buffer-window) w)))
                (with-selected-window w
                  (run-compile))
              (run-compile))))
        (let* ((process (get-buffer-process buffer))
               (old-filter (process-filter process))
               (old-sentinel (process-sentinel process)))
          (set-process-sentinel process (lambda (p e)
                                          (when sentinel (funcall sentinel p e))
                                          (funcall old-sentinel p e)))
          (set-process-filter process (lambda (p o)
                                        (funcall old-filter p o)
                                        (tasklist--buffer-filter p o buffer))))
        (with-current-buffer buffer-name
          (mapcar (lambda (w)
                    (set-window-point w (point-max)))
                  (get-buffer-window-list buffer-name nil t))
          (when tasklist-override-compile-keymap
            (use-local-map tasklist-run-keymap)))))))

(defun tasklist-set-project-root (path)
  (interactive
   (list
    (let* ((default-directory (tasklist--project-root)))
      (read-directory-name "Task project root (blank to unset): "))))
  (setq tasklist-project-root (if (string= path "") nil path)))

(defun tasklist-set-project-default (path)
  (interactive
   (list
    (let* ((default-directory (tasklist--project-root)))
      (read-directory-name "Task default project (blank to unset): "))))
  (setq tasklist-project-default (if (string= path "") nil path)))

(defun tasklist-run-task (&optional task-id)
  (interactive
   (list
    (let* ((tasks (tasklist--get-tasks))
           (choices (mapcar (lambda (x) (symbol-name (car x))) tasks)))
      (intern (ido-completing-read "Run task: " choices nil t nil nil nil)))))
  (let ((task-cwd (tasklist-get-task-cwd task-id)))
    (unless (file-directory-p task-cwd)
      (when (y-or-n-p (format "Task cwd %s does not exist, create?" task-cwd))
        (make-directory task-cwd)))
    (let* ((buffer-name (tasklist--task-buffer-name task-id))
           (command-list (tasklist--compose-task-commands task-id)))
      (mapcar (lambda (cmd)
                (tasklist--invoke task-id buffer-name cmd))
              command-list))))

(defun tasklist-delete-current-windows ()
  "Delete the compile/run windows for the current run configuration"
  (interactive)
  (cl-flet ((f (name)
              (when-let ((b (get-buffer name)))
                (mapcar #'delete-window (get-buffer-window-list b nil t)))))
    (f (tasklist--task-buffer-name))
    (f (tasklist--run-buffer-name))))

;;;; Menu stuff

(defun tasklist--menu-tasks ()
  `((keymap nil
            ,@(mapcar (lambda (x)
                        (let ((name (car x)))
                          (list x 'menu-item
                                (concat (tasklist--get-task-name name) " [" (symbol-name name) "]") t)))
                      (tasklist--get-tasks)))))


(defun tasklist--menu ()
  `(,@(when (tasklist--get-tasks)
        (tasklist--menu-tasks))
      (menu-item "--")
      (:info menu-item "Project Info" t)
      ;; Not used right now
      ,@(when nil
          (nil menu-item "Tools"
               (keymap nil
                       ;;(:set-buffer-local menu-item "Set buffer-local default task" t)
                       )))))

(defun tasklist--popup-menu ()
  (x-popup-menu
   (list '(10 10) (selected-window))
   `(keymap "Task List" ,@(tasklist--menu))))

(defun tasklist--menu-action-dispatch (action)
  (cl-case (car action)
    (:info (message "Project root: %s" (tasklist--project-root)))
    (:set-root (call-interactively #'tasklist-set-project-root))
    (otherwise (tasklist-run-task (car action)))))

(defun tasklist-menu ()
  (interactive)
  (tasklist--menu-action-dispatch
   (tasklist--popup-menu)))

(tasklist--read-options)
(add-hook 'kill-emacs-hook #'tasklist--write-options)

(provide 'tasklist)
