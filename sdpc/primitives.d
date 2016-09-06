/++
  Common primitives used across this library

  Copyright: (C) 2017 Yuxuan Shui
  Author: Yuxuan Shui
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
	alias ParserReturnType(T) = typeof(T(R.init));
}

template Enumerate(T...) {
	struct EnumeratePair(uint xid, xT) {
		enum id = xid;
		alias T = xT;
		T value;
		alias value this;
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
	alias Enumerate = E!(0, T);
}

/**
  Parse result
  Params:
	R = Range type
	E = Error type, must be copyable, non reference type
	T = Data type, used for returning data from parser
 */
struct ParseResult(R, T = void, E = ulong)
if (isForwardRange!R && !is(R == E) && is(typeof(
    {immutable(E) foo = E.init; E copy = foo;}
))) {
	/// Indicates whether the parser succeeded
	immutable(bool) ok;

	/// Result range, where the following parsers should continue parsing
	R r;

	/// Error information
	immutable(E) e;

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

		static auto apply(alias func)(auto ref ParseResult!(R, T, E) i) if (is(typeof(func(i.data_)))){
			alias RT = typeof(func(i.data_));
			alias PR = ParseResult!(R, RT, E);
			if (i.ok)
				return PR(i.r.save, func(i.data_));
			return PR(i.e);
		}

		this(R r, T d) {
			this.r = r;
			this.data_ = d;
			this.ok = true;
		}
	} else {
		this(R r) {
			this.r = r;
			this.ok = true;
		}
	}

	/// Create a parse result with error (implies ok = false)
	this(E e) {
		this.ok = false;
		this.r = R.init;
		this.e = e;
	}

	/// Create a copy of the resulting range
	R cont() {
		return r.save();
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

struct transform(Parser, alias func) {
	static auto opCall(R)(R r) {
		alias PR = typeof(Parser(r));
		return PR.apply!func(Parser(r));
	}
}
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
