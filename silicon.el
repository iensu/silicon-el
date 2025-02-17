;;; silicon.el --- Generate images from source files. -*- lexical-binding: t -*-

;; Author: Jens Östlund
;; Maintainer: Jens Östlund
;; Homepage: https://github.com/iensu/silicon-el
;; Version: 1
;; Package-Requires: ((emacs "25"))

;; This file is not part of GNU Emacs.

;;; License:

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Convenience package for creating images of the current source buffer
;; using Silicon <https://github.com/Aloxaf/silicon>. It requires you to
;; have the `silicon' command-line tool installed and preferably on your path.
;; You can specify the path to the executable by setting `silicon-executable-path'.

;; The package declares `silicon-buffer-file-to-png' which tries to create a PNG
;; of the current source code buffer. See the function doc string for more details.

;;; Code:
(eval-when-compile (require 'subr-x))

(defgroup silicon ()
  "Customize group for Silicon."
  :group 'convenience)

(defcustom silicon-executable-path "silicon"
  "Path to silicon executable."
  :type 'string
  :group 'silicon)

(defcustom silicon-default-background-color "#00000000"
  "Default background color of output PNG."
  :type 'string
  :group 'silicon)

(defcustom silicon-completion-function 'ido-completing-read
  "Function to use for completion.

Function needs to have a signature similar to `ido-completing-read', for example `ivy-completing-read'."
  :type 'function
  :group 'silicon)

(defcustom silicon-default-theme nil
  "Set default theme for generated PNG. Inspect `silicon-available-themes' for available themes."
  :type 'string
  :group 'silicon)

(defcustom silicon-show-line-numbers nil
  "Add line numbers to resulting PNG by default."
  :type 'boolean
  :group 'silicon)

(defcustom silicon-show-window-controls nil
  "Add window controls to the resulting PNG by default."
  :type 'boolean
  :group 'silicon)

(defcustom silicon-rounded-corners t
  "Rounded corners on code window."
  :type 'boolean
  :group 'silicon)

(defcustom silicon-window-shadow nil
  "Specifies the window shadow.

The value is a plist with keys `:blur-radius', `:color', `:offset-x' and/or `:offset-y'."
  :type '(plist :options ((:blur-radius integer)
                          (:color string)
                          (:offset-x integer)
                          (:offset-y integer)))
  :group 'silicon)

(defvar -silicon--background-color-history '())
(defvar -silicon--cmd-options-history '())

(defvar silicon-available-themes nil
  "List of available silicon themes.")

;; Try to populate `silicon-available-themes'
(when (commandp silicon-executable-path)
  (setq-default silicon-available-themes
                (split-string (shell-command-to-string (format "%s --list-themes" silicon-executable-path))
                              "[\r\n]+"
                              'omit-nulls
                              "\s+")))


(defun -silicon--build-command-opts-string (&rest args)
  "Generate a silicon command options string.

Supported options are `:line-numbers', `:window-controls', `:background-color', `:rounded-corners', `shadow', `:theme' and `:highlight-lines'"
  (let* ((show-line-numbers (or (plist-get args :line-numbers) silicon-show-line-numbers))
         (show-window-controls (or (plist-get args :window-controls) silicon-show-window-controls))
         (rounded-corners (or (plist-get args :rounded-corners) silicon-rounded-corners))
         (background-color (or (plist-get args :background-color) silicon-default-background-color))
         (theme (or (plist-get args :theme) silicon-default-theme))
         (highlight-lines (plist-get args :highlight-lines))

         (shadow (or (plist-get args :shadow) silicon-window-shadow))
         (shadow-blur-radius (plist-get shadow :blur-radius))
         (shadow-color (plist-get shadow :color))
         (shadow-offset-x (plist-get shadow :offset-x))
         (shadow-offset-y (plist-get shadow :offset-y))

         (opts `(,(when (not show-line-numbers) "--no-line-number")
                 ,(when (not show-window-controls) "--no-window-controls")
                 ,(when (not rounded-corners) "--no-round-corner")
                 ,(format "--background '%s'" background-color)
                 ,(when theme (format "--theme '%s'" theme))
                 ,(when highlight-lines (format "--highlight-lines '%s'" highlight-lines))
                 ,(when shadow-blur-radius (format "--shadow-blur-radius %d" shadow-blur-radius))
                 ,(when shadow-color (format "--shadow-color '%s'" shadow-color))
                 ,(when shadow-offset-x (format "--shadow-offset-x %d" shadow-offset-x))
                 ,(when shadow-offset-y (format "--shadow-offset-y %d" shadow-offset-y)))))

    (string-join (seq-remove #'null opts) " ")))

(defun -silicon--build-command (file-path options &optional prompt-for-output-file)
  (let ((output-path (if prompt-for-output-file
                         (read-file-name "Output file: "
                                         default-directory
                                         (concat (file-name-base (buffer-file-name)) ".png"))
                       (concat (file-name-sans-extension file-path) ".png"))))
    (string-join `(,silicon-executable-path
                   ,options
                   ,(format "--output '%s'" output-path)
                   ,file-path)
                 " ")))

;;;###autoload
(defun silicon-set-default-theme ()
  "Set the default silicon theme. This command allows you to select from the list of available themes."
  (interactive)
  (defvar silicon-available-themes)
  (setq silicon-default-theme (funcall silicon-completion-function
                                       "Select theme: "
                                       silicon-available-themes
                                       nil
                                       (not (null silicon-available-themes))
                                       silicon-default-theme)))

;;;###autoload
(defun silicon-buffer-file-to-png (universal-arg)
  "Generate a PNG of the current buffer file. By default the PNG will be saved to the same directory as the
buffer file.

Passing the universal argument (C-u) prompts for options and passing a double universal argument (C-u C-u)
allows for direct editing of the options string."
  (interactive "p")

  (if (not (commandp silicon-executable-path))
      (error "Could not find `silicon' executable, try setting `silicon-executable-path'.")

    (if-let* ((file-name (buffer-file-name))
              (file-path (expand-file-name file-name)))

        (let* ((is-edit (= universal-arg 16))
               (is-prompt (= universal-arg 4))
               (command-string
                (cond (is-edit
                       (let ((options (read-string "Options: "
                                                   (-silicon--build-command-opts-string)
                                                   '-silicon--cmd-options-history
                                                   (-silicon--build-command-opts-string))))
                         (-silicon--build-command file-path options t)))

                      (is-prompt
                       (let ((theme
                              (funcall silicon-completion-function
                                       "Theme: "
                                       silicon-available-themes
                                       nil
                                       (not (null silicon-available-themes))
                                       silicon-default-theme))
                             (background-color
                              (read-string "Background color: "
                                           silicon-default-background-color
                                           '-silicon--background-color-history
                                           silicon-default-background-color))
                             (highlight-lines (read-string "Highlight lines: " nil nil nil))
                             (show-line-numbers (yes-or-no-p "Add line numbers? "))
                             (show-window-controls (yes-or-no-p "Add window controls? "))
                             (rounded-corners (yes-or-no-p "Rounded corners? ")))
                         (-silicon--build-command file-path
                                                  (-silicon--build-command-opts-string :theme theme
                                                                                       :background-color background-color
                                                                                       :highlight-lines (if (string= "" highlight-lines) nil highlight-lines)
                                                                                       :line-numbers show-line-numbers
                                                                                       :window-controls show-window-controls
                                                                                       :rounded-corners rounded-corners)
                                                  t)))

                      (t (-silicon--build-command file-path (-silicon--build-command-opts-string))))))
          (compile command-string))

      (error "Current buffer is not associated with any file."))))

(provide 'silicon)
;;; silicon.el ends here
