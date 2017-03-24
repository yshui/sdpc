# sdpc

[![build status](https://gitlab.com/yshui/sdpc/badges/master/build.svg)](https://gitlab.com/yshui/sdpc/commits/master)[![codecov](https://codecov.io/gl/yshui/sdpc/branch/master/graph/badge.svg?token=ygO9YBjvy4)](https://codecov.io/gl/yshui/sdpc)

**sdpc** is a set of very simple, deterministic parser combinators. You can using these combinators to build deterministic parsers for unambiguous grammar without left-recursion.

Because of the determinism, each parser should return a single ParseResult, and indicate the next input position via modifing the input Stream variable.

[Documentation](https://yshui.gitlab.io/sdpc)

## Example

```d
import sdpc;

@safe ParseResult!(string, void, ParseError!string) parse_parentheses(string i) {
	return many!(between!(token!"(", parse_parentheses, token!")"), true)(i);
}
void main() {
	auto i = "(())()(()())";
	assert(parse_parentheses(i).ok);
}
```

[More examples](examples)
