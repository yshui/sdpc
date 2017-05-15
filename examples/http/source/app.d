import sdpc;
import std.range, std.traits;
import std.stdio;
import std.functional : memoize;
import std.experimental.allocator.mallocator : Mallocator;
import std.experimental.allocator;

ParseResult!(R, ElementType!R, ParseError!R) t(R)(R i) if (isForwardRange!R) {
	alias RT = ParseResult!(R, ElementType!R, ParseError!R);
	if (i.empty)
		return RT(ParseError!R("eof", i));
	if (i.front > 127 || i.front < 32)
		return RT(ParseError!R("non ascii", i));
	return not_ch!"()<>@,:;\\\"/[]?={} "(i);
}

template tmemoize(alias t) {
	auto tmemoize(Args...)(Args args) {
		return memoize!(t!Args)(args);
	}
}

alias many_malloc(alias func) = many_alloc!(Mallocator.instance, func);

alias mt = tmemoize!t;

import std.algorithm : moveEmplace, move;
struct Request {
	dchar[] method;
	dchar[] uri;
	dchar[] ver;
	this(A, B, C)(ref A a, ref B b, ref C c) {
		method = a;
		uri = b;
		ver = c;
		a.storage = [];
		b.storage = [];
	}
	~this() nothrow {
		Mallocator.instance.dispose(method);
		Mallocator.instance.dispose(uri);
		//Mallocator.instance.dispose(ver);
	}
}

struct Header {
	dchar[] name;
	dchar[][] values;
	this(T, S)(ref S n, T[] v) {
		name = n;
		n.storage = [];
		values = new dchar[][v.length];
		foreach(i, ref x; v) {
			values[i] = x;
			x.storage = [];
		}
	}
	~this() nothrow {
		Mallocator.instance.dispose(name);
		foreach(ref x; values)
			Mallocator.instance.dispose(x);
	}
}

alias horiz_space = ch!" \t";
alias line_ending = transform_err!(choice!(token!"\r\n", token!"\n"), (x) => x[0]);
alias http_ver = transform!(seq!(token!"HTTP/", word!"0123456789."), (x) => x.v!1);
alias header_value = between!(many!(discard!horiz_space), many_malloc!(not_ch!"\r\n"), line_ending);

alias req_line = transform!(seq!(many_malloc!t, skip!whitespace,
                      many_malloc!(not_ch!" "), skip!whitespace,
                      http_ver,
                      line_ending), (ref x) => Request(x.v!0, x.v!2, x.v!4));// pragma(msg, typeof(x));});

alias header = transform!(seq!(many_malloc!t, token!":", many_malloc!header_value),
                          (ref x) => Header(x.v!0, x.v!2));

alias http = seq!(req_line, many_malloc!header, line_ending);

void main() {
	auto f = File("in.txt", "r");
	char[] buf = new char[f.size];
	f.rawRead(buf);

	enum runs = 1000;
	int sum = 0;
	foreach(i; 0..runs) {
	auto r = many_malloc!http(cast(const(char)[])(buf));
	auto v = move(r.v);
	pragma(msg, typeof(v.storage));
	//writeln(v.storage.length);
	sum+=v.length;
	}
	//foreach(v; r.v) {
		//writeln(v.v!0);
		//writeln(v.v!1);
	//}
	writeln(sum);
}
