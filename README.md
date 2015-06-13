#SDPC

SDPC is a set of very simple, deterministic parser combinators. You can using these combinators to build deterministic parsers for unambiguous grammar without left-recursion.

Because of the determinism, each parser should return a single ParseResult, and indicate the next input position via modifing the input Stream variable.
