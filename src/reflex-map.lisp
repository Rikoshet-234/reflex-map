#|
  This file is a part of reflex-map project.

  (C) COPYRIGHT Alexey Veretennikov<alexey.veretennikov@gmail.com>, 2018
|#
(in-package :reflex-map)

;; Implementation
(defparameter *version* "0.2")

(defparameter *float-scanner*
  (ppcre:create-scanner "-?[0-9]+([.][0-9]+([Ee][0-9]+)?)"))

(defparameter *int-scanner*
  (ppcre:create-scanner "-?[0-9]+"))

(defparameter *hex-scanner*
  (ppcre:create-scanner "0[xX][0-9a-fA-F]+"))


(defclass reflex-map ()
  ((version :initarg :version :initform nil :reader map-version)
   (prefabs :initarg :prefabs :initform nil :reader map-prefabs)
   (global-prefab :initarg :global :initform nil :reader map-global-prefab)))

(defclass prefab-base ()
  ((entities :initarg :entities :initform nil :reader prefab-entities)
   (brushes :initarg :brushes :initform nil :reader prefab-brushes)))

(defclass normal-prefab (prefab-base)
  ((name :initarg :name :initform "" :reader prefab-name)))

(defclass global-prefab (prefab-base)
  ())
    

(defclass entity ()
  ((type :initarg :type :initform nil :reader entity-type)
   (properties :initarg :properties :initform nil
               :reader entity-properties))
  (:documentation "Entity section representation"))


(defclass brush ()
  ((vertices :initarg :vertices :initform nil :reader brush-vertices
             :documentation "A list of vertices")
   (faces :initarg :faces :initform nil :reader brush-faces
          :documentation "A list of faces")))


(defclass vertex ()
  ((x :initarg :x :initform 0 :type 'float :reader vertex-x)
   (y :initarg :y :initform 0 :type 'float :reader vertex-y)
   (z :initarg :z :initform 0 :type 'float :reader vertex-z))
  (:documentation "Representation of the 3d vertex"))


(defclass face ()
  ((u :initarg :u :initform 0 :type 'float :reader face-u)
   (v :initarg :v :initform 0 :type 'float :reader face-v)
   (scale-u :initarg :scale-u :initform 1 :type 'float :reader face-scale-u)
   (scale-v :initarg :scale-v :initform 1 :type 'float :reader face-scale-v)
   (rotation :initarg :rotation :initform 0 :type 'float :reader face-rotation)
   (vertices :initarg :vertices :initform nil :reader face-vertices :documentation "an array of indexes of corresponding ver~tices")
   (model-color :initarg :model-color :initform "" :type 'string :reader face-model-color)
   (model-name :initarg :model-name :initform "" :type 'string :reader face-model-name)))


(defmethod print-object :after ((self entity) stream)
  "Print the contents of the ENTITY"
  nil)
;;;   (with-slots (type properties) self
;;;     (format stream "Entity type: ~a~%Properties:~%" type)
;;;     (dolist (x properties)
;;;       (format stream "~a~%" x))))

(defmethod print-vertex ((self vertex) stream)
  "Print the contents of the VERTEX"
  (with-slots (x y z) self
    (format stream "( ~a ~a ~a )" x y z)))

(defmethod print-inverse-vertex ((self vertex) stream)
  "Print the contents of the VERTEX"
  (with-slots (x y z) self
;;    (format stream "( ~a ~a ~a )" z (round (* 0.6 y)) x)))
;;    (format stream "( ~a ~a ~a )" z x (round (* 0.6 y)))))
    (format stream "( ~a ~a ~a )" z x y)))


(defmethod print-object :after ((self vertex) stream)
  "Print the contents of the VERTEX"
  (print-vertex self stream))

(defmethod print-object :after ((self brush) stream)
  "Print the contents of the BRUSH"
  nil)
;;;   (with-slots (vertices faces) self
;;;     (format stream "Bursh~%Vertices:~%")
;;;     (dolist (v vertices) (print-object v stream))
;;;     (format stream "Faces:~%")
;;;     (dolist (f faces) (print-object f stream))))

(defmethod find-entity-property ((self entity) name)
  (when-let (found 
             (find-if (lambda (prop)
                        (string= (string-downcase (second prop))
                                 (string-downcase name)))
                      (entity-properties self)))
    (cddr found)))



(defun make-vertex (x y z)
  (make-instance 'vertex :x x :y y :z z))

(defmethod vertex-coords ((self vertex))
  (with-slots (x y z) self
    (list x y z)))
  

(defun read-windows-line (in)
  (when-let (line (read-line in nil))
    (string-right-trim '(#\Newline #\Return) line)))


(defun count-indent (line &optional (indent-char #\tab))
  (loop for c across line
        for i below (length line)
        while (char= c indent-char)
        finally (return i)))

(defun if-indent (line count)
  (and line
       (= (count-indent line) count)))

(defun parse-and-trim (line)
  (split-sequence:split-sequence #\Space (string-trim '(#\Tab #\Space) line)))


(defmacro def-is-fun (type scanner-var)
  (let ((fun-name (intern (string-upcase (concatenate 'string "is-" (symbol-name type))))))
  `(progn
     (defun ,fun-name (token)
       (multiple-value-bind (start end)
           (ppcre:scan ,scanner-var token)
         (and start end
              (= (- end start) (length token))))))))

(def-is-fun float *float-scanner*)
(def-is-fun int   *int-scanner*)
(def-is-fun hex   *hex-scanner*)
  
    
(defun tokenize-string (line)
  (mapcar (lambda (token)
            (cond ((or (is-float token)
                       (is-int token))
                   (read-from-string token))
                  ((member token '("reflex" "map" "version" "global" "prefab" "entity" "type" "brush" "vertices" "faces") :test #'string=)
                   (intern (string-upcase token) :reflex-map))
                  (t token)))
          (parse-and-trim line)))


(defun reflex-list-lexer (tokens)
  #'(lambda ()
      (let ((value (pop tokens)))
        (if (null value)
            (values nil nil)
            (let ((terminal
                    (cond ((and (stringp value) (is-hex value)) 'hex)
                          ((stringp value) 'string)
                          ((integerp value) 'integer)
                          ((floatp value) 'float)
                          ;; value of symbol is the symbol itself
                          ((symbolp value) value)
                          (t (error "Unexpected value ~S" value)))))
              (values terminal value))))))


(defun reflex-map-stream-lexer (in-stream &optional (indent-char #\Tab))
  (loop with stack = (list 0)
        with result = nil
        for line = (read-windows-line in-stream)
        while line
        for indent = (count-indent line indent-char)
        for tokens = (tokenize-string line)
        for prev-indent = (car stack)
        if (> indent prev-indent)
          do
             (dotimes (i (- indent prev-indent))
               (push indent stack)
               (push 'indent result))               
        else
          do
             (dotimes (i (- prev-indent indent))
               (push 'dedent result)
               (pop stack))
        do
           (dolist (tok tokens)
             (push tok result))
           (push 'newline result)
        finally
           (dotimes (i (car stack))
             (push 'dedent result))
           (return (nreverse result))))


(defun reflex-map-lexer (filename)
  ;; list of tokens:
  ;; tab, string, newline
  (with-open-file (in filename :if-does-not-exist nil)
    (reflex-map-stream-lexer in)))


(defun prefab-from-entries (name entries)
  (let ((entities-list (remove-if (lambda (x) (eql (type-of x) 'brush)) entries))
        (brushes-list (remove-if (lambda (x) (eql (type-of x) 'entity)) entries)))
    (make-instance 'normal-prefab :name name :entities entities-list :brushes brushes-list)))

(defun global-from-entries (entries)
  (let ((entities-list (remove-if (lambda (x) (eql (type-of x) 'brush)) entries))
        (brushes-list (remove-if (lambda (x) (eql (type-of x) 'entity)) entries)))
    (make-instance 'global-prefab :entities entities-list :brushes brushes-list)))

(defun create-reflex-map (version prefabs)
  (let ((global (find-if (lambda (x) (eql (type-of x) 'global-prefab)) prefabs))
        (only-prefabs (remove-if (lambda (x) (eql (type-of x) 'global-prefab)) prefabs)))
    (make-instance 'reflex-map :version version
                               :global global
                               :prefabs only-prefabs)))

;; grammar of the Reflex Arena map file
(yacc:define-parser *reflex-map-parser*
  (:start-symbol reflex-map)
  (:terminals (string integer float hex newline indent dedent reflex map version global prefab entity type brush vertices faces))
  (reflex-map (header newline body (lambda (h n b)
                                     (declare (ignore n))
                                     (create-reflex-map h b))))

  (header (reflex map version integer
                  ;; return version only
                  (lambda (r m v i)
                    (declare (ignore r m v))
                    i)))
  (body prefabs (entries (lambda (e)
                           ;; still create a list of 1 element
                           (list (global-from-entries e)))))

  (prefabs (prefab-term #'list))
  (prefabs (prefab-term prefabs (lambda (p-t p) (cons p-t p))))
  (prefab-term
   (global newline indent entries dedent
           (lambda (g n i e d)
             (declare (ignore g n i d))
             (global-from-entries e)))
   (prefab prefab-name newline indent entries dedent
                       (lambda (p s n i e d)
                         (declare (ignore p n i d))
                         (prefab-from-entries (format nil "~a" s) e))))
  
  (prefab-name string integer hex float)
  
  (entries (entry #'list))
  (entries (entry entries (lambda (e es) (cons e es))))

  (entry entity-entry brush-entry)

  (entity-entry (entity newline indent type string newline dedent
                        (lambda (e n i type typename n-2 d)
                          (declare (ignore e n i type n-2 d))
                          (make-instance 'entity :type typename :properties nil)))

                (entity newline indent type string newline entry-attributes dedent
                        (lambda (e n i type typename n-2 e-a d)
                          (declare (ignore e n i type n-2 d))
                          (make-instance 'entity :type typename :properties e-a))))

  (entry-attributes (entry-attribute-line newline
                                          (lambda (e-a-l nl)
                                            (declare (ignore nl))
                                            (list e-a-l))))
  
  (entry-attributes (entry-attributes entry-attribute-line newline
                                      (lambda (e-a e-a-l nl)
                                        (declare (ignore nl))
                                        (nconc e-a (list e-a-l)))))
  
  (entry-attribute-line (entry-attribute-value #'list))

  (entry-attribute-line (entry-attribute-value entry-attribute-line
                                               (lambda (e-a-v e-a-l)
                                                 (cons e-a-v e-a-l))))
  (entry-attribute-value hex string integer float)

  (brush-entry (brush newline indent vertices-list faces-list dedent
                        (lambda (b n i v f d)
                          (declare (ignore b n i d))
                          (make-instance 'brush :vertices v :faces f))))


  (vertices-list (vertices newline indent vertices-lines dedent
                           (lambda (v n i v-l d)
                             (declare (ignore v n i d))
                             v-l)))

  (vertices-lines (vertex-line newline
                               (lambda (v n)
                                 (declare (ignore n))
                                 (list v))))
  (vertices-lines (vertices-lines vertex-line newline
                                  (lambda (v-l v n)
                                    (declare (ignore n))
                                    (nconc v-l (list v)))))
  (vertex-line (float float float
                      (lambda (a1 a2 a3)
                        (position-vector (list a1 a2 a3) :type :vertex)))) 

  (faces-list (faces newline indent faces-lines dedent
                     (lambda (f n i f-l d)
                       (declare (ignore f n i d))
                       f-l)))

  (faces-lines (face-line newline
                          (lambda (f-l n)
                            (declare (ignore n))
                            (list f-l))))
                            
  (faces-lines (faces-lines face-line newline
                            (lambda (f-l f n)
                              (declare (ignore n))
                              (nconc f-l (list f)))))

  (face-line (offsets vertices-list models
                      (lambda (offs ver tex)
                        (destructuring-bind (u v s-u s-v rot) offs
                          (make-instance 'face
                                         :u u :v v :scale-u s-u :scale-v s-v
                                         :rotation rot
                                         ;; TODO: fix this. could be hex, string or both
                                         :model-name tex
                                         :vertices ver)))))

  (offsets (float float float float float
                  (lambda (u v s-u s-v rot)
                    (list u v s-u s-v rot))))

  (vertices-list (integer #'list)
                 (integer vertices-list (lambda (i v-l)
                                          (cons i v-l))))

  (models nil hex string (hex string)))

(defun parse-reflex-map-file (filename)
  (yacc:parse-with-lexer (reflex-list-lexer (reflex-map-lexer filename)) *reflex-map-parser*))


;; math

(defgeneric plane-equation (v1 v2 v3)
  (:documentation
   "Calculate the plane equation in format
Ax+By+Cz+D=0 and returns values A B C D
v1,v2,v3 are vertices.

The equation is calculated via
https://www.wolframalpha.com/input/?i=Collect%5Bdet%5B%7Bx-x1,+x2-x1,+x3-x1%7D,%7By-y1,+y2-y1,+y3-y1%7D,%7Bz-z1,+z2-z1,+z3-z1%7D%5D,+%7Bx,y,z%7D%5D
  
x (y1 z2 - y1 z3 - y2 z1 + y2 z3 + y3 z1 - y3 z2) + y (-x1 z2 + x1 z3 + x2 z1 - x2 z3 - x3 z1 + x3 z2) + z (x1 y2 - x1 y3 - x2 y1 + x2 y3 + x3 y1 - x3 y2) - x1 y2 z3 + x1 y3 z2 + x2 y1 z3 - x2 y3 z1 - x3 y1 z2 + x3 y2 z1

Hence
A = (y1 z2 - y1 z3 - y2 z1 + y2 z3 + y3 z1 - y3 z2)
B = (-x1 z2 + x1 z3 + x2 z1 - x2 z3 - x3 z1 + x3 z2)
C = (x1 y2 - x1 y3 - x2 y1 + x2 y3 + x3 y1 - x3 y2)
D = - x1 y2 z3 + x1 y3 z2 + x2 y1 z3 - x2 y3 z1 - x3 y1 z2 + x3 y2 z1"))


(defun plane-equation-impl (x1 y1 z1 x2 y2 z2 x3 y3 z3)
  (let ((A (- (+ (* y1 z2) (* y2 z3) (* y3 z1))
              (+ (* y1 z3) (* y2 z1) (* y3 z2))))
        (B (- (+ (* x1 z3) (* x2 z1) (* x3 z2))
              (+ (* x1 z2) (* x2 z3) (* x3 z1))))
        (C (- (+ (* x1 y2) (* x2 y3) (* x3 y1))
              (+ (* x1 y3) (* x2 y1) (* x3 y2))))
        (D (- (+ (* x1 y3 z2) (* x2 y1 z3) (* x3 y2 z1))
              (+ (* x1 y2 z3) (* x2 y3 z1) (* x3 y1 z2)))))
    (values A B C D)))
  
(defmethod plane-equation ((v1 vertex) (v2 vertex) (v3 vertex))
  (let* ((x1 (vertex-x v1))
         (x2 (vertex-x v2))
         (x3 (vertex-x v3))
         (y1 (vertex-y v1))
         (y2 (vertex-y v2))
         (y3 (vertex-y v3))
         (z1 (vertex-z v1))
         (z2 (vertex-z v2))
         (z3 (vertex-z v3)))
    (plane-equation-impl x1 y1 z1 x2 y2 z2 x3 y3 z3)))

(defmethod plane-equation ((v1 vec4) (v2 vec4) (v3 vec4))
  (let* ((x1 (vx v1))
         (x2 (vx v2))
         (x3 (vx v3))
         (y1 (vy v1))
         (y2 (vy v2))
         (y3 (vy v3))
         (z1 (vz v1))
         (z2 (vz v2))
         (z3 (vz v3)))
    (plane-equation-impl x1 y1 z1 x2 y2 z2 x3 y3 z3)))

(defmethod plane-equation ((v1 list) (v2 list) (v3 list))
  (let* ((x1 (first v1))
         (x2 (first v2))
         (x3 (first v3))
         (y1 (second v1))
         (y2 (second v2))
         (y3 (second v3))
         (z1 (third v1))
         (z2 (third v2))
         (z3 (third v3)))
    (plane-equation-impl x1 y1 z1 x2 y2 z2 x3 y3 z3)))


(defun create-flip-transform (brushes)
  ;; find center
  (let* ((center
           (loop for b in brushes
                 for verc = (mapcar #'vertex-coords
                                    (brush-vertices b))
                 for brush-bnds = (loop for v in verc
                                        minimizing (first v) into xmin
                                        minimizing (second v) into ymin
                                        minimizing (third v) into zmin
                                        maximizing (first v) into xmax
                                        maximizing (second v) into ymax
                                        maximizing (third v) into zmax
                                        finally (return (list xmin ymin zmin xmax ymax zmax)))
                 minimizing (elt brush-bnds 0) into xmin
                 minimizing (elt brush-bnds 1) into ymin
                 minimizing (elt brush-bnds 2) into zmin
                 maximizing (elt brush-bnds 3) into xmax
                 maximizing (elt brush-bnds 4) into ymax
                 maximizing (elt brush-bnds 5) into zmax
                 finally (return (list ;; perform swap z x y
                                  (/ (+ zmin zmax) 2)
                                  (/ (+ xmin xmax) 2)
                                  (/ (+ ymin ymax) 2)))))
         (mirror-matrix-x
           (mat4 '(-1 0 0 0
                   0 1 0 0
                   0 0 1 0
                   0 0 0 1)))
         (mirror-matrix-y
           (mat4 '(1 0 0 0
                   0 -1 0 0
                   0 0 1 0
                   0 0 0 1)))
         (mirror-matrix-z
           (mat4 '(1 0 0 0
                   0 1 0 0
                   0 0 -1 0
                   0 0 0 1)))
         (trans+center (mat4 (list 1 0 0 (first center)
                                   0 1 0 (second center)
                                   0 0 1 (third center)
                                   0 0 0 1)))
         (trans-center (mat4 (list 1 0 0 (- (first center))
                                   0 1 0 (- (second center))
                                   0 0 1 (- (third center))
                                   0 0 0 1))))
    ;; flip horizontally from TrenchBroom
    ;;  const auto transform = vm::translationMatrix(center) * vm::mirrorMatrix<FloatType>(axis) * vm::translationMatrix(-center);
    (declare (ignore mirror-matrix-x mirror-matrix-z))
    ;; (format t "geometry center: ~a ~a ~a~%" (first center)
    ;;         (second center) (third center))
    (m* (m* trans+center mirror-matrix-y) trans-center)))
  
           


(defun rotation-matrix (along-z along-x along-y)
  "Rotation matrix for the list of 3 angles given in degrees.
Angles are along z axis, x axis and y axis"
  (flet ((sind (x)     ; The argument is in degrees 
           (sin (* x (/ (float pi x) 180))))
         (cosd (x)     ; The argument is in degrees 
           (cos (* x (/ (float pi x) 180)))))
    (let* ((cx (cosd along-x))
           (sx (sind along-x))
           (x
             (mat4 (list 1 0 0 0
                         0 cx (- sx) 0
                         0 sx cx 0
                         0 0 0 1)))
           (cy (cosd along-y))
           (sy (sind along-y))
           (y
             (mat4 (list cy 0 sy 0
                         0  1 0  0
                         (- sy) 0 cy 0
                         0 0 0 1)))
           (cz (cosd along-z))
           (sz (sind along-z))
           (z
             (mat4 (list cz (- sz)  0  0
                         sz  cz     0  0
                         0 0 1 0
                         0 0 0 1))))
      (m* (m* x y) z))))


(defun export-face (points transform out)
  ;; take first 3 points from the face
  (let* ((vertices  (subseq points 0 3))
         (normal (multiple-value-list 
                  (apply #'plane-equation vertices)))
         (angle (v. 
                 (vc (v- (apply #'vec3 (third vertices))
                         (apply #'vec3 (first vertices)))
                     (v- (apply #'vec3 (second vertices))
                         (apply #'vec3 (first vertices))))
                 (apply #'vec3 (subseq normal 0 3)))))
    ;; make sure the normal is in positive direction
    (when (> 0 angle)
      (rotatef (nth 1 vertices) (nth 2 vertices)))
    ;; apply transformation
    (let* ((new-vertices
             (mapcar (lambda (p)
                       (let* ((x (elt p 0))
                              (y (elt p 1))
                              (z (elt p 2)))
                         (m* transform (vec4 x y z 1))))
                     vertices))
           (new-normal (multiple-value-list 
                        (apply #'plane-equation new-vertices)))
           (new-angle
             (v. 
              (vc (v- (vxyz (third new-vertices))
                      (vxyz (first new-vertices)))
                  (v- (vxyz (second new-vertices))
                      (vxyz (first new-vertices))))
              (apply #'vec3 (subseq new-normal 0 3)))))
      ;; make sure the normal is in positive direction
      (when (> 0 new-angle)
        (rotatef (nth 1 new-vertices) (nth 2 new-vertices)))
      (mapc (lambda (v) (format out "( ~a ~a ~a ) " (vx v) (vy v) (vz v))) new-vertices))))




  

(defmethod export-brush ((self brush) transform out)
  (with-slots (vertices faces) self
    (format out "{~%")
    (dolist (f faces)
      (let ((points
              (loop for vert-idx in (face-vertices f)
                    for coords = (vertex-coords (elt vertices vert-idx))
                    collect coords into vert-coords
                    finally (return vert-coords))))
        (export-face points transform out))
      (format out " rock4_1 0 0 0 1 1~%"))
    (format out "}~%")))


(defmethod export-brushes ((self prefab-base) out transform)
  (with-slots (brushes) self
    (loop for br in brushes
          for i below (length brushes)
          do
             (format out "// brush ~d~%" i)
             (export-brush br transform out))))


(defun position-vector (attrs &key (type :vertex))
  "Convert list of floats (coordinates in Reflex coordinate
system to appropriate vector depending of keyword :TYPE.
The coordinates swap is also performed.
TYPE could be one of either:
:VERTEX - returns an instance of VERTEX class
:VEC - returns an instance of vec3
:VEC4 - returns an instance of vec4"
  ;; transformation : x z y -> x y z
  (let ((x (first attrs))
        (y (third attrs))
        (z (second attrs)))
    (case type
      (:vertex (make-vertex x y z))
      (:vec (vec x y z))
      (:vec4 (vec4 x y z 1)))))
        



(defmethod export-prefab ((self prefab-base) out
                          global-trans prefabs)
  ;; export global
  (export-brushes self out global-trans)
  ;; export prefabs
  (mapc
   (lambda (ent)
     (when-let (found
                (find-entity-property ent "prefabName"))
       (let ((position (find-entity-property ent "position"))
             (angles (find-entity-property ent "angles")))
         (when-let (prefab (find-if (lambda (p) (string= (prefab-name p) (car found))) prefabs))
           (when position
             (let ((transform (mtranslation (position-vector position :type :vec))))
               (when angles
                 ;; angles are in the following format:
                 ;; considering 
                 (destructuring-bind (along-z along-x along-y)
                     angles
                   (setf transform
                         (m* transform
                           (rotation-matrix (- along-z)
                                            (- along-x)
                                            (- along-y)
                           )))))
               (format out "// prefab ~a, position: ~{~a~^, ~} angles: ~{~a~^, ~}~%" (car found) position angles)
               (export-prefab prefab out (m* global-trans transform) prefabs)))))))
   (remove-if-not (lambda (e) (string= (string-downcase (entity-type e)) "prefab")) (prefab-entities self))))


;; item types:
;; Burst Gun 0
;; Shotgun 1
;; Grenade Launcher 2
;; Plasma Rifle 3
;; Rocket Launcer 4
;; Ion Cannon 5
;; Bolt Rifle 6
;; Stake Gun 7
;; 5 Health 40
;; 25 Health 41
;; 50 Health 42
;; 100 Health 43
;; 5 Armor 50
;; Light Armor 51
;; Medium Armor 52
;; Heavy Armor 53
;; Quad Damage 60
(defmethod export-spawns ((self reflex-map) out global-trans)
  (format out "// spawns~%")
  (with-slots (entities) (map-global-prefab self)
    (mapc
     (lambda (ent)
       (let* ((position (find-entity-property ent "position"))
              (angles (find-entity-property ent "angles"))
              (angle (or (car angles) 0)))
         (when position
           (let ((p
                   (m* global-trans
                       ;; for info_player_start the hbox is defined as the following in TrenchBroom:
                       ;; @baseclass size(-16 -16 -24, 16 16 32) color(0 255 0) = PlayerClass []
                       ;; therefore we must offset spawn point
                       ;; by 24 units
                       (v+ (vec 0 0 24 0)
                           (position-vector position :type :vec4)))))
             (format out "{
\"classname\" \"info_player_deathmatch\"~%")
             (format out "\"origin\" ")
             (format out "\"~d ~d ~d\"~%" (vx p) (vy p) (vz p))
             ;; in TrenchBroom only one angle supported - yaw
             (format out "\"angle\" ")
             (format out "\"~a\"~%" (- 90 angle))
             (format out "}~%")))))
     (remove-if-not (lambda (e) (string= (string-downcase (entity-type e)) "playerspawn")) entities))
    (values)))


(defmethod export-lights ((self reflex-map) out global-trans)
;;   (format out "// lights~%")
;;   (with-slots (entities) (map-global-prefab self)
;;     (mapc
;;      (lambda (ent)
;;        (let ((position (find-entity-property ent "position"))
;;              (angles (find-entity-property ent "angles")))
;;          (when position
;;            (let ((p
;;                    (m* global-trans
;;                        ;; for info_player_start the hbox is defined as the following in TrenchBroom:
;;                        ;; @baseclass size(-16 -16 -24, 16 16 32) color(0 255 0) = PlayerClass []
;;                        ;; therefore we must offset spawn point
;;                        ;; by 24 units
;;                        (v+ (vec 0 0 24 0)
;;                            (position-vector position :4d t)))))
;;              (format out "{
;; \"classname\" \"info_player_deathmatch\"~%")
;;              (format out "\"origin\" ")
;;              (format out "\"~d ~d ~d\"~%" (vx p) (vy p) (vz p))
;;              (when angles
;;                ;; in TrenchBroom only one angle supported - yaw
;;                (format out "\"angle\" ")
;;                (format out "\"~a\"~%" (+ (car angles) 180)))
;;            (format out "}~%")))))
;;      (remove-if-not (lambda (e) (string= (string-downcase (entity-type e)) "playerspawn")) entities))
    (values))



(defmethod create-qw-map-file ((self reflex-map) filename &optional (scales (list 1 1 1)))
  (with-open-file (out filename :direction :output :if-exists :supersede)
    (format out "// Game: Quake
// Format: Standard
// entity 0
{
\"classname\" \"worldspawn\"
\"wad\" \"C:/q1mapping/wads/START.WAD\"~%")
    ;; get the global transformation matrix
    (let ((global-trans  (nmscale (meye 4) (apply #'vec scales))))
;;      (write-matrix global-trans t)
      ;; recursively export prefabs
      (export-prefab (map-global-prefab self) out
                     global-trans (map-prefabs self))
      (format out "}~%")
      (export-spawns self out global-trans)
      (export-lights self out global-trans))))



(defun convert-reflex-to-qw (in-filename out-filename &optional (z-scale 1))
  (when-let ((map (parse-reflex-map-file in-filename)))
    (create-qw-map-file map out-filename (list 1 1 z-scale))))



;;;;;;;;;;;; Application entry point ;;;;;;;;;;;;


(defun usage (name)
  (format t "Usage: ~a input-file output-file [z-scale=1]~%there input-file is a Reflex Arena Map (.map) file, output-file - generated Quake1 .map file~%and optional 3rd argument specifies floating point z-scale of the converted map (1 is for 100%) which is default" name))

(defun main(&optional argv)
  (if (and (/= (length argv) 3)
           (/= (length argv) 4))
      (usage (car argv))
      (let ((from (second argv))
            (to (third argv)))
        (convert-reflex-to-qw from to
                              (if (= (length argv) 4)
                                  (read-from-string (fourth argv))
                                  1.0)))))


