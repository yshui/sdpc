/**
  Combinators
*/
module sdpc.combinators;
import sdpc.primitives;
import std.traits,
       std.string,
       std.stdio,
       std.typetuple,
       std.range;

@safe :
///Match pattern `begin func end`, return the result of func.
struct between(alias begin, alias func, alias end) {
	static auto opCall(R)(R i) if (isForwardRange!R) {
		alias PR = typeof(func(i));
		auto ret1 = begin(i);
		static assert(is(typeof(ret1).ErrType: PR.ErrType));
		if (!ret1.ok)
			return PR(ret1.e);

		auto ret = func(ret1.cont);
		if (!ret.ok)
			return ret;

		auto ret2 = end(ret.cont);
		if (!ret2.ok)
			return PR(ret2.e);
		static if (is(PR.DataType == void))
			return PR(ret2.cont);
		else
			return PR(ret2.cont, ret.v);
	}
}

///
unittest {
	import sdpc.parsers;
	auto i = "(asdf)";
	auto r = between!(token!"(", token!"asdf", token!")")(i);
	assert(r.ok);
	assert(!r.r.length);
}

///Match any of the given pattern, stop when first match is found. All parsers
///must return the same type.
struct choice(T...) {
	static auto opCall(R)(R i) if (isForwardRange!R && allSameType!(staticMap!(ParserReturnType!R, T))) {
		alias PR = typeof(T[0](i));
		alias RT = ParseResult!(R, PR.DataType, PR.ErrType[T.length]);
		PR.ErrType[T.length] err;
		foreach(id, p; T) {
			auto ret = p(i);
			if (ret.ok)
				return RT(ret.cont, ret.v);
			err[id] = ret.e;
		}
		return RT(err[]);
	}
}

/**
  Match pattern `p delim p delim p ... p delim p`

  Return data type will be an array of p's return data type
*/
struct chain(alias p, alias delim, bool allow_empty=false) {
	static auto opCall(R)(R i) if (isForwardRange!R) {
		auto ret = p(i);
		alias T = typeof(ret);
		if (!ret.ok) {
			static if (allow_empty)
				return T(ret.cont, T.DataType.init);
			else
				return ret;
		}

		static if (!is(T.DataType == void))
			T.DataType[] res;
		res ~= ret.v;

		auto last_range = ret.cont;
		while(true) {
			auto dret = delim(last_range);
			if (!dret.ok)
				break;
			auto pret = p(dret.cont);
			if (!pret.ok)
				break;
			static if (!is(T.DataType == void))
				res ~= pret.v;
			last_range = pret.cont;
		}

		static if (is(T.DataType == void))
			return ParseResult!(R, void, T.ErrType)(last_range);
		else
			return ParseResult!(R, T.DataType[], T.ErrType)(last_range, res);
	}
}

/**
  Match `func*` or `func+`

  Return array of func's result
*/
struct many(alias func, bool allow_none = false) {
	static auto opCall(R)(R i) if (isForwardRange!R) {
		alias PR = typeof(func(i));
		static if (is(PR.DataType == void)) {
			alias RT = ParseResult!(R, void, PR.ErrType);
			size_t count = 0;
		} else {
			alias RT = ParseResult!(R, PR.DataType[], PR.ErrType);
			PR.DataType[] res;
		}

		auto last_range = i.save;
		while(true) {
			auto ret = func(last_range);
			if (!ret.ok) {
				static if (is(PR.DataType == void)) {
					if (allow_none || count > 0)
						return RT(last_range);
					else
						return RT(ret.e);
				} else {
					if (allow_none || res.length > 0)
						return RT(last_range, res);
					else
						return RT(ret.e);
				}
			}
			static if (!is(PR.DataType == void))
				res ~= [ret.v];
			else
				count++;
			last_range = ret.cont;
		}
	}
}

///
unittest {
	import sdpc.parsers;
	auto i = "abcdaaddcc";
	alias abcdparser = many!(choice!(token!"a", token!"b", token!"c", token!"d"));
	auto r2 = abcdparser(i);
	assert(r2.ok);
	assert(!r2.r.length);

	i = "abcde";
	auto r3 = abcdparser(i);
	assert(r3.ok); //Parse is OK because 4 char are consumed
	assert(r3.r.length); //But the end-of-buffer is not reached
}

private struct DTTuple(T...) {
	import std.typetuple;
	import std.meta;
	enum notVoid(T) = !is(T.T == void);
	template idMatch(uint id) {
		enum idMatch(T) = T.id == id;
	}
	alias E = Enumerate!T;
	alias E2 = Filter!(notVoid, E);
	private TypeTuple!E2 data;

	ref auto v(uint id)() {
		enum rid = staticIndexOf!(E[id], E2);
		static assert(rid != -1);
		return data[rid].value;
	}
}

/**
  Appply a sequence of parsers one after another.

  Don't use tuple as data type in any of the parsers.
*/
struct seq(T...) {
	static auto opCall(R)(R i) if (isForwardRange!R) {
		alias GetDT(A) = A.DataType;
		alias GetET(A) = A.ErrType;
		alias PRS = staticMap!(ParserReturnType!R, T);
		alias PDT = staticMap!(GetDT, PRS);
		static assert(allSameType!(staticMap!(GetET, PRS)));

		alias RT = ParseResult!(R, DTTuple!PDT, PRS[0].ErrType);
		DTTuple!PDT res;
		auto last_range = i.save;
		foreach(id, p; T) {
			auto ret = p(last_range);
			if (!ret.ok)
				return RT(ret.e);
			static if (!is(PRS[id].DataType == void))
				res.v!id = ret.v;
			last_range = ret.cont;
		}
		return RT(last_range, res);
	}
}

///
unittest {
	import sdpc.parsers;
	auto i = "abcde";
	auto r4 = seq!(token!"a", token!"b", token!"c", token!"d", token!"e")(i);
	assert(r4.ok);
	assert(r4.v.v!0 == "a");
	assert(r4.v.v!1 == "b");
	assert(r4.v.v!2 == "c");
	assert(r4.v.v!3 == "d");
	assert(r4.v.v!4 == "e");

	auto r5 = seq!(token!"a")(i); //seq with single argument.
	assert(r5.ok);
	assert(r5.v.v!0 == "a");
}

/** Optionally matches `p`

  Return data type will be a Nullable of `p`'s data type
*/
struct optional(alias p) {
	static auto opCall(R)(R i) if (isForwardRange!R) {
		import std.typecons;
		auto r = p(i);
		alias PR = typeof(r);
		alias RT = ParseResult!(R, Nullable!(PR.DataType), PR.ErrType);
		if (!r.ok)
			return RT(i, Nullable!(PR.DataType).init);
		else
			return RT(i, nullable(r.v));
	}
}

unittest {
	import sdpc.parsers;

	auto i = "asdf";
	auto r6 = optional!(token!"x")(i);
	assert(r6.ok);
	assert(r6.v.isNull);

	auto r7 = optional!(token!"a")(i);
	assert(r7.ok);
	assert(!r7.v.isNull);
}

/// Match `u` but doesn't consume anything from the input range
struct lookahead(alias u, bool negative = false){
	static ParseResult!R opCall(R)(R i) if (isForwardRange!R) {
		auto r = u(i);
		if ((!r.ok&&!negative) || (r.ok&&negative))
			return ParseResult!R(r.e);
		return ParseResult!R(i);
	}
}


///Skip `p` zero or more times
alias skip(alias p) = discard!(many!(p, true));

///Match `p` but discard the result
struct discard(alias p) {
	static ParseResult!R opCall(R)(R i) if (isForwardRange!R) {
		auto r = p(i);
		if (!r.ok)
			return ParseResult!R(r.e);
		return ParseResult!R(r.cont);
	}
}
