; Misc utils
(define-module (utils)
    #:export (
        bit-vector
        for-loop
        make-guile-style-hex
    ))

; for-loop
(define* (for-loop start end func #:optional (step 1))
    (letrec
        ((loop 
            (lambda (i)
                (if (> i end)
                    '()
                    (cons (func i) (loop (+ i step)))
                    )
                )
            ))
        (loop start)
        )
    )

; from start to end of num
(define (bit-vector num start end)
    (for-loop start end (lambda (i) (logbit? i num)))
    )

; Convert 0x123 to #x123 as guile style
(define (make-guile-style-hex str)
    (if (string-prefix-ci? "0x" str)
        (string-append "#" (substring str 1))
        'str
    ))