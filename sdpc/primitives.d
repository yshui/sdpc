/++
  Common primitives used across this library

  Copyright: 2017 Yuxuan Shui
+/
module sdpc.primitives;
import std.algorithm,
       std.stdio,
       std.typetuple,
       std.traits,
       std.range;

/**
  Get the return types of a parser
  Params:
	R = range type
*/
template ParserReturnType(R) {
	alias ParserReturnType(alias T) = typeof(T(R.init));
}

/**
  Utility function for generate a tuple of `EnumeratePair` from an
  input tuple. Each `EnumeratePair` will have an index attached to it
*/
template staticEnumerate(T...) {
	struct EnumeratePair(uint xid, xT) {
		enum id = xid;
		alias T = xT;
		static if (!is(T == void)) {
			T value;
			alias value this;
		}
	}
	template E(uint start, T...) {
		static if (T.length == 0)
			alias E = AliasSeq!();
		else static if (T.length == 1)
			alias E = AliasSeq!(EnumeratePair!(start, T[0]));
		else {
			enum mid = start + T.length/2;
			alias E = AliasSeq!(E!(start, T[0 .. $/2]),
			                    E!(mid, T[$/2..$]));
		}
	}
	alias staticEnumerate = E!(0, T);
}

///
unittest {
	alias T = AliasSeq!(int, long, float);
	// (EnumeratePair!(0u, int), EnumeratePair!(1u, long), EnumeratePair!(2u, float))
	alias T2 = staticEnumerate!T;
	foreach(id, EP; T2) {
		static assert(id == EP.id);
		static assert(is(EP.T == T[id]));
	}
}

/**
  Parse result
  Params:
	R = Range type
	E = Error type, must be copyable, non reference type
	T = Data type, used for returning data from parser
 */
struct ParseResult(R, T = void, E = ulong)
if (isForwardRange!R && !is(E: R) && is(typeof(
    {immutable(E) foo = E.init; E copy = foo;}
))) {
@safe:
	/// Indicates whether the parser succeeded
	immutable(bool) ok;

	private union {
		R r_;

		E e_;
	}

	/// The data type, for convenience 
	alias DataType = T;

	alias ErrType = E;

	version(D_Ddoc) {
		/// Return the data, only available if T != void,
		/// fails if ok != true
		@property T v();

		/// ParseResult is covariant on its data type
		auto opCast(U: ParseResult!(R2, E2, T2), R2, E2, T2)() if (is(typeof(cast(T2)T.init)));

		/// Create a parse result (implies ok = true)
		this(R r, T d);

		/// Ditto
		this(R r);
	}

	static if (!is(T == void)) {
		private T data_;

		@property auto v() {
			assert(ok);
			return data_;
		}

		auto opCast(U: ParseResult!(R, T2, E), T2)() if (is(typeof(cast(T2)T.init))) {
			if (i.ok)
				return U(r.save, cast(T2)data_);
			return U(e);
		}

		@trusted static auto apply(alias func)(auto ref ParseResult!(R, T, E) i) if (is(typeof(func(i.data_)))){
			alias RT = typeof(func(i.data_));
			alias PR = ParseResult!(R, RT, E);
			if (i.ok) {
				static if (!is(RT == void))
					return PR(i.r_.save, func(i.data_));
				else
					return PR(i.r_.save);
			}
			return PR(i.e_);
		}

		@trusted this(R r, T d) {
			this.r_ = r;
			this.data_ = d;
			this.ok = true;
		}
	} else {
		@trusted this(R r) {
			this.r_ = r;
			this.ok = true;
		}
	}

	/// Get error information
	@property @trusted E err() in {
		assert(!ok);
	} body {
		return e_;
	}

	/// Transform `func` that takes a `E` into a function that takes a `ParseResult`
	@trusted static auto apply_err(alias func)(auto ref ParseResult!(R, T, E) i) if (is(typeof(func(i.e_)))){
		alias RT = typeof(func(i.e_));
		alias PR = ParseResult!(R, T, RT);
		if (i.ok)
			return PR(i.r_.save, i.data_);
		return PR(func(i.e_));
	}

	/// Create a parse result with error (implies ok = false)
	@trusted this(E e) {
		this.ok = false;
		this.e_ = e;
	}

	/// Get result range, where the following parsers should continue parsing
	@property @trusted R cont() in {
		assert(ok);
	} body {
		return r_.save();
	}

}

template isParser(T, E = char) {
	private {
		import std.range.interfaces;
		alias R = ForwardRange!E;
		R rng;
	}

	enum isParser = is(T == struct) && is(typeof(T(rng))) &&
	                is(typeof(T(rng)) == ParseResult!(S, Err, D), S, Err, D);
}

/**
  Apply `func` to the data returned by the `Parser`

  This transform `Parser` from a parser returning data type `T` to
  a parser returning data type `typeof(func(T))`
*/
struct transform(Parser, alias func) {
	static auto opCall(R)(R r) {
		alias PR = typeof(Parser(r));
		return PR.apply!func(Parser(r));
	}
}

/**
  Apply `func` to the error returned by the `Parser`

  Similar to `transform`, but operates on error instead of data
*/
struct transform_err(Parser, alias func) {
	static auto opCall(R)(R r) {
		alias PR = typeof(Parser(r));
		return PR.apply_err!func(Parser(r));
	}
}

///
unittest {
	struct A {
		int a;
	}
	struct B {
		int b;
	}
	struct test01 {
		static auto opCall(R)(R t) if (isForwardRange!R) {
			return ParseResult!(R, A)(t, A(1));
		}
	}

	alias test02 = transform!(test01, x => B(x.a+1));
	auto res = test02("asdf");
	static assert(isParser!test01);
	static assert(isParser!test02);
	static assert(is(typeof(res).DataType == B));
}
