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

/// The unit type
alias Unit = byte[0];

/// Convert void to Unit
template unitizeType(T) {
	static if (is(T == void))
		alias Unitize = Unit;
	else
		alias Unitize = T;
}

/// Convert a function that returns void, to function that returns Unit
template unitizeFunc(func...) if (func.length == 1) {
	pragma(inline) auto unitizeFunc(Args...)(Args args) if (is(typeof(func[0](args)))) {
		static if (is(typeof(func[0](args)) == void)) {
			func[0](args);
			return Unit.init;
		} else {
			return func[0](args);
		}
	}
}

unittest {
	void testfn() {}

	pragma(msg, typeof(unitizeFunc!testfn()));
	static assert(!is(typeof(unitizeFunc!testfn()) == void));
}
/**
  Get the return types of a parser
  Params:
	R = range type
*/
template ParserReturnTypes(R, T...) {
	static if (T.length == 1)
		alias ParserReturnTypes = AliasSeq!(ElementType!(typeof(T[0](R.init))));
	else
		alias ParserReturnTypes = AliasSeq!(ParserReturnTypes!(R, T[0..$/2]), ParserReturnTypes!(R,  T[$/2..$]));
}

// relax requirement of forward range
enum bool isForwardRange(R) = isInputRange!R
    && is(Unqual!(ReturnType!((R r) => r.save)) == Unqual!R);

/// Whether a range is a parsing range. In addition to an input range,
/// a parsing range also has a memeber `err` representing parsing errors,
/// and a member `cont` representing its position in the input.
enum bool isParsingRange(R) = isInputRange!R
    && is(typeof(R.init.err)) && isInputRange!(typeof(R.init.cont));

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

interface ICache(R) if (isForwardRange!R) {
}

import std.experimental.allocator.gc_allocator : GCAllocator;
class Cache(R, Allocator=GCAllocator) : ICache!R {

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
version(legacy)
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
