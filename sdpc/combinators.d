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
import std.typecons : Tuple;
import std.range : ElementType;

import std.experimental.allocator.gc_allocator : GCAllocator;

///Match pattern `begin func end`, return the result of func.
version(legacy) alias between(alias begin, alias func, alias end) = pipe!(seq!(discard!begin, func, discard!end), wrap!"move(a[1])");

///
version(legacy) unittest {
	import sdpc.parsers;
	auto i = "(asdf)";
	auto r = between!(token!"(", token!"asdf", token!")")(i);
	assert(r.ok);
	assert(!r.cont.length);
}

/// Generate a new parser that applies `m` to outputs of parser `p`
template pmap(alias p, alias m) {
auto pmap(R)(in auto ref R i)
if (isForwardRange!R) {
	alias P = typeof(p(i));
	static struct Pmap {
		private P inner;
		typeof(m(inner.front)) front;
		@property bool empty() { return inner.empty; }
		@property ref auto err() { return inner.err; }
		@property ref R cont() { return inner.cont; }
		void popFront() {
			inner.popFront;
			if (!inner.empty) {
				front = m(inner.front);
			}
		}
		this(R i) {
			inner = p(i);
			front = m(inner.front);
		}
	}
	return Pmap(i);
}}

// Produce a parser that exhaust parse `p` and folds over its outputs.
// if `allow_empty` is false, the result will be empty if `p` produce 0 output. Otherwise,
// the result will always have 1 element.
template pfold(alias p, alias func, alias seed, bool allow_empty = false){
auto pfold(R)(in auto ref R i)
if (isForwardRange!R) {
	alias InnerRT = ElementType!(typeof(p(i)));
	alias InnerET = typeof(p(i).err);
	alias RT = typeof(binaryFun!func(seed, InnerRT.init));
	static assert (is(typeof(seed) == RT), "return type of "~func~" should be the save as typeof(seed)");
	static struct Pfold {
		bool empty;
		R cont;
		RT front = seed;
		InnerET err;
		size_t length = 0;

		this(R i) {
			import std.algorithm : fold;
			auto inner = p(i);
			empty = inner.empty && !allow_empty;
			// Could've used (&inner).fold here, but it fails
			// to compile
			while (!inner.empty) {
				front = binaryFun!func(front, inner.front);
				inner.popFront;
			}
			length = 1;
			cont = inner.cont;
			err = inner.err;
		}
		void popFront() { empty = true; }
	}
	return Pfold(i);
}}

/// Match one of the given pattern. Remembers the matching parser.
/// Repeated invocation will keep invoking the parser matched the first time.
template choice(T...) {
auto choice(R)(in auto ref R i)
if (isForwardRange!R) {
	import std.range : iota;
	alias GetP(alias A) = typeof(A(i));
	alias InnerP = staticMap!(GetP, T);
	alias GetDT(A) = typeof(A.init.front);
	alias GetET(A) = typeof(A.init.err);
	alias PDT = staticMap!(GetDT, InnerP);
	alias PET = staticMap!(GetET, InnerP);
	static assert(allSameType!PDT);
	static assert(allSatisfy!(isParsingRange, InnerP));

	static struct Choice {
		private immutable int chosen;
		private InnerP inner;
		bool empty;
		PET err;
		R cont;

		this(R i) {
			cont = i;
			empty = true;
			foreach(id, p; T) {
				auto ret = p(cont);
				if (!ret.empty) {
					empty = false;
					cont = ret.cont;
					chosen = id;
					inner[id] = ret;
					return;
				}
				err[id] = ret.err;
			}
		}

		ref PDT[0] front() {
			final switch(chosen) {
			static foreach(i; 0..T.length) {
			case i: {
				return inner[i].front;
			}}}
		}
		void popFront() {
			o:final switch(chosen) {
			static foreach(i; 0..T.length) {
			case i: {
				inner[i].popFront;
				empty = inner[i].empty;
				cont = inner[i].cont;
				break o;
			}}}
		}

	}
	return Choice(i);
}}

/**
  First invocation matches `p`. Following invocations matches `delim p`
*/
template delimited(alias p, alias delim) {
auto delimited(R)(in auto ref R i)
if (isForwardRange!R) {
	import std.typecons : Nullable, tuple, nullable;
	alias T = ParserReturnTypes!(R, p);
	alias DT = ParserReturnTypes!(R, delim);
	alias TE = typeof(p(i).err);
	alias DTE = typeof(delim(i).err);
	alias RDT = Tuple!(T[0], Nullable!(DT[0]));
	static assert(is(TE == DTE));
	static struct Delimited {
		bool empty;
		RDT front;
		R cont;
		TE err;
		this(R i) {
			auto ret = p(i);
			empty = ret.empty;
			cont = ret.cont;
			if (!ret.empty) {
				front = tuple(ret.front, Nullable!(DT[0]).init);
			} else {
				err = ret.err;
			}
		}
		void popFront() {
			empty = true;
			auto ret1 = delim(cont);
			cont = ret1.cont;
			if (ret1.empty) {
				err = ret1.err;
				return;
			}
			auto ret2 = p(cont);
			cont = ret2.cont;
			if (ret2.empty) {
				err = ret2.err;
				return;
			}

			front = tuple(ret2.front, nullable(ret1.front));
			empty = false;
		}
	}
	return Delimited(i);
}}

///
unittest {
	import sdpc.parsers;
	import std.algorithm;

	alias calc = pfold!(delimited!(number!(), token!"+"), "a+b[0]", 0);
	auto i = "1+2+3+4+5";
	auto r = calc(i);
	assert(!r.empty);
	assert(r.front == 15);
	assert(r.cont.empty);
}

/**
  Like `many_r` but with default `reduce` function that put all return
  values into an array, or return number of matches
*/
version(legacy)
struct many(alias func, bool allow_none = false) {
	static auto opCall(R)(in auto ref R i)
	if (isForwardRange!R) {
		import containers.dynamicarray : DynamicArray;
		import std.algorithm.mutation : move;
		alias PR = typeof(func(i));
		static if (is(PR.DataType == void))
			alias PDTA = void;
		else {
			alias PDTA = DynamicArray!(PR.DataType, RCIAllocator*);
			auto res = PDTA(&theAllocator());
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
	import std.array : array;
	auto i = "aabcdaaddcc";
	alias abcdparser = choice!(token!"a", token!"b", token!"c", token!"d");
	auto r2 = abcdparser(i);
	assert(!r2.empty);
	assert(r2.array.length == 2); // only matches the first two 'a's

	/*
	i = "abcde";
	auto r3 = abcdparser(i);
	assert(r3.ok); //Parse is OK because 4 char are consumed
	assert(r3.v.length == 4);
	assert(r3.cont.length); //But the end-of-buffer is not reached
	*/
}

/**
  Appply a sequence of parsers one after another.

  Don't use tuple as data type in any of the parsers. The return
  data type is a special type of tuple. To get the data of each of
  the parsers, use `Result.v.v!index`, where `index` is the
  index of the desired parser in `T`.
*/
version(legacy)
struct seq(T...) {
	enum notVoid(T) = !is(T == void);
	private static string genParserCalls(int n) {
		import std.range : iota;
		import std.algorithm : map;
		string ret = "";
		foreach(i; 0..n) {
			ret ~= format("auto ret%s = T[%s](last_range);", i, i);
			ret ~= format("if(!ret%s.ok) return RT(ret%s.err);", i, i);
			ret ~= format("last_range = ret%s.cont;", i);
		}

		auto retstr = iota(n).map!(a => format("move(ret%s.v)", a)).join(",");
		ret ~= "return RT(last_range, Tuple!PDT("~retstr~"));";
		return ret;
	}
	static auto opCall(R)(in auto ref R i)
	if (isForwardRange!R) {
		import std.algorithm : move;
		alias GetDT(A) = A.DataType;
		alias GetET(A) = A.ErrType;
		alias PRS = ParserReturnTypes!(R, T);
		alias PDT = staticMap!(GetDT, PRS);
		alias PET = Filter!(notVoid, staticMap!(GetET, PRS));
		static assert(allSameType!PET);

		alias RT = Result!(R, Tuple!PDT, PET[0]);
		auto last_range = i.save;
		mixin(genParserCalls(T.length));
	}
}

///
version(legacy)
unittest {
	import sdpc.parsers;
	auto i = "abcde";
	auto r4 = seq!(token!"a", token!"b", token!"c", token!"d", token!"e")(i);
	assert(r4.ok);
	assert(r4.v[0] == "a");
	assert(r4.v[1] == "b");
	assert(r4.v[2] == "c");
	assert(r4.v[3] == "d");
	assert(r4.v[4] == "e");

	auto r5 = seq!(token!"a")(i); //seq with single argument.
	assert(r5.ok);
	assert(r5.v[0] == "a");
}

/** Optionally matches `p`

  Return data type will be a Nullable of `p`'s data type
*/
version(legacy)
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
version(legacy)
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
version(legacy)
struct lookahead(alias u, bool negative = false){
	static auto opCall(R)(in auto ref R i)
	if (isForwardRange!R) {
		auto r = u(i);
		alias PR = typeof(r);
		alias RT = Result!(R, Unit, PR.ErrType);
		static if (negative) {
			if (r.ok)
				return RT(RT.ErrType.init);
			else
				return RT(i);
		} else {
			if (r.ok)
				return RT(i, []);
			else
				return RT(r.err);
		}
	}
}

version(legacy)
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
version(legacy)
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
version(legacy)
alias skip(alias p) = discard_err!(discard!(many!(discard!p, true)));

///Match `p` but discard the result
version(legacy)
alias discard(alias p) = pipe!(p, wrap!((ref _) { }));
version(legacy)
alias discard_err(alias p) = pipe!(p, wrap_err!((ref _) { }));
