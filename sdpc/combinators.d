/**
  Combinators

  Copyright: 2017 Yuxuan Shui
*/
module sdpc.combinators;
import sdpc.primitives;
import std.traits,
       std.string,
       std.stdio,
       std.typetuple,
       std.range;
import std.algorithm : move;

///Match pattern `begin func end`, return the result of func.
alias between(alias begin, alias func, alias end) = transform!(seq!(discard!begin, func, discard!end), (ref x) => move(x.v!1));

///
@safe unittest {
	import sdpc.parsers;
	auto i = "(asdf)";
	auto r = between!(token!"(", token!"asdf", token!")")(i);
	assert(r.ok);
	assert(!r.cont.length);
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
			err[id] = ret.err;
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
		static if (is(T.DataType == void))
			alias RT = ParseResult!(R, void, T.ErrType);
		else
			alias RT = ParseResult!(R, T.DataType[], T.ErrType);
		if (!ret.ok) {
			static if (allow_empty)
				return RT(ret.cont, []);
			else
				return RT(ret.err);
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
			return RT(last_range);
		else
			return RT(last_range, res);
	}
}

///
@safe unittest {
	import sdpc.parsers;
	import std.algorithm;

	alias calc = transform!(chain!(number!(), token!"+"), (x) => x.reduce!"a+b");
	auto i = "1+2+3+4+5";
	auto r = calc(i);
	assert(r.ok);
	assert(r.v == 15);
}

/**
  Match `func*` or `func+`

  Apply reduce() on the `func`'s return data value (i.e. ReturnType.data)
*/
struct many_r(alias func, alias reduce, alias init, bool allow_none = false) {
	static auto opCall(R)(R i) if (isForwardRange!R) {
		alias PR = typeof(func(i));
		alias RDT = typeof(init);
		alias RT = ParseResult!(R, RDT, PR.ErrType);
		RDT res = init;

		auto last_range = i.save;
		bool none = true;
		while(true) {
			auto ret = func(last_range);
			if (!ret.ok) {
				if (allow_none || !none)
					return RT(last_range, res);
				else
					return RT(ret.err);
			}
			none = false;
			static if (!is(PR.DataType == void))
				res = reduce(res, ret.v);
			else
				res = reduce(res);
			last_range = ret.cont;
		}
	}
}

/**
  Like `many_r` but with default `reduce` function that put all return
  values into an array, or return number of matches
*/
struct many(alias func, bool allow_none = false) {
	static auto opCall(R)(R i) if (isForwardRange!R) {
		alias PR = typeof(func(i));
		static if (is(PR.DataType == void))
			return many_r!(func, a=>a+1, 0uL, allow_none)(i);
		else
			return many_r!(func, (ref a, ref b) {
				a.length++;
				move(b, a[$-1]);
				return a;
			}, cast(PR.DataType[])[], allow_none)(i);
	}
}

struct many_alloc(alias allocator, alias func, bool allow_none = false) {
	import std.experimental.allocator;
	import std.algorithm : moveEmplace;
	struct _Arr(T, bool f = false) {
		T[] storage;
		static if (f) {
			~this() {
				import core.stdc.stdio;
				allocator.dispose(storage);
			}
			@disable this(this);
			alias storage this;
		} else {
			size_t len;
		}
	}
	static auto append(T)(ref _Arr!T a, ref T b) {
		if (a.len >= a.storage.length) {
			if (a.storage)
				allocator.expandArray(a.storage, a.storage.length);
			else
				a.storage = allocator.makeArray!T(4);
		}
		moveEmplace(b, a.storage[a.len]);
		a.len++;
		return a;
	}
	static auto opCall(R)(R i) if (isForwardRange!R) {
		alias PR = typeof(func(i));
		alias DT = PR.DataType;
		static if (is(DT == void))
			return many_r!(func, a=>a+1, 0uL, allow_none)(i);
		else
			return transform!(many_r!(func, append, _Arr!DT(), allow_none), x => _Arr!(DT, true)(x.storage[0..x.len]))(i);
	}
}

///
@safe unittest {
	import sdpc.parsers;
	auto i = "abcdaaddcc";
	alias abcdparser = many!(choice!(token!"a", token!"b", token!"c", token!"d"));
	auto r2 = abcdparser(i);
	assert(r2.ok);
	assert(!r2.cont.length);

	i = "abcde";
	auto r3 = abcdparser(i);
	assert(r3.ok); //Parse is OK because 4 char are consumed
	assert(r3.cont.length); //But the end-of-buffer is not reached
}

// We need this because TypeTuple don't allow `void` in it.
private struct DTTuple(T...) {
	import std.typetuple;
	import std.meta;
	enum notVoid(T) = !is(T.T == void);
	template idMatch(uint id) {
		enum idMatch(T) = T.id == id;
	}
	alias E = staticEnumerate!T;
	alias E2 = Filter!(notVoid, E);
	private TypeTuple!E2 data;

	ref auto v(uint id)() {
		enum rid = staticIndexOf!(E[id], E2);
		static if (rid != -1)
			return data[rid].value;
		else
			return;
	}
}

/**
  Appply a sequence of parsers one after another.

  Don't use tuple as data type in any of the parsers. The return
  data type is a special type of tuple. To get the data of each of
  the parsers, use `ParseResult.v.v!index`, where `index` is the
  index of the desired parser in `T`.
*/
struct seq(T...) {
	static auto opCall(R)(R i) if (isForwardRange!R) {
		import std.algorithm : move;
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
				return RT(ret.err);
			static if (!is(PRS[id].DataType == void))
				res.v!id = move(ret.v);
			last_range = ret.cont;
		}
		return RT(last_range, res);
	}
}

///
@safe unittest {
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

///
@safe unittest {
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
	static auto opCall(R)(R i) if (isForwardRange!R) {
		auto r = u(i);
		alias PR = typeof(r);
		alias RT = ParseResult!(R, void, PR.ErrType);
		static if (negative) {
			if (r.ok)
				return RT(RT.ErrType.init);
			else
				return RT(i);
		} else {
			if (r.ok)
				return RT(i);
			else
				return RT(r.err);
		}
	}
}

///
@safe unittest {
	import sdpc.parsers;

	// Accept "asdf" if followed by "g"
	alias p = seq!(token!"asdf", lookahead!(token!"g"));
	auto i = "asdfg";
	auto r1 = p(i);
	assert(r1.ok);
	assert(r1.cont == "g", r1.cont);

	i = "asdff";
	auto r2 = p(i);
	assert(!r2.ok);
}

///Skip `p` zero or more times
alias skip(alias p) = discard!(many!(discard!p, true));

///Match `p` but discard the result
alias discard(alias p) = transform!(p, (_) { });
