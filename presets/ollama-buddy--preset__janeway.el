(setq ollama-buddy-command-definitions
      '(
        ;; Genreal Commands
        (open-chat
         :key ?o
         :description "Open chat buffer"
         :action (lambda ()
                   (pop-to-buffer (get-buffer-create ollama-buddy--chat-buffer))
                   (when (= (buffer-size) 0)
                     (insert (ollama-buddy--create-intro-message))
                     (ollama-buddy--show-prompt))
                   (goto-char (point-max))))
        
        (show-models
         :key ?v
         :description "View model status"
         :action ollama-buddy-show-model-status)
        
        (swap-model
         :key ?m
         :description "Swap model"
         :action ollama-buddy--swap-model)
        
        (help
         :key ?h
         :description "Help assistant"
         :action (lambda ()
                   (pop-to-buffer (get-buffer-create ollama-buddy--chat-buffer))
                   (goto-char (point-max))
                   (insert (ollama-buddy--create-intro-message))
                   (ollama-buddy--show-prompt)))
        
        (send-region
         :key ?l
         :description "Send region"
         :action (lambda () (ollama-buddy--send-with-command 'send-region)))
        
        ;; Custom Starfleet-style transformations
        
        (captains-log
         :key ?c
         :description "Rewrite as a Captain's Log"
         :model nil
         :prompt "Rework this text into a Starfleet Captain’s Log entry, using precise but reflective language:"
         :action (lambda () (ollama-buddy--send-with-command 'captains-log)))

        (starfleet-briefing
         :key ?b
         :description "Make it a Starfleet mission briefing"
         :model nil
         :prompt "Rewrite the selected text as a professional Starfleet briefing, structured and to the point:"
         :action (lambda () (ollama-buddy--send-with-command 'starfleet-briefing)))

        (borg-negotiation
         :key ?n
         :description "Rewrite as a negotiation with the Borg"
         :model nil
         :prompt "Transform this text into a tense negotiation with the Borg, maintaining diplomacy but firm resistance:"
         :action (lambda () (ollama-buddy--send-with-command 'borg-negotiation)))

        (technobabble-enhance
         :key ?t
         :description "Enhance with Starfleet technobabble"
         :model nil
         :prompt "Rework this text to include appropriate Starfleet technobabble, making it sound scientifically complex but logical:"
         :action (lambda () (ollama-buddy--send-with-command 'technobabble-enhance)))

        (delta-quadrant-danger
         :key ?d
         :description "Add Delta Quadrant-style peril"
         :model nil
         :prompt "Rewrite the selected text to sound like a Starfleet crew facing an unknown and perilous Delta Quadrant anomaly:"
         :action (lambda () (ollama-buddy--send-with-command 'delta-quadrant-danger)))

        (replicate-coffee
         :key ?r
         :description "Make it about coffee (Janeway mode!)"
         :model nil
         :prompt "Modify the selected text to include a reference to coffee in a way that would make Captain Janeway proud:"
         :action (lambda () (ollama-buddy--send-with-command 'replicate-coffee)))

        (prime-directive
         :key ?p
         :description "Make it a Prime Directive dilemma"
         :model nil
         :prompt "Rewrite this as a Starfleet ethical dilemma involving the Prime Directive, balancing logic, morality, and duty:"
         :action (lambda () (ollama-buddy--send-with-command 'prime-directive)))
        
        ;; System Commands
        (custom-prompt
         :key ?e
         :description "Custom prompt"
         :action (lambda ()
                   (when-let ((prefix (read-string "Enter prompt prefix: " nil nil nil t)))
                     (unless (use-region-p)
                       (user-error "No region selected. Select text to use with prompt"))
                     (unless (not (string-empty-p prefix))
                       (user-error "Input string is empty"))
                     (ollama-buddy--send
                      (concat prefix "\n\n"
                              (buffer-substring-no-properties 
                               (region-beginning) (region-end)))))))
        (minibuffer-prompt
         :key ?i
         :description "Minibuffer Prompt"
         :action (lambda ()
                   (when-let ((prefix (read-string "Enter prompt: " nil nil nil t)))
                     (unless (not (string-empty-p prefix))
                       (user-error "Input string is empty"))
                     (ollama-buddy--send prefix))))
        (save-chat
         :key ?s
         :description "Save chat"
         :action (lambda ()
                   (with-current-buffer ollama-buddy--chat-buffer
                     (write-region (point-min) (point-max)
                                   (read-file-name "Save conversation to: ")
                                   'append-to-file
                                   nil))))
        (kill-request
         :key ?x
         :description "Kill request"
         :action (lambda ()
                   (delete-process ollama-buddy--active-process)))
        (quit
         :key ?q
         :description "Quit"
         :action (lambda () (message "Quit Ollama Shell menu.")))
        )
      )
