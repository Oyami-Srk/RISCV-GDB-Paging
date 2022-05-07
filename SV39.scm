; SV39 implementation
(define-module (SV39)
    #:export (
        pte-at
        v2p
        print-type
        pte-max-level
        pte-level-size
        pte-per-page
        pte-type
        is-pte-valid?
        is-pte-a-pde?
    ))

(load "utils.scm")

(use-modules ((gdb) #:prefix gdb:))
(use-modules (utils))

(define page-size 4096) ; in bytes
(define pte-size 8)     ; in bytes
(define pte-per-page (/ page-size pte-size))
(define pte-max-level 3)
(define pte-level-size 
    (letrec (
        (l (letrec 
            ((size (lambda (lvl pre) 
                (let ((cur (* pre pte-per-page)))
                    (if (>= lvl pte-max-level)
                        '()
                        (cons cur (size (+ lvl 1) cur))
                        )))))
            (size 0 (/ page-size pte-per-page))
            ))
        (reverse-list (lambda (l)
            (if (null? l) '() (append (reverse-list (cdr l)) (list (car l)))))))
        (reverse-list l)))

; PTE gdb type
(define pte-type (gdb:lookup-type "unsigned long"))
; PTE destruct
(define (pte-destruct pte)
    (cons
        ; Physical address
        (ash (ash pte -10) 12)
        ; Type bit-vector
        (bit-vector pte 0 9)
        ))
; PTE Check
(define (is-pte-valid? pte) (cadr pte))
(define (is-pte-a-pde? pte)
    (let ((type (cdr pte))) (not (or (list-ref type 1) (list-ref type 2) (list-ref type 3)))))
; Get PTE via ID and pgdir
(define (pte-at pgdir id)
    (pte-destruct (gdb:value->integer (gdb:value-subscript pgdir id))))

; SV39 PTE Type bits names
(define type-names (list "V" "R" "W" "X" "U" "G" "A" "D" "RS1" "RS2"))

(define (print-type type sep)
    (for-loop 0 9 
        (lambda (i) 
            (if (list-ref type i)
                (begin
                    (display (list-ref type-names i))
                    (display sep))))))

; VA destruct
(define (va-destruct va)
    (let
        ((vpn-mask #b111111111)
         (offset-mask #b111111111111)
         (va (string->number (make-guile-style-hex va))))
        (list
            ; VPN 2
            (logand (ash va -30) vpn-mask)
            ; VPN 1
            (logand (ash va -21) vpn-mask)
            ; VPN 0
            (logand (ash va -12) vpn-mask)
            ; offset
            (logand va offset-mask)
            )))

; V2P
(define (v2p pgdir va)
    (let (
        (va (va-destruct va)))
    (letrec 
        ((walk (lambda (pgdir level)
            (let* (
                (pgdir (gdb:value-cast (gdb:make-value pgdir) (gdb:type-pointer pte-type)))
                (pte (pte-at pgdir (list-ref va level))))
                (if (is-pte-valid? pte)
                    (if (is-pte-a-pde? pte)
                        (walk (car pte) (+ level 1)) ; Dir
                        (cons 
                            (+ (car pte) (list-ref va pte-max-level))
                            (cdr pte)) ; Leaf
                    ) ; Valid
                    (gdb:throw-user-error "Virtual address not mapped or map not valid.") ; Not-valid
                )
            )
        )))
        (walk pgdir 0)
    ))
)