;;; ollama-buddy-claude.el --- Anthropic Claude integration for ollama-buddy -*- lexical-binding: t; -*-

;; Author: James Dyer <captainflasmr@gmail.com>
;; Keywordsisend: applications, tools, convenience
;; Package-Requires: ((emacs "28.1") (url "1.2"))

;;; Commentary:
;; This extension provides Anthropic Claude integration for the ollama-buddy package.
;; It allows users to interact with Anthropic's Claude language models using the same interface
;; as ollama-buddy, providing seamless switching between local Ollama models and
;; cloud-based Claude models.

;;; Code:

(require 'json)
(require 'url)
(require 'cl-lib)
(require 'ollama-buddy-core)

(defgroup ollama-buddy-claude nil
  "Anthropic Claude integration for Ollama Buddy."
  :group 'ollama-buddy
  :prefix "ollama-buddy-claude-")

(defcustom ollama-buddy-claude-api-key ""
  "API key for accessing Anthropic Claude services.
Get your key from https://console.anthropic.com/."
  :type 'string
  :group 'ollama-buddy-claude)

(defcustom ollama-buddy-claude-default-model "claude-3-7-sonnet-20250219"
  "Default Claude model to use."
  :type 'string
  :group 'ollama-buddy-claude)

(defcustom ollama-buddy-claude-api-endpoint "https://api.anthropic.com/v1/messages"
  "Endpoint for Anthropic Claude API."
  :type 'string
  :group 'ollama-buddy-claude)

(defcustom ollama-buddy-claude-temperature 0.7
  "Temperature setting for Claude requests (0.0-1.0).
Lower values make the output more deterministic, higher values more creative."
  :type 'float
  :group 'ollama-buddy-claude)

(defcustom ollama-buddy-claude-max-tokens nil
  "Maximum number of tokens to generate in the response.
Use nil for API default behavior (adaptive)."
  :type '(choice integer (const nil))
  :group 'ollama-buddy-claude)

(defcustom ollama-buddy-claude-show-loading t
  "Whether to show a loading indicator during API requests."
  :type 'boolean
  :group 'ollama-buddy-claude)

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

;; Internal variables
(defvar ollama-buddy-claude--model-colors (make-hash-table :test 'equal)
  "Hash table for storing Claude model colors.")

(defvar ollama-buddy-claude--conversation-history-by-model (make-hash-table :test 'equal)
  "Hash table mapping model names to their conversation histories.")

(defvar ollama-buddy-claude--current-response nil
  "Accumulates the current response content.")

(defvar ollama-buddy-claude--current-prompt nil
  "The current prompt sent to Claude.")

(defvar ollama-buddy-claude--current-token-count 0
  "Counter for tokens in the current Claude response.")

(defvar ollama-buddy-claude--current-model nil
  "The currently selected Claude model.")

;; Model display and management functions

(defun ollama-buddy-claude--get-model-color (model)
  "Get color for Claude MODEL."
  (or (gethash model ollama-buddy-claude--model-colors)
      (let ((color (ollama-buddy--hash-string-to-color model)))
        (puthash model color ollama-buddy-claude--model-colors)
        color)))

(defun ollama-buddy-claude--get-full-model-name (model)
  "Get the full model name with prefix for MODEL."
  (concat ollama-buddy-claude-marker-prefix model))

(defun ollama-buddy-claude--is-claude-model (model)
  "Check if MODEL is a Claude model by checking for the prefix."
  (and model (string-prefix-p ollama-buddy-claude-marker-prefix model)))

(defun ollama-buddy-claude--get-real-model-name (model)
  "Extract the actual model name from the prefixed MODEL string."
  (if (ollama-buddy-claude--is-claude-model model)
      (string-trim (substring model (length ollama-buddy-claude-marker-prefix)))
    model))

;; API interaction functions

(defun ollama-buddy-claude--verify-api-key ()
  "Verify that the API key is set."
  (if (string-empty-p ollama-buddy-claude-api-key)
      (progn
        (customize-variable 'ollama-buddy-claude-api-key)
        (error "Please set your Anthropic Claude API key"))
    t))

(defun ollama-buddy-claude--send (prompt &optional model)
  "Send PROMPT to Claude's API using MODEL or default model asynchronously using `url-retrieve`."
  (when (ollama-buddy-claude--verify-api-key)
    ;; Set up the current model
    (setq ollama-buddy-claude--current-model
          (or model 
              ollama-buddy-claude--current-model
              (ollama-buddy-claude--get-full-model-name ollama-buddy-claude-default-model)))

    ;; Store the prompt and initialize response
    (setq ollama-buddy-claude--current-prompt prompt
          ollama-buddy-claude--current-response "")

    ;; Initialize token counter
    (setq ollama-buddy-claude--current-token-count 0)

    ;; Ensure max_tokens is always set
    (let* ((history (when ollama-buddy-history-enabled
                      (gethash ollama-buddy-claude--current-model
                               ollama-buddy-claude--conversation-history-by-model
                               nil)))
           (system-prompt ollama-buddy--current-system-prompt)
           (messages (vconcat []
                              (append
                               (when (and system-prompt (not (string-empty-p system-prompt)))
                                 `(((role . "system") (content . ,system-prompt))))
                               history
                               `(((role . "user") (content . ,prompt))))))
           (max-tokens (or ollama-buddy-claude-max-tokens 4096)) ;; Ensure max_tokens is always set
           ;; Prepare the full payload
           (json-payload
            `((model . ,(ollama-buddy-claude--get-real-model-name ollama-buddy-claude--current-model))
              (messages . ,messages)
              (temperature . ,ollama-buddy-claude-temperature)
              (max_tokens . ,max-tokens))) ;; Always include max_tokens
           (json-str (encode-coding-string (json-encode json-payload) 'utf-8))
           (url-request-method "POST")
           (url-request-extra-headers
            `(("Content-Type" . "application/json")
              ("Authorization" . ,(concat "Bearer " ollama-buddy-claude-api-key))
              ("X-API-Key" . ,ollama-buddy-claude-api-key)
              ("anthropic-version" . "2023-06-01")))
           (url-request-data json-str)
           (endpoint "https://api.anthropic.com/v1/messages"))

      ;; Prepare chat buffer
      (with-current-buffer (get-buffer-create ollama-buddy--chat-buffer)
        (pop-to-buffer (current-buffer))
        (goto-char (point-max))
        (let ((inhibit-read-only t)
              (display-name ollama-buddy-claude--current-model))
          ;; Add model info to response header
          (insert (propertize (format "\n\n** [%s: RESPONSE]" display-name)
                              'face `(:inherit bold :foreground
                                               ,(ollama-buddy-claude--get-model-color display-name)))
                  "\n\n")
          ;; Show loading message
          (insert "Loading response...")

          ;; Update status
          (ollama-buddy--update-status "Sending request to Claude...")

          ;; Send request via `url-retrieve`
          (url-retrieve
           endpoint
           (lambda (status)
             (goto-char (point-min))
             (if (not (search-forward "\n\n" nil t))
                 (message "Error: Malformed HTTP response.")
               (let* ((json-object-type 'alist)
                      (json-array-type 'vector)
                      (json-key-type 'symbol)
                      (response (ignore-errors (json-read)))
                      (error-message (alist-get 'error response))
                      (content ""))

                 ;; Check for API errors
                 (if error-message
                     (setq content (format "Error: %s" (alist-get 'message error-message)))
                   ;; Extract the content based on the new API response format
                   (let ((extracted-text ""))
                     ;; Get the content array from the response
                     (let ((content-obj (alist-get 'content response)))
                       (if (listp content-obj)
                           ;; Handle new API format where content is an object containing an array
                           (let ((content-array (alist-get 'content content-obj)))
                             (if (vectorp content-array)
                                 ;; Process each content item in the array
                                 (dotimes (i (length content-array))
                                   (let* ((item (aref content-array i))
                                         (item-type (alist-get 'type item))
                                         (item-text (alist-get 'text item)))
                                     (when (and (string= item-type "text") item-text)
                                       (setq extracted-text (concat extracted-text item-text)))))
                               ;; Handle case where content.content is not a vector
                               (message "Unexpected content format: %S" content-array)))
                         ;; Handle case where content is already the array
                         (if (vectorp content-obj)
                             (dotimes (i (length content-obj))
                               (let* ((item (aref content-obj i))
                                     (item-type (alist-get 'type item))
                                     (item-text (alist-get 'text item)))
                                 (when (and (string= item-type "text") item-text)
                                   (setq extracted-text (concat extracted-text item-text)))))
                           (message "Unexpected response format: %S" content-obj))))
                     (setq content extracted-text)))

                 ;; Update the chat buffer
                 (with-current-buffer ollama-buddy--chat-buffer
                   (let ((inhibit-read-only t))
                     (goto-char (point-max))
                     (delete-region (line-beginning-position) (point-max))
                     (insert content)

                     ;; Convert markdown to org if enabled
                     (when ollama-buddy-convert-markdown-to-org
                       (ollama-buddy--md-to-org-convert-region (point-min) (point-max)))

                     ;; Add to history
                     (setq ollama-buddy-claude--current-response content)
                     (when ollama-buddy-history-enabled
                       (ollama-buddy-claude--add-to-history "user" prompt)
                       (ollama-buddy-claude--add-to-history "assistant" content))
                     
                     ;; Calculate token count
                     (setq ollama-buddy-claude--current-token-count
                           (length (split-string content "\\b" t)))

                     ;; Show token stats if enabled
                     (when ollama-buddy-display-token-stats
                       (insert (format "\n\n*** Token Stats\n[%d tokens]"
                                       ollama-buddy-claude--current-token-count)))

                     (insert "\n\n*** FINISHED")
                     (ollama-buddy--prepare-prompt-area)
                     (ollama-buddy--update-status
                      (format "Finished [%d tokens]" 
                              ollama-buddy-claude--current-token-count))))))))
          nil t)))))

;; History management functions

(defun ollama-buddy-claude--add-to-history (role content)
  "Add message with ROLE and CONTENT to Claude conversation history."
  (when ollama-buddy-history-enabled
    (let* ((model ollama-buddy-claude--current-model)
           (history (gethash model ollama-buddy-claude--conversation-history-by-model nil)))
      
      ;; Create new history entry for this model if it doesn't exist
      (unless history
        (setq history nil))
      
      ;; Add the new message to this model's history
      (setq history
            (append history
                    (list `((role . ,role)
                            (content . ,content)))))
      
      ;; Truncate history if needed
      (when (and (boundp 'ollama-buddy-max-history-length)
                 (> (length history) (* 2 ollama-buddy-max-history-length)))
        (setq history (seq-take history (* 2 ollama-buddy-max-history-length))))
      
      ;; Update the hash table with the modified history
      (puthash model history ollama-buddy-claude--conversation-history-by-model))))

(defun ollama-buddy-claude-select-model ()
  "Select a Claude model to use."
  (interactive)
  (let* ((models (mapcar (lambda (m) (ollama-buddy-claude--get-full-model-name m))
                         ollama-buddy-claude-models))
         (selected (completing-read "Select Claude model: " models nil t)))
    (setq ollama-buddy-claude--current-model selected)
    (setq ollama-buddy--current-model selected) ; Share with main package
    
    ;; Update the chat buffer
    (with-current-buffer (get-buffer-create ollama-buddy--chat-buffer)
      (pop-to-buffer (current-buffer))
      (ollama-buddy--prepare-prompt-area)
      (goto-char (point-max)))
    
    (message "Selected Claude model: %s" 
             (ollama-buddy-claude--get-real-model-name selected))))

(defun ollama-buddy-claude-clear-history ()
  "Clear the conversation history for the current Claude model."
  (interactive)
  (let ((model ollama-buddy-claude--current-model))
    (remhash model ollama-buddy-claude--conversation-history-by-model)
    (message "Claude conversation history cleared for %s" model)))

(defun ollama-buddy-claude-display-history ()
  "Display the conversation history for the current Claude model."
  (interactive)
  (let* ((model ollama-buddy-claude--current-model)
         (history (gethash model ollama-buddy-claude--conversation-history-by-model nil))
         (buf (get-buffer-create "*Claude Conversation History*")))
    
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "Claude Conversation History for %s:\n\n" model))
        
        (if (null history)
            (insert "No conversation history available.")
          (let ((history-count (/ (length history) 2)))
            (insert (format "Current history: %d message pairs\n\n" history-count))
            
            ;; Display the history in chronological order
            (dolist (msg history)
              (let* ((role (alist-get 'role msg))
                     (content (alist-get 'content msg))
                     (role-face (if (string= role "user")
                                    '(:inherit bold)
                                  '(:inherit bold))))
                (insert (propertize (format "[%s]: " (upcase role)) 'face role-face))
                (insert (format "%s\n\n" content))))))
        
        (view-mode 1)))
    
    (display-buffer buf)))

(defun ollama-buddy-claude-configure ()
  "Configure Claude integration settings."
  (interactive)
  (customize-group 'ollama-buddy-claude))

;; Integration with the main package

(defun ollama-buddy-claude-initialize ()
  "Initialize Claude integration for ollama-buddy."
  (interactive)
  
  ;; Add Claude models to the available models list for completion
  (dolist (model ollama-buddy-claude-models)
    (let ((full-name (ollama-buddy-claude--get-full-model-name model)))
      ;; Generate and store a color for this model
      (puthash full-name (ollama-buddy--hash-string-to-color full-name)
               ollama-buddy-claude--model-colors)))
  
  ;; Set up the key for API authentication if not set
  (when (string-empty-p ollama-buddy-claude-api-key)
    (message "Claude API key not set. Use M-x ollama-buddy-claude-configure to set it"))
  
  (message "Claude integration initialized. Use M-x ollama-buddy-claude-select-model to choose a model"))

;; User commands to expose

;;;###autoload
(defun ollama-buddy-claude-setup ()
  "Setup the Claude integration."
  (interactive)
  (ollama-buddy-claude-initialize)
  (ollama-buddy-claude-configure))

;; Hook into ollama-buddy's model selection and invoke functions
;; This function should be called when ollama-buddy is loaded
(defun ollama-buddy-claude--hook-into-ollama-buddy ()
  "Hook Claude functionality into the main ollama-buddy package."
  ;; Add handler for Claude models to the send-prompt function
  (advice-add 'ollama-buddy--send-prompt :around
              (lambda (orig-fun prompt &optional model)
                (let ((model-to-use (or model ollama-buddy--current-model)))
                  (if (and model-to-use (ollama-buddy-claude--is-claude-model model-to-use))
                      (ollama-buddy-claude--send prompt model-to-use)
                    (funcall orig-fun prompt model-to-use))))))

;; Register the hook function to be called when ollama-buddy is loaded
(add-hook 'ollama-buddy-after-load-hook 'ollama-buddy-claude--hook-into-ollama-buddy)

(provide 'ollama-buddy-claude)
;;; ollama-buddy-claude.el ends here
