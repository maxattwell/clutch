;;; clutch-test-evil.el --- ERT tests for clutch-evil integration -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Tests for the optional Evil integration.  Skipped in CI environments
;; without Evil; run locally with Evil on the load path.

;;; Code:

(require 'ert)
(require 'clutch-test-common)

(require 'clutch-evil)

(require 'evil nil t)

(defun clutch-test-evil--aux-binding (mode-map state key)
  "Return the binding of KEY in the STATE auxiliary map of MODE-MAP."
  (let ((aux (lookup-key mode-map (vector (intern (format "%s-state" state))))))
    (should (keymapp aux))
    (lookup-key aux key)))

(ert-deftest clutch-test-evil-console-states-registered ()
  "Console buffers get the configured motion state."
  (skip-unless (featurep 'evil))
  (clutch-evil-setup)
  (dolist (mode '(clutch-result-mode clutch-record-mode
                  clutch-describe-mode clutch-mongodb-mode
                  clutch-redis-mode clutch--debug-buffer-mode))
    (should (eq (evil-initial-state mode) clutch-evil-console-state)))
  (should (eq (evil-initial-state 'clutch-mode) clutch-evil-edit-state))
  (should (eq (evil-initial-state 'clutch-repl-mode) clutch-evil-input-state)))

(ert-deftest clutch-test-evil-result-navigation-bound ()
  "Result console motion bindings win over Evil's state map."
  (skip-unless (featurep 'evil))
  (clutch-evil-setup)
  (should (eq (clutch-test-evil--aux-binding clutch-result-mode-map 'motion "n")
              #'clutch-result-down-cell))
  (should (eq (clutch-test-evil--aux-binding clutch-result-mode-map 'motion "p")
              #'clutch-result-up-cell))
  (should (eq (clutch-test-evil--aux-binding clutch-result-mode-map 'motion "N")
              #'clutch-result-next-page))
  (should (eq (clutch-test-evil--aux-binding clutch-result-mode-map 'motion "g")
              #'clutch-result-rerun))
  (should (eq (clutch-test-evil--aux-binding clutch-result-mode-map 'motion "s")
              #'clutch-result-sort-by-column))
  (should (eq (clutch-test-evil--aux-binding clutch-result-mode-map 'motion "-")
              #'clutch-result-narrow-column))
  (should (eq (clutch-test-evil--aux-binding clutch-result-mode-map 'motion "?")
              #'clutch-result-dispatch))
  (should (eq (clutch-test-evil--aux-binding clutch-result-mode-map 'motion "\r")
              #'clutch-result-open-record))
  (should (eq (clutch-test-evil--aux-binding clutch-result-mode-map 'motion "\t")
              #'clutch-result-next-cell)))

(ert-deftest clutch-test-evil-result-contested-keys-respect-options ()
  "Contested result keys follow the `clutch-evil-use-*' options."
  (skip-unless (featurep 'evil))
  (let ((clutch-evil-use-v-for-visual-state nil)
        (clutch-evil-use-braces-for-columns t)
        (clutch-evil-use-slash-for-filter t)
        (clutch-evil-use-pipe-for-goto-column nil))
    (clutch-evil-setup)
    (should (eq (clutch-test-evil--aux-binding clutch-result-mode-map 'motion "v")
                #'clutch-result-view-value))
    (should (eq (clutch-test-evil--aux-binding clutch-result-mode-map 'motion "{")
                #'clutch-result-first-column))
    (should (eq (clutch-test-evil--aux-binding clutch-result-mode-map 'motion "}")
                #'clutch-result-last-column))
    (should (eq (clutch-test-evil--aux-binding clutch-result-mode-map 'motion "/")
                #'clutch-result-filter))
    (should (eq (clutch-test-evil--aux-binding clutch-result-mode-map 'motion "|")
                #'clutch-result-shell-command-on-cell)))
  (let ((clutch-evil-use-v-for-visual-state t)
        (clutch-evil-use-braces-for-columns nil)
        (clutch-evil-use-slash-for-filter nil)
        (clutch-evil-use-pipe-for-goto-column t))
    (clutch-evil-setup)
    (should-not (clutch-test-evil--aux-binding clutch-result-mode-map 'motion "v"))
    (should-not (clutch-test-evil--aux-binding clutch-result-mode-map 'motion "{"))
    (should-not (clutch-test-evil--aux-binding clutch-result-mode-map 'motion "}"))
    (should-not (clutch-test-evil--aux-binding clutch-result-mode-map 'motion "/"))
    (should-not (clutch-test-evil--aux-binding clutch-result-mode-map 'motion "|"))))

(ert-deftest clutch-test-evil-record-navigation-bound ()
  "Record console motion bindings win over Evil's state map."
  (skip-unless (featurep 'evil))
  (clutch-evil-setup)
  (should (eq (clutch-test-evil--aux-binding clutch-record-mode-map 'motion "n")
              #'clutch-record-next-row))
  (should (eq (clutch-test-evil--aux-binding clutch-record-mode-map 'motion "p")
              #'clutch-record-prev-row))
  (should (eq (clutch-test-evil--aux-binding clutch-record-mode-map 'motion "g")
              #'clutch-record-refresh))
  (should (eq (clutch-test-evil--aux-binding clutch-record-mode-map 'motion "\r")
              #'clutch-record-toggle-expand))
  (should (eq (clutch-test-evil--aux-binding clutch-record-mode-map 'motion "v")
              #'clutch-record-view-value)))

(ert-deftest clutch-test-evil-describe-and-refine-bound ()
  "Describe refresh and refine confirm are reachable in motion state."
  (skip-unless (featurep 'evil))
  (clutch-evil-setup)
  (should (eq (clutch-test-evil--aux-binding clutch-describe-mode-map 'motion "g")
              #'clutch-describe-refresh))
  (should (eq (lookup-key (evil-get-minor-mode-keymap 'motion 'clutch-refine-mode)
                          "\r")
              #'clutch-refine-confirm)))

(ert-deftest clutch-test-evil-motion-restores-remembered-column ()
  "Evil line motions keep the header highlight on the remembered column.
Evil motions keep the visual column, so point can land on a cell
border where `clutch-col-idx' is absent; the post-command hook must
move point back into the remembered column's cell.  Deliberate moves
to a different horizontal position (row gutter, previous column) are
left alone so the highlight still clears, matching vanilla Clutch."
  (skip-unless (featurep 'evil))
  (clutch-evil-setup)
  (with-temp-buffer
    (clutch-test--setup-rendered-result)
    (evil-change-to-initial-state)
    ;; The restoration only acts when an Evil state is active; bind it
    ;; explicitly because the batch suite does not enable `evil-mode'.
    (let ((evil-state 'motion))
      (clutch--goto-cell 0 1)
      (clutch--sync-result-cursor-ui)
      (should (eql clutch--header-active-col 1))
      ;; On the border before column 1: restored into the remembered column.
      (goto-char (+ (aref clutch--row-start-positions 1)
                    (clutch--column-border-position 1)))
      (should-not (clutch--col-idx-at-point))
      (clutch-evil--restore-result-column)
      (clutch--sync-result-cursor-ui)
      (should (eql (clutch--col-idx-at-point) 1))
      (should (eql clutch--header-active-col 1))
      ;; On the row gutter: a deliberate move, highlight stays cleared.
      (goto-char (aref clutch--row-start-positions 1))
      (clutch-evil--restore-result-column)
      (clutch--sync-result-cursor-ui)
      (should-not clutch--header-active-col)
      ;; Inside the previous column's span (past the gutter): deliberate.
      (goto-char (+ (aref clutch--row-start-positions 1) 10))
      (clutch-evil--restore-result-column)
      (clutch--sync-result-cursor-ui)
      (should (eql (clutch--col-idx-at-point) 0)))))

(ert-deftest clutch-test-evil-line-motion-enters-grid-from-gutter ()
  "Evil line motions from the row gutter enter the grid.
A freshly rendered table leaves point in the gutter with nothing
remembered; the first `j' must land in a cell so the header
highlight appears instead of staying off permanently."
  (skip-unless (featurep 'evil))
  (clutch-evil-setup)
  (with-temp-buffer
    (clutch-test--setup-rendered-result)
    (evil-change-to-initial-state)
    (let ((evil-state 'motion)
          (this-command 'next-line))
      (should-not (clutch--col-idx-at-point))
      (call-interactively 'evil-next-line)
      (clutch-evil--restore-result-column)
      (clutch--sync-result-cursor-ui)
      (should (clutch--col-idx-at-point))
      (should clutch--header-active-col)
      ;; `0' stays a deliberate gutter visit: highlight clears.
      (setq this-command 'evil-beginning-of-line)
      (beginning-of-line)
      (clutch-evil--restore-result-column)
      (clutch--sync-result-cursor-ui)
      (should-not clutch--header-active-col))))

(provide 'clutch-test-evil)
;;; clutch-test-evil.el ends here