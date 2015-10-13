module sdpc.primitives;
import std.algorithm,
       std.stdio,
       std.typetuple,
       std.traits;
package enum Result {
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

struct Reason {
	Reason[] dep;
	string msg;
	string name;
	int line, col;
	string state;
	@disable this();
@safe :
	this(Stream i, string xname) {
		i.get_pos(line, col);
		state = "failed";
		name = xname;
		msg = null;
		dep = [];
	}
	private string str(ulong depth) {
		import std.string : format;
		import std.array : replicate;
		string pos = format("(%s, %s):", line, col);
		if (depth == 0)
			depth = pos.length;
		char[] prefix;
		if (depth >= pos.length)
			prefix.length = depth-pos.length;
		foreach(ref x; prefix)
			x = ' ';
		string res;
		if(dep.length != 0) {
			res = format("%s%sParsing of %s %s, because:\n", pos, prefix, name, state);
			foreach(ref d; dep)
				res ~= d.str(depth+1);
		} else {
			assert(msg !is null);
			res = format("%s%sParsing of %s %s, %s\n", pos, prefix, name, state, msg);
		}
		return res;
	}
	int opCmp(ref const Reason o) const {
		if (line < o.line)
			return -1;
		if (line > o.line)
			return 1;
		if (col < o.col)
			return -1;
		return 1;
	}
	void promote() {
		if (dep.length == 1)
			this = dep[0];
	}
	string explain() {
		return str(0);
	}
	bool empty() {
		return (dep is null || dep.length == 0) && (msg is null || msg == "");
	}
}

struct ParseResult(T...) {
	Result s;
	size_t consumed;
	Reason r;
@safe :
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
				assert(s == Result.OK);
				return t;
			}
			alias result this;
		} else {
			auto result(int id)() {
				assert(s == Result.OK);
				return t[id];
			}
		}
	}

	@property nothrow pure @nogc ok() {
		return s == Result.OK;
	}

	invariant {
		assert(s == Result.OK || consumed == 0);
	}
}
@safe {
	T ok_result(T: ParseResult!U, U)(U r, size_t consumed, ref Reason re) {
		return T(Result.OK, consumed, re, r);
	}

	ParseResult!T ok_result(T...)(T r, size_t consumed, ref Reason re) {
		return ParseResult!T(Result.OK, consumed, re, r);
	}

	T err_result(T: ParseResult!U, U)(ref Reason r) {
		static if (is(U == void))
			return T(Result.Err, 0, r);
		else
			return T(Result.Err, 0, r, U.init);
	}

	ParseResult!T err_result(T)(T def, ref Reason r)
	    if (!is(T == ParseResult!U, U)) {
		return ParseResult!T(Result.Err, 0, r, def);
	}

	ParseResult!T err_result(T...)(ref Reason r)
	    if (!is(T == ParseResult!U, U)) {
		static if (is(T[0] == void))
			return ParseResult!T(Result.Err, 0, r);
		else
			return ParseResult!T(Result.Err, 0, r, T.init);
	}

	ParseResult!T cast_result(T, alias func)(Stream i)
	    if (is(ElemType!(ReturnType!func): T)) {
		auto r = func(i);
		if (!r.ok)
			return err_result!T(r.r);
		return ok_result(cast(T)r.result, r.consumed, r.r);
	}

	///Cast single element to array
	ParseResult!T cast_result(T: U[], alias func, U)(Stream i)
	    if (is(ElemType!(ReturnType!func): U)) {
		auto r = func(i);
		if (!r.ok)
			return err_result!T(r.r);
		return ok_result([cast(U)r.result], r.consumed, r.r);
	}
}

interface Stream {
@safe :
	bool starts_with(const char[] prefix);
	string advance(size_t bytes);
	void push(string f=__FUNCTION__);
	void pop(string f=__FUNCTION__);
	void drop(string f=__FUNCTION__);
	void revert();
	void get_pos(out int line, out int col);
	@property bool eof();
	@property pure nothrow @nogc string head();
}

class BufStream: Stream {
	import std.stdio;
	struct Pos {
		string pos;
		int line, col;
	}
	private {
		Pos now;
		Pos[] stack;
	}
	@safe this(string str) {
		now.pos = str;
		now.line = now.col = 1;
	}
override :
	@property pure nothrow @nogc string head() {
		return now.pos;
	}
	bool starts_with(const char[] prefix) {
		import std.stdio;
		if (prefix.length > now.pos.length)
			return false;
		return now.pos.startsWith(prefix);
	}
	string advance(size_t bytes) {
		assert(bytes <= now.pos.length);
		auto ret = now.pos[0..bytes];
		foreach(c; ret) {
			now.col++;
			if (c == '\n') {
				now.col = 1;
				now.line++;
			}
		}
		now.pos = now.pos[bytes..$];
		return ret;
	}
	void push(string f=__FUNCTION__) {
		//writefln("Push %s, %s", f, stack.length);
		stack ~= [now];
	}
	void pop(string f=__FUNCTION__) {
		//writefln("Pop %s, %s", f, stack.length);
		now = stack[$-1];
		stack.length--;
	}
	void drop(string f=__FUNCTION__) {
		//writefln("Drop %s, %s", f, stack.length);
		stack.length--;
	}
	void revert() {
		now = stack[$-1];
	}
	void get_pos(out int line, out int col) {
		line = now.line;
		col = now.col;
	}
	bool eof() {
		return now.pos.length == 0;
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
