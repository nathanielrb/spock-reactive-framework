;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Utilities

(define (string-split str char)
  (letrec ((cons-if (lambda (a l)
                      (if (null? a) l (cons a l)))))
    (let loop ((strl1 '())
               (strls '())
               (strl (string->list str)))
      (cond ((null? strl)
             (reverse (map list->string (cons-if (reverse strl1) strls))))
            ((eqv? char (car strl))
             (loop '() (cons-if (reverse strl1) strls) (cdr strl)))
            (else
             (loop (cons (car strl) strl1) strls (cdr strl)))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; DOM

(define (qsa element query) (%inline .querySelectorAll element query))

(define (qs element query) (%inline .querySelector element query))

(define (dqsa element query) (%inline .querySelectorAll document.body query))

(define (dqs element query) (qs document.body query))

(define (log msg) (%inline console.log msg))

(define (alert msg) (%inline window.alert msg))

(define (get-id id) (%inline document.getElementById id))

(define (remove-node node)
  (%inline .removeChild (.parentNode node) node))

(define (insert-node-before node1 node2)
  (%inline .insertBefore (.parentNode node2) node1 node2))

(define (replace-node node1 node2)
  (%inline .replaceChild (.parentNode node2) node1 node2))

(define (node-append-child parent child)
  (%inline .appendChild parent child))

(define (set-html elt content)
  (set! (.innerHTML elt) content))

(define (spock-elements)
  (%inline Array.prototype.slice.call
	   (%inline .querySelectorAll document.body "*[spock]")))

(define (add-event-listener event element callback)
  (%inline .addEventListener element event callback))

(define (set-event event elt cb)
  (set! (event elt) cb) elt)

(define-syntax-rule (bind-event event elt proc)
  (begin (set! (event elt) (callback proc))
	 elt))

(define-syntax-rule (define-event name event)
  (define (name elt cb)
    (set! (event elt) cb) elt))

(define-event set-click .onclick)

(define-event set-change .onchange)

(define-event set-input .oninput)

(define (slice a)
  (%inline Array.prototype.slice.call a))

(define (children node)
  (slice (%property-ref .childNodes node)))

(define (car-safe p)
  (and (pair? p) (car p)))

(define (cdr-safe p)
  (and (pair? p) (cdr p)))

(define (empty? x)
  (not (and (void? x) (null? x) (not x))))

(define (nodename elt)
  (%property-ref .nodeName elt))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; snabbdom Virtual DOM

;; (define (alist->js-obj alist)

(define (h selector props children)
  (let ((kids (cond ((list? children) (list->vector children))
		    ((or (vector? children) (string? children)) children)
		    (else #f))))
    (%inline "snabbdom.h" selector props kids)))

(define (patch old new)
  (%inline "patch" old new))

(define-syntax define-element
  (syntax-rules ()
    ((define-element name elt)
     (define-syntax name
       (syntax-rules ()
	 ;; ((name selector)
	 ;; (lambda (props children)
	 ;;   (h (jstring (string-append elt selector))
	 ;;      props children)))
	 ((name selector)
	  (h (jstring (string-append elt (or selector "")))
	     #f (vector)))
	 ((name selector props)
	  (h (jstring (string-append elt (or selector "")))
	     props (vector)))
	 ((name selector props children)
	  (h (jstring (string-append elt (or selector "")))
	     props children)))))))

(define-element <div> "div")

(define-element <h1> "h1")

(define-element <h2> "h2")

(define-element <h3> "h3")

(define-element <h4> "h4")

(define-element <select> "select")

(define-element <option> "option")

(define-element <input> "input")

(define-element <a> "a")

(define (a-click selector text proc)
  (<a> selector (% "props" (% "href" "#")
		   "on" (% "click" (callback proc)))
       text))

(define-element <pre> "pre")

(define-element <ul> "ul")

(define-element <ol> "ol")

(define-element <li> "li")

(define-element <span> "span")

(define-element <b> "b")

(define-element <i> "i")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Events

;; TO DO
;; Handle different states (loading, done, error...)

(define (ajax-cb x)
  (log (.responseText x)))

(define (ajax method path proc)
  (let ((x (%inline "new XMLHttpRequest")))
    (%inline ".open" x (symbol->string method) (jstring path) #t)
    (set! (.onload x)
      (callback
       (lambda (response)
         (if (equal? (.status x) 200)
             (proc response)
             (begin (log "Ajax error")
                    (log event))))))
    (set! (.responseType x) "json")
    (%inline ".send" x)))

(define (get-callback name)
  (let ((symname (if (string? name) (string->symbol name) name)))
    (get symname 'callback)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Signals

(define waiting (lambda () #f))

(define call/cc call-with-current-continuation)

(define *queue* '())

(define (*enqueue* x)
  (set! *queue* (append *queue* (list x))))

(define (*dequeue*)
  (let ((first (car *queue*)))
    (set! *queue* (cdr *queue*))
    first))

(define (yield)
  (if (null? *queue*)
      (waiting)
      (let ((next-cc (*dequeue*)))
	((next-cc)))))

(define (alist-ref key l)
  (cdr-safe (assoc key l)))

(define-syntax with-bindings
  (syntax-rules ()
    ((with-bindings (vars ...) bindings body ...)
     (let ((vars (alist-ref (quote vars) bindings)) ...)
       body ...))))

(define merge-bindings append)

(define (put-cons! var property val)
  (put! var property
	(cons val (or (get var property) '()))))

(define-syntax-rule (catch-vars (vars ...) body ...)
  (letrec ((bindings (call/cc (lambda (k)
				(let ((K (lambda (vals) (k (append vals bindings)))))
				  (map (lambda (var)
					 (put-cons! var 'continuations K))
				       (list (quote vars) ...)))
				'()))))
    (with-bindings (vars ...) bindings body ...)
    (yield)))

(define (get-binding binding-name bindings)
  (let ((binding-pair (assoc binding-name bindings)))
    (and binding-pair (cdr binding-pair))))

(define (send-bindings var bindings)
  ((get var 'continuations) bindings))

(define (three-way-split A B)
  (let loop ((As A)
	     (Bs B)
	     (accA '())
	     (accAB '())
	     (accB '()))
    (if (null? Bs)
	(list (append As accA) accAB accB)
	(let ((b (car Bs)))
	  (let subloop ((As As)
			(Aleft '()))
	    (if (null? As)
		(loop Aleft (cdr Bs) accA accAB (cons b accB))
		(let ((a (car As)))
		  (if (equal? b a)
		      (loop (append Aleft (cdr As)) (cdr Bs) accA (cons b accAB) accB)
		      (subloop (cdr As) (cons a Aleft))))))))))

(define (merge-alist-sets L new-var-set)
  (let ((newvar (car new-var-set)))
    (let loop ((Ls L)
	       (newset (cdr new-var-set))
	       (accum '()))
    (if (or (null? newset) (null? Ls))
	(cons (cons (list newvar) newset) accum)
	(let* ((vars (caar Ls))
	       (set (cdar Ls))
	       (split (three-way-split set newset))
	       (A (car split))
	       (AB (cadr split))
	       (B (caddr split)))
	  (loop (cdr Ls) B
		(append (list (cons vars A)
			      (cons (cons newvar vars)
				    AB))
			accum)))))))

(define (merge-continuation-lists clists)
  (let loop ((merged '())
	     (clists clists))
    (if (null? clists)
	merged
	(loop (merge-alist-sets merged (car clists))
	      (cdr clists)))))

(define (send-vars var-bindings)
  (map (lambda (varset)
	 (let ((var-names (car varset))
	       (continuations (cdr varset)))
	   (when (not (null? continuations))
	     (map (lambda (k) (*enqueue* (lambda ()  (k var-bindings))))
		  continuations))))
       (merge-continuation-lists
	(map (lambda (var-pair)
	       (let ((var (car var-pair)))
		 (cons var (get var 'continuations))))
	     var-bindings)))
  (yield))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Router

;; more serious - hash/router/path...
;; match path = /user/:name/:repo#file/:id
;; with path => '((name . "name") (repo . "repo") (id . "id"))
;; and round-tripping
;;
;; (render (route: :var1) (other vars) body...)
;;
;; later, consider something like
;; <div spock-route="/user/:name/:repo#file/:id" spock-render="proc"> ...

(define (get-hash)
  (let ((hash window.location.hash))
    (and hash (not (equal? hash ""))
	 (not (equal? hash "#"))
	 (substring hash 1))))

(define (set-hash! hash)
  (set! window.location.hash
    (jstring (string-append "#" hash))))

(define (get-path)
  (string-split window.location.pathname #\/))

;; (define (match-route path routes)
;;  => alist '((name . "Bob") (other . #f) (another . #f)))

;; match and send, with all other :vars = #f
;; (define-routes
;;   '("base"
;;     ("user" :user)
;;     ("app"
;;      (:app ("join" "run"))))

;; or (define-route ("base" :var1) (send-vars ...)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; API

(define (register-component name cb)
  (let ((symname (if (string? name) (string->symbol name) name)))
    (put! symname 'callback cb)))

;; (send (a b) (... (values 1 2)))
(define-syntax send
  (syntax-rules ()
    ((send (vars ...) body ...)
     (call-with-values
	 (lambda () body ...)
       (lambda (vars ...)
	 (send-vars
	  (list (cons (quote vars) vars) ...)))))))

;; Is this possible without set! and the this/ref switch?

(define-syntax-rule (render* ref (vars ...) body ...)
  (catch-vars (vars ...)
    (let ((newnode (h (nodename ref) #f (vector body ...))))
      (set! ref (patch ref newnode)))))

(define-syntax render
  (syntax-rules (route:)
    ((render (route: route ...) (vars ...) body)
     ;; add check that route is registered
     (render (route ... vars ...) (and route ... body))) 
    ((render (vars ...) body)
     (lambda (this)
       (let ((ref this))
         (catch-vars (vars ...)
           (let ((newnode body))
             (if newnode
                 (set! ref (patch ref newnode))
                 ref))))))))

(define-syntax-rule (bind this event (vars ...) body ...)
  (catch-vars (vars ...)
    (bind-event event this
		(lambda (this)
		  body ...))))

(define-syntax-rule (bind-this event (vars ...) proc)
  (lambda (this)
    (catch-vars (vars ...)
      (bind-event event this proc))))

(define-syntax cb
  (syntax-rules ()
    ((cb (vars ...) body)
     (callback
      (lambda (event)
	(send (vars ...)
              (body event)))))))

(define-syntax init
  (syntax-rules ()
    ((init ((vars vals) ...))
     (begin
       (map (lambda (e)
	      (let ((name (%inline .getAttribute e "spock")))
		((get-callback name) e)))
	    (spock-elements))

       (send (vars ...) (values vals ...))

       (call/cc (lambda (k) (set! waiting k)))
       (begin (print "waiting..."))))
    ((init) (init ()))))

;    body ...
 ;   (call/cc (lambda (k) (set! waiting k)))
  ;  (begin (print "waiting..."))))

(define (start)
  (call/cc (lambda (k) (set! waiting k)))
  (begin (print "waiting...")))
