;;; clutch-evil.el --- Evil keybindings for Clutch -*- lexical-binding: t; -*-

;; Copyright (C) 2025-2026 Lucius Chen
;; SPDX-License-Identifier: GPL-3.0-or-later
;; Author: Lucius Chen <chenyh572@gmail.com>
;; Maintainer: Lucius Chen <chenyh572@gmail.com>
;; URL: https://github.com/LuciusChen/clutch
;; Keywords: evil, comm, data, tools

;; This file is not part of GNU Emacs.

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
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Optional Evil integration for Clutch, modeled on how Evil and Magit
;; cooperate: read-only console buffers start in motion state so navigation
;; keys work unmodified and unbound keys fall through to Clutch's own keymap,
;; editable SQL buffers start in normal state, and buffers where the user
;; types data (the REPL and insert forms) start in insert state.
;;
;; This file is an optional integration and is not required by `clutch'
;; itself: `clutch.el' is the composition root and must not depend on
;; optional integrations.  Load it explicitly after Evil:
;;
;;   (with-eval-after-load 'evil
;;     (require 'clutch-evil)
;;     (clutch-evil-setup))
;;
;; Loading the file runs `clutch-evil-setup' automatically when Evil is
;; present and `clutch-evil-integration' is non-nil.  `clutch-evil-setup'
;; is idempotent and can also be called interactively to re-apply the
;; configuration after changing the user options below.
;;
;; Initial states (all customizable):
;;
;;   motion  result, record, describe, mongodb and redis consoles, debug
;;           buffer (`clutch-evil-console-state')
;;   normal  SQL editing buffers (`clutch-evil-edit-state')
;;   insert  REPL and insert-row form (`clutch-evil-input-state')
;;
;; Per-surface keybindings (documented here as they are added):
;;
;;   - Read-only console navigation bindings (planned).
;;   - SQL editor bindings (planned).
;;   - REPL and insert-form bindings (planned).
;;
;; Contested single-letter keys follow the binding conflict survey in
;; tasks/02-conflict-survey.md: Clutch's workflow bindings win, with
;; `clutch-evil-use-*' defcustoms to restore the Evil convention where the
;; survey flagged a choice.

;;; Code:

;; Evil is an optional dependency: this file must byte-compile and
;; load in environments where Evil is not installed (e.g. MELPA
;; builds), and only activates when Evil is present.  Call the
;; function `evil-define-key*' rather than the `evil-define-key'
;; macro so byte-compiled output is correct regardless of whether
;; Evil was present at compile time.
(require 'evil nil t)

(declare-function evil-change-state "evil")
(declare-function evil-define-key* "evil")
(declare-function evil-set-initial-state "evil")

(defcustom clutch-evil-integration t
  "When non-nil, set up Evil states and keybindings when this file loads.
Set to nil before loading this file to opt out of the automatic
setup; `clutch-evil-setup' can still be called explicitly."
  :type 'boolean
  :group 'clutch)

(defcustom clutch-evil-console-state 'motion
  "Initial Evil state for Clutch's read-only console buffers.
The result, record, describe, document and debug buffers are
read-only; motion state provides Evil navigation while unbound
keys fall through to the mode's own keymap."
  :type '(choice (const :tag "Motion" motion)
                 (const :tag "Normal" normal)
                 (const :tag "Emacs" emacs)
                 symbol)
  :group 'clutch)

(defcustom clutch-evil-edit-state 'normal
  "Initial Evil state for Clutch's SQL editing buffers.
These buffers edit SQL text; normal state keeps Evil editing
conventions while the C-c command vocabulary stays unchanged."
  :type '(choice (const :tag "Normal" normal)
                 (const :tag "Motion" motion)
                 (const :tag "Emacs" emacs)
                 symbol)
  :group 'clutch)

(defcustom clutch-evil-input-state 'insert
  "Initial Evil state for buffers where the user types data.
Used for the `clutch-repl-mode' prompt and the insert-row form:
these buffers must accept typing immediately, like a shell."
  :type '(choice (const :tag "Insert" insert)
                 (const :tag "Normal" normal)
                 (const :tag "Emacs" emacs)
                 symbol)
  :group 'clutch)

;;;###autoload
(defun clutch-evil-setup ()
  "Set up Evil integration for Clutch.
Set initial Evil states for Clutch's major modes and install
Evil keybindings.  Safe to call more than once."
  (interactive)
  (unless (featurep 'evil)
    (user-error "clutch-evil: Evil is not loaded"))
  (dolist (mode '(clutch-result-mode
                  clutch-record-mode
                  clutch-describe-mode
                  clutch-mongodb-mode
                  clutch-redis-mode
                  clutch--debug-buffer-mode))
    (evil-set-initial-state mode clutch-evil-console-state))
  (dolist (mode '(clutch-mode
                  clutch--indirect-mode))
    (evil-set-initial-state mode clutch-evil-edit-state))
  (dolist (mode '(clutch-repl-mode
                  clutch--result-insert-major-mode))
    (evil-set-initial-state mode clutch-evil-input-state)))

;; Activate on load when Evil is present.
(when (and clutch-evil-integration (featurep 'evil))
  (clutch-evil-setup))

(provide 'clutch-evil)
;;; clutch-evil.el ends here
