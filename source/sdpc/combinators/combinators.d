module sdpc.combinators.combinators;
import sdpc.primitives;
import std.traits,
       std.string,
       std.stdio,
       std.typetuple;

///Match pattern `begin func end`, return the result of func.
auto between(alias begin, alias func, alias end)(Stream input) {
	alias RetTy = ReturnType!func;
	alias ElemTy = ElemType!RetTy;
	static assert(is(RetTy == ParseResult!U, U));
	auto begin_ret = begin(input);
	size_t consumed = begin_ret.consumed;
	if (begin_ret.s != State.OK)
		return err_result!ElemTy();
	auto ret = func(input);
	if (ret.s != State.OK) {
		input.rewind(consumed);
		return ret;
	}
	consumed += ret.consumed;
	auto end_ret = end(input);
	if (end_ret.s != State.OK) {
		input.rewind(consumed);
		return err_result!ElemTy();
	}
	ret.consumed = end_ret.consumed+consumed;
	return ret;
}

///Match any of the given pattern, stop when first match is found. All parsers
///must return the same type.
auto choice(T...)(Stream input) {
	alias ElemTy = ElemType!(ReturnType!(T[0]));
	foreach(p; T) {
		auto ret = p(input);
		if (ret.s == State.OK)
			return ret;
	}
	return err_result!ElemTy();
}

/**
  Match pattern `p delim p delim p ... p delim p`

  Return the result of left-associative applying `op` on the result of `p`
*/
auto chain(alias p, alias op, alias delim)(Stream input) {
	auto ret = p(input);
	alias ElemTy = ReturnType!op;
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
			return ok_result!ElemTy(res, consumed);
		}
		static if (is(ReturnType!delim == ParseResult!void))
			res = op(res, pret.result);
		else
			res = op(res, dret.result, pret.result);
		ret = pret;
		consumed += dret.consumed+pret.consumed;
	}
	return ok_result!ElemTy(res, consumed);
}

/**
  Match `func*` or `func+`

  Return array of func's result
*/
auto many(alias func, bool allow_none = false)(Stream i) {
	alias ElemTy = ElemType!(ReturnType!func);
	static if (is(ElemTy == void)) {
		alias ARetTy = ParseResult!void;
		size_t count = 0;
	} else {
		alias ARetTy = ParseResult!(ElemTy[]);
		ElemTy[] res;
	}
	size_t consumed = 0;
	while(true) {
		auto ret = func(i);
		if (ret.s != State.OK) {
			static if (is(ElemTy == void))
				return ARetTy((count || allow_none) ?
				               State.OK : State.Err, consumed);
			else
				return ARetTy((res.length || allow_none) ?
				              State.OK : State.Err, consumed, res);
		}
		consumed += ret.consumed;
		static if (!is(ElemTy == void))
			res ~= [ret];
		else
			count++;
	}
}

///Consumes nothing, always return OK
auto nop(Stream i) {
	return ParseResult!void(State.OK, 0);
}

private class ParserID(alias func, int id) { }

private template genParserID(int start, T...) {
	static if (T.length == 0)
		alias genParserID = TypeTuple!();
	else {
		private alias now = ParserID!(T[0], start);
		static if (is(ReturnType!(T[0]) == ParseResult!void))
			private enum int next = start;
		else
			private enum int next = start+1;
		alias genParserID = TypeTuple!(now, genParserID!(next, T[1..$]));
	}
}

/**
  Matching using a sequence of parsers, beware that result can only be
  indexed with number readable at compile time, like this: `ret.resutl!0`.

  Also none of the parsers used in seq can return a tuple of results. Otherwise
  it won't compile.
*/
auto seq(T...)(Stream i) {
	alias ElemTys = ElemTypesNoVoid!(staticMap!(ReturnType, T));
	alias RetTy = ParseResult!ElemTys;
	alias PID = genParserID!(0, T);
	ElemTys res = void;
	size_t consumed = 0;
	foreach(pid; PID) {
		static if (is(pid == ParserID!(p, id), alias p, int id)) {
			auto ret = p(i);
			consumed += ret.consumed;
			if (ret.s != State.OK) {
				i.rewind(consumed);
				return RetTy(State.Err, 0, ElemTys.init);
			}
			static if (!is(typeof(ret) == ParseResult!void))
				res[id] = ret.result;
		} else
			static assert(false, p);
	}
	return RetTy(State.OK, consumed, res);
}

///optionally matches p.
auto optional(alias p)(Stream i) {
	auto r = p(i);
	r.s = State.OK;
	return r;
}

///lookahead
auto lookahead(alias p, alias u, bool negative = false)(Stream i) {
	auto r = p(i);
	alias RetTy = typeof(r);
	alias ElemTy = ElemType!RetTy;
	if (!r.ok)
		return r;

	auto r2 = u(i);
	i.rewind(r2.consumed);

	bool pass = r2.ok;

	static if (negative)
		pass = !pass;

	if (!pass) {
		i.rewind(r.consumed);
		return err_result!ElemTy();
	}
	return r;
}

///This combinator first try to match u without consuming anything,
///and continue only if u matches (or not, if negative == true).
auto when(alias u, alias p, bool negative = false)(Stream i) {
	alias RetTy = ReturnType!p;
	alias ElemTy = ElemType!RetTy;
	auto r = u(i);
	i.rewind(r.consumed);

	static if (negative) {
		if (r.ok)
			return err_result!ElemTy();
	} else {
		if (!r.ok)
			return err_result!ElemTy();
	}

	auto r2 = p(i);
	return r;
}

///Match a string, return the matched string
ParseResult!string token(string t)(Stream input) {
	if (!input.starts_with(t))
		return err_result!string();
	string ret = input.advance(t.length);
	return ok_result!string(ret, t.length);
}

///Skip `p` zero or more times
ParseResult!void skip(alias p)(Stream i) {
	auto r = many!(p, true)(i);
	return ParseResult!void(State.OK, r.consumed);
}

///
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

	i.rewind(4);
	auto r4 = seq!(token!"a", token!"b", token!"c", token!"d", token!"e")(i);
	assert(r4.s == State.OK);
	assert(r4.result!0 == "a");
	assert(r4.result!1 == "b");
	assert(r4.result!2 == "c");
	assert(r4.result!3 == "d");
	assert(r4.result!4 == "e");

	i.rewind(1);
	auto r5 = seq!(token!"e")(i); //test seq with single argument.
	assert(r5.s == State.OK, to!string(r5.s));
	assert(r5.result == "e");

	i.rewind(1);
	auto r6 = optional!(token!"a")(i);
	assert(r6.s == State.OK);
	assert(r6.t is null);
}
