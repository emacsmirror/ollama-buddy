;;; ollama-buddy.el --- Ollama Buddy: Your Friendly AI Assistant -*- lexical-binding: t; -*-
;;
;; Author: James Dyer <captainflasmr@gmail.com>
;; Version: 0.1.0
;; Package-Requires: ((emacs "26.1"))
;; Keywords: applications, tools, convenience
;; URL: https://github.com/captainflasmr/ollama-buddy
;;
;; This file is not part of GNU Emacs.
;;
;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or (at
;; your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.
;;
;;; Commentary:
;;
;; Ollama Buddy is an Emacs package that provides a friendly AI assistant
;; for various tasks such as code refactoring, generating commit messages,
;; dictionary lookups, and more.  It interacts with the Ollama server to
;; perform these tasks.
;;
;;; Quick Start
;;
;; (use-package ollama-buddy
;;    :load-path "path/to/ollama-buddy"
;;    :bind ("C-c l" . ollama-buddy-menu)
;;    :config (ollama-buddy-enable-monitor)
;;    :custom ollama-buddy-default-model "llama:latest")
;;
;; OR
;;
;; (add-to-list 'load-path "path/to/ollama-buddy")
;; (require 'ollama-buddy)
;; (global-set-key (kbd "C-c l") #'ollama-buddy-menu)
;; (ollama-buddy-enable-monitor)
;; (setq ollama-buddy-default-model "llama:latest")
;;
;; OR (when added to MELPA)
;;
;; (use-package ollama-buddy
;;    :ensure t
;;    :bind ("C-c l" . ollama-buddy-menu)
;;    :config (ollama-buddy-enable-monitor)
;;    :custom ollama-buddy-default-model "llama:latest")
;;
;;; Usage
;;
;; M-x ollama-buddy-menu
;;
;; OR
;;
;; C-c l
;;
;;; Code:

(require 'json)
(require 'subr-x)
(require 'url)
(require 'cl-lib)

(defgroup ollama-buddy nil
  "Customization group for Ollama Buddy."
  :group 'applications
  :prefix "ollama-buddy-")

(defcustom ollama-buddy-host "localhost"
  "Host where Ollama server is running."
  :type 'string
  :group 'ollama-buddy)

(defcustom ollama-buddy-port 11434
  "Port where Ollama server is running."
  :type 'integer
  :group 'ollama-buddy)

(defcustom ollama-buddy-menu-columns 4
  "Number of columns to display in the Ollama Buddy menu."
  :type 'integer
  :group 'ollama-buddy)

(defcustom ollama-buddy-default-model nil
  "Default Ollama model to use."
  :type 'string
  :group 'ollama-buddy)

(defconst ollama-buddy--separators
  '((header . "========================= | o Y o | =========================")
    (response . "------------------------- | @ Y @ | -------------------------"))
  "Separators for chat display.")

(defcustom ollama-buddy-connection-check-interval 5
  "Interval in seconds to check Ollama connection status."
  :type 'integer
  :group 'ollama-buddy)

(defvar ollama-buddy--current-model nil
  "Timer for checking Ollama connection status.")

(defvar ollama-buddy--connection-timer nil
  "Timer for checking Ollama connection status.")

(defvar ollama-buddy--chat-buffer "*Ollama Buddy Chat*"
  "Chat interaction buffer.")

(defvar ollama-buddy--active-process nil
  "Active Ollama process.")

(defvar ollama-buddy--status "Idle"
  "Current status of the Ollama request.")

(defun ollama-buddy--validate-model (model)
  "Validate MODEL availability."
  (when (and model (ollama-buddy--ollama-running))
    (when (member model (ollama-buddy--get-models))
      model)))

(defun ollama-buddy--get-valid-model (specified-model)
  "Get valid model from SPECIFIED-MODEL with fallback handling."
  (let* ((valid-model (or (ollama-buddy--validate-model specified-model)
                          (ollama-buddy--validate-model ollama-buddy-default-model))))
    (if valid-model
        (cons valid-model specified-model)
      (let ((models (ollama-buddy--get-models)))
        (if models
            (let ((selected (completing-read
                             (format "Model %s not available. Select model: "
                                     (or specified-model ""))
                             models nil t)))
              (setq ollama-buddy--current-model selected)
              (cons selected specified-model))
          (error "No Ollama models available"))))))

(defun ollama-buddy--monitor-connection ()
  "Monitor Ollama connection status and update UI accordingly."
  (unless (ollama-buddy--ollama-running)
    (when (and ollama-buddy--active-process
               (process-live-p ollama-buddy--active-process))
      (delete-process ollama-buddy--active-process)
      (setq ollama-buddy--active-process nil)
      (with-current-buffer (get-buffer-create ollama-buddy--chat-buffer)
        (let ((inhibit-read-only t))
          (goto-char (point-max))
          (insert "\n\n[Connection Lost - Request Interrupted]\n\n")))))
  (ollama-buddy--update-status ollama-buddy--status))

(defun ollama-buddy--update-status (status &optional original-model actual-model)
  "Update the Ollama status and refresh the display.
STATUS is the current operation status.
ORIGINAL-MODEL is the model that was requested.
ACTUAL-MODEL is the model being used instead."
  (setq ollama-buddy--status status)
  (with-current-buffer (get-buffer-create ollama-buddy--chat-buffer)
    (setq header-line-format
          (concat
           (propertize (format " [%s %s: %s]"
                               (if (ollama-buddy--ollama-running) "RUNNING" "OFFLINE")
                               (or ollama-buddy--current-model
                                   ollama-buddy-default-model
                                   "No Model")
                               status)
                       'face '(:inherit bold))
           (when (and original-model actual-model (not (string= original-model actual-model)))
             (propertize (format " [Using %s instead of %s]" actual-model original-model)
                         'face '(:foreground "orange" :weight bold)))))))

(defun ollama-buddy--stream-filter (_proc output)
  "Process stream OUTPUT from PROC while preserving cursor position."
  (ollama-buddy--update-status "Processing...")
  (when-let* ((json-str (replace-regexp-in-string "^[^\{]*" "" output))
              (json-data (and (> (length json-str) 0) (json-read-from-string json-str)))
              (text (alist-get 'content  (alist-get 'message json-data))))
    (with-current-buffer ollama-buddy--chat-buffer
      (let* ((inhibit-read-only t)
             (window (get-buffer-window ollama-buddy--chat-buffer t))
             (old-point (and window (window-point window)))
             (at-end (and window (>= old-point (point-max))))
             (old-window-start (and window (window-start window))))
        (save-excursion
          (goto-char (point-max))
          (insert text)
          (when (eq (alist-get 'done json-data) t)
            (insert (format (propertize "\n\n[%s: FINISHED]\n\n" 'face '(:weight bold)) ollama-buddy--current-model))
            (insert (alist-get 'response ollama-buddy--separators) "\n")
            (ollama-buddy--update-status "Finished")))
        (when window
          (if at-end
              (set-window-point window (point-max))
            (set-window-point window old-point))
          (set-window-start window old-window-start t))))))

(defun ollama-buddy--stream-sentinel (_proc event)
  "Handle stream completion for PROC with EVENT status."
  (when-let* ((status (cond ((string-match-p "finished" event) "Completed")
                            ((string-match-p "\\(?:deleted\\|connection broken\\)" event) "Interrupted")))
              (msg (format "\n\n[Stream %s]\n\n" status)))
    (with-current-buffer ollama-buddy--chat-buffer
      (let ((inhibit-read-only t))
        (goto-char (point-max))
        (insert (propertize msg 'face '(:weight bold)))
        (insert (alist-get 'response ollama-buddy--separators) "\n")))
    (ollama-buddy--update-status (concat "Stream " status))))

(defcustom ollama-buddy-command-definitions
  '((open-chat
     :key ?o
     :description "Open chat buffer"
     :model nil
     :action (lambda ()
               (pop-to-buffer (get-buffer-create ollama-buddy--chat-buffer))
               (when (= (buffer-size) 0)
                 (insert (ollama-buddy--create-intro-message)))
               (goto-char (point-max))))
    
    (show-models
     :key ?v  ; 'v' for view models
     :description "View model status"
     :model nil
     :action ollama-buddy-show-model-status)
    
    (swap-model
     :key ?m
     :description "Swap model"
     :model nil
     :action (lambda ()
               (if (not (ollama-buddy--ollama-running))
                   (error "!!WARNING!! ollama server not running")
                 (let ((new-model
                        (completing-read "Model: " (ollama-buddy--get-models) nil t)))
                   (setq ollama-buddy-default-model new-model)
                   (setq ollama-buddy--current-model new-model)
                   (ollama-buddy--update-status "Idle")))))
    
    (help
     :key ?h
     :description "Help assistant"
     :model nil
     :action (lambda ()
               (pop-to-buffer (get-buffer-create ollama-buddy--chat-buffer))
               (goto-char (point-max))
               (insert (ollama-buddy--create-intro-message))))
    
    (send-region
     :key ?l
     :description "Send region"
     :model nil
     :action (lambda () (ollama-buddy--send-with-command 'send-region)))
    
    (refactor-code
     :key ?r
     :description "Refactor code"
     :model nil
     :prompt "refactor the following code:"
     :action (lambda () (ollama-buddy--send-with-command 'refactor-code)))
    
    (git-commit
     :key ?g
     :description "Git commit message"
     :model nil
     :prompt "write a concise git commit message for the following:"
     :action (lambda () (ollama-buddy--send-with-command 'git-commit)))
    
    (describe-code
     :key ?c
     :description "Describe code"
     :model nil
     :prompt "describe the following code:"
     :action (lambda () (ollama-buddy--send-with-command 'describe-code)))
    
    (dictionary-lookup
     :key ?d
     :description "Dictionary Lookup"
     :model nil
     :prompt-fn (lambda ()
                  (concat "For the word {"
                          (buffer-substring-no-properties (region-beginning) (region-end))
                          "} provide a typical dictionary definition:"))
     :action (lambda () (ollama-buddy--send-with-command 'dictionary-lookup)))
    
    (synonym
     :key ?n
     :description "Word synonym"
     :model nil
     :prompt "list synonyms for word:"
     :action (lambda () (ollama-buddy--send-with-command 'synonym)))
    
    (proofread
     :key ?p
     :description "Proofread text"
     :model nil
     :prompt "proofread the following:"
     :action (lambda () (ollama-buddy--send-with-command 'proofread)))
    
    (make-concise
     :key ?z
     :description "Make concise"
     :model nil
     :prompt "reduce wordiness while preserving meaning:"
     :action (lambda () (ollama-buddy--send-with-command 'make-concise)))
    
    (custom-prompt
     :key ?e
     :description "Custom prompt"
     :model nil
     :action (lambda ()
               (when-let ((prefix (read-string "Enter prompt prefix: " nil nil nil t)))
                 (unless (string-empty-p prefix)
                   (ollama-buddy--send prefix)))))
    
    (save-chat
     :key ?s
     :description "Save chat"
     :model nil
     :action (lambda ()
               (with-current-buffer ollama-buddy--chat-buffer
                 (write-region (point-min) (point-max)
                               (read-file-name "Save conversation to: ")
                               'append-to-file
                               nil))))
    
    (kill-request
     :key ?x
     :description "Kill request"
     :model nil
     :action (lambda ()
               (delete-process ollama-buddy--active-process)))
    
    (quit
     :key ?q
     :description "Quit"
     :model nil
     :action (lambda () (message "Quit Ollama Shell menu."))))
  "Comprehensive command definitions for Ollama Buddy.
Each command is defined with:
  :key - Character for menu selection
  :description - String describing the action
  :model - Specific Ollama model to use (nil means use default)
  :prompt - Optional system prompt
  :prompt-fn - Optional function to generate prompt
  :action - Function to execute"
  :type '(repeat (list symbol
                       (plist :key-type keyword :value-type sexp)))
  :group 'ollama-buddy)

(defun ollama-buddy--get-command-def (command-name)
  "Get command definition for COMMAND-NAME."
  (assoc command-name ollama-buddy-command-definitions))

(defun ollama-buddy--get-command-prop (command-name prop)
  "Get property PROP from command COMMAND-NAME."
  (plist-get (cdr (ollama-buddy--get-command-def command-name)) prop))

(defun ollama-buddy--send-with-command (command-name)
  "Send request using configuration from COMMAND-NAME."
  (let* ((prompt (or (ollama-buddy--get-command-prop command-name :prompt)
                     (when-let ((fn (ollama-buddy--get-command-prop
                                     command-name :prompt-fn)))
                       (funcall fn))))
         (model (ollama-buddy--get-command-prop command-name :model)))
    (ollama-buddy--send prompt model)))

(defun ollama-buddy--send (&optional system-prompt specified-model)
  "Send CONTENT with optional SYSTEM-PROMPT and SPECIFIED-MODEL."
  (unless (and (ollama-buddy--ollama-running) (use-region-p))
    (user-error "Ensure Ollama is running and text is selected"))
  (let* ((prompt (buffer-substring-no-properties (region-beginning) (region-end)))
         (content (if system-prompt (concat system-prompt "\n\n" prompt) prompt))
         (model-info (ollama-buddy--get-valid-model specified-model))
         (model (car model-info))
         (original-model (cdr model-info))
         (payload (json-encode
                   `((model . ,model)
                     (messages . [((role . "user")
                                   (content
                                    . ,(if system-prompt
                                           (concat system-prompt "\n\n" content)
                                         content)))])
                     (stream . t)))))
    (setq ollama-buddy--current-model model)
    
    (with-current-buffer (get-buffer-create ollama-buddy--chat-buffer)
      (pop-to-buffer (current-buffer))
      (goto-char (point-max))
      (unless (> (buffer-size) 0)
        (insert (ollama-buddy--create-intro-message)))
      (insert (format "\n\n%s\n\n%s %s\n\n%s\n\n"
                      (propertize (alist-get 'header ollama-buddy--separators) 'face '(:inherit bold))
                      (propertize "[User: PROMPT]" 'face '(:inherit bold))
                      content
                      (propertize (concat "[" model ": RESPONSE]") 'face '(:inherit bold))))
      (when (and original-model model (not (string= original-model model)))
        (insert (propertize (format "[Using %s instead of %s]" model original-model)
                            'face '(:inherit error :weight bold)) "\n\n"))
      (visual-line-mode 1))

    (ollama-buddy--update-status "Sending request..." original-model model)
    
    (setq ollama-buddy--active-process
          (make-network-process
           :name "ollama-chat-stream"
           :buffer nil
           :host ollama-buddy-host
           :service ollama-buddy-port
           :coding 'utf-8
           :filter #'ollama-buddy--stream-filter
           :sentinel #'ollama-buddy--stream-sentinel))
    
    (process-send-string
     ollama-buddy--active-process
     (concat "POST /api/chat HTTP/1.1\r\n"
             (format "Host: %s:%d\r\n" ollama-buddy-host ollama-buddy-port)
             "Content-Type: application/json\r\n"
             (format "Content-Length: %d\r\n\r\n" (string-bytes payload))
             payload))))

(defun ollama-buddy--make-request (endpoint method &optional payload)
  "Generic request function for ENDPOINT with METHOD and optional PAYLOAD."
  (when (ollama-buddy--ollama-running)
    (let ((url-request-method method)
          (url-request-extra-headers '(("Content-Type" . "application/json")
                                       ("Connection" . "close")))
          (url (format "http://%s:%d%s"
                       ollama-buddy-host ollama-buddy-port endpoint)))
      (with-temp-buffer
        (if payload
            (let ((url-request-data (encode-coding-string payload 'utf-8)))
              (url-insert-file-contents url))
          (url-insert-file-contents url))
        (json-read-from-string (buffer-string))))))

(defun ollama-buddy--get-models ()
  "Get available Ollama models."
  (when-let ((response (ollama-buddy--make-request "/api/tags" "GET")))
    (mapcar (lambda (m) (alist-get 'name m)) (alist-get 'models response))))

(defun ollama-buddy--ollama-running ()
  "Check if Ollama server is running."
  (condition-case nil
      (let ((proc (make-network-process
                   :name "ollama-test"
                   :buffer nil
                   :host ollama-buddy-host
                   :service ollama-buddy-port
                   :nowait nil)))
        (delete-process proc)
        t)
    (error nil)))

(defun ollama-buddy--create-intro-message ()
  "Create welcome message."
  (let ((status (when (ollama-buddy--ollama-running)
                  (format "    Models available:\n\n%s\n\n"
                          (mapconcat (lambda (m) (format "      %s" m))
                                     (ollama-buddy--get-models) "\n")))))
    (propertize
     (concat
      "\n" (alist-get 'header ollama-buddy--separators) "\n"
      "         ╭──────────────────────────────────────╮\n"
      "         │              Welcome to               │\n"
      "         │             OLLAMA BUDDY              │\n"
      "         │       Your Friendly AI Assistant      │\n"
      "         ╰──────────────────────────────────────╯\n\n"
      "    Hi there!\n\n" status
      "    Quick Tips:\n"
      "    - Select text and use M-x ollama-buddy-menu\n"
      "    - Switch models [m], cancel [x]\n"
      "    - Send from any buffer\n\n"
      (alist-get 'response ollama-buddy--separators) "\n\n")
     'face '(:inherit bold))))

;;;###autoload
(defun ollama-buddy-menu ()
  "Display Ollama Buddy menu."
  (interactive)
  (when-let* ((items (mapcar (lambda (cmd-def)
                               (cons (plist-get (cdr cmd-def) :key)
                                     (list (plist-get (cdr cmd-def) :description)
                                           (plist-get (cdr cmd-def) :action))))
                             ollama-buddy-command-definitions))
              (formatted-items
               (mapcar (lambda (item)
                         (format "[%c] %s" (car item) (cadr item)))
                       items))
              (total (length formatted-items))
              (rows (ceiling (/ total (float ollama-buddy-menu-columns))))
              (padded-items (append formatted-items
                                    (make-list (- (* rows
                                                     ollama-buddy-menu-columns)
                                                  total)
                                               "")))
              (format-string
               (mapconcat
                (lambda (width) (format "%%-%ds" (+ width 2)))
                (butlast
                 (cl-loop for col below ollama-buddy-menu-columns collect
                          (cl-loop for row below rows
                                   for idx = (+ (* col rows) row)
                                   when (< idx total)
                                   maximize (length (nth idx padded-items)))))
                ""))
              (prompt
               (format "%s %s%s\nAvailable: %s\n%s"
                       (if (ollama-buddy--ollama-running) "RUNNING" "NOT RUNNING")
                       (or ollama-buddy--current-model "NONE")
                       (if (use-region-p) "" " (NO SELECTION)")
                       (mapconcat #'identity (ollama-buddy--get-models) " ")
                       (mapconcat
                        (lambda (row)
                          (if format-string
                              (apply #'format (concat format-string "%s") row)
                            (car row)))
                        (cl-loop for row below rows collect
                                 (cl-loop for col below ollama-buddy-menu-columns
                                          for idx = (+ (* col rows) row)
                                          when (< idx (length padded-items))
                                          collect (nth idx padded-items)))
                        "\n")))
              (key (read-key (propertize prompt 'face 'minibuffer-prompt)))
              (cmd (assoc key items)))
    (funcall (caddr cmd))))

(defun ollama-buddy-show-model-status ()
  "Display status of models referenced in command definitions."
  (interactive)
  (let* ((used-models (delete-dups
                       (delq nil
                             (mapcar (lambda (cmd)
                                       (plist-get (cdr cmd) :model))
                                     ollama-buddy-command-definitions))))
         (available-models (ollama-buddy--get-models))
         (buf (get-buffer-create "*Ollama Model Status*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "Ollama Model Status:\n\n")
        (insert (format "Current Model: %s\n" ollama-buddy--current-model))
        (insert (format "Default Model: %s\n\n" ollama-buddy-default-model))
        (insert "Models used in commands:\n")
        (dolist (model used-models)
          (insert (format "  %s: %s\n"
                          model
                          (if (member model available-models)
                              "Available ✓"
                            "Not Available ✗"))))
        (insert "\nAvailable Models:\n  ")
        (insert (string-join available-models "\n  "))))
    (display-buffer buf)))

(add-to-list 'ollama-buddy-command-definitions
             '(show-models
               :key ?v  ; 'v' for view models
               :description "View model status"
               :model nil
               :action ollama-buddy-show-model-status))

;;;###autoload
(defun ollama-buddy-enable-monitor ()
  "Enable connection monitoring."
  (interactive)
  (unless ollama-buddy--connection-timer
    (setq ollama-buddy--connection-timer
          (run-with-timer 0 ollama-buddy-connection-check-interval
                          #'ollama-buddy--monitor-connection))))

;;;###autoload
(defun ollama-buddy-disable-monitor ()
  "Disable connection monitoring."
  (interactive)
  (when ollama-buddy--connection-timer
    (cancel-timer ollama-buddy--connection-timer)
    (setq ollama-buddy--connection-timer nil)))

(provide 'ollama-buddy)
;;; ollama-buddy.el ends here
