# YAS

YAS stands for either **Yet Another Scheme** or **YAS Ain't Scheme**; the
interpretation is up to you.

It is an experimental, Lisp-like programming language written in Zig.

## Annotated parentheses

Nested Lisp often ends in a pile of unlabeled `)`s. You count to see what
closes what:

```scheme
(define (fibo n)
  (cond ((= n 0) 1)
        ((= n 1) 1)
        (else (+ (fibo (- n 1))
                 (fibo (- n 2))))))
```

YAS lets you glue a symbol to a delimiter so the closer names the opener.
`()`, `{}`, and `[]` are interchangeable. Both of these mean the same as
`( * x y )` in other Lisps:

```
(* x y *)
( * x y )
```

`(*` is annotated; `( *` is a plain `(` followed by the symbol `*`. A space
after the opener is the difference. The closer must match both the
annotation and the bracket kind.

The fibonacci example in YAS:

```
{fn fibo [ n ]
    (cond
        ( = n 0 ) 1
        ( = n 1 ) 1
        else (+ ( fibo (- n 1 -) )
                ( fibo (- n 2 -) ) +)
    cond)
fn}
```

`{fn` closes with `fn}`, `(cond` with `cond)`, `(+` with `+)`, `(-` with `-)`.
Ordinary calls keep a space: `( = n 0 )`, `( fibo … )`.

Classic parens still work. Annotate only the forms that help you read; which
spelling is clearer is up to the programmer.

## Requirements

- Zig 0.16.0 or newer

## Build

```sh
zig build
```

## Usage

YAS reads source code from standard input:

```sh
echo '(* x ( + 1 2 ) *)' | zig build run
```

## Tests

```sh
zig build test
```

## Project layout

- `src/tokenizer.zig` — lexical analysis
- `src/parser.zig` — syntax tree and parser
- `src/main.zig` — command-line entry point
- `ideas/` — example YAS source files
