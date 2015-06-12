module combinators.combinators;
import primitives;
import std.traits;
auto between(string begin, string end, alias func)(Stream input) {
	alias RetTy = ReturnType!func;
	static assert(is(RetTy == ParseResult!U, U));
	if (!input.starts_with(begin))
		return RetTy(State.Err, null, 0);
	input.advance(begin.length);
	auto ret = func(input);
	if (ret.s != State.OK) {
		assert(ret.consumed == 0);
		input.rewind(begin.length);
		return ret;
	}
	if (!input.starts_with(end)) {
		input.rewind(ret.consumed+begin.length);
		return RetTy(State.Err, null, 0);
	}
	return RetTy(State.OK, ret.t, ret.consumed+end.length);
}
auto choice(T...)(Stream input) {
	foreach(p; T) {
		auto ret = p(input);
		if (ret.s == State.OK)
			return ret;
		assert(ret.consumed == 0);
	}
	return RetTy(State.Err, null, 0);
}

