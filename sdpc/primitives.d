/++
  Common primitives used across this library

  Copyright: 2017 Yuxuan Shui
+/
module sdpc.primitives;
import std.algorithm,
       std.stdio,
       std.typetuple,
       std.traits,
       std.functional,
       std.variant;
import std.range : isInputRange, ElementType;

/**
  Get the return types of a parser
  Params:
	R = range type
*/
template ParserReturnTypes(R, T...) {
	static if (T.length == 1)
		alias ParserReturnTypes = AliasSeq!(typeof(T[0](R.init)));
	else
		alias ParserReturnTypes = AliasSeq!(ParserReturnTypes!(R, T[0..$/2]), ParserReturnTypes!(R,  T[$/2..$]));
}

// relax requirement of forward range
enum bool isForwardRange(R) = isInputRange!R
    && is(Unqual!(ReturnType!((R r) => r.save)) == Unqual!R);

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
			//alias value this;
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

struct Span {
	int begin_row, begin_col;
	int end_row, end_col;
	@safe this(R)(in auto ref R start, in auto ref R end) {
		static if (hasPosition!R) {
			assert(end.row >= start.row);
			assert(start.col <= end.col || start.row < end.row);
			begin_col = start.col;
			begin_row = start.row;
			end_row = end.row;
			end_col = end.col;
		}
	}
}

/**
  Parse result
  Params:
	R = Range type
	E = Error type, must be copyable, non reference type,
	    or void, which means the parser can never fail
	T = Data type, used for returning data from parser
 */
struct Result(R, T = void, E = ulong)
if (isForwardRange!R) {
//&& !is(E: R) && is(typeof(
//    {immutable(E) foo = E.init; E copy = foo;}
//))) {
	/// Indicates whether the parser succeeded
	bool ok = false;

	static if (!is(E == void)) {
		private R _r;
		private E _e;
	} else
		private R _r;

	/// The data type, for convenience 
	alias DataType = T;

	alias ErrType = E;

	alias RangeType = R;

	Span span;
	version(D_Ddoc) {
		/// Return the data, only available if T != void,
		/// fails if ok != true
		@property T v();

		/// Result is covariant on its data type
		auto opCast(U: Result!(R2, E2, T2), R2, E2, T2)() if (is(typeof(cast(T2)T.init)));

		/// Create a parse result (implies ok = true)
		this(R r, T d);

		/// Ditto
		this(R r);
	}

	static if (!is(T == void)) {
		private T data_;

		@property ref auto v() in {
			assert(ok);
		} body {
			return data_;
		}

		auto opCast(U: Result!(R, T2, E), T2)() if (is(typeof(cast(T2)T.init))) {
			if (i.ok)
				return U(r.save, cast(T2)data_);
			return U(_e);
		}

		this(R r, T d) {
			this._r = r;
			this.data_ = d;
			this.ok = true;
		}
	} else {
		this(R r) {
			this._r = r;
			this.ok = true;
		}
	}

	static if (!is(E == void)) {
		/// Get error information
		@property E err() in {
			assert(!ok);
		} body {
			return _e;
		}

		/// Create a parse result with error (implies ok = false)
		this(E e) {
			this.ok = false;
			this._e = e;
		}
	}

	/// Get result range, where the following parsers should continue parsing
	@property R cont() in {
		assert(ok);
	} body {
		return _r.save;
	}
}

interface ICache(R) if (isForwardRange!R) {
}

import std.experimental.allocator.gc_allocator : GCAllocator;
class Cache(R, Allocator=GCAllocator) : ICache!R {

}

/**
  Take a function `func` that takes type T, and return a function that
  takes Result!(_, T, _). The returned function will apply `func` on the
  data part of Result.
*/
template wrap(alias func) {
	alias ufun = unaryFun!func;
	alias bfun = binaryFun!func;
	auto wrap(R, T, E)(auto ref Result!(R, T, E) r)
	if (is(T == void)) {
		return r;
	}
	auto wrap(R, T, E)(auto ref Result!(R, T, E) r)
	if (!is(T == void)) {
		// See if we can call bfun
		static if (is(typeof(bfun(r.v, r.span)))) {
			alias RT = typeof(bfun(r.v, r.span));
			enum isBinary = true;
		} else {
			alias RT = typeof(ufun(r.v));
			enum isBinary = false;
		}
		alias PR = Result!(R, RT, E);
		if (r.ok) {
			static if (!is(RT == void)) {
				static if (isBinary)
					return PR(r.cont.save, bfun(r.v, r.span));
				else
					return PR(r.cont.save, ufun(r.v));
			} else
				return PR(r.cont.save);
		}
		static if (is(E == void))
			assert(0);
		else
			return PR(r.err);
	}
}

/**
  Take a function `func` that takes type E, and return a function that
  takes Result!(_, _, E). The returned function will apply `func` on the
  error part of Result.
*/
template wrap_err(alias func) {
	alias ufun = unaryFun!func;
	auto wrap_err(R, T, E)(auto ref Result!(R, T, E) r)
	if (is(E == void)) {
		assert(r.ok);
		return r;
	}
	auto wrap_err(R, T, E)(auto ref Result!(R, T, E) r)
	if (is(typeof(ufun(E.init)))) {
		alias RT = typeof(ufun(r.err));
		alias PR = Result!(R, T, RT);
		if (r.ok) {
			static if (is(T == void))
				return PR(r.cont);
			else
				return PR(r.cont, r.v);
		}
		static if (is(RT == void))
			assert(0);
		else
			return PR(ufun(r.err));
	}
}

/// Keep track of line and column
struct PositionRange(R) {
pure:
	import std.range : ElementType;
	R r;
	int row = 1, col = 1;
	bool empty() const { return r.empty; }
	auto front() const { return r.front; }
	void popFront() {
		import std.ascii;
		if (front == '\n') {
			row++;
			col = 1;
		} else
			col++;
		r.popFront;
	}
	auto save() const {
		return PositionRange(r.save, row, col);
	}
}

struct PositionRangeNonWhite(R) if (isSomeChar!(ElementType!R)) {
	import std.range : ElementType;
	R r;
	int row = 1, col = 1;
	private int real_row = 1, real_col = 1;
	bool empty() const { return r.empty; }
	auto front() const { return r.front; }
	void popFront() {
		import std.ascii;
		if (front == '\n') {
			real_row++;
			real_col = 1;
		} else
			real_col++;
		r.popFront;
		if (!empty && !front.isWhite) {
			row = real_row;
			col = real_col;
		}
	}
	auto save() const {
		auto ret = PositionRangeNonWhite(r.save, row, col, real_row, real_col);
		return ret;
	}
}

template hasPosition(R) {
	enum hasPosition = is(typeof(R.init.col)) && is(typeof(R.init.row));
}

auto with_position(R)(R i) {
	return PositionRange!R(i);
}

inout(R)[] save(R)(inout(R[]) i) {
	return i;
}

public import std.range.primitives : popFront, front, empty;

///
unittest {
	PositionRange!string a;
	import std.functional;
	struct A {
		int a;
	}
	struct B {
		int b;
	}
	struct test01 {
		static auto opCall(R)(R t) if (isForwardRange!R) {
			return Result!(R, A)(t, A(1));
		}
	}

	alias test02 = pipe!(test01, wrap!(x => B(x.a+1)));
	auto res = test02("asdf");
	static assert(is(typeof(res).DataType == B));
}
