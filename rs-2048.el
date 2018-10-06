;;; rs-2048.el --- Gabriele Cirulli's 2048 puzzle game.  -*- lexical-binding: t -*-

;; Copyright (C) 2018 Ralph Schleicher

;; Author: Ralph Schleicher <rs@ralph-schleicher.de>
;; Keywords: games
;; Version: 1.0

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation, either version 3 of
;; the License, or (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General
;; Public License along with this program.  If not,
;; see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Play Gabriele Cirulli's 2048 puzzle game in an Emacs buffer.
;; The terminal version looks like this:
;;
;;      ╔═══════╦═══════╦═══════╦═══════╗
;;      ║       ║       ║       ║       ║
;;      ║   2   ║       ║       ║       ║
;;      ║       ║       ║       ║       ║
;;      ╠═══════╬═══════╬═══════╬═══════╣
;;      ║       ║       ║       ║       ║
;;      ║   4   ║       ║       ║       ║
;;      ║       ║       ║       ║       ║
;;      ╠═══════╬═══════╬═══════╬═══════╣
;;      ║       ║       ║       ║       ║
;;      ║   16  ║       ║       ║       ║
;;      ║       ║       ║       ║       ║
;;      ╠═══════╬═══════╬═══════╬═══════╣
;;      ║       ║       ║       ║       ║
;;      ║  2048 ║   8   ║       ║       ║
;;      ║       ║       ║       ║       ║
;;      ╚═══════╩═══════╩═══════╩═══════╝
;;
;;      Score: 20096
;;      Moves: 925
;;
;; On graphics displays, the tiles are coloured!

;;; Code:

(require 'cl-lib)

;;;; Customization variables.

(defgroup rs-2048 nil
  "Gabriele Cirulli's 2048 puzzle game."
  :group 'games
  :prefix "rs-2048-")

(defcustom rs-2048-board-size 4
  "Size of the board, i.e. number of rows and columns.
You have to start a new game for this option to take effect."
  :type 'integer
  :group 'rs-2048)

(defcustom rs-2048-undo-depth 5
  "Number of moves to keep in the undo list.
Set to zero to disable undo."
  :type 'integer
  :group 'rs-2048)

(defcustom rs-2048-delay 0.5
  "Number of seconds to wait until a new tile is added to the board."
  :type 'float
  :group 'rs-2048)

(defcustom rs-2048-mode-hook nil
  "Hook run when preparing a 2048 buffer."
  :type 'hook
  :group 'rs-2048)

;;;; The game.

(defvar rs-2048-board nil
  "The playing board.")
(make-variable-buffer-local 'rs-2048-board)

(defvar rs-2048-score 0
  "The current score.")
(make-variable-buffer-local 'rs-2048-score)

(defvar rs-2048-moves 0
  "The current number of moves.")
(make-variable-buffer-local 'rs-2048-moves)

(defvar rs-2048-game-won-p nil
  "True means that the game is won, i.e. you managed to merge a 2048 tile.")
(make-variable-buffer-local 'rs-2048-game-won-p)

(defvar rs-2048-game-over-p nil
  "True means that the game is over.

A value of ‘won’ means that the user stopped the game after the winning
move; ‘full’ means that the board is filled with tiles; any other value
means that the game stopped unconditionally.")
(make-variable-buffer-local 'rs-2048-game-over-p)

(defvar rs-2048-undo-list ()
  "Stack of previous game states.")
(make-variable-buffer-local 'rs-2048-undo-list)

(defvar rs-2048-normal-indices ()
  "List of row/column indices in normal order.")
(make-variable-buffer-local 'rs-2048-normal-indices)

(defvar rs-2048-reverse-indices ()
  "List of row/column indices in reverse order.")
(make-variable-buffer-local 'rs-2048-reverse-indices)

(defun rs-2048-make-board ()
  "Create a new, empty playing board."
  (make-vector (expt rs-2048-board-size 2) 0))

(defsubst rs-2048-board-index (row column)
  "Return the linear index of the tile at ROW and COLUMN."
  (+ (* rs-2048-board-size row) column))

(defsubst rs-2048-get-tile (row column)
  "Return the tile value at ROW and COLUMN."
  (aref rs-2048-board (rs-2048-board-index row column)))

(defsubst rs-2048-set-tile (row column value)
  "Set the tile at ROW and COLUMN to VALUE."
  (aset rs-2048-board (rs-2048-board-index row column) value))

(defun rs-2048-initialize ()
  "Initialize local variables."
  (unless (and (natnump rs-2048-board-size) (> rs-2048-board-size 1))
    (error "Invalid 2048 board size"))
  (let (indices)
    (dotimes (k rs-2048-board-size)
      (push k indices))
    (setq rs-2048-board (rs-2048-make-board)
	  rs-2048-score 0
	  rs-2048-moves 0
	  rs-2048-game-won-p nil
	  rs-2048-game-over-p nil
	  rs-2048-undo-list ()
	  rs-2048-normal-indices (reverse indices)
	  rs-2048-reverse-indices indices)))

(defun rs-2048-state ()
  "Return the current game state."
  ;; TODO: Save random state, too.
  `((rs-2048-board . ,(copy-sequence rs-2048-board))
    (rs-2048-score . ,rs-2048-score)
    (rs-2048-moves . ,rs-2048-moves)
    (rs-2048-game-won-p . ,rs-2048-game-won-p)
    (rs-2048-game-over-p . ,rs-2048-game-over-p)))

(defun rs-2048-save-state (&optional state)
  "Save the current game state."
  (when (> rs-2048-undo-depth 0)
    (push (or state (rs-2048-state)) rs-2048-undo-list)
    (when (> (length rs-2048-undo-list) rs-2048-undo-depth)
      (setcdr (nthcdr (1- rs-2048-undo-depth) rs-2048-undo-list) nil))))

(defun rs-2048-restore-state ()
  "Restore the last saved game state.
Value is true if the state has been modified."
  (let ((state (pop rs-2048-undo-list)))
    (unless (null state)
      (dolist (binding state)
	(set (car binding) (cdr binding)))
      t)))

(defun rs-2048-count-empty-tiles ()
  "Return the number of empty tiles."
  (let ((c 0))
    (dolist (i rs-2048-normal-indices)
      (dolist (j rs-2048-normal-indices)
	(when (zerop (rs-2048-get-tile i j))
	  (incf c))))
    c))

(defun rs-2048-add-tile ()
  "Add a tile to the playing board.
Set ‘rs-2048-game-over-p’ to ‘full’ if the board is full."
  (let ((empty (rs-2048-count-empty-tiles)))
    (unless (zerop empty)
      (catch 'done
	(let ((k (random empty)))
	  (dolist (i rs-2048-normal-indices)
	    (dolist (j rs-2048-normal-indices)
	      (when (zerop (rs-2048-get-tile i j))
		(when (zerop k)
		  (let ((value (if (= (random 10) 0) 4 2)))
		    (rs-2048-set-tile i j value)
		    (throw 'done t)))
		(decf k))))))
      ;; If there was only one empty field, check if further moves
      ;; are possible.  Otherwise, the game is over.
      (catch 'done
	(when (= empty 1)
	  ;; Check horizontal slide.
	  (dolist (i rs-2048-normal-indices)
	    (dolist (j (rest rs-2048-normal-indices))
	      (when (= (rs-2048-get-tile i (1- j)) (rs-2048-get-tile i j))
		(throw 'done t))))
	  ;; Check vertical slide.
	  (dolist (j rs-2048-normal-indices)
	    (dolist (i (rest rs-2048-normal-indices))
	      (when (= (rs-2048-get-tile (1- i) j) (rs-2048-get-tile i j))
		(throw 'done t))))
	  ;; No equal adjacent tiles found.
	  (setq rs-2048-game-over-p 'full)))
      )))

(defvar rs-2048-dirty nil
  "True means that the board layout has changed.")

(defun rs-2048-slide-horizontally (column-indices step)
  "Slide tiles horizontally."
  (dolist (i rs-2048-normal-indices)
    (let (;; Target column for sliding tiles.
	  (k (first column-indices))
	  ;; Target value for merging tiles.
	  (v 0))
      (dolist (j column-indices)
	(let ((value (rs-2048-get-tile i j)))
	  (cond ((zerop value)) ;no-op
		((= value v)
		 ;; Merge tiles.
		 (incf value value)
		 (rs-2048-set-tile i j 0)
		 (rs-2048-set-tile i (- k step) value)
		 (setq rs-2048-dirty t)
		 ;; Update state variables.
		 (incf rs-2048-score value)
		 (when (= value 2048)
		   (setq rs-2048-game-won-p t))
		 ;; Need a new pair.
		 (setq v 0))
		(t
		 ;; Slide tile.
		 (when (/= j k)
		   (rs-2048-set-tile i j 0)
		   (rs-2048-set-tile i k value)
		   (setq rs-2048-dirty t))
		 ;; Column K is occupied with tile value V.
		 (setq v value)
		 (incf k step))
		))))))

(defun rs-2048-slide-vertically (row-indices step)
  "Slide tiles vertically."
  ;; Like ‘rs-2048-slide-horizontally’, but process each column
  ;; instead of each row.
  (dolist (j rs-2048-normal-indices)
    (let ((k (first row-indices))
	  (v 0))
      (dolist (i row-indices)
	(let ((value (rs-2048-get-tile i j)))
	  (cond ((zerop value))
		((= value v)
		 (incf value value)
		 (rs-2048-set-tile i j 0)
		 (rs-2048-set-tile (- k step) j value)
		 (setq rs-2048-dirty t)
		 (incf rs-2048-score value)
		 (when (= value 2048)
		   (setq rs-2048-game-won-p t))
		 (setq v 0))
		(t
		 (when (/= i k)
		   (rs-2048-set-tile i j 0)
		   (rs-2048-set-tile k j value)
		   (setq rs-2048-dirty t))
		 (setq v value)
		 (incf k step))
		))))))

(defun rs-2048-move (fun &rest arg)
  "Perform a move."
  (let (rs-2048-dirty)
    (cl-flet ((make-some-noise ()
		(ding)))
      (if rs-2048-game-over-p
	  (make-some-noise)
	(let ((state (rs-2048-state))
	      (wonp rs-2048-game-won-p))
	  (apply fun arg)
	  (when rs-2048-dirty
	    (rs-2048-save-state state)
	    (incf rs-2048-moves)
	    (rs-2048-redisplay)
	    (when (and (not wonp) rs-2048-game-won-p)
	      (make-some-noise)
	      (unless (y-or-n-p "You won!  Continue playing? ")
		(setq rs-2048-game-over-p 'won)
		(rs-2048-redisplay)))
	    (unless rs-2048-game-over-p
	      (rs-2048-add-tile)
	      (when rs-2048-game-over-p
		(make-some-noise))
	      (when (plusp rs-2048-delay)
		(sit-for rs-2048-delay))
	      (rs-2048-redisplay))))))))

(defun rs-2048-left ()
  "Slide tiles leftwards."
  (interactive)
  (rs-2048-move #'rs-2048-slide-horizontally rs-2048-normal-indices +1))

(defun rs-2048-right ()
  "Slide tiles rightwards."
  (interactive)
  (rs-2048-move #'rs-2048-slide-horizontally rs-2048-reverse-indices -1))

(defun rs-2048-up ()
  "Slide tiles upwards."
  (interactive)
  (rs-2048-move #'rs-2048-slide-vertically rs-2048-normal-indices +1))

(defun rs-2048-down ()
  "Slide tiles downwards."
  (interactive)
  (rs-2048-move #'rs-2048-slide-vertically rs-2048-reverse-indices -1))

(defun rs-2048-undo ()
  "Undo last move."
  (interactive)
  (when (rs-2048-restore-state)
    (rs-2048-redisplay)))

;;;; Visualization.

(defvar rs-2048-grid-face ()
  "Face attributes for grid lines.")

(defvar rs-2048-empty-face ()
  "Face attributes for empty fields.")

(defvar rs-2048-tile-face-alist ()
  "Alist of face attributes for tiles.
List elements are cons cells of the form

     (TILE-VALUE . FACE-ATTRIBUTES)

First element is the numerical value of a tile.
The rest are the associated face attributes.")

(defvar rs-2048-super-tile-face ()
  "Face attributes for super tiles, i.e. tiles not covered by ‘rs-2048-tile-face-alist’.")

(defun rs-2048-draw-board-colored ()
  (let ((tile-width 9)
	(tile-height 5)
	(top (point)))
    ;; Width of a vertical grid line are two characters.
    (let ((row (make-string (+ 2 (* rs-2048-board-size (+ tile-width 2))) ? ))
	  (face rs-2048-grid-face))
      (dotimes (c (+ 1 (* rs-2048-board-size (+ tile-height 1))))
	(let ((start (point)))
	  (insert row)
	  (and face (set-text-properties start (point) `(face ,face)))
	  (insert "\n"))))
    ;; Add tile colours.
    (goto-char top)
    (dolist (i rs-2048-normal-indices)
      ;; Skip over horizontal grid line.
      (forward-line)
      (dotimes (c tile-height)
	(dolist (j rs-2048-normal-indices)
	  (let* ((value (rs-2048-get-tile i j))
		 (face (or (and (= value 0) rs-2048-empty-face)
			   (assoc value rs-2048-tile-face-alist)
			   rs-2048-super-tile-face)))
	    ;; Skip over vertical grid line.
	    (forward-char 2)
	    ;; Insert tile value.
	    (when (and (= c 2) (> value 0))
	      (let* ((str (format "%d" value))
		     (length (length str))
		     (pad (- tile-width length))
		     (post (/ pad 2)) ;truncated by Emacs Lisp
		     (pre (- pad post)))
		(save-excursion
		  (forward-char pre)
		  (delete-char length)
		  (insert str))))
	    ;; Set face properties.
	    (let ((start (point)))
	      (forward-char tile-width)
	      (and face (set-text-properties start (point) `(face ,face))))))
	(forward-line)))
    (goto-char (point-max))))

(defun rs-2048-draw-board-boxed ()
  (let ((tile-width 7)
	(tile-height 3))
    (cl-flet ((draw-row (box-char)
		(let ((pad (make-string tile-width (aref box-char 0))))
		  (insert (aref box-char 1))
		  (dolist (j rs-2048-normal-indices)
		    (when (> j 0)
		      (insert (aref box-char 2)))
		    (insert pad))
		  (insert (aref box-char 3) "\n"))))
      ;; Top grid line.
      (draw-row "═╔╦╗")
      (dolist (i rs-2048-normal-indices)
	;; Intermediate grid line.
	(when (> i 0)
	  (draw-row "═╠╬╣"))
	;; Vertical padding.
	(dotimes (c (/ (1- tile-height) 2))
	  (draw-row " ║║║"))
	;; Tile values.
	(dolist (j rs-2048-normal-indices)
	  (insert ?║)
	  (let ((value (rs-2048-get-tile i j)))
	    (if (zerop value)
		(insert (make-string tile-width ? ))
	      (let* ((str (format "%d" value))
		     (pad (- tile-width (length str)))
		     (post (/ pad 2)) ;truncated by Emacs Lisp
		     (pre (- pad post)))
		(insert (make-string pre ? ) str (make-string post ? ))))))
	(insert ?║ "\n")
	;; Vertical padding.
	(dotimes (c (/ (1- tile-height) 2))
	  (draw-row " ║║║")))
      ;; Bottom grid line.
      (draw-row "═╚╩╝"))))

(defun rs-2048-redisplay ()
  (let ((inhibit-read-only t))
    (erase-buffer)
    (insert "\n"
	    "Join the numbers and get to the 2048 tile!\n"
	    "\n")
    ;; Draw the playing board.
    (cond ((display-graphic-p)
	   (rs-2048-draw-board-colored))
	  (t
	   (rs-2048-draw-board-boxed)))
    ;; Display the state of the game.
    (insert "\n"
	    (format "Score: %d\n" rs-2048-score)
	    (format "Moves: %d\n" rs-2048-moves)
	    "\n")
    (cond ((eq rs-2048-game-over-p 'won)
	   (insert "You won!\n"))
	  (rs-2048-game-over-p
	   (insert "Game over!\n"))
	  (t
	   (insert "Use your arrow keys to move the tiles.  When two tiles\n"
		   "with the same number touch, they merge into one.\n"))))
  (goto-char (point-min))
  ;; Force redisplay.
  (redisplay t))

;;;; Major mode.

(defvar rs-2048-mode-map
  (let ((map (make-sparse-keymap)))
    (suppress-keymap map t)
    (define-key map "?"     #'describe-mode)
    (define-key map "n"     #'rs-2048-new-game)
    (define-key map "q"     #'rs-2048-quit-game)
    (define-key map "z"     #'rs-2048-quit-game)
    (define-key map "u"     #'rs-2048-undo)
    (define-key map [left]  #'rs-2048-left)
    (define-key map [right] #'rs-2048-right)
    (define-key map [up]    #'rs-2048-up)
    (define-key map [down]  #'rs-2048-down)
    (when nil
      (define-key map "h" #'rs-2048-left)
      (define-key map "j" #'rs-2048-down)
      (define-key map "k" #'rs-2048-up)
      (define-key map "l" #'rs-2048-right))
    map)
  "Key bindings for playing 2048.")

(easy-menu-define rs-2048-mode-menu rs-2048-mode-map
  "Menu bar item for 2048 buffers."
  '("2048"
    ["New Game..." rs-2048-new-game t]
    ["Quit Game"   rs-2048-quit-game t]
    "---"
    ["Move Left"  rs-2048-left t]
    ["Move Right" rs-2048-right t]
    ["Move Up"    rs-2048-up t]
    ["Move Down"  rs-2048-down t]
    "---"
    ["Undo" rs-2048-undo t]
    "---"
    ["Customize Options" rs-2048-customize-options t]
    ["Switch Color Theme..." rs-2048-color-theme t]))

(define-derived-mode rs-2048-mode special-mode "2048"
  "Major mode for playing 2048.

Use your arrow keys to move the tiles.  When two tiles with the same
number touch, they merge into one."
  (setq buffer-read-only t
        truncate-lines t
	cursor-type nil)
  (buffer-disable-undo))

;;;###autoload
(defun rs-2048 ()
  "Play 2048."
  (interactive)
  (switch-to-buffer "*2048*")
  (unless (eq major-mode 'rs-2048-mode)
    (rs-2048-mode))
  (when (or (null rs-2048-board) (/= (length rs-2048-board) (expt rs-2048-board-size 2)))
    (rs-2048-new-game)))

;;;###autoload
(defalias 'play-2048 'rs-2048)

;;;###autoload
(defalias '2048-game 'rs-2048)

(defun rs-2048-new-game ()
  "Start a new game."
  (interactive)
  (when (if (called-interactively-p 'interactive)
	    (y-or-n-p "Start a new game? ")
	  t)
    (rs-2048-initialize)
    ;; Add first two tiles.
    (rs-2048-add-tile)
    (rs-2048-add-tile)
    ;; Update board.
    (rs-2048-redisplay)))

(defun rs-2048-quit-game ()
  "Stop playing 2048."
  (interactive)
  (switch-to-buffer (other-buffer)))

(defun rs-2048-customize-options ()
  (interactive)
  (customize-group 'rs-2048 t))

(defun rs-2048-color-theme (theme)
  "Select a color theme."
  (interactive
   (list (let ((tem (completing-read "Color theme: " '(default gabriele none) nil t nil nil 'default)))
	   (if (stringp tem) (intern tem) tem))))
  (ecase theme
    ((default t)
     ;; Tile background colours interpolated from CET-L17 colour map,
     ;; see «https://peterkovesi.com/projects/colourmaps/».  The grey
     ;; levels are derived from the CIE L*a*b* lightness of the tiles.
     ;;
     ;;      Tile |  Colour |   Grey
     ;;     ------+---------+---------
     ;;         2 | #F4EFC4 | #EDEDED
     ;;         4 | #F2D99E | #DBDBDB
     ;;         8 | #F4C183 | #CACACA
     ;;        16 | #F5A771 | #B9B9B9
     ;;        32 | #F48C69 | #A8A8A8
     ;;        64 | #EF7069 | #979797
     ;;       128 | #E5546F | #878787
     ;;       256 | #D5387A | #777777
     ;;       512 | #BD2287 | #686868
     ;;      1024 | #9B1994 | #585858
     ;;      2048 | #6C21A0 | #4A4A4A
     ;;         * | #002AA8 | #3C3C3C
     ;;
     ;; Code:
     ;;
     ;; (in-package :rs-colors)
     ;; (multiple-value-bind (L)
     ;;     (cie-lab-color-coordinates
     ;;      (make-srgb-color-from-number #xF4EFC4 :byte-size 8))
     ;;   (print-color-html
     ;;    (make-cie-lab-color L 0 0 srgb-white-point))
     ;;   (terpri))
     (setq rs-2048-grid-face              '(:foreground "#000000" :background "#A8A8A8")
	   rs-2048-empty-face             '(:foreground "#3C3C3C" :background "#DBDBDB")
	   rs-2048-tile-face-alist '((    2 :foreground "#3C3C3C" :background "#F4EFC4" :weight bold)
				     (    4 :foreground "#3C3C3C" :background "#F2D99E" :weight bold)
				     (    8 :foreground "#3C3C3C" :background "#F4C183" :weight bold)
				     (   16 :foreground "#3C3C3C" :background "#F5A771" :weight bold)
				     (   32 :foreground "#EDEDED" :background "#F48C69" :weight bold)
				     (   64 :foreground "#EDEDED" :background "#EF7069" :weight bold)
				     (  128 :foreground "#EDEDED" :background "#E5546F" :weight bold)
				     (  256 :foreground "#EDEDED" :background "#D5387A" :weight bold)
				     (  512 :foreground "#EDEDED" :background "#BD2287" :weight bold)
				     ( 1024 :foreground "#EDEDED" :background "#9B1994" :weight bold)
				     ( 2048 :foreground "#EDEDED" :background "#6C21A0" :weight bold))
	   rs-2048-super-tile-face        '(:foreground "#EDEDED" :background "#002AA8" :weight bold)))
    (gabriele
     ;; Colours from «https://gabrielecirulli.github.io/2048/style/main.css».
     (setq rs-2048-grid-face 	         '(:foreground "#000000" :background "#BBADA0")
	   rs-2048-empty-face            '(:foreground "#776E65" :background "#CCBFB4")
	   rs-2048-tile-face-alist '((   2 :foreground "#776E65" :background "#EEE4DA" :weight bold)
				     (   4 :foreground "#776E65" :background "#EDE0C8" :weight bold)
				     (   8 :foreground "#F9F6F2" :background "#F2B179" :weight bold)
				     (  16 :foreground "#F9F6F2" :background "#F59563" :weight bold)
				     (  32 :foreground "#F9F6F2" :background "#F67C5F" :weight bold)
				     (  64 :foreground "#F9F6F2" :background "#F65E3B" :weight bold)
				     ( 128 :foreground "#F9F6F2" :background "#EDCF72" :weight bold)
				     ( 256 :foreground "#F9F6F2" :background "#EDCC61" :weight bold)
				     ( 512 :foreground "#F9F6F2" :background "#EDC850" :weight bold)
				     (1024 :foreground "#F9F6F2" :background "#EDC53F" :weight bold)
				     (2048 :foreground "#F9F6F2" :background "#EDC22E" :weight bold))
	   rs-2048-super-tile-face       '(:foreground "#F9F6F2" :background "#3C3A32" :weight bold)))
    ((none nil)
     (setq rs-2048-grid-face       '(:background "#A8A8A8")
	   rs-2048-empty-face      '(:background "#DBDBDB")
	   rs-2048-super-tile-face '(:background "#EDEDED" :weight bold)
	   rs-2048-tile-face-alist  ())))
  (let ((buffer (get-buffer "*2048*")))
    (when (not (null buffer))
      (with-current-buffer buffer
	(rs-2048-redisplay))))
  (values))

;; Not bound.
(defvar rs-2048-initialized)
(eval-when (compile load eval)
  (unless (boundp 'rs-2048-initialized)
    (rs-2048-color-theme 'default)
    (setq rs-2048-initialized t)))

(provide 'rs-2048)

;;; rs-2048.el ends here
