;;; tool-islands-tests.el --- Tests for tool-islands -*- lexical-binding: t; -*-

(require 'ert)
(require 'magit-section)
(require 'tool-islands)

(ert-deftest tool-islands-tree-compacts-single-folders ()
  (let* ((items '("a/b/c/x.el" "a/b/c/y.el" "a/d.el" "e.el"))
         (tree (tool-islands-tree-build items #'identity)))
    ;; "a" holds a file, so it stays; "b" holds only "c", so they merge.
    (should (equal (mapcar #'car (nth 1 tree)) '("a")))
    (should (equal (mapcar #'car (nth 1 (car (nth 1 tree)))) '("b/c")))
    (should (equal (nth 2 tree) '("e.el")))
    (should (= (length (tool-islands-tree-items tree)) 4))))

(ert-deftest tool-islands-row-marks-depth ()
  (with-temp-buffer
    (tool-islands-row 2 "name")
    (should (equal (buffer-string) "name\n"))
    (should (= (get-text-property 1 'tool-islands-depth) 2))
    (should (get-text-property 1 'line-prefix))
    (should (seq-some (lambda (o) (overlay-get o 'tool-islands-chevron))
                      (overlays-at 1)))))

(ert-deftest tool-islands-row-width-counts-indent ()
  (with-temp-buffer
    (tool-islands-row 1 "x")
    (should (= (tool-islands-row-width 1 2)
               (+ tool-islands-row-inset tool-islands-indent tool-islands-state-width
                  (string-pixel-width "x" (current-buffer)))))))

(ert-deftest tool-islands-pill-cap-square-is-space ()
  (let ((cap (tool-islands-pill-cap 'left 0 20 "#ffffff" 4)))
    (should (equal (get-text-property 0 'display cap) '(space :width (4) :height (20))))))

(ert-deftest tool-islands-fit-marks-span ()
  (should (get-text-property 0 'tool-islands-fit (tool-islands-fit "abc"))))

(ert-deftest tool-islands-view-in-section-buffer ()
  (with-temp-buffer
    (magit-section-mode)
    (tool-islands-view-setup)
    (let ((inhibit-read-only t))
      (magit-insert-section (root)
        (magit-insert-section (item 'a)
          (tool-islands-row 0 (tool-islands-fit "Item"))
          (magit-insert-heading))))
    (tool-islands-draw-chevrons)
    (should tool-islands-view)
    (goto-char (point-min))
    (tool-islands-highlight)
    (should (= (length tool-islands-hl) 1))))


(ert-deftest tool-islands-pane-rejected-resize-settles ()
  (save-window-excursion
    (with-temp-buffer
      (switch-to-buffer (current-buffer))
      (let* ((frame (selected-frame))
             (window (selected-window))
             (target (+ 20 (window-pixel-width window)))
             (attempts 0)
             (tool-islands-refit-function #'ignore))
        (unwind-protect
            (cl-letf (((symbol-function 'window-resize)
                       (lambda (&rest _) (cl-incf attempts) (error "At minimum")))
                      ((symbol-function 'tool-islands-pane--dragged-p) #'ignore))
              (set-window-parameter window 'tool-islands-pane-width (lambda () target))
              (tool-islands-pane-fit frame)
              (dotimes (_ 3) (tool-islands-pane-follow frame))
              (should (= attempts 1))
              (cl-incf target)
              (tool-islands-pane-follow frame)
              (should (= attempts 2)))
          (set-window-parameter window 'tool-islands-pane-width nil)
          (set-frame-parameter frame 'tool-islands-pane-last-attempt nil))))))

(ert-deftest tool-islands-pane-skips-child-frames ()
  (cl-letf (((symbol-function 'frame-parent) (lambda (_) t))
            ((symbol-function 'window-list) (lambda (&rest _) (ert-fail "Child inspected"))))
    (tool-islands-pane-fit 'child)
    (tool-islands-pane-follow 'child)))

(ert-deftest tool-islands-button-renderer-preserves-interaction ()
  (let* ((tool-islands-button-render-function
          (lambda (label primary)
            (should primary)
            (concat "custom " label)))
         (button (tool-islands-button "Apply" #'ignore "Apply changes" t))
         (map (get-text-property 0 'local-map button)))
    (should (equal (substring-no-properties button) "custom Apply"))
    (should (equal (get-text-property 0 'help-echo button) "Apply changes"))
    (should (commandp (lookup-key map [header-line down-mouse-1])))
    (should (eq (get-text-property 0 'mouse-face button) 'tool-islands-toolbar-hover))))

(ert-deftest tool-islands-plain-and-rounded-button-fallback ()
  (let ((tool-islands-button-render-function #'tool-islands-button-text))
    (cl-letf (((symbol-function 'tool-islands-button-image)
               (lambda (&rest _) (ert-fail "Plain buttons must not render SVG"))))
      (should-not (get-text-property 0 'display (tool-islands-button "Commit" #'ignore "Commit" t)))))
  (cl-letf (((symbol-function 'expui-icons-svg-p) (lambda () nil)))
    (should (equal (tool-islands-button-rounded "Commit" t)
                   (tool-islands-button-text "Commit" t)))))

(ert-deftest tool-islands-selection-spacing-follows-options ()
  (let ((tool-islands-hl-radius 0) (tool-islands-hl-margin 0))
    (should (= (tool-islands-fit-margin) 4))
    (should (eq (car (get-text-property 0 'display
                                      (tool-islands-pill-cap 'left 0 20 "red")))
                'space)))
  (let ((tool-islands-hl-radius 6) (tool-islands-hl-margin 6))
    (should (= (tool-islands-fit-margin) 16))))

(ert-deftest tool-islands-header-centers-font-and-keeps-explicit-ascent ()
  (let ((tool-islands-header-height 1.5)
        (tool-islands-header-padding 4)
        (tool-islands-header-ascent nil)
        (tool-islands-button-render-function #'tool-islands-button-text))
    (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) t))
              ((symbol-function 'face-font) (lambda (&rest _) "test-font"))
              ((symbol-function 'font-info)
               (lambda (&rest _) [nil nil 20 20 0 0 0 10 15 5])))
      (let ((spec (cdr (tool-islands-header-space 0))))
        (should (equal (plist-get spec :height) '(30)))
        (should (= (plist-get spec :ascent) 67)))
      (let ((tool-islands-header-ascent 68))
        (should (= (plist-get (cdr (tool-islands-header-space 0)) :ascent) 68)))
      (let ((tool-islands-button-render-function #'tool-islands-button-rounded))
        (cl-letf (((symbol-function 'frame-char-height) (lambda (&rest _) 30)))
          (should (equal (plist-get (cdr (tool-islands-header-space 0)) :height) '(50))))))))

(ert-deftest tool-islands-header-delegates-exact-editor-metrics ()
  (let ((tool-islands-header-space-function
         (lambda (width) `(space :width ,width :height 1.9 :ascent 68))))
    (dolist (width '(0 (12)))
      (should (equal (tool-islands-header-space width)
                     `(space :width ,width :height 1.9 :ascent 68))))))

(ert-deftest tool-islands-pane-fit-reaches-sub-character-target ()
  "A pixel target must not be rounded away and retried on every size hook."
  (let* ((window (selected-window))
         (frame (selected-frame))
         (old-width (window-parameter window 'tool-islands-pane-width))
         (actual 256) (resizes 0)
         (tool-islands-refit-function #'ignore))
    (unwind-protect
        (progn
          (set-window-parameter window 'tool-islands-pane-width (lambda () 259))
          (cl-letf (((symbol-function 'window-list) (lambda (&rest _) (list window)))
                    ((symbol-function 'window-pixel-width) (lambda (_) actual))
                    ((symbol-function 'window-resize)
                     (lambda (_ delta &rest _args)
                       (cl-incf resizes)
                       ;; Match Emacs' rounding with an eight-pixel cell.
                       (cl-incf actual (if window-resize-pixelwise delta
                                         (* 8 (round delta 8)))))))
            (tool-islands-pane-fit frame)
            (should (= actual 259))
            (tool-islands-pane-follow frame)
            (should (= resizes 1))))
      (set-window-parameter window 'tool-islands-pane-width old-width))))

(ert-deftest tool-islands-pane-fit-skips-zero-delta-resize ()
  "Opening another pane must not resize a pane already at its target."
  (let* ((window (selected-window))
         (old-width (window-parameter window 'tool-islands-pane-width))
         (width (window-pixel-width window))
         (resizes 0)
         (tool-islands-refit-function #'ignore))
    (unwind-protect
        (progn
          (set-window-parameter window 'tool-islands-pane-width (lambda () width))
          (cl-letf (((symbol-function 'window-list) (lambda (&rest _) (list window)))
                    ((symbol-function 'window-resize)
                     (lambda (&rest _) (cl-incf resizes))))
            (tool-islands-pane-fit (selected-frame))
            (should (= resizes 0))))
      (set-window-parameter window 'tool-islands-pane-width old-width))))

(ert-deftest tool-islands-pane-knows-a-drag ()
  ;; `this-command' names no drag: its motions run from a transient map.
  (let ((this-command nil))
    (let ((track-mouse 'dragging)
          (last-input-event '(mouse-movement)))
      (should (tool-islands-pane--dragged-p)))
    (let ((track-mouse nil)
          (last-input-event '(drag-mouse-1)))
      (should (tool-islands-pane--dragged-p)))
    (let ((track-mouse nil)
          (last-input-event ?a))
      (should-not (tool-islands-pane--dragged-p)))))

(ert-deftest tool-islands-pane-ends-with-its-buffer ()
  (let ((window (selected-window))
        (shown (window-buffer))
        (width #'ignore))
    (unwind-protect
        (with-temp-buffer
          (set-window-parameter window 'tool-islands-pane-width width)
          (set-window-parameter window 'tool-islands-pane-buffer shown)
          (should (eq (tool-islands-pane--width window) width))
          (set-window-buffer window (current-buffer))
          (should-not (tool-islands-pane--width window)))
      (set-window-buffer window shown)
      (set-window-parameter window 'tool-islands-pane-width nil)
      (set-window-parameter window 'tool-islands-pane-buffer nil))))

;;; tool-islands-tests.el ends here
