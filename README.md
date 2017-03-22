# sdpc

**sdpc** is a set of very simple, deterministic parser combinators. You can using these combinators to build deterministic parsers for unambiguous grammar without left-recursion.

Because of the determinism, each parser should return a single ParseResult, and indicate the next input position via modifing the input Stream variable.

## Example

```d
import sdpc;

auto parse_parentheses(Stream i) {
	return many!(between!(token!"(", parse_parentheses, token!")"), true)(i);
}
void main() {
	auto i = "(())()(()())";
	assert(parse_parentheses(i).ok);
}
```
