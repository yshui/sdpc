module sdpc.combinators.combinators;
import sdpc.primitives;
import std.traits,
       std.string,
       std.stdio;
private template ElemType(T) {
	static if (is(T == ParseResult!U, U))
		alias ElemType = U;
	else
		static assert(false);
}

///Match pattern `begin func end', return the result of func
auto between(alias begin, alias func, alias end)(Stream input) {
	alias RetTy = ReturnType!func;
	alias ElemTy = ElemType!RetTy;
	static assert(is(RetTy == ParseResult!U, U));
	auto begin_ret = begin(input);
	size_t consumed = begin_ret.consumed;
	if (begin_ret.s != State.OK)
		return RetTy(State.Err, 0, ElemTy.init);
	auto ret = func(input);
	if (ret.s != State.OK) {
		input.rewind(consumed);
		return ret;
	}
	consumed += ret.consumed;
	auto end_ret = end(input);
	if (end_ret.s != State.OK) {
		input.rewind(consumed);
		return RetTy(State.Err, 0, ElemTy.init);
	}
	return RetTy(State.OK, end_ret.consumed+consumed, ret);
}

///Match any of the given pattern, stop when first match is found
auto choice(T...)(Stream input) {
	alias RetTy = ReturnType!(T[0]);
	foreach(p; T) {
		auto ret = p(input);
		if (ret.s == State.OK)
			return ret;
	}
	return RetTy(State.Err, 0, null);
}

/**
  Match pattern `p delim p delim p ... p delim p'

  Return op(op(op(...op(p, p), p), p)....)
*/
auto chain(alias p, alias op, alias delim)(Stream input) {
	auto ret = p(input);
	alias RetTy = ParseResult!(ReturnType!op);
	if (ret.s != State.OK)
		return ret;
	ElemType!(typeof(ret)) res = ret;
	auto consumed = ret.consumed;

	while(true) {
		auto dret = delim(input);
		if (dret.s != State.OK)
			break;
		auto pret = p(input);
		if (pret.s != State.OK) {
			input.rewind(dret.consumed);
			return RetTy(State.OK, consumed, res);
		}
		static if (is(ReturnType!delim == ParseResult!void))
			res = op(res, pret.result);
		else
			res = op(res, dret.result, pret.result);
		ret = pret;
		consumed += dret.consumed+pret.consumed;
	}
	return RetTy(State.OK, consumed, res);
}

/**
  Match `func*' or `func+'

  Return array [func, func, ...]
*/
template many(alias func, bool allow_none = false) {
	alias RetTy = ReturnType!func;
	static if (is(RetTy == ParseResult!U, U))
		alias RetElem = U;
	alias ARetTy = ParseResult!(RetElem[]);
	auto many(Stream input) {
		RetElem[] res;
		size_t consumed = 0;
		while(true) {
			auto ret = func(input);
			if (ret.s != State.OK) {
				static if (allow_none)
					return ARetTy(State.OK, consumed, res);
				else
					return ARetTy(res.length ? State.OK : State.Err,
						     consumed, res);
			}
			consumed += ret.consumed;
			res ~= [ret];
		}
	}
}

///Consumes nothing, always return OK
auto nop(Stream i) {
	return ParseResult!void(State.OK, 0);
}

///Match a string, return the matched string
ParseResult!string token(string t)(Stream input) {
	alias RetTy = ParseResult!string;
	if (!input.starts_with(t))
		return RetTy(State.Err, 0, null);
	string ret = input.advance(t.length);
	return RetTy(State.OK, t.length, ret);
}

ParseResult!void skip(alias p)(Stream i) {
	auto r = many!(p, true)(i);
	return ParseResult!void(State.OK, r.consumed);
}

unittest {
	import std.stdio;
	import std.array;
	import std.conv;
	BufStream i = new BufStream("(asdf)");
	auto r = between!(token!"(", token!"asdf", token!")")(i);
	assert(r.s == State.OK);
	assert(i.eof());

	i = new BufStream("abcdaaddcc");
	alias abcdparser = many!(choice!(token!"a", token!"b", token!"c", token!"d"));
	auto r2 = abcdparser(i);
	assert(r2.s == State.OK);
	assert(i.eof());

	i = new BufStream("abcde");
	auto r3 = abcdparser(i);
	assert(r3.s == State.OK); //Parse is OK because 4 char are consumed
	assert(!i.eof()); //But the end-of-buffer is not reached
}
