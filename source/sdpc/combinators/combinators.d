module sdpc.combinators.combinators;
import sdpc.primitives;
import std.traits,
       std.string,
       std.stdio,
       std.typetuple;

@safe :
///Match pattern `begin func end`, return the result of func.
auto between(alias begin, alias func, alias end)(Stream i) {
	alias RetTy = ReturnType!func;
	alias ElemTy = ElemType!RetTy;
	static assert(is(RetTy == ParseResult!U, U));
	i.push();
	auto begin_ret = begin(i);
	size_t consumed = begin_ret.consumed;
	if (begin_ret.s != Result.OK) {
		i.pop();
		return err_result!ElemTy(begin_ret.r);
	}

	auto ret = func(i);
	if (!begin_ret.r.empty) {
		if (ret.r.empty)
			ret.r = begin_ret.r;
		else if (begin_ret.r > ret.r)
			ret.r = begin_ret.r;
	}
	if (ret.s != Result.OK) {
		i.pop();
		return err_result!ElemTy(ret.r);
	}

	consumed += ret.consumed;
	auto end_ret = end(i);
	if (!end_ret.r.empty && end_ret.r > ret.r)
		ret.r = end_ret.r;
	if (end_ret.s != Result.OK) {
		i.pop();
		return err_result!ElemTy(ret.r);
	}

	ret.consumed = end_ret.consumed+consumed;
	i.drop();
	return ret;
}

///Match any of the given pattern, stop when first match is found. All parsers
///must return the same type.
auto choice(T...)(Stream i) {
	alias ElemTy = ElemType!(ReturnType!(T[0]));
	auto re = Reason(i, "choice");
	Reason last = Reason(i, "tmp");
	foreach(p; T) {
		auto ret = p(i);
		if (ret.s == Result.OK)
			return ret;
		re.dep ~= ret.r;
		if (ret.r > last)
			last = ret.r;
	}
	re.line = last.line;
	re.col = last.col;
	return err_result!ElemTy(re);
}

/**
  Match pattern `p delim p delim p ... p delim p`

  Return the result of left-associative applying `op` on the result of `p`
*/
auto chain(alias p, alias op, alias delim, bool allow_empty=false)(Stream i) {
	auto ret = p(i);
//	alias ElemTy = ReturnType!op;
	static if (allow_empty) {
		if (!ret.ok)
			return ok_result(op(), 0, ret.r);
	} else {
		if (!ret.ok) {
			alias RetTy = typeof(op(ret.result));
			return err_result!RetTy(ret.r);
		}
	}
	auto res = op(ret.result);
	auto consumed = ret.consumed;
	auto re = Reason(i, "chain");
	re.state = "stopped";

	while(true) {
		i.push();
		auto dret = delim(i);
		if (dret.s != Result.OK) {
			i.pop();
			re = dret.r;
			break;
		}
		auto pret = p(i);
		if (pret.s != Result.OK) {
			i.pop();
			re = pret.r;
			break;
		}
		static if (is(ReturnType!delim == ParseResult!void))
			res = op(res, pret.result);
		else
			res = op(res, dret.result, pret.result);
		ret = pret;
		consumed += dret.consumed+pret.consumed;
		i.drop();
	}
	return ok_result(res, consumed, re);
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
	auto re = Reason(i, "many");
	re.state = "stopped";
	size_t consumed = 0;
	while(true) {
		auto ret = func(i);
		if (ret.s != Result.OK) {
			re = ret.r;
			static if (is(ElemTy == void))
				return ARetTy((count || allow_none) ?
				               Result.OK : Result.Err, consumed, re);
			else
				return ARetTy((res.length || allow_none) ?
				              Result.OK : Result.Err, consumed, re, res);
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
	auto re = Reason(i, "nop");
	return ParseResult!void(Result.OK, 0, re);
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
	auto re = Reason(i, "seq");
	ElemTys res;
	size_t consumed = 0;
	i.push();
	foreach(pid; PID) {
		static if (is(pid == ParserID!(p, id), alias p, int id)) {
			auto ret = p(i);
			consumed += ret.consumed;
			if (ret.r.dep.length != 0 || ret.r.msg){
				if (ret.r > re)
					re = ret.r;
			}
			if (ret.s != Result.OK) {
				//writeln("Matching " ~ __traits(identifier, p) ~ " failed, rewind ", consumed);
				i.pop();
				//writefln("XXX%s %s, %s", ret.r.line, ret.r.col, ret.r.explain());
				static if (ElemTys.length == 1)
					return err_result!(ElemTys[0])(re);
				else
					return err_result!ElemTys(re);
			}
			static if (!is(typeof(ret) == ParseResult!void))
				res[id] = ret.result;
		} else
			static assert(false, p);
	}
	i.drop();
	static if (ElemTys.length == 1)
		return ok_result!(ElemTys[0])(res[0], consumed, re);
	else
		return ok_result(res, consumed, re);
}

auto seq2(alias op, T...)(Stream i) {
	auto r = seq!T(i);
	if (!r.ok)
		return err_result!(ReturnType!op)(r.r);
	alias ElemTy = ElemType!(typeof(r));
	auto ret = op(r.result!0);
	foreach(id, e; ElemTy[1..$])
		ret = op(ret, r.result!(id+1));
	return ok_result(ret, r.consumed, r.r);
}

///optionally matches p.
auto optional(alias p)(Stream i) {
	auto r = p(i);
	r.s = Result.OK;
	return r;
}

///lookahead
auto lookahead(alias p, alias u, bool negative = false)(Stream i) {
	i.push();

	auto r = p(i);
	alias RetTy = typeof(r);
	alias ElemTy = ElemType!RetTy;
	if (!r.ok) {
		r.r.name = "lookahead";
		i.pop();
		return err_result!ElemTy(r.r);
	}

	i.push();
	auto r2 = u(i);
	i.pop();

	bool pass = r2.ok;

	static if (negative)
		pass = !pass;

	if (!pass) {
		auto re = Reason(i, "lookahead");
		i.pop();
		if (r2.ok) {
			r2.r.state = "succeeded";
			r2.r.msg = "which is not expected";
		}
		re.dep ~= r2.r;
		return err_result!ElemTy(re);
	}
	i.drop();
	return r;
}

///This combinator first try to match u without consuming anything,
///and continue only if u matches (or not, if negative == true).
auto when(alias u, alias p, bool negative = false)(Stream i) {
	alias RetTy = ReturnType!p;
	alias ElemTy = ElemType!RetTy;
	auto re = Reason(i, "when");
	i.push();
	auto r = u(i);
	i.pop();

	static if (negative) {
		if (r.ok) {
			auto re2 = r.r;
			re2.state = "succeeded";
			re2.msg = "which is not expected";
			re.dep ~= re2;
			return err_result!ElemTy(re);
		}
	} else {
		if (!r.ok) {
			re.dep ~= r.r;
			return err_result!ElemTy(re);
		}
	}

	auto r2 = p(i);
	return r;
}

///Match a string, return the matched string
ParseResult!string token(string t)(Stream i) {
	auto re = Reason(i, "token");
	if (!i.starts_with(t)) {
		string found;
		if (i.head.length < t.length)
			found = i.head;
		else
			found = i.head[0..t.length];
		re.msg = "expected \"" ~ t ~ "\", but found \"" ~ found ~ "\"";
		return err_result!string(re);
	}
	string ret = i.advance(t.length);
	return ok_result!string(ret, t.length, re);
}

///Skip `p` zero or more times
ParseResult!void skip(alias p)(Stream i) {
	auto re = Reason(i, "skip");
	auto r = many!(p, true)(i);
	return ParseResult!void(Result.OK, r.consumed, re);
}

///Match 'p' but discard the result
ParseResult!void discard(alias p)(Stream i) {
	auto r = p(i);
	if (!r.ok)
		return err_result!void(r.r);
	return ParseResult!void(Result.OK, r.consumed, r.r);
}

///
unittest {
	import std.stdio;
	import std.array;
	import std.conv;
	BufStream i = new BufStream("(asdf)");
	auto r = between!(token!"(", token!"asdf", token!")")(i);
	assert(r.ok);
	assert(i.eof());

	i = new BufStream("abcdaaddcc");
	alias abcdparser = many!(choice!(token!"a", token!"b", token!"c", token!"d"));
	auto r2 = abcdparser(i);
	assert(r2.ok);
	assert(i.eof());

	i = new BufStream("abcde");
	i.push();
	auto r3 = abcdparser(i);
	assert(r3.ok); //Parse is OK because 4 char are consumed
	assert(!i.eof()); //But the end-of-buffer is not reached

	i.revert();
	auto r4 = seq!(token!"a", token!"b", token!"c", token!"d", token!"e")(i);
	assert(r4.ok);
	assert(r4.result!0 == "a");
	assert(r4.result!1 == "b");
	assert(r4.result!2 == "c");
	assert(r4.result!3 == "d");
	assert(r4.result!4 == "e");

	i.revert();
	auto r5 = seq!(token!"a")(i); //test seq with single argument.
	assert(r5.ok, to!string(r5.s));
	assert(r5.result == "a");

	i.revert();
	auto r7 = seq2!(function (string a, string b = "") { return a ~ b; },
			token!"a", token!"b")(i); //test seq with single argument.
	assert(r7.ok);
	assert(r7.result == "ab");

	i.revert();
	auto r6 = optional!(token!"x")(i);
	assert(r6.ok);
	assert(r6.t is null);
}
