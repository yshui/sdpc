/**
    $(B Overview)

    sdpc is a library that provides a set of very simple parser combinators,
    to aid the development of parsers (for compilers or not).

    In this library, a parser is a callable object (a function, a type with
    `opCall`, etc.), that takes a forward range, and returns a `ParseResult`.
    A combinator is a template that takes one or more parsers as its parameter
    and transform them into a new parser. For example, a combinator can take a
    parser and returns a new parser that applies the original parser twice.
    The idea is, you can build more complex parsers by composing a bunch of
    simpler parsers with combinators.

    And sdpc is a library that implements this concept. But since it's a simple
    library It doesn't have features you would expect from a fancier parser
    combinator library, like proper handling of left recursions, memoization,
    etc. But it should be enough for lots of simpler use cases.

    Copyright: 2017 Yuxuan Shui
*/
module sdpc;
public import sdpc.combinators;
public import sdpc.primitives;
public import sdpc.parsers;
