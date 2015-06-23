module sdpc.primitives;
import std.algorithm,
       std.stdio,
       std.typetuple,
       std.traits;
enum State {
	OK,
	Err
}

private template isVoid(T) {
	static if (is(T == void))
		enum bool isVoid = true;
	else
		enum bool isVoid = false;
}

template ElemType(T) {
	static if (is(T == ParseResult!U, U...)) {
		static if (U.length == 1)
			alias ElemType = U[0];
		else
			alias ElemType = U;
	} else
		static assert(false);
}

private template stripVoid(T...) {
	static if (T.length == 0)
		alias stripVoid = TypeTuple!();
	else static if (is(T[0] == void))
		alias stripVoid = stripVoid!(T[1..$]);
	else
		alias stripVoid = TypeTuple!(T[0], stripVoid!(T[1..$]));
}

template ElemTypes(T...) {
	alias ElemTypes = staticMap!(ElemType, T);
}

template ElemTypesNoVoid(T...) {
	alias ElemTypesNoVoid = stripVoid!(ElemTypes!T);
}

struct ParseResult(T...) {
	State s;
	size_t consumed;

	static if (T.length == 0 || allSatisfy!(isVoid, T))
		alias T2 = void;
	else static if (T.length == 1)
		alias T2 = T[0];
	else
		alias T2 = T;
	static if (!is(T2 == void)) {
		T2 t;
		static if (T.length == 1) {
			@property T2 result() {
				assert(s == State.OK);
				return t;
			}
			alias result this;
		} else {
			auto result(int id)() {
				assert(s == State.OK);
				return t[id];
			}
		}
	}

	@property nothrow pure @nogc ok() {
		return s == State.OK;
	}

	invariant {
		assert(s == State.OK || consumed == 0);
	}
}

T ok_result(T: ParseResult!U, U)(U r, size_t consumed) {
	return T(State.OK, consumed, r);
}

ParseResult!T ok_result(T)(T r, size_t consumed) {
	return ParseResult!T(State.OK, consumed, r);
}

T err_result(T: ParseResult!U, U)() {
	static if (is(U == void))
		return T(State.Err, 0);
	else
		return T(State.Err, 0, U.init);
}

ParseResult!T err_result(T)() if (!is(T == ParseResult!U, U)) {
	static if (is(T == void))
		return ParseResult!T(State.Err, 0);
	else
		return ParseResult!T(State.Err, 0, T.init);
}

ParseResult!T cast_result(T, alias func)(Stream i) if (is(ElemType!(ReturnType!func): T)) {
	auto r = func(i);
	if (!r.ok)
		return err_result!T();
	return ok_result(cast(T)r.result, r.consumed);
}

interface Stream {
	bool starts_with(const char[] prefix);
	string advance(size_t bytes);
	void rewind(size_t bytes);
	@property bool eof();
}

class BufStream: Stream {
	import std.stdio;
	private {
		immutable(char)[] buf;
		immutable(char)[] slice;
		size_t offset;
	}
	@property pure nothrow @nogc string head() {
		return slice;
	}
	override bool starts_with(const char[] prefix) {
		import std.stdio;
		if (prefix.length > slice.length)
			return false;
		return slice.startsWith(prefix);
	}
	override string advance(size_t bytes) {
		assert(bytes <= slice.length);
		auto ret = slice[0..bytes];
		slice = slice[bytes..$];
		offset += bytes;
		return ret;
	}
	override void rewind(size_t bytes) {
		import std.conv;
		assert(bytes <= offset, to!string(bytes) ~ "," ~ to!string(offset));
		offset -= bytes;
		slice = buf[offset..$];
	}
	@property override bool eof() {
		return slice.length == 0;
	}
	this(string str) {
		buf = str;
		slice = buf[];
		offset = 0;
	}

}

/*
class Stream {
	private File f;
	char[] buf;
	bool starts_with(const ref string prefix) {
		if (buf.len < prefix.len)
			refill(prefix.len-buf.len);
		if (buf.len < prefix.len)
			return false;
		return buf.startWith(prefix);
	}
	void refill(size_t bytes) {
		size_t pos = buf.len;
		buf.len += bytes;
		auto tmp = f.rawRead(buf[pos..$]);
		if (tmp.len != bytes)
			buf.len = pos+tmp.len;
	}
	void advance(size_t bytes) {
		assert(bytes <= buf.len);
		buf = buf[bytes..$];
	}
	this(File xf) {
		f = xf;
	}
}*/
