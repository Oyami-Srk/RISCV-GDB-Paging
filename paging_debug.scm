; Paging Debugging tool for RISCV, Guile Version

(use-modules ((gdb) #:prefix gdb:))

(load "SV39.scm")
(load "SV48.scm")
(load "utils.scm")

(use-modules (utils))

(define is-riscv64? (string=? (gdb:target-config) "riscv64-elf"))
(define is-riscv32? (string=? (gdb:target-config) "riscv32-elf"))
(if is-riscv64? 
  (display "Target is riscv64\n")
  (if is-riscv32?
  (display "Traget is riscv32, which is not supported yet.\n")
  (display "Unknown target, target must be riscv32/64\n")))


(define use-utf8 #t)
(define output-lines (if use-utf8 (list "│  " "├─ " " │ ") (list "|  " "|-" " |")))
(define type-separator " ")

; PDE walk
; on-dent parameters: dir-address level.
; on-leaf parameters: va-start va-end pa-start pa-end type level
(define (pde-walk pgdir level offset on-dent on-leaf)
    (if (< level mmu:pte-max-level)
        (let ((pgdir  (gdb:value-cast (gdb:make-value pgdir) (gdb:type-pointer mmu:pte-type))))
            (letrec (
                (walk (lambda (id last_va_start last_va_end last_pa_start last_type last_continue)
                    (let ((try-last 
                            (lambda ()
                                (if last_continue
                                    (on-leaf last_va_start last_va_end 
                                            last_pa_start 
                                            (+ last_pa_start 
                                                (- last_va_end last_va_start))
                                            last_type level)
                                    ))))
                        (if (= id mmu:pte-per-page)
                            (try-last)
                            (let* (
                                    (pte (mmu:pte-at pgdir id))
                                    (pa (car pte))
                                    (type (cdr pte))
                                    (start (+ offset (* id (list-ref mmu:pte-level-size level))))
                                    (end (+ start (list-ref mmu:pte-level-size level)))
                                )
                                (if (mmu:is-pte-valid? pte)
                                    (if (mmu:is-pte-a-pde? pte)
                                        (begin
                                            (on-dent pa level)
                                            (pde-walk pa (+ level 1) start on-dent on-leaf)
                                            (walk (+ id 1) 0 0 0 0 #f)); Dir
                                        (if (and 
                                                (= last_va_end start) 
                                                (equal? last_type type) 
                                                (= (+ last_pa_start (- last_va_end last_va_start)))
                                                )
                                            (walk (+ id 1) last_va_start end last_pa_start last_type last_continue)
                                            (begin
                                                (try-last)
                                                (walk (+ id 1) start end pa type #t)
                                            )) ; Leaf
                                        ) ; Valid
                                    (begin
                                        (try-last)
                                        (walk (+ id 1) 0 0 0 0 #f)) ; Non-valid
                                )))))))
                (walk 0 0 0 0 0 #f)))))

; Command Paging inspector
(gdb:register-command! (
    gdb:make-command "paging"
    #: command-class gdb:COMMAND_USER
    #: doc "RISC-V MMU Paging Debugging tool.
Usage: 
    v2p add          : Get Physical address of a virtual address from pagetable at satp.
    v2p pg_addr addr : Get Physical address of a virtual address from pagetable at pg_addr.
Example:
    (gdb) v2p 0x12345678
    (gdb) v2p 0x81230000 0x12345678"
    #: invoke (lambda (self args from-tty) (mmu-debug-command "paging" args))
))

; Command Paging inspector
(gdb:register-command! (
    gdb:make-command "v2p"
    #: command-class gdb:COMMAND_USER
    #: doc "RISC-V MMU Paging Debugging tool.
Usage: 
    paging           : The shortcut of `paging satp` 
    paging satp      : Show page table from satp register.
    paging addr      : Show page table at addr.
Example:
    (gdb) paging
    (gdb) paging satp
    (gdb) paging 0x12340000"
    #: invoke (lambda (self args from-tty) (mmu-debug-command "v2p" args))
))


(define (extract-root-pgdir-from-satp satp)
    (if is-riscv64?
        (ash (logand satp #xFFFFFFFFFFF) 12)
        (ash (logand satp #x3FFFFF) 12))
)

(define (extract-root-pgdir-from-satp? subcommand args)
    (if (string=? subcommand "paging") (or (= (string-length (car args)) 0) (string=? (car args) "satp")) 
    (if (string=? subcommand "v2p") (null? (cdr args))))
)

(define (extract-root-pgdir-from-args subcommand args)
    (string->number (make-guile-style-hex (car args)))
    ; (if (string=? subcommand "paging") (string->number (car args))
    ; (if (string=? subcommand "v2p") (string->number (car args))))
)

(define (mmu-debug-command subcommand args)
    (let* (
        (args (string-split args #\ ))
        (satp (gdb:value->integer (gdb:frame-read-register (gdb:selected-frame) "satp")))
        (mode (if is-riscv64?
                (logand (ash satp -60) #xF )  ;RV64
                (logand (ash satp -31) 1))) ;RV32
        (mode-str (case mode ((0) "Bare") ((1) "SV32") ((8) "SV39") (else "Unknown")))
        (root-pgdir (if (extract-root-pgdir-from-satp? subcommand args) 
                        (extract-root-pgdir-from-satp satp)
                        (extract-root-pgdir-from-args subcommand args)))
        )

        (case mode
            ((8) (use-modules ((SV39) #:prefix mmu:)))
            (else (gdb:throw-user-error (format #f "MMU Mode (~a) unsupported." mode-str)))
        )
        (display "MMU Mode: ")
        (display mode-str)
        (newline)
        (format #t "Page Table @ 0x~:@(~x~)" root-pgdir)
        (newline)

        (if (string=? subcommand "paging") (do-paging root-pgdir)
        (if (string=? subcommand "v2p") (do-v2p root-pgdir (if (extract-root-pgdir-from-satp? "v2p" args) (car args) (cadr args)))))
))


(define (do-paging root-pgdir)
    (let (
        ; on-dent parameter: dir-address.
        (on-dent (lambda (dir-addr level) 
            (for-loop 0 (- level 1) (lambda (i) (display (list-ref output-lines 0))))
            (display (list-ref output-lines 1))
            (format #t "Directory @ 0x~:@(~x~)\n" dir-addr)))
        ; on-leaf parameter: va-start va-end pa-start pa-end type level
        (on-leaf (lambda (va-start va-end pa-start pa-end type level) 
            (for-loop 0 (- level 1) (lambda (i) (display (list-ref output-lines 0))))
            (display (list-ref output-lines 1))
            (format #t "0x~:@(~x~) ~~ 0x~:@(~x~) => 0x~:@(~x~) ~~ 0x~:@(~x~)"
                va-start va-end pa-start pa-end)
            (display (list-ref output-lines 2))
            (mmu:print-type type type-separator)
            (newline)
        )))
        (pde-walk root-pgdir 0 0 on-dent on-leaf)))

(define (do-v2p root-pgdir va)
    (let* ((v2p-info (mmu:v2p root-pgdir va)) (pa (car v2p-info)) (type (cdr v2p-info))) 
    (format #t "0x~:@(~x~) => 0x~:@(~x~)" (string->number (make-guile-style-hex va)) pa)
    (display (list-ref output-lines 2))
    (print-type type type-separator)
    (newline)
))
