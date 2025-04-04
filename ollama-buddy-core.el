;;; ollama-buddy-core.el --- Core functionality for ollama-buddy -*- lexical-binding: t; -*-

;; Author: YourName
;; Keywords: local, tools
;; Package-Requires: ((emacs "28.1") (transient "0.4.0"))

;;; Commentary:

;; This file contains core functionality, shared variables, and utility functions
;; for the ollama-buddy package, which provides an interface to the Ollama API.

;;; Code:

(require 'json)
(require 'subr-x)
(require 'url)
(require 'cl-lib)
(require 'dired)
(require 'org)
(require 'savehist)
(require 'color)

;; Core Customization Groups
(defgroup ollama-buddy nil
  "Customization group for Ollama Buddy."
  :group 'applications
  :prefix "ollama-buddy-")

(defgroup ollama-buddy-params nil
  "Customization group for Ollama API parameters."
  :group 'ollama-buddy
  :prefix "ollama-buddy-param-")

;; Core customization options
(defcustom ollama-buddy-default-register ?a
  "Default register to store the current response when not in multishot mode."
  :type 'character
  :group 'ollama-buddy)

(defcustom ollama-buddy-streaming-enabled t
  "Whether to use streaming mode for responses.
When enabled, responses appear token by token in real time.
When disabled, responses only appear after completion."
  :type 'boolean
  :group 'ollama-buddy)

(defcustom ollama-buddy-params-modified
  nil
  "Set of parameters that have been explicitly modified by the user.
These are the only parameters that will be sent to Ollama."
  :type '(set symbol)
  :group 'ollama-buddy-params)

(defcustom ollama-buddy-interface-level 'basic
  "Level of interface complexity to display."
  :type '(choice (const :tag "Basic (for beginners)" basic)
                 (const :tag "Advanced (full features)" advanced))
  :group 'ollama-buddy)

(defcustom ollama-buddy-default-model nil
  "Default Ollama model to use."
  :type 'string
  :group 'ollama-buddy)

(defcustom ollama-buddy-debug-mode nil
  "When non-nil, show raw JSON messages in a debug buffer."
  :type 'boolean
  :group 'ollama-buddy)

(defcustom ollama-buddy-show-params-in-header t
  "Whether to show modified parameters in the header line."
  :type 'boolean
  :group 'ollama-buddy)

(defcustom ollama-buddy-params-modified nil
  "Set of parameters that have been explicitly modified by the user.
These are the only parameters that will be sent to Ollama."
  :type '(set symbol)
  :group 'ollama-buddy-params)

(defcustom ollama-buddy-params-defaults
  '((num_keep . 5)
    (seed . 42)
    (num_predict . 100)
    (top_k . 20)
    (top_p . 0.9)
    (min_p . 0.0)
    (typical_p . 0.7)
    (repeat_last_n . 33)
    (temperature . 0.8)
    (repeat_penalty . 1.2)
    (presence_penalty . 1.5)
    (frequency_penalty . 1.0)
    (mirostat . 1)
    (mirostat_tau . 0.8)
    (mirostat_eta . 0.6)
    (penalize_newline . t)
    (stop . ["\n" "user:"])
    (numa . nil)
    (num_ctx . 1024)
    (num_batch . 2)
    (num_gpu . 1)
    (main_gpu . 0)
    (low_vram . nil)
    (vocab_only . nil)
    (use_mmap . t)
    (use_mlock . nil)
    (num_thread . 8))
  "Default values for Ollama API parameters."
  :type '(alist :key-type symbol :value-type sexp)
  :group 'ollama-buddy-params)

(defcustom ollama-buddy-command-definitions
  '(
    ;; General Commands
    (open-chat
     :key ?o
     :description "Open chat buffer"
     :action ollama-buddy--open-chat)
    
    (show-models
     :key ?v
     :description "View model status"
     :action ollama-buddy-show-model-status)
    
    (send-region
     :key ?l
     :description "Send region"
     :action (lambda () (ollama-buddy--send-with-command 'send-region)))
    
    (kill-request
     :key ?k
     :description "Kill request"
     :action (lambda ()
               (delete-process ollama-buddy--active-process)))
    
    (switch-role
     :key ?R
     :description "Switch roles"
     :action ollama-buddy-roles-switch-role)
    
    (create-role
     :key ?E
     :description "Create new role"
     :action ollama-buddy-role-creator-create-new-role)
    
    (open-roles-directory
     :key ?D
     :description "Open roles directory"
     :action ollama-buddy-roles-open-directory)
    
    ;; Custom commands
    (refactor-code
     :key ?r
     :description "Refactor code"
     :prompt "refactor the following code:"
     :system "You are an expert software engineer who improves code quality while maintaining functionality, focusing on readability, maintainability, and efficiency by applying clean code principles and design patterns with clear explanations for each change."
     :parameters ((temperature . 0.2) (top_p . 0.7) (repeat_penalty . 1.3))
     :action (lambda () (ollama-buddy--send-with-command 'refactor-code)))
    
    (git-commit
     :key ?g
     :description "Git commit message"
     :prompt "write a concise git commit message for the following:"
     :system "You are a version control expert who creates clear commit messages using imperative mood, keeping summaries under 50 characters, explaining the what and why of changes, and referencing issue numbers where applicable."
     :action (lambda () (ollama-buddy--send-with-command 'git-commit)))
    
    (describe-code
     :key ?c
     :description "Describe code"
     :prompt "describe the following code:"
     :system "You are a technical documentation specialist who analyzes code to provide high-level summaries, explain main components and control flow, highlight notable patterns or optimizations, and clarify complex parts in accessible language."
     :action (lambda () (ollama-buddy--send-with-command 'describe-code)))
    
    (dictionary-lookup
     :key ?d
     :description "Dictionary Lookup"
     :prompt "For the following word provide a typical dictionary definition:"
     :system "You are a professional lexicographer who provides comprehensive word definitions including pronunciation, all relevant parts of speech, etymology, examples of usage, and related synonyms and antonyms in a clear dictionary-style format."
     :action (lambda () (ollama-buddy--send-with-command 'dictionary-lookup)))
    
    (synonym
     :key ?n
     :description "Word synonym"
     :prompt "list synonyms for word:"
     :system "You are a linguistic expert who provides contextually grouped synonyms with notes on connotation, formality levels, and usage contexts to help find the most precise alternative word for specific situations."
     :action (lambda () (ollama-buddy--send-with-command 'synonym)))
    
    (proofread
     :key ?p
     :description "Proofread text"
     :prompt "proofread the following:"
     :system "You are a professional editor who identifies and corrects grammar, spelling, punctuation, and style errors with brief explanations of corrections, providing both the corrected text and a list of changes made."
     :action (lambda () (ollama-buddy--send-with-command 'proofread)))
    
    ;; System Commands
    (custom-prompt
     :key ?e
     :description "Custom prompt"
     :action ollama-buddy--menu-custom-prompt)
    
    (minibuffer-prompt
     :key ?i
     :description "Minibuffer Prompt"
     :action ollama-buddy--menu-minibuffer-prompt)
    
    (quit
     :key ?q
     :description "Quit"
     :action (lambda () (message "Quit Ollama Shell menu."))))
  "Comprehensive command definitions for Ollama Buddy.
Each command is defined with:
  :key - Character for menu selection
  :description - String describing the action
  :model - Specific Ollama model to use (nil means use default)
  :prompt - Optional user prompt prefix
  :system - Optional system prompt/message
  :parameters - Association list of Ollama API parameters
  :action - Function to execute"
  :type '(repeat
          (list :tag "Command Definition"
                (symbol :tag "Command Name")
                (plist :inline t
                       :options
                       ((:key (character :tag "Menu Key Character"))
                        (:description (string :tag "Command Description"))
                        (:model (choice :tag "Specific Model"
                                        (const :tag "Use Default" nil)
                                        (string :tag "Model Name")))
                        (:prompt (string :tag "Static Prompt Text"))
                        (:system (string :tag "System Prompt/Message"))
                        (:parameters (alist :key-type symbol :value-type sexp))
                        (:action (choice :tag "Action"
                                         (function :tag "Existing Function")
                                         (sexp :tag "Lambda Expression")))))))
  :group 'ollama-buddy)

(defcustom ollama-buddy-params-active
  (copy-tree ollama-buddy-params-defaults)
  "Currently active values for Ollama API parameters."
  :type '(alist :key-type symbol :value-type sexp)
  :group 'ollama-buddy-params)

(defcustom ollama-buddy-params-profiles
  '(("Default" . nil)
    ("Creative" . ((temperature . 1.0)
                   (top_p . 0.95)
                   (repeat_penalty . 1.0)))
    ("Precise" . ((temperature . 0.2)
                  (top_p . 0.5)
                  (repeat_penalty . 1.5))))
  "Predefined parameter profiles for different usage scenarios."
  :type '(alist :key-type string :value-type (alist :key-type symbol :value-type sexp))
  :group 'ollama-buddy-params)

(defcustom ollama-buddy-convert-markdown-to-org t
  "Whether to automatically convert markdown to `org-mode' format in responses."
  :type 'boolean
  :group 'ollama-buddy)

(defcustom ollama-buddy-sessions-directory
  (expand-file-name "ollama-buddy-sessions" user-emacs-directory)
  "Directory containing ollama-buddy session files."
  :type 'directory
  :group 'ollama-buddy)

(defcustom ollama-buddy-enable-model-colors t
  "Whether to show model colors."
  :type 'boolean
  :group 'ollama-buddy)

(defcustom ollama-buddy-host "localhost"
  "Host where Ollama server is running."
  :type 'string
  :group 'ollama-buddy)

(defcustom ollama-buddy-port 11434
  "Port where Ollama server is running."
  :type 'integer
  :group 'ollama-buddy)

(defcustom ollama-buddy-menu-columns 5
  "Number of columns to display in the Ollama Buddy menu."
  :type 'integer
  :group 'ollama-buddy)

(defcustom ollama-buddy-roles-directory
  (expand-file-name "ollama-buddy-presets" user-emacs-directory)
  "Directory containing ollama-buddy role preset files."
  :type 'directory
  :group 'ollama-buddy)

(defcustom ollama-buddy-connection-check-interval 5
  "Interval in seconds to check Ollama connection status."
  :type 'integer
  :group 'ollama-buddy)

(defcustom ollama-buddy-history-enabled t
  "Whether to use conversation history in Ollama requests."
  :type 'boolean
  :group 'ollama-buddy)

(defcustom ollama-buddy-max-history-length 10
  "Maximum number of message pairs to keep in conversation history."
  :type 'integer
  :group 'ollama-buddy)

(defcustom ollama-buddy-show-history-indicator t
  "Whether to show the history indicator in the header line."
  :type 'boolean
  :group 'ollama-buddy)

;; Auto-save session functionality
(defcustom ollama-buddy-auto-save-session nil
  "Whether to automatically save session on exit."
  :type 'boolean
  :group 'ollama-buddy)

(defcustom ollama-buddy-auto-save-session-name "autosave"
  "Name to use for auto-saved sessions."
  :type 'string
  :group 'ollama-buddy)

(defcustom ollama-buddy-display-token-stats nil
  "Whether to display token usage statistics in responses."
  :type 'boolean
  :group 'ollama-buddy)

(defcustom ollama-buddy-modelfile-directory
  (expand-file-name "ollama-buddy-modelfiles" user-emacs-directory)
  "Directory for storing temporary Modelfiles."
  :type 'directory
  :group 'ollama-buddy)

(defcustom ollama-buddy-available-models
  '(
    "llama3.2:1b"
    "starcoder2:3b"
    "codellama:7b"
    "phi3:3.8b"
    "gemma3:1b"
    "gemma3:4b"
    "qwen2.5-coder:7b"
    "qwen2.5-coder:3b"
    "mistral:7b"
    "deepseek-r1:7b"
    "deepseek-r1:1.5b"
    "tinyllama:latest"
    "llama3.2:3b"
    )
  "List of available models to pull from Ollama Hub."
  :type '(repeat string)
  :group 'ollama-buddy)

;; Shared variables
(defcustom ollama-buddy-claude-marker-prefix "claude:"
  "Prefix used to identify Claude models in the model list."
  :type 'string
  :group 'ollama-buddy-claude)

(defcustom ollama-buddy-claude-models
  '("claude-3-7-sonnet-20250219"
    "claude-3-5-sonnet-20240620"
    "claude-3-opus-20240229"
    "claude-3-5-haiku-20240307")
  "List of available Claude models."
  :type '(repeat string)
  :group 'ollama-buddy-claude)

(defvar ollama-buddy-claude--current-model nil
  "The currently selected Claude model.")

(defvar ollama-buddy--background-operations nil
  "Alist of active background operations.
Each entry is (OPERATION-ID . DESCRIPTION) where OPERATION-ID
is a unique identifier and DESCRIPTION is displayed in the status line.")

(defvar ollama-buddy--status-update-timer nil
  "Timer for updating the status line with background operations.")

(defcustom ollama-buddy-status-update-interval 1.0
  "Interval in seconds to update the status line with background operations."
  :type 'float
  :group 'ollama-buddy)

(defvar ollama-buddy--running-models-cache nil
  "Cache for running Ollama models.")

(defvar ollama-buddy--running-models-cache-timestamp nil
  "Timestamp when running models cache was last updated.")

(defvar ollama-buddy--colors-cache nil
  "Cache for model colors.")

(defvar ollama-buddy--colors-cache-timestamp nil
  "Timestamp when colors cache was last updated.")

(defvar ollama-buddy--models-cache nil
  "Cache for available Ollama models.")

(defvar ollama-buddy--models-cache-timestamp nil
  "Timestamp when models cache was last updated.")

(defvar ollama-buddy--models-cache-ttl 5
  "Time-to-live for models cache in seconds.")

(defcustom ollama-buddy-openai-marker-prefix "GPT"
  "Prefix to indicate that a model is from OpenAI rather than Ollama."
  :type 'string
  :group 'ollama-buddy-openai)

(defvar ollama-buddy-openai--current-model nil
  "The currently active OpenAI model.")

(defcustom ollama-buddy-openai-models
  '("gpt-4o-mini" "gpt-4o" "gpt-3.5-turbo")
  "List of available OpenAI models."
  :type '(repeat string)
  :group 'ollama-buddy-openai)

(defvar ollama-buddy-roles--current-role "default"
  "The currently active ollama-buddy role.")

(defvar ollama-buddy-role-creator--command-template
  '((key . nil)
    (description . nil)
    (model . nil)
    (prompt . nil)
    (system . nil))
  "Template for a new command definition.")

(defvar ollama-buddy--history-edit-buffer "*Ollama History Edit*"
  "Buffer name for editing Ollama conversation history.")

(defvar ollama-buddy--saved-params-active nil
  "Saved copy of params-active before applying command-specific parameters.")

(defvar ollama-buddy--saved-params-modified nil
  "Saved copy of params-modified before applying command-specific parameters.")

(defvar ollama-buddy--current-suffix nil
  "The current suffix if set.")

(defvar ollama-buddy--current-system-prompt nil
  "The current system prompt if set.")

(defvar ollama-buddy--debug-buffer "*Ollama Debug*"
  "Buffer for showing raw JSON messages.")

(defvar ollama-buddy--current-request-temporary-model nil
  "For the current request don't make current model permanent.")

(defvar ollama-buddy--response-start-position nil
  "Marker for the start position of the current response.")

(defvar ollama-buddy--current-response nil
  "The current response text being accumulated.")

(defvar-local ollama-buddy--response-start-position nil
  "Buffer-local marker for the start position of the current response.")

(defvar ollama-buddy--current-prompt nil
  "The current prompt.")

(defvar ollama-buddy--current-session nil
  "Name of the currently active session, or nil if none.")

(defvar ollama-buddy--conversation-history-by-model (make-hash-table :test 'equal)
  "Hash table mapping model names to their conversation histories.")

(defvar ollama-buddy--token-usage-history nil
  "History of token usage for ollama-buddy interactions.")

(defvar ollama-buddy--current-token-count 0
  "Counter for tokens in the current response.")

(defvar ollama-buddy--current-token-start-time nil
  "Timestamp when the current response started.")

(defvar ollama-buddy--token-update-interval 0.5
  "How often to update the token rate display, in seconds.")

(defvar ollama-buddy--token-update-timer nil
  "Timer for updating token rate display.")

(defvar ollama-buddy--last-token-count 0
  "Token count at last update interval.")

(defvar ollama-buddy--last-update-time nil
  "Timestamp of last token rate update.")

(defvar ollama-buddy--prompt-history nil
  "History of prompts used in ollama-buddy.")

(defvar ollama-buddy--last-status-check nil
  "Timestamp of last Ollama status check.")

(defvar ollama-buddy--status-cache nil
  "Cached status of Ollama connection.")

(defvar ollama-buddy--status-cache-ttl 5
  "Time in seconds before status cache expires.")

(defvar ollama-buddy--current-model nil
  "Current model being used for Ollama requests.")

(defvar ollama-buddy--connection-timer nil
  "Timer for checking Ollama connection status.")

(defvar ollama-buddy--chat-buffer "*Ollama Buddy Chat*"
  "Chat interaction buffer.")

(defvar ollama-buddy--active-process nil
  "Active Ollama process.")

(defvar ollama-buddy--status "Idle"
  "Current status of the Ollama request.")

(defvar ollama-buddy--model-letters nil
  "Alist mapping letters to model names.")

(defvar ollama-buddy--multishot-sequence nil
  "Current sequence of models for multishot execution.")

(defvar ollama-buddy--multishot-progress 0
  "Progress through current multishot sequence.")

(defvar ollama-buddy--multishot-prompt nil
  "The prompt being used for the current multishot sequence.")

;; Keep track of model colors
(defvar ollama-buddy--model-colors (make-hash-table :test 'equal)
  "Hash table mapping model names to their colors.")

;; Core utility functions
(defun ollama-buddy-open-info ()
  "Open the Info manual for the ollama-buddy package."
  (interactive)
  (info "(ollama-buddy)"))

(defun ollama-buddy-claude--get-full-model-name (model)
  "Get the full model name with prefix for MODEL."
  (concat ollama-buddy-claude-marker-prefix model))

(defun ollama-buddy-claude--is-claude-model (model)
  "Check if MODEL is a Claude model by checking for the prefix."
  (and model (string-prefix-p ollama-buddy-claude-marker-prefix model)))

(defun ollama-buddy-escape-unicode (string)
  "Convert all non-ASCII characters in STRING to Unicode escape sequences."
  (let ((result "")
        (i 0))
    (while (< i (length string))
      (let ((char (aref string i)))
        (if (< char 128)  ;; ASCII
            (setq result (concat result (char-to-string char)))
          (setq result (concat result (format "\\u%04X" char)))))
      (setq i (1+ i)))
    result))

(defun ollama-buddy-fix-encoding-issues (string)
  "Fix common encoding issues with a simpler approach."
  (let* ((string (replace-regexp-in-string "â" "—" string))      ;; em dash
        (string (replace-regexp-in-string "" "" string)) ;; alternative em dash
        (string (replace-regexp-in-string "" "" string)) ;; en dash
        (string (replace-regexp-in-string "â€œ" "\"" string))    ;; left double quote
        (string (replace-regexp-in-string "â€" "\"" string))     ;; right double quote
        (string (replace-regexp-in-string "â€˜" "'" string))     ;; left single quote
        (string (replace-regexp-in-string "â€™" "'" string))     ;; right single quote
        (string (replace-regexp-in-string "â€¦" "…" string))     ;; ellipsis
        (string (replace-regexp-in-string "Ã" "E" string))   ;; capital E with acute accent
        (string (replace-regexp-in-string "Ã©" "e" string))   ;; lowercase e with acute accent
        (string (replace-regexp-in-string "â€¢" "•" string)))    ;; bullet point
    string))

(defun ollama-buddy--register-background-operation (operation-id description)
  "Register a new background OPERATION-ID with DESCRIPTION."
  ;; Start the timer if it's not already running
  (unless ollama-buddy--status-update-timer
    (setq ollama-buddy--status-update-timer
          (run-with-timer 0 ollama-buddy-status-update-interval
                          #'ollama-buddy--update-status-with-operations)))
  
  ;; Add the operation to the list
  (push (cons operation-id description) ollama-buddy--background-operations)
  
  ;; Immediately update the status
  (ollama-buddy--update-status-with-operations))

(defun ollama-buddy--complete-background-operation (operation-id &optional completion-status)
  "Mark OPERATION-ID as completed with optional COMPLETION-STATUS."
  ;; Remove the operation from the list
  (setq ollama-buddy--background-operations
        (assq-delete-all operation-id ollama-buddy--background-operations))
  
  ;; Update status with completion message if provided
  (when completion-status
    (ollama-buddy--update-status completion-status))
  
  ;; Cancel the timer if no more operations
  (when (and (null ollama-buddy--background-operations)
             ollama-buddy--status-update-timer)
    (cancel-timer ollama-buddy--status-update-timer)
    (setq ollama-buddy--status-update-timer nil))
  
  ;; Update the status display
  (ollama-buddy--update-status-with-operations))

(defun ollama-buddy--update-status-with-operations ()
  "Update status line to show background operations."
  (with-current-buffer (get-buffer-create ollama-buddy--chat-buffer)
    (let* ((regular-status ollama-buddy--status)
           (operations-text 
            (when ollama-buddy--background-operations
              (mapconcat #'cdr ollama-buddy--background-operations " | ")))
           (combined-status 
            (if operations-text
                (format "%s [%s...]" regular-status operations-text)
              regular-status)))
      
      ;; Call the original update status function with our combined status
      (let ((ollama-buddy--status combined-status))
        (ollama-buddy--update-status combined-status)))))

(defun ollama-buddy-toggle-streaming ()
  "Toggle streaming mode for Ollama responses.
When streaming is enabled, responses appear token by token in real time.
When disabled, responses only appear after completion."
  (interactive)
  (setq ollama-buddy-streaming-enabled (not ollama-buddy-streaming-enabled))
  (ollama-buddy--update-status 
   (if ollama-buddy-streaming-enabled "Streaming enabled" "Streaming disabled"))
  (message "Ollama Buddy streaming mode: %s" 
           (if ollama-buddy-streaming-enabled "enabled" "disabled")))

(defun ollama-buddy-openai--is-openai-model (model)
  "Check if MODEL is an OpenAI model based on prefix."
  (and model
       (string-match-p (concat "^" (regexp-quote ollama-buddy-openai-marker-prefix)) model)))

(defun ollama-buddy--md-to-org-convert-region (start end)
  "Convert the region from START to END from Markdown to Org-mode format."
  (save-excursion
    (save-restriction
      (narrow-to-region start end)
      
      ;; First, handle code blocks by temporarily protecting their content
      (goto-char (point-min))
      (let ((code-blocks nil)
            (counter 0)
            block-start block-end lang content placeholder)
        
        ;; IMPORTANT: Add save-match-data here
        (save-match-data
          ;; Find and replace code blocks with placeholders
          (while (re-search-forward "```\\(.*?\\)\\(?:\n\\|\\s-\\)\\(\\(?:.\\|\n\\)*?\\)```" nil t)
            (setq lang (match-string 1)
                  content (match-string 2)
                  block-start (match-beginning 0)
                  block-end (match-end 0)
                  placeholder (format "CODE_BLOCK_PLACEHOLDER_%d" counter))
            
            ;; Store the code block information for later restoration
            (push (list placeholder lang content) code-blocks)
            
            ;; Replace with placeholder
            (delete-region block-start block-end)
            (goto-char block-start)
            (insert placeholder)
            (setq counter (1+ counter))))
        
        ;; Apply regular Markdown to Org transformations - in individual save-match-data blocks
        ;; Lists: Translate `-`, `*`, or `+` lists to Org-mode lists
        (save-match-data
          (goto-char (point-min))
          (while (re-search-forward "^\\([ \t]*\\)[*-+] \\(.*\\)$" nil t)
            (replace-match (concat (match-string 1) "- \\2"))))
        
        ;; Bold: `**bold**` -> `*bold*` only if directly adjacent
        (save-match-data
          (goto-char (point-min))
          (while (re-search-forward "\\*\\*\\([^ ]\\(.*?\\)[^ ]\\)\\*\\*" nil t)
            (replace-match "*\\1*")))
        
        ;; Italics: `_italic_` -> `/italic/`
        (save-match-data
          (goto-char (point-min))
          (while (re-search-forward "\\([ \n]\\)_\\([^ ].*?[^ ]\\)_\\([ \n]\\)" nil t)
            (replace-match "\\1/\\2/\\3")))
        
        ;; Links: `[text](url)` -> `[[url][text]]`
        (save-match-data
          (goto-char (point-min))
          (while (re-search-forward "\\[\\(.*?\\)\\](\\(.*?\\))" nil t)
            (replace-match "[[\\2][\\1]]")))
        
        ;; Inline code: `code` -> =code=
        (save-match-data
          (goto-char (point-min))
          (while (re-search-forward "`\\(.*?\\)`" nil t)
            (replace-match "=\\1=")))
        
        ;; Horizontal rules: `---` or `***` -> `-----`
        (save-match-data
          (goto-char (point-min))
          (while (re-search-forward "^\\(-{3,}\\|\\*{3,}\\)$" nil t)
            (replace-match "-----")))
        
        ;; Images: `![alt text](url)` -> `[[url]]`
        (save-match-data
          (goto-char (point-min))
          (while (re-search-forward "!\\[.*?\\](\\(.*?\\))" nil t)
            (replace-match "[[\\1]]")))
        
        ;; Headers: Adjust '#'
        (save-match-data
          (goto-char (point-min))
          (while (re-search-forward "^\\(#+\\) " nil t)
            (replace-match (make-string (length (match-string 1)) ?*) nil nil nil 1)))
        
        ;; Any extra characters
        (save-match-data
          (goto-char (point-min))
          (while (re-search-forward "—" nil t)
            (replace-match ", ")))
        
        ;; Restore code blocks with proper Org syntax
        (save-match-data
          (dolist (block (nreverse code-blocks))
            (let ((placeholder (nth 0 block))
                  (lang (nth 1 block))
                  (content (nth 2 block)))
              (goto-char (point-min))
              (when (search-forward placeholder nil t)
                (replace-match (format "#+begin_src %s\n%s#+end_src" lang content) t t)))))))))

(defun ollama-buddy-openai--get-full-model-name (model)
  "Get the full display name for MODEL with prefix."
  (concat ollama-buddy-openai-marker-prefix " " model))

(defun ollama-buddy--text-after-prompt ()
  "Get the text after the prompt:."
  (interactive)
  (save-excursion
    (goto-char (point-max))
    (if (re-search-backward ">> \\(?:PROMPT\\|SYSTEM PROMPT\\):" nil t)
        (progn
          (search-forward ":")
          (string-trim (buffer-substring-no-properties
                        (point) (point-max))))
      "")))

(defun ollama-buddy--get-command-def (command-name)
  "Get command definition for COMMAND-NAME."
  (assoc command-name ollama-buddy-command-definitions))

(defun ollama-buddy--get-command-prop (command-name prop)
  "Get property PROP from command COMMAND-NAME."
  (plist-get (cdr (ollama-buddy--get-command-def command-name)) prop))

(defun ollama-buddy--color-contrast (color1 color2)
  "Calculate contrast ratio between COLOR1 and COLOR2.
Returns a value between 1 and 21, where higher values indicate better contrast.
Based on WCAG 2.0 contrast algorithm."
  (let* ((rgb1 (color-name-to-rgb color1))
         (rgb2 (color-name-to-rgb color2))
         ;; Calculate relative luminance for each color
         (l1 (ollama-buddy--relative-luminance rgb1))
         (l2 (ollama-buddy--relative-luminance rgb2))
         ;; Ensure lighter color is l1
         (light (max l1 l2))
         (dark (min l1 l2)))
    ;; Contrast ratio formula
    (/ (+ light 0.05) (+ dark 0.05))))

(defun ollama-buddy--relative-luminance (rgb)
  "Calculate the relative luminance of RGB.
RGB should be a list of (r g b) values between 0 and 1."
  (let* ((r (nth 0 rgb))
         (g (nth 1 rgb))
         (b (nth 2 rgb))
         ;; Convert RGB to linear values (gamma correction)
         (r-linear (if (<= r 0.03928)
                       (/ r 12.92)
                     (expt (/ (+ r 0.055) 1.055) 2.4)))
         (g-linear (if (<= g 0.03928)
                       (/ g 12.92)
                     (expt (/ (+ g 0.055) 1.055) 2.4)))
         (b-linear (if (<= b 0.03928)
                       (/ b 12.92)
                     (expt (/ (+ b 0.055) 1.055) 2.4))))
    ;; Calculate luminance with RGB coefficients
    (+ (* 0.2126 r-linear)
       (* 0.7152 g-linear)
       (* 0.0722 b-linear))))

(defun ollama-buddy--hash-string-to-color (str)
  "Generate a consistent color based on the hash of STR with good contrast.
Adapts the color to the current theme (light or dark) for better visibility."
  (let* ((hash (abs (sxhash str)))
         ;; Generate HSL values - keeping saturation high for readability
         (hue (mod hash 360))
         (saturation 85)
         ;; Determine if background is light or dark
         (is-dark-background (eq (frame-parameter nil 'background-mode) 'dark))
         ;; Adjust lightness based on background (darker for light bg, lighter for dark bg)
         (base-lightness (if is-dark-background 65 45))
         ;; Avoid problematic hue ranges for visibility (e.g., yellows on white background)
         ;; Adjust lightness for problematic hues
         (lightness (cond
                     ;; Yellows (40-70) - make darker on light backgrounds
                     ((and (>= hue 40) (<= hue 70) (not is-dark-background))
                      (max 20 (- base-lightness 20)))
                     ;; Blues (180-240) - make lighter on dark backgrounds
                     ((and (>= hue 180) (<= hue 240) is-dark-background)
                      (min 80 (+ base-lightness 15)))
                     ;; Default lightness
                     (t base-lightness)))
         ;; Convert HSL to RGB
         (rgb-values (color-hsl-to-rgb (/ hue 360.0) (/ saturation 100.0) (/ lightness 100.0)))
         ;; Convert RGB to hex color
         (color (apply #'color-rgb-to-hex rgb-values))
         ;; Get foreground/background colors for contrast check
         (bg-color (face-background 'default))
         (target-color color))
    
    ;; Adjust saturation for better contrast if needed (fallback approach)
    (when (and bg-color
               (< (ollama-buddy--color-contrast bg-color target-color) 4.5))
      (let* ((adjusted-saturation (min 100 (+ saturation 10)))
             (adjusted-lightness (if is-dark-background
                                     (min 85 (+ lightness 10))
                                   (max 15 (- lightness 10))))
             (adjusted-rgb (color-hsl-to-rgb (/ hue 360.0)
                                             (/ adjusted-saturation 100.0)
                                             (/ adjusted-lightness 100.0))))
        (setq target-color (apply #'color-rgb-to-hex adjusted-rgb))))
    
    target-color))

(defun ollama-buddy--get-model-color (model)
  "Get the color associated with MODEL."
  (if ollama-buddy-enable-model-colors
      (or (gethash model ollama-buddy--model-colors)
          (ollama-buddy--hash-string-to-color model))
    (face-foreground 'default)))  ;; Returns the default foreground color

(defun ollama-buddy--param-shortname (param)
  "Create a 4-character shortened name for PARAM by using first 2 and last 2 chars.
For parameters with 4 or fewer characters, returns the full name."
  (let* ((param-name (symbol-name param))
         (param-len (length param-name)))
    (if (<= param-len 4)
        param-name
      (concat (substring param-name 0 2)
              (substring param-name (- param-len 2) param-len)))))

(defun ollama-buddy--prepare-prompt-area (&optional new-prompt keep-content system-prompt suffix-prompt)
  "Prepare the prompt area in the buffer.
When NEW-PROMPT is non-nil, replace the existing prompt area.
When KEEP-CONTENT is non-nil, preserve the existing prompt content.
When SYSTEM-PROMPT is non-nil, mark as a system prompt.
When SUFFIX-PROMPT is non-nil, mark as a suffix."
  (let* ((model (or ollama-buddy--current-model
                    ollama-buddy-default-model
                    "Default:latest"))
         (color (ollama-buddy--get-model-color model))
         (existing-content (when keep-content (ollama-buddy--text-after-prompt))))

    (let ((buf (get-buffer-create ollama-buddy--chat-buffer)))
      (with-current-buffer buf
        (let ((inhibit-read-only t))
          ;; Clean up existing prompt
          (goto-char (point-max))
          (when (re-search-backward "\\* .*>> \\(?:PROMPT\\|SYSTEM PROMPT\\|SUFFIX\\):" nil t)
            (beginning-of-line)
            (if (or new-prompt
                    (not (string-match-p "[[:alnum:]]" (ollama-buddy--text-after-prompt))))
                ;; Either replacing prompt or current prompt is empty
                (progn
                  (skip-chars-backward "\n")
                  (delete-region (point) (point-max))
                  (goto-char (point-max)))
              ;; Keeping prompt with content
              (goto-char (point-max))))
          
          ;; Insert new prompt header
          (let ((start (point)))
            (insert (format "\n\n* %s %s"
                            model
                            (cond
                             (system-prompt ">> SYSTEM PROMPT: ")
                             (suffix-prompt ">> SUFFIX: ")
                             (t ">> PROMPT: "))))
            
            ;; Apply overlay for model name
            (let ((overlay (make-overlay start (+ start 4 (length model)))))
              (overlay-put overlay 'face `(:foreground ,color :weight bold))))
          
          ;; Restore content if requested
          (when (and keep-content existing-content)
            (insert existing-content)))))))

;; API Interaction

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
        (when (not (string-empty-p (buffer-string)))
          (json-read-from-string (buffer-string)))))))

(defun ollama-buddy--make-request-async (endpoint method payload callback)
  "Make an asynchronous request to ENDPOINT using METHOD with PAYLOAD.
When complete, CALLBACK is called with the status response and result."
  (when (ollama-buddy--ollama-running)
    (let ((url-request-method method)
          (url-request-extra-headers '(("Content-Type" . "application/json")
                                       ("Connection" . "close")))
          (url-request-data (when payload (encode-coding-string payload 'utf-8)))
          (url (format "http://%s:%d%s"
                       ollama-buddy-host ollama-buddy-port endpoint)))
      (url-retrieve url 
                    (lambda (status)
                      (let ((result nil))
                        (unless (plist-get status :error)
                          ;; Only try to parse JSON if there was no error and we have content
                          (goto-char (point-min))
                          (re-search-forward "^$" nil t) ;; Skip headers
                          (when (and (not (= (point) (point-max)))
                                     (not (string-empty-p (buffer-substring-no-properties (point) (point-max)))))
                            (condition-case err
                                (setq result (json-read-from-string 
                                              (buffer-substring-no-properties (point) (point-max))))
                              (error
                               ;; If JSON parsing fails, just return the raw response
                               (message "Warning: Failed to parse JSON response: %s" (error-message-string err))))))
                        (funcall callback status result)))
                    nil t t))))

(defun ollama-buddy--ollama-running ()
  "Check if Ollama server is running using url.el."
  (let ((ollama-url (format "http://%s:%s/api/tags"
                            ollama-buddy-host ollama-buddy-port)))
    (condition-case nil
        (progn
          (url-retrieve-synchronously ollama-url)
          t)
      (error nil))))

(defun ollama-buddy--check-status ()
  "Check Ollama status with caching for better performance."
  (let ((current-time (float-time)))
    (when (or (null ollama-buddy--last-status-check)
              (> (- current-time ollama-buddy--last-status-check)
                 ollama-buddy--status-cache-ttl))
      (setq ollama-buddy--status-cache (ollama-buddy--ollama-running)
            ollama-buddy--last-status-check current-time))
    ollama-buddy--status-cache))

(defun ollama-buddy--get-models-with-others ()
  "Get all available models, including non ollama models."
  (let ((models (ollama-buddy--get-models)))
    (when (featurep 'ollama-buddy-openai)
      (dolist (model ollama-buddy-openai-models)
        (push (ollama-buddy-openai--get-full-model-name model) models)))
    (when (featurep 'ollama-buddy-claude)
      (dolist (model ollama-buddy-claude-models)
        (push (ollama-buddy-claude--get-full-model-name model) models)))
    models))

(defun ollama-buddy--get-models ()
  "Get available Ollama models with caching."
  (when (ollama-buddy--ollama-running)
    (let ((current-time (float-time)))
      (when (or (null ollama-buddy--models-cache-timestamp)
                (> (- current-time ollama-buddy--models-cache-timestamp)
                   ollama-buddy--models-cache-ttl))
        ;; Cache expired or not set - use synchronous version to refresh cache
        (when-let ((response (ollama-buddy--make-request "/api/tags" "GET")))
          (setq ollama-buddy--models-cache
                (mapcar #'car (ollama-buddy--get-models-with-colors-from-result response))
                ollama-buddy--models-cache-timestamp current-time)
          
          ;; Also refresh in background for next time
          (ollama-buddy--refresh-models-cache)))
      
      ollama-buddy--models-cache)))

(defun ollama-buddy--refresh-models-cache ()
  "Refresh the models cache in the background."
  (ollama-buddy--make-request-async 
   "/api/tags" 
   "GET" 
   nil
   (lambda (status result)
     (unless (plist-get status :error)
       (when result
         (setq ollama-buddy--models-cache
               (mapcar #'car (ollama-buddy--get-models-with-colors-from-result result))
               ollama-buddy--models-cache-timestamp (float-time)))))))

(defun ollama-buddy--get-models-with-colors-from-result (result)
  "Get available Ollama models with their associated colors from RESULT."
  (when result
    (mapcar (lambda (m)
              (let ((name (alist-get 'name m)))
                (cons name (ollama-buddy--hash-string-to-color name))))
            (alist-get 'models result))))

(defun ollama-buddy--get-models-with-colors ()
  "Get available Ollama models with their associated colors using cache."
  (when (ollama-buddy--ollama-running)
    (let ((current-time (float-time)))
      (when (or (null ollama-buddy--colors-cache-timestamp)
                (> (- current-time ollama-buddy--colors-cache-timestamp)
                   ollama-buddy--models-cache-ttl))
        ;; Cache expired or not set - use synchronous version to refresh cache
        (when-let ((response (ollama-buddy--make-request "/api/tags" "GET")))
          (setq ollama-buddy--colors-cache
                (ollama-buddy--get-models-with-colors-from-result response)
                ollama-buddy--colors-cache-timestamp current-time)
          
          ;; Also refresh in background for next time
          (ollama-buddy--refresh-colors-cache)))
      
      ollama-buddy--colors-cache)))

(defun ollama-buddy--refresh-colors-cache ()
  "Refresh the model colors cache in the background."
  (ollama-buddy--make-request-async 
   "/api/tags" 
   "GET" 
   nil
   (lambda (status result)
     (unless (plist-get status :error)
       (when result
         (setq ollama-buddy--colors-cache
               (ollama-buddy--get-models-with-colors-from-result result)
               ollama-buddy--colors-cache-timestamp (float-time)))))))

(defun ollama-buddy--get-running-models ()
  "Get list of currently running Ollama models with caching."
  (when (ollama-buddy--ollama-running)
    (let ((current-time (float-time)))
      (when (or (null ollama-buddy--running-models-cache-timestamp)
                (> (- current-time ollama-buddy--running-models-cache-timestamp)
                   ollama-buddy--models-cache-ttl))
        ;; Cache expired or not set - use synchronous version to refresh cache
        (when-let ((response (ollama-buddy--make-request "/api/ps" "GET")))
          (setq ollama-buddy--running-models-cache
                (mapcar (lambda (m) (alist-get 'name m))
                        (alist-get 'models response))
                ollama-buddy--running-models-cache-timestamp current-time)
          
          ;; Also refresh in background for next time
          (ollama-buddy--refresh-running-models-cache)))
      
      ollama-buddy--running-models-cache)))

(defun ollama-buddy--refresh-running-models-cache ()
  "Refresh the running models cache in the background."
  (ollama-buddy--make-request-async 
   "/api/ps" 
   "GET" 
   nil
   (lambda (status result)
     (unless (plist-get status :error)
       (when result
         (setq ollama-buddy--running-models-cache
               (mapcar (lambda (m) (alist-get 'name m))
                       (alist-get 'models result))
               ollama-buddy--running-models-cache-timestamp (float-time)))))))

(defun ollama-buddy--validate-model (model)
  "Validate MODEL availability."
  (when (and model (ollama-buddy--ollama-running))
    (when (member model (ollama-buddy--get-models-with-others))
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
                             (format "%s not available. Select model: "
                                     (or specified-model ""))
                             models nil t)))
              (setq ollama-buddy--current-model selected)
              (cons selected specified-model))
          (error "No Ollama models available"))))))

;; Parameter handling functions

(defun ollama-buddy--apply-command-parameters (params-alist)
  "Apply parameters from PARAMS-ALIST to the current Ollama request."
  ;; Save current parameters to restore later
  (setq ollama-buddy--saved-params-active (copy-tree ollama-buddy-params-active)
        ollama-buddy--saved-params-modified (copy-tree ollama-buddy-params-modified))
  
  ;; Apply new parameters
  (dolist (param-pair params-alist)
    (let ((param (car param-pair))
          (value (cdr param-pair)))
      (setf (alist-get param ollama-buddy-params-active) value)
      (add-to-list 'ollama-buddy-params-modified param))))

(defun ollama-buddy--restore-default-parameters ()
  "Restore parameters to their state before command execution."
  (when ollama-buddy--saved-params-active
    (setq ollama-buddy-params-active ollama-buddy--saved-params-active
          ollama-buddy-params-modified ollama-buddy--saved-params-modified)
    (setq ollama-buddy--saved-params-active nil
          ollama-buddy--saved-params-modified nil)))

(defun ollama-buddy-params-get-for-request ()
  "Get only the modified parameters formatted for the Ollama API request."
  (let ((params (make-hash-table)))
    ;; Only include explicitly modified parameters
    (dolist (param ollama-buddy-params-modified)
      (puthash param (alist-get param ollama-buddy-params-active)
               params))
    
    ;; Convert to an alist for the JSON encoding
    (let ((params-alist nil))
      (maphash (lambda (k v) (push (cons k v) params-alist)) params)
      params-alist)))

(defun ollama-buddy-apply-param-profile (profile-name)
  "Apply parameter PROFILE-NAME from `ollama-buddy-params-profiles'."
  (let ((profile (alist-get profile-name ollama-buddy-params-profiles nil nil #'string=)))
    (if (null profile)
        (message "Profile '%s' not found" profile-name)
      ;; Reset all parameters to defaults
      (setq ollama-buddy-params-active (copy-tree ollama-buddy-params-defaults)
            ollama-buddy-params-modified nil)
      ;; Apply profile-specific parameters
      (dolist (param-pair profile)
        (let ((param (car param-pair))
              (value (cdr param-pair)))
          (setf (alist-get param ollama-buddy-params-active) value)
          (add-to-list 'ollama-buddy-params-modified param)))
      (ollama-buddy--update-status "Profile Applied"))))

;; History-related functions

(defun ollama-buddy--add-to-history (role content)
  "Add message with ROLE and CONTENT to conversation history for current model."
  (when ollama-buddy-history-enabled
    (let* ((model ollama-buddy--current-model)
           (history (gethash model ollama-buddy--conversation-history-by-model nil)))
      
      ;; Create new history entry for this model if it doesn't exist
      (unless history
        (setq history nil))
      
      ;; Add the new message to this model's history
      ;; and put it at the end
      (setq history
            (append history
                    (list `((role . ,role)
                            (content . ,content)))))
      
      ;; Truncate history if needed
      (when (> (length history) (* 2 ollama-buddy-max-history-length))
        (setq history (seq-take history (* 2 ollama-buddy-max-history-length))))
      
      ;; Update the hash table with the modified history
      (puthash model history ollama-buddy--conversation-history-by-model))))

(defun ollama-buddy--get-history-for-request ()
  "Get history for the current request."
  (if ollama-buddy-history-enabled
      (let* ((model ollama-buddy--current-model)
             (history (gethash model ollama-buddy--conversation-history-by-model nil)))
        history)
    nil))

;; Model color functions
(defun ollama-buddy--update-model-colors ()
  "Update the model colors hash table and return it with caching."
  (when (ollama-buddy--ollama-running)
    ;; First update synchronously if needed
    (ollama-buddy--get-models-with-colors)
    
    ;; Update the hash table from the cache
    (dolist (pair ollama-buddy--colors-cache)
      (puthash (car pair) (cdr pair) ollama-buddy--model-colors))
    
    ;; Also refresh in background
    (ollama-buddy--make-request-async 
     "/api/tags" 
     "GET" 
     nil
     (lambda (status result)
       (unless (plist-get status :error)
         (when result
           (let ((models-with-colors (ollama-buddy--get-models-with-colors-from-result result)))
             (dolist (pair models-with-colors)
               (puthash (car pair) (cdr pair) ollama-buddy--model-colors))
             ;; Update cache too
             (setq ollama-buddy--colors-cache models-with-colors
                   ollama-buddy--colors-cache-timestamp (float-time)))))))
    
    ollama-buddy--model-colors))

;; Status update function
(defun ollama-buddy--update-status (status &optional original-model actual-model)
  "Update the Ollama status and refresh the display.
STATUS is the current operation status.
ORIGINAL-MODEL is the model that was requested.
ACTUAL-MODEL is the model being used instead."
  (setq ollama-buddy--status status)
  (with-current-buffer (get-buffer-create ollama-buddy--chat-buffer)
    (let* ((model (or ollama-buddy--current-model
                      ollama-buddy-default-model
                      "No Model"))
           (history (when (and ollama-buddy-show-history-indicator
                               ollama-buddy-history-enabled)
                      (let ((history-count (/ (length
                                               (gethash model
                                                        ollama-buddy--conversation-history-by-model
                                                        nil))
                                              2)))
                        (format "H%d" history-count))))
           (system-indicator (if ollama-buddy--current-system-prompt
                                 (let ((system-text (if (> (length ollama-buddy--current-system-prompt) 30)
                                                        (concat (substring ollama-buddy--current-system-prompt 0 27) "...")
                                                      ollama-buddy--current-system-prompt)))
                                   (format "[%s]" system-text))
                               ""))
           (params (when ollama-buddy-show-params-in-header
                     (let ((param-str
                            (mapconcat
                             (lambda (param)
                               (let ((value (alist-get param ollama-buddy-params-active)))
                                 (format "%s:%s"
                                         (ollama-buddy--param-shortname param)
                                         (cond
                                          ((floatp value) (format "%.1f" value))
                                          ((vectorp value) "...")
                                          (t value)))))
                             ollama-buddy-params-modified " ")))
                       (if (string-empty-p param-str)
                           ""
                         (format " [%s]" param-str))))))
      (setq header-line-format
            (concat
             (format " %s%s%s %s%s%s %s %s %s%s"
                     (if ollama-buddy-display-token-stats "T" "")
                     (if ollama-buddy-streaming-enabled "" "X")
                     (or history "")
                     (if ollama-buddy-convert-markdown-to-org "ORG" "Markdown")
                     (ollama-buddy--update-multishot-status)
                     (propertize (if (ollama-buddy--check-status) "" " OFFLINE")
                                 'face '(:weight bold))
                     (if (ollama-buddy--check-status)
                         (propertize model 'face `(:weight bold :box (:line-width 4 :style flat-button)))
                       (propertize model 'face `(:weight bold :inherit shadow :box (:line-width 4 :style flat-button))))
                     status
                     system-indicator
                     (or params ""))
             (when (and original-model actual-model (not (string= original-model actual-model)))
               (propertize (format " [Using %s instead of %s]" actual-model original-model)
                           'face '(:foreground "orange" :weight bold))))))))

(defun ollama-buddy--update-multishot-status ()
  "Update status line to show multishot progress."
  (if ollama-buddy--multishot-sequence
      (let* ((completed (upcase (substring ollama-buddy--multishot-sequence
                                           0 ollama-buddy--multishot-progress)))
             (remaining (substring ollama-buddy--multishot-sequence
                                   ollama-buddy--multishot-progress)))
        (concat (propertize " Multishot: " 'face '(:weight bold))
                (propertize completed 'face '(:weight bold))
                (propertize remaining 'face '(:weight normal))))
    ""))

;; Command handling functions
(defun ollama-buddy--display-system-prompt (system-prompt &optional timeout)
  "Display SYSTEM-PROMPT in the minibuffer for TIMEOUT seconds.
If TIMEOUT is nil, use a default of 2 seconds."
  (let ((timeout (or timeout 2))
        (message-text (if (string-empty-p system-prompt)
                          "No system prompt set"
                        (format "Using system prompt: %s"
                                (if (> (length system-prompt) 80)
                                    (concat (substring system-prompt 0 77) "...")
                                  system-prompt)))))
    ;; Display the message
    (message message-text)
    ;; Set a timer to clear it after timeout
    (run-with-timer timeout nil (lambda () (message nil)))))

(provide 'ollama-buddy-core)
;;; ollama-buddy-core.el ends here
