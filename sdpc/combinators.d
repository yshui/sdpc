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
       std.functional,
       std.variant,
       std.experimental.allocator;

import std.experimental.allocator.gc_allocator : GCAllocator;

///Match pattern `begin func end`, return the result of func.
alias between(alias begin, alias func, alias end) = pipe!(seq!(discard!begin, func, discard!end), wrap!"move(a.v!1)");

///
unittest {
	import sdpc.parsers;
	auto i = "(asdf)";
	auto r = between!(token!"(", token!"asdf", token!")")(i);
	assert(r.ok);
	assert(!r.cont.length);
}

///Match any of the given pattern, stop when first match is found. All parsers
///must return the same type.
struct choice(T...) {
	enum notVoid(T) = !is(T == void);
	enum hasCombine(T) = is(typeof(T.init + T.init) == T);
	static auto opCall(R)(in auto ref R i)
	if (isForwardRange!R) {
		alias GetDT(A) = A.DataType;
		alias GetET(A) = A.ErrType;
		alias PRS = ParserReturnTypes!(R, T);
		alias PDT = staticMap!(GetDT, PRS);
		alias PET = Filter!(notVoid, staticMap!(GetET, PRS));
		static assert(allSameType!PET);
		static assert(allSameType!PDT);
		static assert(hasCombine!(PET[0]));
		static if (hasCombine!(PET[0])) {
			alias RT = Result!(R, PDT[0], PET[0]);
			PET[0] err;
		} else {
			alias RT = Result!(R, PDT[0], PET[0][T.length]);
			PET[0][T.length] err;
		}
		foreach(id, p; T) {
			auto ret = p(i);
			if (ret.ok)
				return RT(ret.cont, ret.v);
			static if (is(typeof(ret.err))) {
				static if (hasCombine!(PET[0])) {
					static if (id == 0)
						err = ret.err;
					else
						err = err + ret.err;
				} else
					err[id] = ret.err;
			} else
				assert(0);
		}
		return RT(err);
	}
}

/**
  Match pattern `p delim p delim p ... p delim p`

  Return data type will be an array of p's return data type
*/
struct chain(alias p, alias delim, bool allow_empty=false) {
	static auto opCall(R, alias Allocator = GCAllocator.instance)(in auto ref R i)
	if (isForwardRange!R) {
		import containers.dynamicarray : DynamicArray;
		import std.experimental.allocator.common : stateSize;
		import std.algorithm.mutation : move;
		auto ret = p(i);
		alias T = typeof(ret);
		alias DT = typeof(delim(i));
		alias RDT = DTTuple!(T.DataType, DT.DataType);
		alias RDTA = DynamicArray!(RDT, typeof(Allocator));
		alias RT = Result!(R, RDTA, T.ErrType);
		if (!ret.ok) {
			static if (allow_empty)
				return RT(i, []);
			else
				return RT(ret.err);
		}

		static if (stateSize!(typeof(Allocator))) {
			auto res = RDTA(Allocator);
		} else {
			RDTA res;
		}
		RDT tmp;
		static if (!is(T.DataType == void))
			tmp.v!0 = ret.v;
		res ~= tmp;

		auto last_range = ret.cont;
		while(true) {
			auto dret = delim(last_range);
			if (!dret.ok)
				break;
			static if (!is(DT.DataType == void))
				tmp.v!1 = dret.v;
			auto pret = p(dret.cont);
			if (!pret.ok)
				break;
			static if (!is(T.DataType == void))
				tmp.v!0 = pret.v;
			res ~= tmp;
			last_range = pret.cont;
		}

		return RT(last_range, move(res));
	}
}

///
unittest {
	import sdpc.parsers;
	import std.algorithm;

	alias calc = pipe!(chain!(number!(), token!"+"), wrap!((x) => x[].fold!"a+b.v!0"(0)));
	auto i = "1+2+3+4+5";
	auto r = calc(i);
	assert(r.ok);
	assert(r.v == 15);
}

/**
  Match `func*` or `func+`

  ReturnType.v is a InputRange of the results
*/
struct many_range(alias func, bool allow_none = false) {
@nogc:
	static auto opCall(R)(in auto ref R i)
	if (isForwardRange!R) {
		alias PR = typeof(func(i));
		static struct ManyResults {
			private R curr;
			private PR pr;
			bool empty;
			ulong length = 0;
			this(R i) {
				pr = func(i);
				empty = !pr.ok;
				if (pr.ok)
					curr = pr.cont;
			}
			static if (!is(PR.DataType == void)) {
				@property auto front() {
					return pr.v;
				}
				void popFront() {
					pr = func(curr);
					empty = !pr.ok;
					if (pr.ok)
						curr = pr.cont;
				}
			}
		}
		alias RT = Result!(R, ManyResults, PR.ErrType);
		auto res = ManyResults(i);

		auto last_range = i.save;
		while(true) {
			auto ret = func(last_range);
			if (!ret.ok) {
				if (allow_none || res.length)
					return RT(last_range, res);
				else
					return RT(ret.err);
			}
			res.length++;
			last_range = ret.cont;
		}
	}
}

/**
  Like `many_r` but with default `reduce` function that put all return
  values into an array, or return number of matches
*/
struct many(alias func, bool allow_none = false) {
	static auto opCall(R, alias Allocator = GCAllocator.instance)(in auto ref R i)
	if (isForwardRange!R) {
		import containers.dynamicarray : DynamicArray;
		import std.algorithm.mutation : move;
		alias PR = typeof(func(i));
		static if (is(PR.DataType == void))
			alias PDTA = void;
		else {
			alias PDTA = DynamicArray!(PR.DataType, typeof(Allocator));
			static if (stateSize!(typeof(Allocator))) {
				auto res = PDTA(Allocator);
			} else {
				PDTA res;
			}
		}
		bool none = true;
		alias RT = Result!(R, PDTA, PR.ErrType);

		auto last_range = i.save;
		while(true) {
			auto ret = func(last_range);
			if (!ret.ok) {
				if (allow_none || !none) {
					static if (!is(PDTA == void))
						return RT(last_range, move(res));
					else
						return RT(last_range);
				} else
						return RT(ret.err);
			}
			static if (!is(PDTA == void))
				res ~= ret.v;
			none = false;
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
	assert(!r2.cont.length);

	i = "abcde";
	auto r3 = abcdparser(i);
	assert(r3.ok); //Parse is OK because 4 char are consumed
	assert(r3.v.length == 4);
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

	ref auto v(uint id)() inout {
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
  the parsers, use `Result.v.v!index`, where `index` is the
  index of the desired parser in `T`.
*/
struct seq(T...) {
	enum notVoid(T) = !is(T == void);
	static auto opCall(R)(in auto ref R i)
	if (isForwardRange!R) {
		import std.algorithm : move;
		alias GetDT(A) = A.DataType;
		alias GetET(A) = A.ErrType;
		alias PRS = ParserReturnTypes!(R, T);
		alias PDT = staticMap!(GetDT, PRS);
		alias PET = Filter!(notVoid, staticMap!(GetET, PRS));
		static assert(allSameType!PET);

		alias RT = Result!(R, DTTuple!PDT, PET[0]);
		DTTuple!PDT res;
		auto last_range = i.save;
		foreach(id, p; T) {
			auto ret = p(last_range);
			if (!ret.ok) {
				static if (is(typeof(ret).ErrType == void))
					assert(0);
				else
					return RT(ret.err);
			}
			static if (!is(PRS[id].DataType == void))
				res.v!id = move(ret.v);
			last_range = ret.cont;
		}
		return RT(last_range, move(res));
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
	static auto opCall(R)(in auto ref R i)
	if (isForwardRange!R) {
		import std.typecons;
		auto r = p(i);
		alias PR = typeof(r);
		alias RT = Result!(R, Nullable!(PR.DataType), PR.ErrType);
		if (!r.ok)
			return RT(i, Nullable!(PR.DataType).init);
		else
			return RT(r.cont, nullable(r.v));
	}
}

///
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
	static auto opCall(R)(in auto ref R i)
	if (isForwardRange!R) {
		auto r = u(i);
		alias PR = typeof(r);
		alias RT = Result!(R, void, PR.ErrType);
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

struct span(alias p) {
	static auto opCall(R)(in auto ref R i)
	if (isForwardRange!R) {
		auto r = p(i);
		if (r.ok)
			r.span = Span(i, r.cont);
		return r;
	}
}

///
unittest {
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
alias skip(alias p) = discard_err!(discard!(many!(discard!p, true)));

///Match `p` but discard the result
alias discard(alias p) = pipe!(p, wrap!((_) { }));
alias discard_err(alias p) = pipe!(p, wrap_err!((_) { }));
