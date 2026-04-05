;;;; functions to implement arrays

;;;; This software is part of the SBCL system. See the README file for
;;;; more information.
;;;;
;;;; This software is derived from the CMU CL system, which was
;;;; written at Carnegie Mellon University and released into the
;;;; public domain. The software is in the public domain and is
;;;; provided with absolutely no warranty. See the COPYING and CREDITS
;;;; files for more information.

(in-package "SB-VM")

(declaim (inline adjustable-array-p
                 array-displacement))

;;;; miscellaneous accessor functions

;;; These functions are only needed by the interpreter, 'cause the
;;; compiler inlines them.
(macrolet ((def (name)
             `(progn
                (defun ,name (array)
                  (,name array))
                (defun (setf ,name) (value array)
                  (setf (,name array) value)))))
  (def %array-fill-pointer)
  (def %array-available-elements)
  (def %array-data)
  (def %array-displacement)
  (def %array-displaced-p)
  (def %array-displaced-from))

(defun %array-dimension (array axis)
  (%array-dimension array axis))

(defun %check-bound (array bound index)
  (declare (type index bound)
           (fixnum index))
  (%check-bound array bound index))

(defun check-bound (array bound index)
  (declare (type index bound)
           (fixnum index))
  (%check-bound array bound index)
  index)

(defun %with-array-data/fp (array start end)
  (%with-array-data-macro array start end :check-bounds t :check-fill-pointer t))

(defun %with-array-data (array start end)
  (%with-array-data-macro array start end :check-bounds t :array-header-p t))

(defun %data-vector-and-index (array index)
  (if (array-header-p array)
      (multiple-value-bind (vector index)
          (%with-array-data array index nil)
        (values vector index))
      (values (truly-the (simple-array * (*)) array) index)))

(defun sb-c::%data-vector-and-index/check-bound (array index)
  (%check-bound array (array-dimension array 0) index)
  (%data-vector-and-index array index))


;;;; MAKE-ARRAY
(declaim (inline %integer-vector-widetag-and-n-bits-shift))
(defun %integer-vector-widetag-and-n-bits-shift (signed high)
  (let ((unsigned-table
          #.(let ((map (make-array (1+ n-word-bits))))
              (loop for saetp across
                    (reverse *specialized-array-element-type-properties*)
                    for ctype = (saetp-ctype saetp)
                    when (and (numeric-type-p ctype)
                              (eq (numeric-type-class ctype) 'integer)
                              (zerop (numeric-type-low ctype)))
                    do (fill map (cons (saetp-typecode saetp)
                                       (saetp-n-bits-shift saetp))
                             :end (1+ (integer-length (numeric-type-high ctype)))))
              map))
        (signed-table
          #.(let ((map (make-array (1+ n-word-bits))))
              (loop for saetp across
                    (reverse *specialized-array-element-type-properties*)
                    for ctype = (saetp-ctype saetp)
                    when (and (numeric-type-p ctype)
                              (eq (numeric-type-class ctype) 'integer)
                              (minusp (numeric-type-low ctype)))
                    do (fill map (cons (saetp-typecode saetp)
                                       (saetp-n-bits-shift saetp))
                             :end (+ (integer-length (numeric-type-high ctype)) 2)))
              map)))
    (cond ((or (not (fixnump high))
               (> high n-word-bits))
           (values #.simple-vector-widetag
                   #.(1- (integer-length n-word-bits))))
          (signed
           (let ((x (aref signed-table high)))
             (values (car x) (cdr x))))
          (t
           (let ((x (aref unsigned-table high)))
             (values (car x) (cdr x)))))))

;;; This is a bit complicated, but calling subtypep over all
;;; specialized types is exceedingly slow
(defun %vector-widetag-and-n-bits-shift (type)
  (declare (explicit-check))
  (macrolet ((with-parameters ((arg-type &key intervals)
                               (&rest args) &body body)
               (let ((type-sym (gensym)))
                 `(let (,@(loop for arg in args
                                collect `(,arg '*)))
                    (declare (ignorable ,@args))
                    (when (consp type)
                      (let ((,type-sym (cdr type)))
                        (block nil
                          ,@(loop for arg in args
                                  collect
                                  `(cond ((consp ,type-sym)
                                          (let ((value (pop ,type-sym)))
                                            (if (or (eq value '*)
                                                    (typep value ',arg-type)
                                                    ,(if intervals
                                                         `(and (consp value)
                                                               (null (cdr value))
                                                               (typep (car value)
                                                                      ',arg-type))))
                                                (setf ,arg value)
                                                (ill-type))))
                                         ((null ,type-sym)
                                          (return))
                                         (t
                                          (ill-type)))))
                        (when ,type-sym
                          (ill-type))))
                    ,@body)))
             (ill-type ()
               `(go fastidiously-parse))
             (result (widetag)
               (let ((value (symbol-value widetag)))
                 `(values ,value
                          ,(saetp-n-bits-shift
                            (find value
                                  *specialized-array-element-type-properties*
                                  :key #'saetp-typecode))))))
    (flet ((integer-interval-widetag (low high)
             (if (minusp low)
                 (%integer-vector-widetag-and-n-bits-shift
                  t
                  (1+ (max (integer-length low) (integer-length high))))
                 (%integer-vector-widetag-and-n-bits-shift
                  nil
                  (max (integer-length low) (integer-length high))))))
      (tagbody
         (binding*
             ((consp (consp type))
              (type-name (if consp (car type) type))
              ((widetag n-bits-shift)
               (case type-name
                 ((t)
                  (when consp
                    (ill-type))
                  (result simple-vector-widetag))
                 ((base-char standard-char #-sb-unicode character)
                  (when consp
                    (ill-type))
                  (result simple-base-string-widetag))
                 #+sb-unicode
                 ((character extended-char)
                  (when consp
                    (ill-type))
                  (result simple-character-string-widetag))
                 (bit
                  (when consp
                    (ill-type))
                  (result simple-bit-vector-widetag))
                 (fixnum
                  (when consp
                    (ill-type))
                  (result simple-array-fixnum-widetag))
                 (unsigned-byte
                  (with-parameters ((integer 1)) (high)
                    (if (eq high '*)
                        (result simple-vector-widetag)
                        (%integer-vector-widetag-and-n-bits-shift nil high))))
                 (signed-byte
                  (with-parameters ((integer 1)) (high)
                    (if (eq high '*)
                        (result simple-vector-widetag)
                        (%integer-vector-widetag-and-n-bits-shift t high))))
                 (double-float
                  (with-parameters (double-float :intervals t) (low high)
                    (if (and (not (eq low '*))
                             (not (eq high '*))
                             (if (or (consp low) (consp high))
                                 (>= (type-bound-number low) (type-bound-number high))
                                 (> low high)))
                        (result simple-array-nil-widetag)
                        (result simple-array-double-float-widetag))))
                 (single-float
                  (with-parameters (single-float :intervals t) (low high)
                    (if (and (not (eq low '*))
                             (not (eq high '*))
                             (if (or (consp low) (consp high))
                                 (>= (type-bound-number low) (type-bound-number high))
                                 (> low high)))
                        (result simple-array-nil-widetag)
                        (result simple-array-single-float-widetag))))
                 (mod
                  (if (and (consp type)
                           (consp (cdr type))
                           (null (cddr type))
                           (typep (cadr type) '(integer 1)))
                      (%integer-vector-widetag-and-n-bits-shift
                       nil (integer-length (1- (cadr type))))
                      (ill-type)))
                 #+long-float
                 (long-float
                  (with-parameters (long-float :intervals t) (low high)
                    (if (and (not (eq low '*))
                             (not (eq high '*))
                             (if (or (consp low) (consp high))
                                 (>= (type-bound-number low) (type-bound-number high))
                                 (> low high)))
                        (result simple-array-nil-widetag)
                        (result simple-array-long-float-widetag))))
                 (integer
                  (with-parameters (integer :intervals t) (low high)
                    (let ((low (if (consp low)
                                   (1+ (car low))
                                   low))
                          (high (if (consp high)
                                    (1- (car high))
                                    high)))
                      (cond ((or (eq high '*)
                                 (eq low '*))
                             (result simple-vector-widetag))
                            ((> low high)
                             (result simple-array-nil-widetag))
                            (t
                             (integer-interval-widetag low high))))))
                 (complex
                  (with-parameters (t) (subtype)
                    (if (eq subtype '*)
                        (result simple-vector-widetag)
                        (case subtype
                          ((short-float single-float)
                           (result simple-array-complex-single-float-widetag))
                          ((double-float long-float)
                           (result simple-array-complex-double-float-widetag))
                          ((real rational float)
                           (result simple-vector-widetag))
                          (t
                           (go fastidiously-parse))))))
                 ((nil)
                  (result simple-array-nil-widetag))
                 (t
                  (go fastidiously-parse)))))
           (return-from %vector-widetag-and-n-bits-shift
             (values widetag n-bits-shift)))
       fastidiously-parse)
      ;; Do things the hard way after falling through the tagbody.
      (let* ((ctype (type-or-nil-if-unknown type))
             (ctype (if ctype
                        (sb-kernel::replace-hairy-type ctype)
                        (error "~@<Unable to determine UPGRADED-ARRAY-ELEMENT-TYPE for ~s~:@_because it contains unknown types.~:>"
                               type))))
        (typecase ctype
          (numeric-union-type
           (case (sb-kernel::numtype-aspects-id (sb-kernel::numeric-union-type-aspects ctype))
             (#.(sb-kernel::!compute-numtype-aspect-id :real 'integer nil)
              (let* ((ranges (sb-kernel::numeric-union-type-ranges ctype))
                     (low (aref ranges 1))
                     (high (aref ranges (1- (length ranges)))))
                (if (and (integerp low) (integerp high))
                    (integer-interval-widetag low high)
                    (result simple-vector-widetag))))
             (#.(sb-kernel::!compute-numtype-aspect-id :real 'float 'double-float)
              (result simple-array-double-float-widetag))
             (#.(sb-kernel::!compute-numtype-aspect-id :real 'float 'single-float)
              (result simple-array-single-float-widetag))
             (#.(sb-kernel::!compute-numtype-aspect-id :complex 'float 'single-float)
              (result simple-array-complex-single-float-widetag))
             (#.(sb-kernel::!compute-numtype-aspect-id :complex 'float 'double-float)
              (result simple-array-complex-double-float-widetag))
             (t
              (result simple-vector-widetag))))
          (union-type
           (let ((types (union-type-types ctype)))
             (cond ((not (every #'numeric-type-p types))
                    (result simple-vector-widetag))
                   ((csubtypep ctype (specifier-type 'integer))
                    (block nil
                      (integer-interval-widetag
                       (dx-flet ((low (x)
                                      (or (numeric-type-low x)
                                          (return (result simple-vector-widetag)))))
                         (reduce #'min types :key #'low))
                       (dx-flet ((high (x)
                                       (or (numeric-type-high x)
                                           (return (result simple-vector-widetag)))))
                         (reduce #'max types :key #'high)))))
                   ((csubtypep ctype (specifier-type 'double-float))
                    (result simple-array-double-float-widetag))
                   ((csubtypep ctype (specifier-type 'single-float))
                    (result simple-array-single-float-widetag))
                   #+long-float
                   ((csubtypep ctype (specifier-type 'long-float))
                    (result simple-array-long-float-widetag))
                   ((csubtypep ctype (specifier-type 'complex-double-float))
                    (result simple-array-complex-double-float-widetag))
                   ((csubtypep ctype (specifier-type 'complex-single-float))
                    (result simple-array-complex-single-float-widetag))
                   (t
                    (result simple-vector-widetag)))))
          (intersection-type
           (let ((types (intersection-type-types ctype)))
             (loop for type in types
                   unless (hairy-type-p type)
                   return (%vector-widetag-and-n-bits-shift (type-specifier type)))
             (result simple-vector-widetag)))
          (character-set-type
           #-sb-unicode (result simple-base-string-widetag)
           #+sb-unicode
           (if (loop for (start . end)
                     in (character-set-type-pairs ctype)
                     always (and (< start base-char-code-limit)
                                 (< end base-char-code-limit)))
               (result simple-base-string-widetag)
               (result simple-character-string-widetag)))
          (t
           (let ((expansion (type-specifier ctype)))
             (if (equal expansion type)
                 (result simple-vector-widetag)
                 (%vector-widetag-and-n-bits-shift expansion)))))))))

(defun %vector-widetag-and-n-bits-shift-list (&rest type)
  (declare (dynamic-extent type))
  (%vector-widetag-and-n-bits-shift type))

(defun %string-widetag-and-n-bits-shift (element-type)
  (declare (explicit-check))
  (macrolet ((result (widetag)
               (let ((value (symbol-value widetag)))
                 `(values ,value
                          ,(saetp-n-bits-shift
                            (find value
                                  *specialized-array-element-type-properties*
                                  :key #'saetp-typecode))))))
    (cond ((eq element-type 'character)
           #+sb-unicode
           (result simple-character-string-widetag)
           #-sb-unicode
           (result simple-base-string-widetag))
          ((or (eq element-type 'base-char)
               (eq element-type 'standard-char)
               (eq element-type nil))
           (result simple-base-string-widetag))
          (t
           (multiple-value-bind (widetag n-bits-shift)
               (sb-vm::%vector-widetag-and-n-bits-shift element-type)
             (unless (or #+sb-unicode (= widetag sb-vm:simple-character-string-widetag)
                         (= widetag sb-vm:simple-base-string-widetag))
               (error "~S is not a valid :ELEMENT-TYPE for MAKE-STRING" element-type))
             (values widetag n-bits-shift))))))

(defun %complex-vector-widetag (widetag)
  (macrolet ((make-case ()
               `(case widetag
                  ,@(loop for saetp across *specialized-array-element-type-properties*
                          for complex = (saetp-complex-typecode saetp)
                          when complex
                          collect (list (saetp-typecode saetp) complex))
                  (t
                   #.complex-vector-widetag))))
    (make-case)))

(declaim (inline vector-length-in-words))
(defun vector-length-in-words (length n-bits-shift)
  (declare (type fixnum length)
           (type (integer 0 (#.n-word-bits)) n-bits-shift))
  #.(if (fixnump (ash array-dimension-limit 7))
        `(values
          ;; Shifting by n-word-bits-1 will overflow and produce 0 for a nil-vector
          (ceiling (logand (ash length n-bits-shift) most-positive-fixnum) n-word-bits))
        `(if (= n-bits-shift ,(1- n-word-bits)) ;; nil-vector
             0
             (let ((mask (ash (1- n-word-bits) (- n-bits-shift)))
                   (shift (- n-bits-shift
                             (1- (integer-length n-word-bits)))))
               (ash (+ length mask) shift)))))


;;; N-BITS-SHIFT is the shift amount needed to turn LENGTH into array-size-in-bits,
;;; i.e. log(2,bits-per-elt)
(declaim (inline allocate-vector-with-widetag))
(defun allocate-vector-with-widetag (#+ubsan poisoned widetag length n-bits-shift)
  (declare (type (unsigned-byte 8) widetag)
           (type index length))
  (let* (    ;; KLUDGE: add SAETP-N-PAD-ELEMENTS "by hand" since there is
             ;; but a single case involving it now.
         (full-length (+ length (if (= widetag simple-base-string-widetag) 1 0)))
         (nwords (the fixnum
                      (vector-length-in-words full-length n-bits-shift))))
    #+ubsan (if poisoned ; first arg to allocate-vector must be a constant
                      (allocate-vector t widetag length nwords)
                      (allocate-vector nil widetag length nwords))
    #-ubsan (allocate-vector widetag length nwords)))

(declaim (ftype (sfunction (array) (integer 128 255)) array-underlying-widetag)
         (inline array-underlying-widetag))
(defun array-underlying-widetag (array)
  (macrolet ((generate-table ()
               (macrolet ((to-index (x) `(ash ,x -2)))
                 (let ((table (sb-xc:make-array 64 :initial-element 0
                                                   :element-type '(unsigned-byte 8))))
                   (dovector (saetp *specialized-array-element-type-properties*)
                     (let* ((typecode (saetp-typecode saetp))
                            (complex-typecode (saetp-complex-typecode saetp)))
                       (setf (aref table (to-index typecode)) typecode)
                       (when complex-typecode
                         (setf (aref table (to-index complex-typecode)) typecode))))
                   (setf (aref table (to-index simple-array-widetag)) 0
                         (aref table (to-index complex-vector-widetag)) 0
                         (aref table (to-index complex-array-widetag)) 0)
                   table)))
             (to-index (x) `(ash ,x -2)))
    (named-let recurse ((x array))
      (let ((result (aref (generate-table)
                          (to-index (%other-pointer-widetag x)))))
        (if (= 0 result)
            (recurse (%array-data x))
            (truly-the (integer 128 255) result))))))

(defun array-underlying-widetag-and-shift (array)
  (declare (explicit-check))
  (let ((widetag (array-underlying-widetag array)))
    (values widetag
            (truly-the (unsigned-byte 8)
                       (aref %%simple-array-n-bits-shifts%% widetag)))))

;; Complain in various ways about wrong MAKE-ARRAY and ADJUST-ARRAY arguments,
;; returning the two initialization arguments needed for DATA-VECTOR-FROM-INITS.
;; This is an unhygienic macro which would be a MACROLET other than for
;; doing so would entail moving toplevel defuns around for no good reason.
(defmacro check-make-array-initargs (displaceable &optional element-type size)
  `(cond ,@(when displaceable
             `((displaced-to
                (when (or element-p contents-p)
                  (if (and element-p contents-p)
                      (error "Neither :INITIAL-ELEMENT nor :INITIAL-CONTENTS ~
                               may be specified with the :DISPLACED-TO option")
                      (error "~S may not be specified with the :DISPLACED-TO option"
                             (if element-p :initial-element :initial-contents))))
                (unless (= (array-underlying-widetag displaced-to) widetag)
                  ;; Require exact match on upgraded type (lp#1331299)
                  (error "Can't displace an array of type ~/sb-impl:print-type-specifier/ ~
                           into another of type ~/sb-impl:print-type-specifier/"
                         ,element-type (array-element-type displaced-to)))
                (when (< (array-total-size displaced-to)
                         (+ displaced-index-offset ,size))
                  (error "The :DISPLACED-TO array is too small.")))
               (offset-p
                (error "Can't specify :DISPLACED-INDEX-OFFSET without :DISPLACED-TO"))))
         ((and element-p contents-p)
          (error "Can't specify both :INITIAL-ELEMENT and :INITIAL-CONTENTS"))
         (element-p  (values :initial-element initial-element))
         (contents-p (values :initial-contents initial-contents))))
(defmacro make-array-bad-fill-pointer (actual max adjective)
  ;; There was a comment implying that this should be TYPE-ERROR
  ;; but I don't see that as a spec requirement.
  `(error "Can't supply a value for :FILL-POINTER (~S) that is larger ~
           than the~A size of the vector (~S)" ,actual ,adjective ,max))

(declaim (inline %save-displaced-array-backpointer
                 %save-displaced-new-array-backpointer))
(defun %save-displaced-array-backpointer (array data)
  (flet ((purge (pointers)
           (remove-if (lambda (value)
                        (or (not value) (eq array value)))
                      pointers
                      :key #'weak-pointer-value)))
    (let ((old-data (%array-data array)))
      (unless (eq old-data data)
        ;; Add backpointer to the new data vector if it has a header.
        (when (array-header-p data)
          (setf (%array-displaced-from data)
                (cons (make-weak-pointer array)
                      (purge (%array-displaced-from data)))))
        ;; Remove old backpointer, if any.
        (when (array-header-p old-data)
          (setf (%array-displaced-from old-data)
                (purge (%array-displaced-from old-data))))))))

(defun %save-displaced-new-array-backpointer (array data)
  (flet ((purge (pointers)
           (remove-if-not #'weak-pointer-value pointers)))
    (setf (%array-displaced-from data)
          (cons (make-weak-pointer array)
                (purge (%array-displaced-from data))))))

(defmacro populate-dimensions (header list-or-index rank)
  `(if (listp ,list-or-index)
       (let ((dims ,list-or-index))
         (dotimes (axis ,rank)
           (declare ((integer 0 ,array-rank-limit) axis))
           (%set-array-dimension ,header axis (pop dims))))
       (%set-array-dimension ,header 0 ,list-or-index)))

(declaim (inline rank-and-total-size-from-dims))
(defun rank-and-total-size-from-dims (dims)
  (cond ((not (listp dims)) (values 1 (the index dims)))
        ((not dims) (values 0 1))
        (t (let ((rank 1) (product (car dims)))
             (declare (%array-rank rank) (index product))
             (dolist (dim (cdr dims) (values rank product))
               (setq product (* product (the index dim)))
               (incf rank))))))

(declaim (inline widetag->element-type))
(defun widetag->element-type (widetag)
  (svref #.(let ((a (make-array 32 :initial-element 0)))
             (dovector (saetp *specialized-array-element-type-properties* a)
               (let ((tag (saetp-typecode saetp)))
                 (setf (aref a (ash (- tag #x80) -2)) (saetp-specifier saetp)))))
         (- (ash widetag -2) 32)))

(defun initial-contents-error (content-length length)
  (error "There are ~W elements in the :INITIAL-CONTENTS, but ~
                                the vector length is ~W."
         content-length length))

(defun initial-contents-list-error (list length)
  (if (proper-list-p list)
      (error "There are ~W elements in the :INITIAL-CONTENTS, but ~
                                the vector length is ~W."
             (length list) length)
      (error ":INITIAL-CONTENTS is not a proper list.")))

(declaim (inline fill-vector-initial-contents))
(defun fill-vector-initial-contents (length vector initial-contents)
  (declare (index length)
           (explicit-check initial-contents)
           (optimize (sb-c:insert-array-bounds-checks 0)))
  (if (listp initial-contents)
      (let ((list initial-contents))
        (tagbody
           (go init)
         ERROR
           (sb-vm::initial-contents-list-error initial-contents length)
         INIT
           (loop for i below length
                 do
                 (when (atom list)
                   (go error))
                 (setf (aref vector i) (pop list)))
           (when list
             (go error)))
        vector)
      (cond-dispatch (vectorp initial-contents)
        (let ((content-length (length initial-contents)))
          (unless (= content-length length)
            (sb-vm::initial-contents-error content-length length))
          (replace vector initial-contents)))))

(defun fill-vector-t-initial-contents (length vector initial-contents)
  (declare (index length)
           (inline fill-vector-initial-contents)
           (explicit-check initial-contents))
  (fill-vector-initial-contents length vector initial-contents))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (dolist (s '(fill-vector-initial-contents))
    (clear-info :function :inlining-data s)
    (clear-info :function :inlinep s)
    (clear-info :source-location :declaration s)))

(defun %make-simple-array (dimensions widetag n-bits)
  (declare (explicit-check dimensions))
  (multiple-value-bind (array-rank total-size) (rank-and-total-size-from-dims dimensions)
    (let ((data (allocate-vector-with-widetag #+ubsan t widetag total-size n-bits)))
      (cond ((= array-rank 1)
             data)
            (t
             (let* ((array (make-array-header simple-array-widetag array-rank)))
               (reset-array-flags array +array-fill-pointer-p+)
               (setf (%array-fill-pointer array) total-size)
               (setf (%array-available-elements array) total-size)
               (setf (%array-data array) data)
               (setf (%array-displaced-from array) nil)
               (setf (%array-displaced-p array) nil)
               (populate-dimensions array dimensions array-rank)
               array))))))

(defun %make-simple-array-array-dimensions (array widetag n-bits)
  (let* ((total-size (array-total-size array))
         (array-rank (array-rank array))
         (data (allocate-vector-with-widetag #+ubsan t widetag total-size n-bits)))
    (cond ((eq array-rank 1)
           data)
          (t
           (let* ((header (make-array-header simple-array-widetag array-rank)))
             (reset-array-flags header +array-fill-pointer-p+)
             (setf (%array-fill-pointer header) total-size)
             (setf (%array-available-elements header) total-size)
             (setf (%array-data header) data)
             (setf (%array-displaced-from header) nil)
             (setf (%array-displaced-p header) nil)
             (dotimes (axis array-rank)
               (%set-array-dimension header axis (%array-dimension array axis)))
             header)))))

;;; Widetag is the widetag of the underlying vector,
;;; it'll be the same as the resulting array widetag only for simple vectors
(defun %make-array (dimensions widetag n-bits
                    &key
                      element-type
                      (initial-element nil element-p)
                      (initial-contents nil contents-p)
                      adjustable fill-pointer
                      displaced-to
                      (displaced-index-offset 0 offset-p))
  (declare (ignore element-type))
  (binding* (((array-rank total-size) (rank-and-total-size-from-dims dimensions))
             ((initialize initial-data)
              ;; element-type might not be supplied, but widetag->element is always good
              (check-make-array-initargs t (widetag->element-type widetag) total-size))
             (simple (and (null fill-pointer)
                          (not adjustable)
                          (null displaced-to))))

    (cond ((and simple (= array-rank 1))
           (let ((vector ; a (SIMPLE-ARRAY * (*))
                  (allocate-vector-with-widetag #+ubsan (not (or element-p contents-p))
                                                widetag total-size n-bits)))
             ;; presence of at most one :INITIAL-thing keyword was ensured above
             (cond (element-p
                    (fill vector initial-element))
                   (contents-p
                    (let ((content-length (length initial-contents)))
                      (unless (= total-size content-length)
                        (initial-contents-error content-length total-size)))
                    (replace vector initial-contents))
                   #+ubsan
                   (t
                    ;; store the function which bears responsibility for creation of this
                    ;; array in case we need to blame it for not initializing.
                    (set-vector-extra-data (if (= widetag simple-vector-widetag) ; no shadow bits.
                                               vector ; use the LENGTH slot directly
                                               (vector-extra-data vector))
                                           (ash (sap-ref-word (current-fp) n-word-bytes) 3)) ; XXX: magic
                    (cond ((= widetag simple-vector-widetag)
                           (fill vector (%make-lisp-obj unwritten-vector-element-marker)))
                          ((array-may-contain-random-bits-p widetag)
                           ;; Leave the last word alone for base-string,
                           ;; in case the mandatory trailing null is part of a data word.
                           (dotimes (i (- (vector-length-in-words total-size n-bits)
                                          (if (= widetag simple-base-string-widetag) 1 0)))
                             (setf (%vector-raw-bits vector i) sb-ext:most-positive-word))))))
             vector))
          (t
           ;; it's non-simple or multidimensional, or both.
           (when fill-pointer
             (unless (= array-rank 1)
               (error "Only vectors can have fill pointers."))
             (when (and (integerp fill-pointer) (> fill-pointer total-size))
               (make-array-bad-fill-pointer fill-pointer total-size "")))
           (let* ((data (or displaced-to
                            (data-vector-from-inits dimensions total-size widetag n-bits
                                                    initialize initial-data)))
                  (array (make-array-header
                          (cond ((= array-rank 1)
                                 (%complex-vector-widetag widetag))
                                (simple simple-array-widetag)
                                (t complex-array-widetag))
                          array-rank)))
             (cond (fill-pointer
                    (logior-array-flags array +array-fill-pointer-p+)
                    (setf (%array-fill-pointer array)
                          (if (eq fill-pointer t) total-size fill-pointer)))
                   (t
                    (reset-array-flags array +array-fill-pointer-p+)
                    (setf (%array-fill-pointer array) total-size)))
             (setf (%array-available-elements array) total-size)
             (setf (%array-data array) data)
             (setf (%array-displaced-from array) nil)
             (cond (displaced-to
                    (setf (%array-displacement array) (or displaced-index-offset 0))
                    (setf (%array-displaced-p array) t)
                    (when (adjustable-array-p data)
                      (%save-displaced-new-array-backpointer array data)))
                   (t
                    (setf (%array-displaced-p array) nil)))
             (populate-dimensions array dimensions array-rank)
             array)))))

(defun make-array (dimensions &rest args
                   &key (element-type t)
                        initial-element initial-contents
                        adjustable
                        fill-pointer
                        displaced-to
                        displaced-index-offset)
  (declare (ignore initial-element
                   initial-contents adjustable
                   fill-pointer displaced-to displaced-index-offset))
  (declare (explicit-check))
  (multiple-value-bind (widetag shift) (%vector-widetag-and-n-bits-shift element-type)
    (apply #'%make-array dimensions widetag shift args)))

(defun make-static-vector (length &key
                           (element-type '(unsigned-byte 8))
                           (initial-contents nil contents-p)
                           (initial-element nil element-p))
  "Allocate vector of LENGTH elements in static space. Only allocation
of specialized arrays is supported."
  ;; STEP 1: check inputs fully
  (check-make-array-initargs nil) ; for effect
  (when contents-p
    (unless (= length (length initial-contents))
      (error "There are ~W elements in the :INITIAL-CONTENTS, but the ~
              vector length is ~W."
             (length initial-contents)
             length))
    (unless (every (lambda (x) (typep x element-type)) initial-contents)
      (error ":INITIAL-CONTENTS contains elements not of type ~
               ~/sb-impl:print-type-specifier/."
             element-type)))
  (when element-p
    (unless (typep initial-element element-type)
      (error ":INITIAL-ELEMENT ~S is not of type ~
               ~/sb-impl:print-type-specifier/."
             initial-element element-type)))
  ;; STEP 2
  ;;
  ;; Allocate and possibly initialize the vector.
  (multiple-value-bind (type n-bits-shift)
      (%vector-widetag-and-n-bits-shift element-type)
    (when (eq type simple-vector-widetag)
      (error "Static arrays of type ~/sb-impl:print-type-specifier/ not supported."
             element-type))
    (let* ((full-length
             ;; KLUDGE: add SAETP-N-PAD-ELEMENTS "by hand" since there is
             ;; but a single case involving it now.
             (+ length (if (= type simple-base-string-widetag) 1 0)))
           (vector
             (allocate-static-vector type length
                                     (vector-length-in-words full-length
                                                             n-bits-shift))))
      (cond (element-p
             (fill vector initial-element))
            (contents-p
             (replace vector initial-contents))
            (t
             vector)))))

#+darwin-jit
(defun make-static-code-vector (length initial-contents)
  "Allocate vector of LENGTH elements in static space. Only allocation
of specialized arrays is supported."
  (let ((vector (allocate-static-code-vector simple-array-unsigned-byte-8-widetag
                                             length
                                             (* length n-word-bytes))))
    (with-pinned-objects (initial-contents)
      (jit-memcpy (vector-sap vector) (vector-sap initial-contents) length))
    vector))

;;; DATA-VECTOR-FROM-INITS returns a simple rank-1 array that has the
;;; specified array characteristics. Dimensions is only used to pass
;;; to FILL-DATA-VECTOR for error checking on the structure of
;;; initial-contents.
(defun data-vector-from-inits (dimensions total-size widetag n-bits initialize initial-data)
  (declare (fixnum widetag n-bits)) ; really just that they're non-nil
  (let ((data (allocate-vector-with-widetag #+ubsan (not initialize) widetag total-size n-bits)))
    (ecase initialize
     (:initial-element
      (fill (the vector data) initial-data))
     (:initial-contents
      ;; DIMENSIONS can be supplied as a list or integer now
      (dx-let ((list-of-dims (list dimensions))) ; ok if already a list
        (fill-data-vector data
                          (if (listp dimensions) dimensions list-of-dims)
                          initial-data)))
     ((nil)))
    data))

(defun vector (&rest objects)
  "Construct a SIMPLE-VECTOR from the given objects."
  (let ((v (make-array (length objects))))
    (do-rest-arg ((x i) objects 0 v)
      (setf (aref v i) x))))


;;;; accessor/setter functions

;;; Dispatch to an optimized routine the data vector accessors for
;;; each different specialized vector type. Do dispatching by looking
;;; up the widetag in the array rather than with the typecases, which
;;; as of 1.0.5 compiles to a naive sequence of linear TYPEPs. Also
;;; provide separate versions where bounds checking has been moved
;;; from the callee to the caller, since it's much cheaper to do once
;;; the type information is available. Finally, for each of these
;;; routines also provide a slow path, taken for arrays that are not
;;; vectors or not simple.
;;; FIXME: how is this not redundant with DEFINE-ARRAY-DISPATCH?
;;; Which is to say, why did DEFINE-ARRAY-DISPATCH decide to do
;;; something different instead of figuring out how to unify the ways
;;; that we call an element of an array accessed by widetag?
(macrolet ((def (name table-name)
             `(progn
                (define-load-time-global ,table-name
                    (make-array ,(1+ widetag-mask)))
                (declaim (type (simple-array function (,(1+ widetag-mask)))
                               ,table-name))
                (defmacro ,name (array-var &optional type)
                  (if type
                      `(truly-the function
                                  (svref ,',table-name (%other-pointer-widetag
                                                        (locally (declare (optimize (safety 1)))
                                                          (the ,type ,array-var)))))
                      `(truly-the function
                                  ;; Assigning TAG to 0 initially produces slightly better
                                  ;; code than would be generated by the more natural expression
                                  ;;   (let ((tag (if (%other-ptr ...) (widetag ...) 0)))
                                  ;; but either way is suboptimal. As expressed, if the array-var
                                  ;; is known to satisfy %other-pointer-p, then it performs a
                                  ;; move-immediate-to-register which is clobbered right away
                                  ;; by a zero-extending load. A peephole pass could eliminate
                                  ;; the first move as effectless.  If expressed the other way,
                                  ;; it would produce a jump around a jump because the compiler
                                  ;; is unwilling to *unconditionally* assign 0 into a register
                                  ;; to begin with. It actually wants to guard an immediate load
                                  ;; when it doesn't need to, as if both consequents of the IF
                                  ;; have side-effects that should not happen.
                                  (let ((tag 0))
                                    (when (%other-pointer-p ,array-var)
                                      (setf tag (%other-pointer-widetag ,array-var)))
                                    (svref ,',table-name tag))))))))
  (def !find-data-vector-setter %%data-vector-setters%%)
  (def !find-data-vector-setter/check-bounds %%data-vector-setters/check-bounds%%)
  ;; Used by DO-VECTOR-DATA -- which in turn appears in DOSEQUENCE expansion,
  ;; meaning we can have post-build dependences on this.
  (def %find-data-vector-reffer %%data-vector-reffers%%)
  (def !find-data-vector-reffer/check-bounds %%data-vector-reffers/check-bounds%%))

;;; Like DOVECTOR, but more magical -- can't use this on host.
(defmacro sb-impl::do-vector-data ((elt vector &optional result) &body body)
  (multiple-value-bind (forms decls) (parse-body body nil)
    (with-unique-names (index vec start end ref)
      `(with-array-data ((,vec ,vector)
                         (,start)
                         (,end)
                         :check-fill-pointer t)
         (let ((,ref (%find-data-vector-reffer ,vec)))
           (declare (function ,ref))
           (do ((,index ,start (1+ ,index)))
               ((>= ,index ,end)
                (let ((,elt nil))
                  ,@(sb-impl::filter-dolist-declarations decls)
                  ,elt
                  ,result))
             (let ((,elt (funcall ,ref ,vec ,index)))
               ,@decls
               (tagbody ,@forms))))))))

(macrolet ((%ref (accessor-getter extra-params &optional vector-check)
             `(sb-c::%funcall-no-nargs (,accessor-getter array ,vector-check) array index ,@extra-params))
           (define (accessor-name slow-accessor-name
                                  accessor-getter extra-params check-bounds
                                  &optional (slow-accessor-getter accessor-getter))
             `(progn
                (defun ,accessor-name (array index ,@extra-params)
                  (declare (explicit-check))
                  (declare (optimize speed
                                     ;; (SAFETY 0) is ok. All calls to
                                     ;; these functions are generated by
                                     ;; the compiler, so argument count
                                     ;; checking isn't needed. Type checking
                                     ;; is done implicitly via the widetag
                                     ;; dispatch.
                                     (safety 0)))
                  (%ref ,accessor-getter ,extra-params))
                (defun ,(symbolicate 'vector- accessor-name) (array index ,@extra-params)
                  (declare (explicit-check)
                           (optimize speed (safety 0)))
                  (%ref ,accessor-getter ,extra-params vector))
                (defun ,(symbolicate 'string- accessor-name) (array index ,@extra-params)
                  (declare (explicit-check)
                           (optimize speed (safety 0)))
                  (%ref ,accessor-getter ,extra-params string))
                (defun ,slow-accessor-name (array index ,@extra-params)
                  (declare (optimize speed (safety 0))
                           (array array))
                  (let ((index (locally
                                   (declare (optimize (speed 1) (safety 1)))
                                 (,@check-bounds index))))
                   (if (not (%array-displaced-p array))
                       ;; The reasonably quick path of non-displaced complex
                       ;; arrays.
                       (let ((array (%array-data array)))
                         (%ref ,slow-accessor-getter ,extra-params))
                       ;; The real slow path.
                       (with-array-data
                           ((array array)
                            (index index)
                            (end)
                            :force-inline t)
                         (declare (ignore end))
                         (%ref ,slow-accessor-getter ,extra-params))))))))
  (define hairy-data-vector-ref slow-hairy-data-vector-ref
    %find-data-vector-reffer
    nil (progn))
  (define hairy-data-vector-set slow-hairy-data-vector-set
    !find-data-vector-setter
    (new-value) (progn))
  (define hairy-data-vector-ref/check-bounds
      slow-hairy-data-vector-ref/check-bounds
    !find-data-vector-reffer/check-bounds
    nil (check-bound array (%array-available-elements array)) %find-data-vector-reffer)
  (define hairy-data-vector-set/check-bounds
      slow-hairy-data-vector-set/check-bounds
    !find-data-vector-setter/check-bounds
    (new-value) (check-bound array (%array-available-elements array)) !find-data-vector-setter))

(defun hairy-ref-error (array index &optional new-value)
  (declare (ignore index new-value)
           (optimize (sb-c:verify-arg-count 0)))
  (error 'type-error
         :datum array
         :expected-type 'vector))

(macrolet ((define-reffer (saetp check-form)
             (let* ((type (saetp-specifier saetp))
                    (atype `(simple-array ,type (*))))
               `(named-lambda (optimized-data-vector-ref ,type) (vector index)
                  (declare (optimize speed (safety 0))
                           ;; Obviously these all coerce raw words to lispobjs
                           ;; so don't keep spewing notes about it.
                           (muffle-conditions compiler-note)
                           (ignorable index))
                  ,(if type
                       `(data-vector-ref (the ,atype vector)
                                         (the index
                                              (locally
                                                  (declare (optimize (safety 1)))
                                                (,@check-form index))))
                       `(data-nil-vector-ref (the ,atype vector) index)))))
           (define-setter (saetp check-form)
             (let* ((type (saetp-specifier saetp))
                    (atype `(simple-array ,type (*))))
               `(named-lambda (optimized-data-vector-set ,type) (vector index new-value)
                  (declare (optimize speed (safety 0)))
                  ;; Impossibly setting an elt of an (ARRAY NIL)
                  ;; returns no value. And nobody cares.
                  (declare (muffle-conditions compiler-note))
                  (data-vector-set (the ,atype vector)
                                   (locally
                                       (declare (optimize (safety 1)))
                                     (the index
                                       (,@check-form index)))
                                   (locally
                                       ;; SPEED 1 needed to avoid the compiler
                                       ;; from downgrading the type check to
                                       ;; a cheaper one.
                                       (declare (optimize (speed 1)
                                                          (safety 1)))
                                     (the* (,type :context sb-c::aref-context) new-value)))
                  ;; Low-level setters return no value
                  new-value)))
           (define-reffers (symbol deffer check-form slow-path)
             `(progn
                ;; FIXME/KLUDGE: can't just FILL here, because genesis doesn't
                ;; preserve the binding, so re-initiaize as NS doesn't have
                ;; the energy to figure out to change that right now.
                (setf ,symbol (make-array (1+ widetag-mask)
                                          :initial-element #'hairy-ref-error))
                ,@(loop for widetag in '(complex-vector-widetag
                                         complex-bit-vector-widetag
                                         #+sb-unicode complex-character-string-widetag
                                         complex-base-string-widetag
                                         simple-array-widetag
                                         complex-array-widetag)
                        collect `(setf (svref ,symbol ,widetag) ,slow-path))
                ,@(loop for saetp across *specialized-array-element-type-properties*
                        for widetag = (saetp-typecode saetp)
                        collect `(setf (svref ,symbol ,widetag)
                                       (,deffer ,saetp ,check-form))))))
  (defun !hairy-data-vector-reffer-init ()
    (define-reffers %%data-vector-reffers%% define-reffer
      (progn)
      #'slow-hairy-data-vector-ref)
    (define-reffers %%data-vector-setters%% define-setter
      (progn)
      #'slow-hairy-data-vector-set)
    (define-reffers %%data-vector-reffers/check-bounds%% define-reffer
      (check-bound vector (length vector))
      #'slow-hairy-data-vector-ref/check-bounds)
    (define-
