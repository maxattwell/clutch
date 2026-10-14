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
;; Read-only console bindings (motion state):
;;
;;   n / p     down / up cell (record: next / prev row)
;;   N         next page
;;   g         rerun / refresh
;;   RET       open record (record: toggle field)
;;   TAB       next cell
;;   s         sort by column
;;   -         narrow column
;;   ?         transient dispatch menu
;;   v         full cell value (unless `clutch-evil-use-v-for-visual-state')
;;   /         client filter (unless `clutch-evil-use-slash-for-filter')
;;   { / }     first / last column
;;   |         shell command on cell
;;
;; `?' keeps Clutch's transient dispatch menus, so every EVIL-yielding
;; command (export, fullscreen, WHERE filter, count, agent copy, scroll)
;; remains reachable from dispatch.  `evil-snipe' is disabled in console
;; buffers so `s' keeps its Clutch binding (`clutch-evil-disable-snipe').
;; Evil's line motions keep the visual column, so point can land on a
;; cell border, which would clear the header's active-column highlight;
;; result buffers restore point into the remembered column
;; (`clutch-evil--restore-result-column').
;;
;; SQL editor bindings (planned):
;;
;;   - REPL and insert-form bindings (planned).
;;
;; Contested single-letter keys follow the binding conflict survey in
;; tasks/02-conflict-survey.md: Clutch's workflow bindings win, with
;; `clutch-evil-use-*' defcustoms to restore the Evil convention where the
;; survey flagged a choice.

;;; Code:

;; Requires cover the Clutch commands bound below; there is no top-level
;; `clutch' require because the composition root must not be a dependency
;; of integration modules.
(require 'clutch-object)
(require 'clutch-result)
(require 'clutch-ui)

;; Evil is an optional dependency: this file must byte-compile and
;; load in environments where Evil is not installed (e.g. MELPA
;; builds), and only activates when Evil is present.  Call the
;; function `evil-define-key*' rather than the `evil-define-key'
;; macro so byte-compiled output is correct regardless of whether
;; Evil was present at compile time.
(require 'evil nil t)

(declare-function evil-define-key* "evil")
(declare-function evil-define-minor-mode-key "evil")
(declare-function evil-set-initial-state "evil")
(declare-function evil-snipe-local-mode "evil-snipe")
(declare-function evil-snipe-override-local-mode "evil-snipe")

(defvar evil-state)

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
conventions while the `C-c' command vocabulary stays unchanged."
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

(defcustom clutch-evil-disable-snipe t
  "When non-nil, disable `evil-snipe' in Clutch console buffers.
evil-snipe's minor-mode keymaps outrank Clutch's console bindings
\(e.g. `s' for sorting), so setup turns the snipe minor modes off in
console buffers via the snipe mode hooks, mirroring the approach
used by other packages with single-letter console bindings."
  :type 'boolean
  :group 'clutch)

(defcustom clutch-evil-use-v-for-visual-state nil
  "When non-nil, leave `v' to Evil's visual state in console buffers.
By default `v' opens the full value of the cell at point in result
and record buffers."
  :type 'boolean
  :group 'clutch)

(defcustom clutch-evil-use-braces-for-columns t
  "When non-nil, bind `{' and `}' to first/last column in result buffers.
By default Clutch's column-jump bindings win; set to nil to restore
Evil's paragraph motions."
  :type 'boolean
  :group 'clutch)

(defcustom clutch-evil-use-slash-for-filter t
  "When non-nil, bind `/' to the client-side row filter in result buffers.
By default the local filter wins; set to nil to keep `evil-search-forward'
on `/' (isearch stays available on `C-s' either way)."
  :type 'boolean
  :group 'clutch)

(defcustom clutch-evil-use-pipe-for-goto-column nil
  "When non-nil, leave `|' to Evil's goto-column-N in result buffers.
By default `|' runs a shell command on the cell at point; numeric
column jumping stays on `C' either way."
  :type 'boolean
  :group 'clutch)

(defun clutch-evil--maybe-disable-snipe ()
  "Disable the `evil-snipe' minor modes in Clutch console buffers.
Added to the snipe mode hooks by `clutch-evil-setup' when
`clutch-evil-disable-snipe' is non-nil.  Mode hooks run on disable
as well as enable, so guard on the modes being active to avoid
recursing."
  (when (derived-mode-p 'clutch-result-mode
                        'clutch-record-mode
                        'clutch-describe-mode)
    (when (bound-and-true-p evil-snipe-local-mode)
      (evil-snipe-local-mode -1))
    (when (bound-and-true-p evil-snipe-override-local-mode)
      (evil-snipe-override-local-mode -1))))

(defun clutch-evil--bind-or-remove (state map key command enabled)
  "Bind KEY to COMMAND in STATE of MAP, or remove KEY when ENABLED is nil.
Used for the contested keys governed by `clutch-evil-use-*' options
so that re-running `clutch-evil-setup' applies the current values."
  (evil-define-key* state map key (if enabled command nil)))

(defun clutch-evil--restore-result-column ()
  "Keep point inside a result cell after Evil line motions.
Evil's line motions track the visual column, so point can end up on
a cell border where the `clutch-col-idx' property is absent; the
post-command sync then clears the header's active-column highlight.
When point sits inside the horizontal span of the column remembered
in `clutch--last-cell-position', move it back into that column's
cell on the current row.  When no column is remembered and point is
off the grid after a line motion (for example `j' from the row
gutter of a freshly rendered table), fall back to the remembered
or first cell of the current row.  Point moved elsewhere on purpose
\(`0' to the gutter, `h'/`l' between columns) stays where it is,
matching the vanilla behavior of clearing the highlight."
  (when (and clutch--column-widths
             (memq evil-state '(normal motion))
             (not (clutch--col-idx-at-point)))
    (let ((cidx (cdr-safe clutch--last-cell-position))
          (col (current-column)))
      (if (and cidx
               (>= col (clutch--column-border-position cidx))
               (< col (or (clutch--column-border-position (1+ cidx))
                          (- (line-end-position) (line-beginning-position)))))
          ;; Inside the remembered column's span: undo the line-motion
          ;; landing on the border.
          (when-let* ((cell-pos (text-property-any (line-beginning-position)
                                                   (line-end-position)
                                                   'clutch-col-idx cidx)))
            (goto-char cell-pos))
        ;; After an Evil line motion with no cell under point, re-enter
        ;; the grid in the remembered (or first) column of this row.
        ;; `evil-line-move' rewrites `this-command' to `next-line' or
        ;; `previous-line', so match both the evil names and theirs.
        (when (memq this-command '(next-line previous-line
                                   evil-next-line evil-previous-line
                                   evil-goto-first-line evil-goto-line))
          (clutch--goto-cell (clutch--row-idx-at-line) cidx))))))

(defun clutch-evil--init-result-buffer ()
  "Install Evil motion compatibility in a result buffer.
Runs the column restoration from `post-command-hook' before
Clutch's own cursor sync, which is appended without a depth and
therefore runs later."
  (add-hook 'post-command-hook #'clutch-evil--restore-result-column -50 t))

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
    (evil-set-initial-state mode clutch-evil-input-state))
  (evil-define-key* 'motion clutch-result-mode-map
    "n" #'clutch-result-down-cell
    "p" #'clutch-result-up-cell
    "N" #'clutch-result-next-page
    "g" #'clutch-result-rerun
    "s" #'clutch-result-sort-by-column
    "-" #'clutch-result-narrow-column
    "?" #'clutch-result-dispatch
    (kbd "RET") #'clutch-result-open-record
    (kbd "TAB") #'clutch-result-next-cell
    [tab] #'clutch-result-next-cell)
  (evil-define-key* 'motion clutch-record-mode-map
    "n" #'clutch-record-next-row
    "p" #'clutch-record-prev-row
    "g" #'clutch-record-refresh
    (kbd "RET") #'clutch-record-toggle-expand)
  (evil-define-key* 'motion clutch-describe-mode-map
    "g" #'clutch-describe-refresh)
  (add-hook 'clutch-result-mode-hook #'clutch-evil--init-result-buffer)
  (evil-define-minor-mode-key 'motion 'clutch-refine-mode
    (kbd "RET") #'clutch-refine-confirm)
  (clutch-evil--bind-or-remove
   'motion clutch-result-mode-map "v"
   #'clutch-result-view-value (not clutch-evil-use-v-for-visual-state))
  (clutch-evil--bind-or-remove
   'motion clutch-result-mode-map "{"
   #'clutch-result-first-column clutch-evil-use-braces-for-columns)
  (clutch-evil--bind-or-remove
   'motion clutch-result-mode-map "}"
   #'clutch-result-last-column clutch-evil-use-braces-for-columns)
  (clutch-evil--bind-or-remove
   'motion clutch-result-mode-map "/"
   #'clutch-result-filter clutch-evil-use-slash-for-filter)
  (clutch-evil--bind-or-remove
   'motion clutch-result-mode-map "|"
   #'clutch-result-shell-command-on-cell
   (not clutch-evil-use-pipe-for-goto-column))
  (clutch-evil--bind-or-remove
   'motion clutch-record-mode-map "v"
   #'clutch-record-view-value (not clutch-evil-use-v-for-visual-state))
  (when clutch-evil-disable-snipe
    (add-hook 'evil-snipe-local-mode-hook
              #'clutch-evil--maybe-disable-snipe)
    (add-hook 'evil-snipe-override-local-mode-hook
              #'clutch-evil--maybe-disable-snipe)))

;; Activate on load when Evil is present.
(when (and clutch-evil-integration (featurep 'evil))
  (clutch-evil-setup))

(provide 'clutch-evil)
;;; clutch-evil.el ends here
