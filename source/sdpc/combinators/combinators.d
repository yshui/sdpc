module sdpc.combinators.combinators;
import sdpc.primitives;
import std.traits;
auto between(alias begin, alias func, alias end)(Stream input) {
	alias RetTy = ReturnType!func;
	static assert(is(RetTy == ParseResult!U, U));
	auto begin_ret = begin(input);
	size_t consumed = begin_ret.consumed;
	if (begin_ret.s != State.OK)
		return begin_ret;
	auto ret = func(input);
	if (ret.s != State.OK) {
		input.rewind(consumed);
		return ret;
	}
	consumed += ret.consumed;
	auto end_ret = end(input);
	if (end_ret.s != State.OK) {
		input.rewind(consumed);
		return end_ret;
	}
	return RetTy(State.OK, end_ret.consumed+consumed, ret);
}
auto choice(T...)(Stream input) {
	foreach(p; T) {
		auto ret = p(input);
		if (ret.s == State.OK)
			return ret;
	}
	return RetTy(State.Err, 0, null);
}
template many(alias func, bool allow_none = false) {
	alias RetTy = ReturnType!func;
	static if (is(RetTy == ParseResult!U, U))
		alias RetElem = U;
	ParseResult!(RetElem[]) many(Stream input) {
		RetElem[] res;
		size_t consumed = 0;
		while(true) {
			auto ret = func(input);
			if (ret.s != State.OK) {
				static if (allow_none)
					return RetTy(State.OK, consumed, res);
				else
					return RetTy(res.length ? State.OK : State.Err,
						     consumed, res);
			}
			consumed += ret.consumed;
			res ~= [ret];
		}
	}
}
ParseResult!(const(char)[]) token(string t)(Stream input) {
	alias RetTy = ParseResult!(const(char)[]);
	if (!input.starts_with(t))
		return RetTy(State.Err, 0, null);
	const(char)[] ret = input.advance(t.length);
	return RetTy(State.OK, 0, ret);
}
unittest {
	BufStream i = new BufStream("(asdf)");
	auto r = between!(token!"(", token!"asdf", token!")")(i);
	assert(r.s == State.OK);
}
